import Docs from "../Docs/Docs.q"
import folder_paths from "../Docs/Tree.q"

--" An option of a `<select>`. --"
struct Choice
    public value: string
    public label: string
    public selected: bool
end

--" The folders of a language as options, the root first: `(racine)`, then `guide`, `guide / types`... --"
fun folder_choices(docs: Docs, locale: string, selected: int?) -> array<Choice>
    let folders = docs.store.folders(locale)
    let paths = folder_paths(folders)
    let out: array<Choice> = [Choice { value: "", label: "(racine)", selected: selected == none }]
    let labelled: array<Choice> = []
    for f in folders do
        let path = paths[f.id] ?? f.slug
        labelled.push(Choice { value: "{f.id}", label: path.replace("/", " / "), selected: selected == f.id })
    end
    for c in labelled.sorted_by(fun(a: Choice, b: Choice) -> int if a.label < b.label then -1 elseif a.label > b.label then 1 else 0 end end) do
        out.push(c)
    end
    out
end

export Choice, folder_choices
