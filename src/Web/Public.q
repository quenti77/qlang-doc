import Docs, LOCALES from "../Docs/Docs.q"
import Release, SnapFolder, SnapPage from "../Docs/Models.q"
import Views from "./Views.q"
import highlight from "../Markup/Highlight.q"

let SAMPLE = "struct Greeter
    public name: string
end

impl Greeter
    public fun hello(self) -> string
        \"Bonjour \{self.name\} !\"
    end
end

print(Greeter \{ name: \"qlang\" \}.hello())"

struct NavItem
    public is_folder: bool
    public title: string
    public url: string
    public style: string
    public active: bool
    public path: string
    public hidden: string
    public expanded: string
end

struct TocItem
    public id: string
    public text: string
    public style: string
end

struct VersionLink
    public label: string
    public url: string
    public current: bool
end

struct PageData
    public title: string
    public html: string
    public nav: array<NavItem>
    public toc: array<TocItem>
    public has_toc: bool
    public crumbs: string
    public has_crumbs: bool
    public has_prev: bool
    public prev_url: string
    public prev_title: string
    public has_next: bool
    public next_url: string
    public next_title: string
    public t: Strings
end

struct MessageData
    public title: string
    public text: string
end

struct HitRow
    public title: string
    public url: string
    public path: string
    public excerpt: string
end

struct SearchData
    public query: string
    public hits: array<HitRow>
    public has_hits: bool
    public count: int
    public searched: bool
    public t: Strings
end

struct Heading
    public level: int
    public id: string
    public text: string
end

--" The words of the site's own interface, in each language. --"
struct Strings
    public docs: string
    public packages: string
    public playground: string
    public search: string
    public previous: string
    public next: string
    public on_this_page: string
    public no_results: string
    public results: string
    public footer: string
end

fun strings_of(locale: string) -> Strings
    if locale == "en" then
        return Strings { docs: "Documentation", packages: "Packages", playground: "Playground", search: "Search the docs", previous: "Previous", next: "Next", on_this_page: "On this page", no_results: "Nothing found.", results: "results", footer: "qlang" }
    end
    Strings { docs: "Documentation", packages: "Paquets", playground: "Playground", search: "Rechercher dans la doc", previous: "Précédent", next: "Suivant", on_this_page: "Sur cette page", no_results: "Aucun résultat.", results: "résultats", footer: "qlang" }
end

fun parent_of(path: string) -> string
    let cut = path.last_index_of("/")
    if cut == none then "" else path.substring(0, cut) end
end

fun depth_of(path: string) -> int
    path.split("/").len() - 1
end

--" A nav entry starts hidden unless its folder is on the way to the page being read. --"
fun hidden_attr(parent: string, active: string) -> string
    if parent == "" or active.starts_with(parent + "/") then "" else "hidden" end
end

--" The documentation of a release as a list in reading order: each folder, then what it holds (folders first, then pages). --"
fun ordered(folders: array<SnapFolder>, pages: array<SnapPage>, parent: string, out: array<NavItem>, seq: array<SnapPage>, active: string, base: string, suffix: string)
    let subs = folders.filter(fun(f: SnapFolder) -> bool parent_of(f.path) == parent end).sorted_by(fun(a: SnapFolder, b: SnapFolder) -> int a.position - b.position end)
    for f in subs do
        out.push(NavItem { is_folder: true, title: f.title, url: "", style: "padding-left:{depth_of(f.path) + 0.5}rem", active: false, path: f.path, hidden: hidden_attr(parent, active), expanded: if active.starts_with(f.path + "/") then "true" else "false" end })
        ordered(folders, pages, f.path, out, seq, active, base, suffix)
    end
    let leaves = pages.filter(fun(p: SnapPage) -> bool parent_of(p.path) == parent end).sorted_by(fun(a: SnapPage, b: SnapPage) -> int a.position - b.position end)
    for p in leaves do
        out.push(NavItem { is_folder: false, title: p.title, url: "{base}/{p.path}{suffix}", style: "padding-left:{depth_of(p.path) + 0.5}rem", active: p.path == active, path: p.path, hidden: hidden_attr(parent, active), expanded: "false" })
        seq.push(p)
    end
end

fun excerpt_of(markdown: string, words: string) -> string
    let flat = markdown.replace("\n", " ").replace("#", "").replace("`", "").replace("*", "")
    let at = flat.lower().index_of(words.lower())
    if at == none then
        return flat.substring(0, if flat.len() > 160 then 160 else flat.len() end)
    end
    let start = if at > 60 then at - 60 else 0 end
    let stop = if at + 120 > flat.len() then flat.len() else at + 120 end
    (if start > 0 then "…" else "" end) + flat.substring(start, stop).trim() + (if stop < flat.len() then "…" else "" end)
end

--" The public site: the pages of the published release (or of the one named by `?v=`). --"
struct Public
    docs: Docs
    views: Views
end

impl Public
    public fun new(docs: Docs, views: Views) -> Public
        Public { docs: docs, views: views }
    end

    fun shell(self, locale: string, title: string, release: Release?, current_path: string) -> map<string, Json>
        let versions: array<VersionLink> = []
        for r in self.docs.store.releases() do
            let url = if r.current then "/{locale}/docs" else "/{locale}/docs?v={r.label}" end
            versions.push(VersionLink { label: r.label, url: url, current: release != none and release.id == r.id })
        end
        let shell: map<string, Json> = {
            "title": Json.string(title),
            "locale": Json.string(locale),
            "other_locale": Json.string(if locale == "fr" then "en" else "fr" end),
            "label": Json.string(if release == none then "" else release.label end),
            "versions": Json.of(versions),
            "has_versions": Json.of(versions.len() > 1),
            "t": Json.of(strings_of(locale)),
            "query": Json.string(""),
            "docs_url": Json.string("/{locale}/docs"),
            "search_url": Json.string("/{locale}/search"),
        }
        shell
    end

    fun message(self, locale: string, title: string, text: string, status: int) -> Response
        let shell = self.shell(locale, title, none, "")
        self.views.public_page("public_message", shell, Json.of(MessageData { title: title, text: text })).with_status(status)
    end

    public fun home(self, req: Request) -> Response
        let shell = self.shell("fr", "qlang", none, "")
        shell["sample"] = Json.string(highlight(SAMPLE))
        self.views.public_page("public_home", shell, Json.object({ "sample": Json.string(highlight(SAMPLE)) }))
    end

    fun resolve(self, req: Request) -> Release?
        let label = req.query["v"]
        if label != none then
            return self.docs.store.release_by_label(label)
        end
        let id = self.docs.store.current_release_id()
        if id == none then none else self.docs.store.release(id) end
    end

    public fun handle(self, req: Request) -> Response
        let segments = req.path.split("/").filter(fun(s: string) -> bool s != "" end)
        if segments.len() >= 2 and LOCALES.contains(segments[0]) then
            if segments[1] == "docs" then
                return self.page(req, segments[0], segments.slice(2, segments.len()).join("/"))
            end
            if segments[1] == "search" then
                return self.search(req, segments[0])
            end
        end
        if segments.len() == 1 and segments[0] == "docs" then
            return Response.redirect("/fr/docs")
        end
        self.message("fr", "Page introuvable", "Cette page n'existe pas.", 404)
    end

    fun page(self, req: Request, locale: string, path: string) -> Response
        let release = self.resolve(req)
        if release == none then
            return self.message(locale, "Documentation", "La documentation n'est pas encore publiée.", 404)
        end
        let explicit = req.query["v"]
        let suffix = if explicit == none then "" else "?v={explicit}" end
        let base = "/{locale}/docs"
        let folders = self.docs.store.release_folders(release.id).filter(fun(f: SnapFolder) -> bool f.locale == locale end)
        let pages = self.docs.store.release_pages(release.id).filter(fun(p: SnapPage) -> bool p.locale == locale end)
        let nav: array<NavItem> = []
        let seq: array<SnapPage> = []
        ordered(folders, pages, "", nav, seq, path, base, suffix)
        if seq.is_empty() then
            return self.message(locale, "Documentation", "Cette version n'a pas de pages dans cette langue.", 404)
        end
        let found = seq.filter(fun(p: SnapPage) -> bool p.path == path end)
        if found.is_empty() then
            let inside = seq.filter(fun(p: SnapPage) -> bool path == "" or p.path.starts_with(path + "/") end)
            if not inside.is_empty() then
                return Response.redirect("{base}/{inside[0].path}{suffix}")
            end
            return self.message(locale, "Page introuvable", "Cette page n'existe pas dans cette version.", 404)
        end
        let page = found[0]
        let at = seq.index_of(page) ?? 0
        let toc: array<TocItem> = []
        let parsed = Json.parse(page.toc)
        if parsed.is_ok() then
            let headings = Json.to<array<Heading>>(parsed.unwrap())
            if headings.is_ok() then
                for h in headings.unwrap() do
                    if h.level == 2 or h.level == 3 then
                        toc.push(TocItem { id: h.id, text: h.text, style: if h.level == 3 then "padding-left:1rem" else "" end })
                    end
                end
            end
        end
        let crumbs: array<string> = []
        let parts = path.split("/")
        let k = 0
        while k < parts.len() - 1 do
            let prefix = parts.slice(0, k + 1).join("/")
            for f in folders do
                if f.path == prefix then
                    crumbs.push(f.title)
                end
            end
            k = k + 1
        end
        let data = PageData {
            title: page.title, html: page.html, nav: nav, toc: toc, has_toc: toc.len() > 1, crumbs: crumbs.join(" › "), has_crumbs: not crumbs.is_empty(),
            has_prev: at > 0, prev_url: if at > 0 then "{base}/{seq[at - 1].path}{suffix}" else "" end, prev_title: if at > 0 then seq[at - 1].title else "" end,
            has_next: at + 1 < seq.len(), next_url: if at + 1 < seq.len() then "{base}/{seq[at + 1].path}{suffix}" else "" end, next_title: if at + 1 < seq.len() then seq[at + 1].title else "" end,
            t: strings_of(locale),
        }
        self.views.public_page("public_page", self.shell(locale, page.title, release, path), Json.of(data))
    end

    fun search(self, req: Request, locale: string) -> Response
        let release = self.resolve(req)
        let query = (req.query["q"] ?? "").trim()
        let hits: array<HitRow> = []
        if release != none and query.len() >= 2 then
            let explicit = req.query["v"]
            let suffix = if explicit == none then "" else "?v={explicit}" end
            for p in self.docs.store.search_release(release.id, locale, query, 30) do
                hits.push(HitRow { title: p.title, url: "/{locale}/docs/{p.path}{suffix}", path: p.path.replace("/", " › "), excerpt: excerpt_of(p.markdown, query) })
            end
        end
        let data = SearchData { query: query, hits: hits, has_hits: not hits.is_empty(), count: hits.len(), searched: query.len() >= 2, t: strings_of(locale) }
        let shell = self.shell(locale, strings_of(locale).search, release, "")
        shell["query"] = Json.string(query)
        self.views.public_page("public_search", shell, Json.of(data))
    end
end

export Public
