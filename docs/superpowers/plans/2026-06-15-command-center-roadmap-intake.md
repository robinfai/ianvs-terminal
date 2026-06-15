# Command Center Roadmap Intake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Command Center as a parallel roadmap track and create the complete `T-300` through `T-322` task package.

**Architecture:** This is a docs-only intake. `docs/ROADMAP.md` becomes the product-line entry, and `docs/tasks/command-center/` becomes the execution entry with complete task documents. No Dart, Flutter, Rust, terminal package API, renderer, or runtime behavior changes are part of this plan.

**Tech Stack:** Markdown, existing `docs/ROADMAP.md`, existing `docs/tasks/TEMPLATE.md`, existing repository testing guidance in `docs/TESTING.md`.

---

## Scope Check

The design spec covers one documentation intake project, not software implementation. It includes a roadmap section and a complete task package for future implementation work. Keep this plan as one unit because the roadmap, directory README, and task documents are one coherent handoff.

Out of scope for this plan:

- Command Center feature implementation.
- Flutter UI changes.
- Terminal runtime/package API changes.
- Copying `COMMAND_CENTER_*.md` files from the zip.
- Agent / AI, remote / SSH, cloud sync, collaboration, plugin ecosystem, or renderer rewrite.

## File Structure

- Modify `docs/ROADMAP.md`
  - Add a `Command Center 并行产品线` section after the current execution stance and before the long-term directions.
  - State that Command Center is parallel to `M1-M5`, not a replacement.
  - Define `CC0` through `CC6`.
- Create `docs/tasks/command-center/README.md`
  - Explain execution rules, global non-goals, phases, lanes, and task index.
- Create `docs/tasks/command-center/T-300-command-center-track-intake.md`
  - Freeze the product-line intake and document-only entry.
- Create `docs/tasks/command-center/T-301-command-center-feature-flags.md`
  - Define the future off-by-default flag/config task.
- Create `docs/tasks/command-center/T-302-command-invocation-lifecycle-model.md`
  - Define command invocation lifecycle model work.
- Create `docs/tasks/command-center/T-303-shell-hook-lifecycle-adapter.md`
  - Define shell hook to lifecycle adapter work.
- Create `docs/tasks/command-center/T-304-command-lifecycle-degraded-state.md`
  - Define lifecycle degraded/unavailable state work.
- Create `docs/tasks/command-center/T-305-session-command-history-buffer.md`
  - Define session-local history buffer work.
- Create `docs/tasks/command-center/T-306-global-command-history-repository.md`
  - Define global history persistence work.
- Create `docs/tasks/command-center/T-307-command-history-privacy-filter.md`
  - Define sensitive command filtering and clear/disable behavior.
- Create `docs/tasks/command-center/T-308-command-search-query-parser.md`
  - Define command search query parser work.
- Create `docs/tasks/command-center/T-309-command-search-index-ranking.md`
  - Define search index and ranking work.
- Create `docs/tasks/command-center/T-310-command-search-overlay-controller.md`
  - Define `Ctrl-R` overlay controller/state work.
- Create `docs/tasks/command-center/T-311-command-search-overlay-widget.md`
  - Define `Ctrl-R` overlay UI and keyboard navigation work.
- Create `docs/tasks/command-center/T-312-command-search-insert-execute-safety.md`
  - Define insert-vs-execute safety behavior.
- Create `docs/tasks/command-center/T-313-command-block-range-model.md`
  - Define command block row range model work.
- Create `docs/tasks/command-center/T-314-command-block-navigation.md`
  - Define block navigation work.
- Create `docs/tasks/command-center/T-315-command-block-actions-reducer.md`
  - Define block action reducer work.
- Create `docs/tasks/command-center/T-316-command-block-action-wiring.md`
  - Define copy/re-input/rerun wiring work.
- Create `docs/tasks/command-center/T-317-command-bar-editor.md`
  - Define command bar editor work.
- Create `docs/tasks/command-center/T-318-command-center-context-chips.md`
  - Define context chip work.
- Create `docs/tasks/command-center/T-319-command-center-mode-router.md`
  - Define explicit mode router work.
- Create `docs/tasks/command-center/T-320-sticky-command-header.md`
  - Define sticky command header work.
- Create `docs/tasks/command-center/T-321-command-review-entrypoints.md`
  - Define review / Instant Replay entrypoints.
- Create `docs/tasks/command-center/T-322-command-center-verification-gates.md`
  - Define verification gates and manual QA template work.

Every task document must include these sections exactly:

- `Goal`
- `Scope`
- `Non-goals`
- `Files In Scope`
- `Functional Acceptance`
- `Verification Commands`
- `Manual QA`
- `Done When`
- `Risks / Follow-ups`

## Task Document Payloads

Use these payloads when creating task documents. Keep each task focused on its named goal and repeat the global safety guardrails where relevant.

### Global Non-goals For Every Command Center Task

- 不做 Agent v1 或 AI command generation。
- 不做 remote / SSH / SFTP / serial、cloud sync、collaboration 或 plugin ecosystem。
- 不重写 terminal renderer。
- 不把产品 UI 下沉到 `packages/ianvs_terminal`。
- 不绕过 read-only、paste confirmation、shortcut isolation 或普通 terminal 输入语义。

### T-300 Payload

