import Tag, Snapshot, Source from "./Models.q"

--" Reads git repositories with the `git` program. Only the worker (`tools/sync-packages.q`, run with `--allow-process`) imports this
file: the web server never runs a program. What it does is narrow on purpose: it lists tags, and clones one tag with no history into a
folder that it deletes at once, to read `qlang.toml` and the README. Nothing from the repository is ever run. --"

let MAX_FILE = 1048576

struct GitSource
    --" The protocol git may use (`https`; the tests use `file`). --"
    public protocol: string
    public timeout_ms: int
end

fun git_env() -> map<string, string>
    { "GIT_TERMINAL_PROMPT": "0", "GIT_CONFIG_NOSYSTEM": "1", "GIT_ASKPASS": "true", "GIT_ALLOW_PROTOCOL": "https" }
end

impl GitSource
    public fun https() -> GitSource
        GitSource { protocol: "https", timeout_ms: 60000 }
    end

    fun git(self, args: array<string>) -> Result<string, string>
        let guard = ["-c", "protocol.allow=never", "-c", "protocol.{self.protocol}.allow=always", "-c", "core.symlinks=false", "-c", "core.fsmonitor=false"]
        let env = git_env()
        env["GIT_ALLOW_PROTOCOL"] = self.protocol
        let r = Process.run_with("git", guard.concat(args), ProcessOptions { env: env, timeout_ms: self.timeout_ms })
        if r.is_err() then
            return Err("git : {r.unwrap_err().message}")
        end
        if r.unwrap().status != 0 then
            let said = r.unwrap().stderr.trim()
            return Err("git : {if said == "" then "échec" else said.lines()[0] end}")
        end
        Ok(r.unwrap().stdout)
    end

    --" The tags of a repository with the commit each points to (`git ls-remote --tags --refs`). --"
    public fun tags(self, url: string) -> Result<array<Tag>, string>
        let out = self.git(["ls-remote", "--tags", "--refs", "--", url])
        if out.is_err() then
            return Err(out.unwrap_err())
        end
        let tags: array<Tag> = []
        for line in out.unwrap().lines() do
            let cells = line.split("\t")
            if cells.len() == 2 and cells[1].starts_with("refs/tags/") then
                tags.push(Tag { name: cells[1].substring(10, cells[1].len()), sha: cells[0] })
            end
        end
        Ok(tags)
    end

    fun read_file(self, dir: string, names: array<string>) -> string
        for name in names do
            let file = File.of("{dir}/{name}")
            let is_file = file.is_file()
            let link = file.is_link()
            if is_file.is_ok() and is_file.unwrap() and link.is_ok() and not link.unwrap() then
                let size = file.size()
                if size.is_ok() and size.unwrap() <= MAX_FILE then
                    let text = file.read()
                    if text.is_ok() then
                        return text.unwrap()
                    end
                end
            end
        end
        ""
    end

    --" `qlang.toml` and the README of a tag. The clone is deleted whatever happens. --"
    public fun snapshot(self, url: string, tag: string) -> Result<Snapshot, string>
        let base = env.get("TMPDIR") ?? "/tmp"
        let dir = "{base}/qlang-doc-sync-{ulid.new()}"
        fs.create_dir(dir)
        let cloned = self.git(["clone", "--quiet", "--depth", "1", "--single-branch", "--no-tags", "--branch", tag, "--", url, "{dir}/repo"])
        if cloned.is_err() then
            fs.remove_dir(dir, all: true)
            return Err(cloned.unwrap_err())
        end
        let manifest = self.read_file("{dir}/repo", ["qlang.toml"])
        let readme = self.read_file("{dir}/repo", ["README.md", "Readme.md", "readme.md", "README.markdown"])
        fs.remove_dir(dir, all: true)
        if manifest == "" then
            return Err("Pas de qlang.toml à la racine du dépôt (étiquette {tag}).")
        end
        Ok(Snapshot { manifest: manifest, readme: readme })
    end

    public fun source(self) -> Source
        Source {
            tags: fun(url: string) -> Result<array<Tag>, string> self.tags(url) end,
            snapshot: fun(url: string, tag: string) -> Result<Snapshot, string> self.snapshot(url, tag) end,
        }
    end
end

export GitSource
