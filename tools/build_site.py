#!/usr/bin/env python3
"""Build the six zero-dependency static pages. Run from any directory."""
from pathlib import Path
from html import escape
import re

ROOT = Path(__file__).resolve().parents[1]
REPO = 'https://github.com/robinfai/ianvs-terminal'
DOCS = REPO + '/blob/main/'
NAV = [('home','概览','index.html'), ('features','功能','features/index.html'), ('technology','技术','technology/index.html'), ('osc','协议','osc/index.html'), ('roadmap','进展','roadmap/index.html')]
ARROW = '<span aria-hidden="true">↗</span>'

def link(label, url, cls='text-link'):
    return f'<a class="{cls}" href="{url}">{label} {ARROW}</a>'

def intro(n, eyebrow, heading, desc):
    return f'<section class="page-intro wrap"><p class="eyebrow"><span>{n}</span> {eyebrow}</p><h1>{heading}</h1><p class="lead">{desc}</p></section>'

def section_head(n, eyebrow, heading, desc=''):
    return f'<div class="section-heading"><div><p class="eyebrow"><span>{n}</span> {eyebrow}</p><h2>{heading}</h2></div>{f"<p>{desc}</p>" if desc else ""}</div>'

def cta(prefix):
    return f'''<section class="closing wrap"><div><p class="eyebrow">YOUR NEXT SESSION</p><h2>下一次打开终端，<br>从这里开始。</h2></div><div><p>开源、macOS 优先。<br>从源码运行，亲手试试你的日常工作流。</p>{link('开始本地试用',prefix+'open-source/index.html','button primary')}</div><span class="closing-symbol" aria-hidden="true">↗</span></section>'''

def render(key, title, description, body):
    prefix = '' if key == 'home' else '../'
    nav = ''.join(f'<a href="{prefix+path}"'+(' aria-current="page"' if name==key else '')+f'>{label}</a>' for name,label,path in NAV)
    html = f'''<!doctype html>
<html lang="zh-CN" data-theme="system">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="description" content="{description}">
<meta property="og:title" content="{title} · Ianvs Terminal">
<meta property="og:description" content="{description}">
<meta property="og:type" content="website">
<title>{title} · Ianvs Terminal</title>
<link rel="icon" href="{prefix}assets/images/brand/app-icon.png">
<script src="{prefix}assets/theme.js"></script>
<link rel="stylesheet" href="{prefix}assets/styles.css">
<script src="{prefix}assets/app.js" defer></script>
</head>
<body data-page="{key}">
<a class="skip-link" href="#main-content">跳到正文</a>
<header class="site-header"><div class="header-inner wrap">
<a class="brand" href="{prefix}index.html" aria-label="ianvs 首页"><span class="brand-symbol" aria-hidden="true"><i></i><i></i></span><span>ianvs<span class="brand-suffix"> / terminal</span></span></a>
<button type="button" class="menu-toggle" data-menu-toggle aria-expanded="false" aria-controls="main-nav">菜单 <span aria-hidden="true">☰</span></button>
<nav id="main-nav" class="main-nav" aria-label="主导航">{nav}</nav>
<div class="header-actions"><label class="theme-control"><span class="sr-only">外观主题</span><select data-theme-select aria-label="外观主题"><option value="system">◐ 系统</option><option value="light">☀ 浅色</option><option value="dark">☾ 深色</option></select></label><a class="header-cta" href="{prefix}open-source/index.html"{' aria-current="page"' if key=='open-source' else ''}>开始使用 <span aria-hidden="true">↗</span></a></div>
</div></header>
<main id="main-content" tabindex="-1">{body}</main>
<footer class="site-footer wrap"><div class="footer-top"><a class="brand" href="{prefix}index.html"><span class="brand-symbol" aria-hidden="true"><i></i><i></i></span>ianvs</a><p>让每一次输入，都保持专注。</p><a class="text-link" href="{REPO}">GitHub ↗</a></div><div class="footer-bottom"><span>IANVS TERMINAL · OPEN SOURCE</span><nav aria-label="页脚导航"><a href="{prefix}features/index.html">功能</a><a href="{prefix}technology/index.html">技术</a><a href="{prefix}osc/index.html">协议参考</a><a href="{prefix}roadmap/index.html">产品进展</a><a href="{prefix}open-source/index.html">本地试用</a></nav><span>BUILT WITH FLUTTER + RUST</span></div></footer>
<div class="sr-only" role="status" data-status></div>
</body></html>'''
    target=ROOT/('index.html' if key=='home' else key+'/index.html')
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(html)

