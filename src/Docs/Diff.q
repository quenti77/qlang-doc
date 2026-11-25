--" A line diff, to show what a change did to a page. --"

--" One line of a diff: `same`, `add` (only in the new text) or `del` (only in the old one), with its line numbers
(0 when the line does not exist on that side). --"
struct Line
    public kind: string
    public text: string
    public old_no: int
    public new_no: int
end

--" How many lines were added and removed. --"
struct Stats
    public added: int
    public removed: int
end

let MAX_CELLS = 4000000

fun line(kind: string, text: string, old_no: int, new_no: int) -> Line
    Line { kind: kind, text: text, old_no: old_no, new_no: new_no }
end

--" The lines of `old` and `new`, in order, each marked same / add / del. --"
fun diff(old: string, new: string) -> array<Line>
    let a = old.split("\n")
    let b = new.split("\n")
    let na = a.len()
    let nb = b.len()
    let prefix = 0
    while prefix < na and prefix < nb and a[prefix] == b[prefix] do
        prefix = prefix + 1
    end
    let suffix = 0
    while suffix < na - prefix and suffix < nb - prefix and a[na - 1 - suffix] == b[nb - 1 - suffix] do
        suffix = suffix + 1
    end
    let out: array<Line> = []
    let k = 0
    while k < prefix do
        out.push(line("same", a[k], k + 1, k + 1))
        k = k + 1
    end
    let n = na - prefix - suffix
    let m = nb - prefix - suffix
    if n * m > MAX_CELLS then
        for i in 0..n do
            out.push(line("del", a[prefix + i], prefix + i + 1, 0))
        end
        for j in 0..m do
            out.push(line("add", b[prefix + j], 0, prefix + j + 1))
        end
    else
        for l in middle(a, b, prefix, n, m) do
            out.push(l)
        end
    end
    let tail = 0
    while tail < suffix do
        out.push(line("same", a[na - suffix + tail], na - suffix + tail + 1, nb - suffix + tail + 1))
        tail = tail + 1
    end
    out
end

--" The diff of the part that differs: the longest common subsequence of `n` lines of `a` and `m` lines of `b`, both starting at `at`. --"
fun middle(a: array<string>, b: array<string>, at: int, n: int, m: int) -> array<Line>
    let out: array<Line> = []
    if n == 0 and m == 0 then
        return out
    end
    let width = m + 1
    let table: array<int> = []
    for _k in 0..((n + 1) * width) do
        table.push(0)
    end
    let i = n - 1
    while i >= 0 do
        let j = m - 1
        while j >= 0 do
            if a[at + i] == b[at + j] then
                table[i * width + j] = table[(i + 1) * width + j + 1] + 1
            else
                let down = table[(i + 1) * width + j]
                let right = table[i * width + j + 1]
                table[i * width + j] = if down >= right then down else right end
            end
            j = j - 1
        end
        i = i - 1
    end
    let x = 0
    let y = 0
    while x < n and y < m do
        if a[at + x] == b[at + y] then
            out.push(line("same", a[at + x], at + x + 1, at + y + 1))
            x = x + 1
            y = y + 1
        elseif table[(x + 1) * width + y] >= table[x * width + y + 1] then
            out.push(line("del", a[at + x], at + x + 1, 0))
            x = x + 1
        else
            out.push(line("add", b[at + y], 0, at + y + 1))
            y = y + 1
        end
    end
    while x < n do
        out.push(line("del", a[at + x], at + x + 1, 0))
        x = x + 1
    end
    while y < m do
        out.push(line("add", b[at + y], 0, at + y + 1))
        y = y + 1
    end
    out
end

fun stats(lines: array<Line>) -> Stats
    let added = 0
    let removed = 0
    for l in lines do
        if l.kind == "add" then
            added = added + 1
        elseif l.kind == "del" then
            removed = removed + 1
        end
    end
    Stats { added: added, removed: removed }
end

--" Only the changed lines and `context` unchanged ones around them, in groups (a hunk each). --"
fun hunks(lines: array<Line>, context: int) -> array<array<Line>>
    let keep: array<bool> = []
    for _l in lines do
        keep.push(false)
    end
    let i = 0
    while i < lines.len() do
        if lines[i].kind != "same" then
            let first = if i - context < 0 then 0 else i - context end
            let last = if i + context >= lines.len() then lines.len() - 1 else i + context end
            for k in first..(last + 1) do
                keep[k] = true
            end
        end
        i = i + 1
    end
    let out: array<array<Line>> = []
    let current: array<Line> = []
    for k in 0..lines.len() do
        if keep[k] then
            current.push(lines[k])
        elseif current.len() > 0 then
            out.push(current)
            current = []
        end
    end
    if current.len() > 0 then
        out.push(current)
    end
    out
end

export Line, Stats, diff, stats, hunks
