# Warp 布局与设计对齐待办

日期：`2026-05-04`

## 目标

把 Warp 文档截图中的应用元素布局、对应源码语义，以及 Ianvs Terminal 当前布局放在同一张整改清单里。后续实现不复制 Warp 品牌、素材、私有云能力或文案；但命名布局项必须通过归一化像素级 contract，关键 rect 的位置和尺寸相对 Warp 本机样本偏差不超过 `5%`。目标是让 Ianvs Terminal 的信息层级、交互入口、主要 CTA、block 感知和搜索体验接近 Warp 的现代终端基线，不能停留在“功能都有但 UI 很像后台工具表单”的状态。

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

### Warp 本机交互截图

本轮截图由用户在本机 Warp 手动完成，保存于 `docs/design_snapshots/warp_alignment/warp_interaction/`。Computer Use 对 `dev.warp.Warp-Stable` 被安全策略拒绝，所以这里不把截图采集记为自动化验证。

- `01_terminal_blocks.png`：terminal 内容区内的 command/output block、prompt/cwd/git 状态和底部 input editor 同屏。
- `02_block_not_hover_click_actions.png`：block 选中/hover 后右侧出现贴近 block 本体的 inline actions。
- `03_command_search.png`：统一 search palette 展示 workflows、prompts、notebooks、environment variables、files、sessions、launch configurations、conversations 等类别。
- `04_completion_input.png`：输入区能识别 shell command，并显示自动检测与快捷键覆盖提示。
- `05_split_pane.png`：split 后每个 pane 都有独立 header、close/overflow、cwd/git/context chips 和输入区。
- `06_tab_or_launch_config_entry.png`：顶部 `+` 菜单集中 New Terminal Tab、Agent Tab、Cloud Agent Tab、shell selector 和 Launch Configs 入口。

### Warp 源码

基线：`../../warp`，`warpdotdev/Warp@23eedf4`，浅克隆 + sparse checkout。

- `../../warp/app/src/launch_configs/launch_config.rs`
  - `LaunchConfig::from_snapshot(name, app_state)` 从 app state 保存 `active_window_index + windows[]`。
  - `WindowTemplate / TabTemplate / PaneTemplateType` 保留 active tab、pane tree、cwd、commands、pane mode 和 shell override。
- `../../warp/app/src/launch_configs/save_modal.rs`
  - `LaunchConfigSaveModal` 是居中 modal：标题、关闭、说明、文档链接、单行文件名编辑器、primary save button、成功后 `Open File`。
- `../../warp/app/src/terminal/model/block.rs`
  - `Block` 持有 prompt grid、command/output grid、cwd、session、exit code、timestamps、banner、prompt snapshot、filter query 等。
- `../../warp/app/src/terminal/model/blocks.rs`
  - `BlockList` 是 terminal scroll / render 模型的一部分，支持 restored separator、inline banner、subshell separator、rich content。
- `../../warp/app/src/terminal/input/terminal.rs`
  - input editor 支持 pinned bottom/top/waterfall，并把 slash commands、prompts、conversation、skills、inline history、repos 等 inline menu 编排在输入区上下。
- `../../warp/app/src/search/command_search/view.rs`
  - `CommandSearchView` 默认搜索 `history, workflows, and more`，支持 resizable panel 和统一结果渲染。
- `../../warp/app/src/search/command_palette/navigation/search.rs`
  - session navigation 以 prompt、last/running command、hint text 建 fuzzy search 文本。
- `../../warp/app/src/pane_group/pane/view/header/mod.rs`
  - pane header 承担 focus、close、overflow menu、drag/drop 和 pane move 行为。

### Ianvs 当前源码状态

- `lib/src/terminal_windows.dart`：已有产品层 `TerminalWindowsController`，支持 in-app window collection、active window、app-level launch config / restore。
- `lib/src/launch_config.dart`：已有 `version = 2`、`activeWindowIndex`、`windows[]`，并保留单窗口 legacy `tabs` 字段兼容。
- `lib/main.dart`
  - `_Header`：固定 `76px` 两行 header，包含产品名、session/status badge、window strip、tab strip、add menu、overflow menu 和 block toolbar。
  - `_LaunchConfigPanel`：大尺寸 dialog，已改为 name-first 保存流，显示 app snapshot、统计卡片、路径预览、Advanced path、pane startup command 列、Save / Apply CTA 和保存成功态。
  - `_InlineBlockRail` + `_BlockHistoryPanel`：active block rail 已按 viewport 高度下沉，并为 viewport 预留 padding，右侧 block history side panel 默认收起。
  - `_InputContextStrip` + `_ModernInputBar`：底部 input-adjacent context chips 与 editor 输入区同屏，输入区最多 4 行，右侧 Submit / History / Save / Raw 图标；split 中非 active pane 保留不可输入的底部 editor preview。
  - `_CommandPalettePanel`：顶部 280px 统一 palette，合并 workflow-like saved commands、history、session 和 launch config 搜索，并复用旧 command history / workspace search key 以兼容测试。
- `lib/src/command_palette.dart`：已有跨 app windows 的 workflow / history / session / launch config palette controller，支持 `workflow:`、`saved:`、`history:`、`session:`、`ssh:`、`launch:` filter prefix。
- `lib/src/saved_commands.dart`：saved command 已从纯字符串升级为 `SavedCommandEntry` schema，并兼容旧 `commands[]`。
- `lib/src/workspace_search.dart`：只搜索当前 active window 的 tab / pane，不覆盖全 app window collection。
- `test/widget_test.dart`：已覆盖 app-level launch config、多窗口恢复、menu entries、block panel、command palette。
- `test/launch_config_golden_test.dart`、`test/warp_alignment_golden_test.dart` 和 `docs/design_snapshots/warp_alignment/`：已覆盖 Launch Config compose / success、default terminal、block actions、completion input、block + command palette、split pane、split pane + session palette、saved config sidecar 九张 golden 截图，并在 `test/warp_alignment_golden_test.dart` 里对 default block / input、block actions hover、completion input、command palette、session palette、add menu、split pane、saved config sidecar 建立 `5%` 归一化像素 contract。

## 差异总览