terminal = '''<div class="terminal-demo" aria-label="终端工作流交互示意，非真实连接"><div class="terminal-chrome"><span class="window-dots" aria-hidden="true"><i></i><i></i><i></i></span><span>ianvs terminal</span><span class="chrome-label">WORKFLOW PREVIEW</span></div><div class="terminal-tabs"><span class="active">⌘ &nbsp; Local shell</span><span>↗ &nbsp; staging</span><span aria-hidden="true">+</span><span class="replay-label">◷ &nbsp; 回看</span></div><div class="terminal-stage"><div class="terminal-primary"><div class="terminal-location"><span>~/development/ianvs</span><span>zsh</span></div><div class="terminal-output" data-demo-output><p><span class="terminal-accent">❯</span> <span>make run</span></p><p class="terminal-dim">Launching Ianvs Terminal on macOS…</p><p><span class="terminal-accent">✓</span> Local shell ready</p><p><span class="terminal-accent">✓</span> Your next idea starts here.</p><p class="terminal-prompt"><span class="terminal-accent">❯</span> <span class="cursor" aria-hidden="true"></span></p></div></div><div class="terminal-secondary"><div class="terminal-location"><span>staging</span><span class="terminal-accent">SSH</span></div><div class="terminal-output"><p class="terminal-dim">$ ssh deploy@staging</p><p>Welcome back.</p><p class="terminal-dim">Last login: today</p><div class="mini-divider"></div><p class="terminal-accent">deploy@staging ~</p><p>❯ <span class="cursor outline" aria-hidden="true"></span></p></div><div class="connection-note"><span class="small-dot"></span>独立会话，同一布局</div></div></div><div class="terminal-foot"><span><i class="small-dot"></i> <span data-demo-status>本地会话 · 就绪</span></span><span>UTF-8 &nbsp; / &nbsp; zsh</span></div></div>'''

home=f'''<section class="home-hero wrap"><div class="hero-topline"><p class="eyebrow"><span class="small-dot"></span> A TERMINAL, CLOSE TO HOME.</p><span class="edition">OPEN SOURCE / macOS</span></div><div class="hero-copy"><h1>输入，从容。<br><span>一切，尽在本地。</span></h1><div class="hero-aside"><p>从本地 shell 到远程 SSH，<br>让会话井然有序，让重要输出随时可回看。<br>一个专注于终端本身的开源工具。</p><div class="actions">{link('开始使用','open-source/index.html','button primary')}{link('探索功能','features/index.html','button secondary')}</div><p class="hero-meta">macOS 优先 · Flutter + Rust · 本地优先</p></div></div><div class="hero-preview">{terminal}<div class="preview-bottom"><div class="demo-switcher" role="group" aria-label="切换终端演示"><button type="button" data-demo="local" aria-pressed="true">01 本地会话</button><button type="button" data-demo="ssh" aria-pressed="false">02 远程 SSH</button><button type="button" data-demo="replay" aria-pressed="false">03 回看输出</button></div><span>交互示意 · 点击切换工作流</span></div></div></section>
<section class="principle-strip wrap" aria-label="产品要点"><div><span class="strip-icon">⌘</span><p>本地与远程<span>同一套会话体验</span></p></div><div><span class="strip-icon">⊞</span><p>多标签与分屏<span>按工作节奏组织</span></p></div><div><span class="strip-icon">◷</span><p>回看与本地录制<span>留住有用的输出</span></p></div><div><span class="strip-icon">⌂</span><p>先保存到本机<span>离线也不耽误工作</span></p></div></section>
<section class="section wrap">{section_head('01','MADE FOR THE EVERYDAY','熟悉的工作流，<br>少一点来回切换。','从一条命令开始，到多个会话并行。<br>把注意力留给手上的事情。')}<div class="feature-mosaic"><article class="feature-card feature-large"><div class="card-top"><span class="pill">SESSION & LAYOUT</span><span class="card-number">01 /</span></div><h3>一边运行，一边观察。</h3><p>本地 shell 和 SSH 共用标签与分屏。<br>保存常用启动配置，在需要的目录直接打开终端。</p><div class="layout-graphic" aria-hidden="true"><div class="layout-tabs"><span>Terminal 01</span><span>Terminal 02</span></div><div class="layout-panes"><div><b>LOCAL</b><i></i><i></i><i></i><span>❯ ▍</span></div><div><b>SSH / STAGING</b><i></i><i></i><span>❯ ▍</span></div></div></div>{link('了解会话与布局','features/index.html#sessions')}</article><article class="feature-card"><div class="card-top"><span class="pill">REPLAY</span><span class="card-number">02 /</span></div><h3>刚才的输出，<br>还在这里。</h3><p>回看最近画面，或保存一段本地录制。之后重新打开，继续搜索与复制。</p><div class="replay-graphic" aria-hidden="true"><span>00:00</span><div class="timeline"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div><span>02:34</span></div>{link('认识回看','features/index.html#instant-replay')}</article><article class="feature-card"><div class="card-top"><span class="pill">LOCAL FIRST</span><span class="card-number">03 /</span></div><h3>断开网络，<br>也能保存设置。</h3><p>主机、配置与凭据先保存在本机。需要时再连接可选 API，同步配置。</p><div class="local-graphic" aria-hidden="true"><span>⌂<small>你的设备</small></span><i>········</i><span>⇄<small>可选同步</small></span></div>{link('了解本地数据','features/index.html#local-first')}</article></div></section>
<section class="manifesto"><div class="wrap manifesto-inner"><p class="eyebrow">LESS BETWEEN YOU<br>AND YOUR TERMINAL.</p><div><h2>打开目录。<br>启动会话。<br><span>继续你的事情。</span></h2><p>Ianvs 把终端放在中心。可复用的 Profile、有序的标签与分屏、独立保存的录制，各自清楚，各得其所。</p>{link('查看完整功能','features/index.html')}</div><span class="manifesto-mark" aria-hidden="true">❯_</span></div></section>
<section class="section wrap">{section_head('02','OPEN BY DESIGN','界面轻盈，底层扎实。','Flutter 构建交互，Rust 处理终端底层。<br>每一层都可以在源码中找到。')}<div class="engineering-grid"><div><div class="stack-row"><span>01</span><h3>Flutter</h3><p>窗口、交互与外观</p></div><div class="stack-row"><span>02</span><h3>Dart</h3><p>会话运行时与终端视图</p></div><div class="stack-row"><span>03</span><h3>Rust</h3><p>PTY、VT 解析与终端帧</p></div></div><aside class="engineering-aside"><span class="code-symbol" aria-hidden="true">&lt;/&gt;</span><h3>也可以成为<br>你的应用的一部分。</h3><p>通过 ianvs_terminal_core，把 macOS 终端嵌入 Flutter 应用。</p>{link('开发者入口','technology/index.html')}</aside></div></section>{cta('')}'''
home=home.replace('<h1>输入，从容。', '<h1 id="hero-title">输入，从容。').replace('<h2>熟悉的工作流，', '<h2 id="experience-title">熟悉的工作流，').replace('<div class="feature-mosaic">', '<div class="feature-mosaic" id="highlights-title">').replace('<h2>界面轻盈，底层扎实。', '<h2 id="proof-title">界面轻盈，底层扎实。').replace('<h2>下一次打开终端，', '<h2 id="try-title">下一次打开终端，')
render('home','输入，从容','Ianvs Terminal：macOS 优先的开源终端。本地 shell、SSH、多标签分屏、回看与本地录制，配置先保存在本机。',home)

