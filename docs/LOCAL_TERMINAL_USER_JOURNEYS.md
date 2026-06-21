# Local Terminal User Journeys

Date: 2026-06-21

本文基于当前代码梳理 `Ianvs Terminal` 示例应用的核心用户旅程。它不是路线图状态、验收证据或需求承诺；它是一份从代码反推出来的体验地图，用来帮助后续产品设计、回归测试和任务拆分对齐同一套入口、状态和安全边界。

## 阅读地图

主要入口和职责：

- `example/lib/main.dart`：调用 `runIanvsTerminalApp()`。
- `example/lib/app_bootstrap.dart`：组装 Riverpod providers，接入 clipboard、window bridge、session runtime、reference demo 和 shell animation 开关。
- `example/lib/app.dart`：根据 `SessionController` 的主题偏好创建 `MaterialApp`，主页为 `ShellScreen`。
- `example/lib/features/sessions/session_controller.dart`：负责 profile/config bootstrap、session 创建、tab/pane 生命周期、runtime event 同步、窗口标题和默认偏好。
- `example/lib/features/sessions/session_state.dart`：定义 `TerminalTab`、`TerminalPane` 和 split layout tree。
- `example/lib/features/shell/shell_screen.dart` 及 `shell_screen_state_*.dart`：承载主界面、Command Center、底部 Universal Input、Command Search、Action Search、Toolbelt、clipboard/paste、快捷键、原生窗口菜单和 transient UI 状态。
- `example/lib/features/shell/universal_input.dart`：定义 terminal/agent/auto 输入模式、自然语言分类、命令建议与风险等级。
- `example/lib/features/shell/window_bridge.dart`：桥接 macOS 窗口标题、关闭/退出请求、native paste/find/command search、hotkey window 和通知。

相关长期约束：

- [ARCHITECTURE.md](ARCHITECTURE.md)：包分层、PTY/runtime/viewport 数据流。
- [COMMAND_CENTER_WARP_POST_UNIVERSAL_INPUT_SPEC.md](COMMAND_CENTER_WARP_POST_UNIVERSAL_INPUT_SPEC.md)：Command Center 与 Agent Center 合流后的输入所有权和安全边界。
- [TESTING.md](TESTING.md)：当前验证入口。

## 全局体验模型

当前产品是一个以本地 shell session 为中心的工作台：

1. 启动时加载 profiles、local config/preferences 和默认 profile。
2. 如果有有效默认 profile，自动创建第一个 PTY session 并显示终端工作区。
3. 用户主要在 terminal pane 中工作；底部 `ShellCommandInputBar` 提供更强的命令编辑、补全、自然语言建议和 Agent 对话入口。
4. 顶部 chrome、Command Center、Action Search、Toolbelt、Profiles/Defaults dialog 提供二级操作入口。
5. 写入 shell 的动作必须经过当前 session、read-only、paste policy、Agent proposal review 等 guard。

核心不变量：

- 同一时刻只有一个输入 owner。terminal、command input、command search、action search、agent conversation、proposal review 不能同时拥有文本插入权。
- 自然语言不会静默写入 PTY；它只能插入建议命令，用户需要再次确认执行。
- Agent 生成的命令不能绕过 review/read-only/paste/risk gates。
- `read-only` 是 session 级状态，阻止 command input、paste、helper send 和直接 plain text send。
- 多行或大段文本发送走 paste decision；需要确认时必须先弹确认。
- 打开 Command Center、Profiles、Defaults、Command Search、Action Search 等 overlay 前会清理相互冲突的 transient UI，并在关闭后恢复 terminal 或 command input focus。

## Journey 1: 首次启动进入 Shell Workspace

触发入口：

- 用户启动 app。
- 代码路径：`main.dart -> app_bootstrap.dart -> app.dart -> ShellScreen`。

主线：

