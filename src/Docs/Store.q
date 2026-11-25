import Account, Folder, Page, PageRow, Revision, Release, SnapFolder, SnapPage, AuditEntry, AuditFilter from "./Models.q"

type Row = map<string, Json>

fun num(v: int) -> Json
    Json.number(v as float)
end

fun text(v: string) -> Json
    Json.string(v)
end

fun opt(v: int?) -> Json
    if v == none then Json.null() else Json.number(v as float) end
end

fun col_int(row: Row, name: string) -> int
    row.get(name, Json.null()).as_number() as int
end

fun col_opt(row: Row, name: string) -> int?
    let v = row.get(name, Json.null())
    if v.is_null() then none else v.as_number() as int end
end

fun col_text(row: Row, name: string) -> string
    let v = row.get(name, Json.null())
    if v.is_null() then "" else v.as_string() end
end

fun account_of(row: Row) -> Account
    Account { id: col_int(row, "id"), login: col_text(row, "login"), role: col_text(row, "role"), password_hash: col_text(row, "password_hash") }
end

fun folder_of(row: Row) -> Folder
    Folder { id: col_int(row, "id"), parent_id: col_opt(row, "parent_id"), locale: col_text(row, "locale"), slug: col_text(row, "slug"), title: col_text(row, "title"), position: col_int(row, "position"), section: col_text(row, "section") }
end

fun page_of(row: Row) -> Page
    Page {
        id: col_int(row, "id"), folder_id: col_opt(row, "folder_id"), locale: col_text(row, "locale"), slug: col_text(row, "slug"),
        title: col_text(row, "title"), markdown: col_text(row, "markdown"), html: col_text(row, "html"), toc: col_text(row, "toc"),
        position: col_int(row, "position"), revision: col_int(row, "revision"), updated_at: col_int(row, "updated_at"), updated_by: col_opt(row, "updated_by"),
    }
end

fun revision_of(row: Row) -> Revision
    Revision {
        id: col_int(row, "id"), page_id: col_int(row, "page_id"), number: col_int(row, "number"), title: col_text(row, "title"),
        markdown: col_text(row, "markdown"), source: col_text(row, "source"), summary: col_text(row, "summary"),
        author: col_text(row, "author"), created_at: col_int(row, "created_at"),
    }
end

fun release_of(row: Row, current: int?) -> Release
    let id = col_int(row, "id")
    Release {
        id: id, label: col_text(row, "label"), qlang_version: col_text(row, "qlang_version"), note: col_text(row, "note"),
        author: col_text(row, "author"), created_at: col_int(row, "created_at"), pages: col_int(row, "pages"), current: current == id,
    }
end

--" Every query of the documentation goes through here. A database that fails is not something a page can fix:
the error stops the request (a `500`), and the log says what it was. --"
struct Store
    public db: Db
end

