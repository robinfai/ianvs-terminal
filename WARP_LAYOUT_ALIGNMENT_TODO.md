# Warp 布局与设计对齐待办

日期：`2026-05-04`

## 目标

把 Warp 文档截图中的应用元素布局、对应源码语义，以及 Ianvs Terminal 当前布局放在同一张整改清单里。后续实现不要求逐像素复刻 Warp，也不复制 Warp 品牌、素材、私有云能力或文案；目标是让 Ianvs Terminal 的信息层级、交互入口、主要 CTA、block 感知和搜索体验接近 Warp 的现代终端基线，不能停留在“功能都有但 UI 很像后台工具表单”的状态。

## 对齐基准

### Warp 文档截图

- `Tab Configs`：`https://docs.warp.dev/terminal/windows/tab-configs/`
  - `save-new-tab-config.png`：vertical tabs / tab context menu 中高亮 `Save as new config`。
  - `saved-tab-config-menu.png`：`+` 菜单中展示 saved tab config，右侧 sidecar 提供 `Make default`、`Edit config`、`Remove`。
- `Launch Configurations (Legacy)`：`https://docs.warp.dev/terminal/sessions/launch-configurations`
  - 作为 app-level `windows / tabs / panes / active_window_index / commands` 语义参考，不作为新 UI 的唯一视觉参考。
- `Terminal Blocks`：`https://docs.warp.dev/terminal/blocks`
  - `annotated_blocks-1.png`：命令与输出在 terminal 内容里形成一个 atomic block。
- `Block basics`：`https://docs.warp.dev/terminal/blocks/block-basics`
  - block divider、active block、失败 block 红色状态和 sticky command header 行为。
- `Modern Text Editing`：`https://docs.warp.dev/terminal/editor/`
  - `soft-wrapping.png`：底部 input editor、软换行、建议菜单和编辑器级快捷键。
- `Command Search`：`https://docs.warp.dev/terminal/entry/command-search/`
  - `command-search-panel.png`：统一搜索面板、结果列表、过滤前缀、可水平 resize。
- `Split panes`：`https://docs.warp.dev/terminal/windows/split-panes/`
  - pane header、active pane marker、拖拽调整 pane / 移到 tab 的产品感知。
- `Session Navigation`：`https://docs.warp.dev/terminal/sessions/session-navigation/`
  - session palette 按 prompt、当前命令、最近命令和状态搜索，按最近 focus 排序。

### Warp 源码

- `/private/tmp/warp-source-20260503/app/src/launch_configs/launch_config.rs`
  - `LaunchConfig::from_snapshot(name, app_state)` 从 app state 保存 `active_window_index + windows[]`。
  - `WindowTemplate / TabTemplate / PaneTemplateType` 保留 active tab、pane tree、cwd、commands、pane mode 和 shell override。
- `/private/tmp/warp-source-20260503/app/src/launch_configs/save_modal.rs`
  - `LaunchConfigSaveModal` 是居中 modal：标题、关闭、说明、文档链接、单行文件名编辑器、primary save button、成功后 `Open File`。
- `/private/tmp/warp-source-20260503/app/src/terminal/model/block.rs`
  - `Block` 持有 prompt grid、command/output grid、cwd、session、exit code、timestamps、banner、prompt snapshot、filter query 等。
- `/private/tmp/warp-source-20260503/app/src/terminal/model/blocks.rs`
  - `BlockList` 是 terminal scroll / render 模型的一部分，支持 restored separator、inline banner、subshell separator、rich content。
- `/private/tmp/warp-source-20260503/app/src/terminal/input/terminal.rs`
  - input editor 支持 pinned bottom/top/waterfall，并把 slash commands、prompts、conversation、skills、inline history、repos 等 inline menu 编排在输入区上下。
- `/private/tmp/warp-source-20260503/app/src/search/command_search/view.rs`
  - `CommandSearchView` 默认搜索 `history, workflows, and more`，支持 resizable panel 和统一结果渲染。
- `/private/tmp/warp-source-20260503/app/src/search/command_palette/navigation/search.rs`
  - session navigation 以 prompt、last/running command、hint text 建 fuzzy search 文本。
- `/private/tmp/warp-source-20260503/app/src/pane_group/pane/view/header/mod.rs`
  - pane header 承担 focus、close、overflow menu、drag/drop 和 pane move 行为。

### Ianvs 当前源码状态