- Title: `Command Center Track Intake`
- Goal: 冻结 Command Center 作为并行产品线进入仓库路线图和任务体系。
- Scope: `docs/ROADMAP.md`、`docs/tasks/command-center/README.md`、`docs/tasks/command-center/T-300-command-center-track-intake.md`。
- Files In Scope: `docs/ROADMAP.md`、`docs/tasks/command-center/README.md`、`docs/tasks/command-center/T-300-command-center-track-intake.md`。
- Functional Acceptance: `ROADMAP.md` 说明 Command Center 不替换 `M1-M5`；目录 README 指向 `T-300` 到 `T-322`；任务包规则清楚写出全局护栏。
- Verification Commands: `rg -n "Command Center 并行产品线|T-300-command-center-track-intake|T-322-command-center-verification-gates" docs/ROADMAP.md docs/tasks/command-center`
- Manual QA: 文档任务，无需 UI QA；人工检查路线图关系和任务入口是否清楚。
- Done When: 并行产品线入口和完整任务索引存在。
- Risks / Follow-ups: 后续执行任务时必须继续按任务边界拆分，不把多个功能合进一个任务。

### T-301 Payload

- Title: `Command Center Feature Flags`
- Goal: 定义未来 Command Center feature flags 和本地配置入口，默认全部关闭。
- Scope: `example/lib/features/config/`、`example/lib/features/command_center/` 或 `example/lib/features/productivity/` 的 flag snapshot、对应测试。
- Files In Scope: `example/lib/features/config/local_terminal_config_models.dart`、`example/lib/features/config/local_terminal_config_loader.dart`、`example/lib/features/command_center/command_center_feature_flags.dart`、`example/test/config/local_terminal_config_models_test.dart`、`example/test/command_center/command_center_feature_flags_test.dart`。
- Functional Acceptance: 默认配置不启用任何 Command Center UI 或索引；子开关可独立表达 search、history、blocks、bar、chips、review；测试可注入 flag snapshot。
- Verification Commands: `cd example && flutter analyze && flutter test test/config/local_terminal_config_models_test.dart test/command_center/command_center_feature_flags_test.dart`
- Manual QA: 纯配置模型任务，无需 UI QA。
- Done When: 后续任务可以通过同一 flag snapshot 判断能力是否启用。
- Risks / Follow-ups: 配置 schema 需保持 local-only，不新增 remote 顶层语义。

### T-302 Payload

- Title: `Command Invocation Lifecycle Model`
- Goal: 建立 command invocation lifecycle 的 app 层模型，为 history、search、blocks 共用。
- Scope: command invocation、lifecycle state、status、duration、cwd/session/pane metadata。
- Files In Scope: `example/lib/features/command_center/command_invocation_models.dart`、`example/test/command_center/command_invocation_models_test.dart`。
- Functional Acceptance: 模型能表达 running、succeeded、failed、unknown；包含 command、cwd、startedAt、finishedAt、exitCode、duration、sessionId；多 session 数据不会混淆。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_invocation_models_test.dart`
- Manual QA: 纯模型任务，无需 UI QA。
- Done When: History/Search/Blocks 任务不需要重新定义 invocation 字段。
- Risks / Follow-ups: shell hook 顺序异常由 `T-304` 处理，不在本任务里扩张。

### T-303 Payload

- Title: `Shell Hook Lifecycle Adapter`
- Goal: 将 `TerminalSessionShellHookEvent` 转成 Command Center lifecycle event。
- Scope: app 层 adapter；不改 package event schema。
- Files In Scope: `example/lib/features/command_center/shell_hook_lifecycle_adapter.dart`、`example/test/command_center/shell_hook_lifecycle_adapter_test.dart`、只读参考 `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`。
- Functional Acceptance: `preexec` 创建 start event；`command_finished` 创建 finish event；`precmd.pwd` 或 cwd payload 更新 cwd；未知 hook 被忽略并记录 unavailable/unknown reason。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/shell_hook_lifecycle_adapter_test.dart`
- Manual QA: 纯 adapter 任务，无需 UI QA。
- Done When: 后续 reducer 不直接解析 raw shell hook payload。
- Risks / Follow-ups: 不同 shell 的 hook 命名差异需要通过降级状态表达。

### T-304 Payload

- Title: `Command Lifecycle Degraded State`
- Goal: 定义 shell integration 缺失、hook 顺序异常和 range 缺失时的降级状态。
- Scope: unavailable reason、limited capability、disabled action reason。
- Files In Scope: `example/lib/features/command_center/command_lifecycle_degraded_state.dart`、`example/test/command_center/command_lifecycle_degraded_state_test.dart`。
- Functional Acceptance: shell integration 关闭时不抛异常；Search 可继续使用已有 history；Blocks 和 sticky header 可显示 disabled reason；缺失 output range 不允许执行 copy output。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_lifecycle_degraded_state_test.dart`
- Manual QA: 纯状态任务无需 UI QA；后续 UI 任务必须复用这些 reason。
- Done When: 每个 Command Center action 都能得到 enabled/disabled/unavailable 的明确原因。
- Risks / Follow-ups: UI 文案在后续 widget 任务中验证。

### T-305 Payload

- Title: `Session Command History Buffer`
- Goal: 建立 session-local command history buffer。
- Scope: 当前 session 内 command 记录、去重、limit trimming、cwd/status metadata。
- Files In Scope: `example/lib/features/command_center/session_command_history_buffer.dart`、`example/test/command_center/session_command_history_buffer_test.dart`。
- Functional Acceptance: command_finished 后可立即检索；同 session newest-first；空命令不入库；不同 session 隔离。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/session_command_history_buffer_test.dart`
- Manual QA: 纯模型任务，无需 UI QA。
- Done When: `Ctrl-R` overlay 可以先消费 session-local history。
- Risks / Follow-ups: 全局落盘由 `T-306` 处理。