features=intro('01','THE TERMINAL, IN DETAIL','从一条命令，<br>到有序的每一天。','本地 shell、远程连接、会话布局与回看。<br>日常要用的东西，就在顺手的位置。')
features+='''<nav class="anchor-nav wrap" aria-label="本页目录"><a href="#sessions">会话与布局</a><a href="#instant-replay">回看与录制</a><a href="#local-first">本地与同步</a><a href="#capabilities-title">终端细节</a></nav>'''
features+=f'''<section class="section wrap feature-detail" id="sessions"><div><p class="eyebrow"><span>01</span> SESSION & LAYOUT</p><h2>本地或远程，<br>都在熟悉的终端里。</h2><p class="lead-small">本地 shell 与 SSH 共用标签、分屏和终端布局。多个会话并行时，也能清楚知道自己在哪个窗口、哪个 Pane。</p><ul class="check-list"><li>Profile 保存程序、参数与初始目录等启动默认值</li><li>选择文件夹，直接在这个目录打开一个新终端</li><li>布局恢复保留组织方式，并启动新的会话</li><li>SSH 主机可以本地创建、编辑、保存与重连</li></ul></div><div class="feature-display">{terminal}<p class="caption">本地与 SSH 会话布局示意</p></div></section>
<section class="section section-rule wrap feature-detail" id="instant-replay"><div class="recording-display"><div class="recording-header"><span>◷ &nbsp; 回看</span><span class="pill">本机资料库</span></div><div class="recording-item"><span class="recording-icon">↶</span><div><strong>最近画面</strong><p>回看这次使用中的输出</p></div><span>→</span></div><div class="recording-item"><span class="recording-icon">▷</span><div><strong>已保存录制</strong><p>停止并保存后，留在本机</p></div><span>→</span></div><div class="recording-item"><span class="recording-icon">↗</span><div><strong>打开录制文件</strong><p>继续搜索、选择与复制</p></div><span>→</span></div><div class="recording-foot">最近画面是临时缓存；保存的录制可在重启后找回。</div></div><div><p class="eyebrow"><span>02</span> REPLAY & RECORDING</p><h2>输出过去了，<br>线索还可以留下。</h2><p class="lead-small">从工具栏的「回看」进入最近画面、已保存录制或本地文件。主动录制在停止并保存后进入录制列表。</p><p>最近画面会在退出后清除；保存的录制独立留在本机。回放 SSH 录制时，无需重新连接主机。</p><p class="inline-note">录制文件与终端布局分开保存，也不会随配置 API 同步。</p></div></section>
<section class="section section-rule wrap" id="local-first">{section_head('03','LOCAL FIRST','数据先落在本机，<br>同步按需开启。','没有配置 API，也能保存配置和 SSH 主机。<br>需要跨设备使用配置时，再选择你的同步目标。')}<div class="three-grid"><article class="simple-card"><span class="feature-icon">⌂</span><h3>本地可用</h3><p>配置与 SSH 主机使用本地存储。密码与私钥加密保存，离线也能编辑、保存和发起重连。</p></article><article class="simple-card"><span class="feature-icon">⇄</span><h3>可选配置同步</h3><p>连接 API 后仍先保存本地，再合并与同步。独立修改自动合并，同字段冲突由你明确选择。</p></article><article class="simple-card"><span class="feature-icon">⊙</span><h3>切换依然安心</h3><p>关闭或切换 API 保留本地数据。终端布局、重启配置与录制文件始终留在本机。</p></article></div><p class="section-footnote">API 提供可选配置同步；它不提供团队云、协作或共享终端会话。</p></section>
<section class="section section-rule wrap" aria-labelledby="capabilities-title"><p class="eyebrow"><span>04</span> THOUGHTFUL DETAILS</p><h2 id="capabilities-title">小动作，也认真对待。</h2><div class="detail-list"><article id="shell-hook"><span>01</span><h3>可感知的 shell 上下文</h3><p>从 shell 集成中获取当前目录、命令生命周期与退出状态；在本地与逐层进入的 SSH Shell 中，分别查看当前会话能力。</p></article><article id="mode-aware-input"><span>02</span><h3>跟随模式的输入</h3><p>按键、粘贴、鼠标与滚动适配当前终端模式，让 shell 与终端应用使用同一套输入路径。</p></article><article id="row-cache"><span>03</span><h3>聚焦变化的绘制</h3><p>终端帧与行级缓存帮助视图处理变化内容，减少重复绘制。具体性能以实际工作负载为准。</p></article><article id="diagnostics-export"><span>04</span><h3>问题有线索可查</h3><p>需要排查问题时导出诊断，让复现与反馈更容易对齐。</p></article><article id="json-request"><span>05</span><h3>统一的运行时契约</h3><p>会话事件、请求与终端帧由当前 native / Dart 契约连接。开发接入请查阅最新 package 文档。</p></article><article id="xterm-api"><span>06</span><h3>可嵌入 Flutter 应用</h3><p>ianvs_terminal_core 暴露终端运行时、会话视图和底部终端面板，用 runtimeSignals 订阅会话事件。</p></article></div><div class="actions">{link('查看技术架构','../technology/index.html','button secondary')}{link('浏览协议支持','../osc/index.html','button secondary')}</div></section>{cta('../')}'''
render('features','功能','了解 Ianvs 的本地 shell、SSH、终端布局、回看、本地录制与可选配置同步。',features)

