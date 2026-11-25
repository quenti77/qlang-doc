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

    finish()
end
