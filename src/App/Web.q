import "@std/web/app.q" as web
import "@std/web/health.q" as health
import "@std/web/session.q" as sessions
import "@std/web/limit.q" as limit
import "@std/web/cache.q" as cc
import Config from "./Config.q"
import Store from "../Docs/Store.q"
import Docs from "../Docs/Docs.q"
import Views from "../Web/Views.q"
import Public from "../Web/Public.q"
import PackagePages from "../Web/PackagePages.q"
import Registry, Options from "../Registry/Registry.q"
import "../Web/AuthPage.q" as auth_page
import "../Web/DashboardPage.q" as dashboard_page
import "../Web/TreePage.q" as tree_page
import "../Web/PagePages.q" as page_pages
import "../Web/ImportPage.q" as import_page
import "../Web/ReleasePage.q" as release_page
import "../Web/AuditPage.q" as audit_page
import "../Web/AccountPage.q" as account_page
import "../Web/PackageAdminPage.q" as package_admin_page

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

--" A git host calls this when a repository pushes: GitHub signs the body (`X-Hub-Signature-256`), GitLab sends the secret (`X-Gitlab-Token`).
The package, if the registry knows it, is queued for the worker; nothing is read here. --"
fun hook_handler(registry: Registry, secret: string) -> fun(Request) -> Response
    fun(req: Request) -> Response
        if secret == "" then
            return Response.not_found()
        end
        let body = req.body ?? ""
        let signature = req.header("x-hub-signature-256")
        let token = req.header("x-gitlab-token")
        let trusted = false
        if signature != none then
            trusted = Crypto.equal(signature, "sha256=" + Hash.hmac_sha256(secret, body))
        elseif token != none then
            trusted = Crypto.equal(token, secret)
        end
        if not trusted then
            return web.Problem { status: 401, message: "bad signature" }.to_response()
        end
        let parsed = Json.parse(body)
        let repository = if parsed.is_ok() then parsed.unwrap().get("repository") else none end
        let url = if repository == none then none else repository.get("html_url") ?? repository.get("git_http_url") ?? repository.get("homepage") end
        let queued = url != none and url.is_string() and registry.request_sync_for_url(url.as_string())
        Response.json("\{\"queued\":{queued}\}").with_status(202)
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
    let registry = Registry.new(docs.store, Options { submissions_open: config.submissions_open, hosts: config.git_hosts })
    let packages = PackagePages.new(docs, views.unwrap(), registry, config.base_url)
    let app = web.App.new([])
    app.use(sessions.sessions_using(config.session_secret, sessions.Options {
        secure: config.secure_cookies, lifetime: 28800, same_site: "Lax", store: none, prefix: "doc",
    }))
    app.use(sessions.csrf_protect_except(["/hooks/"]))
    let limiter = limit.rate_limit(cc.Cache.memory(), 5, 3600, fun(req: Request) -> string req.header("x-forwarded-for") ?? req.remote_addr end)
    app.use(fun(req: Request, next: web.Handler) -> Response
        if req.method == "POST" and req.path == "/packages/submit" then limiter(req, next) else next(req) end
    end)
    app.container.set(docs)
    app.container.set(views.unwrap())
    app.container.set(registry)
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
    app.discover(Reflect.declared(package_admin_page))
    app.get("/packages", fun(req: Request) -> Response packages.list(req) end)
    app.get("/packages.json", fun(req: Request) -> Response packages.index(req) end)
    app.get("/packages/submit", fun(req: Request) -> Response packages.submit_form(req) end)
    app.post("/packages/submit", fun(req: Request) -> Response packages.submit(req) end)
    app.get("/packages/:name", fun(req: Request) -> Response packages.show(req, req.params.get("name", "")) end)
    app.post("/hooks/git", hook_handler(registry, config.hook_secret))
    app.not_found(fun(req: Request) -> Response site.handle(req) end)
    let problems = app.validate()
    if not problems.is_empty() then
        panic("the application is not wired correctly:\n" + problems.join("\n"))
    end
    app
end

export build