- `lib/src/terminal_windows.dart`：已有产品层 `TerminalWindowsController`，支持 in-app window collection、active window、app-level launch config / restore。
- `lib/src/launch_config.dart`：已有 `version = 2`、`activeWindowIndex`、`windows[]`，并保留单窗口 legacy `tabs` 字段兼容。
- `lib/main.dart`
  - `_Header`：固定 `110px` 两行 header，包含产品名、session/status badge、window strip、tab strip 和大量 icon actions。
  - `_LaunchConfigPanel`：大尺寸 dialog，显示 app snapshot、统计卡片、手动 path、pane startup command 列和 Save / Apply CTA。
  - `_InlineBlockRail` + `_BlockHistoryPanel`：在 terminal viewport 顶部叠加 active block rail，右侧仍有 block history side panel。
  - `_ModernInputBar`：底部 TextField 输入区，最多 4 行，右侧 Submit / History / Save / Raw 图标。
  - `_CommandHistoryPanel`：底部 250px 面板，只合并 saved commands 和当前 tab block history。
- `lib/src/workspace_search.dart`：只搜索当前 active window 的 tab / pane，不覆盖全 app window collection。
- `test/widget_test.dart`：已覆盖 app-level launch config、多窗口恢复、menu entries、block panel、command history，但没有截图或 golden 级视觉验收。

## 差异总览

| 区域 | Warp 布局 / 设计 | Ianvs 当前状态 | 对齐结论 |
| --- | --- | --- | --- |
| App chrome / tabs | 顶部 chrome 更轻，tab / `+` 菜单和右键菜单承载主要配置入口；pane 有自己的 header 和 active marker。 | Header 很高，动作集中在两行工具栏；window strip 是 in-app 横条；pane 缺少 header / drag-drop / active triangle。 | 功能入口已多，但视觉更像调试工具栏，需要压缩 chrome 并把配置动作移入菜单/上下文。 |
| Tab / Launch config | 文档截图强调 `+` 菜单、context menu、saved config sidecar；legacy 源码 modal 是 name-first、save-success-open-file 流程。 | 已有 app-level export 和摘要面板，但仍 path-first，缺少 saved config 菜单、sidecar、成功态和 open/copy file feedback。 | M7A 基本落地；M7B 只完成面板升级的前半段，仍需贴近截图节奏。 |
| Blocks | block 是 terminal 内容模型本身，带 divider、状态、selection、sticky header、上下文操作。 | 有 inline rail 和右侧 panel，但 block 仍是 overlay + side panel，不是 scrollback 内分组。 | 视觉感知有所提升，但还不像 Warp 的 terminal-native blocks。 |
| Input editor | 输入区像编辑器，支持软换行、inline menu、pinned modes、command search 入口。 | 底部输入栏可用，但仍是表单式 TextField + icon row；history / completion 分裂成两个面板。 | 现代输入能力存在，视觉与交互编排仍需统一。 |
| Command search / session nav | Command Search 覆盖 terminal inputs、saved commands、workflows、agent history；Session Navigation 能搜 prompt / command / status。 | Command history 只覆盖 saved commands + 当前 tab history；Workspace Search 只搜当前 active window 的 pane。 | 搜索入口和数据源范围明显不足，需要统一 palette。 |
| Split panes | pane header 可拖拽、关闭、focus，active pane 有角标；pane 可拖到 tab bar。 | 可 split / close / focus pane，但主要从 header 图标操作，pane 级可视控制弱。 | 基础功能达标，pane 视觉和直接操作未对齐。 |
| 验证 | Warp 有 integration_testing 的 window、pane、workspace、launch_configs、terminal 等模块。 | Ianvs 有 widget + real shell smoke，但没有截图/golden 和桌面 E2E harness。 | 后续 UI 对齐必须补截图工件和高层 E2E，否则无法判断“接近对齐”。 |

## 整改待办

### P0：视觉基准与截图验收

- [ ] `WLA-001` 建立截图验收目录，只保存 Ianvs 自己的截图工件，不复制 Warp 图片；Warp 侧以文档 URL、图片文件名和元素拆解作为引用。
  - 建议目录：`docs/design_snapshots/warp_alignment/`
  - Ianvs 截图尺寸：`1440x900` 主窗口、`1280x800` 较窄窗口、`960x700` modal 压力场景。
  - 对比维度：布局层级、主 CTA 位置、菜单 / sidecar 关系、信息密度、成功反馈、block 是否在 terminal 内容中可感知。
