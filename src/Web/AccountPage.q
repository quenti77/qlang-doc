import "@std/web/app.q" as web
import Docs from "../Docs/Docs.q"
import Account from "../Docs/Models.q"
import Views from "./Views.q"
import render, session_of, uid_of, ok, fail, form_of from "./Support.q"

struct AccountRow
    public id: int
    public login: string
    public role: string
    public is_admin: bool
end

struct AccountsData
    public accounts: array<AccountRow>
    public csrf: string
end

--" The accounts that may sign in to the panel (administrators only). --"
#[web.Controller("/admin/accounts")]
#[web.Guard("admin")]
struct AccountPage
    docs: Docs
    views: Views
end

impl AccountPage
    #[web.Get("")]
    public fun list(self, req: Request) -> Response
        let rows = self.docs.store.accounts().map(fun(a: Account) -> AccountRow AccountRow { id: a.id, login: a.login, role: a.role, is_admin: a.role == "admin" } end)
        render(self.docs, self.views, req, "accounts", "Comptes", "accounts", Json.of(AccountsData { accounts: rows, csrf: session_of(req).csrf_field() }))
    end

    #[web.Post("")]
    public fun create(self, req: Request) -> Response
        let form = form_of(req)
        let made = self.docs.create_account(form["login"] ?? "", form["password"] ?? "", form["role"] ?? "editor", uid_of(req))
        if made.is_err() then fail(req, made.unwrap_err()) else ok(req, "Compte créé.") end
        Response.redirect("/admin/accounts")
    end

    #[web.Post("/:id/password")]
    public fun password(self, req: Request, #[web.Path] id: int) -> Response
        let done = self.docs.change_password(id, form_of(req)["password"] ?? "", uid_of(req))
        if done.is_err() then fail(req, done.unwrap_err()) else ok(req, "Mot de passe changé.") end
        Response.redirect("/admin/accounts")
    end

    #[web.Post("/:id/delete")]
    public fun delete(self, req: Request, #[web.Path] id: int) -> Response
        let done = self.docs.delete_account(id, uid_of(req))
        if done.is_err() then fail(req, done.unwrap_err()) else ok(req, "Compte supprimé.") end
        Response.redirect("/admin/accounts")
    end
end