tech=intro('02','UNDER THE SURFACE','界面到核心，<br>边界清晰。','从可嵌入的 Flutter 视图，到 Rust PTY 与 VT 核心。<br>把终端能力做成可以理解、复用和验证的层次。')
tech+=f'''<section class="section wrap" aria-labelledby="layers-title"><p class="eyebrow">ARCHITECTURE</p><h2 id="layers-title">每一层，各司其职。</h2><div class="architecture-map"><div><span class="layer-tag">HOST</span><h3>example / Flutter app</h3><p>窗口、标签、菜单、Profile 编辑与产品流程</p></div><span class="layer-connector" aria-hidden="true">↓</span><div><span class="layer-tag">RUNTIME</span><h3>ianvs_terminal</h3><p>会话运行时、viewport、输入、选区与滚动适配</p></div><span class="layer-connector" aria-hidden="true">↓</span><div><span class="layer-tag">TRANSPORT</span><h3>ianvs_pty</h3><p>PTY 会话传输与 FFI 包装</p></div><span class="layer-connector" aria-hidden="true">↓</span><div><span class="layer-tag">NATIVE</span><h3>Rust / native core</h3><p>PTY、VT 解析、终端帧与图形资源</p></div></div><p class="section-footnote">可选 Go / GORM 数据 API 提供配置同步目标；终端运行与本地保存不依赖它。</p></section>
<section class="section section-rule wrap" id="xterm-title">{section_head('01','EMBEDDABLE BY DESIGN','给你的 Flutter 应用，<br>一个真正的终端。','ianvs_terminal_core 将 Dart / Flutter 运行时、终端视图、底部面板和 Rust PTY 打包在一起。')}<div class="two-grid"><div><h3>macOS 原生库随构建打包</h3><p>CodeAsset build hook 自动编译并打包原生库，宿主无需额外增加 Xcode dylib 复制步骤。</p><ul class="check-list"><li>macOS Intel / Apple silicon；Flutter 3.41+、Rust 1.88+</li><li>TerminalSessionView：单个终端会话</li><li>TerminalBottomPanel：可管理标签的底部面板</li><li>runtimeSignals：有序的会话事件 API</li><li>宿主管理窗口、导航、权限与平台剪贴板</li></ul>{link('阅读 package 接入文档',DOCS+'packages/ianvs_terminal_core/README.md')}</div><div class="code-card"><div class="code-header"><span>Flutter / Dart</span><button type="button" data-copy="embed-code">复制代码</button></div><pre><code id="embed-code">import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

// 由宿主提供平台剪贴板回调
final runtime =
  TerminalRuntimeController.native(
    copyToClipboard: copyToClipboard,
    readClipboard: readClipboard,
  );</code></pre><p class="code-note">结构示例；完整生命周期与依赖版本见 package 文档。</p></div></div></section>
<section class="section section-rule wrap" id="capability-map-title">{section_head('02','CURRENT CONTRACT','让状态、持久化与回放，<br>各走自己的路径。')}<div class="three-grid"><article class="simple-card"><span class="pill">SESSION</span><h3>一次运行，一个会话</h3><p>Session 对应一个真实 PTY 进程。运行时标题、时间戳与退出状态属于当前会话。</p></article><article class="simple-card"><span class="pill">RELAUNCH</span><h3>恢复布局，启动新会话</h3><p>Terminal Layout 保存标签和 Pane 拓扑。Relaunch Spec 只保留 Profile、命令参数和初始目录。</p></article><article class="simple-card"><span class="pill">RECORDING</span><h3>录制独立于布局</h3><p>Recording Library 使用当前格式的本地文件。SSH 录制在隔离回放后端打开，不会创建远程连接。</p></article></div><div class="note-panel"><h3>当前工程重点：运行时契约稳定性</h3><p>Native 与 Dart 使用明确的当前版本边界，拒绝缺失、未知或不支持的数据形状。旧版 JSON 回退接口和历史 xterm 风格回调不属于公开接入面。</p>{link('查看当前执行目标',DOCS+'docs/CURRENT_EXECUTION_TARGET.md')}</div></section>
<section class="section section-rule wrap" id="frame-diff-visuals"><p class="eyebrow">FRAME & VIEWPORT</p><h2 id="frame-diff-visuals-title">只把需要变化的内容，<br>送到需要它的地方。</h2><div class="frame-flow"><div><b>01 / PTY</b><span>程序输出</span></div><span aria-hidden="true">→</span><div><b>02 / CORE</b><span>解析与终端帧</span></div><span aria-hidden="true">→</span><div><b>03 / VIEWPORT</b><span>变化行与绘制</span></div></div><p class="lead-small">解析、会话运行时和视图绘制各自承担责任。终端帧与缓存减少重复处理，诊断导出帮助定位具体工作负载中的问题。</p><details class="resource-details"><summary>展开 Frame Diff 原理参考图</summary><p>保留的早期原理图用于理解设计思路；当前接口以源码与 package 文档为准。</p><div class="resource-links">{''.join(link(label,'../assets/images/frame-diff/'+name) for label,name in [('原理与优势','principle-advantages.png'),('生命周期','lifecycle.png'),('Snapshot / Delta','snapshot-delta.png'),('设计收益','benefits.png')])}</div></details></section>
<section class="section section-rule wrap" id="feature-visuals"><p class="eyebrow">REFERENCE LIBRARY</p><h2 id="feature-visuals-title">继续沿着线索阅读。</h2><div class="resource-grid"><article class="resource-item"><h3>架构参考</h3><p>原有结构图保留为设计参考。</p>{link('打开参考图','../assets/images/feature-visuals/architecture-overview.png')}</article><article class="resource-item" id="shell-hook-visual"><h3>Shell Hook</h3><p>命令、目录与会话线索。</p>{link('打开参考图','../assets/images/feature-visuals/shell-hook.png')}</article><article class="resource-item" id="row-cache-visual"><h3>行级缓存</h3><p>从变化行到视图更新。</p>{link('打开参考图','../assets/images/feature-visuals/row-cache.png')}</article><article class="resource-item" id="input-modes-visual"><h3>输入模式</h3><p>按键与终端模式的关系。</p>{link('打开参考图','../assets/images/feature-visuals/input-modes.png')}</article><article class="resource-item" id="instant-replay-visual"><h3>最近画面</h3><p>早期回看原理；保存录制见功能页。</p>{link('打开参考图','../assets/images/feature-visuals/instant-replay.png')}</article><article class="resource-item" id="matrix-title"><h3>OSC 协议参考</h3><p>按协议查看能力与权限边界。</p>{link('浏览支持矩阵','../osc/index.html')}</article></div><div class="actions">{link('仓库架构',DOCS+'docs/ARCHITECTURE.md','button secondary')}{link('测试与验证',DOCS+'docs/TESTING.md','button secondary')}</div></section>{cta('../')}'''
render('technology','技术','Ianvs 的 Flutter、Dart、Rust 分层架构，可嵌入的 ianvs_terminal_core package，以及当前运行时契约。',tech)

