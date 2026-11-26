import Row, num, text, col_int, col_opt, col_text from "../Docs/Store.q"
import Package, PackageVersion from "./Models.q"

fun keywords_of(raw: string) -> array<string>
    let parsed = Json.parse(raw)
    if parsed.is_err() then
        return []
    end
    let list = Json.to<array<string>>(parsed.unwrap())
    if list.is_ok() then list.unwrap() else [] end
end

fun package_of(row: Row) -> Package
    Package {
        id: col_int(row, "id"), name: col_text(row, "name"), git_url: col_text(row, "git_url"), description: col_text(row, "description"),
        license: col_text(row, "license"), keywords: keywords_of(col_text(row, "keywords")), readme_html: col_text(row, "readme_html"),
        status: col_text(row, "status"), removed_reason: col_text(row, "removed_reason"), latest_version: col_text(row, "latest_version"),
        sync_requested: row.get("sync_requested", Json.null()).as_bool(), sync_error: col_text(row, "sync_error"),
        synced_at: col_opt(row, "synced_at") ?? 0, created_at: col_int(row, "created_at"),
    }
end

fun version_of(row: Row) -> PackageVersion
    PackageVersion {
        id: col_int(row, "id"), version: col_text(row, "version"), commit_sha: col_text(row, "commit_sha"),
        yanked: row.get("yanked", Json.null()).as_bool(), qlang_req: col_text(row, "qlang_req"), first_seen: col_int(row, "first_seen"),
    }
end

--" Every query of the registry. As for the documentation, a database that fails stops the request. --"
struct PackageStore
    public db: Db
end

