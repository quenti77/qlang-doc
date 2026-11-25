(function () {
  document.addEventListener("submit", function (event) {
    var message = event.target.getAttribute && event.target.getAttribute("data-confirm");
    if (message && !window.confirm(message)) event.preventDefault();
  });

  document.addEventListener("click", function (event) {
    var button = event.target.closest && event.target.closest("button[data-group]");
    if (!button) return;
    var open = button.getAttribute("aria-expanded") !== "true";
    button.setAttribute("aria-expanded", open ? "true" : "false");
    document.querySelectorAll('tr[data-in="' + button.dataset.group + '"]').forEach(function (row) { row.hidden = !open; });
  });

  // a button with data-twostep asks again on its own label before it sends: first click arms it, second click sends
  document.addEventListener("click", function (event) {
    var button = event.target.closest && event.target.closest("button[data-twostep]");
    if (!button) return;
    if (button.dataset.armed === "1") return;
    event.preventDefault();
    button.dataset.armed = "1";
    button.dataset.label = button.textContent;
    button.textContent = button.dataset.twostep;
    button.classList.add("armed");
    setTimeout(function () {
      button.dataset.armed = "";
      button.textContent = button.dataset.label;
      button.classList.remove("armed");
    }, 4000);
  });

  var picks = function () { return Array.prototype.slice.call(document.querySelectorAll('input[name="pick"]')); };
  var counter = function () {
    var count = document.getElementById("bulk-count");
    if (count) count.textContent = picks().filter(function (c) { return c.checked; }).length;
  };
  document.addEventListener("change", function (event) {
    var box = event.target;
    if (!box.matches) return;
    if (box.id === "pick-all") {
      picks().forEach(function (c) { c.checked = box.checked; });
    } else if (box.matches('input[name="pick"][data-folder]')) {
      picks().forEach(function (c) { if (c.dataset.path.indexOf(box.dataset.path + "/") === 0) c.checked = box.checked; });
    } else {
      return;
    }
    counter();
  });

  var source = document.getElementById("markdown");
  var preview = document.getElementById("preview");
  if (!source || !preview) return;
  var state = document.getElementById("preview-state");
  var meta = document.querySelector('meta[name="csrf-token"]');
  var timer = null;
  function render() {
    if (state) state.textContent = "…";
    fetch("/admin/preview", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded", "X-CSRF-Token": meta ? meta.content : "" },
      body: "markdown=" + encodeURIComponent(source.value)
    }).then(function (r) { return r.text(); }).then(function (html) {
      preview.innerHTML = html;
      if (state) state.textContent = "";
    }).catch(function () { if (state) state.textContent = "(aperçu indisponible)"; });
  }
  source.addEventListener("input", function () { clearTimeout(timer); timer = setTimeout(render, 350); });
})();
