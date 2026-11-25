import describe, it, expect, finish from "@test"
import highlight from "./Highlight.q"

fun test_suite()
    describe("highlight", fun()
        it("colours keywords, names, strings and comments", fun()
            let html = highlight("fun hello() -> string\n    \"a\" -- note\nend")
            expect(html.contains("<span class=\"tk-decl\">fun</span>")).to_be(true)
            expect(html.contains("<span class=\"tk-fndef\">hello</span>")).to_be(true)
            expect(html.contains("<span class=\"tk-type\">string</span>")).to_be(true)
            expect(html.contains("<span class=\"tk-string\">&quot;a&quot;</span>") or html.contains("<span class=\"tk-string\">\"a\"</span>")).to_be(true)
            expect(html.contains("<span class=\"tk-comment\">-- note</span>")).to_be(true)
            expect(html.contains("<span class=\"tk-control\">end</span>")).to_be(true)
        end)

        it("escapes HTML in the code", fun()
            let html = highlight("a < b")
            expect(html.contains("&lt;")).to_be(true)
            expect(html.contains("<b")).to_be(false)
        end)

        it("keeps a documentation block as one piece", fun()
            let html = highlight("--\" about\nthe thing --\"\nlet x = 1")
            expect(html.contains("<span class=\"tk-doc\">")).to_be(true)
            expect(html.contains("<span class=\"tk-number\">1</span>")).to_be(true)
        end)
    end)

    finish()
end
