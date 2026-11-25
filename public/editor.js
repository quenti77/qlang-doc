(function () {
  var area = document.querySelector("textarea.editor");
  if (!area) return;

  var dirty = false;
  function changed() {
    dirty = true;
    area.dispatchEvent(new Event("input", { bubbles: true }));
    status();
  }

  // wraps the selection (or a placeholder) in a marker; running it again on the same text removes it
  function wrap(before, after, placeholder) {
    var s = area.selectionStart, e = area.selectionEnd, text = area.value;
    var chosen = text.slice(s, e) || placeholder;
    if (text.slice(s - before.length, s) === before && text.slice(e, e + after.length) === after) {
      area.setRangeText(chosen, s - before.length, e + after.length, "select");
    } else {
      area.setRangeText(before + chosen + after, s, e, "end");
      area.setSelectionRange(s + before.length, s + before.length + chosen.length);
    }
    area.focus();
    changed();
  }

  // puts a prefix at the start of every selected line; the same prefix again takes it away
  function lines(prefix, numbered) {
    var text = area.value;
    var s = text.lastIndexOf("\n", area.selectionStart - 1) + 1;
    var e = text.indexOf("\n", area.selectionEnd);
    if (e === -1) e = text.length;
    var rows = text.slice(s, e).split("\n");
    var all = rows.every(function (r) { return r.indexOf(prefix) === 0 || (numbered && /^\d+\. /.test(r)); });
    rows = rows.map(function (r, i) {
      if (all) return numbered ? r.replace(/^\d+\. /, "") : r.slice(prefix.length);
      return (numbered ? i + 1 + ". " : prefix) + r;
    });
    area.setRangeText(rows.join("\n"), s, e, "select");
    area.focus();
    changed();
  }

  function block(snippet, cursorBack) {
    var s = area.selectionStart;
    var lead = s > 0 && area.value[s - 1] !== "\n" ? "\n\n" : "";
    area.setRangeText(lead + snippet, s, area.selectionEnd, "end");
    area.setSelectionRange(area.selectionStart - (cursorBack || 0), area.selectionStart - (cursorBack || 0));
    area.focus();
    changed();
  }

  function link() {
    var s = area.selectionStart, e = area.selectionEnd, chosen = area.value.slice(s, e) || "texte";
    area.setRangeText("[" + chosen + "](https://)", s, e, "end");
    area.setSelectionRange(area.selectionEnd - 9, area.selectionEnd - 1);
    area.focus();
    changed();
  }

  var tools = [
    ["B", "Gras (Ctrl+B)", function () { wrap("**", "**", "gras"); }],
    ["I", "Italique (Ctrl+I)", function () { wrap("*", "*", "italique"); }],
    ["S", "Barré", function () { wrap("~~", "~~", "barré"); }],
    ["`", "Code", function () { wrap("`", "`", "code"); }],
    ["|"],
    ["H2", "Titre", function () { lines("## "); }],
    ["H3", "Sous-titre", function () { lines("### "); }],
    ["|"],
    ["•", "Liste", function () { lines("- "); }],
    ["1.", "Liste numérotée", function () { lines("1. ", true); }],
    ["☑", "Tâches", function () { lines("- [ ] "); }],
    ["❝", "Citation", function () { lines("> "); }],
    ["|"],
    ["🔗", "Lien (Ctrl+K)", link],
    ["{ }", "Bloc de code", function () { block("```qlang\n\n```\n", 5); }],
    ["▦", "Tableau", function () { block("| Colonne | Colonne |\n| --- | --- |\n| | |\n"); }],
    ["―", "Séparateur", function () { block("---\n"); }]
  ];

  var bar = document.createElement("div");
  bar.className = "md-toolbar";
  bar.setAttribute("role", "toolbar");
  tools.forEach(function (t) {
    if (t[0] === "|") {
      var sep = document.createElement("span");
      sep.className = "sep";
      bar.appendChild(sep);
      return;
    }
    var b = document.createElement("button");
    b.type = "button";
    b.textContent = t[0];
    b.title = t[1];
    b.setAttribute("aria-label", t[1]);
    b.addEventListener("click", t[2]);
    bar.appendChild(b);
  });
  area.parentNode.insertBefore(bar, area);

  var info = document.createElement("div");
  info.className = "md-status muted";
  area.parentNode.appendChild(info);
  function status() {
    var words = (area.value.match(/\S+/g) || []).length;
    info.textContent = words + " mots · " + area.value.split("\n").length + " lignes" + (dirty ? " · modifié" : "");
  }
  status();

  area.addEventListener("keydown", function (event) {
    var mod = event.ctrlKey || event.metaKey;
    if (mod && event.key === "b") { event.preventDefault(); wrap("**", "**", "gras"); return; }
    if (mod && event.key === "i") { event.preventDefault(); wrap("*", "*", "italique"); return; }
    if (mod && event.key === "k") { event.preventDefault(); link(); return; }
    if (mod && event.key === "Enter") { event.preventDefault(); area.form.requestSubmit(); return; }
    if (event.key === "Tab") {
      event.preventDefault();
      var text = area.value;
      var s = text.lastIndexOf("\n", area.selectionStart - 1) + 1;
      var e = area.selectionEnd;
      if (area.selectionStart === area.selectionEnd && !event.shiftKey) {
        area.setRangeText("  ", area.selectionStart, area.selectionEnd, "end");
      } else {
        var rows = text.slice(s, e).split("\n").map(function (r) {
          return event.shiftKey ? r.replace(/^ {1,2}/, "") : "  " + r;
        });
        area.setRangeText(rows.join("\n"), s, e, "select");
      }
      changed();
      return;
    }
    if (event.key === "Enter" && !event.shiftKey && !mod && area.selectionStart === area.selectionEnd) {
      // carries a list on: "- a" then Enter gives "- ", and Enter on an empty item ends the list
      var pos = area.selectionStart;
      var start = area.value.lastIndexOf("\n", pos - 1) + 1;
      var row = area.value.slice(start, pos);
      var m = /^(\s*)([-*+] \[[ x]\] |[-*+] |(\d+)\. |> )(.*)$/.exec(row);
      if (m && pos === start + row.length) {
        event.preventDefault();
        if (m[4] === "") {
          area.setRangeText("", start, pos, "end");
        } else {
          var marker = m[3] ? (parseInt(m[3], 10) + 1) + ". " : m[2].replace("[x]", "[ ]");
          area.setRangeText("\n" + m[1] + marker, pos, pos, "end");
        }
        changed();
      }
    }
  });

  area.addEventListener("input", function () { dirty = true; status(); });

  var preview = document.getElementById("preview");
  if (preview) {
    area.addEventListener("scroll", function () {
      var ratio = area.scrollTop / Math.max(1, area.scrollHeight - area.clientHeight);
      preview.scrollTop = ratio * (preview.scrollHeight - preview.clientHeight);
    });
  }

  window.addEventListener("beforeunload", function (event) {
    if (dirty && !area.form.dataset.saving) { event.preventDefault(); event.returnValue = ""; }
  });
  area.form.addEventListener("submit", function () { area.form.dataset.saving = "1"; });
})();
