import "@std/web/app.q" as web
import "@std/web/session.q" as sessions
import Docs from "../Docs/Docs.q"
import diff, stats, hunks from "../Docs/Diff.q"
import folder_paths, page_path from "../Docs/Tree.q"
import Views from "./Views.q"
import Choice, folder_choices from "./Choices.q"
import render, session_of, uid_of, ok, fail, when, form_of, int_of, locale_of from "./Support.q"

struct NewData
    public locale: string
    public title: string
    public slug: string
    public markdown: string
    public folders: array<Choice>
    public csrf: string
end

struct EditData
    public id: int
    public title: string
    public slug: string
    public markdown: string
    public html: string
    public locale: string
    public path: string
    public revision: int
    public updated: string
    public folders: array<Choice>
    public csrf: string
    public csrf_token: string
end

struct RevisionRow
    public number: int
    public title: string
    public author: string
    public at: string
    public summary: string
    public source: string
    public added: int
    public removed: int
    public has_prev: bool
    public prev: int
    public is_current: bool
end

struct HistoryData
    public id: int
    public title: string
    public revisions: array<RevisionRow>
    public csrf: string
end

struct DiffRow
    public gap: bool
    public add: bool
    public del: bool
    public old_no: string
    public new_no: string
    public text: string
end

struct DiffData
    public id: int
    public title: string
    public older: int
    public newer: int
    public added: int
    public removed: int
    public same: bool
    public rows: array<DiffRow>
    public csrf: string
end

fun source_label(source: string) -> string
    if source == "import" then "import"
    elseif source == "restore" then "retour"
    else "édition" end
end

fun number_text(n: int) -> string
    if n <= 0 then "" else "{n}" end
end

--" Creating, editing, moving and deleting pages; their history and the diff between two revisions. --"
#[web.Controller("/admin")]
#[web.Guard("auth")]
struct PagePages
    docs: Docs
    views: Views
end