impl PackageStore
    public fun new(db: Db) -> PackageStore
        PackageStore { db: db }
    end

    fun rows(self, sql: string, params: array<Json>) -> array<Row>
        let r = self.db.query(sql, params)
        if r.is_err() then
            panic("database: {r.unwrap_err().message} ({sql})")
        end
        r.unwrap()
    end

    fun exec(self, sql: string, params: array<Json>) -> int
        let r = self.db.execute(sql, params)
        if r.is_err() then
            panic("database: {r.unwrap_err().message} ({sql})")
        end
        r.unwrap()
    end

    --" The packages with a status (empty: all), matching the words in their name, description or keywords, and a keyword. --"
    public fun packages(self, status: string, words: string, keyword: string) -> array<Package>
        let where: array<string> = []
        let params: array<Json> = []
        if status != "" then
            where.push("status = ?")
            params.push(text(status))
        end
        if words != "" then
            let pattern = "%" + words.lower().replace("%", "").replace("_", "") + "%"
            where.push("(LOWER(name) LIKE ? OR LOWER(description) LIKE ? OR LOWER(keywords) LIKE ?)")
            params.push(text(pattern))
            params.push(text(pattern))
            params.push(text(pattern))
        end
        if keyword != "" then
            where.push("LOWER(keywords) LIKE ?")
            params.push(text("%\"" + keyword.lower().replace("%", "").replace("_", "") + "\"%"))
        end
        let clause = if where.is_empty() then "" else "WHERE " + where.join(" AND ") end
        self.rows("SELECT * FROM packages {clause} ORDER BY name", params).map(fun(row: Row) -> Package package_of(row) end)
    end

    public fun package(self, id: int) -> Package?
        let r = self.rows("SELECT * FROM packages WHERE id = ?", [num(id)])
        if r.is_empty() then none else package_of(r[0]) end
    end

    public fun package_by_name(self, name: string) -> Package?
        let r = self.rows("SELECT * FROM packages WHERE name = ?", [text(name)])
        if r.is_empty() then none else package_of(r[0]) end
    end

    public fun package_by_git(self, url: string) -> Package?
        let r = self.rows("SELECT * FROM packages WHERE LOWER(git_url) = ?", [text(url.lower())])
        if r.is_empty() then none else package_of(r[0]) end
    end

    public fun create_package(self, name: string, git_url: string, status: string) -> int
        let r = self.rows("INSERT INTO packages (name, git_url, status, sync_requested, created_at) VALUES (?, ?, ?, ?, ?) RETURNING id", [text(name), text(git_url), text(status), Json.of(status == "listed"), num(time.now())])
        col_int(r[0], "id")
    end

    public fun set_name(self, id: int, name: string)
        self.exec("UPDATE packages SET name = ? WHERE id = ?", [text(name), num(id)])
    end

    public fun set_status(self, id: int, status: string, reason: string)
        self.exec("UPDATE packages SET status = ?, removed_reason = ? WHERE id = ?", [text(status), text(reason), num(id)])
    end

    public fun set_sync_requested(self, id: int, on: bool)
        self.exec("UPDATE packages SET sync_requested = ? WHERE id = ?", [Json.of(on), num(id)])
    end

    public fun set_sync_error(self, id: int, message: string)
        self.exec("UPDATE packages SET sync_error = ?, sync_requested = ? WHERE id = ?", [text(message), Json.of(false), num(id)])
    end

    public fun set_synced(self, id: int, description: string, license: string, keywords: array<string>, readme_html: string, latest: string)
        self.exec("UPDATE packages SET description = ?, license = ?, keywords = ?, readme_html = ?, latest_version = ?, synced_at = ?, sync_error = '', sync_requested = ? WHERE id = ?", [text(description), text(license), text(Json.of(keywords).to_text()), text(readme_html), text(latest), num(time.now()), Json.of(false), num(id)])
    end

    public fun delete_package(self, id: int)
        self.exec("DELETE FROM package_versions WHERE package_id = ?", [num(id)])
        self.exec("DELETE FROM packages WHERE id = ?", [num(id)])
    end

    public fun versions(self, package_id: int) -> array<PackageVersion>
        self.rows("SELECT * FROM package_versions WHERE package_id = ?", [num(package_id)]).map(fun(row: Row) -> PackageVersion version_of(row) end)
    end

    --" Records a tag: new ones are added, a known one gets its commit and requirement refreshed. Gives true when it was new. --"
    public fun upsert_version(self, package_id: int, version: string, sha: string, qlang_req: string) -> bool
        let known = self.rows("SELECT id FROM package_versions WHERE package_id = ? AND version = ?", [num(package_id), text(version)])
        if known.is_empty() then
            self.exec("INSERT INTO package_versions (package_id, version, commit_sha, yanked, qlang_req, first_seen) VALUES (?, ?, ?, ?, ?, ?)", [num(package_id), text(version), text(sha), Json.of(false), text(qlang_req), num(time.now())])
            return true
        end
        self.exec("UPDATE package_versions SET commit_sha = ? WHERE package_id = ? AND version = ?", [text(sha), num(package_id), text(version)])
        false
    end

    public fun set_version_requirement(self, package_id: int, version: string, qlang_req: string)
        self.exec("UPDATE package_versions SET qlang_req = ? WHERE package_id = ? AND version = ?", [text(qlang_req), num(package_id), text(version)])
    end

    public fun set_yanked(self, package_id: int, version: string, yanked: bool)
        self.exec("UPDATE package_versions SET yanked = ? WHERE package_id = ? AND version = ?", [Json.of(yanked), num(package_id), text(version)])
    end

    --" Listed packages that asked for a sync, or that were synced before `cutoff` (milliseconds), oldest first. --"
    public fun due_for_sync(self, cutoff: int, limit: int) -> array<Package>
        self.rows("SELECT * FROM packages WHERE status = 'listed' AND (sync_requested = ? OR COALESCE(synced_at, 0) < ?) ORDER BY COALESCE(synced_at, 0) LIMIT ?", [Json.of(true), num(cutoff), num(limit)]).map(fun(row: Row) -> Package package_of(row) end)
    end

    public fun count(self, status: string) -> int
        col_int(self.rows("SELECT COUNT(*) AS n FROM packages WHERE status = ?", [text(status)])[0], "n")
    end
end

export PackageStore
