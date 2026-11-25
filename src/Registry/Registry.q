import "@std/toml.q" as toml
import Store from "../Docs/Store.q"
import render_page from "../Markup/Render.q"
import Package, PackageVersion, Tag, Source, SyncReport from "./Models.q"
import PackageStore from "./Store.q"
import "./Semver.q" as semver

--" What the operator decides: who may submit, and from where git repositories may come. --"
struct Options
    --" Anyone may submit a package (it waits in the moderation queue). Off by default. --"
    public submissions_open: bool
    --" The hosts a submitted repository may live on (`github.com`...); empty: any public host. --"
    public hosts: array<string>
end

impl Options
    public fun closed() -> Options
        Options { submissions_open: false, hosts: [] }
    end
end

--" Packages are what people share; the registry only says where they live. Nothing is run and no code is read except
`qlang.toml` and the README of a tag, by the worker (`tools/sync-packages.q`), never by the web server. --"
struct Registry
    public log: Store
    public packages: PackageStore
    public options: Options
end

fun valid_name(name: string) -> bool
    if name == "" or name.len() > 64 then
        return false
    end
    for c in name.chars() do
        if not ((c.is_digit()) or (c.is_alpha() and c == c.lower()) or c == "-" or c == "_") then
            return false
        end
    end
    true
end

fun is_address(host: string) -> bool
    if host.contains(":") or host.contains("[") then
        return true
    end
    for c in host.chars() do
        if not (c.is_digit() or c == ".") then
            return false
        end
    end
    true
end

fun is_private_host(host: string) -> bool
    not host.contains(".") or is_address(host) or host == "localhost" or host.ends_with(".local") or host.ends_with(".internal") or host.ends_with(".localhost")
end

fun has_url_char_only(rest: string) -> bool
    for c in rest.chars() do
        if not (c.is_digit() or c.is_alpha() or c == "." or c == "-" or c == "_" or c == "/" or c == "~") then
            return false
        end
    end
    true
end

--" The canonical form of a public https repository address (no `.git`, no trailing `/`), or an error that says what is wrong.
`hosts` limits where it may live (empty: any public host). --"
fun check_git_url(raw: string, hosts: array<string>) -> Result<string, string>
    let url = raw.trim()
    if url.len() > 300 or not url.starts_with("https://") then
        return Err("L'adresse doit commencer par https:// (300 caractères au plus).")
    end
    let rest = url.substring(8, url.len())
    if not has_url_char_only(rest) then
        return Err("L'adresse contient des caractères non permis.")
    end
    let parts = rest.split("/").filter(fun(p: string) -> bool p != "" end)
    if parts.len() < 3 or parts.len() > 5 then
        return Err("L'adresse doit désigner un dépôt : https://hôte/propriétaire/dépôt")
    end
    let host = parts[0].lower()
    if is_private_host(host) then
        return Err("L'hôte doit être un nom de domaine public.")
    end
    if not hosts.is_empty() and not hosts.contains(host) then
        return Err("Hôtes acceptés : {hosts.join(", ")}.")
    end
    if parts.contains(".") or parts.contains("..") then
        return Err("L'adresse contient des caractères non permis.")
    end
    let path = parts.slice(1, parts.len()).join("/")
    let bare = path.strip_suffix(".git") ?? path
    Ok("https://" + host + "/" + bare)
end

fun text_at(json: Json, key: string) -> string
    let v = json.get(key)
    if v == none or v.is_null() then "" else v.as_string() end
end

