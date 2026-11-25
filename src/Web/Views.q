import "@std/template.q" as template
import "@std/web/session.q" as sessions

let TEMPLATES = ["layout", "login", "dashboard", "tree", "page_form", "page_edit", "history", "diff", "import", "releases", "release", "audit", "accounts", "public_layout", "public_home", "public_page", "public_message", "public_search", "public_packages", "public_package", "public_submit", "admin_packages", "admin_package", "public_playground"]

--" The HTML pages: templates read once, a page is a template inside the layout. --"
struct Views
    public sources: map<string, string>
end

impl Views
    --" Reads the templates of a folder. A missing file is an error at start, not a 500 at the first visit. --"
    public fun load(dir: string) -> Result<Views, Error>
        let sources: map<string, string> = {}
        for name in TEMPLATES do
            let text = fs.read("{dir}/{name}.html")
            if text.is_err() then
                return Err(Error { message: "the template {name} cannot be read in {dir}: {text.unwrap_err().message}" })
            end
            sources[name] = text.unwrap()
        end
        Ok(Views { sources })
    end

    fun fill(self, name: string, data: Json) -> Result<string, string>
        let source = self.sources[name]
        if source == none then
            return Err("the template {name} does not exist")
        end
        let html = template.render_html(source, data)
        if html.is_err() then
            return Err("{name}: {html.unwrap_err().message}")
        end
        Ok(html.unwrap())
    end

    --" A fragment: a template filled with data, without the layout. --"
    public fun fragment(self, name: string, data: Json) -> Result<string, string>
        self.fill(name, data)
    end

    --" An admin page: the template `name` inside the layout of the panel. --"
    public fun page(self, name: string, title: string, data: Json, session: sessions.Session, section: string, login: string, is_admin: bool) -> Response
        let content = self.fill(name, data)
        if content.is_err() then
            return Response.text(content.unwrap_err()).with_status(500)
        end
        let held = session.flash()
        let kind = if held == none then "" else held.split("|")[0] end
        let message = if held == none then "" else held.strip_prefix("{kind}|") ?? "" end
        let shell = Json.object({
            "title": Json.string(title),
            "login": Json.string(login),
            "is_admin": Json.of(is_admin),
            "csrf": Json.string(session.csrf_field()),
            "csrf_token": Json.string(session.csrf_token()),
            "flash": Json.string(message),
            "flash_ok": Json.of(kind == "ok"),
            "nav_dashboard": Json.of(section == "dashboard"),
            "nav_docs": Json.of(section == "docs"),
            "nav_import": Json.of(section == "import"),
            "nav_releases": Json.of(section == "releases"),
            "nav_audit": Json.of(section == "audit"),
            "nav_accounts": Json.of(section == "accounts"),
            "nav_packages": Json.of(section == "packages"),
            "content": Json.string(content.unwrap()),
        })
        let html = self.fill("layout", shell)
        if html.is_err() then
            return Response.text(html.unwrap_err()).with_status(500)
        end
        Response.html(html.unwrap())
    end

    --" A page of the public site. --"
    public fun public_page(self, name: string, shell: map<string, Json>, data: Json) -> Response
        let content = self.fill(name, data)
        if content.is_err() then
            return Response.text(content.unwrap_err()).with_status(500)
        end
        shell["content"] = Json.string(content.unwrap())
        let html = self.fill("public_layout", Json.object(shell))
        if html.is_err() then
            return Response.text(html.unwrap_err()).with_status(500)
        end
        Response.html(html.unwrap())
    end
end

export Views
