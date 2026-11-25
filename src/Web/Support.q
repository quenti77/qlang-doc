import "@std/web/session.q" as sessions

fun session_of(req: Request) -> sessions.Session
    sessions.session_of(req)
end

--" The id of the signed in account, or none. --"
fun uid_of(req: Request) -> int?
    let held = sessions.session_of(req).get("uid")
    if held == none then none else held.to_int() end
end

fun ok(req: Request, message: string)
    sessions.session_of(req).flash_set("ok|{message}")
end

fun fail(req: Request, message: string)
    sessions.session_of(req).flash_set("error|{message}")
end

--" A date for people: `25/11/2026 14:30`. --"
fun when(ms: int) -> string
    if ms <= 0 then "" else datetime.at(ms).format("DD/MM/YYYY HH:mm") end
end

fun form_of(req: Request) -> map<string, string>
    let f = req.form()
    if f.is_ok() then f.unwrap() else {} end
end

--" A number from a form field or a query parameter; none when it is empty or not a number. --"
fun int_of(text: string?) -> int?
    if text == none or text.trim() == "" then none else text.trim().to_int() end
end

fun locale_of(text: string?) -> string
    if text == "en" then "en" else "fr" end
end

--" Where to go back to after an action: the page that sent it when it is of this site, otherwise `fallback`. --"
fun back(req: Request, fallback: string) -> Response
    let target = form_of(req)["return"] ?? fallback
    Response.redirect(if target.starts_with("/admin") then target else fallback end)
end

import Docs from "../Docs/Docs.q"
import Views from "./Views.q"

--" A page of the panel, for whoever is signed in. --"
fun render(docs: Docs, views: Views, req: Request, name: string, title: string, section: string, data: Json) -> Response
    let uid = uid_of(req)
    let account = if uid == none then none else docs.store.account(uid) end
    let login = if account == none then "" else account.login end
    let admin = account != none and account.role == "admin"
    views.page(name, title, data, sessions.session_of(req), section, login, admin)
end
export session_of, uid_of, ok, fail, when, form_of, int_of, locale_of, back, render