### T-306 Payload

- Title: `Global Command History Repository`
- Goal: 建立 local-first global command history 的持久化和安全 fallback。
- Scope: repository、json roundtrip、corrupt file fallback、batched write。
- Files In Scope: `example/lib/features/command_center/global_command_history_repository.dart`、`example/test/command_center/global_command_history_repository_test.dart`。
- Functional Acceptance: history 可保存和读取；损坏文件不导致启动失败；limit trimming 生效；session-local 与 global merge 规则明确。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/global_command_history_repository_test.dart`
- Manual QA: 人工检查测试临时文件不包含敏感 fixture；不需要 UI QA。
- Done When: Search index 可读取 global history。
- Risks / Follow-ups: 隐私过滤由 `T-307` 接入。

### T-307 Payload

- Title: `Command History Privacy Filter`
- Goal: 增加 sensitive command filter、disable history 和 clear history 策略。
- Scope: password/token/private key patterns、用户关闭 history、清空记录意图。
- Files In Scope: `example/lib/features/command_center/command_history_privacy_filter.dart`、`example/test/command_center/command_history_privacy_filter_test.dart`。
- Functional Acceptance: 明显 secret 命令不保存；禁用 history 时不写入 repository；clear history 删除 local history；过滤结果可解释。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_history_privacy_filter_test.dart`
- Manual QA: 纯策略任务，无需 UI QA。
- Done When: Repository 保存前必须经过 privacy filter。
- Risks / Follow-ups: 过滤规则要保守，避免误删普通命令。

### T-308 Payload

- Title: `Command Search Query Parser`
- Goal: 支持 command search 的文本和 filter prefix 解析。
- Scope: `history:`、`block:`、`action:`、`cwd:`、`status:` 等 prefix。
- Files In Scope: `example/lib/features/command_center/command_search_query_parser.dart`、`example/test/command_center/command_search_query_parser_test.dart`。
- Functional Acceptance: raw query 被解析为 text 和 filters；未知 prefix 保留为普通文本；空白稳定处理；quoted cwd 可被解析。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_search_query_parser_test.dart`
- Manual QA: 纯 parser 任务，无需 UI QA。
- Done When: Search index 和 overlay 共用同一个 query model。
- Risks / Follow-ups: 不实现自然语言意图识别。

### T-309 Payload

- Title: `Command Search Index Ranking`
- Goal: 建立 command search index 和 ranking。
- Scope: fuzzy/prefix matching、recency、cwd proximity、status、frequency。
- Files In Scope: `example/lib/features/command_center/command_search_index.dart`、`example/test/command_center/command_search_index_test.dart`。
- Functional Acceptance: prefix 和 fuzzy 查询可命中；当前 cwd 结果提权；失败/成功状态 filter 生效；10k 条 fixture 的查询保持可交互。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_search_index_test.dart`
- Manual QA: 纯 index 任务，无需 UI QA。
- Done When: Overlay 可直接消费 ranked results。
- Risks / Follow-ups: 大历史性能可在 `T-322` 增加基线。

### T-310 Payload

- Title: `Command Search Overlay Controller`
- Goal: 建立 `Ctrl-R` overlay 的 state/controller。
- Scope: open/close、query update、selection movement、insert/execute intent。
- Files In Scope: `example/lib/features/command_center/command_search_overlay_controller.dart`、`example/test/command_center/command_search_overlay_controller_test.dart`。
- Functional Acceptance: `Ctrl-R` intent 打开搜索；`Esc` 关闭；上下键更新选中项；`Enter` 产生 insert intent；`Cmd/Ctrl+Enter` 产生 explicit execute intent。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_search_overlay_controller_test.dart`
- Manual QA: 纯 controller 任务，无需 UI QA。
- Done When: Widget 任务不需要自行管理搜索状态。
- Risks / Follow-ups: 快捷键消费由 `T-311` 和 `T-312` 共同验证。

### T-311 Payload

- Title: `Command Search Overlay Widget`
- Goal: 实现 `Ctrl-R` overlay UI 和键盘导航。
- Scope: widget、focus、result list、empty/loading/unavailable states。
- Files In Scope: `example/lib/features/command_center/command_search_overlay.dart`、`example/test/command_center/command_search_overlay_test.dart`、必要的 `example/lib/features/shell/` wiring。
- Functional Acceptance: overlay 可打开关闭；结果显示 command、cwd、exit status、last run；键盘导航可用；IME 搜索词输入不被中断；`Esc` 不泄漏到 PTY。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_search_overlay_test.dart`
- Manual QA: 运行 app，按 `Ctrl-R`，输入英文和中文搜索词，上下移动、`Esc` 关闭，确认 shell 未收到控制字符。
- Done When: 用户能看到并导航 command search overlay。
- Risks / Follow-ups: 视觉细节可在后续 UI polish 中调整，但 terminal safety 不可放宽。

