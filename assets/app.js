(function () {
  'use strict';
  const root = document.documentElement;
  const announce = (message) => {
    const status = document.querySelector('[data-status]');
    if (status) status.textContent = message;
  };

  const themeLabels = { system: '跟随系统', light: '浅色', dark: '深色' };
  const themeSelect = document.querySelector('[data-theme-select]');
  if (themeSelect) {
    themeSelect.value = root.dataset.theme || 'system';
    themeSelect.addEventListener('change', () => {
      const theme = themeSelect.value;
      root.dataset.theme = theme;
      try { localStorage.setItem('ianvs-astra-theme', theme); } catch (_) { /* Works without storage. */ }
      announce('外观已切换为' + themeLabels[theme]);
    });
    window.addEventListener('storage', (event) => {
      if (event.key !== 'ianvs-astra-theme' && event.key !== null) return;
      const theme = ['light', 'dark', 'system'].includes(event.newValue) ? event.newValue : 'system';
      root.dataset.theme = theme;
      themeSelect.value = theme;
    });
  }

  const menuToggle = document.querySelector('[data-menu-toggle]');
  const menu = document.getElementById('main-nav');
  const closeMenu = () => {
    if (!menuToggle || !menu) return;
    menu.classList.remove('is-open');
    menuToggle.setAttribute('aria-expanded', 'false');
  };
  if (menuToggle && menu) {
    menuToggle.addEventListener('click', () => {
      const open = menuToggle.getAttribute('aria-expanded') !== 'true';
      menuToggle.setAttribute('aria-expanded', String(open));
      menu.classList.toggle('is-open', open);
    });
    menu.addEventListener('click', (event) => {
      if (event.target.closest('a')) closeMenu();
    });
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && menuToggle.getAttribute('aria-expanded') === 'true') {
        closeMenu();
        menuToggle.focus();
      }
    });
    document.addEventListener('click', (event) => {
      if (!event.target.closest('.site-header')) closeMenu();
    });
    const desktop = window.matchMedia('(min-width: 851px)');
    desktop.addEventListener('change', (event) => { if (event.matches) closeMenu(); });
  }

  const demoFrames = {
    local: {
      lines: [['prompt', 'make run'], ['dim', 'Launching Ianvs Terminal on macOS…'], ['ok', 'Local shell ready'], ['ok', 'Your next idea starts here.']],
      status: '本地会话 · 就绪'
    },
    ssh: {
      lines: [['prompt', 'ssh deploy@staging'], ['dim', 'Connecting with your saved SSH Profile…'], ['ok', 'Welcome back, deploy.'], ['dim', '本地与远程，在同一套标签与分屏里。']],
      status: 'SSH 会话 · 演示'
    },
    replay: {
      lines: [['dim', '◷  本地录制 / build-session'], ['ok', '打开已保存的终端录制'], ['dim', '00:12  build started'], ['dim', '00:34  build completed'], ['ok', '搜索输出 · 选择文本 · 复制结果']],
      status: '录制回放 · 演示'
    }
  };
  const demoOutput = document.querySelector('[data-demo-output]');
  const demoStatus = document.querySelector('[data-demo-status]');
  const demoButtons = Array.from(document.querySelectorAll('[data-demo]'));
  if (demoOutput && demoStatus && demoButtons.length) {
    demoButtons.forEach((button) => button.addEventListener('click', () => {
      const frame = demoFrames[button.dataset.demo];
      if (!frame) return;
      demoButtons.forEach((item) => item.setAttribute('aria-pressed', String(item === button)));
      demoOutput.replaceChildren();
      frame.lines.forEach(([type, text]) => {
        const line = document.createElement('p');
        if (type === 'dim') line.className = 'terminal-dim';
        if (type === 'ok' || type === 'prompt') {
          const marker = document.createElement('span');
          marker.className = 'terminal-accent';
          marker.textContent = type === 'ok' ? '✓ ' : '❯ ';
          line.append(marker);
        }
        line.append(document.createTextNode(text));
        demoOutput.append(line);
      });
      const prompt = document.createElement('p');
      prompt.className = 'terminal-prompt';
      prompt.textContent = '❯ ▍';
      demoOutput.append(prompt);
      demoStatus.textContent = frame.status;
      announce('工作流演示已切换：' + frame.status);
    }));
  }

  document.querySelectorAll('[data-copy]').forEach((button) => {
    button.addEventListener('click', async () => {
      const target = document.getElementById(button.dataset.copy);
      if (!target) return;
      const original = button.textContent;
      try {
        if (!navigator.clipboard || !navigator.clipboard.writeText) throw new Error('Clipboard unavailable');
        await navigator.clipboard.writeText(target.textContent);
        button.textContent = '已复制 ✓';
        announce('已复制到剪贴板');
      } catch (_) {
        const range = document.createRange();
        range.selectNodeContents(target);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        button.textContent = '请手动复制';
        announce('剪贴板不可用，已选中代码，请使用系统复制快捷键');
      }
      window.setTimeout(() => { button.textContent = original; }, 2200);
    });
  });

  const search = document.querySelector('[data-protocol-search]');
  const filters = Array.from(document.querySelectorAll('[data-filter]'));
  const rows = Array.from(document.querySelectorAll('[data-protocol-row]'));
  const groups = Array.from(document.querySelectorAll('[data-protocol-group]'));
  const count = document.querySelector('[data-result-count]');
  const empty = document.querySelector('[data-empty-state]');
  if (search && filters.length && rows.length && count && empty) {
    let selected = 'all';
    const normalize = (text) => text.toLowerCase().replace(/\s+/g, '');
    const url = new URL(window.location.href);
    const allowed = filters.map((button) => button.dataset.filter);
    selected = allowed.includes(url.searchParams.get('family')) ? url.searchParams.get('family') : 'all';
    search.value = url.searchParams.get('q') || '';
    const apply = (updateUrl) => {
      const term = normalize(search.value.trim());
      let visible = 0;
      rows.forEach((row) => {
        const matches = (selected === 'all' || row.dataset.family === selected) && normalize(row.textContent).includes(term);
        row.hidden = !matches;
        if (matches) visible++;
      });
      filters.forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.filter === selected)));
      groups.forEach((group) => {
        group.hidden = !rows.some((row) => row.dataset.family === group.dataset.protocolGroup && !row.hidden);
      });
      count.textContent = visible + ' 项协议记录';
      empty.hidden = visible !== 0;
      if (updateUrl) {
        const next = new URL(window.location.href);
        if (selected === 'all') next.searchParams.delete('family'); else next.searchParams.set('family', selected);
        if (search.value.trim()) next.searchParams.set('q', search.value.trim()); else next.searchParams.delete('q');
        window.history.replaceState(null, '', next);
      }
    };
    search.addEventListener('input', () => apply(true));
    filters.forEach((button) => button.addEventListener('click', () => { selected = button.dataset.filter; apply(true); }));
    document.querySelector('[data-clear-filters]')?.addEventListener('click', () => {
      selected = 'all'; search.value = ''; apply(true); search.focus();
    });
    window.addEventListener('popstate', () => {
      const current = new URL(window.location.href);
      selected = allowed.includes(current.searchParams.get('family')) ? current.searchParams.get('family') : 'all';
      search.value = current.searchParams.get('q') || '';
      apply(false);
    });
    apply(false);
  }
})();