| 区域 | Warp 布局 / 设计 | Ianvs 当前状态 | 对齐结论 |
| --- | --- | --- | --- |
| App chrome / tabs | 顶部 chrome 更轻，tab / `+` 菜单和右键菜单承载主要配置入口；pane 有自己的 header 和 active marker。 | Header 已从 `110px` 压到 `76px`，创建 / 配置入口收进 add menu，搜索 / split / copy / paste / restart / session context / settings 等收进 overflow；window strip 是 in-app 横条；pane 已有 local header / active marker / drag handle。 | P1 chrome 入口已收口，后续主要转向 terminal-native blocks 和 input editor。 |
| Tab / Launch config | 文档截图强调 `+` 菜单、context menu、saved config sidecar；legacy 源码 modal 是 name-first、save-success-open-file 流程。 | 已有 app-level export、name-first compose、Advanced path、摘要面板、成功态、saved config discovery、sidecar、tab/window strip save action、add menu 入口和 golden 截图。 | M7A 已落地；M7B 的保存流、发现入口、sidecar、context action 和 add menu 收口已处理。 |
| Blocks | block 是 terminal 内容模型本身，带 divider、状态、selection、sticky header、上下文操作。 | 有 inline rail、viewport reserved padding、左侧 status rail 和右侧 panel，但 block 仍不是 scrollback 内分组。 | 视觉感知有所提升，但还不像 Warp 的 terminal-native blocks。 |
| Input editor | 输入区像编辑器，支持软换行、inline menu、pinned modes、command search 入口。 | `_ModernInputBar` 已改为 editor 容器 + trailing toolbar；输入草稿存在时显示 `terminal-input-command-detection-strip`，空输入保留 context chips；command/session palette、completion 和 legacy history 共用 input 附近的 inline shell；补齐 `Ctrl-U` / `Cmd-A` / `Opt-Backspace` / `Ctrl-R`。 | P1 输入区和 inline menu 已收口，后续主要是 workflow schema 和高级编辑体验。 |
| Command search / session nav | Command Search 覆盖 terminal inputs、saved commands、workflows、agent history；Session Navigation 能搜 prompt / command / status。 | 已有统一 `CommandPaletteController`，覆盖 workflow-like saved commands / history / all windows session / saved launch configs，支持 `workflow:`、`saved:`、`history:`、`session:`、`ssh:`、`launch:` filter prefix、rich detail、source rail 计数筛选和 input-adjacent inline shell；source rail 与 results list 已有 5% rect contract。 | Warp `workflows` / `launch configurations` 的 Ianvs 信息架构和可见 source 入口已落地；后续重点是 session prompt snapshot fidelity。 |
| Split panes | pane header 可拖拽、关闭、focus，active pane 有角标；pane 可拖到 tab bar。 | 已有 pane local header、active marker、drag handle、pane-local context chips、每个 pane 的底部输入区、pane overflow menu、pane 级 split / close / focus，并支持从 pane menu 把当前 pane 移到新 tab。 | P1 视觉承载点、pane-local menu、每 pane 输入区和 move-to-tab 行为已到位；完整 drag gesture 可作为后续增强。 |
| 验证 | Warp 有 integration_testing 的 window、pane、workspace、launch_configs、terminal 等模块。 | Ianvs 已有 widget、real shell smoke、Launch Config / Warp alignment golden，以及 `test/demo_terminal_session_test.dart` 桌面端 E2E harness。 | M7E 高层入口已覆盖多窗口、app export / apply、workspace search、session restore、SSH restart 和 screenshot gates。 |

## 当前处理状态

| item | 状态 | 证据 | 仍缺 |
| --- | --- | --- | --- |
| `WLA-001` | `done` | `docs/design_snapshots/warp_alignment/README.md`、Launch Config 两张 Ianvs golden | 其他 UI 面的截图说明放在 `WLA-002` 继续补 |
| `WLA-002` | `done` | `default_terminal_layout.png`、`block_actions_layout.png`、`completion_input_layout.png`、`launch_config_compose.png`、`launch_config_success.png`、`blocks_command_palette.png`、`split_pane_layout.png`、`split_session_palette.png`、`saved_config_sidecar.png` | 后续新增 UI 面时继续补截图 |
| `WLA-003` | `done` | `test/launch_config_golden_test.dart`、`test/warp_alignment_golden_test.dart` | M7E 组合命令已归 `WLA-072` |
| `WLA-004` | `done` | `test/warp_alignment_golden_test.dart` 新增 default terminal layout screenshot gate；`docs/design_snapshots/warp_alignment/default_terminal_layout.png` 对齐 Warp `01_terminal_blocks.png`；默认态 block history panel 不再常驻挤占 terminal 宽度 | 原生 scrollback block 仍归 `WLA-034` |
| `WLA-010` | `done` | `_LaunchConfigPanel` 已有 `terminal-launch-config-name-field` 和 name -> path sync | 无 |
| `WLA-011` | `done` | `_LaunchConfigPanel` 已有 success phase、`Copy path`、`Apply saved app`、`Done` | 无 |
| `WLA-012` | `done` | `terminal-add-menu-button` 的 saved configs action 打开 `_SavedLaunchConfigsPanel`，列出已保存配置并提供 sidecar 操作 | 无 |
| `WLA-013` | `done` | Tab strip 已有 `terminal-tab-save-config-*`，Window strip 已有 `terminal-window-save-app-config-*`；`scope: tab/app` schema 和 widget test 覆盖 | 无 |
| `WLA-014` | `done` | `saved_config_sidecar.png`、`launch_config_compose.png`、`launch_config_success.png` 覆盖入口、sidecar、CTA 和成功反馈 | 无 |
| `WLA-020` | `done` | `_Header` 高度已从 `110px` 压到 `76px`；低频动作迁入 `terminal-header-overflow-menu-button`；widget test 断言旧平铺 key 不在初始 header | 后续 block toolbar 贴近 block 本体归 `WLA-032` |
| `WLA-021` | `done` | `terminal-add-menu-button` 承载 New Tab、New Window、New SSH、saved configs、Save current tab/app、Launch Config；旧创建 / config 平铺按钮已移除 | 无 |
| `WLA-022` | `done` | 每个 pane 已有 `terminal-pane-header-*`、`terminal-pane-active-marker-*`、pane 级 split / close actions | drag/drop 继续归 `WLA-023` |
| `WLA-023` | `done` | pane header 已有 `terminal-pane-drag-handle-*` 和 move cursor，作为后续 drag/drop 承载点 | 完整拖拽到 tab bar 可作为后续增强 |
| `WLA-024` | `done` | pane header 新增 `terminal-pane-context-chips-*` / `terminal-pane-context-chip-*-*` 和 `terminal-pane-menu-*`；menu 覆盖 focus / split / session context / copy / paste / restart / close | 完整拖拽到 tab bar 仍是后续增强 |
| `WLA-025` | `done` | pane menu 新增 `terminal-pane-menu-move-to-new-tab-*`；`TerminalTabsController.moveActivePaneToNewTab()` 在不重启 session 的情况下把 split pane 提升为新 tab | 完整 drag gesture 仍是后续增强 |
| `WLA-030` | `done` | block rail 显示时按 viewport 高度下沉，并动态提高 `TerminalViewport.contentPadding.top`；无 block 时保持 `14`；`test/widget_test.dart` 覆盖 | 原生 scrollback 分组继续归 `WLA-031 -> WLA-034` |
| `WLA-031` | `done` | `terminal-block-status-rail` 在 viewport 左侧展示每个 block 的状态色、状态文案和 command preview；viewport left padding 提高到 `132` | 原生 row range divider 继续归 `WLA-034` |
| `WLA-032` | `done` | active block card 有 hover/pressed interaction layer 和 `terminal-inline-block-actions-button`，菜单提供 copy command / output / all、reinput 和 bookmark placeholder；`block_actions_layout.png` 与行为测试覆盖 inline actions | bookmark 仍是 placeholder |
| `WLA-033` | `done` | `terminal-sticky-block-command-header` 固定在 active block rail，显示当前 command preview，点击会滚回 active block 起点 | 真正随 scrollback row range sticky 继续归 `WLA-034` |
| `WLA-034` | `done` | `FLUTTERM_FEEDBACK.md` 的 `FT-008` 已记录 row range divider / background / status gutter / sticky header 扩展点需求 | 等用户明确要求时再进入 flutterm 工作树 |
| `WLA-040` | `done` | `_InlineMenuShell` 统一 command palette、completion、legacy history 的 inline menu 外壳；command/session palette 从 header 下移到 active pane input editor 上方；widget test 覆盖 command/completion shell key | 无 |
| `WLA-041` | `done` | `_ModernInputBar` 改为 `terminal-modern-input-editor` 轻边框 editor，Submit / History / Save / Raw 收进 `terminal-modern-input-toolbar`；widget test 覆盖输入框不再使用 outline border | 无 |
| `WLA-042` | `done` | `applyModernInputClearLine`、`applyModernInputSelectBuffer`、`applyModernInputDeletePreviousWord` 和 `_ModernInputBar` 快捷键处理覆盖 `Ctrl-U`、`Cmd-A`、`Opt-Backspace`、`Ctrl-R`；raw 模式测试覆盖不误伤 | 无 |
| `WLA-043` | `done` | completion panel rows 保留 source badge，并新增 selected semantics、active left rail 与 `terminal-completion-active-badge-*`；widget test 覆盖 source label 和选择态切换 | 无 |
| `WLA-044` | `done` | `_InputContextStrip` 在底部 editor 上方显示 `terminal-input-context-chip-*`，覆盖 target / cwd / status / last-command；widget + default golden 覆盖 | git branch prompt fidelity 后续依赖更完整 shell metadata |
| `WLA-050` | `done` | `lib/src/command_palette.dart` + `_CommandPalettePanel` | completion shell 已按 `WLA-040` 收口 |
| `WLA-051` | `done` | palette 直接基于 `TerminalWindowsController` 构建所有 window / tab / pane session 结果 | 旧 `WorkspaceSearchController` 可保留为 legacy 或后续删除 |
| `WLA-052` | `done` | `workflow:`、`saved:`、`history:`、`session:`、`ssh:`、`launch:` prefix filter | 无 |
| `WLA-053` | `done` | palette rows 已显示 command/session detail label：状态、cwd、target、last command、output preview、completed / recent time 和 prompt context；`test/command_palette_test.dart` 与 widget test 覆盖 | 更深 prompt snapshot fidelity 后续再做 |
| `WLA-054` | `done` | command palette 新增 `CommandPaletteEntrySource.launchConfig`、`launch:` / `config:` filter、saved config row detail 和 Enter apply 行为；unit + widget test 覆盖 | 无 |
| `WLA-055` | `done` | saved commands 在 palette 中以 `Workflow` source 呈现，同时保留 `saved:` alias、保存 / 删除行为和旧 `SavedCommandEntry` 持久化 schema | 更深 workflow 编辑 UI 后续再做 |
| `WLA-056` | `done` | command palette header 新增 `terminal-command-palette-source-rail`，用 source chip 显示 Workflow / History / Sessions / SSH / Launch 的可用数量并支持点击筛选 | Files / prompts / notebooks 等非 Ianvs Terminal 本地能力不伪装为已支持 |
| `WLA-060` | `done` | Launch Config 保存面板新增 `terminal-launch-config-scope-explainer`，Saved Config row / sidecar 显示 `App config` / `Tab config` scope copy；widget test 覆盖 app/tab 概念文案 | 无 |
| `WLA-061` | `done` | `SavedCommandEntry` schema: `title`、`tags`、`cwdHint`、`targetKind`、`createdAt`；旧 `commands[]` 迁移测试覆盖 | 编辑 UI 仍待后续 |
| `WLA-062` | `done` | Settings 面板新增 `settings-session-defaults-section`，预留 new session shell、startup shell、split/tab/window cwd policy 控件；widget test 覆盖 key | 行为接入可作为后续增强 |
| `WLA-070` | `done` | `test/demo_terminal_session_test.dart` 的 `_DesktopDemoHarness` 封装 window、tab、pane、launch config、session context、SSH、workspace search、command search 常用动作 | 无 |
| `WLA-071` | `done` | demo harness 场景覆盖 app export/apply、多窗口 active window、workspace palette、split pane restore、SSH restart、command palette reinput | 无 |
| `WLA-072` | `done` | M7E 组合命令同时运行 `test/demo_terminal_session_test.dart`、`test/launch_config_golden_test.dart`、`test/warp_alignment_golden_test.dart`；截图路径固定在 `docs/design_snapshots/warp_alignment/`，失败由 Flutter golden diff 输出 | 无 |
| `WLA-080` | `done` | `test/warp_alignment_golden_test.dart` 的 default display 1:1、default block / input、block actions hover、command palette、session palette、add menu、split pane、saved config sidecar pixel contract 仍有效；default display 读取 `analysis/default_display_view_annotation.json`，completion、command/session palette 与 saved config sidecar 的目标比例 / rect 已直接读取 `analysis/reannotated/alignment_regions.json` | 无 |
| `WLA-081` | `done` | `terminal-pane-surface-1` 作为 active terminal pane local 坐标；`completion input matches the pane-local pixel contract` 覆盖 block band、command/output body、actions、detection strip 和 input editor，并以 reannotated 标注的 pane-local ratio 为准；`completion_input_layout.png` 已更新 | 无 |
| `WLA-082` | `done` | `analysis/reannotated/` 重新生成 10 张 layout comparison SVG；`alignment_regions.json` 记录全部 rect / normalized delta；`alignment_iteration_report.md` 记录 10 次重复生成 fingerprint 完全一致，30 个可比 region 无 `review` 状态 | 无 |