### T-312 Payload

- Title: `Command Search Insert Execute Safety`
- Goal: 确保搜索结果默认插入，不自动执行，显式执行受安全策略保护。
- Scope: insert command、explicit execute、read-only guard、paste/multiline safety。
- Files In Scope: `example/lib/features/command_center/command_search_intents.dart`、`example/test/command_center/command_search_insert_execute_safety_test.dart`、必要的 `example/lib/features/shell/` input wiring。
- Functional Acceptance: `Enter` 插入命令且不发送回车；`Cmd/Ctrl+Enter` 才执行；read-only 下执行 disabled；多行结果进入既有 paste/multiline policy。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_search_insert_execute_safety_test.dart`
- Manual QA: 在真实 app 中选择历史命令，确认 `Enter` 只插入；read-only 下显式执行不可用。
- Done When: Search overlay 不会意外执行命令。
- Risks / Follow-ups: macOS shortcut routing 需注意和 terminal `Ctrl-R` 语义冲突。

### T-313 Payload

- Title: `Command Block Range Model`
- Goal: 建立 command block 的 row range 模型。
- Scope: input range、output range、status、session/pane isolation、missing range。
- Files In Scope: `example/lib/features/command_center/command_block_models.dart`、`example/test/command_center/command_block_models_test.dart`。
- Functional Acceptance: block lifecycle 与 invocation 对齐；output range 不串命令；missing range 禁用依赖 range 的动作；不同 pane/session 隔离。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_block_models_test.dart`
- Manual QA: 纯模型任务，无需 UI QA。
- Done When: Block navigation 和 actions 可以消费稳定模型。
- Risks / Follow-ups: package 层 row range API 未冻结时只做 app 层适配。

### T-314 Payload

- Title: `Command Block Navigation`
- Goal: 支持 previous/next block 和 last failed block 导航。
- Scope: navigation reducer/controller、selected block state、disabled reason。
- Files In Scope: `example/lib/features/command_center/command_block_navigation.dart`、`example/test/command_center/command_block_navigation_test.dart`。
- Functional Acceptance: 能定位上一条、下一条和最近失败 block；无目标时给 disabled reason；只读浏览可导航但不写 PTY。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_block_navigation_test.dart`
- Manual QA: 后续 UI 接入时手测；本任务为模型/控制器可不做 UI QA。
- Done When: Shell action registry 可接入 block navigation intent。
- Risks / Follow-ups: 真实 scroll-to-row 由 UI/wiring 任务验证。

### T-315 Payload

- Title: `Command Block Actions Reducer`
- Goal: 将 block actions 归约为 clipboard/input/search/save/review intents。
- Scope: copy command、copy output、copy both、re-input、rerun、search within block、save output。
- Files In Scope: `example/lib/features/command_center/command_block_actions.dart`、`example/lib/features/command_center/command_block_action_reducer.dart`、`example/test/command_center/command_block_action_reducer_test.dart`。
- Functional Acceptance: copy output 需要有效 output range；re-input 不执行；rerun 需要显式触发；read-only 下写入型 action disabled；search within block 不污染 global search。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_block_action_reducer_test.dart`
- Manual QA: 纯 reducer 任务，无需 UI QA。
- Done When: Wiring 任务可以把 reducer intent 接到真实 clipboard/input。
- Risks / Follow-ups: save output 的目标路径选择留给 wiring 任务定义。

### T-316 Payload

- Title: `Command Block Action Wiring`
- Goal: 接入 copy output、re-input、rerun 的实际 shell/action wiring。
- Scope: action ids、availability、clipboard bridge、terminal input intent。
- Files In Scope: `example/lib/features/shell/shell_action_registry.dart`、`example/lib/features/shell/shell_action_availability.dart`、`example/lib/features/shell/shell_action_dispatcher.dart`、`example/test/shell/shell_action_availability_test.dart`、`example/test/shell/shell_action_dispatcher_test.dart`。
- Functional Acceptance: block actions 出现在统一 action registry；availability 使用 reducer reason；copy output 使用正确 range；rerun 走 read-only/paste safety。
- Verification Commands: `cd example && flutter analyze && flutter test test/shell/shell_action_availability_test.dart test/shell/shell_action_dispatcher_test.dart`
- Manual QA: 手动运行成功/失败命令，测试 copy output、re-input、rerun；read-only 下 rerun 不可用。
- Done When: MVP block actions 能通过统一 action pipeline 触发。
- Risks / Follow-ups: 复制范围与用户选区冲突时用户选区优先。

### T-317 Payload

