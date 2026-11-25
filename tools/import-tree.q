import Boot from "../src/App/Boot.q"
import Store from "../src/Docs/Store.q"
import Docs, slug_of from "../src/Docs/Docs.q"

--" `qlang run tools/import-tree.q -- fr ../qlang-learn/content/fr`: imports a folder of Markdown files, one documentation
folder per directory, each page a revision when it already exists. Safe to run again. --"
let args = env.args()
if args.len() < 2 then
    panic("usage: qlang run tools/import-tree.q -- <locale> <directory>")
end
let locale = args[0]
let root = args[1]
let boot = Boot.start()
let docs = Docs.new(Store.new(boot.db))

fun title_of(name: string) -> string
    let bare = name.replace("-", " ")
    bare.capitalize()
end

fun folder_for(parent: int?, name: string) -> int
    let slug = slug_of(name)
    let found = docs.store.find_folder(locale, parent, slug)
    if found != none then
        return found.id
    end
    docs.create_folder(locale, parent, title_of(name), slug, none).unwrap()
end

fun walk(dir: string, parent: int?) -> int
    let count = 0
    for name in fs.list(dir).unwrap() do
        let path = "{dir}/{name}"
        if fs.is_dir(path).unwrap() then
            count = count + walk(path, folder_for(parent, name))
        elseif name.ends_with(".md") then
            let content = fs.read(path).unwrap()
            let done = docs.import_markdown(locale, parent, name, content, none)
            if done.is_err() then
                print("skipped {path}: {done.unwrap_err()}")
            else
                count = count + 1
            end
        end
    end
    count
end

print("imported {walk(root, none)} pages from {root}")