impl PagePages
    #[web.Get("/new-page")]
    public fun new_form(self, req: Request, #[web.Query] locale: string?, #[web.Query] folder: string?) -> Response
        let lang = locale_of(locale)
        let session = session_of(req)
        let data = NewData {
            locale: lang, title: session.old("title") ?? "", slug: session.old("slug") ?? "", markdown: session.old("markdown") ?? "",
            folders: folder_choices(self.docs, lang, int_of(folder)), csrf: session.csrf_field(),
        }
        render(self.docs, self.views, req, "page_form", "Nouvelle page", "docs", Json.of(data))
    end

    #[web.Post("/pages")]
    public fun create(self, req: Request) -> Response
        let form = form_of(req)
        let locale = locale_of(form["locale"])
        let made = self.docs.create_page(locale, int_of(form["folder"]), form["title"] ?? "", form["slug"] ?? "", form["markdown"] ?? "", "edit", uid_of(req))
        if made.is_err() then
            session_of(req).flash_input({ "title": form["title"] ?? "", "slug": form["slug"] ?? "", "markdown": form["markdown"] ?? "" })
            fail(req, made.unwrap_err())
            return Response.redirect("/admin/new-page?locale={locale}&folder={form["folder"] ?? ""}")
        end
        ok(req, "Page créée.")
        Response.redirect("/admin/pages/{made.unwrap()}")
    end

    #[web.Get("/pages/:id")]
    public fun edit(self, req: Request, #[web.Path] id: int) -> Response
        let page = self.docs.store.page(id)
        if page == none then
            return Response.not_found()
        end
        let session = session_of(req)
        let paths = folder_paths(self.docs.store.folders(page.locale))
        let data = EditData {
            id: page.id, title: page.title, slug: page.slug, markdown: page.markdown, html: page.html, locale: page.locale,
            path: page_path(page.folder_id, page.slug, paths), revision: page.revision, updated: when(page.updated_at),
            folders: folder_choices(self.docs, page.locale, page.folder_id), csrf: session.csrf_field(), csrf_token: session.csrf_token(),
        }
        render(self.docs, self.views, req, "page_edit", page.title, "docs", Json.of(data))
    end

    #[web.Post("/pages/:id")]
    public fun save(self, req: Request, #[web.Path] id: int) -> Response
        let form = form_of(req)
        let saved = self.docs.edit_page(id, form["title"] ?? "", form["markdown"] ?? "", form["summary"] ?? "", "edit", uid_of(req))
        if saved.is_err() then
            fail(req, saved.unwrap_err())
        else
            ok(req, "Page enregistrée (révision {saved.unwrap()}).")
        end
        Response.redirect("/admin/pages/{id}")
    end

    #[web.Post("/pages/:id/rename")]
    public fun rename(self, req: Request, #[web.Path] id: int) -> Response
        let done = self.docs.rename_page(id, form_of(req)["slug"] ?? "", uid_of(req))
        if done.is_err() then fail(req, done.unwrap_err()) else ok(req, "Adresse modifiée.") end
        Response.redirect("/admin/pages/{id}")
    end

    #[web.Post("/pages/:id/move")]
    public fun move(self, req: Request, #[web.Path] id: int) -> Response
        let done = self.docs.move_page(id, int_of(form_of(req)["to"]), uid_of(req))
        if done.is_err() then fail(req, done.unwrap_err()) else ok(req, "Page déplacée.") end
        Response.redirect("/admin/pages/{id}")
    end

    #[web.Post("/pages/:id/delete")]
    public fun delete(self, req: Request, #[web.Path] id: int) -> Response
        let page = self.docs.store.page(id)
        let locale = if page == none then "fr" else page.locale end
        let done = self.docs.delete_page(id, uid_of(req))
        if done.is_err() then
            fail(req, done.unwrap_err())
            return Response.redirect("/admin/docs?locale={locale}")
        end
        ok(req, "Page supprimée. Son dernier texte reste dans le journal.")
        Response.redirect("/admin/docs?locale={locale}")
    end

    --" The HTML of a Markdown text, for the preview of the editor. --"
    #[web.Post("/preview")]
    public fun preview(self, req: Request) -> Response
        Response.html(self.docs.render(form_of(req)["markdown"] ?? "").html)
    end

    #[web.Get("/pages/:id/history")]
    public fun history(self, req: Request, #[web.Path] id: int) -> Response
        let page = self.docs.store.page(id)
        if page == none then
            return Response.not_found()
        end
        let revisions = self.docs.store.revisions(id)
        let rows: array<RevisionRow> = []
        let k = 0
        while k < revisions.len() do
            let r = revisions[k]
            let before = if k + 1 < revisions.len() then revisions[k + 1].markdown else "" end
            let s = if k + 1 < revisions.len() then stats(diff(before, r.markdown)) else stats(diff("", r.markdown)) end
            rows.push(RevisionRow {
                number: r.number, title: r.title, author: if r.author == "" then "—" else r.author end, at: when(r.created_at), summary: r.summary,
                source: source_label(r.source), added: s.added, removed: s.removed, has_prev: k + 1 < revisions.len(),
                prev: if k + 1 < revisions.len() then revisions[k + 1].number else 0 end, is_current: r.number == page.revision,
            })
            k = k + 1
        end
        render(self.docs, self.views, req, "history", "Historique · {page.title}", "docs", Json.of(HistoryData { id: id, title: page.title, revisions: rows, csrf: session_of(req).csrf_field() }))
    end

    #[web.Get("/pages/:id/diff")]
    public fun compare(self, req: Request, #[web.Path] id: int, #[web.Query("from")] older: string?, #[web.Query("to")] newer: string?) -> Response
        let page = self.docs.store.page(id)
        if page == none then
            return Response.not_found()
        end
        let a = self.docs.store.revision(id, int_of(older) ?? 0)
        let b = self.docs.store.revision(id, int_of(newer) ?? page.revision)
        if a == none or b == none then
            return Response.not_found()
        end
        let lines = diff(a.markdown, b.markdown)
        let s = stats(lines)
        let rows: array<DiffRow> = []
        for group in hunks(lines, 3) do
            if not rows.is_empty() then
                rows.push(DiffRow { gap: true, add: false, del: false, old_no: "", new_no: "", text: "" })
            end
            for l in group do
                rows.push(DiffRow { gap: false, add: l.kind == "add", del: l.kind == "del", old_no: number_text(l.old_no), new_no: number_text(l.new_no), text: l.text })
            end
        end
        let data = DiffData {
            id: id, title: page.title, older: a.number, newer: b.number, added: s.added, removed: s.removed,
            same: s.added == 0 and s.removed == 0, rows: rows, csrf: session_of(req).csrf_field(),
        }
        render(self.docs, self.views, req, "diff", "Différences · {page.title}", "docs", Json.of(data))
    end

    #[web.Post("/pages/:id/restore")]
    public fun restore(self, req: Request, #[web.Path] id: int) -> Response
        let number = int_of(form_of(req)["number"]) ?? 0
        let done = self.docs.restore_revision(id, number, uid_of(req))
        if done.is_err() then
            fail(req, done.unwrap_err())
        else
            ok(req, "Révision {number} rétablie (nouvelle révision {done.unwrap()}).")
        end
        Response.redirect("/admin/pages/{id}")
    end
end