- Title: `Command Bar Editor`
- Goal: 建立 terminal-first command bar editor。
- Scope: multiline editing、soft wrap、insert command、read-only/paste integration。
- Files In Scope: `example/lib/features/command_center/command_bar_editor.dart`、`example/test/command_center/command_bar_editor_test.dart`、必要的 `example/lib/features/shell/` wiring。
- Functional Acceptance: 普通文本默认进 shell；`Shift+Enter` 可插入换行；长命令 soft wrap；read-only 阻止发送；IME composition 不被抢。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_bar_editor_test.dart`
- Manual QA: 在 app 中输入普通命令、多行命令和中文 IME，确认输入行为稳定。
- Done When: Command Bar 可作为显式增强输入层接入，但不改变默认 terminal 行为。
- Risks / Follow-ups: 第一版不做 quote/bracket auto-pair。

### T-318 Payload

- Title: `Command Center Context Chips`
- Goal: 展示 terminal-safe context chips。
- Scope: cwd、profile、shell hook status、last exit、selected block、read-only chip。
- Files In Scope: `example/lib/features/command_center/context_chip_models.dart`、`example/lib/features/command_center/context_chips.dart`、`example/test/command_center/context_chips_test.dart`。
- Functional Acceptance: chips 从现有 session/productivity state 派生；shell hook 关闭显示 unavailable reason；last exit 可指向最近失败 block；chips 不触发命令执行。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/context_chips_test.dart`
- Manual QA: 运行命令并切换 read-only，确认 chips 更新且不造成 terminal 输入失焦。
- Done When: Command Bar 和 mode router 可消费 context chips。
- Risks / Follow-ups: git branch chip 若需要 filesystem probe，必须另行控制频率和错误处理。

### T-319 Payload

- Title: `Command Center Mode Router`
- Goal: 建立显式 mode router，区分 terminal、command search、action search、saved command 和 future agent。
- Scope: mode state、keyboard routing、escape/cancel、disabled future agent mode。
- Files In Scope: `example/lib/features/command_center/command_center_mode_router.dart`、`example/test/command_center/command_center_mode_router_test.dart`。
- Functional Acceptance: 默认 mode 是 terminal；只有显式快捷键或入口进入增强 mode；futureAgent 只作为 disabled extension point；`Esc` 返回 terminal mode。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_center_mode_router_test.dart`
- Manual QA: 后续 UI 接入时手测；本任务为 state/router 可不做 UI QA。
- Done When: Command Bar、Search、Action Search 不再各自决定 terminal input ownership。
- Risks / Follow-ups: 不实现自然语言自动识别。

### T-320 Payload

- Title: `Sticky Command Header`
- Goal: 为长输出 command block 提供 sticky header。
- Scope: visible viewport block resolution、alt-buffer/pager handling、keyboard/accessibility labels。
- Files In Scope: `example/lib/features/command_center/sticky_command_header.dart`、`example/test/command_center/sticky_command_header_test.dart`、必要的 `example/lib/features/shell/` overlay wiring。
- Functional Acceptance: 长输出滚动时显示当前 command header；alt-buffer/fullscreen app 不显示误导 header；失败状态不只靠颜色表达；header 不写入 scrollback。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/sticky_command_header_test.dart`
- Manual QA: 运行长输出、失败命令、`less` 或 `vim`，确认 header 显示/隐藏符合预期。
- Done When: Sticky header 能提升 block 可读性且不遮挡 terminal 内容。
- Risks / Follow-ups: 计算必须基于可见范围，避免扫描整段 scrollback。

### T-321 Payload

- Title: `Command Review Entrypoints`
- Goal: 从 command block 接入 Review / Instant Replay。
- Scope: replay from here、open in review、failure snapshot source metadata、diff extension point。
- Files In Scope: `example/lib/features/command_center/command_review_entrypoints.dart`、`example/test/command_center/command_review_entrypoints_test.dart`、`example/lib/features/shell/shell_screen_instant_replay.dart`、`example/lib/features/shell/instant_replay_store.dart`。
- Functional Acceptance: `Replay from here` 定位到相关 frame/range；live terminal 继续运行；review 不共享可写 input controller；diff 不可用时有 disabled reason。
- Verification Commands: `cd example && flutter analyze && flutter test test/command_center/command_review_entrypoints_test.dart test/shell/instant_replay_store_test.dart`
- Manual QA: 从失败 block 打开 review，确认 live terminal 没被切到只读或写入 review 输入。
- Done When: Command Blocks 能复用现有 Instant Replay 路径进入深复盘。
- Risks / Follow-ups: output diff 可以作为后续独立任务开启。

### T-322 Payload

- Title: `Command Center Verification Gates`
- Goal: 沉淀 Command Center 的自动化、手工、性能和 stop condition 验证门。
- Scope: verification task doc、manual QA template、performance gate list、known stop conditions。
- Files In Scope: `docs/tasks/command-center/T-322-command-center-verification-gates.md`、必要时更新 `docs/TESTING.md` 或 `docs/KNOWN_ISSUES.md`。
- Functional Acceptance: 每个 Command Center lane 有最小验证命令；输入/IME/paste/read-only/shortcut/scroll/renderer 风险有人工门；stop conditions 清楚列出。
- Verification Commands: `rg -n "Ctrl-R|read-only|IME|paste|shortcut|stop condition|performance" docs/tasks/command-center/T-322-command-center-verification-gates.md`
- Manual QA: 文档任务，无需 UI QA；人工检查是否覆盖 Search、Blocks、Command Bar、Review。
- Done When: 后续实现任务能引用同一验证门，而不是各自发明验收方式。
- Risks / Follow-ups: 真正跑 gate 的证据由各实现任务记录。

---

### Task 1: Update Roadmap With Command Center Parallel Track

**Files:**
- Modify: `docs/ROADMAP.md`

- [ ] **Step 1: Insert the Command Center section**

Add this section after the current execution stance and before the long-term directions:

