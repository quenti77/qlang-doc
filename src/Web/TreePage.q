import "@std/web/app.q" as web
import Docs from "../Docs/Docs.q"
import flatten from "../Docs/Tree.q"
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
    public section_label: string
    public sel_doc: string
    public sel_ref: string
end

struct TreeData
    public locale: string
    public is_fr: bool
    public is_en: bool
    public other: string
    public rows: array<TreeRow>
    public empty: bool
    public folders: array<Choice>
    public csrf: string
end

--" The tree of the documentation, in folders: create, rename, move, reorder and delete. --"
#[web.Controller("/admin")]
#[web.Guard("auth")]
struct TreePage
    docs: Docs
    views: Views
end

impl TreePage
    #[web.Get("/docs")]
    public fun show(self, req: Request, #[web.Query] locale: string?) -> Response
        let lang = locale_of(locale)
        let sections: map<int, string> = {}
        for f in self.docs.store.folders(lang) do
            sections[f.id] = f.section
        end
        let items = flatten(self.docs.store.folders(lang), self.docs.store.page_rows(lang))
        let rows = items.map(fun(i: Item) -> TreeRow
            let section = sections[i.id] ?? "doc"
            let root = i.kind == "folder" and i.depth == 0
            TreeRow {
                is_folder: i.kind == "folder", id: i.id, title: i.title, slug: i.slug, path: i.path, style: "padding-left:{i.depth * 1.5 + 0.75}rem", revision: i.revision, updated: when(i.updated_at),
                is_root: root, section_label: if section == "ref" then "Référence" else "Documentation" end, sel_doc: if section == "doc" then "selected" else "" end, sel_ref: if section == "ref" then "selected" else "" end,
            }
        end)
        let data = TreeData {
            locale: lang, is_fr: lang == "fr", is_en: lang == "en", other: if lang == "fr" then "en" else "fr" end, rows: rows, empty: rows.is_empty(),
            folders: folder_choices(self.docs, lang, none), csrf: session_of(req).csrf_field(),
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
            self.docs.set_section(made.unwrap(), form["section"] ?? "doc", uid_of(req))
        end
        self.done(req, Ok(true), "Dossier créé.", locale)
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
