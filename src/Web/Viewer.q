import "@std/web/session.q" as sessions
import Docs from "../Docs/Docs.q"
import links from "./Sections.q"

--" Who looks at the public site, for the header: nothing for a visitor, the login and an "Admin" button for the staff. --"
struct Viewer
    public signed_in: bool
    public login: string
    public staff: bool
    public signup_open: bool
    public csrf: string
end

fun viewer_of(docs: Docs, req: Request, signup_open: bool) -> Viewer
    let session = sessions.session_of(req)
    let held = session.get("uid")
    let id = if held == none then none else held.to_int() end
    let account = if id == none then none else docs.store.account(id) end
    if account == none then
        return Viewer { signed_in: false, login: "", staff: false, signup_open: signup_open, csrf: "" }
    end
    Viewer { signed_in: true, login: account.login, staff: account.role == "admin" or account.role == "editor", signup_open: signup_open, csrf: session.csrf_field() }
end

--" The frame of a public page that is not part of the documentation: French, no versions. --"
fun base_shell(docs: Docs, req: Request, signup_open: bool, title: string) -> map<string, Json>
    {
        "title": Json.string(title),
        "locale": Json.string("fr"),
        "other_locale": Json.string("en"),
        "label": Json.string(""),
        "versions": Json.array([]),
        "has_versions": Json.of(false),
        "query": Json.string(""),
        "t": Json.of({ "docs": "Documentation", "packages": "Paquets", "playground": "Playground", "search": "Rechercher dans la doc" }),
        "docs_url": Json.string("/fr/{docs.default_section()}"),
        "sections": Json.of(links(docs, "fr")),
        "other_url": Json.string("/en/{docs.default_section()}"),
        "search_url": Json.string("/fr/search"),
        "viewer": Json.of(viewer_of(docs, req, signup_open)),
    }
end

export Viewer, viewer_of, base_shell