## 已完成项补充复核

日期：`2026-05-04`

复核范围：`WLA-001 -> WLA-003`、`WLA-010 -> WLA-014`、`WLA-050 -> WLA-052`、`WLA-061`。

复核方法：

- 对照本文已勾选条目的完成条件，逐项检查实现入口、schema、截图工件和测试文件。
- 重点复核此前容易误读的三处：`WLA-012` 是否真的有 saved config discovery + sidecar、`WLA-014` 是否有 dedicated sidecar golden、`WLA-061` 是否覆盖旧 `commands[]` 数据兼容。

复核结论：

| item | 复核状态 | 证据 | 结论 / 后续 |
| --- | --- | --- | --- |
| `WLA-001` | `confirmed` | `docs/design_snapshots/warp_alignment/` 只保存 Ianvs 截图；README 用 Warp URL 和截图文件名做引用 | 维持 done |
| `WLA-002` | `confirmed` | `default_terminal_layout.png`、`block_actions_layout.png`、`completion_input_layout.png`、`launch_config_compose.png`、`launch_config_success.png`、`blocks_command_palette.png`、`split_pane_layout.png`、`split_session_palette.png`、`saved_config_sidecar.png` | 维持 done；后续新增 UI 面继续补截图 |
| `WLA-003` | `confirmed` | `test/launch_config_golden_test.dart`、`test/warp_alignment_golden_test.dart` | 维持 done；M7E screenshot gate 已归 `WLA-072` |
| `WLA-010` | `confirmed` | `terminal-launch-config-name-field`、建议 path 由 name 同步、Advanced path 折叠 | 维持 done |
| `WLA-011` | `confirmed` | 保存后进入 success state，动作是 `Copy path`、`Apply saved app`、`Done` | 维持 done；不再记录为 `Open config` |
| `WLA-012` | `confirmed-with-scope` | `terminal-add-menu-button` 里的 saved configs action 打开 `_SavedLaunchConfigsPanel`；sidecar 有摘要、`Apply`、`Edit file`、`Remove`、`Make default` | 维持 done；发现入口已随 `WLA-021` 收敛到 add menu |
| `WLA-013` | `confirmed` | tab strip `terminal-tab-save-config-*` 保存 `scope: tab`；window strip `terminal-window-save-app-config-*` 保存 `scope: app` | 维持 done |
| `WLA-014` | `confirmed` | `saved_config_sidecar.png` 加入 golden gate，并和 compose / success 一起覆盖入口、sidecar、CTA、成功反馈 | 维持 done |
| `WLA-050` | `confirmed` | `CommandPaletteController` 合并 saved commands、history、session results | 维持 done；completion inline shell 归 `WLA-040` |
| `WLA-051` | `confirmed` | palette 直接遍历 `TerminalWindowsController.windows` 构建 all windows / tabs / panes 结果 | 维持 done |
| `WLA-052` | `confirmed` | `saved:`、`history:`、`session:`、`ssh:` prefix filter 和 active filter chip | 维持 done |
| `WLA-061` | `confirmed` | `SavedCommandEntry` metadata schema；旧 `commands[]` 迁移和 metadata roundtrip 已补单测 | 维持 done；编辑 UI 不属于本项 |

