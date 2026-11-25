import "@std/web/app.q" as web
import Docs from "../Docs/Docs.q"
import AuditEntry, AuditFilter from "../Docs/Models.q"
import action_label from "./Labels.q"
import Views from "./Views.q"
import render, session_of, when, int_of from "./Support.q"

let PER_PAGE = 40
let PUBLICATIONS = ["release.publish", "release.rollback", "release.unpublish"]

struct AuditRow
    public at: string
    public user: string
    public action: string
    public action_key: string
    public summary: string
    public stats: string
    public link: string
    public has_link: bool
    public link_label: string
    public kind_row: bool
    public kind_toggle: bool
    public marker: bool
    public group: string
    public hidden: string
    public expanded: string
    public label: string
end

struct Choice
    public value: string
    public label: string
    public selected: string
end

struct AuditData
    public rows: array<AuditRow>
    public users: array<Choice>
    public actions: array<Choice>
    public since: string
    public until: string
    public query: string
    public total: int
    public filtered: bool
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

--" Midnight (UTC) of a `YYYY-MM-DD` day, in milliseconds; none when the text is not a date. --"
fun day_ms(text: string?) -> int?
    if text == none or text.trim() == "" then
        return none
    end
    let d = datetime.parse(text.trim())
    if d == none then none else d.unix() * 1000 end
end

--" The end of a day given by its start: the next midnight. --"
fun end_of(start: int?) -> int?
    if start == none then none else start + 86400000 end
end

fun toggle_row(id: string, count: int, label: string, open: bool) -> AuditRow
    AuditRow { at: "", user: "", action: "", action_key: "", summary: "", stats: "", link: "", has_link: false, link_label: "", kind_row: false, kind_toggle: true, marker: false, group: id, hidden: "", expanded: if open then "true" else "false" end, label: "{count} {label}" }
end

--" Closes a run of changes: a line to fold it, then the changes, hidden unless the run is open. --"
fun flush(out: array<AuditRow>, run: array<AuditRow>, id: string, label: string, open: bool)
    if run.is_empty() then
        return
    end
    out.push(toggle_row(id, run.len(), label, open))
    for r in run do
        r.group = id
        r.hidden = if open then "" else "hidden" end
        out.push(r)
    end
end

--" Puts the changes made between two publications under a line that folds them. The newest run, not published yet, stays open. --"
fun grouped(rows: array<AuditRow>) -> array<AuditRow>
    let out: array<AuditRow> = []
    let run: array<AuditRow> = []
    let n = 0
    for r in rows do
        if r.marker then
            flush(out, run, "g{n}", if n == 0 then "changement(s) pas encore publié(s)" else "changement(s) dans cette version" end, n == 0)
            run.clear()
            n += 1
            out.push(r)
        else
            run.push(r)
        end
    end
    flush(out, run, "g{n}", if n == 0 then "changement(s) pas encore publié(s)" else "changement(s) dans cette version" end, n == 0)
    out
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
    AuditRow { at: when(e.created_at), user: if e.user == "" then "—" else e.user end, action: action_label(e.action), action_key: e.action, summary: e.summary, stats: stats, link: link, has_link: link != "", link_label: label, kind_row: true, kind_toggle: false, marker: PUBLICATIONS.contains(e.action), group: "", hidden: "", expanded: "", label: "" }
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
    public fun show(self, req: Request, #[web.Query] type: string?, #[web.Query] page: string?, #[web.Query] user: string?, #[web.Query] action: string?, #[web.Query("from")] since: string?, #[web.Query("to")] until: string?) -> Response
        let kind = if ["page", "folder", "release", "account", "package"].contains(type ?? "") then type ?? "" else "" end
        let day_start = day_ms(since)
        let day_end = day_ms(until)
        let wanted_action = action ?? ""
        let filter = AuditFilter { kind: kind, user_id: int_of(user), action: wanted_action, since: day_start, until: end_of(day_end) }
        let total = self.docs.store.audit_total(filter)
        let pages = if total == 0 then 1 else (total + PER_PAGE - 1) // PER_PAGE end
        let current = int_of(page) ?? 1
        if current < 1 then
            current = 1
        end
        if current > pages then
            current = pages
        end
        let rows = self.docs.store.audit_search(filter, PER_PAGE, (current - 1) * PER_PAGE).map(fun(e: AuditEntry) -> AuditRow row_of(e) end)
        let narrowed = kind != "" or filter.user_id != none or wanted_action != "" or day_start != none or day_end != none
        let shown = if narrowed then rows else grouped(rows) end
        let users: array<Choice> = [Choice { value: "", label: "Tout le monde", selected: "" }]
        for a in self.docs.store.accounts() do
            users.push(Choice { value: "{a.id}", label: a.login, selected: if filter.user_id == a.id then "selected" else "" end })
        end
        let actions: array<Choice> = [Choice { value: "", label: "Toutes les actions", selected: "" }]
        for key in self.docs.store.audit_actions() do
            actions.push(Choice { value: key, label: action_label(key), selected: if key == wanted_action then "selected" else "" end })
        end
        let since_text = if day_start == none then "" else (since ?? "") end
        let until_text = if day_end == none then "" else (until ?? "") end
        let query = "type={kind}&user={user ?? ""}&action={wanted_action}&from={since_text}&to={until_text}"
        let data = AuditData {
            rows: shown, users: users, actions: actions, since: since_text, until: until_text, query: query, total: total,
            filtered: filter.user_id != none or wanted_action != "" or day_start != none or day_end != none,
            kind: kind, kind_all: kind == "", kind_page: kind == "page", kind_folder: kind == "folder", kind_release: kind == "release", kind_account: kind == "account", kind_package: kind == "package", page: current, pages: pages, prev: current - 1, next: current + 1,
            has_prev: current > 1, has_next: current < pages, csrf: session_of(req).csrf_field(),
        }
        render(self.docs, self.views, req, "audit", "Journal", "audit", Json.of(data))
    end
end
