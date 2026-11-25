--" Syntax highlighting of qlang code, done on the server: the page carries the colours, no script is needed. --"

fun word_set(words: string) -> map<string, bool>
    let out: map<string, bool> = {}
    for w in words.split(" ") do
        out[w] = true
    end
    out
end

let CONTROL = word_set("if then elseif else end while for in step do break continue match case return")
let DECL = word_set("fun struct impl trait enum let const")
let MODIFIER = word_set("public private protected static override extends import export from as")
let OPERATOR_WORDS = word_set("and or not mod")
let ATOMS = word_set("true false none self super")
let TYPES = word_set("int float bool string uuid ulid array map range")

--" Escapes the characters that have a meaning in HTML. --"
fun escape(text: string) -> string
    text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
end

fun span(kind: string, text: string) -> string
    "<span class=\"tk-{kind}\">{escape(text)}</span>"
end

fun is_word_start(c: string) -> bool
    c == "_" or c.is_alpha()
end

fun is_word_char(c: string) -> bool
    c == "_" or c.is_alpha() or c.is_digit()
end

fun classify(word: string, previous: string) -> string
    if CONTROL.has(word) then return "control" end
    if DECL.has(word) then return "decl" end
    if MODIFIER.has(word) then return "modifier" end
    if OPERATOR_WORDS.has(word) then return "opword" end
    if ATOMS.has(word) then return "atom" end
    if TYPES.has(word) then return "type" end
    if previous == "fun" then return "fndef" end
    if previous == "struct" or previous == "enum" or previous == "trait" or previous == "extends" then return "typedef" end
    let first = word.chars()[0]
    if first.is_alpha() and first == first.upper() then return "type" end
    "name"
end

--" The code as HTML, one `<span>` per coloured piece. --"
fun highlight(code: string) -> string
    let chars = code.chars()
    let n = chars.len()
    let out = ""
    let i = 0
    let previous = ""
    while i < n do
        let c = chars[i]
        let start = i
        if c == "-" and i + 1 < n and chars[i + 1] == "-" then
            let doc = i + 2 < n and chars[i + 2] == "\""
            if doc then
                i = i + 3
                while i < n and not (chars[i] == "-" and i + 2 < n and chars[i + 1] == "-" and chars[i + 2] == "\"") do
                    i = i + 1
                end
                i = i + 3
                if i > n then i = n end
            else
                while i < n and chars[i] != "\n" do
                    i = i + 1
                end
            end
            out = out + span(if doc then "doc" else "comment" end, chars.slice(start, i).join(""))
        elseif c == "\"" then
            i = i + 1
            while i < n and chars[i] != "\"" do
                if chars[i] == "\\" then
                    i = i + 1
                end
                i = i + 1
            end
            i = i + 1
            if i > n then i = n end
            out = out + span("string", chars.slice(start, i).join(""))
        elseif c.is_digit() then
            while i < n and (chars[i].is_digit() or chars[i] == "." or chars[i] == "_") do
                i = i + 1
            end
            out = out + span("number", chars.slice(start, i).join(""))
        elseif is_word_start(c) then
            while i < n and is_word_char(chars[i]) do
                i = i + 1
            end
            let word = chars.slice(start, i).join("")
            let kind = classify(word, previous)
            if kind == "name" and i < n and chars[i] == "(" then
                kind = "fn"
            end
            previous = word
            out = out + span(kind, word)
        elseif c == " " or c == "\n" or c == "\t" then
            i = i + 1
            out = out + c
        else
            i = i + 1
            out = out + span("punct", c)
        end
        if c != " " and c != "\n" and c != "\t" and not is_word_start(c) then
            previous = ""
        end
    end
    out
end

export highlight, escape