复核后调整：

- `WLA-012` 的发现入口已随 `WLA-021` 收敛到 `+` add menu，sidecar 和 store discovery 维持完成。
- `WLA-011` 的 success state 文案按当前实现记录为 `Copy path`、`Apply saved app`、`Done`，不再写 `Open config`。
- `WLA-061` 新增旧 `commands[]` 迁移和 rich entry metadata 直接测试，补齐已完成项复核证据。

### 新增已完成项补充复核

日期：`2026-05-04`

复核范围：`WLA-020 -> WLA-034`。

复核方法：

- 对照 `WLA-020 -> WLA-034` 的完成条件，检查 header / add menu / pane header / block rail / sticky header 的实现 key、测试覆盖和上游反馈记录。
- 只确认当前产品层已经完成的视觉与交互收口；真正进入 flutterm scrollback render layer 的能力继续按 `FT-008` 作为上游扩展点，不把产品层 overlay 写成 terminal-native render 完成。

复核结论：

| item | 复核状态 | 证据 | 结论 / 后续 |
| --- | --- | --- | --- |
| `WLA-020` | `confirmed` | `_Header` 高度为 `76px`；`terminal-header-overflow-menu-button` 承载低频动作；widget test 覆盖高度、overflow 菜单和旧平铺入口移除 | 维持 done |
| `WLA-021` | `confirmed` | `terminal-add-menu-button` 承载 New Tab、New Window、New SSH、Saved configs、Save current tab/app、Launch Config | 维持 done |
| `WLA-022` | `confirmed` | `terminal-pane-header-*`、`terminal-pane-active-marker-*`、pane 级 split / close actions 已渲染；widget test 覆盖 active marker 和 pane actions | 维持 done |
| `WLA-023` | `confirmed-with-scope` | `terminal-pane-drag-handle-*` 和 move cursor 已提供 header hit area / hover affordance | 维持 done；完整 drag/drop 到 tab bar 是后续增强 |
| `WLA-030` | `confirmed` | inline block rail 显示时按 viewport 高度下沉，并动态提高 `TerminalViewport.contentPadding.top`，无 block 时保持默认 padding；widget test 覆盖 | 维持 done |
| `WLA-031` | `confirmed` | `terminal-block-status-rail` 显示状态色、状态文案和 command preview；viewport left padding 提高到 `132` | 维持 done；真正 row range divider 归 `WLA-034` / `FT-008` |
| `WLA-032` | `confirmed` | active block card hover/pressed 只改变交互层；`terminal-inline-block-actions-button` 菜单提供 copy command、copy output、copy all、reinput、bookmark placeholder；`block_actions_layout.png` 和 widget test 覆盖 inline actions | 维持 done；bookmark 仍是 placeholder |
| `WLA-033` | `confirmed` | `terminal-sticky-block-command-header` 显示 active command preview，点击回到 active block 起点；widget test 覆盖 | 维持 done |
| `WLA-034` | `confirmed-with-upstream-boundary` | `FLUTTERM_FEEDBACK.md` 的 `FT-008` 已记录 row range divider、background、status gutter、sticky header 扩展点 | 维持 done；不在 Ianvs Terminal 内绕过 `flutterm_terminal` 重做 render layer |

复核后调整：

- `WLA-023` 的 done 口径限定为 drag/drop 后续入口和 hover affordance，不包含完整拖拽到 tab bar。
- `WLA-030 -> WLA-033` 的 done 口径限定为产品层 reserved padding、status rail、inline actions 和 sticky command header；真正 scrollback row range 原生绘制继续由 `WLA-034` / `FT-008` 承接。
- `WLA-034` 已完成的是“上游需求评估与记录”，不是 flutterm 实现。

### 新增已完成项补充复核（二）

日期：`2026-05-04`

复核范围：`WLA-040 -> WLA-042`、`WLA-053`、`WLA-060 -> WLA-062`、`WLA-070 -> WLA-072`。

复核方法：

- 对照新增 done 项的完成条件，检查 inline menu、现代输入 editor、palette detail、launch config scope copy、settings breadth 和 M7E harness 的实现 key、测试覆盖和文档验证命令。
- 区分“行为已接入”和“产品概念 / 控件预留 / 验证编排已完成”：`WLA-062` 当前是 settings breadth 预留控件，不是所有 policy 已驱动 session launch；`WLA-072` 当前依赖 Flutter golden diff，不另写自定义 diff renderer。

复核结论：

| item | 复核状态 | 证据 | 结论 / 后续 |
| --- | --- | --- | --- |
| `WLA-040` | `confirmed` | `_InlineMenuShell` 统一 command/session palette、completion、legacy history；`terminal-inline-menu-shell-command-palette`、`terminal-inline-menu-shell-completion` 有 widget test 覆盖 | 维持 done |
| `WLA-041` | `confirmed` | `terminal-modern-input-editor` 使用轻量 editor 容器，`terminal-modern-input-toolbar` 收敛 Submit / History / Save / Raw；widget test 断言输入框不再使用 outline border | 维持 done |
| `WLA-042` | `confirmed` | `applyModernInputClearLine`、`applyModernInputSelectBuffer`、`applyModernInputDeletePreviousWord` 和 `_ModernInputBar` 快捷键处理覆盖 `Ctrl-U`、`Cmd-A`、`Opt-Backspace`、`Ctrl-R`；raw mode 测试覆盖不误伤 | 维持 done |
| `WLA-053` | `confirmed` | `CommandPaletteEntry.commandDetailLabel` / `sessionDetailLabel` 输出 status、cwd、target、last command、output preview、completed / recent time、prompt context；`test/command_palette_test.dart` 和 widget test 覆盖 | 维持 done；workflow source 已另归 `WLA-055` |
| `WLA-060` | `confirmed` | `terminal-launch-config-scope-explainer`、saved config row / sidecar 的 `App config` / `Tab config` scope copy，widget test 覆盖 app/tab 概念文案 | 维持 done |
| `WLA-061` | `confirmed-from-prior-review` | 旧 `commands[]` 迁移、rich metadata roundtrip、去重和删除已有 `test/saved_commands_test.dart` 覆盖 | 维持 done |
| `WLA-062` | `confirmed-with-scope` | Settings 面板有 `settings-session-defaults-section`、`settings-startup-shell-field`、`settings-cwd-policy-split`、`settings-cwd-policy-tab`、`settings-cwd-policy-window` | 维持 done；policy 行为接入是后续增强 |
| `WLA-070` | `confirmed` | `test/demo_terminal_session_test.dart` 的 `_DesktopDemoHarness` 封装 app rebuild、window / tab / pane、Launch Config save / apply、Session Context、New SSH Session、Workspace Search、Command Search 和 restart | 维持 done |
| `WLA-071` | `confirmed` | demo harness 场景覆盖 app export / apply 成功反馈、多窗口 active window 恢复、workspace palette、split pane restore、SSH restart、command palette reinput | 维持 done |
| `WLA-072` | `confirmed-with-golden-boundary` | M7E 验证命令组合运行 `test/demo_terminal_session_test.dart`、`test/launch_config_golden_test.dart`、`test/warp_alignment_golden_test.dart`；截图路径固定在 `docs/design_snapshots/warp_alignment/*.png` | 维持 done；失败差异由 Flutter golden diff 输出 |

