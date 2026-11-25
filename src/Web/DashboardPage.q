import "@std/web/app.q" as web
import Docs, Change from "../Docs/Docs.q"
import AuditEntry from "../Docs/Models.q"
import Views from "./Views.q"
import render, session_of, when from "./Support.q"

struct ChangeRow
    public kind: string
    public label: string
    public locale: string
    public path: string
    public title: string
end

struct ActivityRow
    public user: string
    public summary: string
    public at: string
end

struct DashboardData
    public pages: int
    public published: string
    public has_published: bool
    public changes: array<ChangeRow>
    public has_changes: bool
    public change_count: int
    public activity: array<ActivityRow>
    public csrf: string
end

--" The first page of the panel: what is published, what is waiting, what happened lately. --"
#[web.Controller("/admin")]
#[web.Guard("auth")]
struct DashboardPage
    docs: Docs
    views: Views
end

impl DashboardPage
    #[web.Get("")]
    public fun show(self, req: Request) -> Response
        let store = self.docs.store
        let count = store.page_rows("fr").len() + store.page_rows("en").len()
        let current = store.current_release_id()
        let release = if current == none then none else store.release(current) end
        let changes = self.docs.pending_changes().map(fun(c: Change) -> ChangeRow
            ChangeRow { kind: c.kind, label: if c.kind == "new" then "Nouvelle" elseif c.kind == "deleted" then "Supprimée" else "Modifiée" end, locale: c.locale, path: c.path, title: c.title }
        end)
        let activity = store.audit("", 12, 0).map(fun(a: AuditEntry) -> ActivityRow
            ActivityRow { user: if a.user == "" then "—" else a.user end, summary: a.summary, at: when(a.created_at) }
        end)
        let data = DashboardData {
            pages: count,
            published: if release == none then "" else release.label end,
            has_published: release != none,
            changes: changes,
            has_changes: not changes.is_empty(),
            change_count: changes.len(),
            activity: activity,
            csrf: session_of(req).csrf_field(),
        }
        render(self.docs, self.views, req, "dashboard", "Tableau de bord", "dashboard", Json.of(data))
    end
end
