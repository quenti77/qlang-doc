import "@std/web/app.q" as web
import "@std/web/health.q" as health
import "@std/web/session.q" as sessions
import Config from "./Config.q"
import Store from "../Docs/Store.q"
import Docs from "../Docs/Docs.q"
import Views from "../Web/Views.q"
import Public from "../Web/Public.q"
import "../Web/AuthPage.q" as auth_page
import "../Web/DashboardPage.q" as dashboard_page
import "../Web/TreePage.q" as tree_page
import "../Web/PagePages.q" as page_pages
import "../Web/ImportPage.q" as import_page
import "../Web/ReleasePage.q" as release_page
import "../Web/AuditPage.q" as audit_page
import "../Web/AccountPage.q" as account_page

--" The guard of the panel: whoever has no signed session, or whose account is gone, goes to the login page. --"
fun auth_guard(docs: Docs) -> fun(Request) -> Response?
    fun(req: Request) -> Response?
        let session = sessions.session_of(req)
        let held = session.get("uid")
        let id = if held == none then none else held.to_int() end
        let account = if id == none then none else docs.store.account(id) end
        if account == none then
            session.clear()
            return Response.redirect("/admin/login")
        end
        none
    end
end

--" What only an administrator may do (releases, accounts). --"
fun admin_guard(docs: Docs) -> fun(Request) -> Response?
    fun(req: Request) -> Response?
        let held = sessions.session_of(req).get("uid")
        let id = if held == none then none else held.to_int() end
        let account = if id == none then none else docs.store.account(id) end
        if account == none or account.role != "admin" then
            return web.Problem { status: 403, message: "réservé aux administrateurs" }.to_response()
        end
        none
    end
end

--" The HTTP application over an open database: the public documentation and the panel under `/admin`. --"
fun build(db: Db, config: Config) -> web.App
    let views = Views.load(config.views_dir)
    if views.is_err() then
        panic(views.unwrap_err().message)
    end
    let docs = Docs.new(Store.new(db))
    let site = Public.new(docs, views.unwrap())
    let app = web.App.new([])
    app.use(sessions.sessions_using(config.session_secret, sessions.Options {
        secure: config.secure_cookies, lifetime: 28800, same_site: "Lax", store: none, prefix: "doc",
    }))
    app.use(sessions.csrf_protect())
    app.container.set(docs)
    app.container.set(views.unwrap())
    app.guard("auth", auth_guard(docs))
    app.guard("admin", admin_guard(docs))
    let checks = health.Health.new()
    checks.check("database", health.db_check(db))
    checks.mount(app, "/health")
    app.get("/", fun(req: Request) -> Response site.home(req) end)
    app.discover(Reflect.declared(auth_page))
    app.discover(Reflect.declared(dashboard_page))
    app.discover(Reflect.declared(tree_page))
    app.discover(Reflect.declared(page_pages))
    app.discover(Reflect.declared(import_page))
    app.discover(Reflect.declared(release_page))
    app.discover(Reflect.declared(audit_page))
    app.discover(Reflect.declared(account_page))
    app.not_found(fun(req: Request) -> Response site.handle(req) end)
    let problems = app.validate()
    if not problems.is_empty() then
        panic("the application is not wired correctly:\n" + problems.join("\n"))
    end
    app
end

export build