roadmap=intro('04','A WORK IN PROGRESS','把下一步，<br>走得扎实。','已具备的能力、正在打磨的部分、仍待验证的平台。<br>用清楚的状态，描述产品的进展。')
roadmap+=f'''<section class="section wrap"><div class="progress-feature"><div><span class="status-pill active-status">当前重点</span><h2>运行时契约<br>稳定性</h2><p>持续收紧 native 与 Dart 的当前边界，让会话、输入、渲染和诊断在明确契约下保持一致。</p>{link('查看执行目标',DOCS+'docs/CURRENT_EXECUTION_TARGET.md')}</div><div class="progress-lines"><div><span>01</span><p>明确的当前版本接口</p></div><div><span>02</span><p>真实 PTY 的验证路径</p></div><div><span>03</span><p>布局、重启与录制各自独立</p></div><div><span>04</span><p>针对性回归与完整验证</p></div></div></div></section>
<section class="section section-rule wrap">{section_head('01','PLATFORM STATUS','先把一个平台做好。','macOS 是当前主交付平台。<br>其他平台的产品状态，以真实设备证据为准。')}<div class="platform-list"><article><h3>macOS</h3><span class="status-pill active-status">主交付平台</span><p>本地 shell、SSH、标签与分屏、回看和本地录制。推荐从 macOS 本地源码试用。</p></article><article><h3>iOS</h3><span class="status-pill">SSH 配套路径</span><p>已实现面向 SSH 的流程与本地持久化。实体设备与发布验收仍需要独立证据。</p></article><article><h3>Linux / Windows</h3><span class="status-pill">待桌面验证</span><p>尚不作为已交付桌面平台宣传，需要真实桌面宿主与交互验证后再更新状态。</p></article></div></section>
<section class="section section-rule wrap">{section_head('02','PRODUCT DIRECTION','终端，始终是中心。')}<div class="two-grid"><article class="simple-card"><p class="eyebrow">CONTINUE TO REFINE</p><h3>持续打磨的日常能力</h3><ul class="check-list"><li>本地与 SSH 会话的共同体验</li><li>多标签、分屏与终端布局恢复</li><li>回看、录制资料库与输出搜索</li><li>本地保存与可选 API 配置同步</li><li>可复用的 Flutter 终端 package</li></ul></article><article class="simple-card"><p class="eyebrow">CLEAR PRODUCT SCOPE</p><h3>清晰的产品边界</h3><p>选择文件夹会在这个目录打开新终端，不建立项目容器。当前产品不定义项目浏览器、Git / IDE 上下文、插件市场或托管协作服务。</p><p>这样，每一项改进都可以回到同一个问题：它是否让终端更好用。</p>{link('阅读完整产品范围',DOCS+'docs/TERMINAL_PRODUCT_SCOPE.md')}</article></div></section>
<section class="section section-rule wrap">{section_head('03','FOLLOW THE WORK','在公开的代码里，<br>一起把它做得更好。')}<div class="resource-grid"><article class="resource-item"><h3>跟踪变更</h3><p>在 GitHub 查看最近提交与代码演进。</p>{link('查看提交',REPO+'/commits/main/')}</article><article class="resource-item"><h3>反馈问题</h3><p>附上平台、复现步骤与必要诊断信息。</p>{link('打开 Issues',REPO+'/issues')}</article><article class="resource-item"><h3>验证进展</h3><p>从测试文档了解本地验证入口。</p>{link('阅读测试文档',DOCS+'docs/TESTING.md')}</article></div></section>{cta('../')}'''
render('roadmap','产品进展','Ianvs 当前能力、macOS 主交付状态、iOS SSH 配套路径和待验证桌面平台，以及运行时稳定性的当前重点。',roadmap)

