(function () {
  const storageKey = "flutterm-site-theme";
  const themes = ["system", "dark", "light"];
  const labels = {
    system: "系统",
    dark: "深色",
    light: "浅色",
  };

  function readStoredTheme() {
    try {
      const value = window.localStorage.getItem(storageKey);
      return themes.includes(value) ? value : "system";
    } catch (_error) {
      return "system";
    }
  }

  function storeTheme(theme) {
    try {
      window.localStorage.setItem(storageKey, theme);
    } catch (_error) {
      // The visible theme still changes for this page view.
    }
  }

  function applyTheme(theme) {
    if (theme === "system") {
      document.documentElement.dataset.theme = "system";
    } else {
      document.documentElement.dataset.theme = theme;
    }

    document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
      button.textContent = labels[theme];
      button.setAttribute("aria-label", "当前主题：" + labels[theme] + "。点击切换主题。");
    });
  }

  function setupThemeToggle() {
    let currentTheme = readStoredTheme();
    applyTheme(currentTheme);

    document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
      button.addEventListener("click", () => {
        const nextTheme = themes[(themes.indexOf(currentTheme) + 1) % themes.length];
        currentTheme = nextTheme;
        storeTheme(nextTheme);
        applyTheme(nextTheme);
      });
    });
  }

  function setupTerminalHero() {
    const command = document.querySelector("[data-terminal-command]");
    const status = document.querySelector("[data-terminal-status]");
    const proof = document.querySelector("[data-terminal-proof]");
    const platform = document.querySelector("[data-terminal-platform]");
    const feature = document.querySelector("[data-terminal-feature]");
    if (!command || !status || !proof || !platform || !feature) {
      return;
    }

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const frames = [
      {
        command: "flutter run -d macos",
        status: "local shell ready",
        proof: "copy / paste / scroll verified",
        platform: "macOS ready",
        feature: "frame diff / shell hooks",
      },
      {
        command: "watch shell hooks",
        status: "cwd and command visible",
        proof: "prompt context stays useful",
        platform: "desktop platforms next",
        feature: "shell hook events",
      },
      {
        command: "export diagnostics",
        status: "attribution bundle ready",
        proof: "parser / render costs separated",
        platform: "open source path",
        feature: "diagnostics export",
      },
      {
        command: "scroll high-output session",
        status: "row cache active",
        proof: "dirty rows repaint first",
        platform: "macOS ready",
        feature: "row visual cache",
      },
    ];

    let index = 0;
    function renderFrame(frame) {
      command.textContent = frame.command;
      status.textContent = frame.status;
      proof.textContent = frame.proof;
      platform.textContent = frame.platform;
      feature.textContent = frame.feature;
    }

    renderFrame(frames[0]);
    if (reducedMotion.matches) {
      return;
    }

    window.setInterval(() => {
      index = (index + 1) % frames.length;
      renderFrame(frames[index]);
    }, 2600);
  }

  function setupReveals() {
    const revealTargets = Array.from(document.querySelectorAll("[data-reveal]"));
    if (revealTargets.length === 0) {
      return;
    }

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (reducedMotion.matches || !("IntersectionObserver" in window)) {
      revealTargets.forEach((target) => target.classList.add("is-visible"));
      return;
    }

    document.documentElement.classList.add("motion-ready");
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) {
            return;
          }
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -12% 0px", threshold: 0.16 },
    );

    revealTargets.forEach((target) => observer.observe(target));
  }

  document.addEventListener("DOMContentLoaded", () => {
    setupThemeToggle();
    setupTerminalHero();
    setupReveals();
  });
})();
