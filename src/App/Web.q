import "@std/web/app.q" as web
import "@std/web/health.q" as health
import home_page from "./Home.q"

--" The HTTP application over an open database. --"
fun build(db: Db) -> web.App
    let app = web.App.new([])
    let checks = health.Health.new()
    checks.check("database", health.db_check(db))
    checks.mount(app, "/health")
    app.get("/", fun(req: Request) -> Response Response.html(home_page()) end)
    app
end

export build
