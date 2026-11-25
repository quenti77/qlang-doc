import "@std/web/app.q" as web
import Docs from "../Docs/Docs.q"
import Section, Folder from "../Docs/Models.q"
import flatten, folder_paths from "../Docs/Tree.q"
import Item from "../Docs/Tree.q"
import Views from "./Views.q"
import Choice, folder_choices from "./Choices.q"
import render, session_of, uid_of, ok, fail, when, form_of, int_of, locale_of, back from "./Support.q"

struct TreeRow
    public is_folder: bool
    public id: int
    public title: string
    public slug: string
    public path: string
    public style: string
    public revision: int
    public updated: string
    public is_root: bool
    public pick: string
    public sections: array<SectionOption>
end

--" A section as an option of a `<select>`, and as a tab. --"
struct SectionOption
    public value: string
    public label: string
    public selected: string
    public url: string
    public current: bool
end

--" Where the selection can go: for each section, its top, then its folders. --"
struct TargetGroup
    public label: string
    public slug: string
    public selected: string
    public options: array<Choice>
end

struct TreeData
    public locale: string
    public is_fr: bool
    public is_en: bool
    public other: string
    public rows: array<TreeRow>
    public empty: bool
    public folders: array<Choice>
    public targets: array<TargetGroup>
    public tabs: array<SectionOption>
    public section: string
    public section_title: string
    public section_url: string
    public choices: array<SectionOption>
    public csrf: string
end

fun options_of(all: array<Section>, selected: string, locale: string) -> array<SectionOption>
    all.map(fun(x: Section) -> SectionOption
        SectionOption { value: x.slug, label: x.title, selected: if x.slug == selected then "selected" else "" end, url: "/admin/docs?locale={locale}&section={x.slug}", current: x.slug == selected }
    end)
end

fun targets_of(all: array<Section>, folders: array<Folder>, current: string) -> array<TargetGroup>
    let paths = folder_paths(folders)
    let roots: map<string, string> = {}
    for f in folders do
        if f.parent_id == none then
            roots[f.slug] = f.section
        end
    end
    all.map(fun(s: Section) -> TargetGroup
        let options: array<Choice> = []
        for f in folders do
            let path = paths[f.id] ?? f.slug
            if roots[path.split("/")[0]] == s.slug then
                options.push(Choice { value: "{f.id}", label: path.replace("/", " / "), selected: false })
            end
        end
        TargetGroup { label: s.title, slug: s.slug, selected: if s.slug == current then "selected" else "" end, options: options.sorted_by(fun(a: Choice, b: Choice) -> int if a.label < b.label then -1 elseif a.label > b.label then 1 else 0 end end) }
    end)
end

--" The tree of the documentation: first a section, then its folders and pages, which can be created, renamed, moved, reordered and deleted. --"
#[web.Controller("/admin")]
#[web.Guard("auth")]
struct TreePage
    docs: Docs
    views: Views
end

fun form_values(req: Request) -> map<string, array<string>>
    let all = req.form_all()
    if all.is_ok() then all.unwrap() else {} end
end

--" The parent of each folder, 0 for a folder at the root. --"
fun parents_of(folders: array<Folder>) -> map<int, int>
    let parents: map<int, int> = {}
    for f in folders do
        parents[f.id] = f.parent_id ?? 0
    end
    parents
end

--" The ids of the folders among the picked items (`f12` is a folder, `p7` a page). --"
fun picked_folders(picks: array<string>) -> map<int, bool>
    let picked: map<int, bool> = {}
    for p in picks do
        if p.starts_with("f") then
            picked[(p.substring(1, p.len()).to_int() ?? 0)] = true
        end
    end
    picked
end

