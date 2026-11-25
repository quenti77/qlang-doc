import describe, it, expect, finish from "@test"
import parse, compare, newest_first, latest from "./Semver.q"

fun test_suite()
    describe("semver", fun()
        it("reads tags and refuses the others", fun()
            expect(parse("v1.2.3").unwrap().minor).to_be(2)
            expect(parse("1.0.0-rc.1").unwrap().pre).to_be("rc.1")
            expect(parse("latest") == none).to_be(true)
            expect(parse("v1.2") == none).to_be(true)
            expect(parse("v1.x.3") == none).to_be(true)
            expect(parse("v1.0.0-$(touch x)") == none).to_be(true)
        end)

        it("orders numbers, not texts, and puts pre-releases first", fun()
            expect(compare(parse("v1.10.0").unwrap(), parse("v1.9.0").unwrap())).to_be(1)
            expect(compare(parse("v1.0.0-rc.1").unwrap(), parse("v1.0.0").unwrap())).to_be(-1)
            expect(compare(parse("v2.0.0").unwrap(), parse("v2.0.0").unwrap())).to_be(0)
        end)

        it("sorts newest first and picks the latest release", fun()
            let tags = ["v0.9.0", "v1.10.0", "v1.2.0", "v2.0.0-rc.1", "nightly", "v1.9.5"]
            expect(newest_first(tags).join(" ")).to_be("v2.0.0-rc.1 v1.10.0 v1.9.5 v1.2.0 v0.9.0")
            expect(latest(tags)).to_be("v1.10.0")
            expect(latest(["v1.0.0-beta"])).to_be("v1.0.0-beta")
            expect(latest(["foo"]) == none).to_be(true)
        end)
    end)

    finish()
end
