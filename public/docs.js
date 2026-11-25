(function () {
  // on a phone the navigation of the docs starts folded, so that the page comes first
  var details = document.querySelector("details.side-details");
  if (details && window.matchMedia("(max-width: 44rem)").matches) details.open = false;

  var nav = document.querySelector(".side nav");
  if (!nav) return;
  var items = Array.prototype.slice.call(nav.children);
  var folders = items.filter(function (el) { return el.tagName === "BUTTON"; });

  // an entry shows when every folder above it is expanded
  function refresh() {
    var open = {};
    folders.forEach(function (f) { open[f.dataset.path] = f.getAttribute("aria-expanded") === "true"; });
    items.forEach(function (el) {
      var parts = el.dataset.path.split("/");
      var shown = true;
      for (var i = 1; i < parts.length; i++) {
        if (!open[parts.slice(0, i).join("/")]) { shown = false; break; }
      }
      el.hidden = !shown;
    });
  }

  nav.addEventListener("click", function (e) {
    var f = e.target.closest("button.side-title");
    if (!f) return;
    f.setAttribute("aria-expanded", f.getAttribute("aria-expanded") === "true" ? "false" : "true");
    refresh();
  });
  document.querySelectorAll(".side-tools button").forEach(function (b) {
    b.addEventListener("click", function () {
      var value = b.dataset.fold === "open" ? "true" : "false";
      folders.forEach(function (f) { f.setAttribute("aria-expanded", value); });
      refresh();
    });
  });
})();
