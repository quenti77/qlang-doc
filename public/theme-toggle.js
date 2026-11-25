(function () {
  var root = document.documentElement;
  var buttons = document.querySelectorAll("[data-theme-set]");
  function current() { return root.dataset.theme || "system"; }
  function paint() {
    buttons.forEach(function (b) { b.setAttribute("aria-pressed", String(b.dataset.themeSet === current())); });
  }
  buttons.forEach(function (b) {
    b.addEventListener("click", function () {
      var t = b.dataset.themeSet;
      if (t === "system") delete root.dataset.theme; else root.dataset.theme = t;
      try { if (t === "system") localStorage.removeItem("theme"); else localStorage.setItem("theme", t); } catch (e) {}
      paint();
    });
  });
  paint();
})();