```markdown
## Command Center 并行产品线

Command Center 是独立产品线，不替换当前 `M1` 到 `M5`。它可以和 runtime/xterm
证据、shell hook 契约、workspace expansion 并行推进，但每个任务都必须守住这些护栏：

- 普通输入默认发给 shell，不做自然语言自动识别。
- 不重写 renderer，不把 command block header 写入 scrollback。
- 产品 UI 留在 `example/`，`packages/ianvs_terminal` 只保留中性 terminal 能力。
- 不绕过 read-only、paste confirmation、shortcut isolation 或现有 terminal input policy。
- v1 不做 Agent / AI、remote / SSH、cloud sync、协作或插件生态。

Command Center 的执行入口是 `docs/tasks/command-center/`。任务从 `T-300` 起步，
按完整任务文档执行，不沿用旧 Hyper-like phase 编号。

### CC0: 规划和任务包入库

目标：

- 把 Command Center 作为并行产品线写入路线图。
- 建立 `docs/tasks/command-center/` 任务目录。
- 写完整 `T-300` 到 `T-322` 任务文档。

完成条件：

- `docs/ROADMAP.md` 说明 Command Center 和现有 `M1-M5` 的并行关系。
- 任务目录 README 可作为执行入口。
- 所有 Command Center 任务都有 Goal、Scope、Non-goals、Files In Scope、Functional Acceptance、Verification Commands、Manual QA、Done When 和 Risks / Follow-ups。

### CC1: Command Lifecycle 数据基座

目标：

- 建立 feature flags、command invocation lifecycle、shell hook adapter 和降级状态。
- 后续 Search、Blocks、Command Bar 不重复解析 raw shell hook。

任务范围：

- `T-301` 到 `T-304`

完成条件：

- Command Center 默认全部关闭。
- lifecycle 模型可表达 running、succeeded、failed、unknown。
- shell integration 关闭或 hook 缺失时返回明确 unavailable reason。

### CC2: History Repository 和 Search Index

目标：

- 建立 session-local history、global history、privacy filter、query parser 和 search ranking。

任务范围：

- `T-305` 到 `T-309`

完成条件：

- 命令可在 session 内即时检索。
- global history 可安全 roundtrip。
- sensitive command 不保存。
- ranking 支持 recency、cwd、status 和 frequency。

### CC3: `Ctrl-R` Command Search Overlay

目标：

- 提供显式 `Ctrl-R` 搜索入口。
- 默认插入结果，不自动执行。

任务范围：

- `T-310` 到 `T-312`

完成条件：

- `Ctrl-R` 打开 overlay。
- `Enter` 只插入命令。
- 显式执行经过 read-only、paste 和 shortcut safety。

### CC4: Command Blocks Range 和 Actions MVP

目标：

- 建立 command block range、导航、actions reducer 和 action wiring。

任务范围：

- `T-313` 到 `T-316`

完成条件：

- output range 不串命令。
- previous/next/failed block 可导航。
- copy output、re-input、rerun 走统一 action pipeline。

### CC5: Command Bar、Context Chips 和 Mode Router

目标：

- 产品化输入体验，同时保持 terminal-first。

任务范围：

- `T-317` 到 `T-319`

完成条件：

- 普通文本仍默认进 shell。
- Context chips 只展示 terminal-safe 状态。
- mode switching 必须显式触发。

### CC6: Sticky Header、Review 接入和验证收口

目标：

- 补齐长输出 block 的 sticky header、Review / Instant Replay entrypoints 和验证门。

任务范围：

- `T-320` 到 `T-322`

完成条件：

- sticky header 不影响 scrollback 和复制。
- review 入口复用 Instant Replay，不共享 live terminal 的可写 input controller。
- 自动化、手工、性能和 stop condition 验证门写入任务文档。
```

- [ ] **Step 2: Verify roadmap section exists**

Run:

```bash
rg -n "Command Center 并行产品线|CC0: 规划和任务包入库|CC6: Sticky Header" docs/ROADMAP.md
```

Expected: all three strings are found.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/ROADMAP.md
git commit -m "Document command center roadmap track"
```

Expected: commit succeeds with only `docs/ROADMAP.md`.

### Task 2: Create Command Center Task Directory README

**Files:**
- Create: `docs/tasks/command-center/README.md`

- [ ] **Step 1: Create README**

Create `docs/tasks/command-center/README.md` with this content:

```markdown
# Command Center Tasks

Command Center 是并行产品线，不替换 `docs/ROADMAP.md` 里的 `M1-M5`。本目录是
Command Center 的任务执行入口。

## 全局护栏

- 普通输入默认发给 shell。
- 不做自然语言自动识别。
- 不重写 terminal renderer。
- 不把产品 UI 下沉到 `packages/ianvs_terminal`。
- 不绕过 read-only、paste confirmation、shortcut isolation 或 terminal input policy。
- v1 不做 Agent / AI、remote / SSH、cloud sync、协作或插件生态。

## 执行阶段

- `CC0`：规划和任务包入库。
- `CC1`：command lifecycle 数据基座。
- `CC2`：history repository 和 search index。
- `CC3`：`Ctrl-R` command search overlay。
- `CC4`：command blocks range 和 actions MVP。
- `CC5`：command bar、context chips、mode router。
- `CC6`：sticky header、review 接入、验证收口。

## 任务依赖

Foundation lane:

```text
T-300 -> T-301 -> T-302 -> T-303 -> T-304
```

History/Search lane:

