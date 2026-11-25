import "@std/web/app.q" as web
import "@std/web/session.q" as sessions
import Docs from "../Docs/Docs.q"
import Views from "./Views.q"
import ok, fail, form_of from "./Support.q"

struct LoginData
    public login: string
    public csrf: string
end

--" Signing in and out of the panel. --"
#[web.Controller("/admin")]
struct AuthPage
    docs: Docs
    views: Views
end

impl AuthPage
    #[web.Get("/login")]
    public fun form(self, req: Request) -> Response
        let session = sessions.session_of(req)
        if session.get("uid") != none then
            return Response.redirect("/admin")
        end
        let data = LoginData { login: session.old("login") ?? "", csrf: session.csrf_field() }
        self.views.page("login", "Connexion", Json.of(data), session, "", "", false)
    end

    #[web.Post("/login")]
    public fun sign_in(self, req: Request) -> Response
        let session = sessions.session_of(req)
        let form = form_of(req)
        let login = form["login"] ?? ""
        let account = self.docs.authenticate(login, form["password"] ?? "")
        if account == none then
            session.flash_input({ "login": login })
            fail(req, "Identifiant ou mot de passe incorrect.")
            return Response.redirect("/admin/login")
        end
        session.regenerate()
        session.set("uid", "{account.id}")
        self.docs.store.log(account.id, "account.login", "account", account.id, "Connexion de {account.login}", Json.object({}))
        Response.redirect("/admin")
    end

    #[web.Post("/logout")]
    public fun sign_out(self, req: Request) -> Response
        let session = sessions.session_of(req)
        session.clear()
        session.regenerate()
        ok(req, "Tu es déconnecté.")
        Response.redirect("/admin/login")
    end
end
