import highlight from "../Markup/Highlight.q"

let SAMPLE = "struct Greeter
    public name: string
end

impl Greeter
    public fun hello(self) -> string
        \"Bonjour \{self.name\} !\"
    end
end

print(Greeter \{ name: \"qlang\" \}.hello())"

--" The front page: what qlang is, where to learn it, where to find packages. --"
fun home_page() -> string
    "<!doctype html>
<html lang=\"fr\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
<title>qlang</title><script src=\"/theme.js\"></script><link rel=\"stylesheet\" href=\"/site.css\"></head>
<body>
<header class=\"top\"><div class=\"wrap\">
<a class=\"brand\" href=\"/\">q<b>lang</b></a>
<nav class=\"main\"><a href=\"/docs\">Documentation</a><a href=\"/packages\">Paquets</a><a href=\"/playground\">Playground</a></nav>
<span class=\"lang\">FR · EN</span>
<span class=\"theme\" role=\"group\" aria-label=\"Thème\"><button type=\"button\" data-theme-set=\"light\">Clair</button><button type=\"button\" data-theme-set=\"dark\">Sombre</button><button type=\"button\" data-theme-set=\"system\">Auto</button></span>
</div></header>
<main class=\"wrap\">
<section class=\"hero\">
<h1>Un langage simple,<br>lisible et typé.</h1>
<p>qlang est un langage interprété, pensé pour apprendre à programmer. Sa syntaxe est en anglais et ressemble aux vrais langages (Rust, TypeScript, Lua).</p>
<a class=\"btn primary\" href=\"/docs\">Commencer</a><a class=\"btn\" href=\"/packages\">Parcourir les paquets</a>
</section>
<pre class=\"sample\">{highlight(SAMPLE)}</pre>
<section class=\"grid\">
<div class=\"card\"><h3>Documentation</h3><p>Le guide du langage, la bibliothèque standard et la référence, en français et en anglais.</p></div>
<div class=\"card\"><h3>Paquets</h3><p>Le registre des paquets : <span class=\"install\">qlang add nom</span>, versions, README, licence.</p></div>
<div class=\"card\"><h3>Playground</h3><p>Essayer qlang dans le navigateur, sans rien installer.</p></div>
</section>
</main>
<footer><div class=\"wrap\">qlang · site en cours de refonte</div></footer>
<script src=\"/theme-toggle.js\"></script>
</body></html>"
end

export home_page