- [ ] `WLA-002` 为 `Launch Config`、block rail / panel、command search、workspace search、split pane 各生成一张当前 Ianvs 截图，并在文档中标注与 Warp 截图的差异。
- [ ] `WLA-003` 增加可重复的 screenshot / golden gate。短期可用 widget screenshot；中期并入 M7E 桌面 E2E harness。

### P1：Launch Config / Tab Config 保存流

- [ ] `WLA-010` 把 `_LaunchConfigPanel` 从 path-first 改为 name-first。
  - 默认路径由文件名生成：`~/Library/Application Support/Ianvs/ianvs-terminal/launch_configs/<name>.json`。
  - 高级 path 输入可折叠，不应是第一视觉焦点。
  - 主标题和 primary CTA 聚焦“保存当前 app / tab config”，不是“编辑 JSON path”。
- [ ] `WLA-011` 增加保存成功态。
  - 保存后不直接关闭 dialog，显示保存文件名、路径、`Open config` / `Copy path` / `Done`。
  - 对齐 Warp `LaunchConfigSaveModal` 的 `NotSaved -> Success -> OpenFile` 状态节奏。
- [ ] `WLA-012` 增加 saved config 发现入口。
  - Header 的 `Launch Config` 按钮保留，但 `+` / New tab 入口要能列出已保存配置。
  - saved config hover / select 时显示 sidecar：摘要、`Apply`、`Edit file`、`Remove`、`Make default`。
  - 这是对齐 Warp `saved-tab-config-menu.png` 的核心。
- [ ] `WLA-013` 增加 tab / window context action。
  - Tab 或 Window strip 上提供 `Save as config`，不要求复制 Warp 文案。
  - 保存当前 tab 时走 tab-scoped schema；保存全 app 时走 app-level schema。
- [ ] `WLA-014` 补充 visual acceptance：新保存流截图与 Warp `Tab Configs` 截图在入口层级、sidecar、CTA 和成功反馈上达到约 `80%` 相似。

### P1：App Chrome 与 Pane 直接操作

- [ ] `WLA-020` 压缩 `_Header`。
  - 当前 `110px` 两行工具栏应降为更轻的 top chrome：产品名 / active context / window+tab strip / primary add menu。
  - 低频动作移入 overflow 或 palette，避免 Copy / Paste / Restart / Split / Session Context / Launch Config 全部平铺。
- [ ] `WLA-021` 把 `New Window`、`New Tab`、`Launch Config` 合并成更接近 Warp 的 add menu。
  - 单一 `+` 入口承载 New Tab、New Window、New SSH、saved configs、Save current tab/app。
  - 保留 macOS menu parity，但日常视觉入口不应变成一排工具按钮。
- [ ] `WLA-022` 为 pane 增加本地 header / active marker。
  - 每个 pane 显示 compact session label、cwd / target、close / split / overflow。
  - active pane 用角标、边框或 header accent 标记；不要只靠外部 header 状态。
- [ ] `WLA-023` 设计 pane drag/drop 的后续入口。
  - 先做 header hit area 和 hover affordance，再决定是否实现完整拖拽到 tab bar。

### P1：Terminal-native Block 呈现

- [ ] `WLA-030` 把 block rail 从 viewport overlay 改为不遮挡 terminal 内容的表现。
  - 当前 `_InlineBlockRail` `Positioned(top: 12, left: 18, right: 18)` 会覆盖 terminal 内容；短期应为 terminal 内容预留 padding 或改成 sticky header。
- [ ] `WLA-031` 增加 terminal 内 block divider / left status rail。
  - 每个完成 block 至少有边界、状态颜色、command preview。
  - 失败 / interrupted block 要比普通 succeeded block 有更明显的视觉区分。
- [ ] `WLA-032` 把 block 操作靠近 block 本体。
  - hover / context menu 提供 copy command、copy output、copy all、reinput、bookmark placeholder。
  - Header 的 `_BlockToolbar` 可以保留为辅助，但不应是唯一操作入口。
- [ ] `WLA-033` 补 sticky command header。
  - 滚动长输出时，当前 block command 应在 viewport 顶部 sticky 显示，点击可回到 block 起点。
- [ ] `WLA-034` 评估 flutterm 渲染扩展点。
  - 如果需要按 scrollback row range 绘制 divider / background / sticky header，先在 `FLUTTERM_FEEDBACK.md` 增补明确上游需求，不在产品层做脆弱 frame diff。

### P2：Input Editor 与 Inline Menu

