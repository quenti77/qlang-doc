import "@markdown/markdown.q" as markdown
import "@std/web/session.q" as sessions
import Folder, Page, Account, Release, SnapFolder, SnapPage from "./Models.q"
import Store from "./Store.q"
import folder_paths, page_path from "./Tree.q"
import render_page from "../Markup/Render.q"
import Stats, diff, stats from "./Diff.q"

--" What a page needs once its Markdown is read. --"
struct Rendered
    public html: string
    public toc: string
    public title: string
end

--" What the changes did to the working copy compared to the published release. --"
struct Change
    public kind: string
    public locale: string
    public path: string
    public title: string
end

let LOCALES = ["fr", "en"]

fun is_slug(text: string) -> bool
    if text == "" or text.len() > 100 then
        return false
    end
    for c in text.chars() do
        if not (c.is_digit() or (c.is_alpha() and c == c.lower()) or c == "-" or c == "_" or c == ".") then
            return false
        end
    end
    true
end

--" `Getting started!` becomes `getting-started`. --"
fun slug_of(text: string) -> string
    let out = ""
    let dash = false
    for c in text.lower().chars() do
        if c.is_digit() or c.is_alpha() then
            out = out + c
            dash = false
        elseif not dash and out != "" then
            out = out + "-"
            dash = true
        end
    end
    out.strip_suffix("-") ?? out
end

--" What a Markdown file says about itself: the `title:` of its front matter, or its first heading, or its name. --"
struct Imported
    public title: string
    public body: string
end

fun read_front_matter(content: string, fallback: string) -> Imported
    let text = content.replace("\r\n", "\n")
    let title = ""
    let body = text
    if text.starts_with("---\n") then
        let rest = text.substring(4, text.len())
        let close = rest.index_of("\n---\n")
        if close != none then
            for line in rest.substring(0, close).split("\n") do
                if line.starts_with("title:") then
                    title = line.substring(6, line.len()).trim().strip_prefix("\"") ?? line.substring(6, line.len()).trim()
                    title = title.strip_suffix("\"") ?? title
                end
            end
            body = rest.substring(close + 5, rest.len())
        end
    end
    if title == "" then
        let heading = markdown.convert(body, markdown.Options.plain()).title
        title = if heading == "" then fallback else heading end
    end
    Imported { title: title.trim(), body: body.trim() }
end

fun file_stem(filename: string) -> string
    let name = filename.split("/")
    let last = name[name.len() - 1]
    let dot = last.last_index_of(".")
    if dot == none or dot == 0 then last else last.substring(0, dot) end
end

--" The documentation: what the admin does and what the public reads. Every change leaves a line in the audit log. --"
struct Docs
    public store: Store
end

