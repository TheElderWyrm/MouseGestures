/* MouseGestures purchase page — self-contained, null-guarded.
   Theme toggle (shares the "mg-theme" key with the rest of the site) + year.
   Kept separate from main.js so the checkout page has no dependency on the
   homepage's hero/ribbon markup. */
(function () {
  "use strict";
  var docEl = document.documentElement;

  var toggle = document.getElementById("themeToggle");
  if (toggle) {
    toggle.addEventListener("click", function () {
      var next = docEl.getAttribute("data-theme") === "dark" ? "light" : "dark";
      docEl.setAttribute("data-theme", next);
      try { localStorage.setItem("mg-theme", next); } catch (e) { /* private mode */ }
    });
  }

  // follow the OS while the visitor hasn't chosen manually
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function (e) {
    var stored = null;
    try { stored = localStorage.getItem("mg-theme"); } catch (err) { /* ignore */ }
    if (!stored) docEl.setAttribute("data-theme", e.matches ? "dark" : "light");
  });

  var year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());
})();
