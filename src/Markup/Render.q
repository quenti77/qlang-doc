import "@markdown/markdown.q" as markdown
import highlight from "./Highlight.q"

--" The options of the site: fenced code is coloured by the qlang highlighter when it is qlang, and only escaped otherwise. --"
fun site_options() -> markdown.Options
    let options = markdown.Options.plain()
    options.highlight = fun(language: string, code: string) -> string
        if language == "qlang" or language == "q" then highlight(code) else markdown.escape(code) end
    end
    options
end

--" A Markdown text turned into HTML, with its title and its headings. --"
fun render_page(source: string) -> markdown.Document
    markdown.convert(source, site_options())
end

export render_page, site_options