1. `buildIanvsTerminalRoot()` 注入 `sessionControllerProvider`、clipboard bridge、window bridge、demo fixture 和 shell animation provider。
2. `IanvsTerminalApp` 监听 `SessionController.themeMode`，创建 light/dark Material 主题。
3. `SessionController.build()` 异步调用 `_bootstrap()`。
4. `_bootstrap()` 加载 profiles；如果为空，使用 `defaultTerminalProfile()`。
5. `_loadBootstrapConfig()` 读取 local terminal config，失败时回退 legacy preferences。
6. `_resolveBootstrapPreferences()` 解析 configured/effective default profile；必要时修复写回偏好。
7. 如果存在 effective default profile，`TerminalRuntimeController.createSession()` 创建初始 session。
8. `SessionState` 更新为 ready，包含 profiles、tabs、activeSessionId、defaultProfileId、themeMode、terminalViewportPadding 和 configurationWarnings。
9. `ShellScreen` 渲染顶部 tabs/chrome、中间 terminal workspace、底部 command input/status bar。

异常与分支：

- Reference demo mode 开启时，不创建真实 PTY，而是从 demo fixture 初始化 tabs、profiles 和 viewport。
- 没有 active session 时，`ShellScreen` 展示 empty state，用户通过 New tab 回到 workspace。
- profile load warnings 会显示配置告警 banner，并提供 `Review Profiles` 入口。
- bootstrap 期间 `isReady == false` 时显示 startup surface。

代码锚点：

