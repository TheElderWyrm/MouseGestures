/* Runs synchronously in <head> to set the theme before first paint (no flash).
   ?theme=dark|light in the URL forces one (handy for screenshots). */
(function () {
    var forced = (location.search.match(/[?&]theme=(dark|light)/) || [])[1];
    var stored = null;
    try { stored = localStorage.getItem('mg-theme'); } catch (e) { /* private mode */ }
    var theme = forced
        || ((stored === 'light' || stored === 'dark') ? stored : null)
        || (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    document.documentElement.setAttribute('data-theme', theme);
    document.documentElement.classList.add('has-js');
})();
