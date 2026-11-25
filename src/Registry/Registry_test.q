import describe, it, expect, finish from "@test"
import Store from "../Docs/Store.q"
import fresh_db from "../Docs/TestSupport.q"
import PackageVersion, Tag, Snapshot, Source from "./Models.q"
import Options, Registry, check_git_url, valid_name from "./Registry.q"

let MANIFEST = "[package]\nname = \"json5\"\nversion = \"1.2.0\"\ndescription = \"JSON5 for qlang\"\nlicense = \"MIT\"\nkeywords = [\"json\", \"parser\"]\nqlang = \"1.11\"\n"

fun fake_source() -> Source
    Source {
        tags: fun(url: string) -> Result<array<Tag>, string>
            if url.contains("broken") then
                return Err("repository not found")
            end
            if url.contains("untagged") then
                return Ok([Tag { name: "nightly", sha: "aaa" }])
            end
            Ok([Tag { name: "v1.0.0", sha: "sha100" }, Tag { name: "v1.2.0", sha: "sha120" }, Tag { name: "v1.10.0-rc.1", sha: "sha110rc" }, Tag { name: "latest", sha: "x" }])
        end,
        snapshot: fun(url: string, tag: string) -> Result<Snapshot, string>
            Ok(Snapshot { manifest: MANIFEST, readme: "# json5\n\nParses **JSON5**. <script>alert(1)</script>" })
        end,
    }
end

fun registry(open: bool) -> Registry
    Registry.new(Store.new(fresh_db()), Options { submissions_open: open, hosts: ["github.com"] })
end