- `example/lib/app_bootstrap.dart`
- `example/lib/app.dart`
- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/shell/shell_screen.dart`

验证锚点：

- `example/test/widget_test.dart`
- `example/test/sessions/session_controller_test.dart`
- `example/test/shell/shell_screen_phase1a_test.dart`

## Journey 2: 运行普通 Shell 命令

触发入口：

- 用户在底部 `ShellCommandInputBar` 输入命令并按 Enter 或点击 run。

主线：

1. `ShellScreen` 为 active session 创建 command input controller/focus node。
2. `ShellCommandInputBar` 根据 `UniversalInputClassifier` 对文本分类。
3. terminal/auto 模式下，如果分类为 command，`_submit()` 调用外部 `onSubmitted`。
4. `ShellScreen` 的 `_submitCommandInput(sessionId, command)` 先检查空文本和 read-only。
5. 提交前记录 command block preview capture。
6. 单行命令直接调用 `_sendPlainTextToSession(sessionId, '$command\n')`。
7. 多行命令走 `_sendCommandInputTextWithPasteConfirmation()`，由 `LocalTerminalPasteDecisionResolver` 判断是否需要确认。
8. `_sendPlainTextToSession()` 编码 UTF-8，并通过 `TerminalRuntimeController.sendInput()` 写入 PTY。
9. 成功后清空 command input，恢复输入焦点，后续 runtime frame event 更新 viewport。

异常与分支：

- read-only session 下 `_submitCommandInput()` 返回 false，不清空输入也不写 PTY。
- 多行/大段文本如果被 paste policy 判定需要确认，用户取消则不写 PTY。
- 命令纠错面板存在时，用户继续输入会 dismiss correction；成功提交后也会清理 active correction。

代码锚点：

- `example/lib/features/shell/shell_screen_command_blocks.dart`
- `example/lib/features/shell/shell_screen_state_terminal_workspace.dart`
- `example/lib/features/shell/shell_screen_state_clipboard.dart`
- `example/lib/features/shell/universal_input.dart`

验证锚点：

- `example/test/shell/universal_input_test.dart`
- `example/test/shell/shell_screen_command_blocks_test.dart`
- `example/test/policies/local_terminal_paste_decision_test.dart`

## Journey 3: 自然语言建议与 Agent 对话

触发入口：

- 用户在 auto/terminal 模式输入自然语言。
- 用户切换到 Agent 模式，或输入 `* ` 前缀触发 Agent mode。

自然语言主线：

1. `UniversalInputClassifier` 将输入标记为 `naturalLanguage`。
2. `ShellCommandInputBar._submit()` 不执行原文本。
3. 如果已有 suggestions，接受第一条建议并插入输入框。
4. 如果没有 suggestions，调用 `onGenerateCommandDrafts` 生成命令草稿。
5. 有草稿时插入第一条命令，并显示 `Suggested command inserted. Press Enter to run it.`。
6. 没有可用草稿时显示自然语言不可用提示。

Agent 主线：

1. 用户切换到 `UniversalInputMode.agent` 后，输入区上方显示 compact `AgentConversationPane`。
2. `ShellCommandInputBar._sendAgentMessage()` 把用户消息和 streaming assistant placeholder 追加到本地 `AgentConversation`。
3. `AgentRequest` 携带当前 conversation、redacted context 和所选 model config，经 `AgentRuntimeAdapter.send()` 流式返回。
4. Agent proposal 可通过 review/insert 回到 command input，但执行仍受安全 pipeline 约束。

安全边界：

- 自然语言只插入建议，不直接执行。
- Agent 发送请求使用 context snapshot，secret value 不进入 Agent request。
- Agent proposal 的执行是后续 gated slice，不允许绕过 read-only、paste confirmation 或风险确认。

代码锚点：

- `example/lib/features/shell/universal_input.dart`
- `example/lib/features/shell/shell_screen_command_blocks.dart`
- `example/lib/features/shell/shell_screen_state_command_search.dart`
- `example/lib/features/agent_center/`

验证锚点：

- `example/test/shell/universal_input_test.dart`
- `example/test/agent_center/agent_command_safety_pipeline_test.dart`
- `example/test/command_center/command_search_insert_execute_safety_test.dart`

## Journey 4: Command Center 执行动作

触发入口：

- 用户点击 chrome 中的 Command Center。
- 用户按 Command Center 快捷键。
- 用户从 Action Search 或 native menu 进入相关动作。

主线：

1. `_openCommandMenu()` 防止重复打开，并调用 `_dismissTransientCommandInputUi(includeSearchOverlays: true)` 清理冲突 overlay。
2. 打开 `RawDialogRoute<TerminalActionId>`，显示右上角 `_ShellCommandMenu`。
3. 菜单展示 search field、Top actions、App actions、Session actions、policy/productivity/tooling actions。
4. 每个 tile 根据 active session、default profile、read-only、command block feature flags、hotkey status 等状态决定 enabled 和 disabled reason。
5. 用户点击 tile 或在 search field 中提交匹配 query 后，route 返回 `TerminalActionId`。
6. route 关闭并完成动画后，`_openCommandMenu()` 再次清理 transient UI。
7. defaults/profiles/dynamic profiles 走专用 dialog/sheet。
8. 其他动作进入 `ShellActionProductionRuntimeAdapter`，由 production callbacks 调用真实 side effect。
9. 失败或 skipped result 通过 SnackBar 展示原因。

典型动作：

- App: New tab、Defaults & appearance、Reopen closed tab、Toolbelt、Terminal color presets、Profiles、Dynamic profiles。
- Session: Copy selection、Copy mode、Paste、Advanced paste、Paste history、Split right/down、Zoom pane、Search terminal output。
- Productivity: Command Search、Replay from command block、Read-only、Clear scrollback、Global search、Autocomplete、Auto composer、Prompt navigation、Select command output。
- Integration: Recent directories、tmux、Coprocess、Annotations、Captured output、Password manager。
- Policy/platform: Hotkey window、notifications、export scrollback、export diagnostics。

代码锚点：

- `example/lib/features/shell/shell_screen_command_menu.dart`
- `example/lib/features/shell/shell_screen_state_command_actions.dart`
- `example/lib/features/shell/shell_action_production_runtime_adapter.dart`
- `example/lib/features/shell/shell_action_production_callbacks.dart`

验证锚点：

- `example/test/shell/shell_command_menu_model_test.dart`
- `example/test/shell/shell_action_production_callbacks_test.dart`
- `example/test/shell/shell_action_production_executor_test.dart`
- `example/test/shell/shell_screen_phase3_test.dart`
- `example/test/shell/shell_screen_phase4_test.dart`

## Journey 5: Tabs 与 Panes 工作区管理

触发入口：

- 顶部 tab chrome。
- Command Center / Action Search。
- tab context menu。

主线：

1. New tab 通过 `_createSession()` 调用 `SessionController.createSession(profile)`。
2. `createSession()` 为 profile 注入默认 TERM/COLORTERM 和环境覆盖，创建 PTY session，并追加 `TerminalTab`。
3. Activate tab/pane 调用 `SessionController.activateSession(sessionId)`，更新 active pane、activeSessionId 和窗口标题。
4. Split right/down 调用 `_splitActiveSession()`，再进入 `SessionController.splitActiveSession(profile, axis)`。
5. `TerminalPaneLayoutNode.splitPane()` 将当前 leaf 替换为 split node，pane layout tree 保留 ratio 和 axis。
6. Focus next/previous pane 在 active tab 的 effective panes 中移动。
7. Resize/grow/swap/zoom 都围绕 `TerminalPaneLayoutNode` 和 `_zoomedPaneSessionId` 更新 UI 状态。
8. Close session/tab 时关闭 runtime session，清理 viewport/focus/new-output 状态，并选中下一个可用 session。

异常与分支：

- 关闭最后一个 session 会进入 `Shell workspace is idle` empty state。
- Reopen closed tab/pane 会根据保存的 `TerminalPane.profileSnapshot` 重新创建真实 runtime session；不会复用旧 PTY。
- zoomed pane 状态下，部分 pane management action 会提示先 unzoom。
- 分屏如果没有 default profile 或 active session，会 disabled/skipped。

代码锚点：

- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/sessions/session_state.dart`
- `example/lib/features/shell/shell_screen_state_sessions.dart`
- `example/lib/features/shell/shell_screen_state_command_actions.dart`