复核后调整：

- `WLA-040` 的完成口径是三个现有面板共用 inline shell 和 input-adjacent 呈现；更深的 workflow 编辑 UI 和 session prompt fidelity 继续作为后续增强。
- `WLA-062` 的完成口径是 settings breadth 与控件预留，不宣称 split / tab / window cwd policy 已完全驱动真实 session launch。
- `WLA-072` 的完成口径是把 demo harness 与 golden gates 编排成固定验证命令，截图 diff 使用 Flutter golden 机制。

### 新增已完成项补充复核（三）

日期：`2026-05-04`

复核范围：`WLA-024`、`WLA-043`、`WLA-054 -> WLA-055`。

复核方法：

- 对照 `WARP_SOURCE_REAUDIT.md` 本轮新增优先项，检查 command palette launch config / workflow source、completion 候选选择态、pane-local context chips 与 pane menu 的实现 key、行为测试和 golden 更新。
- 确认本轮仍只修改 Ianvs Terminal 产品层与文档；未进入 `/Users/luobinghui/projects/flutter/flutterm`。

复核结论：

| item | 复核状态 | 证据 | 结论 / 后续 |
| --- | --- | --- | --- |
| `WLA-024` | `confirmed` | `_PaneLocalHeader` 渲染 `terminal-pane-context-chips-*`、`terminal-pane-context-chip-*-target/cwd/status/last-command` 和 `terminal-pane-menu-*`；`test/widget_test.dart` 覆盖 menu values 和 menu-driven split / close | 维持 done；完整拖拽到 tab bar 仍后续增强 |
| `WLA-043` | `confirmed` | `_CompletionPanel` 保留 source badge，新增 selected semantics、active left rail 和 `terminal-completion-active-badge-*`；widget test 覆盖 Tab 打开、ArrowDown 切换和 Enter 接受 | 维持 done |
| `WLA-054` | `confirmed` | `CommandPaletteEntrySource.launchConfig`、`launch:` / `config:` prefix、`TerminalLaunchConfigurationStore.listSaved()` source、palette Enter apply；`test/command_palette_test.dart` 与 widget test 覆盖 | 维持 done |
| `WLA-055` | `confirmed` | saved commands 在 palette 里以 `Workflow` badge 呈现，同时 `saved:` alias、保存 history、删除 saved command 和持久化 reload 仍由 widget / unit test 覆盖 | 维持 done；workflow 编辑 UI 后续再做 |

复核后调整：

- `WLA-052` 的 prefix 口径从 `saved/history/session/ssh` 扩展为 `workflow/saved/history/session/ssh/launch`；`saved:` 作为兼容 alias 保留。
- `WLA-053` 不再把 workflow schema 标为后续未覆盖；本轮完成的是 workflow-like saved command source，后续只保留更深编辑 UI。
- `blocks_command_palette.png`、`split_session_palette.png`、`saved_config_sidecar.png` 已随 pane header/menu/context chip 视觉更新。

### 新增已完成项补充复核（四）

日期：`2026-05-04`

复核范围：`WLA-025`、`WLA-056`。

复核方法：

- 对照本轮用户要求“使用应用截图导出功能对比布局与功能特性支持”，把已经存在但不够显性的 command palette source 能力转成截图可见的 source rail。
- 对照 Warp split pane 的 pane move 语义，在 Ianvs 产品层补 pane menu 的 move-to-tab 行为；不宣称完整 drag/drop gesture 已完成。

复核结论：

| item | 复核状态 | 证据 | 结论 / 后续 |
| --- | --- | --- | --- |
| `WLA-025` | `confirmed` | `TerminalTabsController.moveActivePaneToNewTab()`、`TerminalWindowsController.moveActivePaneToNewTab()`、`terminal-pane-menu-move-to-new-tab-*`；controller + widget test 覆盖不重启 session 的 move 行为 | 维持 done；完整 drag gesture 后续再做 |
| `WLA-056` | `confirmed` | `_PaletteSourceRail` / `_PaletteSourceChip`、`CommandPaletteController.countForFilter()` / `updateFilter()`；command palette unit test、widget test 和 `warp_alignment_golden_test.dart` 截图 seed 覆盖 | 维持 done；不把 Files / prompts / notebooks 等非当前产品能力显示为已支持 |

### 新增已完成项补充复核（五）

日期：`2026-05-04`

复核范围：`WLA-004`、`WLA-044`。

复核方法：

- 对照用户点名的 `[Image #1] 默认布局`，把 Warp 本机 `01_terminal_blocks.png` 拆成默认终端画面验收：不打开 palette / modal，terminal 内容、block 导航、底部 editor 和 context chips 同屏。
- 检查 screenshot harness 是否真的导出 default layout，而不是复用 command palette / saved config / split pane 的代理截图。

复核结论：

| item | 复核状态 | 证据 | 结论 / 后续 |
| --- | --- | --- | --- |
| `WLA-004` | `confirmed` | `test/warp_alignment_golden_test.dart` 新增 `default terminal layout stays visually stable`，输出 `docs/design_snapshots/warp_alignment/default_terminal_layout.png`；默认 block history panel 已改为按需打开 | 维持 done；该截图专门覆盖默认布局 |
| `WLA-044` | `confirmed` | `_InputContextStrip`、`terminal-input-context-chip-target/cwd/status/last-command`；`test/widget_test.dart` 和 default golden 覆盖 | 维持 done；git branch / prompt fidelity 后续依赖 shell metadata |

## 整改待办

### P0：视觉基准与截图验收

- [x] `WLA-001` 建立截图验收目录，只保存 Ianvs 自己的截图工件，不复制 Warp 图片；Warp 侧以文档 URL、图片文件名和元素拆解作为引用。
  - 建议目录：`docs/design_snapshots/warp_alignment/`
  - Ianvs 截图尺寸：`1440x900` 主窗口、`1280x800` 较窄窗口、`960x700` modal 压力场景。
  - 对比维度：布局层级、主 CTA 位置、菜单 / sidecar 关系、信息密度、成功反馈、block 是否在 terminal 内容中可感知。
- [x] `WLA-002` 为 `Launch Config`、block rail / panel、command search、workspace search、split pane 各生成一张当前 Ianvs 截图，并在文档中标注与 Warp 截图的差异。
  - `launch_config_compose.png`、`launch_config_success.png` 覆盖 Launch Config。
  - `block_actions_layout.png` 覆盖 block hover / selected interaction layer 和贴近 block 本体的 actions。
  - `blocks_command_palette.png` 覆盖 block rail / panel 和 command palette。
  - `split_session_palette.png` 覆盖 split pane 和 workspace/session palette。
  - `saved_config_sidecar.png` 覆盖 saved config discovery 和 sidecar。
- [x] `WLA-003` 增加可重复的 screenshot / golden gate。短期可用 widget screenshot；中期并入 M7E 桌面 E2E harness。
  - `test/launch_config_golden_test.dart` 覆盖 Launch Config compose / success。
  - `test/warp_alignment_golden_test.dart` 覆盖 block / command palette / split pane / session palette / saved config sidecar。
