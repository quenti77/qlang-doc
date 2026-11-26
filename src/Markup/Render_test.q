import describe, it, expect, finish from "@test"
import render_page from "./Render.q"

fun test_suite()
    describe("render_page", fun()
        it("colours qlang code and leaves other languages escaped", fun()
            let doc = render_page("# Guide\n\n```qlang\nlet a = 1\n```\n\n```sh\na < b\n```")
            expect(doc.title).to_be("Guide")
            expect(doc.html.contains("<span class=\"tk-decl\">let</span>")).to_be(true)
            expect(doc.html.contains("a &lt; b")).to_be(true)
        end)
    end)

    describe("diff blocks", fun()
        it("colour the code of a diff-<language> block and keep the markers", fun()
            let doc = render_page("```diff-qlang\n@@ -1 +1 @@\n-let a = 1\n+let a = 2\n print(a)\n```")
            expect(doc.html.contains("class=\"language-diff-qlang\"")).to_be(true)
            expect(doc.html.contains("-<span class=\"tk-decl\">let</span>")).to_be(true)
            expect(doc.html.contains("+<span class=\"tk-decl\">let</span>")).to_be(true)
            expect(doc.html.contains("@@ -1 +1 @@")).to_be(true)
        end)
    end)

    describe("alerts", fun()
        it("turns [!INFO], [!SUCCESS], [!WARNING] and [!DANGER] into alert boxes and leaves other quotes alone", fun()
            let doc = render_page("> [!INFO]\n> a\n\n> [!success]\n> b\n\n> [!WARNING]\n> c\n\n> [!DANGER]\n> d\n\n> plain\n\n```\n> [!INFO]\n```")
            for kind in ["note", "tip", "warning", "caution"] do
                expect(doc.html.contains("markdown-alert-" + kind)).to_be(true)
            end
            expect(doc.html.contains("<blockquote>")).to_be(true)
            expect(doc.html.contains("<p class=\"markdown-alert-title\"></p>")).to_be(true)
            expect(doc.html.contains(">Warning</p>")).to_be(false)
            expect(doc.html.contains("[!INFO]")).to_be(true)
        end)
    end)

    finish()
end
