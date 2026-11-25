import Docs from "../Docs/Docs.q"
import Section from "../Docs/Models.q"

--" A section as the header of the public site links to it. --"
struct SectionLink
    public title: string
    public url: string
end

fun links(docs: Docs, locale: string) -> array<SectionLink>
    docs.store.sections().map(fun(s: Section) -> SectionLink SectionLink { title: s.title, url: "/{locale}/{s.slug}" } end)
end

export SectionLink, links
