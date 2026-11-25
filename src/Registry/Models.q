--" What the registry knows: packages (git repositories with a `qlang.toml` and tags `vX.Y.Z`) and their versions. --"

--" status: `pending` (submitted, waiting for a moderator), `listed` (in the index) or `removed` (withdrawn: `qlang add` refuses it). --"
struct Package
    public id: int
    public name: string
    public git_url: string
    public description: string
    public license: string
    public keywords: array<string>
    public readme_html: string
    public status: string
    public removed_reason: string
    public latest_version: string
    public sync_requested: bool
    public sync_error: string
    public synced_at: int
    public created_at: int
end

struct PackageVersion
    public id: int
    public version: string
    public commit_sha: string
    public yanked: bool
    public qlang_req: string
    public first_seen: int
end

--" A tag of a git repository and the commit it points to. --"
struct Tag
    public name: string
    public sha: string
end

--" The files of a package at one tag that the registry reads. --"
struct Snapshot
    public manifest: string
    public readme: string
end

--" Where the registry reads git repositories from. The worker gives it the real one (`git`), the tests a fake one. --"
struct Source
    public tags: fun(string) -> Result<array<Tag>, string>
    public snapshot: fun(string, string) -> Result<Snapshot, string>
end

struct SyncReport
    public added: int
    public latest: string
    public warning: string
end

export Package, PackageVersion, Tag, Snapshot, Source, SyncReport
