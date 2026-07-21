/* Runs synchronously in <head> to set the theme before first paint (no flash). */
(function () {
    var stored = null;
    try { stored = localStorage.getItem('mg-theme'); } catch (e) { /* private mode */ }
    var theme = (stored === 'light' || stored === 'dark')
        ? stored
        : (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
    document.documentElement.setAttribute('data-theme', theme);
})();