验证锚点：

- `example/test/sessions/session_state_test.dart`
- `example/test/sessions/session_controller_phase3_test.dart`
- `example/test/shell/shell_screen_phase2a_test.dart`
- `example/test/shell/shell_screen_phase2b_test.dart`

## Journey 6: Profiles、Defaults 与 Appearance

触发入口：

- Command Center 的 `Defaults & appearance`、`Terminal color presets`、`Profiles...`、`Dynamic profiles`。
- 配置告警 banner 的 `Review Profiles`。

Defaults 主线：

1. `_openDefaultsAndAppearance()` 清理 transient UI，设置 `_isDefaultsOpen`，发布 acceptance snapshot。
2. 打开 `DefaultsAndAppearanceDialog`，传入 profiles、configured/effective default profile、themeMode 和 viewport padding。
3. 用户保存后，分别调用 `setDefaultProfile()` / `resetDefaultProfile()`、`setThemeMode()`、`setTerminalViewportPadding()`、`saveProfile()`。
4. 如果用户选择 open profiles，则转入 Profiles sheet。
5. 关闭后恢复 session focus。

Profiles 主线：

1. `_openProfilesSheet()` 打开 `ProfilesSheet`。
2. `OpenProfileResult` 用选中 profile 创建新 session。
3. `EditProfileResult` 打开 `ProfileEditorDialog` 并保存编辑。
4. `CreateProfileResult` 用 `_newProfileTemplate()` 生成唯一 id，再打开 editor。
5. `DynamicProfilesSheet` 可导入 iTerm-style JSON profiles，并逐个 `saveProfile()`。

代码锚点：

- `example/lib/features/shell/shell_screen_state_profile_actions.dart`
- `example/lib/features/shell/defaults_appearance_dialog.dart`
- `example/lib/features/profiles/profiles_sheet.dart`
- `example/lib/features/profiles/profile_editor.dart`
- `example/lib/features/profiles/dynamic_profiles_sheet.dart`
- `example/lib/features/profiles/profile_repository.dart`

验证锚点：

- `example/test/profiles/profile_repository_test.dart`
- `example/test/profiles/profile_sheets_test.dart`
- `example/test/profiles/profile_editor_test.dart`
- `example/test/shell/shell_screen_phase3_test.dart`

## Journey 7: Command Search、Action Search 与 Command Blocks

触发入口：

- Command Center 的 `Command Search` / `Action search`。
- `Ctrl-R` / `Cmd-R` command search shortcut。
- Toolbelt 的 Command search。
- Command block scoped actions。

Command Search 主线：

1. `_openCommandSearch(sessionId)` 关闭 toolbelt/autocomplete/auto composer/action search，并创建 `CommandSearchOverlayController`。
2. controller 使用当前 session command blocks 和 global history。
3. 用户可查看结果、跳转到对应 command block、插入命令、执行安全允许的命令，或 ask Agent explain/debug。
4. ask Agent 会关闭 search，切换 Universal Input 到 agent mode，并把 prompt 注入 `ShellAgentPromptAction`。
5. 关闭后优先恢复 command input focus，否则恢复 terminal focus。

