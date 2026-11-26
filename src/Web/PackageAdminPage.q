import "@std/web/app.q" as web
import Docs from "../Docs/Docs.q"
import Package, PackageVersion from "../Registry/Models.q"
import Registry from "../Registry/Registry.q"
import Views from "./Views.q"
import render, session_of, uid_of, ok, fail, when, form_of from "./Support.q"

struct AdminPackageRow
    public id: int
    public name: string
    public git_url: string
    public description: string
    public latest: string
    public has_error: bool
    public error: string
    public waiting: bool
    public synced: string
    public removed_reason: string
end

struct AdminPackagesData
    public status: string
    public is_pending: bool
    public is_listed: bool
    public is_removed: bool
    public pending_count: int
    public rows: array<AdminPackageRow>
    public empty: bool
    public open: bool
    public csrf: string
end

struct AdminVersionRow
    public version: string
    public sha: string
    public yanked: bool
    public qlang_req: string
    public seen: string
end

struct AdminPackageData
    public id: int
    public name: string
    public git_url: string
    public status: string
    public is_pending: bool
    public is_listed: bool
    public is_removed: bool
    public description: string
    public license: string
    public latest: string
    public error: string
    public has_error: bool
    public waiting: bool
    public removed_reason: string
    public synced: string
    public versions: array<AdminVersionRow>
    public csrf: string
end

fun admin_row(p: Package) -> AdminPackageRow
    AdminPackageRow {
        id: p.id, name: p.name, git_url: p.git_url, description: p.description, latest: p.latest_version, has_error: p.sync_error != "", error: p.sync_error,
        waiting: p.sync_requested, synced: if p.synced_at > 0 then when(p.synced_at) else "jamais" end, removed_reason: p.removed_reason,
    }
end

--" The registry in the panel: the queue of proposals, the packages of the index, the ones that were withdrawn (administrators only). --"
#[web.Controller("/admin/packages")]
#[web.Guard("admin")]
struct PackageAdminPage
    docs: Docs
    views: Views
    registry: Registry
end

impl PackageAdminPage
    #[web.Get("")]
    public fun list(self, req: Request, #[web.Query] status: string?) -> Response
        let pending = self.registry.packages.count("pending")
        let chosen = if status == "listed" or status == "removed" or status == "pending" then status ?? "listed" elseif pending > 0 then "pending" else "listed" end
        let rows = self.registry.packages.packages(chosen, "", "").map(fun(p: Package) -> AdminPackageRow admin_row(p) end)
        let data = AdminPackagesData {
            status: chosen, is_pending: chosen == "pending", is_listed: chosen == "listed", is_removed: chosen == "removed", pending_count: pending,
            rows: rows, empty: rows.is_empty(), open: self.registry.options.submissions_open, csrf: session_of(req).csrf_field(),
        }
        render(self.docs, self.views, req, "admin_packages", "Paquets", "packages", Json.of(data))
    end

    #[web.Get("/:id")]
    public fun show(self, req: Request, #[web.Path] id: int) -> Response
        let p = self.registry.packages.package(id)
        if p == none then
            return Response.not_found()
        end
        let versions = self.registry.versions(id).map(fun(v: PackageVersion) -> AdminVersionRow
            AdminVersionRow { version: v.version, sha: v.commit_sha.substring(0, 8), yanked: v.yanked, qlang_req: v.qlang_req, seen: when(v.first_seen) }
        end)
        let data = AdminPackageData {
            id: p.id, name: p.name, git_url: p.git_url, status: p.status, is_pending: p.status == "pending", is_listed: p.status == "listed", is_removed: p.status == "removed",
            description: p.description, license: p.license, latest: p.latest_version, error: p.sync_error, has_error: p.sync_error != "", waiting: p.sync_requested,
            removed_reason: p.removed_reason, synced: if p.synced_at > 0 then when(p.synced_at) else "jamais" end, versions: versions, csrf: session_of(req).csrf_field(),
        }
        render(self.docs, self.views, req, "admin_package", p.name, "packages", Json.of(data))
    end

    fun answer(self, req: Request, done: Result<bool, string>, message: string, to: string) -> Response
        if done.is_err() then fail(req, done.unwrap_err()) else ok(req, message) end
        Response.redirect(to)
    end

    #[web.Post("")]
    public fun add(self, req: Request) -> Response
        let form = form_of(req)
        let made = self.registry.add(form["git"] ?? "", uid_of(req))
        if made.is_err() then
            fail(req, made.unwrap_err())
            return Response.redirect("/admin/packages?status=listed")
        end
        ok(req, "Paquet ajouté : le worker va lire son dépôt et prendre le nom de son qlang.toml.")
        Response.redirect("/admin/packages/{made.unwrap()}")
    end

    #[web.Post("/:id/approve")]
    public fun approve(self, req: Request, #[web.Path] id: int) -> Response
        self.answer(req, self.registry.approve(id, uid_of(req)), "Paquet accepté : le worker va lire son dépôt.", "/admin/packages")
    end

    #[web.Post("/:id/reject")]
    public fun reject(self, req: Request, #[web.Path] id: int) -> Response
        self.answer(req, self.registry.reject(id, uid_of(req)), "Proposition refusée.", "/admin/packages")
    end

    #[web.Post("/:id/remove")]
    public fun remove(self, req: Request, #[web.Path] id: int) -> Response
        self.answer(req, self.registry.remove(id, form_of(req)["reason"] ?? "", uid_of(req)), "Paquet retiré de l'index.", "/admin/packages/{id}")
    end

    #[web.Post("/:id/restore")]
    public fun restore(self, req: Request, #[web.Path] id: int) -> Response
        self.answer(req, self.registry.restore(id, uid_of(req)), "Paquet rétabli.", "/admin/packages/{id}")
    end

    #[web.Post("/:id/delete")]
    public fun delete(self, req: Request, #[web.Path] id: int) -> Response
        self.answer(req, self.registry.delete(id, uid_of(req)), "Paquet supprimé.", "/admin/packages?status=listed")
    end

    #[web.Post("/:id/sync")]
    public fun sync(self, req: Request, #[web.Path] id: int) -> Response
        self.answer(req, self.registry.request_sync(id), "Lecture demandée : le worker la fera à son prochain passage.", "/admin/packages/{id}")
    end

    #[web.Post("/:id/yank")]
    public fun yank(self, req: Request, #[web.Path] id: int) -> Response
        let form = form_of(req)
        self.answer(req, self.registry.yank(id, form["version"] ?? "", form["on"] == "1", uid_of(req)), "Version mise à jour.", "/admin/packages/{id}")
    end
end
