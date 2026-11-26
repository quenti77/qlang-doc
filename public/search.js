(function () {
  var form = document.querySelector("form.search");
  if (!form) return;
  var input = form.querySelector("input[name=q]");
  var fr = (document.documentElement.lang || "").toLowerCase().indexOf("fr") === 0;
  var T = fr
    ? { none: "Aucun résultat.", all: "Voir tous les résultats", placeholder: input.placeholder, hint: "↑↓ pour naviguer · Entrée pour ouvrir · Échap pour fermer" }
    : { none: "Nothing found.", all: "See all results", placeholder: input.placeholder, hint: "↑↓ to move · Enter to open · Esc to close" };
  var mac = /Mac|iPhone|iPad/.test(navigator.platform || "");
  var version = new URLSearchParams(location.search).get("v");

  function allUrl(q) {
    return form.getAttribute("action") + "?q=" + encodeURIComponent(q) + (version ? "&v=" + encodeURIComponent(version) : "");
  }

  // the query is marked in a text, without ever building HTML from it
  function marked(node, text, q) {
    var at = q ? text.toLowerCase().indexOf(q.toLowerCase()) : -1;
    if (at < 0) { node.textContent = text; return; }
    node.appendChild(document.createTextNode(text.slice(0, at)));
    var m = document.createElement("mark");
    m.textContent = text.slice(at, at + q.length);
    node.appendChild(m);
    node.appendChild(document.createTextNode(text.slice(at + q.length)));
  }

  // a list of results fed by an input; `close` is called when a result is chosen or Escape is pressed
  function results(field, list, close) {
    var timer, serial = 0, current = -1, items = [], last = "";

    function select(i) {
      items.forEach(function (li, n) { li.setAttribute("aria-selected", String(n === i)); });
      current = i;
      if (items[i]) items[i].scrollIntoView({ block: "nearest" });
    }
    function clear() { list.textContent = ""; items = []; current = -1; list.hidden = true; }

    function show(data, q) {
      list.textContent = "";
      items = [];
      current = -1;
      var hits = data.hits || [];
      if (!hits.length) {
        var none = document.createElement("li");
        none.className = "none";
        none.textContent = T.none;
        list.appendChild(none);
      }
      hits.forEach(function (h) {
        var li = document.createElement("li");
        li.setAttribute("role", "option");
        var a = document.createElement("a");
        a.href = h.url;
        var title = document.createElement("strong");
        marked(title, h.title, q);
        var path = document.createElement("span");
        path.className = "muted path";
        path.textContent = h.path;
        var ex = document.createElement("span");
        ex.className = "excerpt";
        marked(ex, h.excerpt, q);
        a.appendChild(title); a.appendChild(path); a.appendChild(ex);
        a.addEventListener("click", close);
        li.appendChild(a);
        list.appendChild(li);
        items.push(li);
      });
      if (hits.length) {
        var more = document.createElement("li");
        more.className = "all";
        var link = document.createElement("a");
        link.href = allUrl(q);
        link.textContent = T.all + " →";
        more.appendChild(link);
        list.appendChild(more);
        items.push(more);
      }
      list.hidden = false;
    }

    function run() {
      var q = field.value.trim();
      if (q.length < 2) { last = ""; clear(); return; }
      if (q === last) return;
      last = q;
      var mine = ++serial;
      var url = form.getAttribute("action") + "?format=json&limit=5&q=" + encodeURIComponent(q) + (version ? "&v=" + encodeURIComponent(version) : "");
      fetch(url, { headers: { Accept: "application/json" } })
        .then(function (r) { return r.ok ? r.json() : { hits: [] }; })
        .then(function (data) { if (mine === serial) show(data, q); })
        .catch(function () { if (mine === serial) clear(); });
    }

    field.addEventListener("input", function () { clearTimeout(timer); timer = setTimeout(run, 120); });
    field.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown" && items.length) { e.preventDefault(); select((current + 1) % items.length); }
      else if (e.key === "ArrowUp" && items.length) { e.preventDefault(); select((current - 1 + items.length) % items.length); }
      else if (e.key === "Enter") {
        var a = items[current] && items[current].querySelector("a");
        e.preventDefault();
        if (a) { close(); location.href = a.href; }
        else if (field.value.trim() !== "") { close(); location.href = allUrl(field.value.trim()); }
      }
      else if (e.key === "Escape") { clearTimeout(timer); close(); }
    });
    return { run: run, clear: clear, reset: function () { last = ""; clear(); } };
  }

  // under the box of the header
  var drop = document.createElement("ul");
  drop.className = "search-results";
  drop.setAttribute("role", "listbox");
  drop.hidden = true;
  form.appendChild(drop);
  var header = results(input, drop, function () { drop.hidden = true; });
  input.addEventListener("focus", function () { if (drop.children.length) drop.hidden = false; });
  document.addEventListener("click", function (e) { if (!form.contains(e.target)) drop.hidden = true; });
  form.addEventListener("keydown", function (e) { if (e.key === "Escape") { drop.hidden = true; } });

  var badge = document.createElement("kbd");
  badge.className = "search-key";
  badge.textContent = mac ? "⌘K" : "Ctrl K";
  badge.setAttribute("aria-hidden", "true");
  form.appendChild(badge);
  input.addEventListener("focus", function () { badge.hidden = true; });
  input.addEventListener("blur", function () { badge.hidden = input.value !== ""; });

  // Ctrl+K (or Cmd+K, or "/") opens the palette
  var palette, pfield, plist, presults;
  function open() {
    if (!palette) {
      palette = document.createElement("dialog");
      palette.className = "palette";
      pfield = document.createElement("input");
      pfield.type = "search";
      pfield.placeholder = T.placeholder;
      pfield.setAttribute("aria-label", T.placeholder);
      plist = document.createElement("ul");
      plist.className = "search-results";
      plist.setAttribute("role", "listbox");
      plist.hidden = true;
      var hint = document.createElement("p");
      hint.className = "muted palette-hint";
      hint.textContent = T.hint;
      palette.appendChild(pfield); palette.appendChild(plist); palette.appendChild(hint);
      document.body.appendChild(palette);
      presults = results(pfield, plist, function () { palette.close(); });
      palette.addEventListener("click", function (e) { if (e.target === palette) palette.close(); });
    }
    drop.hidden = true;
    pfield.value = input.value;
    presults.reset();
    if (palette.showModal) palette.showModal(); else palette.setAttribute("open", "");
    pfield.focus();
    pfield.select();
    presults.run();
  }
  document.addEventListener("keydown", function (e) {
    var typing = /^(INPUT|TEXTAREA|SELECT)$/.test((e.target.tagName || "")) || e.target.isContentEditable;
    if ((e.key === "k" || e.key === "K") && (e.ctrlKey || e.metaKey)) { e.preventDefault(); open(); }
    else if (e.key === "/" && !typing && !e.ctrlKey && !e.metaKey && !e.altKey) { e.preventDefault(); open(); }
  });
  badge.addEventListener("click", function () { open(); });
})();