impl Store
    public fun new(db: Db) -> Store
        Store { db: db }
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

    fun now(self) -> int
        time.now()
    end

    --" Several writes that stand or fall together. --"
    public fun atomic<T>(self, work: fun() -> T) -> T
        self.db.begin()
        let out = work()
        self.db.commit()
        out
    end

    -- Accounts

    public fun count_accounts(self) -> int
        col_int(self.rows("SELECT COUNT(*) AS n FROM users", [])[0], "n")
    end

    public fun create_account(self, login: string, hash: string, role: string) -> int
        let r = self.rows("INSERT INTO users (login, password_hash, role, created_at) VALUES (?, ?, ?, ?) RETURNING id", [text(login), text(hash), text(role), num(self.now())])
        col_int(r[0], "id")
    end

    public fun account_by_login(self, login: string) -> Account?
        let r = self.rows("SELECT * FROM users WHERE login = ?", [text(login)])
        if r.is_empty() then none else account_of(r[0]) end
    end

    public fun account(self, id: int) -> Account?
        let r = self.rows("SELECT * FROM users WHERE id = ?", [num(id)])
        if r.is_empty() then none else account_of(r[0]) end
    end

    public fun accounts(self) -> array<Account>
        self.rows("SELECT * FROM users ORDER BY login", []).map(fun(row: Row) -> Account account_of(row) end)
    end

    public fun update_password(self, id: int, hash: string)
        self.exec("UPDATE users SET password_hash = ? WHERE id = ?", [text(hash), num(id)])
    end

    public fun delete_account(self, id: int)
        self.exec("UPDATE pages SET updated_by = NULL WHERE updated_by = ?", [num(id)])
        self.exec("UPDATE page_revisions SET author_id = NULL WHERE author_id = ?", [num(id)])
        self.exec("UPDATE releases SET created_by = NULL WHERE created_by = ?", [num(id)])
        self.exec("UPDATE audit_logs SET user_id = NULL WHERE user_id = ?", [num(id)])
        self.exec("DELETE FROM users WHERE id = ?", [num(id)])
    end

    -- Folders

    public fun folders(self, locale: string) -> array<Folder>
        self.rows("SELECT * FROM folders WHERE locale = ? ORDER BY position, id", [text(locale)]).map(fun(row: Row) -> Folder folder_of(row) end)
    end

    public fun folder(self, id: int) -> Folder?
        let r = self.rows("SELECT * FROM folders WHERE id = ?", [num(id)])
        if r.is_empty() then none else folder_of(r[0]) end
    end

    public fun find_folder(self, locale: string, parent_id: int?, slug: string) -> Folder?
        let r = self.rows("SELECT * FROM folders WHERE locale = ? AND COALESCE(parent_id, 0) = ? AND slug = ?", [text(locale), num(parent_id ?? 0), text(slug)])
        if r.is_empty() then none else folder_of(r[0]) end
    end

    fun next_position(self, table: string, locale: string, parent: int?) -> int
        let column = if table == "folders" then "parent_id" else "folder_id" end
        let r = self.rows("SELECT COALESCE(MAX(position), 0) + 1 AS n FROM {table} WHERE locale = ? AND COALESCE({column}, 0) = ?", [text(locale), num(parent ?? 0)])
        col_int(r[0], "n")
    end

    public fun create_folder(self, locale: string, parent_id: int?, slug: string, title: string) -> int
        let position = self.next_position("folders", locale, parent_id)
        let r = self.rows("INSERT INTO folders (locale, parent_id, slug, title, position, created_at) VALUES (?, ?, ?, ?, ?, ?) RETURNING id", [text(locale), opt(parent_id), text(slug), text(title), num(position), num(self.now())])
        col_int(r[0], "id")
    end

    public fun update_folder(self, id: int, slug: string, title: string)
        self.exec("UPDATE folders SET slug = ?, title = ? WHERE id = ?", [text(slug), text(title), num(id)])
    end

    public fun set_folder_section(self, id: int, section: string)
        self.exec("UPDATE folders SET section = ? WHERE id = ?", [text(section), num(id)])
    end

    public fun move_folder(self, id: int, parent_id: int?)
        let f = self.folder(id).unwrap()
        let position = self.next_position("folders", f.locale, parent_id)
        self.exec("UPDATE folders SET parent_id = ?, position = ? WHERE id = ?", [opt(parent_id), num(position), num(id)])
    end

    public fun delete_folder(self, id: int)
        self.exec("DELETE FROM folders WHERE id = ?", [num(id)])
    end

    public fun folder_is_empty(self, id: int) -> bool
        let a = col_int(self.rows("SELECT COUNT(*) AS n FROM folders WHERE parent_id = ?", [num(id)])[0], "n")
        let b = col_int(self.rows("SELECT COUNT(*) AS n FROM pages WHERE folder_id = ?", [num(id)])[0], "n")
        a == 0 and b == 0
    end

    --" Sets the order of siblings: `ids` in the order they should have. --"
    public fun order(self, table: string, ids: array<int>)
        let k = 1
        for id in ids do
            self.exec("UPDATE {table} SET position = ? WHERE id = ?", [num(k), num(id)])
            k = k + 1
        end
    end

    -- Pages

    public fun page_rows(self, locale: string) -> array<PageRow>
        let out: array<PageRow> = []
        for row in self.rows("SELECT id, folder_id, locale, slug, title, position, revision, updated_at FROM pages WHERE locale = ? ORDER BY position, id", [text(locale)]) do
            out.push(PageRow {
                id: col_int(row, "id"), folder_id: col_opt(row, "folder_id"), locale: col_text(row, "locale"), slug: col_text(row, "slug"),
                title: col_text(row, "title"), position: col_int(row, "position"), revision: col_int(row, "revision"), updated_at: col_int(row, "updated_at"),
            })
        end
        out
    end

    public fun pages(self, locale: string) -> array<Page>
        let out: array<Page> = []
        for row in self.rows("SELECT * FROM pages WHERE locale = ? ORDER BY position, id", [text(locale)]) do
            out.push(page_of(row))
        end
        out
    end

    public fun page(self, id: int) -> Page?
        let r = self.rows("SELECT * FROM pages WHERE id = ?", [num(id)])
        if r.is_empty() then none else page_of(r[0]) end
    end

    public fun find_page(self, locale: string, folder_id: int?, slug: string) -> Page?
        let r = self.rows("SELECT * FROM pages WHERE locale = ? AND COALESCE(folder_id, 0) = ? AND slug = ?", [text(locale), num(folder_id ?? 0), text(slug)])
        if r.is_empty() then none else page_of(r[0]) end
    end

    fun add_revision(self, page_id: int, number: int, title: string, markdown: string, source: string, summary: string, author: int?)
        self.exec("INSERT INTO page_revisions (page_id, number, title, markdown, source, summary, author_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [num(page_id), num(number), text(title), text(markdown), text(source), text(summary), opt(author), num(self.now())])
    end

    --" Creates a page and its first revision. --"
    public fun create_page(self, locale: string, folder_id: int?, slug: string, title: string, markdown: string, html: string, toc: string, source: string, summary: string, author: int?) -> int
        let position = self.next_position("pages", locale, folder_id)
        let now = self.now()
        let r = self.rows("INSERT INTO pages (locale, folder_id, slug, title, markdown, html, toc, position, revision, created_at, updated_at, updated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?) RETURNING id", [text(locale), opt(folder_id), text(slug), text(title), text(markdown), text(html), text(toc), num(position), num(now), num(now), opt(author)])
        let id = col_int(r[0], "id")
        self.add_revision(id, 1, title, markdown, source, summary, author)
        id
    end

    --" Saves a new text for a page as a new revision. Nothing is written when nothing changed: the answer is then the current revision. --"
    public fun save_page(self, id: int, title: string, markdown: string, html: string, toc: string, source: string, summary: string, author: int?) -> int
        let page = self.page(id).unwrap()
        if page.title == title and page.markdown == markdown then
            return page.revision
        end
        let number = page.revision + 1
        self.exec("UPDATE pages SET title = ?, markdown = ?, html = ?, toc = ?, revision = ?, updated_at = ?, updated_by = ? WHERE id = ?", [text(title), text(markdown), text(html), text(toc), num(number), num(self.now()), opt(author), num(id)])
        self.add_revision(id, number, title, markdown, source, summary, author)
        number
    end

    public fun set_page_slug(self, id: int, slug: string)
        self.exec("UPDATE pages SET slug = ? WHERE id = ?", [text(slug), num(id)])
    end

    public fun move_page(self, id: int, folder_id: int?)
        let p = self.page(id).unwrap()
        let position = self.next_position("pages", p.locale, folder_id)
        self.exec("UPDATE pages SET folder_id = ?, position = ? WHERE id = ?", [opt(folder_id), num(position), num(id)])
    end

    public fun delete_page(self, id: int)
        self.exec("DELETE FROM pages WHERE id = ?", [num(id)])
    end

    -- Revisions

    public fun revisions(self, page_id: int) -> array<Revision>
        let out: array<Revision> = []
        for row in self.rows("SELECT r.*, COALESCE(u.login, '') AS author FROM page_revisions r LEFT JOIN users u ON u.id = r.author_id WHERE r.page_id = ? ORDER BY r.number DESC", [num(page_id)]) do
            out.push(revision_of(row))
        end
        out
    end

    public fun revision(self, page_id: int, number: int) -> Revision?
        let r = self.rows("SELECT r.*, COALESCE(u.login, '') AS author FROM page_revisions r LEFT JOIN users u ON u.id = r.author_id WHERE r.page_id = ? AND r.number = ?", [num(page_id), num(number)])
        if r.is_empty() then none else revision_of(r[0]) end
    end

    -- Releases

    public fun current_release_id(self) -> int?
        let r = self.rows("SELECT value FROM settings WHERE name = 'current_release'", [])
        if r.is_empty() then none else col_text(r[0], "value").to_int() end
    end

    public fun clear_current_release(self)
        self.exec("DELETE FROM settings WHERE name = 'current_release'", [])
    end

    public fun set_current_release(self, id: int)
        self.exec("DELETE FROM settings WHERE name = 'current_release'", [])
        self.exec("INSERT INTO settings (name, value) VALUES ('current_release', ?)", [text("{id}")])
    end

    public fun releases(self) -> array<Release>
        let current = self.current_release_id()
        let out: array<Release> = []
        for row in self.rows("SELECT r.*, COALESCE(u.login, '') AS author, (SELECT COUNT(*) FROM release_pages p WHERE p.release_id = r.id) AS pages FROM releases r LEFT JOIN users u ON u.id = r.created_by ORDER BY r.created_at DESC, r.id DESC", []) do
            out.push(release_of(row, current))
        end
        out
    end

    public fun release(self, id: int) -> Release?
        let current = self.current_release_id()
        let r = self.rows("SELECT r.*, COALESCE(u.login, '') AS author, (SELECT COUNT(*) FROM release_pages p WHERE p.release_id = r.id) AS pages FROM releases r LEFT JOIN users u ON u.id = r.created_by WHERE r.id = ?", [num(id)])
        if r.is_empty() then none else release_of(r[0], current) end
    end

    public fun release_by_label(self, label: string) -> Release?
        let r = self.rows("SELECT id FROM releases WHERE label = ?", [text(label)])
        if r.is_empty() then none else self.release(col_int(r[0], "id")) end
    end

    public fun create_release(self, label: string, qlang_version: string, note: string, author: int?) -> int
        let r = self.rows("INSERT INTO releases (label, qlang_version, note, created_by, created_at) VALUES (?, ?, ?, ?, ?) RETURNING id", [text(label), text(qlang_version), text(note), opt(author), num(self.now())])
        col_int(r[0], "id")
    end

    public fun add_release_folder(self, release_id: int, f: SnapFolder)
        self.exec("INSERT INTO release_folders (release_id, locale, path, title, position, section) VALUES (?, ?, ?, ?, ?, ?)", [num(release_id), text(f.locale), text(f.path), text(f.title), num(f.position), text(f.section)])
    end

    public fun add_release_page(self, release_id: int, p: SnapPage)
        self.exec("INSERT INTO release_pages (release_id, locale, path, title, markdown, html, toc, position) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [num(release_id), text(p.locale), text(p.path), text(p.title), text(p.markdown), text(p.html), text(p.toc), num(p.position)])
    end

    public fun release_folders(self, release_id: int) -> array<SnapFolder>
        let out: array<SnapFolder> = []
        for row in self.rows("SELECT * FROM release_folders WHERE release_id = ? ORDER BY locale, path", [num(release_id)]) do
            out.push(SnapFolder { locale: col_text(row, "locale"), path: col_text(row, "path"), title: col_text(row, "title"), position: col_int(row, "position"), section: col_text(row, "section") })
        end
        out
    end

    public fun release_pages(self, release_id: int) -> array<SnapPage>
        let out: array<SnapPage> = []
        for row in self.rows("SELECT * FROM release_pages WHERE release_id = ? ORDER BY locale, path", [num(release_id)]) do
            out.push(SnapPage {
                locale: col_text(row, "locale"), path: col_text(row, "path"), title: col_text(row, "title"), markdown: col_text(row, "markdown"),
                html: col_text(row, "html"), toc: col_text(row, "toc"), position: col_int(row, "position"),
            })
        end
        out
    end

    public fun release_page(self, release_id: int, locale: string, path: string) -> SnapPage?
        let r = self.rows("SELECT * FROM release_pages WHERE release_id = ? AND locale = ? AND path = ?", [num(release_id), text(locale), text(path)])
        if r.is_empty() then
            return none
        end
        let row = r[0]
        SnapPage { locale: col_text(row, "locale"), path: col_text(row, "path"), title: col_text(row, "title"), markdown: col_text(row, "markdown"), html: col_text(row, "html"), toc: col_text(row, "toc"), position: col_int(row, "position") }
    end

    --" The pages of a release whose title or text holds the words (a plain `LIKE`, good enough for a documentation). --"
    public fun search_release(self, release_id: int, locale: string, words: string, limit: int) -> array<SnapPage>
        let out: array<SnapPage> = []
        let pattern = "%" + words.lower().replace("\\", "").replace("%", "").replace("_", "") + "%"
        for row in self.rows("SELECT * FROM release_pages WHERE release_id = ? AND locale = ? AND (LOWER(title) LIKE ? OR LOWER(markdown) LIKE ?) ORDER BY (CASE WHEN LOWER(title) LIKE ? THEN 0 ELSE 1 END), path LIMIT ?", [num(release_id), text(locale), text(pattern), text(pattern), text(pattern), num(limit)]) do
            out.push(SnapPage {
                locale: col_text(row, "locale"), path: col_text(row, "path"), title: col_text(row, "title"), markdown: col_text(row, "markdown"),
                html: col_text(row, "html"), toc: col_text(row, "toc"), position: col_int(row, "position"),
            })
        end
        out
    end

    public fun delete_release(self, id: int)
        self.exec("DELETE FROM releases WHERE id = ?", [num(id)])
    end

    -- Audit

    public fun log(self, user_id: int?, action: string, entity_type: string, entity_id: int?, summary: string, data: Json)
        self.exec("INSERT INTO audit_logs (user_id, action, entity_type, entity_id, summary, data, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)", [opt(user_id), text(action), text(entity_type), opt(entity_id), text(summary), text(data.to_text()), num(self.now())])
    end

    public fun audit_search(self, f: AuditFilter, limit: int, offset: int) -> array<AuditEntry>
        let params: array<Json> = []
        let where = audit_where(f, params)
        params.push(num(limit))
        params.push(num(offset))
        let out: array<AuditEntry> = []
        for row in self.rows("SELECT a.*, COALESCE(u.login, '') AS login FROM audit_logs a LEFT JOIN users u ON u.id = a.user_id {where} ORDER BY a.created_at DESC, a.id DESC LIMIT ? OFFSET ?", params) do
            out.push(AuditEntry {
                id: col_int(row, "id"), user: col_text(row, "login"), action: col_text(row, "action"), entity_type: col_text(row, "entity_type"),
                entity_id: col_opt(row, "entity_id"), summary: col_text(row, "summary"), data: col_text(row, "data"), created_at: col_int(row, "created_at"),
            })
        end
        out
    end

    public fun audit_total(self, f: AuditFilter) -> int
        let params: array<Json> = []
        let where = audit_where(f, params)
        col_int(self.rows("SELECT COUNT(*) AS n FROM audit_logs a {where}", params)[0], "n")
    end

    --" The actions that appear in the journal, to fill the filter. --"
    public fun audit_actions(self) -> array<string>
        self.rows("SELECT DISTINCT action FROM audit_logs ORDER BY action", []).map(fun(row: Row) -> string col_text(row, "action") end)
    end

    public fun audit(self, kind: string, limit: int, offset: int) -> array<AuditEntry>
        self.audit_search(AuditFilter { kind: kind, user_id: none, action: "", since: none, until: none }, limit, offset)
    end

    public fun audit_count(self, kind: string) -> int
        self.audit_total(AuditFilter { kind: kind, user_id: none, action: "", since: none, until: none })
    end
end

fun audit_where(f: AuditFilter, params: array<Json>) -> string
    let parts: array<string> = []
    if f.kind != "" then
        parts.push("a.entity_type = ?")
        params.push(text(f.kind))
    end
    if f.user_id != none then
        parts.push("a.user_id = ?")
        params.push(num(f.user_id ?? 0))
    end
    if f.action != "" then
        parts.push("a.action = ?")
        params.push(text(f.action))
    end
    if f.since != none then
        parts.push("a.created_at >= ?")
        params.push(num(f.since ?? 0))
    end
    if f.until != none then
        parts.push("a.created_at < ?")
        params.push(num(f.until ?? 0))
    end
    if parts.is_empty() then "" else "WHERE " + parts.join(" AND ") end
end

export Store, Row, num, text, opt, col_int, col_opt, col_text