Action Search 主线：

1. `_openCommandActionSearch(sessionId)` 关闭 command search/autocomplete/auto composer，并构建 `CommandActionSearchController`。
2. controller 聚合 shell actions、productivity state、command block feature flags 和 saved commands。
3. 用户选择 action 后，`_openCommandActionSearchAction()` 映射到 `TerminalActionId` 并执行对应 side effect。
4. saved command 的 insert/execute 路径仍走 command input 与 read-only/paste safety。

Command Blocks 主线：

1. shell integration/runtime event 生成 prompt marks、command snapshots 和 global command history。
2. command block preview、selected block、last failed block 等上下文可以进入 context chips 和 Agent prompts。
3. block-scoped rerun/debug/explain/replay 都必须检查 feature flags、block validity 和 read-only。

代码锚点：

- `example/lib/features/shell/shell_screen_state_command_search.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/lib/features/shell/shell_screen_command_blocks.dart`
- `example/lib/features/shell/shell_screen_state_command_history.dart`
- `example/lib/features/command_center/`

验证锚点：

- `example/test/command_center/command_search_overlay_controller_test.dart`
- `example/test/command_center/command_action_search_controller_test.dart`
- `example/test/command_center/command_search_insert_execute_safety_test.dart`
- `example/test/command_center/command_block_action_reducer_test.dart`
- `example/test/productivity/shell_command_block_controller_test.dart`

## Journey 8: Clipboard、Paste、Read-only 与输入安全

触发入口：

- Native paste menu。
- Command Center paste/advanced paste/paste history。
- Terminal keyboard paste。
- Command input 多行提交。
- Password manager、recent directory、duplicate cwd、saved command 等 helper send。

主线：

1. 普通 copy 使用 selection controller 和 clipboard bridge。
2. Paste 读取 clipboard 后进入 paste decision。
3. `LocalTerminalPasteDecisionResolver` 根据文本、多行/大段、read-only、paste policy 和 history policy 返回 blocked/confirm/send。
4. 需要确认时打开 paste confirmation dialog。
5. Advanced Paste 允许用户先转换文本，关闭 sheet 不写 shell，点击 send 才进入既有 paste 流程。
6. Paste History 从 repository 加载 recent entries，选择后仍写入 active session。
7. 最终发送使用 `TerminalInputController.clipboardPasteBytesFor()` 或 `_sendPlainTextToSession()`。

Read-only guard：

- `_readOnlySessionIds` 保存 read-only session。
- `_submitCommandInput()` 在入口阻止写入。
- `_sendCommandInputTextWithPasteConfirmation()` 将 read-only 传给 decision resolver。
- `_sendPlainTextToSession()` 再次阻止直接写入。
- paste、coprocess、integrations、command search/action search 的写入型操作都会检查 read-only 或通过统一 availability model disabled。

代码锚点：

- `example/lib/features/shell/shell_screen_state_clipboard.dart`
- `example/lib/features/shell/shell_screen_state_terminal_workspace.dart`
- `example/lib/features/shell/shell_screen_state_sessions.dart`
- `example/lib/features/policies/local_terminal_paste_decision.dart`
- `example/lib/features/shell/paste_history_repository.dart`

验证锚点：

- `example/test/policies/local_terminal_paste_decision_test.dart`
- `example/test/shell/paste_history_repository_test.dart`
- `example/test/shell/shell_screen_phase4_test.dart`
- `example/test/terminal_input_controller_test.dart`

## Journey 9: Toolbelt 与 Utilities

触发入口：

- Command Center 的 `Toolbelt`。
- Action Search 的 `toolbelt`。
- 右侧 `_ShellToolbelt` 内部 action rows。

主线：

1. `_openToolbelt()` 设置 `_isToolbeltOpen = true`。
2. terminal workspace 与 toolbelt 并排显示。
3. Toolbelt 展示 captured output、paste history、command search、recent directories、prompt marks、tmux integration、coprocess、annotations、instant replay、password manager 和 completion diagnostics。
4. 点击 row 调用 ShellScreen 注入的打开函数，通常会进入 sheet/dialog/overlay，并在结束后恢复 focus。