- [ ] `WLA-040` 统一 history / completion / command search 的呈现位置。
  - `_CommandHistoryPanel` 和 `_CompletionPanel` 应共享一个 inline menu shell：搜索输入、结果列表、来源 badge、详情区。
  - 菜单位置跟随 input editor，可在 input 上方或下方，不要继续堆多个全宽底部 panel。
- [ ] `WLA-041` 把 `_ModernInputBar` 从表单视觉改为 editor 视觉。
  - 保留多行和软换行能力，但减少输入框边框厚重感。
  - Submit / History / Save / Raw 放进更紧凑的 trailing toolbar 或 overflow。
- [ ] `WLA-042` 补 editor 操作覆盖。
  - 按 Warp 文档补齐至少：`Ctrl-U` 清行、`Cmd-A` 全选 buffer、`Opt-Backspace` 删除词、`Ctrl-R` 打开统一 command search。
  - Raw 模式不受 editor 快捷键误伤。

### P2：统一 Command / Session Palette

- [ ] `WLA-050` 把 command history、saved commands、workspace search 合并为一个 palette shell。
  - 来源至少包括：saved commands、当前 window 历史、所有 Ianvs windows 的 pane/session、recent cwd / target context。
  - 后续预留 workflow-like command schema，但不引入 Warp AI / cloud 对象。
- [ ] `WLA-051` 扩展 `WorkspaceSearchController` 到 `TerminalWindowsController`。
  - 结果必须覆盖所有 app windows，而不是只搜 active window 的 `TerminalTabsController`。
  - 结果字段加入 window label、tab title、pane cwd、target host、last command、status。
- [ ] `WLA-052` 增加 filter prefix。
  - 至少支持 `history:`、`saved:`、`session:`、`ssh:`。
  - UI 上显示 active filter chip，输入删除后恢复 all。
- [ ] `WLA-053` 结果详情区对齐 Warp rich history / session navigation。
  - command 结果显示状态、cwd、完成时间、输出首行。
  - session 结果显示 prompt / cwd / target / running or last command / recency。

### P2：Saved Config Schema 与设置 breadth

- [ ] `WLA-060` 拆分 app-level launch config 和 tab-level config 的用户概念。
  - app export：windows / tabs / panes / metadata。
  - tab config：单 tab pane tree / cwd / commands / shell / title / optional params。
- [ ] `WLA-061` 为 saved command 升级 schema。
  - 从纯字符串 list 演进到 `{title, command, tags, cwdHint, targetKind, createdAt}`，兼容旧数据。
- [ ] `WLA-062` 增加 session settings breadth。
  - 至少预留 new session shell、startup shell、working directory policy by split/tab/window。

### P3：桌面端 E2E

- [ ] `WLA-070` 建立 M7E 桌面端 E2E harness。
  - 统一封装 window、tab、pane、launch config、session context、SSH、workspace search 动作和断言。
- [ ] `WLA-071` 首批 E2E 场景。
  - 新建两个 window，切换 active window。
  - 保存 app config，销毁状态，重新 apply，恢复 active window / active pane。
  - 保存成功态截图。
  - split pane、workspace palette、SSH command session restart。
- [ ] `WLA-072` 把截图验收纳入 E2E 输出。
  - 每个关键 UI 输出当前截图路径和失败时的差异说明。

## 当前优先级建议

1. 先做 `WLA-001 -> WLA-003`。没有 Ianvs 自己的截图工件，就无法严肃判断“接近对齐”。
2. 再做 `WLA-010 -> WLA-014`。Launch / Tab Config 是用户当前明确要求截图对齐的最强信号，且当前 Ianvs 已有 app-level 基础，只差保存流和菜单层级。
3. 同步做 `WLA-020 -> WLA-023`。如果顶部 chrome 仍是 110px 工具栏，其他 UI 即使补齐也会显得不像现代 terminal。
4. 接着做 `WLA-030 -> WLA-034`。Blocks 是 Warp 体验的核心，必须从 overlay / side panel 提升到 terminal-native 感知。
5. 最后以 `WLA-050 -> WLA-053` 和 `WLA-070 -> WLA-072` 收口搜索和验证体系。

## 不做事项

- 不复制 Warp 品牌、素材、图标、云服务、AI objects 或私有实现。
- 不把 Ianvs Terminal 说成 Warp-compatible 或 Warp clone。
- 不为了视觉对齐绕过 `flutterm_terminal` 重新实现 terminal runtime。
- 不把 mobile、本地 shell 以外的平台承诺提前写进首版验收。