- [x] `WLA-004` 增加默认终端布局截图 gate。
  - 对齐 Warp 本机 `01_terminal_blocks.png`，截图不应依赖打开 command palette、saved config panel 或 launch config modal。
  - 当前实现：`default_terminal_layout.png` 只启动默认 terminal + seed blocks，固定 terminal 内容区、block rail / status rail、底部 input context strip 和 editor；block history panel 默认收起，避免右侧常驻面板挤占 terminal。
  - 验收：`test/warp_alignment_golden_test.dart` 的 `default terminal layout stays visually stable`。
- [x] `WLA-080` 增加 `5%` 像素级布局 contract。
  - `test/warp_alignment_golden_test.dart` 读取关键 widget 的全局像素 rect，并以 Warp 本机样本拆出的归一化位置 / 尺寸作为目标，断言偏差 `<= 0.05`。
  - 当前覆盖：默认布局 header / block rail / inline actions / block output band / input context / input / 默认无右侧 panel、block actions hover、completion input 的 pane-local block band / command-output body / actions / detection strip / input editor、command palette 居中浮层 left / top / width / height / source rail / results top、session palette source rail / results top、add menu、split pane divider / pane header / active marker / 两侧 context + input、saved config dialog / sidecar。
  - `completion_input_layout.png` 的旧关键 rect 曾按 `99%` 要求收紧为偏差 `<= 0.01`；但 `2026-05-05` 重新审图后确认该 contract 使用整图比例，混入了 Warp sidebar / app chrome 的全局偏移；当前已改为 `terminal-pane-surface-1` 的 pane-local 坐标。
  - 当前截图拆分：`block_actions_layout.png` 以 Warp `02_block_not_hover_click_actions.png` 固化 block actions 交互层；`completion_input_layout.png` 以 Warp `04_completion_input.png` 固化 block-first input 状态，并使用 `analysis/completion_input_alignment_review.md` 定义的 pane-local contract；`split_pane_layout.png` 补齐独立布局面；`blocks_command_palette.png`、`split_session_palette.png` 继续覆盖浮层组合状态。
  - Launch Config compose / success：`test/launch_config_golden_test.dart` 覆盖 panel、name、scope explainer、path preview、advanced path、success state、success path 和 success action row 的 5% rect contract。
  - 后续增强：completion 候选面板没有独立 Warp 本机截图，继续由 widget 行为测试覆盖；若用户补候选面板基准图，再追加 dedicated rect contract。
- [x] `WLA-082` 全量布局对比图重新标注并重复 10 次对齐校验。
  - 覆盖 10 张 Ianvs 布局对比图：default、block actions、completion input、blocks command palette、split pane、split session palette、add menu、saved config sidecar、launch config compose、launch config success。
  - 本地 Warp 样本存在时生成左右对照 SVG；Launch Config compose / success 没有本地 Warp modal raster，按 Warp `Tab Configs` 文档和 `launch_configs/save_modal.rs` 语义生成 Ianvs 标注说明。
  - 当前实现：`docs/design_snapshots/warp_alignment/analysis/reannotate_alignment.py --iterations 10` 生成 `analysis/reannotated/*_comparison.svg`、`alignment_regions.json` 和 `alignment_iteration_report.md`。
  - 验收：10 次 fingerprint 一致；`alignment_regions.json` 的 `comparison_count` 为 `10`；30 个可比 region 的状态均为 `pass`，没有 `review`。

### P1：Launch Config / Tab Config 保存流

- [x] `WLA-010` 把 `_LaunchConfigPanel` 从 path-first 改为 name-first。
  - 默认路径由文件名生成：`~/Library/Application Support/Ianvs/ianvs-terminal/launch_configs/<name>.json`。
  - 高级 path 输入可折叠，不应是第一视觉焦点。
  - 主标题和 primary CTA 聚焦“保存当前 app / tab config”，不是“编辑 JSON path”。
- [x] `WLA-011` 增加保存成功态。
  - 保存后不直接关闭 dialog，显示保存文件名、路径、`Copy path` / `Apply saved app` / `Done`。
  - 对齐 Warp `LaunchConfigSaveModal` 的 `NotSaved -> Success -> OpenFile` 状态节奏。
- [x] `WLA-012` 增加 saved config 发现入口。
  - `+` add menu 提供 `Saved configs` 入口列出已保存配置。
  - saved config hover / select 时显示 sidecar：摘要、`Apply`、`Edit file`、`Remove`、`Make default`。
  - 这是对齐 Warp `saved-tab-config-menu.png` 的核心。
  - 当前实现：`terminal-add-menu-button` 增加 saved configs action，`_SavedLaunchConfigsPanel` 支持选择、apply、edit file、remove、make default；`TerminalLaunchConfigurationStore.listSaved()` / `remove()` 覆盖持久化发现与删除。
  - 验收：`test/widget_test.dart` 覆盖保存、发现、设为 default、apply、remove；`test/launch_config_test.dart` 覆盖 store list / remove。
- [x] `WLA-013` 增加 tab / window context action。
  - Tab 或 Window strip 上提供 `Save as config`，不要求复制 Warp 文案。
  - 保存当前 tab 时走 tab-scoped schema；保存全 app 时走 app-level schema。
  - 当前实现：tab strip 的 `Save tab as config` 保存单 tab config，JSON 顶层写入 `scope: "tab"`；window strip 的 `Save app as config` 保存完整 app config，JSON 顶层写入 `scope: "app"`。
  - 验收：`test/widget_test.dart` 覆盖 tab / window context action；`test/launch_config_test.dart` 覆盖 scope serialization / fallback。
- [x] `WLA-014` 补充 visual acceptance：新保存流截图与 Warp `Tab Configs` 截图在入口层级、sidecar、CTA 和成功反馈上不再只用主观百分比描述，后续同类新增项优先补 `5%` rect contract。
  - `saved_config_sidecar.png` 覆盖 saved config list + sidecar + CTA。
  - `launch_config_compose.png` / `launch_config_success.png` 覆盖 compose 和 success state。

### P1：App Chrome 与 Pane 直接操作

- [x] `WLA-020` 压缩 `_Header`。
  - 当前 `110px` 两行工具栏应降为更轻的 top chrome：产品名 / active context / window+tab strip / primary add menu。
  - 低频动作移入 overflow 或 palette，避免 Copy / Paste / Restart / Split / Session Context / Launch Config 全部平铺。
  - 当前实现：header 高度压到 `76px`；创建 / 配置入口进入 `terminal-add-menu-button`；搜索、workspace search、settings、split、close pane/window、session context、copy、paste、restart 进入 `terminal-header-overflow-menu-button`；`test/widget_test.dart` 覆盖 header 高度、add / overflow 菜单值和旧平铺 key 不在初始 header。
- [x] `WLA-021` 把 `New Window`、`New Tab`、`Launch Config` 合并成更接近 Warp 的 add menu。
  - 单一 `+` 入口承载 New Tab、New Window、New SSH、saved configs、Save current tab/app。
  - 保留 macOS menu parity，但日常视觉入口不应变成一排工具按钮。
  - 当前实现：`terminal-add-menu-button` 已承载 New Tab、New Window、New SSH、saved configs、Save current tab/app、Launch Config；旧平铺按钮已迁出日常视觉入口，测试通过菜单 helper 保持同一行为覆盖。
