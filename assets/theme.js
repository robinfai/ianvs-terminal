// Apply before CSS to avoid a flash when a saved theme differs from the system.
(function () {
  document.documentElement.classList.add('js');
  try {
    var saved = localStorage.getItem('ianvs-astra-theme');
    document.documentElement.dataset.theme = ['light', 'dark', 'system'].includes(saved) ? saved : 'system';
  } catch (_) {
    document.documentElement.dataset.theme = 'system';
  }
})();
