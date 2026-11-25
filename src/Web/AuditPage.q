import "@std/web/app.q" as web
import Docs from "../Docs/Docs.q"
import AuditEntry from "../Docs/Models.q"
import Views from "./Views.q"
import render, session_of, when, int_of from "./Support.q"

let PER_PAGE = 40

struct AuditRow
    public at: string
    public user: string
    public action: string
    public summary: string
    public stats: string
    public link: string
    public has_link: bool
    public link_label: string
end

struct AuditData
    public rows: array<AuditRow>
    public kind: string
    public kind_all: bool
    public kind_page: bool
    public kind_folder: bool
    public kind_release: bool
    public kind_account: bool
    public kind_package: bool
    public page: int
    public pages: int
    public prev: int
    public next: int
    public has_prev: bool
    public has_next: bool
    public csrf: string
end

fun number_in(data: Json, key: string) -> int?
    let v = data.get(key)
    if v == none or v.is_null() then none else v.as_number() as int end
end

--" The link that a log line offers: the diff of an edit, the page, the release. --"
fun link_of(e: AuditEntry, data: Json) -> string
    if e.entity_id == none then
        return ""
    end
    let id = e.entity_id
    if e.entity_type == "page" and e.action != "page.delete" then
        let older = number_in(data, "from")
        let newer = number_in(data, "to")
        if older != none and newer != none and (e.action == "page.edit" or e.action == "page.import" or e.action == "page.restore") then
            return "/admin/pages/{id}/diff?from={older}&to={newer}"
        end
        return "/admin/pages/{id}"
    end
    if e.entity_type == "package" and e.action != "package.delete" and e.action != "package.reject" then
        return "/admin/packages/{id}"
    end
    if e.entity_type == "release" and e.action != "release.delete" then
        return "/admin/releases/{id}"
    end
    ""
end

fun row_of(e: AuditEntry) -> AuditRow
    let parsed = Json.parse(e.data)
    let data = if parsed.is_ok() then parsed.unwrap() else Json.object({}) end
    let added = number_in(data, "added")
    let removed = number_in(data, "removed")
    let stats = if added == none or removed == none then "" else "+{added} −{removed}" end
    let link = link_of(e, data)
    let label = if link.contains("/diff") then "voir le diff" elseif link == "" then "" else "ouvrir" end
    AuditRow { at: when(e.created_at), user: if e.user == "" then "—" else e.user end, action: e.action, summary: e.summary, stats: stats, link: link, has_link: link != "", link_label: label }
end

--" The journal: who did what and when, with the size of each diff. --"
#[web.Controller("/admin")]
#[web.Guard("auth")]
struct AuditPage
    docs: Docs
    views: Views
end

impl AuditPage
    #[web.Get("/audit")]
    public fun show(self, req: Request, #[web.Query] type: string?, #[web.Query] page: string?) -> Response
        let kind = if ["page", "folder", "release", "account", "package"].contains(type ?? "") then type ?? "" else "" end
        let total = self.docs.store.audit_count(kind)
        let pages = if total == 0 then 1 else (total + PER_PAGE - 1) // PER_PAGE end
        let current = int_of(page) ?? 1
        if current < 1 then
            current = 1
        end
        if current > pages then
            current = pages
        end
        let rows = self.docs.store.audit(kind, PER_PAGE, (current - 1) * PER_PAGE).map(fun(e: AuditEntry) -> AuditRow row_of(e) end)
        let data = AuditData {
            rows: rows, kind: kind, kind_all: kind == "", kind_page: kind == "page", kind_folder: kind == "folder", kind_release: kind == "release", kind_account: kind == "account", kind_package: kind == "package", page: current, pages: pages, prev: current - 1, next: current + 1,
            has_prev: current > 1, has_next: current < pages, csrf: session_of(req).csrf_field(),
        }
        render(self.docs, self.views, req, "audit", "Journal", "audit", Json.of(data))
    end
end
