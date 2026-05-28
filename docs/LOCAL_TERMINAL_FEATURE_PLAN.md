# Local Terminal Feature Plan

这份文档把外部竞品调研收敛成 `ianvs terminal` 后续本地 terminal 功能设计。范围只覆盖本地 terminal：macOS 本地 shell、tabs、panes、profiles、配置、shell integration、workspace UX。不做 SSH、remote domain、SFTP、serial、协作 Web session。

## Baseline

- 规划时间：2026-05-15 Asia/Shanghai
- 仓库分支：`codex/hyper-first-shell`
- 仓库基线提交：`974be56e15859b1f302fc56e496f451efadc44fd`
- 基线提交时间：2026-05-15 09:36:12 +0800
- 基线提交标题：`Preserve Ghostty configuration findings as a reusable product baseline`

## Inputs

- `/Users/robinfai/Downloads/deep-research-report.md`
- `docs/GHOSTTY_CONFIG_COMPARISON.md`
- `docs/HYPER_LIKE_TARGET.md`
- `docs/HYPER_LIKE_GAP_MATRIX.md`
- `docs/ROADMAP.md`
- 官方竞品文档：
  - [Alacritty configuration](https://alacritty.org/config-alacritty.html)
  - [Ghostty configuration](https://ghostty.org/docs/config)
  - [Ghostty keybindings](https://ghostty.org/docs/config/keybind)
  - [kitty overview](https://sw.kovidgoyal.net/kitty/overview/)
  - [kitty shell integration](https://sw.kovidgoyal.net/kitty/shell-integration/)
  - [WezTerm features](https://wezterm.org/features.html)
  - [WezTerm multiplexing](https://wezterm.org/multiplexing.html)
  - [Windows Terminal panes](https://learn.microsoft.com/en-au/windows/terminal/panes)
  - [Zellij layouts](https://zellij.dev/documentation/layouts.html)
  - [Zellij features](https://zellij.dev/features/)
  - [Konsole handbook](https://docs.kde.org/trunk_kf6/en/konsole/konsole/commandreference.html)
  - [GNOME Terminal preferences](https://help.gnome.org/gnome-terminal/pref.html)
  - [iTerm2 documentation](https://stage.iterm2.com/documentation-one-page.html)
  - [Warp blocks](https://docs.warp.dev/terminal/blocks/block-basics)
  - [Warp command search](https://docs.warp.dev/terminal/entry/command-search)
  - [Wave workspaces](https://docs.waveterm.dev/workspaces)

## Scope

### In

- 本地 shell session。
- 本地 tabs、panes、workspace、layout 保存和恢复。
- 本地 profile、theme、keybinding、clipboard/paste、notification、hotkey window 配置。
- shell integration 暴露的 prompt marks、cwd tracking、command status、recent commands、recent directories。
- 本地 terminal productivity：search、command output selection、paste history、read-only mode、clear scrollback。

### Out

- SSH profile、SSH config、SSH agent、SSH terminfo、SSH env 注入。
- remote domain、remote workspace、remote multiplexing。
- SFTP、Telnet、serial、移动端 Termux 类场景。
- 协作 Web session、浏览器共享终端。
- 插件生态 v1、AI widgets v1、renderer 重写。

## Current Repo Baseline

| Area | Current state | Gap |
| --- | --- | --- |
| Profile persistence | `ianvs_profiles.json`，由 `ProfileRepository` 读写 | profile 能覆盖终端启动和视觉，但还不是统一配置系统 |
| App preferences | `ianvs_preferences.json`，主要有默认 profile 和 theme mode | app 级偏好太薄，不能承载 keybindings、layouts、clipboard policy |
| Terminal config | `TerminalSessionConfig` 已覆盖 program、args、env、cwd、emulation、scrollback、字体、颜色、cursor、copy-on-select、option-drag-mode | 配置项较多，但来源、热重载和优先级没有统一协议 |
| Shell integration | 已有 preexec、command finished、precmd、cwd、recent commands、recent directories、prompt marks | 只有总开关，缺 feature 级策略和产品化动作 |
| Tabs and panes | `ShellScreen` 已有 tab、split right/down、pane focus 等入口 | pane tree、layout persistence、move/resize/swap/zoom 需要收口 |
| Actions and shortcuts | `ShellScreen` 中已有 command surface 和硬编码快捷键 | 缺统一 action registry、冲突检测、配置覆盖和焦点消费规则 |
| Search and command output | 已有搜索、prompt 导航、select command output 等能力 | 需要变成可配置、可测试、可发现的本地生产力能力 |
| Paste and clipboard | 已有 paste、advanced paste、paste history、OSC 52 流程 | 缺统一 clipboard/paste policy 和安全边界 |
| Hotkey window | 已有 `WindowBridge.toggleHotkeyWindow()` | 缺位置、尺寸、动画、autohide、权限失败状态等配置 |
| Notifications | 已有 command finished、bell、activity 类入口 | 缺用户策略、静默/活动监控和验收规则 |

## Competitor Signals

| Product | Useful local-terminal signal | What to avoid |
| --- | --- | --- |
| Alacritty | TOML、import、live reload、窗口/字体/滚动/光标/选择配置边界清楚 | 不吸收“没有 tabs/panes”的极简取向 |
| Ghostty | zero-config defaults、配置拆分/重载、keybinding 触发语义、quick terminal | 不吸收 `ssh-env`、`ssh-terminfo` |
| kitty | layouts、action browser、shell integration、prompt 跳转、last command output、cwd/env clone | remote control 和 SSH 相关能力不进入本地 v1 |
| WezTerm | pane tree、workspace、Lua 风格可组合配置、action/keybinding 统一 | remote domain、SSH domain、serial domain 不进入本地 scope |
| Windows Terminal | command palette、profiles、actions、split panes、focus/move/resize pane | 不为 Windows 平台提前扩展当前 macOS 目标 |
| Zellij | layout save/load、pane UI、floating/stacked panes、默认可用的 workspace | 协作、Web client、插件生态先不做 |
| Konsole | 多 profile、活动/静默监控、搜索、保存输出、布局自动化 | 不绑定 KDE/Qt 平台语义 |
| GNOME Terminal | 稳定 profile、偏好设置、标签页、桌面一致性和可访问性 | 不把稳态桌面偏好扩成过重设置面 |
| iTerm2 | hotkey window、Open Quickly、timestamps、badges、shell integration、profile command | 不做 remote 文件传输和 SSH 自动化 |
| Warp | blocks、sticky command header、block search、command search | AI/workflow widgets 不作为 v1 核心 |
| Wave | workspace persistence、blocks、terminal 和辅助面板组合 | 不做远程协作或云同步 |
| Tabby | 现代 shell workspace、tabs/splits、theme/shortcut discoverability | SSH/Telnet/SFTP/serial 是明确非目标 |
| Hyper | UI 可定制、现代 shell chrome、主题入口 | 不做 JS/CSS 插件生态 v1 |

## Product Principles

1. 先把本地 terminal 做成完整产品，不把 SSH 当成下一阶段默认目标。
2. 先收口模型，再增加选项；配置、动作、pane、notification 都要有统一入口。
3. terminal 输入优先级高于 app 快捷键；任何 action surface 都不能把控制字符误写进 shell。
4. shell integration 是本地效率能力的基础，但必须能关闭，且关闭后 terminal 仍可用。
5. 默认体验要好，不要求用户先写配置才能正常使用。
6. 高阶能力先作为后置增强，不阻塞基础工作区、配置和快捷键模型。

## Feature Design

### 1. Local Workspace Model

目标模型：

```text
TerminalWorkspace
  TerminalTab[]
    TerminalPaneNode
      LocalSession
```

需要支持：

- 新建 tab。
- 关闭 tab，最后一个 tab 关闭后回到 empty state。
- split right / split down / auto split。
- pane focus next / previous / by direction。
- pane resize。
- pane move / swap。
- pane zoom / unzoom。
- undo close tab / pane。
- 从当前 pane 继承 cwd 打开新 tab 或 split。
- 保存和恢复本地 workspace layout。

非目标：

- 不保存远程连接。
- 不恢复 SSH session。
- 不把 tmux server 作为 workspace 后端。

### 2. Action Registry

每个用户可触发动作都注册为稳定 action：

```text
TerminalAction
  id
  label
  category
  defaultKeyBinding
  enabledWhen
  terminalInputPolicy
  commandPaletteVisibility
```

第一批 action 分类：

| Category | Actions |
| --- | --- |
| Session | new tab, close tab, reopen closed tab, duplicate current cwd |
| Pane | split right, split down, focus direction, resize, swap, zoom, close pane |
| Clipboard | copy, paste, paste history, paste as bracketed, copy command output |
| Search | search scrollback, next match, previous match, clear search |
| Shell integration | next prompt, previous prompt, select command output, open recent directory |
| View | clear scrollback, toggle read-only, toggle command palette, toggle hotkey window |
| Profile | open profile, edit profile, set default profile, apply theme |
| Monitor | toggle command-finished notify, toggle bell notify, toggle silence/activity monitor |

关键规则：

- action id 是配置和测试的稳定边界。
- keybinding 只引用 action id，不直接调用 `ShellScreen` 私有方法。
- 同一个 keybinding 冲突时，配置加载必须给出可见诊断。
- 当 terminal 正在处理文本输入、IME composition、paste 或 selection drag 时，app action 不抢输入。

### 3. Keybinding Model

配置需要表达：

- 默认快捷键。
- 用户覆盖。
- 禁用某个默认快捷键。
- 多平台保留位，但当前只实现 macOS。
- 触发条件：global、focused app、terminal focused、command palette open。
- 消费策略：终端优先、app 优先、仅当 action performable。

第一阶段只需要支持本地配置，不需要完整 DSL。推荐先用 JSON schema 承载，后续再决定是否导入 TOML/YAML。

### 4. Unified Local Config

目标是把 profile、app preferences、keybindings、layouts、clipboard/paste policy、monitor rules 收进一个 versioned local config。

建议配置结构：

```text
LocalTerminalConfig
  version
  profiles
  defaultProfileId
  appearance
  keybindings
  workspace
  clipboard
  paste
  shellIntegration
  notifications
  hotkeyWindow
```

配置优先级：

1. 内建默认值。
2. 用户配置文件。
3. profile override。
4. 当前 session 临时状态。

热重载规则：

| Config area | Reload behavior |
| --- | --- |
| Theme, font size, cursor blink, keybindings, notification policy | 可热重载 |
| Shell program, args, env, cwd, emulation, shell integration mode | 只影响新 session |
| Workspace layout restore | 下次打开 workspace 生效 |
| Clipboard/paste policy | 可热重载，但进行中的 paste 不被中断 |

迁移规则：

- 旧 `ianvs_profiles.json` 必须可读。
- 旧 `ianvs_preferences.json` 必须可读。
- 首次写入新 config 时保留旧文件读取 fallback。
- schema 不能新增 SSH、remote、serial、SFTP 顶层字段。

### 5. Shell Integration Features

保留当前本地 shell hook 能力，并把它产品化：

- prompt marks。
- current working directory。
- command start。
- command finished。
- command exit status。
- recent commands。
- recent directories。
- last command output range。

用户功能：

- jump to previous / next prompt。
- select command output。
- copy last command output。
- new tab / split from current cwd。
- open recent directory。
- command finished notification。
- long-running command finished notification。

关闭 shell integration 时：

- terminal 输入输出不受影响。
- prompt 导航、cwd inherit、command output selection 降级为不可用 action。
- UI 必须说明是能力不可用，而不是报错。

### 6. Clipboard And Paste Policy

需要把已有 copy/paste 能力整理为可配置策略：

- copy-on-select：off / clipboard。
- right click：context menu / paste / copy selection。
- middle click：disabled / paste。
- bracketed paste：auto / force / plain。
- large paste confirmation。
- multiline paste confirmation。
- paste history size。
- OSC 52 copy/paste 策略。
- read-only mode 下禁止 paste 和 send text。

验收重点：

- 粘贴不会绕过 read-only。
- 多行粘贴有策略保护。
- selection copy 不破坏 terminal focus。
- OSC 52 行为仍受 emulation/profile 边界控制。

### 7. Search, Blocks, And Scrollback

本地生产力能力不需要完整复制 Warp，但可以吸收 block 化体验：

- 普通 scrollback search。
- prompt mark search。
- block scoped search。
- jump to command block。
- sticky command header。
- copy command output。
- save scrollback / save command output。
- clear scrollback。

第一阶段只实现 action 与状态模型；视觉呈现可以沿用现有 shell surface，避免同时重做 terminal renderer。

### 8. Notifications And Monitors

本地通知规则：

| Rule | Trigger | Default |
| --- | --- | --- |
| bell | terminal bell event | unfocused only |
| command finished | shell integration command finished | unfocused only |
| long-running command finished | command duration exceeds threshold | unfocused only |
| silence | no output for configured duration while command running | off |
| activity | output appears in inactive pane | badge only |
| prompt ready | prompt mark appears after long command | off |

每条规则需要：

- enabled。
- threshold。
- target：badge / in-app toast / system notification。
- focus policy：always / unfocused / never。

### 9. Hotkey Window

本地 quick terminal 应建立在现有 `WindowBridge` 上：

- toggle hotkey window。
- 配置窗口宽高、屏幕位置、动画、autohide。
- 配置打开时使用 default profile 或 last active workspace。
- 记录 macOS 权限或平台调用失败状态。
- hotkey window 与主窗口共享配置，但不强制共享 workspace。

### 10. Themes And Visual Identity

优先做：

- theme preset 选择。
- light/dark paired theme。
- theme import/export。
- profile-level theme override。
- active/inactive pane 边界。
- split divider color。
- terminal background / selection / cursor 颜色。

后置：

- background image。
- blur。
- opacity。
- variable font axis。
- per-style font family。

### 11. Higher-Level Local Enhancements

这些能力有价值，但不应抢在统一配置、action registry 和 workspace model 前面：

- layout templates。
- command pane。
- timestamps。
- scrollback editor。
- graphics/image storage limit。
- local tmux convenience actions。
- coprocess convenience actions。

tmux/coprocess 只能作为本地辅助入口，不作为核心 workspace 后端。

## Prioritized Roadmap

### P0: Documentation And Boundaries

交付：

- 本文档。
- `docs/ROADMAP.md` 将 SSH 阶段替换为 Local Workspace Expansion。
- 明确 SSH/remote/serial/SFTP 非目标。

验收：

- 路线图没有把 SSH 作为后续阶段。
- 本地 workspace 的目标、非目标、完成条件清楚。

### P1: Action And Config Foundation

交付：

- `TerminalActionId` 与 action registry。
- keybinding default table。
- keybinding conflict diagnostics。
- versioned local config schema。
- 旧 profile/preferences 读取兼容。

验收：

- 所有顶层菜单/command palette/快捷键通过 action id 触发。
- app action 不泄漏到 terminal input。
- 旧配置文件仍能启动默认 shell。

### P2: Local Workspace

交付：

- `TerminalWorkspace`、`TerminalTab`、`TerminalPaneNode`。
- split/focus/resize/move/swap/zoom/close/undo close。
- same-cwd new tab/split。
- layout save/load。

验收：

- 多 pane 操作稳定。
- 关闭最后一个 pane/tab 后 empty state 正确。
- layout restore 不恢复任何远程概念。

### P3: Shell Productivity

交付：

- prompt mark navigation。
- command output selection/copy。
- recent commands/directories。
- block scoped search。
- clear scrollback。
- read-only mode。

验收：

- shell integration 关闭时相关 action disabled。
- shell integration 开启时 cwd 和 command range 可用。
- search/selection/copy 不破坏 scrollback 和 focus。

### P4: Clipboard, Notifications, Hotkey Window

交付：

- clipboard/paste policy。
- paste history policy。
- command finished/bell/activity/silence monitors。
- hotkey window 配置与失败状态。

验收：

- large/multiline paste 受策略保护。
- read-only 禁止发送文本。
- 通知只在配置允许时出现。
- hotkey window 调用失败有可见状态。

### P5: Visual And Advanced Local Features

交付：

- theme import/export。
- paired light/dark theme。
- split divider/unfocused pane visual policy。
- layout templates。
- command pane。
- timestamps。
- scrollback export。
- graphics/image storage policy。

验收：

- 不引入 plugin system 作为前置条件。
- 不触碰 renderer rewrite。
- advanced feature 可关闭，默认路径仍简单。

## Design Types

这些是规划级类型名，用于后续实现任务拆分，不要求一次性落地。

```text
TerminalActionId
TerminalAction
TerminalKeyBinding
TerminalKeyBindingScope
TerminalInputPolicy
LocalTerminalConfig
TerminalWorkspace
TerminalTab
TerminalPaneNode
TerminalLayoutTemplate
TerminalMonitorRule
TerminalClipboardPolicy
TerminalPastePolicy
HotkeyWindowConfig
ShellIntegrationFeatureSet
```

## Test Plan

### Unit Tests

- action registry：注册、查找、重复 id、enabled predicate。
- keybinding：默认值、用户覆盖、禁用、冲突诊断、scope matching。
- config：旧 profile/preferences 读取、version migration、禁止 remote 字段。
- workspace model：split、focus、resize、move、swap、zoom、close、undo close。
- shell integration state：prompt marks、cwd、command status、recent commands/directories。
- clipboard/paste policy：large paste、multiline paste、read-only、bracketed paste。
- monitor rules：bell、command finished、long-running command、activity、silence。

### Widget Tests

- command palette/action menu 不向 terminal 输入字符。
- split right/down 后 active pane 正确。
- 关闭 active pane 后 focus fallback 正确。
- 关闭最后一个 tab 后 empty state 正确。
- same-cwd new tab/split 使用当前 cwd。
- shell integration disabled 时相关 action disabled。
- paste confirmation 与 paste history UI 不破坏 focus。
- hotkey window action 失败时显示可见状态。

### Integration / Manual

- 本地 `/bin/zsh` 或 `/bin/bash` smoke。
- IME composition + paste + resize。
- 多 pane resize 和 scrollback search。
- command finished notification。
- hotkey window 权限与失败路径。
- 确认 UI、配置和测试没有 SSH/remote/serial/SFTP 入口。

## Acceptance Checklist

- 文档和路线图都把本地 terminal 作为下一阶段主线。
- 任何新增配置类型都不能以 SSH/remote/serial/SFTP 为前置。
- action registry 是用户动作、快捷键、菜单和 command palette 的共同入口。
- workspace model 只管理本地 session。
- shell integration 是增强能力，不是 terminal 可用性的硬依赖。
- 所有涉及输入、粘贴、focus、selection 的任务必须保留现有 terminal protected contracts。

## Rejected

| Alternative | Reason |
| --- | --- |
| 继续把 SSH 作为 Phase 3 | 用户明确限定本地 terminal 范围，且本地 workspace、配置、action 模型还没收口 |
| 先做 plugin ecosystem | 过早扩大边界，会拖慢本地核心体验 |
| 先做 renderer rewrite | 当前规划主要是产品与配置层，renderer 不是阻塞项 |
| 直接复制某一个竞品 | 各竞品取向不同，`ianvs terminal` 当前更需要本地 workspace + shell product 收口 |
| 把 tmux 当核心 workspace 后端 | tmux 可作为本地辅助入口，但不应决定 app 的 pane/layout 数据模型 |
