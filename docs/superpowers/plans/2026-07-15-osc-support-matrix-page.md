# OSC Support Matrix Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an accessible, responsive `/osc/` GitHub Pages page that presents Ianvs's current OSC support matrix and link it from the technology page.

**Architecture:** Keep the site fully static. Add one semantic HTML page, reuse the shared theme script and visual tokens, extend the shared validator with page-specific assertions, and add only the CSS needed for summary cards, status labels, and table-contained horizontal scrolling.

**Tech Stack:** Static HTML, shared CSS, existing vanilla JavaScript theme toggle, Python standard-library site validator.

---

## File map

- Create `osc/index.html`: complete user-facing support matrix grouped by protocol source.
- Modify `technology/index.html`: add one repository-evidence card linking to `/osc/`.
- Modify `assets/styles.css`: matrix page summary, status labels, table caption, scroll containment, and narrow-screen behavior.
- Modify `tools/validate_site.py`: require the sixth page and assert its key semantic/content contract.
- Modify `README.md`: update the page count and list.

### Task 1: Make site validation describe the new page

**Files:**
- Modify: `tools/validate_site.py`

- [ ] **Step 1: Add the failing page and content assertions**

Add `Path("osc/index.html")` to `PAGES`. Add these constants after `REQUIRED_CSS_SNIPPETS`:

```python
REQUIRED_OSC_SNIPPETS = [
    '<html lang="zh-CN"',
    '<caption>OSC',
    'scope="col"',
    'class="matrix-scroll"',
    'OSC 23',
    'RequestUpload',
    'ianvs-osc934/1',
    '完整证据矩阵',
]

REQUIRED_OSC_CSS_SNIPPETS = [
    ".osc-summary",
    ".matrix-scroll",
    ".status-pill",
]
```

Add this function before `main()`:

```python
def validate_osc_page() -> None:
    html = read_text(Path("osc/index.html"))
    for snippet in REQUIRED_OSC_SNIPPETS:
        if snippet not in html:
            fail(f"osc/index.html missing required snippet: {snippet}")

    technology = read_text(Path("technology/index.html"))
    if "../osc/index.html" not in technology:
        fail("technology/index.html is missing the OSC matrix link")

    styles = read_text(Path("assets/styles.css"))
    for snippet in REQUIRED_OSC_CSS_SNIPPETS:
        if snippet not in styles:
            fail(f"assets/styles.css missing OSC snippet: {snippet}")
```

Call it from `main()` after `validate_assets()`:

```python
def main() -> None:
    for page in PAGES:
        validate_page(page)
    validate_assets()
    validate_osc_page()
    print("site validation passed")
```

- [ ] **Step 2: Run the validator and verify RED**

Run: `python3 tools/validate_site.py`

Expected: `site validation failed: missing osc/index.html`.

- [ ] **Step 3: Commit the failing contract**

```bash
git add tools/validate_site.py
git commit -m "test(site): require OSC support matrix page"
```

### Task 2: Add the static OSC page and site entry

**Files:**
- Create: `osc/index.html`
- Modify: `technology/index.html`
- Modify: `README.md`

- [ ] **Step 1: Create the page shell**

Create `osc/index.html` using the existing technology page header/footer. Use:

```html
<!doctype html>
<html lang="zh-CN" data-theme="system">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="查看 ianvs 当前支持的 OSC 序号、协议来源、核心能力、主要场景和安全边界。">
    <title>OSC 支持矩阵 - ianvs</title>
    <link rel="stylesheet" href="../assets/styles.css">
    <script src="../assets/app.js" defer></script>
  </head>
```

Keep the shared skip link, brand, navigation, theme button, `main-content` landmark, and footer. The hero copy is:

```html
<p class="eyebrow">OSC support</p>
<h1 class="page-title">终端程序发来的能力请求，边界要说清楚。</h1>
<p>这里整理 ianvs 当前支持的 OSC 序号、协议来源、核心能力和主要场景。解析成功不等于自动获得剪贴板、文件、URL 或系统权限。</p>
```

- [ ] **Step 2: Add the source explanation and summary cards**

Use one `aria-labelledby="osc-overview-title"` section with three `.osc-summary` articles:

```html
<article class="osc-summary">
  <strong>事实标准</strong>
  <span>xterm 和被多个终端采用的通用约定。</span>
</article>
<article class="osc-summary">
  <strong>三方与社区规范</strong>
  <span>Kitty、iTerm2、VS Code、ConEmu、urxvt 和 UAPI。</span>
</article>
<article class="osc-summary">
  <strong>权限边界</strong>
  <span>剪贴板、文件、URL 和变量披露继续经过产品权限与当前会话校验。</span>
</article>
```

