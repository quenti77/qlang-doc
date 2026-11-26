import "@markdown/markdown.q" as markdown
import highlight from "./Highlight.q"

--" A line of code coloured by language: only qlang is coloured, the rest is escaped. --"
fun colour(language: string, code: string) -> string
    if language == "qlang" or language == "q" then highlight(code) else markdown.escape(code) end
end

--" The code of a `diff-<language>` block: the `+`, `-` or space that starts each line stays as it is, the rest is coloured as `<language>`. The `@@` lines are left alone. --"
fun colour_diff(language: string, code: string) -> string
    let out: array<string> = []
    for line in code.split("\n") do
        let mark = if line.len() > 0 then line.substring(0, 1) else "" end
        if (mark == "+" or mark == "-" or mark == " ") and not line.starts_with("+++") and not line.starts_with("---") then
            out.push(markdown.escape(mark) + colour(language, line.substring(1, line.len())))
        else
            out.push(markdown.escape(line))
        end
    end
    out.join("\n")
end

--" The options of the site: fenced code is coloured by the qlang highlighter when it is qlang, and only escaped otherwise. --"
fun site_options() -> markdown.Options
    let options = markdown.Options.plain()
    options.highlight = fun(language: string, code: string) -> string
        if language.starts_with("diff-") then colour_diff(language.substring(5, language.len()), code) else colour(language, code) end
    end
    options
end

--" The quotes that stand out are `> [!INFO]`, `> [!SUCCESS]`, `> [!WARNING]` and `> [!DANGER]` (the Markdown library knows them as note, tip, warning and caution). --"
let ALERTS = [["info", "NOTE"], ["success", "TIP"], ["warning", "WARNING"], ["danger", "CAUTION"]]

fun alert_markers(source: string) -> string
    let out: array<string> = []
    let fenced = false
    for line in source.split("\n") do
        if line.starts_with("```") then
            fenced = not fenced
        end
        let rest = if not fenced and line.starts_with(">") then line.substring(1, line.len()).trim().lower() else "" end
        let kept = line
        for pair in ALERTS do
            if rest == "[!" + pair[0] + "]" then
                kept = "> [!" + pair[1] + "]"
            end
        end
        out.push(kept)
    end
    out.join("\n")
end

--" The title of an alert comes from the stylesheet, in the language of the page: the library writes it in English. --"
fun alert_titles(html: string) -> string
    let out = html
    for pair in ALERTS do
        let name = pair[1].lower()
        out = out.replace("<p class=\"markdown-alert-title\">" + name.substring(0, 1).upper() + name.substring(1, name.len()) + "</p>", "<p class=\"markdown-alert-title\"></p>")
    end
    out
end

--" A Markdown text turned into HTML, with its title and its headings. --"
fun render_page(source: string) -> markdown.Document
    let doc = markdown.convert(alert_markers(source), site_options())
    doc.html = alert_titles(doc.html)
    doc
end

export render_page, site_options
