import Boot from "./src/App/Boot.q"
import build from "./src/App/Web.q"

--" `qlang serve main.q --static public`. The tables are made by `qlang run migrate.q`, once, not by each worker. --"
let boot = Boot.start()
let app = build(boot.db)

fun handle(req: Request) -> Response
    app.handle(req)
end