- [ ] **Step 3: Add four semantic matrix sections**

Each section uses this exact structure, with a unique heading and caption:

```html
<section class="section osc-matrix-section" aria-labelledby="xterm-osc-title">
  <div class="section-header">
    <div>
      <p class="kicker">xterm &amp; common</p>
      <h2 id="xterm-osc-title">xterm 与通用约定</h2>
    </div>
  </div>
  <div class="matrix-scroll" tabindex="0" aria-label="可横向滚动的 xterm 与通用 OSC 支持矩阵">
    <table class="matrix osc-matrix">
      <caption>OSC：xterm 与通用约定</caption>
      <thead>
        <tr>
          <th scope="col">OSC</th>
          <th scope="col">来源</th>
          <th scope="col">状态</th>
          <th scope="col">核心能力</th>
          <th scope="col">主要场景</th>
        </tr>
      </thead>
    </table>
  </div>
</section>
```

Insert one `<tbody>` after each `</thead>`, populate it with the rows assigned to
that group below, and close it before `</table>`:

| Group | OSC | Source | Status | Core capability | Main scenario |
|---|---|---|---|---|---|
| xterm/common | 0/1/2/l/L | xterm；l/L 来自 Sun/CDE | 支持 | 设置窗口标题和图标名，保留分号与拆分 UTF-8 | Tab 标题、窗口标题、会话识别 |
| xterm/common | 4/104 | xterm + iTerm2 查询别名 | 支持 | 0–255 调色板设置、查询和重置；-1/-2 默认色查询 | TUI 动态换色、主题探测 |
| xterm/common | 5/6/105/106 | xterm + iTerm2 | 支持双命名空间 | xterm 属性色；iTerm2 增量 Tab RGB 与默认色恢复 | 搜索高亮、任务 Tab 着色 |
| xterm/common | 7 | iTerm2/VTE 等通用扩展 | 支持 | 上报当前目录、主机和用户，拒绝畸形路径 | CWD 展示、远程会话标识 |
| xterm/common | 8 | iTerm2/VTE 通用扩展 | 支持 | 超链接 URI、id 身份、命中测试和打开目标 | 编译日志、文档与文件链接 |
| xterm/common | 9 | iTerm2/ConEmu | 安全子集 | 有界纯文本通知 | 后台命令完成提醒 |
| xterm/common | 9;4 | ConEmu/Windows Terminal | 支持 | 正常、不确定、错误、清除进度，百分比限制 0–100 | 构建、下载、长任务进度 |
| xterm/common | 9;9 | ConEmu/Windows Terminal | 适配器支持 | 上报绝对 CWD，不覆盖既有远程身份 | Windows shell 目录同步 |
| xterm/common | 10–19 / 110–119 | xterm | 支持 | 前景、背景、光标、选择和高亮动态颜色及恢复 | 应用级主题、选择色和光标色 |
| xterm/common | 23 | 安全兼容处理 | 不支持 | 有界空操作，不修改标题栈 | 消费旧输入并避免副作用 |
| xterm/common | 50 | xterm | 支持 | 会话级 TrueType 字体族设置和查询 | 临时切换等宽字体、能力探测 |
| xterm/common | 52 | xterm | 文本子集 | 权限控制的 Base64 文本写入和读取请求 | 远程程序复制文本、剪贴板同步 |
| xterm/common | 60/61/62 | xterm | 只读支持 | 查询允许、拒绝和可用 OSC 子能力，不改变权限 | 子进程启动时能力协商 |
| kitty | 21 | Kitty | 有界子集 | 批量颜色设置、查询和重置 | Kitty 应用换色、颜色能力探测 |
| kitty | 22 | Kitty | 支持 | 30 种指针、设置/重置、栈和状态查询 | 链接、拖放和文本选择反馈 |
| kitty | 66 | Kitty | 支持 | 定宽/自然宽、倍数/小数缩放、对齐和多单元格文本 | 大标题、数学与富文本式展示 |
| kitty | 72 | Kitty | macOS 接收端子集 | 拖放查询、目标注册和用户放入的 MIME 数据 | 从 Finder 向当前终端拖入文件或文本 |
| kitty | 99 | Kitty | 安全交互子集 | 通知生命周期、查询、纯文字按钮和固定回报 | 可交互任务通知；不执行通知命令 |
| kitty | 5522 | Kitty | 安全子集 | 多 MIME 二进制剪贴板、授权读取、令牌和分块回复 | 图片、富文本和文件引用粘贴 |
| iterm2 | 133 | FinalTerm/iTerm2 | 支持 | Prompt、命令、输出生命周期、语义 Prompt 和嵌套 shell 恢复 | Prompt 跳转、上次输出、命令块搜索 |
| iterm2 | 1337 会话元数据 | iTerm2 | 支持子集 | CurrentDir、RemoteHost、UserVar、Badge、Mark、版本和单元格尺寸 | Shell 集成、目录与远程身份 |
| iterm2 | 1337 变量与 Unicode | iTerm2 | 权限/外观子集 | ReportVariable 精确授权；Unicode 8/9 宽度切换和栈 | 安全披露终端变量、兼容旧字符宽度 |
| iterm2 | 1337 颜色与光标 | iTerm2 | 支持子集 | SetColors、CursorShape、光标行高亮和样式恢复 | 动态主题、光标外观和当前行定位 |
| iterm2 | 1337 终端内交互 | iTerm2 | 支持子集 | 剪贴板写入、标注、块折叠/渲染、按钮、清屏和清 Captured Output | 命令块、结果折叠、终端内文档与操作 |
| iterm2 | 1337 图像/文件/外部动作 | iTerm2 | 权限控制子集 | 内联图像、显式保存下载、确认打开 URL、受限 attention | 图片预览、文件下载、链接确认和提醒 |
| iterm2 | 1337 RequestUpload 等 | iTerm2 | 明确不授权 | 不读取本地文件；StealFocus、SetProfile 不授权 | 阻止子进程扩大主机权限 |
| iterm2 | 21337 | iTerm2 | 外观子集 | 增量 Tab 指示点、状态文本和状态颜色 | Tab 上展示构建、部署和连接状态 |
| other | 633 | VS Code | 适配器子集 | A–E/P 生命周期、命令关联和 CWD 属性 | 兼容 VS Code shell integration |
| other | 777 | urxvt | 安全子集 | 结构化标题和消息通知 | 兼容已有通知脚本 |
| other | 934 | Ianvs 私有 ianvs-osc934/1 | 支持 | 最多 64 个带 ID/标签的并行进度状态，支持查询和移除 | 同一 Pane 内展示多个任务 |
| other | 3008 | UAPI 社区规范 | 元数据支持 | v1.0 层级上下文、更新、返回、子级关闭和恢复 | Shell、容器与远程上下文建模 |

