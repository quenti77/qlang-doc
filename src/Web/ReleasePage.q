import "@std/web/app.q" as web
import Docs, Change from "../Docs/Docs.q"
import Release, SnapPage from "../Docs/Models.q"
import Views from "./Views.q"
import render, session_of, uid_of, ok, fail, when, form_of from "./Support.q"

struct ReleaseRow
    public id: int
    public label: string
    public qlang_version: string
    public note: string
    public author: string
    public at: string
    public pages: int
    public current: bool
    public changes: array<PendingRow>
    public change_count: int
end

struct PendingRow
    public label: string
    public locale: string
    public path: string
    public title: string
end

struct ReleasesData
    public releases: array<ReleaseRow>
    public has_releases: bool
    public pending: array<PendingRow>
    public has_pending: bool
    public pending_count: int
    public suggestion: string
    public csrf: string
end

struct PageLine
    public locale: string
    public path: string
    public title: string
    public lines: int
end

struct ReleaseData
    public release: ReleaseRow
    public pages: array<PageLine>
    public csrf: string
end

fun change_rows(changes: array<Change>) -> array<PendingRow>
    changes.map(fun(c: Change) -> PendingRow
        PendingRow { label: if c.kind == "new" then "Nouvelle" elseif c.kind == "deleted" then "Supprimée" else "Modifiée" end, locale: c.locale, path: c.path, title: c.title }
    end)
end

fun row_of(r: Release) -> ReleaseRow
    ReleaseRow { id: r.id, label: r.label, qlang_version: r.qlang_version, note: r.note, author: if r.author == "" then "—" else r.author end, at: when(r.created_at), pages: r.pages, current: r.current, changes: [], change_count: 0 }
end

--" Releases: a frozen copy of the documentation tied to a qlang version. The public site serves the published one; going back to an older one is one click. --"
#[web.Controller("/admin/releases")]
#[web.Guard("auth")]
struct ReleasePage
    docs: Docs
    views: Views
end

impl ReleasePage
    #[web.Get("")]
    public fun list(self, req: Request) -> Response
        let releases = self.docs.store.releases().map(fun(r: Release) -> ReleaseRow
            let row = row_of(r)
            row.changes = change_rows(self.docs.release_changes(r.id))
            row.change_count = row.changes.len()
            row
        end)
        let pending = change_rows(self.docs.pending_changes())
        let data = ReleasesData {
            releases: releases, has_releases: not releases.is_empty(), pending: pending, has_pending: not pending.is_empty(), pending_count: pending.len(),
            suggestion: if releases.is_empty() then "" else releases[0].qlang_version end, csrf: session_of(req).csrf_field(),
        }
        render(self.docs, self.views, req, "releases", "Versions", "releases", Json.of(data))
    end

    #[web.Get("/:id")]
    public fun show(self, req: Request, #[web.Path] id: int) -> Response
        let release = self.docs.store.release(id)
        if release == none then
            return Response.not_found()
        end
        let pages = self.docs.store.release_pages(id).map(fun(p: SnapPage) -> PageLine
            PageLine { locale: p.locale, path: p.path, title: p.title, lines: p.markdown.split("\n").len() }
        end)
        render(self.docs, self.views, req, "release", "Version {release.label}", "releases", Json.of(ReleaseData { release: row_of(release), pages: pages, csrf: session_of(req).csrf_field() }))
    end

    #[web.Post("")]
    #[web.Guard("admin")]
    public fun create(self, req: Request) -> Response
        let form = form_of(req)
        let made = self.docs.create_release(form["label"] ?? "", form["qlang_version"] ?? "", form["note"] ?? "", form["publish"] == "1", uid_of(req))
        if made.is_err() then
            fail(req, made.unwrap_err())
            return Response.redirect("/admin/releases")
        end
        ok(req, if form["publish"] == "1" then "Version créée et publiée." else "Version créée (pas encore publiée)." end)
        Response.redirect("/admin/releases/{made.unwrap()}")
    end

    #[web.Post("/:id/publish")]
    #[web.Guard("admin")]
    public fun publish(self, req: Request, #[web.Path] id: int) -> Response
        let done = self.docs.publish(id, uid_of(req))
        if done.is_err() then fail(req, done.unwrap_err()) else ok(req, "La version est publiée.") end
        Response.redirect("/admin/releases")
    end

    #[web.Post("/unpublish")]
    #[web.Guard("admin")]
    public fun unpublish(self, req: Request) -> Response
        let done = self.docs.unpublish(uid_of(req))
        if done.is_err() then fail(req, done.unwrap_err()) else ok(req, "La documentation est dépubliée.") end
        Response.redirect("/admin/releases")
    end

    #[web.Post("/:id/restore")]
    #[web.Guard("admin")]
    public fun restore(self, req: Request, #[web.Path] id: int) -> Response
        let done = self.docs.restore_release(id, uid_of(req))
        if done.is_err() then
            fail(req, done.unwrap_err())
        else
            ok(req, "Copie de travail rétablie : {done.unwrap()} page(s) touchée(s), chacune avec une nouvelle révision.")
        end
        Response.redirect("/admin/releases/{id}")
    end

    #[web.Post("/:id/delete")]
    #[web.Guard("admin")]
    public fun delete(self, req: Request, #[web.Path] id: int) -> Response
        let done = self.docs.delete_release(id, uid_of(req))
        if done.is_err() then fail(req, done.unwrap_err()) else ok(req, "Version supprimée.") end
        Response.redirect("/admin/releases")
    end
end
