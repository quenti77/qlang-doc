(function () {
  document.addEventListener("submit", function (event) {
    var message = event.target.getAttribute && event.target.getAttribute("data-confirm");
    if (message && !window.confirm(message)) event.preventDefault();
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