Use a text-bearing status element in the status cell, for example:

```html
<span class="status-pill" data-status="supported">支持</span>
```

Allowed `data-status` values are `supported`, `subset`, `gated`, `metadata`, and `unsupported`; the visible Chinese text remains authoritative.

- [ ] **Step 4: Add scope notes and repository evidence**

Add a compact list stating:

```html
<ul class="boundary-list">
  <li>现代 OSC 主要面向 Xterm256；VT220 配置通常会拒绝或静默消费。</li>
  <li>OSC 23 是安全空操作，不会修改标题或 CSI 标题栈。</li>
  <li>OSC 72 当前只实现 macOS 接收端，不读取远程文件或目录。</li>
  <li>OSC 52 只处理文本；多 MIME 数据通过 OSC 5522。</li>
  <li>OSC 99 不自动聚焦，不播放声音，不接收图标，也不执行通知命令。</li>
  <li>OSC 1337 RequestUpload、StealFocus 和 SetProfile 不获得主机权限。</li>
</ul>
```

Link “完整证据矩阵” to `https://github.com/robinfai/ianvs-terminal/blob/main/docs/protocols/osc_support_matrix.md` and state “仓库口径：2026-07-14；页面整理：2026-07-15”。

- [ ] **Step 5: Link the page from technology and update README**

Insert this card in `technology/index.html` under “Repository evidence”:

```html
<a class="card" href="../osc/index.html">
  <h3>OSC 支持矩阵</h3>
  <p>查看当前 OSC 序号、协议来源、能力范围和安全边界。</p>
</a>
```

Change “五个页面” to “六个页面” in `README.md` and add `osc/index.html` to the page list.

- [ ] **Step 6: Run the validator and verify the remaining GREEN/RED boundary**

Run: `python3 tools/validate_site.py`

Expected before Task 3 CSS: FAIL with `assets/styles.css missing OSC snippet: .osc-summary`.

- [ ] **Step 7: Commit page content**

```bash
git add osc/index.html technology/index.html README.md
git commit -m "feat(site): add OSC support matrix content"
```

### Task 3: Add responsive matrix styles

**Files:**
- Modify: `assets/styles.css`

- [ ] **Step 1: Add shared-theme styles**