impl Docs
    public fun new(store: Store) -> Docs
        Docs { store: store }
    end

    public fun render(self, source: string) -> Rendered
        let doc = render_page(source)
        Rendered { html: doc.html, toc: Json.of(doc.headings).to_text(), title: doc.title }
    end

    -- Accounts

    --" The account that has this login and this password, or none (the same answer for a wrong login and a wrong password). --"
    public fun authenticate(self, login: string, password: string) -> Account?
        let account = self.store.account_by_login(login.trim())
        if account == none then
            Password.verify(password, "$argon2id$v=19$m=19456,t=2,p=1$c29tZXNhbHRzb21lc2FsdA$Zm9vYmFyYmF6cXV4cXV1eGZvb2JhcmJhenF1eA")
            return none
        end
        let ok = Password.verify(password, account.password_hash)
        if ok.is_ok() and ok.unwrap() then account else none end
    end

    public fun create_account(self, login: string, password: string, role: string, actor: int?) -> Result<int, string>
        if login.trim().len() < 3 then
            return Err("L'identifiant doit faire au moins 3 caractères.")
        end
        if password.len() < 12 then
            return Err("Le mot de passe doit faire au moins 12 caractères.")
        end
        if role != "admin" and role != "editor" then
            return Err("Rôle inconnu.")
        end
        if self.store.account_by_login(login.trim()) != none then
            return Err("Cet identifiant existe déjà.")
        end
        let hash = Password.hash(password)
        if hash.is_err() then
            return Err("Le mot de passe n'a pas pu être haché.")
        end
        let id = self.store.create_account(login.trim(), hash.unwrap(), role)
        self.store.log(actor, "account.create", "account", id, "Compte {login.trim()} créé ({role})", Json.object({ "login": Json.string(login.trim()), "role": Json.string(role) }))
        Ok(id)
    end

    public fun change_password(self, id: int, password: string, actor: int?) -> Result<bool, string>
        if password.len() < 12 then
            return Err("Le mot de passe doit faire au moins 12 caractères.")
        end
        let hash = Password.hash(password)
        if hash.is_err() then
            return Err("Le mot de passe n'a pas pu être haché.")
        end
        self.store.update_password(id, hash.unwrap())
        self.store.log(actor, "account.password", "account", id, "Mot de passe changé", Json.object({}))
        Ok(true)
    end

    public fun delete_account(self, id: int, actor: int?) -> Result<bool, string>
        if id == actor then
            return Err("Tu ne peux pas supprimer ton propre compte.")
        end
        let account = self.store.account(id)
        if account == none then
            return Err("Compte introuvable.")
        end
        self.store.delete_account(id)
        self.store.log(actor, "account.delete", "account", id, "Compte {account.login} supprimé", Json.object({ "login": Json.string(account.login) }))
        Ok(true)
    end

    -- Folders

    fun check_parent(self, locale: string, parent_id: int?) -> Result<bool, string>
        if parent_id == none then
            return Ok(true)
        end
        let parent = self.store.folder(parent_id)
        if parent == none or parent.locale != locale then
            return Err("Dossier parent introuvable.")
        end
        Ok(true)
    end

    public fun create_folder(self, locale: string, parent_id: int?, title: string, slug_input: string, actor: int?) -> Result<int, string>
        if not LOCALES.contains(locale) then
            return Err("Langue inconnue.")
        end
        let name = title.trim()
        if name == "" then
            return Err("Le titre est obligatoire.")
        end
        let slug = if slug_input.trim() == "" then slug_of(name) else slug_input.trim() end
        if not is_slug(slug) then
            return Err("L'adresse (slug) ne peut contenir que des minuscules, chiffres, - _ et .")
        end
        let parent = self.check_parent(locale, parent_id)
        if parent.is_err() then
            return Err(parent.unwrap_err())
        end
        if self.store.find_folder(locale, parent_id, slug) != none or self.store.find_page(locale, parent_id, slug) != none then
            return Err("Cette adresse est déjà prise à cet endroit.")
        end
        let id = self.store.create_folder(locale, parent_id, slug, name)
        self.store.log(actor, "folder.create", "folder", id, "Dossier « {name} » créé", Json.object({ "locale": Json.string(locale), "slug": Json.string(slug) }))
        Ok(id)
    end

    public fun update_folder(self, id: int, title: string, slug_input: string, actor: int?) -> Result<bool, string>
        let folder = self.store.folder(id)
        if folder == none then
            return Err("Dossier introuvable.")
        end
        let name = title.trim()
        let slug = slug_input.trim()
        if name == "" or not is_slug(slug) then
            return Err("Titre et adresse valides sont obligatoires.")
        end
        if slug != folder.slug and (self.store.find_folder(folder.locale, folder.parent_id, slug) != none or self.store.find_page(folder.locale, folder.parent_id, slug) != none) then
            return Err("Cette adresse est déjà prise à cet endroit.")
        end
        self.store.update_folder(id, slug, name)
        self.store.log(actor, "folder.update", "folder", id, "Dossier « {name} » modifié", Json.object({ "from_title": Json.string(folder.title), "to_title": Json.string(name), "from_slug": Json.string(folder.slug), "to_slug": Json.string(slug) }))
        Ok(true)
    end

    fun is_inside(self, folder_id: int, candidate: int?) -> bool
        let current = candidate
        let guard = 0
        while current != none and guard < 50 do
            if current == folder_id then
                return true
            end
            let f = self.store.folder(current)
            current = if f == none then none else f.parent_id end
            guard = guard + 1
        end
        false
    end

    public fun move_folder(self, id: int, parent_id: int?, actor: int?) -> Result<bool, string>
        let folder = self.store.folder(id)
        if folder == none then
            return Err("Dossier introuvable.")
        end
        let parent = self.check_parent(folder.locale, parent_id)
        if parent.is_err() then
            return Err(parent.unwrap_err())
        end
        if self.is_inside(id, parent_id) then
            return Err("Un dossier ne peut pas être déplacé dans lui-même.")
        end
        if self.store.find_folder(folder.locale, parent_id, folder.slug) != none or self.store.find_page(folder.locale, parent_id, folder.slug) != none then
            return Err("Cette adresse est déjà prise dans le dossier de destination.")
        end
        self.store.move_folder(id, parent_id)
        self.store.log(actor, "folder.move", "folder", id, "Dossier « {folder.title} » déplacé", Json.object({ "from": opt_json(folder.parent_id), "to": opt_json(parent_id) }))
        Ok(true)
    end

    public fun delete_folder(self, id: int, actor: int?) -> Result<bool, string>
        let folder = self.store.folder(id)
        if folder == none then
            return Err("Dossier introuvable.")
        end
        if not self.store.folder_is_empty(id) then
            return Err("Le dossier n'est pas vide : déplace ou supprime son contenu d'abord.")
        end
        self.store.delete_folder(id)
        self.store.log(actor, "folder.delete", "folder", id, "Dossier « {folder.title} » supprimé", Json.object({ "slug": Json.string(folder.slug), "locale": Json.string(folder.locale) }))
        Ok(true)
    end

    --" Puts the siblings in the order of `ids` (all of the same kind and the same parent). --"
    public fun reorder(self, kind: string, ids: array<int>, actor: int?) -> Result<bool, string>
        if kind != "folders" and kind != "pages" then
            return Err("Type inconnu.")
        end
        self.store.order(kind, ids)
        self.store.log(actor, "{kind}.reorder", kind.strip_suffix("s") ?? kind, none, "Ordre modifié", Json.object({ "ids": Json.array(ids.map(fun(i: int) -> Json Json.number(i as float) end)) }))
        Ok(true)
    end

    -- Pages

    public fun create_page(self, locale: string, folder_id: int?, title: string, slug_input: string, markdown_text: string, source: string, actor: int?) -> Result<int, string>
        if not LOCALES.contains(locale) then
            return Err("Langue inconnue.")
        end
        let name = title.trim()
        if name == "" then
            return Err("Le titre est obligatoire.")
        end
        let slug = if slug_input.trim() == "" then slug_of(name) else slug_input.trim() end
        if not is_slug(slug) then
            return Err("L'adresse (slug) ne peut contenir que des minuscules, chiffres, - _ et .")
        end
        let parent = self.check_parent(locale, folder_id)
        if parent.is_err() then
            return Err(parent.unwrap_err())
        end
        if self.store.find_page(locale, folder_id, slug) != none or self.store.find_folder(locale, folder_id, slug) != none then
            return Err("Cette adresse est déjà prise à cet endroit.")
        end
        let r = self.render(markdown_text)
        let id = self.store.create_page(locale, folder_id, slug, name, markdown_text, r.html, r.toc, source, if source == "import" then "Import" else "Création" end, actor)
        self.store.log(actor, "page.{source}", "page", id, "Page « {name} » {if source == "import" then "importée" else "créée" end}", Json.object({ "locale": Json.string(locale), "slug": Json.string(slug), "lines": Json.number(markdown_text.split("\n").len() as float) }))
        Ok(id)
    end

    --" Saves a page: a new revision, with the diff stats in the log. --"
    public fun edit_page(self, id: int, title: string, markdown_text: string, summary: string, source: string, actor: int?) -> Result<int, string>
        let page = self.store.page(id)
        if page == none then
            return Err("Page introuvable.")
        end
        let name = title.trim()
        if name == "" then
            return Err("Le titre est obligatoire.")
        end
        let r = self.render(markdown_text)
        let number = self.store.save_page(id, name, markdown_text, r.html, r.toc, source, summary.trim(), actor)
        if number != page.revision then
            let s = diff_stats(page.markdown, markdown_text)
            self.store.log(actor, "page.{source}", "page", id, "Page « {name} » modifiée (révision {number})", Json.object({
                "from": Json.number(page.revision as float), "to": Json.number(number as float),
                "added": Json.number(s.added as float), "removed": Json.number(s.removed as float),
                "summary": Json.string(summary.trim()),
            }))
        end
        Ok(number)
    end

    public fun rename_page(self, id: int, slug_input: string, actor: int?) -> Result<bool, string>
        let page = self.store.page(id)
        if page == none then
            return Err("Page introuvable.")
        end
        let slug = slug_input.trim()
        if not is_slug(slug) then
            return Err("L'adresse (slug) ne peut contenir que des minuscules, chiffres, - _ et .")
        end
        if slug != page.slug and (self.store.find_page(page.locale, page.folder_id, slug) != none or self.store.find_folder(page.locale, page.folder_id, slug) != none) then
            return Err("Cette adresse est déjà prise à cet endroit.")
        end
        self.store.set_page_slug(id, slug)
        self.store.log(actor, "page.rename", "page", id, "Adresse de « {page.title} » changée", Json.object({ "from": Json.string(page.slug), "to": Json.string(slug) }))
        Ok(true)
    end

    public fun move_page(self, id: int, folder_id: int?, actor: int?) -> Result<bool, string>
        let page = self.store.page(id)
        if page == none then
            return Err("Page introuvable.")
        end
        let parent = self.check_parent(page.locale, folder_id)
        if parent.is_err() then
            return Err(parent.unwrap_err())
        end
        if self.store.find_page(page.locale, folder_id, page.slug) != none or self.store.find_folder(page.locale, folder_id, page.slug) != none then
            return Err("Cette adresse est déjà prise dans le dossier de destination.")
        end
        self.store.move_page(id, folder_id)
        self.store.log(actor, "page.move", "page", id, "Page « {page.title} » déplacée", Json.object({ "from": opt_json(page.folder_id), "to": opt_json(folder_id) }))
        Ok(true)
    end

    --" Deletes a page. Its last text stays in the log, so that it can be put back by hand. --"
    public fun delete_page(self, id: int, actor: int?) -> Result<bool, string>
        let page = self.store.page(id)
        if page == none then
            return Err("Page introuvable.")
        end
        self.store.delete_page(id)
        self.store.log(actor, "page.delete", "page", id, "Page « {page.title} » supprimée", Json.object({
            "locale": Json.string(page.locale), "slug": Json.string(page.slug), "title": Json.string(page.title), "markdown": Json.string(page.markdown),
        }))
        Ok(true)
    end

    public fun restore_revision(self, page_id: int, number: int, actor: int?) -> Result<int, string>
        let revision = self.store.revision(page_id, number)
        if revision == none then
            return Err("Révision introuvable.")
        end
        self.edit_page(page_id, revision.title, revision.markdown, "Retour à la révision {number}", "restore", actor)
    end

    --" Imports a Markdown file into a folder: a new page, or a new revision of the page that has this name. --"
    public fun import_markdown(self, locale: string, folder_id: int?, filename: string, content: string, actor: int?) -> Result<int, string>
        if content.trim() == "" then
            return Err("Le fichier est vide.")
        end
        let stem = file_stem(filename)
        let info = read_front_matter(content, stem)
        let slug = slug_of(stem)
        if slug == "" then
            return Err("Le nom du fichier ne donne pas d'adresse valide.")
        end
        let existing = self.store.find_page(locale, folder_id, slug)
        if existing != none then
            return self.edit_page(existing.id, info.title, info.body, "Import de {filename}", "import", actor)
        end
        self.create_page(locale, folder_id, info.title, slug, info.body, "import", actor)
    end

    -- Releases

    --" The working copy as it would be published: the folders and the pages with their paths. --"
    public fun snapshot(self) -> (array<SnapFolder>, array<SnapPage>)
        let folders_out: array<SnapFolder> = []
        let pages_out: array<SnapPage> = []
        for locale in LOCALES do
            let folders = self.store.folders(locale)
            let paths = folder_paths(folders)
            for f in folders do
                folders_out.push(SnapFolder { locale: locale, path: paths[f.id] ?? f.slug, title: f.title, position: f.position })
            end
            for p in self.store.pages(locale) do
                pages_out.push(SnapPage { locale: locale, path: page_path(p.folder_id, p.slug, paths), title: p.title, markdown: p.markdown, html: p.html, toc: p.toc, position: p.position })
            end
        end
        (folders_out, pages_out)
    end

    --" Freezes the working copy as a release. `label` names it (`1.12.0`), and it is tied to the qlang version it documents. --"
    public fun create_release(self, label: string, qlang_version: string, note: string, publish: bool, actor: int?) -> Result<int, string>
        let name = label.trim()
        if name == "" or name.len() > 40 then
            return Err("Le nom de la version est obligatoire (40 caractères au plus).")
        end
        for c in name.chars() do
            if not (c.is_digit() or c.is_alpha() or c == "." or c == "-" or c == "_") then
                return Err("Le nom de la version ne peut contenir que des lettres, chiffres, . - et _")
            end
        end
        if self.store.release_by_label(name) != none then
            return Err("Une version porte déjà ce nom.")
        end
        let snap = self.snapshot()
        if snap.1.is_empty() then
            return Err("Il n'y a aucune page à publier.")
        end
        let id = self.store.atomic(fun() -> int
            let rid = self.store.create_release(name, if qlang_version.trim() == "" then name else qlang_version.trim() end, note.trim(), actor)
            for f in snap.0 do
                self.store.add_release_folder(rid, f)
            end
            for p in snap.1 do
                self.store.add_release_page(rid, p)
            end
            rid
        end)
        self.store.log(actor, "release.create", "release", id, "Version {name} créée ({snap.1.len()} pages)", Json.object({ "label": Json.string(name), "pages": Json.number(snap.1.len() as float), "qlang": Json.string(qlang_version.trim()) }))
        if publish then
            self.publish(id, actor)
        end
        Ok(id)
    end

    --" Makes a release the one that the public site serves. Going back to an older one is the same call: nothing is lost. --"
    public fun publish(self, id: int, actor: int?) -> Result<bool, string>
        let release = self.store.release(id)
        if release == none then
            return Err("Version introuvable.")
        end
        let before = self.store.current_release_id()
        self.store.set_current_release(id)
        let older = before != none and before != id and (self.store.release(before) ?? release).created_at > release.created_at
        self.store.log(actor, if older then "release.rollback" else "release.publish" end, "release", id, if older then "Retour à la version {release.label}" else "Version {release.label} publiée" end, Json.object({ "label": Json.string(release.label), "previous": opt_json(before) }))
        Ok(true)
    end

    public fun delete_release(self, id: int, actor: int?) -> Result<bool, string>
        let release = self.store.release(id)
        if release == none then
            return Err("Version introuvable.")
        end
        if release.current then
            return Err("La version publiée ne peut pas être supprimée : publie-en une autre d'abord.")
        end
        self.store.delete_release(id)
        self.store.log(actor, "release.delete", "release", id, "Version {release.label} supprimée", Json.object({ "label": Json.string(release.label) }))
        Ok(true)
    end

    --" Puts the pages of a release back in the working copy (as new revisions, so that nothing is lost). Pages that the release does not have are left alone. --"
    public fun restore_release(self, id: int, actor: int?) -> Result<int, string>
        let release = self.store.release(id)
        if release == none then
            return Err("Version introuvable.")
        end
        let touched = 0
        for sp in self.store.release_pages(id) do
            let parts = sp.path.split("/")
            let folder: int? = none
            let k = 0
            while k < parts.len() - 1 do
                let found = self.store.find_folder(sp.locale, folder, parts[k])
                if found == none then
                    let title = self.release_folder_title(id, sp.locale, parts.slice(0, k + 1).join("/"), parts[k])
                    folder = self.store.create_folder(sp.locale, folder, parts[k], title)
                else
                    folder = found.id
                end
                k = k + 1
            end
            let slug = parts[parts.len() - 1]
            let page = self.store.find_page(sp.locale, folder, slug)
            if page == none then
                self.create_page(sp.locale, folder, sp.title, slug, sp.markdown, "restore", actor)
                touched = touched + 1
            elseif page.unwrap().markdown != sp.markdown or page.unwrap().title != sp.title then
                self.edit_page(page.id, sp.title, sp.markdown, "Retour à la version {release.label}", "restore", actor)
                touched = touched + 1
            end
        end
        self.store.log(actor, "release.restore", "release", id, "Copie de travail rétablie depuis la version {release.label} ({touched} pages)", Json.object({ "label": Json.string(release.label), "pages": Json.number(touched as float) }))
        Ok(touched)
    end

    fun release_folder_title(self, release_id: int, locale: string, path: string, fallback: string) -> string
        for f in self.store.release_folders(release_id) do
            if f.locale == locale and f.path == path then
                return f.title
            end
        end
        fallback
    end

    --" What differs between the working copy and the published release: new, changed and deleted pages. --"
    public fun pending_changes(self) -> array<Change>
        let out: array<Change> = []
        let current = self.store.current_release_id()
        let snap = self.snapshot()
        let published: map<string, SnapPage> = {}
        if current != none then
            for sp in self.store.release_pages(current) do
                published["{sp.locale}:{sp.path}"] = sp
            end
        end
        let seen: map<string, bool> = {}
        for p in snap.1 do
            let key = "{p.locale}:{p.path}"
            seen[key] = true
            let old = published[key]
            if old == none then
                out.push(Change { kind: "new", locale: p.locale, path: p.path, title: p.title })
            elseif old.unwrap().markdown != p.markdown or old.unwrap().title != p.title then
                out.push(Change { kind: "changed", locale: p.locale, path: p.path, title: p.title })
            end
        end
        for key in published.keys() do
            if seen[key] == none then
                let old = published[key].unwrap()
                out.push(Change { kind: "deleted", locale: old.locale, path: old.path, title: old.title })
            end
        end
        out
    end
end

fun opt_json(v: int?) -> Json
    if v == none then Json.null() else Json.number(v as float) end
end

fun diff_stats(old: string, new: string) -> Stats
    stats(diff(old, new))
end

export Docs, Rendered, Change, LOCALES, slug_of, is_slug
