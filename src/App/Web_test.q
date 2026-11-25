import describe, it, expect, finish from "@test"
import "@std/web/testing.q" as testing
import Docs from "../Docs/Docs.q"
import Store from "../Docs/Store.q"
import fresh_db from "../Docs/TestSupport.q"
import Config from "./Config.q"
import Registry, Options from "../Registry/Registry.q"
import build from "./Web.q"

let PASSWORD = "a long enough password"

fun config(open: bool) -> Config
    Config { database_url: "", session_secret: "test-session-secret-of-at-least-32-chars", secure_cookies: false, submissions_open: open, signup_open: true, views_dir: "views", git_hosts: ["github.com"], hook_secret: "hook-secret", base_url: "https://docs.example.org" }
end

struct Site
    public client: testing.Client
    public docs: Docs
end

fun site() -> Site
    site_with(false)
end

fun site_with(open: bool) -> Site
    let db = fresh_db()
    let docs = Docs.new(Store.new(db))
    docs.create_account("boss", PASSWORD, "admin", none)
    docs.create_account("writer", PASSWORD, "editor", none)
    Site { client: testing.Client.new(build(db, config(open))), docs: docs }
end

--" The CSRF token that a page of the site carries. --"
fun token(client: testing.Client, path: string) -> string
    let body = client.get(path).body
    let marker = "name=\"_csrf\" value=\""
    let at = body.index_of(marker)
    if at == none then
        panic("no CSRF token in {path}")
    end
    let rest = body.substring(at + marker.len(), body.len())
    rest.substring(0, rest.index_of("\"") ?? 0)
end

fun sign_in(client: testing.Client, login: string)
    let t = token(client, "/admin/login")
    client.post_form("/admin/login", { "_csrf": t, "login": login, "password": PASSWORD }).expect_status(302)
end

fun post(client: testing.Client, source: string, path: string, fields: map<string, string>) -> testing.Reply
    let t = token(client, source)
    fields["_csrf"] = t
    client.post_form(path, fields)
end