start=intro('05','MAKE IT YOURS','你的下一次会话，<br>从源码开始。','在 macOS 上运行 Ianvs Terminal，<br>用自己的日常命令，体验它的工作方式。')
start+=f'''<section class="section wrap start-layout"><aside class="start-aside"><span class="pill">macOS / FROM SOURCE</span><h2>准备好，<br>打开终端。</h2><p>建议先安装 Flutter、Rust / Cargo，以及 Xcode 命令行工具。具体版本要求与平台步骤以仓库 README 为准。</p><p class="inline-note">此处提供源码运行入口。可用的发行文件请以 GitHub Releases 实际列表为准。</p>{link('查看仓库 README',DOCS+'README.md')}{link('查看 Releases',REPO+'/releases')}</aside><div class="install-steps"><article><div class="step-heading"><span>01</span><h3>获取源码</h3></div><div class="code-card"><div class="code-header"><span>Terminal</span><button type="button" data-copy="clone-code">复制命令</button></div><pre><code id="clone-code">git clone https://github.com/robinfai/ianvs-terminal.git
cd ianvs-terminal</code></pre></div></article><article><div class="step-heading"><span>02</span><h3>准备依赖，启动 macOS 应用</h3></div><div class="code-card"><div class="code-header"><span>Repository root</span><button type="button" data-copy="run-code">复制命令</button></div><pre><code id="run-code">make bootstrap
make run</code></pre></div><p>在仓库根目录执行。应用使用本地存储，试用本地 shell 与保存 SSH 主机无需先配置数据 API。</p></article><article><div class="step-heading"><span>03</span><h3>试试你的工作流</h3></div><ol class="number-list"><li>打开本地 shell，在常用目录运行命令</li><li>创建一个 SSH Profile，打开远程会话</li><li>分出一个 Pane，让输出并排显示</li><li>录制一段会话，保存后从「回看」重新打开</li></ol></article></div></section>
<section class="section section-rule wrap">{section_head('01','BUILD WITH CONFIDENCE','参与开发，<br>从验证开始。')}<div class="two-grid"><div><h3>常用验证入口</h3><p>仓库提供静态分析、测试与完整验证命令。提交修改前，按实际改动范围完成对应检查。</p>{link('阅读测试指南',DOCS+'docs/TESTING.md')}</div><div class="code-card"><div class="code-header"><span>Verification</span><button type="button" data-copy="verify-code">复制命令</button></div><pre><code id="verify-code">make analyze
make test
make verify</code></pre></div></div></section>
<section class="section section-rule wrap"><p class="eyebrow">GOOD TO KNOW</p><h2>开始之前的小问题。</h2><div class="faq"><details><summary>使用之前需要连接服务器或 API 吗？</summary><p>不需要。配置与 SSH 主机先保存在本机。可选 API 只用于配置同步，在设置中的 Defaults &amp; appearance → API sync (optional) 管理。</p></details><details><summary>关闭 API 会影响我的本地数据吗？</summary><p>关闭或切换 API 保留本地数据。布局与录制文件始终留在本机，也不会随配置同步。</p></details><details><summary>恢复布局会找回已经退出的进程吗？</summary><p>布局恢复会按保存的 Profile、命令参数和目录启动新的 PTY 会话。想回看之前的输出，请使用已保存的录制。</p></details><details><summary>可以在 iPhone、Linux 或 Windows 上使用吗？</summary><p>macOS 是主交付平台。iOS 已实现 SSH 配套流程与本地保存，但实体设备和发布验收还需要独立证据；Linux / Windows 尚待真实桌面宿主证据。</p></details><details><summary>可以把终端嵌入自己的 Flutter 应用吗？</summary><p>可以从 ianvs_terminal_core 的 macOS 接入路径开始。它包含运行时、终端视图和底部面板。<a class="text-link" href="{DOCS}packages/ianvs_terminal_core/README.md">阅读 package 文档 ↗</a></p></details></div></section>
<section class="source-banner wrap"><span class="code-symbol" aria-hidden="true">&lt;/&gt;</span><div><h2>代码开放，欢迎动手。</h2><p>读源码、提问题，或试着改进你在意的体验。</p></div>{link('打开 GitHub',REPO,'button primary')}</section>'''
render('open-source','开始使用','从源码在 macOS 运行 Ianvs Terminal，查看准备步骤、运行命令、验证方法与常见问题。',start)

