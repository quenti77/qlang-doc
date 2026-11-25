import "@std/web/app.q" as web
import "@std/web/upload.q" as upload
import Docs from "../Docs/Docs.q"
import Views from "./Views.q"
import Choice, folder_choices from "./Choices.q"
import render, session_of, uid_of, ok, fail, int_of, locale_of from "./Support.q"

struct ImportData
    public locale: string
    public is_fr: bool
    public is_en: bool
    public other: string
    public folders: array<Choice>
    public csrf: string
end

--" Importing Markdown files: one or many, into a folder. A file whose name is already a page there becomes a new revision of it. --"
#[web.Controller("/admin")]
#[web.Guard("auth")]
struct ImportPage
    docs: Docs
    views: Views
end

impl ImportPage
    #[web.Get("/import")]
    public fun form(self, req: Request, #[web.Query] locale: string?, #[web.Query] folder: string?) -> Response
        let lang = locale_of(locale)
        let data = ImportData { locale: lang, is_fr: lang == "fr", is_en: lang == "en", other: if lang == "fr" then "en" else "fr" end, folders: folder_choices(self.docs, lang, int_of(folder)), csrf: session_of(req).csrf_field() }
        render(self.docs, self.views, req, "import", "Import Markdown", "import", Json.of(data))
    end

    #[web.Post("/import")]
    public fun receive(self, req: Request) -> Response
        let rules = upload.Rules { max_size: 1048576, max_files: 100, types: ["text/plain", "text/markdown"], required: true }
        let sent = upload.receive(req, rules)
        if sent.is_err() then
            fail(req, sent.unwrap_err().message)
            return Response.redirect("/admin/import")
        end
        let locale = locale_of(sent.unwrap().fields["locale"])
        let folder = int_of(sent.unwrap().fields["folder"])
        let created = 0
        let updated = 0
        let problems: array<string> = []
        for file in sent.unwrap().files do
            let content = file.data.to_string()
            if content == none then
                problems.push("{file.filename} : ce n'est pas du texte UTF-8")
                continue
            end
            let done = self.docs.import_markdown(locale, folder, file.filename, content, uid_of(req))
            if done.is_err() then
                problems.push("{file.filename} : {done.unwrap_err()}")
            elseif done.unwrap().created then
                created = created + 1
            else
                updated = updated + 1
            end
        end
        let report = "{created} page(s) créée(s), {updated} mise(s) à jour"
        if problems.is_empty() then
            ok(req, report + ".")
        else
            fail(req, report + ". Refusés : " + problems.join(" ; "))
        end
        Response.redirect("/admin/docs?locale={locale}")
    end
end