fun test_suite()
    describe("the panel", fun()
        it("sends a visitor to the login page and refuses a wrong password", fun()
            let s = site()
            let r = s.client.get("/admin").expect_status(302)
            expect(r.header("location")).to_be("/admin/login")
            let t = token(s.client, "/admin/login")
            s.client.post_form("/admin/login", { "_csrf": t, "login": "boss", "password": "wrong password!!" }).expect_status(302)
            expect(s.client.get("/admin").status).to_be(302)
        end)

        it("refuses a form without the CSRF token", fun()
            let s = site()
            s.client.post_form("/admin/login", { "login": "boss", "password": PASSWORD }).expect_status(403)
        end)

        it("lets an administrator in", fun()
            let s = site()
            sign_in(s.client, "boss")
            s.client.get("/admin").expect_status(200).expect_body_contains("Tableau de bord")
        end)

        it("keeps releases and accounts for administrators", fun()
            let s = site()
            sign_in(s.client, "writer")
            s.client.get("/admin/docs").expect_status(200)
            post(s.client, "/admin/releases", "/admin/releases", { "label": "1.0.0" }).expect_status(403)
            s.client.get("/admin/accounts").expect_status(403)
        end)
    end)

    describe("public accounts", fun()
        it("signs a member up, who gets no panel and no Admin button", fun()
            let s = site()
            let t = token(s.client, "/account/register")
            s.client.post_form("/account/register", { "_csrf": t, "login": "reader", "password": PASSWORD, "password2": PASSWORD }).expect_status(302)
            s.client.get("/").expect_status(200).expect_body_contains("reader")
            expect(s.client.get("/").body.contains("href=\"/admin\"")).to_be(false)
            expect(s.client.get("/admin").header("location")).to_be("/")
            expect(s.docs.store.account_by_login("reader").unwrap().role).to_be("member")
        end)

        it("refuses a bad sign-up", fun()
            let s = site()
            let t = token(s.client, "/account/register")
            s.client.post_form("/account/register", { "_csrf": t, "login": "reader", "password": PASSWORD, "password2": "another long password" }).expect_status(422)
            s.client.post_form("/account/register", { "_csrf": t, "login": "boss", "password": PASSWORD, "password2": PASSWORD }).expect_status(422).expect_body_contains("existe déjà")
        end)

        it("shows the Admin button to the staff only", fun()
            let s = site()
            expect(s.client.get("/").body.contains("href=\"/admin\"")).to_be(false)
            let t = token(s.client, "/account/login")
            s.client.post_form("/account/login", { "_csrf": t, "login": "boss", "password": PASSWORD }).expect_status(302)
            s.client.get("/").expect_status(200).expect_body_contains("href=\"/admin\"")
        end)

        it("refuses a wrong password", fun()
            let s = site()
            let t = token(s.client, "/account/login")
            s.client.post_form("/account/login", { "_csrf": t, "login": "boss", "password": "wrong password!!" }).expect_status(401)
        end)
    end)

    describe("writing and publishing", fun()
        it("creates a folder and a page, shows the diff, goes back", fun()
            let s = site()
            sign_in(s.client, "writer")
            post(s.client, "/admin/docs", "/admin/folders", { "locale": "fr", "title": "Guide", "slug": "", "parent": "" }).expect_status(302)
            post(s.client, "/admin/docs", "/admin/pages", { "locale": "fr", "folder": "1", "title": "Types", "slug": "", "markdown": "# Types\n\none" }).expect_status(302)
            post(s.client, "/admin/pages/1", "/admin/pages/1", { "title": "Types", "markdown": "# Types\n\ntwo", "summary": "second" }).expect_status(302)
            s.client.get("/admin/pages/1/history").expect_status(200).expect_body_contains("second")
            s.client.get("/admin/pages/1/diff?from=1&to=2").expect_status(200).expect_body_contains("line-add")
            post(s.client, "/admin/pages/1/history", "/admin/pages/1/restore", { "number": "1" }).expect_status(302)
            s.client.get("/admin/pages/1").expect_body_contains("one")
        end)

        it("keeps the journal readable after a rename, whose data holds text", fun()
            let s = site()
            sign_in(s.client, "writer")
            post(s.client, "/admin/docs", "/admin/pages", { "locale": "fr", "folder": "", "title": "Intro", "slug": "", "markdown": "# Intro" }).expect_status(302)
            post(s.client, "/admin/pages/1", "/admin/pages/1", { "title": "Intro", "markdown": "# Intro\n\nmore", "summary": "" }).expect_status(302)
            post(s.client, "/admin/pages/1", "/admin/pages/1/rename", { "slug": "start" }).expect_status(302)
            s.client.get("/admin/audit").expect_body_contains("diff?from=1&amp;to=2")
            s.client.get("/admin/audit").expect_status(200).expect_body_contains("page.rename")
        end)

        it("previews Markdown without saving it", fun()
            let s = site()
            sign_in(s.client, "writer")
            let t = token(s.client, "/admin/new-page")
            s.client.header("X-CSRF-Token", t)
            s.client.post_form("/admin/preview", { "markdown": "**bold**" }).expect_status(200).expect_body_contains("<strong>bold</strong>")
        end)

        it("imports uploaded Markdown files", fun()
            let s = site()
            sign_in(s.client, "writer")
            let t = token(s.client, "/admin/import")
            s.client.post_multipart("/admin/import", { "_csrf": t, "locale": "en", "folder": "" }, [
                testing.TestFile { field: "files", filename: "hello.md", content_type: "text/markdown", data: "# Hello\n\nworld".to_bytes() },
            ]).expect_status(302)
            expect(s.docs.store.find_page("en", none, "hello").unwrap().title).to_be("Hello")
        end)

        it("serves only what a release published, and goes back to the older one", fun()
            let s = site()
            sign_in(s.client, "boss")
            s.client.get("/fr/docs").expect_status(404)
            let id = s.docs.create_page("fr", none, "Intro", "", "# Intro\n\nversion one <script>alert(1)</script>", "edit", none).unwrap()
            post(s.client, "/admin/releases", "/admin/releases", { "label": "1.0.0", "qlang_version": "1.0.0", "note": "", "publish": "1" }).expect_status(302)
            let first = s.client.get("/fr/docs/intro").expect_status(200)
            first.expect_body_contains("version one")
            expect(first.body.contains("<script>alert")).to_be(false)
            s.docs.edit_page(id, "Intro", "# Intro\n\nversion two", "", "edit", none)
            s.client.get("/fr/docs/intro").expect_body_contains("version one")
            post(s.client, "/admin/releases", "/admin/releases", { "label": "2.0.0", "qlang_version": "2.0.0", "note": "", "publish": "1" })
            s.client.get("/fr/docs/intro").expect_body_contains("version two")
            s.client.get("/fr/docs/intro?v=1.0.0").expect_body_contains("version one")
            post(s.client, "/admin/releases", "/admin/releases/1/publish", {}).expect_status(302)
            s.client.get("/fr/docs/intro").expect_body_contains("version one")
            s.client.get("/fr/search?q=version").expect_status(200).expect_body_contains("Intro")
            s.client.get("/fr/docs/missing").expect_status(404)
        end)
    end)

    describe("the playground", fun()
        it("serves the page and the WebAssembly module", fun()
            let s = site()
            s.client.get("/playground").expect_status(200).expect_body_contains("pg-source")
        end)
    end)

    describe("the registry", fun()
        it("serves the index in the format of qlang search", fun()
            let s = site()
            let registry = Registry.new(s.docs.store, Options { submissions_open: false, hosts: [] })
            registry.add("json5", "https://github.com/me/json5", none)
            let body = s.client.get("/packages.json").expect_status(200).body
            let index = Json.parse(body).unwrap()
            expect(index.get("json5").unwrap().get("git").unwrap().as_string()).to_be("https://github.com/me/json5")
            s.client.get("/packages").expect_status(200).expect_body_contains("json5")
            s.client.get("/packages/json5").expect_status(200).expect_body_contains("qlang add json5")
            s.client.get("/packages/nope").expect_status(404)
        end)

        it("takes proposals only when they are open, and holds them for a moderator", fun()
            let closed = site()
            post(closed.client, "/admin/login", "/packages/submit", { "name": "json5", "git": "https://github.com/me/json5" }).expect_status(302)
            expect(closed.client.get("/packages.json").body.contains("json5")).to_be(false)
            let open = site_with(true)
            post(open.client, "/packages/submit", "/packages/submit", { "name": "json5", "git": "https://github.com/me/json5" }).expect_status(302)
            open.client.get("/packages/json5").expect_status(404)
            expect(open.client.get("/packages.json").body.contains("json5")).to_be(false)
            post(open.client, "/packages/submit", "/packages/submit", { "name": "evil", "git": "https://localhost/me/x" }).expect_status(302)
            open.client.get("/packages/submit").expect_status(200).expect_body_contains("Proposer")
        end)

        it("keeps moderation for administrators", fun()
            let s = site_with(true)
            post(s.client, "/packages/submit", "/packages/submit", { "name": "json5", "git": "https://github.com/me/json5" })
            sign_in(s.client, "writer")
            s.client.get("/admin/packages").expect_status(403)
            s.client.forget_cookies()
            sign_in(s.client, "boss")
            s.client.get("/admin/packages").expect_status(200).expect_body_contains("json5")
            post(s.client, "/admin/packages", "/admin/packages/1/approve", {}).expect_status(302)
            expect(s.docs.store.audit("package", 10, 0)[0].action).to_be("package.approve")
            s.client.get("/packages/json5").expect_status(200)
        end)

        it("queues a package when its host calls the webhook with the right signature", fun()
            let s = site()
            let registry = Registry.new(s.docs.store, Options { submissions_open: false, hosts: [] })
            let id = registry.add("json5", "https://github.com/me/json5", none).unwrap()
            registry.packages.set_sync_requested(id, false)
            let payload = "\{\"repository\": \{\"html_url\": \"https://github.com/me/json5\"\}\}"
            s.client.header("X-Hub-Signature-256", "sha256=" + Hash.hmac_sha256("wrong", payload))
            s.client.post("/hooks/git", payload).expect_status(401)
            s.client.header("X-Hub-Signature-256", "sha256=" + Hash.hmac_sha256("hook-secret", payload))
            s.client.post("/hooks/git", payload).expect_status(202).expect_body_contains("true")
            expect(registry.packages.package(id).unwrap().sync_requested).to_be(true)
        end)
    end)

    finish()
end