- [x] `WLA-022` 为 pane 增加本地 header / active marker。
  - 每个 pane 显示 compact session label、cwd / target、close / split / overflow。
  - active pane 用角标、边框或 header accent 标记；不要只靠外部 header 状态。
  - 当前实现：每个 pane 显示 local header、`Pane <id>` label、target badge、cwd preview、pane 级 split right / split down / close；active pane 有 header accent 和 `terminal-pane-active-marker-*`；非 active pane 也保留 `terminal-inactive-input-context-strip-*` 与 `terminal-inactive-modern-input-bar-*`，但不接收输入。
  - 验收：`test/widget_test.dart` 覆盖 pane header 渲染、active marker、pane 级 split / close action。
- [x] `WLA-023` 设计 pane drag/drop 的后续入口。
  - 先做 header hit area 和 hover affordance，再决定是否实现完整拖拽到 tab bar。
  - 当前实现：pane header 已有 `terminal-pane-drag-handle-*`，hover 使用 move cursor；完整 drag gesture 和 tab bar drop target 留作后续增强。
- [x] `WLA-024` 补 pane-local context chips 和 pane menu。
  - 每个 pane header 显示 pane-local target、cwd、status 和最近命令 chip；split 后不能只依赖 active pane 的全局 context。
  - pane menu 提供 focus、split、session context、copy、paste、restart、close，避免 pane 操作继续回流到全局 header。
  - 当前实现：`terminal-pane-context-chips-*` / `terminal-pane-context-chip-*-*` 和 `terminal-pane-menu-*` 已落地；widget test 覆盖 menu 项和 menu-driven split / close。
- [x] `WLA-025` 支持 pane move-to-tab 行为。
  - pane menu 提供 `Move to new tab`，把 split pane 提升为独立 tab，作为完整 drag/drop 到 tab bar 前的可用行为。
  - 当前实现：`TerminalTabsController.moveActivePaneToNewTab()` 复用现有 pane shell，不重启 PTY session；`TerminalWindowsController` 暴露同名入口，pane menu 通过 `terminal-pane-menu-move-to-new-tab-*` 调用。
  - 验收：`test/terminal_panes_controller_test.dart` 覆盖 controller 不重启 session；`test/widget_test.dart` 覆盖 pane menu 触发后 tab / pane 可切换。

### P1：Terminal-native Block 呈现

- [x] `WLA-030` 把 block rail 从 viewport overlay 改为不遮挡 terminal 内容的表现。
  - 当前 `_InlineBlockRail` 曾固定 `Positioned(top: 12, left: 18, right: 18)`，会让 block 贴近 viewport 顶部。
  - 当前实现：active pane 有 block rail 时，rail 会按 viewport 高度下沉，并同步提高 `TerminalViewport.contentPadding.top`，让 terminal 内容避开 rail；无 block 时保持默认 padding。
- [x] `WLA-031` 增加 terminal 内 block divider / left status rail。
  - 每个完成 block 至少有边界、状态颜色、command preview。
  - 失败 / interrupted block 要比普通 succeeded block 有更明显的视觉区分。
  - 当前实现：active pane 有 blocks 时，viewport 左侧显示 `terminal-block-status-rail`，每个 marker 带状态色、状态文案和 command preview；失败 / interrupted 复用更醒目的状态色；`TerminalViewport.contentPadding.left` 从 `14` 提高到 `132`，避免遮挡 terminal 内容。
- [x] `WLA-032` 把 block 操作靠近 block 本体。
  - hover / context menu 提供 copy command、copy output、copy all、reinput、bookmark placeholder。
  - Header 的 `_BlockToolbar` 可以保留为辅助，但不应是唯一操作入口。
  - 当前实现：`terminal-inline-active-block-card` 内有 `terminal-inline-block-actions-button`，菜单提供 copy command、copy output、copy all、reinput 和 disabled bookmark placeholder；active block card 的 hover/pressed 只改变背景和边框交互层，不移动 block/input；`block_actions_layout.png` 和 widget test 覆盖 inline copy/reinput 行为。
- [x] `WLA-033` 补 sticky command header。
  - 滚动长输出时，当前 block command 应在 viewport 顶部 sticky 显示，点击可回到 block 起点。
  - 当前实现：`terminal-sticky-block-command-header` 固定在 active block rail 中，显示当前 command preview；点击会调用 active block selection 并滚回 block 起点。
- [x] `WLA-034` 评估 flutterm 渲染扩展点。
  - 如果需要按 scrollback row range 绘制 divider / background / sticky header，先在 `FLUTTERM_FEEDBACK.md` 增补明确上游需求，不在产品层做脆弱 frame diff。
  - 当前处理：`FT-008` 已更新为“需要上游任务”，记录 row range divider、background、status gutter 和 sticky header 扩展点；本轮不修改 `/Users/luobinghui/projects/flutter/flutterm`。

### P2：Input Editor 与 Inline Menu

- [x] `WLA-040` 统一 history / completion / command search 的呈现位置。
  - `_CommandHistoryPanel` 和 `_CompletionPanel` 应共享一个 inline menu shell：搜索输入、结果列表、来源 badge、详情区。
  - 菜单位置跟随 input editor，可在 input 上方或下方，不要继续堆多个全宽底部 panel。
  - 当前实现：`_InlineMenuShell` 统一承载 command/session palette、completion 和 legacy command history；command/session palette 已移到 active pane input editor 上方，completion rows 使用 source badge 和 description detail，窄 split pane 也通过 widget test 覆盖不溢出。
- [x] `WLA-041` 把 `_ModernInputBar` 从表单视觉改为 editor 视觉。
  - 保留多行和软换行能力，但减少输入框边框厚重感。
  - Submit / History / Save / Raw 放进更紧凑的 trailing toolbar 或 overflow。
  - 当前实现：`terminal-modern-input-editor` 使用轻量 editor 容器和无 outline 的 `TextField`；`terminal-modern-input-toolbar` 内收敛 Submit / History / Save / Raw 四个 icon action。
- [x] `WLA-042` 补 editor 操作覆盖。
  - 按 Warp 文档补齐至少：`Ctrl-U` 清行、`Cmd-A` 全选 buffer、`Opt-Backspace` 删除词、`Ctrl-R` 打开统一 command search。
  - Raw 模式不受 editor 快捷键误伤。
  - 当前实现：现代输入编辑 helper 和 `_ModernInputBar` 已覆盖这些快捷键；`Ctrl-R` 打开统一 command/session palette，raw 模式保持不打开 command search。
- [x] `WLA-043` 补 completion 候选面板的来源标签和选择态。
  - 每个候选保留 spec / template / generator source badge。
  - active row 需要有明确 selected state，而不是只靠键盘内部 index。
  - 当前实现：completion row 使用 source badge、selected semantics、active left rail 和 `terminal-completion-active-badge-*`；widget test 覆盖 source label 和选择态切换。
- [x] `WLA-044` 在默认布局补 input-adjacent context chips。
  - 底部 editor 上方显示当前 pane 的 target、cwd、status 和最近命令，让默认画面与 Warp `01_terminal_blocks.png` 的 bottom prompt / context 关系更接近。
  - 当前实现：空输入时 `_InputContextStrip` 在 active pane 的 `_ModernInputBar` 上方渲染 `terminal-input-context-chip-*`；输入草稿存在时切换为 `terminal-input-command-detection-strip`，用于对齐 Warp `04_completion_input.png` 的基础输入识别状态。
  - 验收：`test/widget_test.dart` 覆盖 chip key；`default_terminal_layout.png` 固化默认布局。

