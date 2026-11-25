import Folder, PageRow from "./Models.q"

--" One line of the documentation tree, folders and pages mixed, in reading order. --"
struct Item
    public kind: string
    public id: int
    public title: string
    public slug: string
    public path: string
    public depth: int
    public revision: int
    public updated_at: int
    public parent_id: int?
end

--" The path of every folder (`guide/types`), by id. --"
fun folder_paths(folders: array<Folder>) -> map<int, string>
    let by_id: map<int, Folder> = {}
    for f in folders do
        by_id[f.id] = f
    end
    let out: map<int, string> = {}
    for f in folders do
        let parts: array<string> = [f.slug]
        let parent = f.parent_id
        let guard = 0
        while parent != none and guard < 50 do
            let up = by_id[parent]
            if up == none then
                break
            end
            parts.insert(0, up.slug)
            parent = up.parent_id
            guard = guard + 1
        end
        out[f.id] = parts.join("/")
    end
    out
end

--" The path of a page: its folder's path and its slug. --"
fun page_path(folder_id: int?, slug: string, paths: map<int, string>) -> string
    if folder_id == none then
        return slug
    end
    let base = paths[folder_id]
    if base == none then slug else base + "/" + slug end
end

fun children_of(parent: int?, depth: int, folders: array<Folder>, pages: array<PageRow>, paths: map<int, string>, out: array<Item>)
    for f in folders do
        if f.parent_id == parent then
            out.push(Item { kind: "folder", id: f.id, title: f.title, slug: f.slug, path: paths[f.id] ?? f.slug, depth: depth, revision: 0, updated_at: 0, parent_id: f.parent_id })
            children_of(f.id, depth + 1, folders, pages, paths, out)
        end
    end
    for p in pages do
        if p.folder_id == parent then
            out.push(Item { kind: "page", id: p.id, title: p.title, slug: p.slug, path: page_path(p.folder_id, p.slug, paths), depth: depth, revision: p.revision, updated_at: p.updated_at, parent_id: p.folder_id })
        end
    end
end

--" The whole tree of a language as a flat list: each folder, then what is inside it (folders first, then pages, each by position). --"
fun flatten(folders: array<Folder>, pages: array<PageRow>) -> array<Item>
    let out: array<Item> = []
    children_of(none, 0, folders, pages, folder_paths(folders), out)
    out
end

export Item, folder_paths, page_path, flatten
