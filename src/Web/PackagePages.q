import "@std/web/session.q" as sessions
import Docs from "../Docs/Docs.q"
import Package, PackageVersion from "../Registry/Models.q"
import Registry from "../Registry/Registry.q"
import Views from "./Views.q"
import when from "./Support.q"

struct PackageRow
    public name: string
    public url: string
    public description: string
    public license: string
    public has_license: bool
    public latest: string
    public has_latest: bool
    public keywords: array<string>
end

struct KeywordLink
    public name: string
    public url: string
    public active: bool
end

struct PackagesData
    public query: string
    public keyword: string
    public rows: array<PackageRow>
    public has_rows: bool
    public count: int
    public keywords: array<KeywordLink>
    public can_submit: bool
    public index_url: string
end

struct VersionRow
    public version: string
    public yanked: bool
    public qlang_req: string
    public has_req: bool
    public seen: string
end

struct PackageData
    public name: string
    public description: string
    public has_description: bool
    public license: string
    public has_license: bool
    public git_url: string
    public latest: string
    public has_latest: bool
    public readme_html: string
    public has_readme: bool
    public versions: array<VersionRow>
    public has_versions: bool
    public keywords: array<string>
    public removed: bool
    public removed_reason: string
    public synced: string
    public install: string
    public pinned: string
end

struct SubmitData
    public open: bool
    public name: string
    public git: string
    public hosts: string
    public csrf: string
    public sent: bool
    public error: string
    public has_error: bool
end

fun row_of(p: Package) -> PackageRow
    PackageRow { name: p.name, url: "/packages/{p.name}", description: p.description, license: p.license, has_license: p.license != "", latest: p.latest_version, has_latest: p.latest_version != "", keywords: p.keywords }
end

--" The public pages of the registry: the list, a package, the proposal form, and the index that `qlang search` reads. --"
struct PackagePages
    docs: Docs
    views: Views
    registry: Registry
    base_url: string
end

impl PackagePages
    public fun new(docs: Docs, views: Views, registry: Registry, base_url: string) -> PackagePages
        PackagePages { docs: docs, views: views, registry: registry, base_url: base_url }
    end

    fun shell(self, title: string) -> map<string, Json>
        {
            "title": Json.string(title),
            "locale": Json.string("fr"),
            "other_locale": Json.string("en"),
            "label": Json.string(""),
            "versions": Json.array([]),
            "has_versions": Json.of(false),
            "query": Json.string(""),
            "t": Json.of({ "docs": "Documentation", "packages": "Paquets", "playground": "Playground", "search": "Rechercher dans la doc" }),
            "docs_url": Json.string("/fr/docs"),
            "search_url": Json.string("/fr/search"),
        }
    end

    --" `/packages.json`: the index, in the format of `qlang search` and `qlang add`. --"
    public fun index(self, req: Request) -> Response
        Response.json(self.registry.index_json()).with_header("Cache-Control", "public, max-age=60")
    end

    public fun list(self, req: Request) -> Response
        let words = (req.query["q"] ?? "").trim()
        let keyword = (req.query["k"] ?? "").trim()
        let found = self.registry.packages.packages("listed", words, keyword)
        let all = self.registry.packages.packages("listed", "", "")
        let counts: map<string, int> = {}
        for p in all do
            for k in p.keywords do
                counts[k] = counts.get(k, 0) + 1
            end
        end
        let names = counts.keys().sorted_by(fun(a: string, b: string) -> int
            let d = counts.get(b, 0) - counts.get(a, 0)
            if d != 0 then d elseif a < b then -1 else 1 end
        end)
        let keywords: array<KeywordLink> = []
        for k in names do
            if keywords.len() < 12 then
                keywords.push(KeywordLink { name: k, url: "/packages?k={k}", active: k == keyword })
            end
        end
        let data = PackagesData {
            query: words, keyword: keyword, rows: found.map(fun(p: Package) -> PackageRow row_of(p) end), has_rows: not found.is_empty(), count: found.len(),
            keywords: keywords, can_submit: self.registry.options.submissions_open, index_url: "{self.base_url}/packages.json",
        }
        let shell = self.shell("Paquets")
        shell["query"] = Json.string(words)
        shell["search_url"] = Json.string("/packages")
        self.views.public_page("public_packages", shell, Json.of(data))
    end

    public fun show(self, req: Request, name: string) -> Response
        let p = self.registry.packages.package_by_name(name)
        if p == none or p.status == "pending" then
            return self.views.public_page("public_message", self.shell("Paquet introuvable"), Json.of({ "title": "Paquet introuvable", "text": "Ce paquet n'est pas dans le registre." })).with_status(404)
        end
        let versions = self.registry.versions(p.id).map(fun(v: PackageVersion) -> VersionRow
            VersionRow { version: v.version, yanked: v.yanked, qlang_req: v.qlang_req, has_req: v.qlang_req != "", seen: when(v.first_seen) }
        end)
        let data = PackageData {
            name: p.name, description: p.description, has_description: p.description != "", license: p.license, has_license: p.license != "", git_url: p.git_url,
            latest: p.latest_version, has_latest: p.latest_version != "", readme_html: p.readme_html, has_readme: p.readme_html != "",
            versions: versions, has_versions: not versions.is_empty(), keywords: p.keywords, removed: p.status == "removed", removed_reason: p.removed_reason,
            synced: if p.synced_at > 0 then when(p.synced_at) else "" end, install: "qlang add {p.name}",
            pinned: "{p.name} = \{ git = \"{p.git_url}\", version = \"^{(p.latest_version.strip_prefix("v") ?? "1.0.0")}\" \}",
        }
        self.views.public_page("public_package", self.shell(p.name), Json.of(data))
    end

    public fun submit_form(self, req: Request) -> Response
        let session = sessions.session_of(req)
        let held = session.flash() ?? ""
        let error = held.strip_prefix("error|") ?? ""
        let data = SubmitData {
            open: self.registry.options.submissions_open, name: session.old("name") ?? "", git: session.old("git") ?? "", hosts: self.registry.options.hosts.join(", "),
            csrf: session.csrf_field(), sent: held == "sent", error: error, has_error: error != "",
        }
        self.views.public_page("public_submit", self.shell("Proposer un paquet"), Json.of(data))
    end

    public fun submit(self, req: Request) -> Response
        let session = sessions.session_of(req)
        let form = req.form()
        let fields: map<string, string> = if form.is_ok() then form.unwrap() else {} end
        let made = self.registry.submit(fields["name"] ?? "", fields["git"] ?? "")
        if made.is_err() then
            session.flash_input({ "name": fields["name"] ?? "", "git": fields["git"] ?? "" })
            session.flash_set("error|{made.unwrap_err()}")
            return Response.redirect("/packages/submit")
        end
        session.flash_set("sent")
        Response.redirect("/packages/submit")
    end
end

export PackagePages
