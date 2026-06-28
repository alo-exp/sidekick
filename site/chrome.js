(function () {
  function themeKeys() {
    var el = document.documentElement;
    return {
      primary: el.getAttribute('data-theme-key') || 'alo-theme',
      legacy: el.getAttribute('data-theme-key-legacy') || ''
    };
  }

  function readSavedTheme() {
    var keys = themeKeys();
    try {
      var saved = localStorage.getItem(keys.primary);
      if (!saved && keys.legacy) saved = localStorage.getItem(keys.legacy);
      return saved || document.documentElement.getAttribute('data-theme') || 'light';
    } catch (e) {
      return document.documentElement.getAttribute('data-theme') || 'light';
    }
  }

  function setIconState(dark) {
    var sun = document.getElementById('icon-sun');
    var moon = document.getElementById('icon-moon');
    if (!sun || !moon) return;
    sun.style.display = dark ? 'none' : '';
    moon.style.display = dark ? '' : 'none';
  }

  function applyTheme(dark) {
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    setIconState(dark);
    try {
      var keys = themeKeys();
      localStorage.setItem(keys.primary, dark ? 'dark' : 'light');
      if (keys.legacy) localStorage.setItem(keys.legacy, dark ? 'dark' : 'light');
    } catch (e) { /* storage unavailable */ }
  }

  window.toggleTheme = function () {
    applyTheme(document.documentElement.getAttribute('data-theme') !== 'dark');
  };

  function initThemeToggle() {
    var btn = document.getElementById('theme-toggle') || document.getElementById('theme-btn');
    if (!btn) return;
    if (!btn.getAttribute('aria-label')) btn.setAttribute('aria-label', 'Toggle light/dark mode');
    if (!btn.onclick) btn.addEventListener('click', window.toggleTheme);
  }

  function initMobileNav() {
    document.querySelectorAll('.nav-links a').forEach(function (a) {
      a.addEventListener('click', function () {
        var links = document.querySelector('.nav-links');
        if (links) links.classList.remove('active');
      });
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    initThemeToggle();
    initMobileNav();
    applyTheme(readSavedTheme() === 'dark');
    if (window.lucide && typeof window.lucide.createIcons === 'function') {
      window.lucide.createIcons();
    }
  });
})();