# Protocol content is kept as auditable data, independent of generated markup.
protocols = [
('xterm','OSC 0 / 1 / 2','支持','窗口与图标标题','有界标题元数据；不获取主机权限。'),
('xterm','CSI 20 / 21 / 22 / 23 t','Xterm256 支持','标题查询与标题栈','有界标题查询、独立标题通道与 10 槽标题栈。'),
('xterm','OSC 4 / 5 / 6','支持子集','调色板与特殊颜色','设置、查询、重置遵循外观权限与终端配置。'),
('xterm','OSC 7','支持','当前工作目录','上报目录与远程身份；拒绝畸形路径。'),
('xterm','OSC 8','支持','超链接','保留 URI 与链接身份；打开动作由宿主策略控制。'),
('xterm','OSC 9 / 9;4','安全子集','通知与任务进度','纯文本通知；进度状态与百分比有界。'),
('xterm','OSC 9;9','适配器支持','绝对工作目录','保留已有远程身份。'),
('xterm','OSC 10–19 / 110–119','支持','动态颜色与恢复','前景、背景、光标、选择与高亮。'),
('xterm','OSC 23','不支持','有界空操作','消费旧输入，不修改标题栈。'),
('xterm','OSC 50','支持子集','会话字体族','TrueType 字体族设置与查询；不持久化 Profile。'),
('xterm','OSC 52','权限控制','文本剪贴板','受权限控制的 Base64 文本读写请求。'),
('xterm','OSC 60 / 61 / 62','只读支持','能力查询','查询允许、拒绝与可用子能力，不改变权限。'),
('kitty','OSC 21','有界子集','批量颜色操作','颜色设置、查询与重置。'),
('kitty','OSC 22','支持','指针形状','指针设置、重置、栈与状态查询。'),
('kitty','OSC 66','支持','多单元格文本','定宽、自然宽、缩放与对齐。'),
('kitty','OSC 72','macOS 子集','拖放接收端','仅接收用户放入的数据，不读取远程文件或目录。'),
('kitty','OSC 99','安全子集','交互通知','通知生命周期与纯文本按钮，不执行通知命令。'),
('kitty','OSC 5522','权限控制','多 MIME 剪贴板','多 MIME 数据、授权读取、令牌与分块回复。'),
('iterm','OSC 133','支持','Shell 生命周期','Prompt、命令、输出阶段与嵌套 shell 语义。'),
('iterm','OSC 1337 · 元数据','支持子集','目录与远程身份','CurrentDir、RemoteHost、UserVar 等元数据。'),
('iterm','OSC 1337 · 外观','支持子集','颜色、光标与 Unicode','有界外观设置与 Unicode 8/9 宽度状态。'),
('iterm','OSC 1337 · 交互','协议子集','终端内交互','协议处理遵循产品动作边界；不承诺历史独立 UI 入口。'),
('iterm','OSC 1337 · 图像 / 文件','权限控制','内联图像与显式保存','文件下载、外部 URL 与 attention 由宿主策略控制。'),
('iterm','OSC 1337 · RequestUpload','不授权','主机文件访问等','RequestUpload、StealFocus 与 SetProfile 不获得主机权限。'),
('iterm','OSC 21337','外观子集','标签状态','指示点、状态文本与状态颜色。'),
('other','OSC 633','适配器子集','VS Code shell 集成','生命周期、命令关联与目录属性。'),
('other','OSC 777','安全子集','urxvt 通知','结构化标题与文本消息。'),
('other','OSC 934','支持','Ianvs 并行进度','带 ID / 标签的有界并行任务状态、查询与移除。'),
('other','OSC 3008','元数据支持','UAPI 层级上下文','层级上下文更新与恢复；不建立产品项目容器。'),
]
osc=intro('03','PROTOCOL FIELD GUIDE','让协议支持，<br>有据可查。','按协议查找终端能力与适用边界。<br>支持解析、展示元数据和授权主机动作，是不同层面的能力。')
osc+=f'''<section class="protocol-tools wrap" aria-labelledby="osc-overview-title"><h2 class="sr-only" id="osc-overview-title">查找 OSC 协议</h2><label class="search-control"><span aria-hidden="true">⌕</span><span class="sr-only">搜索协议或能力</span><input type="search" data-protocol-search placeholder="搜索协议、能力或编号，例如 OSC 52" aria-label="搜索协议或能力"></label><div class="protocol-filters" role="group" aria-label="筛选协议族"><button type="button" data-filter="all" aria-pressed="true">全部</button><button type="button" data-filter="xterm" aria-pressed="false">xterm</button><button type="button" data-filter="kitty" aria-pressed="false">Kitty</button><button type="button" data-filter="iterm" aria-pressed="false">iTerm2</button><button type="button" data-filter="other" aria-pressed="false">其他</button></div><p class="filter-count" data-result-count role="status">{len(protocols)} 项协议记录</p></section><div class="protocol-sections wrap">'''
for group,name,ident,desc in [('xterm','xterm 与通用扩展','xterm-osc-title','标题、目录、颜色、超链接与剪贴板。'),('kitty','Kitty','kitty-osc-title','颜色、指针、文本、拖放与交互通知。'),('iterm','iTerm2 与 Shell 集成','iterm-osc-title','命令生命周期、会话元数据与受限主机动作。'),('other','其他协议与 Ianvs 扩展','other-osc-title','编辑器适配、通知、任务进度与上下文元数据。')]:
    rows=''.join(f'<tr data-protocol-row data-family="{g}"><th scope="row">{escape(code)}</th><td><span class="status-pill">{status}</span></td><td><strong>{name_}</strong><p>{note}</p></td></tr>' for g,code,status,name_,note in protocols if g==group)
    osc+=f'<section class="protocol-group" data-protocol-group="{group}" aria-labelledby="{ident}"><div class="protocol-heading"><h2 id="{ident}">{name}</h2><p>{desc}</p></div><div class="table-scroll" tabindex="0" role="region" aria-label="{name} 协议表格"><table><caption class="sr-only">{name} 协议能力与边界</caption><thead><tr><th scope="col">协议</th><th scope="col">范围</th><th scope="col">能力与说明</th></tr></thead><tbody>{rows}</tbody></table></div></section>'