impl TreePage
    #[web.Get("/docs")]
    public fun show(self, req: Request, #[web.Query] locale: string?, #[web.Query] section: string?) -> Response
        let lang = locale_of(locale)
        let all = self.docs.store.sections()
        let wanted = section ?? ""
        let chosen = if all.filter(fun(x: Section) -> bool x.slug == wanted end).is_empty() then self.docs.default_section() else wanted end
        let title = all.filter(fun(x: Section) -> bool x.slug == chosen end).map(fun(x: Section) -> string x.title end)
        let folders = self.docs.store.folders(lang)
        let roots: map<string, string> = {}
        for f in folders do
            if f.parent_id == none then
                roots[f.slug] = f.section
            end
        end
        let first = self.docs.default_section()
        let items = flatten(folders, self.docs.store.page_rows(lang)).filter(fun(i: Item) -> bool
            let top = i.path.split("/")[0]
            (if i.path.contains("/") or i.kind == "folder" then roots[top] ?? first else first end) == chosen
        end)
        let rows = items.map(fun(i: Item) -> TreeRow
            let root = i.kind == "folder" and i.depth == 0
            TreeRow {
                is_folder: i.kind == "folder", id: i.id, title: i.title, slug: i.slug, path: i.path, style: "padding-left:{i.depth * 1.5 + 0.75}rem", revision: i.revision, updated: when(i.updated_at),
                is_root: root, pick: "{if i.kind == "folder" then "f" else "p" end}{i.id}", sections: options_of(all, chosen, lang),
            }
        end)
        let data = TreeData {
            locale: lang, is_fr: lang == "fr", is_en: lang == "en", other: if lang == "fr" then "en" else "fr" end, rows: rows, empty: rows.is_empty(),
            folders: folder_choices(self.docs, lang, none), targets: targets_of(all, folders, chosen), tabs: options_of(all, chosen, lang), section: chosen, section_title: if title.is_empty() then chosen else title[0] end,
            section_url: "/admin/docs?locale={lang}&section={chosen}", choices: options_of(all, chosen, lang), csrf: session_of(req).csrf_field(),
        }
        render(self.docs, self.views, req, "tree", "Documentation", "docs", Json.of(data))
    end

    fun done(self, req: Request, result: Result<bool, string>, message: string, locale: string) -> Response
        if result.is_err() then
            fail(req, result.unwrap_err())
        else
            ok(req, message)
        end
        back(req, "/admin/docs?locale={locale}")
    end

    #[web.Post("/folders")]
    public fun create(self, req: Request) -> Response
        let form = form_of(req)
        let locale = locale_of(form["locale"])
        let made = self.docs.create_folder(locale, int_of(form["parent"]), form["title"] ?? "", form["slug"] ?? "", uid_of(req))
        if made.is_err() then
            return self.done(req, Err(made.unwrap_err()), "", locale)
        end
        if int_of(form["parent"]) == none and (form["section"] ?? "") != "" then
            self.docs.set_section(made.unwrap(), form["section"] ?? "", uid_of(req))
        end
        self.done(req, Ok(true), "Dossier créé.", locale)
    end

    --" Moves one picked item (`f12` is a folder, `p7` a page). A folder dropped at the root of a section goes into that section. --"
    fun move_one(self, pick: string, id: int, holder: int, target: int?, dest: string, first: string, actor: int?) -> Result<bool, string>
        let is_folder = pick.starts_with("f")
        if not is_folder and target == none and dest != first then
            return Err("une page ne peut pas être à la racine de cette section : choisis un dossier")
        end
        if is_folder and target == none and holder == 0 then
            return self.docs.set_section(id, dest, actor)
        end
        let done: Result<bool, string> = if is_folder then self.docs.move_folder(id, target, actor) else self.docs.move_page(id, target, actor) end
        if done.is_ok() and is_folder and target == none and dest != "" then
            self.docs.set_section(id, dest, actor)
        end
        done
    end

    #[web.Post("/bulk-move")]
    public fun bulk_move(self, req: Request) -> Response
        let form = form_values(req)
        let one = fun(key: string) -> string
            let v = form[key]
            if v == none or v.is_empty() then "" else v[0] end
        end
        let locale = locale_of(one("locale"))
        let target = int_of(one("to"))
        let section = one("section")
        let dest = if target == none then one("dest") else "" end
        let first = self.docs.default_section()
        let picks = form["pick"] ?? []
        let folders = self.docs.store.folders(locale)
        let parents = parents_of(folders)
        let picked = picked_folders(picks)
        let moved = 0
        let problems: array<string> = []
        let actor = uid_of(req)
        for p in picks do
            let id = p.substring(1, p.len()).to_int() ?? 0
            let held = self.docs.store.page(id)
            let holder = if p.starts_with("f") then parents[id] ?? 0 elseif held == none then 0 else held.folder_id ?? 0 end
            if self.under_picked(holder, parents, picked) then
                continue
            end
            let done = self.move_one(p, id, holder, target, dest, first, actor)
            if done.is_err() then
                problems.push(done.unwrap_err())
            else
                moved += 1
            end
        end
        if moved > 0 then
            ok(req, "{moved} élément(s) déplacé(s).")
        end
        if not problems.is_empty() then
            fail(req, "{problems.len()} refusé(s) : {problems[0]}")
        end
        if moved == 0 and problems.is_empty() then
            fail(req, "Rien n'est sélectionné.")
        end
        back(req, "/admin/docs?locale={locale}&section={section}")
    end

    --" True when a folder above `holder` (0 for the top) is picked too: it moves along with its content, so the content is left alone. --"
    fun under_picked(self, holder: int, parents: map<int, int>, picked: map<int, bool>) -> bool
        let current = holder
        let guard = 0
        while current != 0 and guard < 50 do
            if picked[current] == true then
                return true
            end
            current = parents[current] ?? 0
            guard += 1
        end
        false
    end

    #[web.Post("/sections")]
    public fun create_section(self, req: Request) -> Response
        let form = form_of(req)
        let made = self.docs.create_section(form["title"] ?? "", form["slug"] ?? "", uid_of(req))
        let locale = locale_of(form["locale"])
        if made.is_err() then
            fail(req, made.unwrap_err())
            return back(req, "/admin/docs?locale={locale}")
        end
        ok(req, "Section créée.")
        Response.redirect("/admin/docs?locale={locale}&section={made.unwrap()}")
    end

    #[web.Post("/sections/:slug")]
    public fun rename_section(self, req: Request, #[web.Path] slug: string) -> Response
        let form = form_of(req)
        self.done(req, self.docs.rename_section(slug, form["title"] ?? "", uid_of(req)), "Section renommée.", locale_of(form["locale"]))
    end

    #[web.Post("/sections/:slug/delete")]
    public fun delete_section(self, req: Request, #[web.Path] slug: string) -> Response
        let locale = locale_of(form_of(req)["locale"])
        let done = self.docs.delete_section(slug, uid_of(req))
        if done.is_err() then
            fail(req, done.unwrap_err())
            return back(req, "/admin/docs?locale={locale}")
        end
        ok(req, "Section supprimée.")
        Response.redirect("/admin/docs?locale={locale}")
    end

    #[web.Post("/folders/:id/section")]
    public fun section(self, req: Request, #[web.Path] id: int) -> Response
        let folder = self.docs.store.folder(id)
        let locale = if folder == none then "fr" else folder.locale end
        self.done(req, self.docs.set_section(id, form_of(req)["section"] ?? "", uid_of(req)), "Section modifiée.", locale)
    end

    #[web.Post("/folders/:id")]
    public fun update(self, req: Request, #[web.Path] id: int) -> Response
        let form = form_of(req)
        let folder = self.docs.store.folder(id)
        let locale = if folder == none then "fr" else folder.locale end
        self.done(req, self.docs.update_folder(id, form["title"] ?? "", form["slug"] ?? "", uid_of(req)), "Dossier modifié.", locale)
    end

    #[web.Post("/folders/:id/move")]
    public fun move(self, req: Request, #[web.Path] id: int) -> Response
        let folder = self.docs.store.folder(id)
        let locale = if folder == none then "fr" else folder.locale end
        self.done(req, self.docs.move_folder(id, int_of(form_of(req)["to"]), uid_of(req)), "Dossier déplacé.", locale)
    end

    #[web.Post("/folders/:id/delete")]
    public fun delete(self, req: Request, #[web.Path] id: int) -> Response
        let folder = self.docs.store.folder(id)
        let locale = if folder == none then "fr" else folder.locale end
        self.done(req, self.docs.delete_folder(id, uid_of(req)), "Dossier supprimé.", locale)
    end

    #[web.Post("/shift")]
    public fun shift(self, req: Request) -> Response
        let form = form_of(req)
        let kind = form["kind"] ?? ""
        let id = int_of(form["id"]) ?? 0
        let direction = if form["dir"] == "up" then -1 else 1 end
        let locale = locale_of(form["locale"])
        self.done(req, self.docs.shift(kind, id, direction, uid_of(req)), "Ordre modifié.", locale)
    end
end
