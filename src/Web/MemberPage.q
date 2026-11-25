import "@std/web/session.q" as sessions
import Docs from "../Docs/Docs.q"
import Views from "./Views.q"
import base_shell from "./Viewer.q"
import form_of from "./Support.q"

struct FormData
    public login: string
    public error: string
    public has_error: bool
    public csrf: string
    public open: bool
end

--" Accounts of the public site: anyone may sign up (unless it is closed) and sign in; only the staff gets the "Admin" button. --"
struct MemberPage
    docs: Docs
    views: Views
    signup_open: bool
end

impl MemberPage
    public fun new(docs: Docs, views: Views, signup_open: bool) -> MemberPage
        MemberPage { docs: docs, views: views, signup_open: signup_open }
    end

    fun show(self, req: Request, name: string, title: string, login: string, error: string, status: int) -> Response
        let data = FormData { login: login, error: error, has_error: error != "", csrf: sessions.session_of(req).csrf_field(), open: self.signup_open }
        self.views.public_page(name, base_shell(self.docs, req, self.signup_open, title), Json.of(data)).with_status(status)
    end

    fun signed_in(self, req: Request) -> bool
        sessions.session_of(req).get("uid") != none
    end

    public fun login_form(self, req: Request) -> Response
        if self.signed_in(req) then
            return Response.redirect("/")
        end
        self.show(req, "public_login", "Connexion", "", "", 200)
    end

    public fun login(self, req: Request) -> Response
        let form = form_of(req)
        let login = form["login"] ?? ""
        let account = self.docs.authenticate(login, form["password"] ?? "")
        if account == none then
            return self.show(req, "public_login", "Connexion", login, "Identifiant ou mot de passe incorrect.", 401)
        end
        let session = sessions.session_of(req)
        session.regenerate()
        session.set("uid", "{account.id}")
        self.docs.store.log(account.id, "account.login", "account", account.id, "Connexion de {account.login}", Json.object({}))
        Response.redirect("/")
    end

    public fun register_form(self, req: Request) -> Response
        if self.signed_in(req) then
            return Response.redirect("/")
        end
        self.show(req, "public_register", "Inscription", "", "", 200)
    end

    public fun register(self, req: Request) -> Response
        if not self.signup_open then
            return self.show(req, "public_register", "Inscription", "", "Les inscriptions sont fermées.", 403)
        end
        let form = form_of(req)
        let login = form["login"] ?? ""
        if form["password"] != form["password2"] then
            return self.show(req, "public_register", "Inscription", login, "Les deux mots de passe sont différents.", 422)
        end
        let made = self.docs.create_account(login, form["password"] ?? "", "member", none)
        if made.is_err() then
            return self.show(req, "public_register", "Inscription", login, made.unwrap_err(), 422)
        end
        let session = sessions.session_of(req)
        session.regenerate()
        session.set("uid", "{made.unwrap()}")
        Response.redirect("/")
    end

    public fun logout(self, req: Request) -> Response
        let session = sessions.session_of(req)
        session.clear()
        session.regenerate()
        Response.redirect("/")
    end
end

export MemberPage
