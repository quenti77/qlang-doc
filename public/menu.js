(function () {
  document.querySelectorAll(".avatar[data-name]").forEach(function (a) { a.textContent = (a.dataset.name || "?").charAt(0); });
  var menu = document.querySelector("details.user-menu");
  if (!menu) return;
  document.addEventListener("click", function (e) { if (menu.open && !menu.contains(e.target)) menu.open = false; });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") menu.open = false; });
})();

(function () {
  var toggle = document.querySelector(".nav-toggle");
  var nav = document.getElementById("main-nav");
  if (!toggle || !nav) return;
  toggle.addEventListener("click", function () {
    var open = nav.classList.toggle("open");
    toggle.setAttribute("aria-expanded", String(open));
  });
})();
