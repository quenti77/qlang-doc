--" What the documentation is made of: folders hold folders and pages, a page keeps its revisions, a release is a
frozen copy of everything that the public site serves. --"

struct Account
    public id: int
    public login: string
    public role: string
    public password_hash: string
end

struct Folder
    public id: int
    public parent_id: int?
    public locale: string
    public slug: string
    public title: string
    public position: int
    public section: string
end

--" A page of the working copy (what the editors change). --"
struct Page
    public id: int
    public folder_id: int?
    public locale: string
    public slug: string
    public title: string
    public markdown: string
    public html: string
    public toc: string
    public position: int
    public revision: int
    public updated_at: int
    public updated_by: int?
end

--" A page without its text, for lists. --"
struct PageRow
    public id: int
    public folder_id: int?
    public locale: string
    public slug: string
    public title: string
    public position: int
    public revision: int
    public updated_at: int
end

struct Revision
    public id: int
    public page_id: int
    public number: int
    public title: string
    public markdown: string
    public source: string
    public summary: string
    public author: string
    public created_at: int
end

struct Release
    public id: int
    public label: string
    public qlang_version: string
    public note: string
    public author: string
    public created_at: int
    public pages: int
    public current: bool
end

--" A folder as a release kept it. --"
struct SnapFolder
    public locale: string
    public path: string
    public title: string
    public position: int
    public section: string
end

--" A page as a release kept it: served as is, whatever happens to the working copy afterwards. --"
struct SnapPage
    public locale: string
    public path: string
    public title: string
    public markdown: string
    public html: string
    public toc: string
    public position: int
end

struct AuditEntry
    public id: int
    public user: string
    public action: string
    public entity_type: string
    public entity_id: int?
    public summary: string
    public data: string
    public created_at: int
end

--" What the journal is narrowed to; an empty field means "no limit". Times are epoch milliseconds, `until` excluded. --"
struct AuditFilter
    public kind: string
    public user_id: int?
    public action: string
    public since: int?
    public until: int?
end

export AuditFilter, Account, Folder, Page, PageRow, Revision, Release, SnapFolder, SnapPage, AuditEntry
