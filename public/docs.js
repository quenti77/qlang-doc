(function () {
  // on a phone the navigation of the docs starts folded, so that the page comes first
  var nav = document.querySelector("details.side-details");
  if (nav && window.matchMedia("(max-width: 44rem)").matches) nav.open = false;
})();