```text
T-305 -> T-306 -> T-307 -> T-308 -> T-309 -> T-310 -> T-311 -> T-312
```

Blocks lane:

```text
T-313 -> T-314 -> T-315 -> T-316 -> T-320 -> T-321
```

Command Bar lane:

```text
T-317 -> T-318 -> T-319
```

Verification lane:

```text
T-322
```

`T-322` 贯穿全程，但作为收口任务沉淀自动化、手工、性能和 stop condition 验证门。

## 任务索引

- [T-300 Command Center Track Intake](T-300-command-center-track-intake.md)
- [T-301 Command Center Feature Flags](T-301-command-center-feature-flags.md)
- [T-302 Command Invocation Lifecycle Model](T-302-command-invocation-lifecycle-model.md)
- [T-303 Shell Hook Lifecycle Adapter](T-303-shell-hook-lifecycle-adapter.md)
- [T-304 Command Lifecycle Degraded State](T-304-command-lifecycle-degraded-state.md)
- [T-305 Session Command History Buffer](T-305-session-command-history-buffer.md)
- [T-306 Global Command History Repository](T-306-global-command-history-repository.md)
- [T-307 Command History Privacy Filter](T-307-command-history-privacy-filter.md)
- [T-308 Command Search Query Parser](T-308-command-search-query-parser.md)
- [T-309 Command Search Index Ranking](T-309-command-search-index-ranking.md)
- [T-310 Command Search Overlay Controller](T-310-command-search-overlay-controller.md)
- [T-311 Command Search Overlay Widget](T-311-command-search-overlay-widget.md)
- [T-312 Command Search Insert Execute Safety](T-312-command-search-insert-execute-safety.md)
- [T-313 Command Block Range Model](T-313-command-block-range-model.md)
- [T-314 Command Block Navigation](T-314-command-block-navigation.md)
- [T-315 Command Block Actions Reducer](T-315-command-block-actions-reducer.md)
- [T-316 Command Block Action Wiring](T-316-command-block-action-wiring.md)
- [T-317 Command Bar Editor](T-317-command-bar-editor.md)
- [T-318 Command Center Context Chips](T-318-command-center-context-chips.md)
- [T-319 Command Center Mode Router](T-319-command-center-mode-router.md)
- [T-320 Sticky Command Header](T-320-sticky-command-header.md)
- [T-321 Command Review Entrypoints](T-321-command-review-entrypoints.md)
- [T-322 Command Center Verification Gates](T-322-command-center-verification-gates.md)
```

- [ ] **Step 2: Verify README links**

Run:

```bash
rg -n "T-300|T-322|全局护栏|任务依赖" docs/tasks/command-center/README.md
```

Expected: all searched terms are present.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/tasks/command-center/README.md
git commit -m "Add command center task index"
```

Expected: commit succeeds with only the README.

### Task 3: Create Foundation Task Documents

**Files:**
- Create: `docs/tasks/command-center/T-300-command-center-track-intake.md`
- Create: `docs/tasks/command-center/T-301-command-center-feature-flags.md`
- Create: `docs/tasks/command-center/T-302-command-invocation-lifecycle-model.md`
- Create: `docs/tasks/command-center/T-303-shell-hook-lifecycle-adapter.md`
- Create: `docs/tasks/command-center/T-304-command-lifecycle-degraded-state.md`

- [ ] **Step 1: Write the five task documents**

Use the global task sections and the payloads for `T-300` through `T-304`. Each file must include all required sections and must link verification references to `../../TESTING.md`.

- [ ] **Step 2: Verify required sections**

Run:

```bash
for f in docs/tasks/command-center/T-30{0,1,2,3,4}-*.md; do
  rg -q "^## Goal$" "$f" &&
  rg -q "^## Scope$" "$f" &&
  rg -q "^## Non-goals$" "$f" &&
  rg -q "^## Files In Scope$" "$f" &&
  rg -q "^## Functional Acceptance$" "$f" &&
  rg -q "^## Verification Commands$" "$f" &&
  rg -q "^## Manual QA$" "$f" &&
  rg -q "^## Done When$" "$f" &&
  rg -q "^## Risks / Follow-ups$" "$f" || exit 1
done
```

Expected: exit code 0.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/tasks/command-center/T-30{0,1,2,3,4}-*.md
git commit -m "Add command center foundation tasks"
```

Expected: commit succeeds with five task files.

### Task 4: Create History And Search Task Documents

**Files:**
- Create: `docs/tasks/command-center/T-305-session-command-history-buffer.md`
- Create: `docs/tasks/command-center/T-306-global-command-history-repository.md`
- Create: `docs/tasks/command-center/T-307-command-history-privacy-filter.md`
- Create: `docs/tasks/command-center/T-308-command-search-query-parser.md`
- Create: `docs/tasks/command-center/T-309-command-search-index-ranking.md`
- Create: `docs/tasks/command-center/T-310-command-search-overlay-controller.md`
- Create: `docs/tasks/command-center/T-311-command-search-overlay-widget.md`
- Create: `docs/tasks/command-center/T-312-command-search-insert-execute-safety.md`

- [ ] **Step 1: Write the eight task documents**

Use the global task sections and the payloads for `T-305` through `T-312`. Ensure `T-311` and `T-312` contain Manual QA because they touch UI, shortcuts, IME, and command execution safety.

- [ ] **Step 2: Verify search lane coverage**

Run:

```bash
rg -n "Ctrl-R|Enter|read-only|IME|privacy|ranking|session-local|global history" docs/tasks/command-center/T-30{5,6,7,8,9}-*.md docs/tasks/command-center/T-31{0,1,2}-*.md
```

Expected: search terms appear across the history/search task files.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/tasks/command-center/T-30{5,6,7,8,9}-*.md docs/tasks/command-center/T-31{0,1,2}-*.md
git commit -m "Add command center history search tasks"
```

