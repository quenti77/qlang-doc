--" Versions of packages: tags `v1.2.3` or `v1.2.3-rc.1`, ordered the way qlang orders them. --"

struct Version
    public major: int
    public minor: int
    public patch: int
    public pre: string
end

--" `v1.2.3` or `1.2.3-rc.1` as numbers; none when it is not a version. --"
fun parse(tag: string) -> Version?
    let text = tag.strip_prefix("v") ?? tag
    let core = text
    let pre = ""
    let dash = text.index_of("-")
    if dash != none then
        core = text.substring(0, dash)
        pre = text.substring(dash + 1, text.len())
    end
    for c in pre.chars() do
        if not (c.is_alpha() or c.is_digit() or c == "." or c == "-") then
            return none
        end
    end
    let parts = core.split(".")
    if parts.len() != 3 then
        return none
    end
    let numbers: array<int> = []
    for p in parts do
        let n = p.to_int()
        if n == none or n < 0 or p.len() > 9 then
            return none
        end
        numbers.push(n)
    end
    Version { major: numbers[0], minor: numbers[1], patch: numbers[2], pre: pre }
end

--" -1, 0 or 1. A pre-release (`1.0.0-rc.1`) comes before its release (`1.0.0`). --"
fun compare(a: Version, b: Version) -> int
    if a.major != b.major then
        return if a.major < b.major then -1 else 1 end
    end
    if a.minor != b.minor then
        return if a.minor < b.minor then -1 else 1 end
    end
    if a.patch != b.patch then
        return if a.patch < b.patch then -1 else 1 end
    end
    if a.pre == b.pre then
        return 0
    end
    if a.pre == "" then
        return 1
    end
    if b.pre == "" then
        return -1
    end
    if a.pre < b.pre then -1 else 1 end
end

--" The tags sorted from the newest to the oldest, the ones that are not versions dropped. --"
fun newest_first(tags: array<string>) -> array<string>
    let valid = tags.filter(fun(t: string) -> bool parse(t) != none end)
    valid.sorted_by(fun(a: string, b: string) -> int compare(parse(b).unwrap(), parse(a).unwrap()) end)
end

--" The newest tag that is not a pre-release, or the newest of all when there is only pre-releases. --"
fun latest(tags: array<string>) -> string?
    let sorted = newest_first(tags)
    for t in sorted do
        if parse(t).unwrap().pre == "" then
            return t
        end
    end
    if sorted.is_empty() then none else sorted[0] end
end

export Version, parse, compare, newest_first, latest
