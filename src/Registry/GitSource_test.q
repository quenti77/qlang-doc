import describe, it, expect, finish from "@test"
import Tag from "./Models.q"
import GitSource from "./GitSource.q"

--" Makes a real repository on disk, with two tags, and reads it through `file://`. Needs `git` and `--allow-process`. --"
fun make_repo() -> string
    let dir = "{env.get("TMPDIR") ?? "/tmp"}/qlang-doc-test-{ulid.new()}"
    fs.create_dir(dir)
    let run = fun(args: array<string>) -> bool
        let r = Process.run_with("git", args, ProcessOptions { cwd: dir, env: { "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t" }, timeout_ms: 20000 })
        r.is_ok() and r.unwrap().status == 0
    end
    run(["init", "-q", "-b", "main"])
    fs.write("{dir}/qlang.toml", "[package]\nname = \"demo\"\nversion = \"1.0.0\"\ndescription = \"A demo\"\nlicense = \"MIT\"\n")
    fs.write("{dir}/README.md", "# Demo\n\nHello.\n")
    run(["add", "."])
    run(["commit", "-q", "-m", "one"])
    run(["tag", "v1.0.0"])
    fs.write("{dir}/README.md", "# Demo\n\nHello again.\n")
    run(["commit", "-q", "-am", "two"])
    run(["tag", "v1.1.0"])
    dir
end

fun test_suite()
    describe("GitSource", fun()
        it("lists tags and reads the files of a tag, then cleans up", fun()
            let dir = make_repo()
            let source = GitSource { protocol: "file", timeout_ms: 30000 }
            let tags = source.tags("file://{dir}").unwrap().map(fun(t: Tag) -> string t.name end)
            expect(tags.join(" ")).to_be("v1.0.0 v1.1.0")
            let snap = source.snapshot("file://{dir}", "v1.0.0").unwrap()
            expect(snap.manifest.contains("A demo")).to_be(true)
            expect(snap.readme.contains("Hello.")).to_be(true)
            expect(snap.readme.contains("again")).to_be(false)
            expect(source.snapshot("file://{dir}", "v9.9.9").is_err()).to_be(true)
            fs.remove_dir(dir, all: true)
        end)

        it("does not follow a README that is a link to a file of the machine", fun()
            let secret = "{env.get("TMPDIR") ?? "/tmp"}/qlang-doc-secret-{ulid.new()}"
            fs.write(secret, "TOP-SECRET-CONTENT")
            let dir = "{env.get("TMPDIR") ?? "/tmp"}/qlang-doc-test-{ulid.new()}"
            fs.create_dir(dir)
            let run = fun(args: array<string>) -> bool
                let r = Process.run_with("git", args, ProcessOptions { cwd: dir, env: { "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t" }, timeout_ms: 20000 })
                r.is_ok() and r.unwrap().status == 0
            end
            run(["init", "-q", "-b", "main"])
            fs.write("{dir}/qlang.toml", "[package]\nname = \"demo\"\n")
            run(["add", "."])
            run(["commit", "-q", "-m", "one"])
            Process.run("ln", ["-s", secret, "{dir}/README.md"])
            run(["add", "."])
            run(["commit", "-q", "-m", "link"])
            run(["tag", "v1.0.0"])
            let snap = GitSource { protocol: "file", timeout_ms: 30000 }.snapshot("file://{dir}", "v1.0.0").unwrap()
            expect(snap.readme.contains("TOP-SECRET-CONTENT")).to_be(false)
            fs.remove_dir(dir, all: true)
            fs.remove(secret)
        end)

        it("refuses a protocol that was not allowed", fun()
            let source = GitSource { protocol: "https", timeout_ms: 5000 }
            expect(source.tags("file:///tmp").is_err()).to_be(true)
        end)
    end)

    finish()
end