Expected: commit succeeds with eight task files.

### Task 5: Create Blocks Task Documents

**Files:**
- Create: `docs/tasks/command-center/T-313-command-block-range-model.md`
- Create: `docs/tasks/command-center/T-314-command-block-navigation.md`
- Create: `docs/tasks/command-center/T-315-command-block-actions-reducer.md`
- Create: `docs/tasks/command-center/T-316-command-block-action-wiring.md`
- Create: `docs/tasks/command-center/T-320-sticky-command-header.md`
- Create: `docs/tasks/command-center/T-321-command-review-entrypoints.md`

- [ ] **Step 1: Write the six task documents**

Use the global task sections and the payloads for `T-313`, `T-314`, `T-315`, `T-316`, `T-320`, and `T-321`. Ensure UI or runtime-adjacent tasks include Manual QA.

- [ ] **Step 2: Verify block lane coverage**

Run:

```bash
rg -n "output range|copy output|re-input|rerun|sticky header|Instant Replay|read-only|scrollback" docs/tasks/command-center/T-31{3,4,5,6}-*.md docs/tasks/command-center/T-32{0,1}-*.md
```

Expected: searched concepts appear across block task files.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/tasks/command-center/T-31{3,4,5,6}-*.md docs/tasks/command-center/T-32{0,1}-*.md
git commit -m "Add command center block tasks"
```

Expected: commit succeeds with six task files.

### Task 6: Create Command Bar And Verification Task Documents

**Files:**
- Create: `docs/tasks/command-center/T-317-command-bar-editor.md`
- Create: `docs/tasks/command-center/T-318-command-center-context-chips.md`
- Create: `docs/tasks/command-center/T-319-command-center-mode-router.md`
- Create: `docs/tasks/command-center/T-322-command-center-verification-gates.md`

- [ ] **Step 1: Write the four task documents**

Use the global task sections and the payloads for `T-317`, `T-318`, `T-319`, and `T-322`. Ensure `T-317`, `T-318`, and `T-322` contain Manual QA.

- [ ] **Step 2: Verify command bar and gates coverage**

Run:

```bash
rg -n "terminal-first|Shift\\+Enter|context chips|mode router|IME|paste|shortcut|stop condition|performance" docs/tasks/command-center/T-31{7,8,9}-*.md docs/tasks/command-center/T-322-command-center-verification-gates.md
```

Expected: searched concepts appear across the command bar and verification files.

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/tasks/command-center/T-31{7,8,9}-*.md docs/tasks/command-center/T-322-command-center-verification-gates.md
git commit -m "Add command center command bar verification tasks"
```

Expected: commit succeeds with four task files.

### Task 7: Documentation Completeness Review

**Files:**
- Inspect: `docs/ROADMAP.md`
- Inspect: `docs/tasks/command-center/README.md`
- Inspect: `docs/tasks/command-center/T-300-command-center-track-intake.md` through `docs/tasks/command-center/T-322-command-center-verification-gates.md`

- [ ] **Step 1: Count task files**

Run:

```bash
find docs/tasks/command-center -maxdepth 1 -type f -name 'T-3*.md' | sort | wc -l
```

Expected: `23`.

- [ ] **Step 2: Verify there are no placeholder markers**

Run:

```bash
rg -n "TB[D]|T[O]DO|FIXM[E]|待[定]|占[位]|implement[ ]later|fill[ ]in[ ]details" docs/ROADMAP.md docs/tasks/command-center
```

Expected: no matches and exit code 1.

- [ ] **Step 3: Verify required sections on all task files**

Run:

```bash
for f in docs/tasks/command-center/T-3*.md; do
  rg -q "^## Goal$" "$f" &&
  rg -q "^## Scope$" "$f" &&
  rg -q "^## Non-goals$" "$f" &&
  rg -q "^## Files In Scope$" "$f" &&
  rg -q "^## Functional Acceptance$" "$f" &&
  rg -q "^## Verification Commands$" "$f" &&
  rg -q "^## Manual QA$" "$f" &&
  rg -q "^## Done When$" "$f" &&
  rg -q "^## Risks / Follow-ups$" "$f" || {
    echo "Missing required section in $f"
    exit 1
  }
done
```

Expected: exit code 0.

- [ ] **Step 4: Verify all README links target existing files**

Run:

```bash
for target in $(rg -o "T-3[0-9][0-9][^)]*\\.md" docs/tasks/command-center/README.md); do
  test -f "docs/tasks/command-center/$target" || {
    echo "Missing $target"
    exit 1
  }
done
```

Expected: exit code 0.

- [ ] **Step 5: Commit any review fixes**

If files changed during review, run:

```bash
git add docs/ROADMAP.md docs/tasks/command-center
git commit -m "Polish command center task package"
```

Expected: commit succeeds only if review fixes were needed. If no files changed, skip this commit.