osc+='''<div class="empty-state" data-empty-state hidden><span aria-hidden="true">⌕</span><h2>没有找到匹配的协议</h2><p>换一个编号或关键词，也可以清除筛选查看全部。</p><button class="button secondary" type="button" data-clear-filters>清除筛选</button></div></div>'''
osc+=f'''<section class="section wrap" aria-labelledby="osc-boundaries-title"><div class="note-panel"><p class="eyebrow">READING THE MATRIX</p><h2 id="osc-boundaries-title">协议能力，有明确的边界。</h2><div class="two-grid"><p>现代 OSC 主要面向 Xterm256；VT220 配置通常拒绝或静默消费。通知、剪贴板、文件与 URL 等能力需要经过各自的权限策略，支持协议不会自动扩大主机权限。</p><p>本页是仓库协议矩阵的概览。元数据支持不代表独立产品入口；旧版命令入口与调试面板也不由本表重新授权。具体子集、测试证据和限制请查阅完整矩阵与当前产品范围。</p></div><div class="actions">{link('完整协议矩阵',DOCS+'docs/protocols/osc_support_matrix.md','button secondary')}{link('当前产品范围',DOCS+'docs/TERMINAL_PRODUCT_SCOPE.md','button secondary')}</div></div></section>'''
render('osc','协议参考','可搜索的 Ianvs OSC 协议参考，涵盖 xterm、Kitty、iTerm2 与其他扩展的支持子集和权限边界。',osc)
print('Built 6 static pages.')