### P2：统一 Command / Session Palette

- [x] `WLA-050` 把 command history、saved commands、workspace search 合并为一个 palette shell。
  - 来源至少包括：saved commands、当前 window 历史、所有 Ianvs windows 的 pane/session、recent cwd / target context。
  - 后续预留 workflow-like command schema，但不引入 Warp AI / cloud 对象。
- [x] `WLA-051` 扩展 `WorkspaceSearchController` 到 `TerminalWindowsController`。
  - 结果必须覆盖所有 app windows，而不是只搜 active window 的 `TerminalTabsController`。
  - 结果字段加入 window label、tab title、pane cwd、target host、last command、status。
- [x] `WLA-052` 增加 filter prefix。
  - 至少支持 `history:`、`saved:`、`session:`、`ssh:`。
  - 当前已扩展支持 `workflow:`、`saved:`、`history:`、`session:`、`ssh:`、`launch:`；`config:` / `configs:` 作为 launch config alias。
  - UI 上显示 active filter chip，输入删除后恢复 all。
- [x] `WLA-053` 结果详情区对齐 Warp rich history / session navigation。
  - command 结果显示状态、cwd、完成时间、输出首行。
  - session 结果显示 prompt / cwd / target / running or last command / recency。
  - 当前实现：`CommandPaletteEntry.commandDetailLabel` / `sessionDetailLabel` 生成 rich detail，UI 在每行下方显示；command palette 单测覆盖状态、cwd、完成时间、输出首行、prompt context、target 和 running 状态，widget test 覆盖 detail 文案渲染。
- [x] `WLA-054` 增加 launch config palette source。
  - Palette 直接从 `TerminalLaunchConfigurationStore.listSaved()` 注册 saved launch configs。
  - 结果可按名称、path、scope、window/tab/pane count、pane cwd、startup command 和 metadata 搜索。
  - Enter / click 直接 apply saved config，并更新 `_lastLaunchConfigPath` 与 snackbar。
  - 验收：`test/command_palette_test.dart` 覆盖 source / prefix / detail；`test/widget_test.dart` 覆盖从 palette apply 后恢复 split panes。
- [x] `WLA-055` 增加 workflow-like saved command source。
  - 以 `SavedCommandEntry` 的 title / command / tags / cwdHint / targetKind / createdAt 作为 workflow-like command metadata。
  - UI source badge 显示 `Workflow`，同时保留 `saved:` prefix alias 和原有保存 / 删除 / reload 行为。
  - 验收：`test/command_palette_test.dart` 覆盖 workflow source；`test/widget_test.dart` 覆盖 save command、source badge、save/remove 和 reload。
- [x] `WLA-056` 增加 command palette source rail。
  - command palette header 显示支持来源的数量与可点击筛选：Workflow、History、Sessions、SSH、Launch。
  - 不显示 Ianvs Terminal 当前未支持的 Warp 云 / AI / 文件类别，避免把“参考 Warp 类别”误写成已支持功能。
  - 当前实现：`CommandPaletteController.countForFilter()` / `updateFilter()` 驱动 `_PaletteSourceRail`；`test/warp_alignment_golden_test.dart` seed saved launch config，确保截图导出中能看到 Launch source，并对 source rail / results top 加入 5% rect contract。
  - 验收：`test/command_palette_test.dart` 覆盖 source 计数与点击筛选逻辑；`test/widget_test.dart` 覆盖从 source rail 切到 Launch 后应用 saved config。

### P2：Saved Config Schema 与设置 breadth

- [x] `WLA-060` 拆分 app-level launch config 和 tab-level config 的用户概念。
  - app export：windows / tabs / panes / metadata。
  - tab config：单 tab pane tree / cwd / commands / shell / title / optional params。
  - 当前实现：Launch Config 保存面板明确说明 `App config` 与 `Tab config` 的范围；Saved Config list / sidecar 显示 scope title 与说明，widget test 覆盖 app/tab scope 文案。
- [x] `WLA-061` 为 saved command 升级 schema。
  - 从纯字符串 list 演进到 `{title, command, tags, cwdHint, targetKind, createdAt}`，兼容旧数据。
  - 验收：`test/saved_commands_test.dart` 覆盖旧 `commands[]` 迁移、metadata roundtrip、去重和删除。
- [x] `WLA-062` 增加 session settings breadth。
  - 至少预留 new session shell、startup shell、working directory policy by split/tab/window。
  - 当前实现：Settings 面板把 default shell 文案收口为 `New session shell`，并新增 `Session defaults` 预留区：startup shell、split cwd policy、tab cwd policy、window cwd policy。

### P3：桌面端 E2E

- [x] `WLA-070` 建立 M7E 桌面端 E2E harness。
  - 统一封装 window、tab、pane、launch config、session context、SSH、workspace search 动作和断言。
  - 当前实现：`test/demo_terminal_session_test.dart` 中 `_DesktopDemoHarness` 封装 app 启动 / rebuild、window / tab / pane、Launch Config save / apply、Session Context、New SSH Session、Workspace Search、Command Search 和 restart。
- [x] `WLA-071` 首批 E2E 场景。
  - 新建两个 window，切换 active window。
  - 保存 app config，销毁状态，重新 apply，恢复 active window / active pane。
  - 保存成功态截图。
  - split pane、workspace palette、SSH command session restart。
  - 当前实现：demo harness 覆盖 app export / apply 成功反馈、多窗口 active window 恢复、workspace palette 跳转、split pane session restore、SSH command session restart、command palette reinput。
- [x] `WLA-072` 把截图验收纳入 E2E 输出。
  - 每个关键 UI 输出当前截图路径和失败时的差异说明。
  - 当前实现：M7E 验证命令同时运行 demo harness 与 golden gates：`flutter test test/demo_terminal_session_test.dart test/launch_config_golden_test.dart test/warp_alignment_golden_test.dart`；截图路径固定为 `docs/design_snapshots/warp_alignment/*.png`，失败时由 Flutter golden diff 输出差异。

## 当前优先级建议

1. 当前已完成 `WLA-001 -> WLA-004`、`WLA-010 -> WLA-014`、`WLA-020 -> WLA-025`、`WLA-030 -> WLA-034`、`WLA-040 -> WLA-044`、`WLA-050 -> WLA-056`、`WLA-060 -> WLA-062`、`WLA-070 -> WLA-072`、`WLA-080 -> WLA-081`。
2. 本轮 `WARP_SOURCE_REAUDIT.md` 点名的 launch config source、workflow-like saved command source、completion 来源标签 / 选择态、pane-local context chips 和 pane menu 已完成并有 unit / widget / golden 验证；本次追加 source rail 截图可见入口、pane move-to-tab 行为，以及 `[Image #1]` 默认布局截图 gate / input context strip。
3. 若继续扩展，优先做 session prompt snapshot fidelity、settings 行为接入、完整 pane drag gesture 到 tab bar 和 terminal-native block render upstream，而不是重复当前 widget / golden / E2E 覆盖。

## 不做事项

- 不复制 Warp 品牌、素材、图标、云服务、AI objects 或私有实现。
- 不把 Ianvs Terminal 说成 Warp-compatible 或 Warp clone。
- 不为了视觉对齐绕过 `flutterm_terminal` 重新实现 terminal runtime。
- 不把 mobile、本地 shell 以外的平台承诺提前写进首版验收。