fun test_suite()
    describe("addresses and names", fun()
        it("keeps public https repositories only", fun()
            expect(check_git_url("https://github.com/me/json5.git", []).unwrap()).to_be("https://github.com/me/json5")
            expect(check_git_url("https://github.com/me/json5/", []).unwrap()).to_be("https://github.com/me/json5")
            for bad in ["http://github.com/me/x", "git@github.com:me/x.git", "https://localhost/me/x", "https://127.0.0.1/me/x", "https://10.0.0.1/me/x", "https://github.com/me", "https://user:pw@github.com/me/x", "https://github.com/me/x y", "file:///etc/passwd", "https://github.com/../x/y"] do
                expect(check_git_url(bad, []).is_err()).to_be(true)
            end
            expect(check_git_url("https://example.org/me/x", ["github.com"]).is_err()).to_be(true)
        end)

        it("accepts lowercase package names only", fun()
            expect(valid_name("json5")).to_be(true)
            expect(valid_name("my-pkg_2")).to_be(true)
            expect(valid_name("Json")).to_be(false)
            expect(valid_name("a b")).to_be(false)
            expect(valid_name("")).to_be(false)
        end)
    end)

    describe("submissions", fun()
        it("are closed unless the operator opens them", fun()
            expect(registry(false).submit("json5", "https://github.com/me/json5").is_err()).to_be(true)
        end)

        it("wait in the queue, and are not in the index until accepted", fun()
            let r = registry(true)
            let id = r.submit("json5", "https://github.com/me/json5").unwrap()
            expect(r.packages.package(id).unwrap().status).to_be("pending")
            expect(r.index_json().contains("json5")).to_be(false)
            expect(r.submit("json5", "https://github.com/me/other").is_err()).to_be(true)
            expect(r.submit("other", "https://github.com/me/json5.git").is_err()).to_be(true)
            expect(r.approve(id, none).is_ok()).to_be(true)
            expect(r.packages.package(id).unwrap().status).to_be("listed")
            expect(r.packages.package(id).unwrap().sync_requested).to_be(true)
            expect(r.approve(id, none).is_err()).to_be(true)
        end)

        it("can be refused, and then forgotten", fun()
            let r = registry(true)
            let id = r.submit("spam", "https://github.com/me/spam").unwrap()
            expect(r.reject(id, none).is_ok()).to_be(true)
            expect(r.packages.package(id) == none).to_be(true)
            expect(r.submit("spam", "https://github.com/me/spam").is_ok()).to_be(true)
        end)
    end)

    describe("reading a repository", fun()
        it("fills the page from the tags, the manifest and the README", fun()
            let r = registry(false)
            let id = r.add("json5", "https://github.com/me/json5", none).unwrap()
            let report = r.sync(id, fake_source()).unwrap()
            expect(report.latest).to_be("v1.2.0")
            expect(report.added).to_be(3)
            let p = r.packages.package(id).unwrap()
            expect(p.description).to_be("JSON5 for qlang")
            expect(p.license).to_be("MIT")
            expect(p.keywords.join(",")).to_be("json,parser")
            expect(p.sync_requested).to_be(false)
            expect(p.readme_html.contains("<strong>JSON5</strong>")).to_be(true)
            expect(p.readme_html.contains("<script>")).to_be(false)
            let versions = r.versions(id).map(fun(v: PackageVersion) -> string v.version end)
            expect(versions.join(" ")).to_be("v1.10.0-rc.1 v1.2.0 v1.0.0")
            expect(r.sync(id, fake_source()).unwrap().added).to_be(0)
        end)

        it("keeps the reason when it cannot read", fun()
            let r = registry(false)
            let id = r.add("broken", "https://github.com/me/broken", none).unwrap()
            expect(r.sync(id, fake_source()).is_err()).to_be(true)
            expect(r.packages.package(id).unwrap().sync_error).to_be("repository not found")
            let u = r.add("untagged", "https://github.com/me/untagged", none).unwrap()
            expect(r.sync(u, fake_source()).is_err()).to_be(true)
            expect(r.packages.package(u).unwrap().sync_error.contains("vX.Y.Z")).to_be(true)
        end)

        it("reads what is due, and no more", fun()
            let r = registry(false)
            let a = r.add("json5", "https://github.com/me/json5", none).unwrap()
            expect(r.sync_due(fake_source(), 3600000, 10).len()).to_be(1)
            expect(r.sync_due(fake_source(), 3600000, 10).len()).to_be(0)
            r.request_sync(a)
            expect(r.sync_due(fake_source(), 3600000, 10).len()).to_be(1)
        end)

        it("is asked by a webhook for a package it knows", fun()
            let r = registry(false)
            let a = r.add("json5", "https://github.com/me/json5", none).unwrap()
            r.sync(a, fake_source())
            expect(r.request_sync_for_url("https://github.com/Me/json5.git")).to_be(true)
            expect(r.packages.package(a).unwrap().sync_requested).to_be(true)
            expect(r.request_sync_for_url("https://github.com/me/unknown")).to_be(false)
        end)
    end)

    describe("the index", fun()
        it("is the format of qlang search, with yanked versions and removals", fun()
            let r = registry(true)
            let a = r.add("json5", "https://github.com/me/json5", none).unwrap()
            r.sync(a, fake_source())
            let b = r.add("old", "https://github.com/me/old", none).unwrap()
            r.submit("waiting", "https://github.com/me/waiting")
            expect(r.yank(a, "v1.0.0", true, none).is_ok()).to_be(true)
            expect(r.yank(a, "v9.9.9", true, none).is_err()).to_be(true)
            expect(r.remove(b, "", none).is_err()).to_be(true)
            expect(r.remove(b, "abandoned by its author", none).is_ok()).to_be(true)
            let index = Json.parse(r.index_json()).unwrap()
            let json5 = index.get("json5").unwrap()
            expect(json5.get("git").unwrap().as_string()).to_be("https://github.com/me/json5")
            expect(json5.get("license").unwrap().as_string()).to_be("MIT")
            expect(json5.get("yanked").unwrap().to_text()).to_be("[\"v1.0.0\"]")
            expect(index.get("old").unwrap().get("removed").unwrap().as_string()).to_be("abandoned by its author")
            expect(index.get("waiting") == none).to_be(true)
            expect(r.restore(b, none).is_ok()).to_be(true)
            expect(Json.parse(r.index_json()).unwrap().get("old").unwrap().get("removed") == none).to_be(true)
        end)
    end)

    finish()
end
