import describe, it, expect, finish from "@test"
import Line, diff, stats, hunks from "./Diff.q"

fun kinds(text_a: string, text_b: string) -> string
    diff(text_a, text_b).map(fun(l: Line) -> string
        if l.kind == "same" then "=" elseif l.kind == "add" then "+" else "-" end
    end).join("")
end

fun test_suite()
    describe("diff", fun()
        it("sees no change in identical texts", fun()
            expect(kinds("a\nb\nc", "a\nb\nc")).to_be("===")
        end)

        it("finds added, removed and changed lines", fun()
            expect(kinds("a\nb\nc", "a\nb\nc\nd")).to_be("===+")
            expect(kinds("a\nb\nc", "a\nc")).to_be("=-=")
            expect(kinds("a\nb\nc", "a\nx\nc")).to_be("=-+=")
        end)

        it("numbers the lines of each side", fun()
            let lines = diff("a\nb\nc", "a\nx\nc")
            expect(lines[1].old_no).to_be(2)
            expect(lines[1].new_no).to_be(0)
            expect(lines[2].old_no).to_be(0)
            expect(lines[2].new_no).to_be(2)
            expect(lines[3].old_no).to_be(3)
            expect(lines[3].new_no).to_be(3)
        end)

        it("counts what changed", fun()
            let s = stats(diff("a\nb\nc\nd", "a\nB\nc\nd\ne"))
            expect(s.added).to_be(2)
            expect(s.removed).to_be(1)
        end)

        it("groups the changes with a little context", fun()
            let old_text = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12"
            let new_text = "1\nX\n3\n4\n5\n6\n7\n8\n9\n10\n11\nY"
            let groups = hunks(diff(old_text, new_text), 1)
            expect(groups.len()).to_be(2)
            expect(groups[0].len()).to_be(4)
        end)
    end)

    finish()
end
