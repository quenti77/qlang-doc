(function () {
  var ICONS = {
    copy: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/></svg>',
    done: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
    expand: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/></svg>',
    lines: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 6h10M10 12h10M10 18h10M4 5.5h1.5V10M4 18.5c0-1.5 2-1.5 2-3a1 1 0 0 0-2 0"/></svg>',
    close: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>'
  };
  var fr = (document.documentElement.lang || "").toLowerCase().indexOf("fr") === 0;
  var TEXT = fr
    ? { copy: "Copier le code", copied: "Copié", expand: "Voir en grand", close: "Fermer", lines: "Numéros de ligne" }
    : { copy: "Copy code", copied: "Copied", expand: "View larger", close: "Close", lines: "Line numbers" };

  function button(icon, label) {
    var b = document.createElement("button");
    b.type = "button";
    b.title = label;
    b.setAttribute("aria-label", label);
    b.innerHTML = icon;
    return b;
  }

  function copy(text, b) {
    function ok() {
      b.classList.add("done");
      b.innerHTML = ICONS.done;
      b.title = TEXT.copied;
      setTimeout(function () { b.classList.remove("done"); b.innerHTML = ICONS.copy; b.title = TEXT.copy; }, 1500);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(ok, function () { fallback(text) && ok(); });
    } else if (fallback(text)) { ok(); }
  }
  function fallback(text) {
    var t = document.createElement("textarea");
    t.value = text; t.style.position = "fixed"; t.style.opacity = "0";
    document.body.appendChild(t); t.select();
    var done = false;
    try { done = document.execCommand("copy"); } catch (e) {}
    document.body.removeChild(t);
    return done;
  }

  var modal;
  function open(pre) {
    if (!modal) {
      modal = document.createElement("dialog");
      modal.className = "code-modal";
      modal.addEventListener("click", function (e) { if (e.target === modal) modal.close(); });
      document.body.appendChild(modal);
    }
    modal.innerHTML = "";
    var head = document.createElement("header");
    var c = button(ICONS.copy, TEXT.copy);
    c.addEventListener("click", function () { copy(pre.textContent, c); });
    var x = button(ICONS.close, TEXT.close);
    x.addEventListener("click", function () { modal.close(); });
    head.appendChild(numbersButton()); head.appendChild(c); head.appendChild(x);
    modal.appendChild(head);
    modal.appendChild(pre.cloneNode(true));
    if (modal.showModal) modal.showModal(); else modal.setAttribute("open", "");
  }

  // puts every line of a block in its own element (the tokens that cross a line are cut and reopened), so numbers and diff colours can follow lines
  function splitLines(code) {
    var out = [], conts = [];
    function newLine(stack) {
      var line = document.createElement("span");
      line.className = "line";
      out.push(line);
      conts = [line];
      stack.forEach(function (anc) { var c = anc.cloneNode(false); conts[conts.length - 1].appendChild(c); conts.push(c); });
    }
    function walk(node, stack) {
      Array.prototype.slice.call(node.childNodes).forEach(function (ch) {
        var n = stack.length;
        if (ch.nodeType === 3) {
          ch.nodeValue.split("\n").forEach(function (t, i) {
            if (i > 0) { conts[n].appendChild(document.createTextNode("\n")); newLine(stack); }
            if (t) conts[n].appendChild(document.createTextNode(t));
          });
        } else if (ch.nodeType === 1) {
          var c = ch.cloneNode(false);
          conts[n].appendChild(c);
          conts.length = n + 1;
          conts.push(c);
          walk(ch, stack.concat([ch]));
        }
      });
    }
    newLine([]);
    walk(code, []);
    if (out.length > 1 && out[out.length - 1].textContent === "") out.pop();
    var diff = /(^|\s)language-diff(-|\s|$)/.test(code.className);
    code.textContent = "";
    out.forEach(function (line) {
      if (diff) {
        var t = line.textContent;
        if (t.indexOf("@@") === 0) line.classList.add("diff-hunk");
        else if (t.charAt(0) === "+" && t.indexOf("+++") !== 0) line.classList.add("diff-add");
        else if (t.charAt(0) === "-" && t.indexOf("---") !== 0) line.classList.add("diff-del");
      }
      code.appendChild(line);
    });
  }

  var root = document.documentElement;
  try { if (localStorage.getItem("codeNumbers") === "1") root.classList.add("code-numbers"); } catch (e) {}
  function toggleNumbers(b) {
    var on = root.classList.toggle("code-numbers");
    try { localStorage.setItem("codeNumbers", on ? "1" : "0"); } catch (e) {}
    document.querySelectorAll(".code-tools .lines, .code-modal .lines").forEach(function (x) { x.setAttribute("aria-pressed", String(on)); });
  }
  function numbersButton() {
    var b = button(ICONS.lines, TEXT.lines);
    b.classList.add("lines");
    b.setAttribute("aria-pressed", String(root.classList.contains("code-numbers")));
    b.addEventListener("click", function () { toggleNumbers(b); });
    return b;
  }

  function enhance(scope) {
    scope.querySelectorAll(".prose pre").forEach(function (pre) {
      if (pre.parentNode.classList.contains("code-block")) return;
      var code = pre.querySelector("code");
      if (code) splitLines(code);
      var wrap = document.createElement("div");
      wrap.className = "code-block";
      pre.parentNode.insertBefore(wrap, pre);
      wrap.appendChild(pre);
      var tools = document.createElement("div");
      tools.className = "code-tools";
      var c = button(ICONS.copy, TEXT.copy);
      c.addEventListener("click", function () { copy(pre.textContent, c); });
      var e = button(ICONS.expand, TEXT.expand);
      e.addEventListener("click", function () { open(pre); });
      tools.appendChild(numbersButton()); tools.appendChild(c); tools.appendChild(e);
      wrap.appendChild(tools);
    });
  }

  enhance(document);
  // the live preview of the editor replaces its content on every change
  var preview = document.getElementById("preview");
  if (preview && window.MutationObserver) {
    new MutationObserver(function () { enhance(preview); }).observe(preview, { childList: true });
  }
})();