impl Registry
    public fun new(log: Store, options: Options) -> Registry
        Registry { log: log, packages: PackageStore.new(log.db), options: options }
    end

    fun add_package(self, name_input: string, url_input: string, status: string, actor: int?, hosts: array<string>) -> Result<int, string>
        let name = name_input.trim()
        if not valid_name(name) then
            return Err("Le nom ne peut contenir que des minuscules, chiffres, - et _ (64 caractères au plus).")
        end
        let url = check_git_url(url_input, hosts)
        if url.is_err() then
            return Err(url.unwrap_err())
        end
        if self.packages.package_by_name(name) != none then
            return Err("Ce nom est déjà pris.")
        end
        if self.packages.package_by_git(url.unwrap()) != none then
            return Err("Ce dépôt est déjà référencé.")
        end
        let id = self.packages.create_package(name, url.unwrap(), status)
        let what = if status == "pending" then "Paquet {name} proposé" else "Paquet {name} ajouté" end
        self.log.log(actor, "package.{if status == "pending" then "submit" else "add" end}", "package", id, what, Json.object({ "name": Json.string(name), "git": Json.string(url.unwrap()) }))
        Ok(id)
    end

    --" Anyone's proposal: it waits for a moderator. Refused when submissions are closed. --"
    public fun submit(self, name: string, url: string) -> Result<int, string>
        if not self.options.submissions_open then
            return Err("Les propositions de paquets sont fermées.")
        end
        self.add_package(name, url, "pending", none, self.options.hosts)
    end

    --" A moderator adds a package straight to the index (any public https host). --"
    public fun add(self, name: string, url: string, actor: int?) -> Result<int, string>
        self.add_package(name, url, "listed", actor, [])
    end

    fun load(self, id: int) -> Result<Package, string>
        let p = self.packages.package(id)
        if p == none then Err("Paquet introuvable.") else Ok(p) end
    end

    public fun approve(self, id: int, actor: int?) -> Result<bool, string>
        let p = self.load(id)
        if p.is_err() then
            return Err(p.unwrap_err())
        end
        if p.unwrap().status != "pending" then
            return Err("Ce paquet n'est pas en attente.")
        end
        self.packages.set_status(id, "listed", "")
        self.packages.set_sync_requested(id, true)
        self.log.log(actor, "package.approve", "package", id, "Paquet {p.unwrap().name} accepté", Json.object({ "name": Json.string(p.unwrap().name) }))
        Ok(true)
    end

    --" Refuses a proposal: it is forgotten. --"
    public fun reject(self, id: int, actor: int?) -> Result<bool, string>
        let p = self.load(id)
        if p.is_err() then
            return Err(p.unwrap_err())
        end
        if p.unwrap().status != "pending" then
            return Err("Ce paquet n'est pas en attente.")
        end
        self.packages.delete_package(id)
        self.log.log(actor, "package.reject", "package", id, "Proposition {p.unwrap().name} refusée", Json.object({ "name": Json.string(p.unwrap().name), "git": Json.string(p.unwrap().git_url) }))
        Ok(true)
    end

    --" Withdraws a package from the index: `qlang add` refuses it, projects that already lock it keep working. --"
    public fun remove(self, id: int, reason: string, actor: int?) -> Result<bool, string>
        let p = self.load(id)
        if p.is_err() then
            return Err(p.unwrap_err())
        end
        if reason.trim() == "" then
            return Err("Dis pourquoi le paquet est retiré.")
        end
        self.packages.set_status(id, "removed", reason.trim())
        self.log.log(actor, "package.remove", "package", id, "Paquet {p.unwrap().name} retiré", Json.object({ "name": Json.string(p.unwrap().name), "reason": Json.string(reason.trim()) }))
        Ok(true)
    end

    public fun restore(self, id: int, actor: int?) -> Result<bool, string>
        let p = self.load(id)
        if p.is_err() then
            return Err(p.unwrap_err())
        end
        if p.unwrap().status != "removed" then
            return Err("Ce paquet n'est pas retiré.")
        end
        self.packages.set_status(id, "listed", "")
        self.packages.set_sync_requested(id, true)
        self.log.log(actor, "package.restore", "package", id, "Paquet {p.unwrap().name} rétabli", Json.object({ "name": Json.string(p.unwrap().name) }))
        Ok(true)
    end

    public fun delete(self, id: int, actor: int?) -> Result<bool, string>
        let p = self.load(id)
        if p.is_err() then
            return Err(p.unwrap_err())
        end
        self.packages.delete_package(id)
        self.log.log(actor, "package.delete", "package", id, "Paquet {p.unwrap().name} supprimé", Json.object({ "name": Json.string(p.unwrap().name), "git": Json.string(p.unwrap().git_url) }))
        Ok(true)
    end

    --" A version that must not be chosen any more (a flaw was found): projects that lock it keep working. --"
    public fun yank(self, id: int, version: string, yanked: bool, actor: int?) -> Result<bool, string>
        let p = self.load(id)
        if p.is_err() then
            return Err(p.unwrap_err())
        end
        let known = self.packages.versions(id).filter(fun(v: PackageVersion) -> bool v.version == version end)
        if known.is_empty() then
            return Err("Version inconnue.")
        end
        self.packages.set_yanked(id, version, yanked)
        self.log.log(actor, if yanked then "package.yank" else "package.unyank" end, "package", id, "{p.unwrap().name} {version} {if yanked then "retirée du choix" else "de nouveau choisissable" end}", Json.object({ "name": Json.string(p.unwrap().name), "version": Json.string(version) }))
        Ok(true)
    end

    --" Asks the worker to read the repository again (from the panel, or from a webhook). --"
    public fun request_sync(self, id: int) -> Result<bool, string>
        let p = self.load(id)
        if p.is_err() then
            return Err(p.unwrap_err())
        end
        self.packages.set_sync_requested(id, true)
        Ok(true)
    end

    --" A webhook of a git host: the repository that pushed asks for a sync. Gives true when we know it. --"
    public fun request_sync_for_url(self, url: string) -> bool
        let checked = check_git_url(url, [])
        if checked.is_err() then
            return false
        end
        let p = self.packages.package_by_git(checked.unwrap())
        if p == none or p.status != "listed" then
            return false
        end
        self.packages.set_sync_requested(p.id, true)
        true
    end

    --" The versions of a package, newest first. --"
    public fun versions(self, id: int) -> array<PackageVersion>
        let all = self.packages.versions(id)
        let order = semver.newest_first(all.map(fun(v: PackageVersion) -> string v.version end))
        let out: array<PackageVersion> = []
        for name in order do
            for v in all do
                if v.version == name then
                    out.push(v)
                end
            end
        end
        out
    end

    fun fail(self, p: Package, message: string) -> Result<SyncReport, string>
        self.packages.set_sync_error(p.id, message)
        self.log.log(none, "package.sync_failed", "package", p.id, "Lecture de {p.name} impossible", Json.object({ "name": Json.string(p.name), "error": Json.string(message) }))
        Err(message)
    end

    --" Reads the repository of a package through `source`: its tags become versions, and the manifest and the README of the latest one fill its page. --"
    public fun sync(self, id: int, source: Source) -> Result<SyncReport, string>
        let loaded = self.load(id)
        if loaded.is_err() then
            return Err(loaded.unwrap_err())
        end
        let p = loaded.unwrap()
        let tags = source.tags(p.git_url)
        if tags.is_err() then
            return self.fail(p, tags.unwrap_err())
        end
        let names = tags.unwrap().map(fun(t: Tag) -> string t.name end)
        let latest = semver.latest(names)
        if latest == none then
            return self.fail(p, "Aucune étiquette de la forme vX.Y.Z dans le dépôt.")
        end
        let added = 0
        for t in tags.unwrap() do
            if semver.parse(t.name) != none and self.packages.upsert_version(id, t.name, t.sha, "") then
                added = added + 1
            end
        end
        let snap = source.snapshot(p.git_url, latest)
        if snap.is_err() then
            return self.fail(p, snap.unwrap_err())
        end
        let manifest = toml.parse(snap.unwrap().manifest)
        if manifest.is_err() then
            return self.fail(p, "qlang.toml : {manifest.unwrap_err().message}")
        end
        let section = manifest.unwrap().get("package")
        if section == none then
            return self.fail(p, "qlang.toml n'a pas de section [package].")
        end
        let keywords = Json.to<array<string>>(section.get("keywords") ?? Json.array([]))
        let readme = snap.unwrap().readme
        let shown = if readme.len() > 200000 then readme.substring(0, 200000) else readme end
        self.packages.set_synced(id, text_at(section, "description"), text_at(section, "license"), if keywords.is_ok() then keywords.unwrap() else [] end, render_page(shown).html, latest)
        self.packages.set_version_requirement(id, latest, text_at(section, "qlang"))
        let warning = if text_at(section, "name") != "" and text_at(section, "name") != p.name then "Le nom dans qlang.toml ({text_at(section, "name")}) diffère du nom référencé ({p.name})." else "" end
        self.log.log(none, "package.sync", "package", id, "Paquet {p.name} lu : {latest} ({added} nouvelle(s) version(s))", Json.object({ "name": Json.string(p.name), "latest": Json.string(latest), "added": Json.number(added as float) }))
        Ok(SyncReport { added: added, latest: latest, warning: warning })
    end

    --" Reads every listed package that asked for it or has not been read since `older_than_ms`. Gives what happened to each. --"
    public fun sync_due(self, source: Source, older_than_ms: int, limit: int) -> array<string>
        let out: array<string> = []
        let cutoff = time.now() - older_than_ms
        for p in self.packages.due_for_sync(cutoff, limit) do
            let done = self.sync(p.id, source)
            if done.is_ok() then
                out.push("{p.name}: {done.unwrap().latest} (+{done.unwrap().added})")
            else
                out.push("{p.name}: {done.unwrap_err()}")
            end
        end
        out
    end

    --" The index in the format of `qlang search` / `qlang add`: set `QLANG_INDEX_URL` to its address. --"
    public fun index_json(self) -> string
        let entries: map<string, Json> = {}
        for p in self.packages.packages("", "", "") do
            if p.status == "pending" then
                continue
            end
            let yanked = self.packages.versions(p.id).filter(fun(v: PackageVersion) -> bool v.yanked end).map(fun(v: PackageVersion) -> string v.version end)
            let entry: map<string, Json> = {
                "git": Json.string(p.git_url),
                "description": Json.string(p.description),
                "license": Json.string(p.license),
                "keywords": Json.of(p.keywords),
            }
            if not yanked.is_empty() then
                entry["yanked"] = Json.of(yanked)
            end
            if p.status == "removed" then
                entry["removed"] = Json.string(if p.removed_reason == "" then "retiré" else p.removed_reason end)
            end
            entries[p.name] = Json.object(entry)
        end
        Json.object(entries).to_text()
    end
end

export Options, Registry, check_git_url, valid_name