体验定位：

- Toolbelt 是工作区侧边工具集合，不直接改变 active tab/pane 生命周期。
- Completion diagnostics panel 是 read-only 诊断入口，用于展示 wiring/blocked 状态，不作为验收证据。

代码锚点：

- `example/lib/features/shell/shell_screen_toolbelt.dart`
- `example/lib/features/shell/shell_screen_state_integrations.dart`
- `example/lib/features/shell/shell_screen_state_coprocesses.dart`
- `example/lib/features/shell/shell_screen_state_instant_replay.dart`

验证锚点：

- `example/test/shell/local_terminal_completion_diagnostics_panel_test.dart`
- `example/test/shell/instant_replay_store_test.dart`
- `example/test/shell/shell_screen_phase3_test.dart`

## Journey 10: Native Window、Shortcuts、Close/Quit

触发入口：

- macOS native menu paste/find/command search。
- Window close button。
- Quit shortcut。
- Hotkey window toggle。
- Shell shortcuts inside Flutter.

主线：

1. `WindowBridge.setNativeMenuHandlers()` 注册 native paste/find/command search/window close callbacks。
2. native paste/find/command search 调用 ShellScreen 对应 handler，不直接操作 PTY。
3. native close/quit 走 `onWindowCloseRequested`，由 ShellScreen 判断当前 overlay 和 session 状态。
4. 如果有 overlay，应先关闭 overlay 或阻止隐藏输入写入。
5. 如果需要退出确认，调用 `WindowBridge.requestQuitConfirmation()` 或展示 product-level confirmation。
6. Hotkey window toggle 先读 `WindowBridge.hotkeyStatus()`；不可用时显示明确失败 feedback。
7. window title 随 active pane/profile 改变，由 `SessionController._setWindowTitle()` 调用 bridge。

代码锚点：

- `example/lib/features/shell/window_bridge.dart`
- `example/lib/features/shell/shell_screen_state_shortcuts_status.dart`
- `example/lib/features/shell/shell_shortcut_bridge.dart`
- `example/macos/Runner/AppDelegate.swift`
- `example/macos/Runner/MainFlutterWindow.swift`

验证锚点：

- `example/test/shell/window_bridge_test.dart`
- `example/test/shell/shell_shortcut_bridge_test.dart`
- `example/test/shell/shell_screen_phase4_test.dart`

## 端到端回归建议

每次改动 shell 主旅程时，优先选择与改动面匹配的验证：

- 启动/session/tab/pane：`cd example && flutter test test/sessions/session_controller_test.dart test/sessions/session_state_test.dart test/shell/shell_screen_phase2a_test.dart test/shell/shell_screen_phase2b_test.dart`
- Command Center/action dispatch：`cd example && flutter test test/shell/shell_command_menu_model_test.dart test/shell/shell_action_production_executor_test.dart test/shell/shell_screen_phase3_test.dart`
- Universal input/Agent safety：`cd example && flutter test test/shell/universal_input_test.dart test/agent_center/agent_command_safety_pipeline_test.dart test/command_center/command_search_insert_execute_safety_test.dart`
- Paste/read-only/window policy：`cd example && flutter test test/policies/local_terminal_paste_decision_test.dart test/shell/shell_screen_phase4_test.dart test/shell/window_bridge_test.dart`
- Profile/defaults：`cd example && flutter test test/profiles/profile_repository_test.dart test/profiles/profile_sheets_test.dart test/profiles/profile_editor_test.dart`

## 后续维护规则

- 如果新增用户可见入口，先判断它属于 terminal workspace、Command Center、Action Search、Toolbelt、Profiles/Defaults、Agent Center 还是 native bridge，再补到相应 journey。
- 如果新增写 PTY 的路径，必须在本文对应 journey 标注它如何经过 read-only、paste/risk/Agent proposal gate。
- 如果新增 overlay/sheet/dialog，必须说明它打开前会关闭哪些 transient UI，以及关闭后恢复 terminal focus 还是 command input focus。
- 本文不记录任务完成状态；任务完成情况仍以 `docs/tasks/**`、verification ledger 和测试输出为准。