Add after the existing `.matrix tr:last-child td` rule:

```css
.osc-summary-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 16px;
}

.osc-summary {
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: color-mix(in srgb, var(--bg-elevated) 92%, transparent);
  padding: 20px;
}

.osc-summary strong,
.osc-summary span {
  display: block;
}

.osc-summary strong {
  color: var(--accent-strong);
  font-size: 1.05rem;
}

.osc-summary span {
  margin-top: 8px;
  color: var(--muted);
}

.osc-matrix-section {
  scroll-margin-top: 96px;
}

.matrix-scroll {
  max-width: 100%;
  overflow-x: auto;
  border-radius: var(--radius);
  -webkit-overflow-scrolling: touch;
}

.matrix-scroll:focus-visible {
  outline-offset: 4px;
}

.osc-matrix {
  min-width: 920px;
  font-size: 0.94rem;
}

.osc-matrix caption {
  padding: 12px 16px;
  background: var(--bg-soft);
  color: var(--muted-strong);
  font-weight: 900;
  text-align: start;
}

.osc-matrix th:first-child,
.osc-matrix td:first-child {
  width: 145px;
  font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
  font-variant-numeric: tabular-nums;
  font-weight: 800;
}

.status-pill {
  display: inline-flex;
  align-items: center;
  min-height: 28px;
  border: 1px solid var(--line-strong);
  border-radius: 999px;
  padding: 3px 9px;
  color: var(--muted-strong);
  font-size: 0.78rem;
  font-weight: 900;
  white-space: nowrap;
}

.status-pill[data-status="supported"] {
  border-color: var(--accent);
  background: var(--accent-soft);
  color: var(--accent-strong);
}

.status-pill[data-status="gated"],
.status-pill[data-status="subset"] {
  border-color: var(--violet);
}

.status-pill[data-status="unsupported"] {
  border-style: dashed;
}

.boundary-list {
  margin: 0;
  padding-inline-start: 1.35rem;
  color: var(--muted);
}

.boundary-list li + li {
  margin-block-start: 10px;
}
```

- [ ] **Step 2: Add the narrow-layout rule**

Inside `@media (max-width: 920px)`, add `.osc-summary-grid` to the one-column selector list:

```css
.grid.two,
.grid.three,
.diagram,
.feature-strip,
.highlight-grid,
.capability-map,
.visual-card,
.osc-summary-grid {
  grid-template-columns: 1fr;
}
```

Do not use `.matrix { display: block; }` for the new page; `.matrix-scroll` owns horizontal scrolling.

- [ ] **Step 3: Run the validator and verify GREEN**

Run: `python3 tools/validate_site.py`

Expected: `site validation passed`.

- [ ] **Step 4: Commit styles**

```bash
git add assets/styles.css
git commit -m "style(site): make OSC matrix responsive"
```

### Task 4: Content and browser verification

**Files:**
- Verify: `osc/index.html`
- Verify: `technology/index.html`
- Verify: `assets/styles.css`

- [ ] **Step 1: Run the source OSC corpus validator**

Run:

```bash
python3 /Users/robinfai/personal/ianvs/ianvs-terminal/tools/validate_osc_protocol_corpus.py
```

Expected: `OSC corpus valid: 45 cases, 85 required edge classes`.

- [ ] **Step 2: Serve the site locally**

Run from the temporary worktree:

```bash
python3 -m http.server 8080 --bind 127.0.0.1
```

Expected: server starts without errors and `/osc/` returns HTTP 200.

- [ ] **Step 3: Inspect desktop and 320px layouts**

Verify at desktop and 320px viewport widths:

- page itself has no horizontal overflow;
- each matrix can scroll horizontally inside `.matrix-scroll`;
- skip link, theme toggle, technology link, evidence link, headings and captions are reachable;
- status meaning remains visible as text in light and dark themes;
- no row claims full support where the source matrix says subset, gated, metadata-only or unsupported.

- [ ] **Step 4: Run final repository checks**

Run:

```bash
python3 tools/validate_site.py
git diff --check gh-pages...HEAD
git status --short
```

Expected: validator passes, `git diff --check` prints nothing, and status is clean.

- [ ] **Step 5: Fast-forward local gh-pages**

First confirm `/Users/robinfai/personal/ianvs/ianvs-terminal-gh-pages` has no tracked changes. Then run from that worktree:

```bash
git merge --ff-only codex/gh-pages-osc-matrix
```

Expected: local `gh-pages` fast-forwards to the completed commit. Preserve the existing untracked `assets/images/.DS_Store`; do not add or remove it.
