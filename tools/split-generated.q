import Boot from "../src/App/Boot.q"
import Store from "../src/Docs/Store.q"
import Docs from "../src/Docs/Docs.q"
import Section from "../src/Docs/Models.q"

--" `qlang run tools/split-generated.q`: spreads the pages of the imported `docs-generated` folder over the sections of
the site, by the number that starts their address. Safe to run again; the same can be done by hand in the admin. --"
let boot = Boot.start()
let docs = Docs.new(Store.new(boot.db))

struct Target
    public section: string
    public folder: string
    public fr: string
    public en: string
end

let SECTIONS = [
    Section { slug: "std", title: "Bibliothèque standard", position: 0 },
    Section { slug: "web", title: "Web", position: 0 },
    Section { slug: "contribuer", title: "Contribuer", position: 0 },
]

fun target_for(n: int) -> Target?
    if n <= 2 then
        return Target { section: "docs", folder: "prise-en-main", fr: "Prise en main", en: "Getting started" }
    end
    if n >= 10 and n <= 22 then
        return Target { section: "docs", folder: "le-langage", fr: "Le langage", en: "The language" }
    end
    if n >= 23 and n <= 32 then
        return Target { section: "ref", folder: "langage", fr: "Langage", en: "Language" }
    end
    if n >= 40 and n <= 41 then
        return Target { section: "contribuer", folder: "developpement", fr: "Développement", en: "Development" }
    end
    if n >= 50 and n <= 60 or n == 89 or n == 90 then
        return Target { section: "std", folder: "modules", fr: "Modules", en: "Modules" }
    end
    if n >= 61 and n <= 88 then
        return Target { section: "web", folder: "modules-web", fr: "Modules web", en: "Web modules" }
    end
    if n >= 100 and n <= 203 then
        return Target { section: "ref", folder: "types-et-fonctions", fr: "Types et fonctions", en: "Types and functions" }
    end
    none
end

for s in SECTIONS do
    if docs.store.sections().filter(fun(x: Section) -> bool x.slug == s.slug end).is_empty() then
        docs.create_section(s.title, s.slug, none)
    end
end

let moved = 0
for locale in ["fr", "en"] do
    let source = docs.store.find_folder(locale, none, "docs-generated")
    if source == none then
        continue
    end
    for row in docs.store.page_rows(locale) do
        if row.folder_id != source.id then
            continue
        end
        let n = row.slug.split("-")[0].to_int()
        let goal = if n == none then none else target_for(n) end
        if goal == none then
            print("left in place: {locale}/{row.slug}")
            continue
        end
        let folder = docs.store.find_folder(locale, none, goal.folder)
        let id = if folder == none then docs.create_folder(locale, none, if locale == "fr" then goal.fr else goal.en end, goal.folder, none).unwrap() else folder.id end
        docs.set_section(id, goal.section, none)
        let done = docs.move_page(row.id, id, none)
        if done.is_err() then
            print("skipped {locale}/{row.slug}: {done.unwrap_err()}")
        else
            moved += 1
        end
    end
    if docs.store.folder_is_empty(source.id) then
        docs.delete_folder(source.id, none)
    end
end
print("moved {moved} pages")
