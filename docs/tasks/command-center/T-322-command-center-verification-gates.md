# T-322 Command Center Verification Gates

## Goal

沉淀 Command Center 的自动化、手工、性能和 stop condition 验证门。

## Scope

- 汇总 Command Center 各 lane 的最小自动化命令。
- 定义输入、IME、paste、read-only、shortcut、scroll、renderer 和 review 隔离的人工 QA。
- 定义 `Ctrl-R` 与 command input 的 focus handoff，以及 command block 模式下文本插入权的验证门。
- 定义 search index 和 sticky header 的性能门。
- 记录 stop conditions，出现时必须停止并修复。

## Non-goals

- 不实现任何 Command Center 功能。
- 不替代各实现任务自己的测试。
- 不降低 `docs/TESTING.md` 的默认验证要求。
- 不把失败 gate 写成通过。
- 不跳过 GUI、terminal、输入法、滚动、复制粘贴等人工检查。

## Files In Scope

- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- 必要时更新 `docs/TESTING.md`
- 必要时更新 `docs/KNOWN_ISSUES.md`

## Functional Acceptance

- Foundation lane 有模型和 adapter 的最小测试命令。
- History/Search lane 有 parser、index、overlay 和 insert/execute safety 的最小测试命令。
- Blocks lane 有 range、navigation、actions、sticky header 和 review entrypoints 的最小测试命令。
- Command Bar lane 有 editor、context chips 和 mode router 的最小测试命令。
- Manual QA 覆盖 `Ctrl-R`、read-only、IME、paste、shortcut、scrollback、copy output、sticky header、Instant Replay review 和 alt-buffer / pager。
- Manual QA 和 stop conditions 覆盖 `Ctrl-R` 焦点切换、command input 唯一写入口，以及旧版历史浮层文案或重复 `cwd/history` 入口的清理。
- Performance gates 覆盖 10k history search、长输出 block creation、sticky header 可见范围计算和 context chip update debounce。

## Command Center Verification Gate

Command Center 的默认原则是 terminal-first：普通输入先归 shell，增强 UI 只有在显式入口或显式 shortcut 下接管输入。后续任务引用本 gate 时，不能把这里的自动化、人工 QA、性能门或 stop condition 降级成“可选”。

## Automated Gates

通用 focused gate：

```bash
cd example
flutter analyze
flutter test test/config/local_terminal_config_models_test.dart test/command_center test/shell/instant_replay_store_test.dart test/shell/shell_command_action_search_adapter_test.dart
```

Foundation lane 最小命令：

```bash
cd example
flutter test \
  test/config/local_terminal_config_models_test.dart \
  test/command_center/command_center_feature_flags_test.dart \
  test/command_center/command_invocation_models_test.dart \
  test/command_center/shell_hook_lifecycle_adapter_test.dart \
  test/command_center/command_center_runtime_test.dart \
  test/command_center/command_center_shell_event_wiring_test.dart \
  test/command_center/command_lifecycle_degraded_state_test.dart
```

History/Search lane 最小命令：

```bash
cd example
flutter test \
  test/command_center/session_command_history_buffer_test.dart \
  test/command_center/global_command_history_repository_test.dart \
  test/command_center/command_history_persistence_wiring_test.dart \
  test/command_center/command_history_privacy_filter_test.dart \
  test/command_center/command_search_query_parser_test.dart \
  test/command_center/command_search_index_test.dart \
  test/command_center/command_search_overlay_controller_test.dart \
  test/command_center/command_search_overlay_test.dart \
  test/command_center/command_search_insert_execute_safety_test.dart \
  test/command_center/command_search_shell_wiring_test.dart
```

Blocks lane 最小命令：

```bash
cd example
flutter test \
  test/command_center/command_block_models_test.dart \
  test/command_center/command_block_navigation_test.dart \
  test/command_center/command_block_action_reducer_test.dart \
  test/command_center/sticky_command_header_test.dart \
  test/command_center/command_review_entrypoints_test.dart \
  test/shell/instant_replay_store_test.dart
```

Command Bar lane 最小命令：

```bash
cd example
flutter test \
  test/command_center/command_bar_editor_test.dart \
  test/command_center/command_center_context_wiring_test.dart \
  test/command_center/context_chips_test.dart \
  test/command_center/command_center_mode_router_test.dart \
  test/command_center/saved_command_repository_test.dart \
  test/command_center/command_action_search_index_test.dart \
  test/command_center/command_action_search_controller_test.dart \
  test/command_center/command_action_search_shell_wiring_test.dart \
  test/command_center/command_action_search_overlay_test.dart \
  test/shell/shell_command_action_search_adapter_test.dart \
  test/shell/terminal_action_registry_test.dart
flutter test test/widget_test.dart --plain-name "ordinary slash key does not open action search overlay"
flutter test test/widget_test.dart --plain-name "command menu opens action search overlay without shell write"
flutter test test/widget_test.dart --plain-name "action search updates saved command usage after insert"
flutter test test/widget_test.dart --plain-name "action search can run toggle read only without shell write"
flutter test test/widget_test.dart --plain-name "action search can open toolbelt without shell write"
flutter test test/widget_test.dart --plain-name "action search can open paste history without shell write"
flutter test test/widget_test.dart --plain-name "action search can open advanced paste without shell write"
flutter test test/widget_test.dart --plain-name "action search can open copy mode without shell write"
flutter test test/widget_test.dart --plain-name "action search can open captured output without shell write"
flutter test test/widget_test.dart --plain-name "action search can open annotations without shell write"
flutter test test/widget_test.dart --plain-name "action search can open shell integration without shell write"
flutter test test/widget_test.dart --plain-name "action search can open tmux integration without shell write"
flutter test test/widget_test.dart --plain-name "action search can open coprocess without shell write"
flutter test test/widget_test.dart --plain-name "action search can open password manager without shell write"
flutter test test/widget_test.dart --plain-name "action search can open instant replay without shell write"
flutter test test/widget_test.dart --plain-name "action search can select command output without shell write"
flutter test test/widget_test.dart --plain-name "action search can copy selection without shell write"
flutter test test/widget_test.dart --plain-name "action search can copy command output without shell write"
flutter test test/widget_test.dart --plain-name "action search can open theme picker without shell write"
flutter test test/widget_test.dart --plain-name "action search can toggle command-finished notifications without shell write"
flutter test test/widget_test.dart --plain-name "action search can toggle bell notifications without shell write"
flutter test test/widget_test.dart --plain-name "action search can toggle activity monitor without shell write"
flutter test test/widget_test.dart --plain-name "action search can split right without shell write"
flutter test test/widget_test.dart --plain-name "action search can split down without shell write"
flutter test test/widget_test.dart --plain-name "action search can zoom pane without shell write"
flutter test test/widget_test.dart --plain-name "action search can apply two-pane layout without shell write"
flutter test test/widget_test.dart --plain-name "action search can reopen closed tab without shell write"
flutter test test/widget_test.dart --plain-name "action search can explain unavailable diagnostics export"
flutter test test/widget_test.dart --plain-name "action search can export scrollback without shell write"
flutter test test/widget_test.dart --plain-name "action search can explain unavailable clear scrollback without shell write"
flutter test test/widget_test.dart --plain-name "action search can explain unavailable recent directory without shell write"
flutter test test/widget_test.dart --plain-name "action search can focus next pane without shell write"
flutter test test/widget_test.dart --plain-name "action search can focus previous pane without shell write"
flutter test test/widget_test.dart --plain-name "action search can swap pane without shell write"
flutter test test/widget_test.dart --plain-name "action search can resize pane without shell write"
flutter test test/widget_test.dart --plain-name "action search can close pane without shell write"
flutter test test/widget_test.dart --plain-name "action search can reopen closed pane without shell write"
flutter test test/widget_test.dart --plain-name "action search can close active tab without shell write"
flutter test test/widget_test.dart --plain-name "action search can duplicate current cwd into new tab"
flutter test test/widget_test.dart --plain-name "action search can paste clipboard text into shell"
flutter test test/widget_test.dart --plain-name "action search can move to next search match without shell write"
flutter test test/widget_test.dart --plain-name "action search can move to previous search match without shell write"
flutter test test/widget_test.dart --plain-name "action search can clear shell search without shell write"
flutter test test/widget_test.dart --plain-name "action search explains unavailable command block actions without shell write"
flutter test test/widget_test.dart --plain-name "action search can copy block output without shell write"
flutter test test/widget_test.dart --plain-name "action search prefers selected block over newest block without shell write"
flutter test test/widget_test.dart --plain-name "action search can save block output without shell write"
flutter test test/widget_test.dart --plain-name "action search can open block output in review without shell write"
flutter test test/widget_test.dart --plain-name "action search can open scoped search for an active command block"
flutter test test/widget_test.dart --plain-name "action search can reinput and rerun an active command block"
flutter test test/widget_test.dart --plain-name "action search explains unavailable remaining visual workspace actions without shell write"
flutter test test/shell/shell_command_action_search_adapter_test.dart --plain-name "adds terminal theme preset actions with encoded theme ids"
flutter test test/widget_test.dart --plain-name "action search can apply terminal theme preset without shell write"
flutter test test/widget_test.dart --plain-name "context chip navigates to the last failed command block"
flutter test test/widget_test.dart --plain-name "selected block chip opens block actions without shell write"
flutter test test/widget_test.dart --plain-name "selected block chip can copy command and output together"
flutter test test/widget_test.dart --plain-name "selected block chip can save block output without shell write"
flutter test test/widget_test.dart --plain-name "selected block chip can open block output in review without shell write"
flutter test test/widget_test.dart --plain-name "selected block chip opens scoped search within block output"
flutter test test/widget_test.dart --plain-name "selected block chip can reinput and rerun block command"
```

Full example regression gate remains the default from `docs/TESTING.md`:

```bash
cd example
flutter analyze
flutter test
flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
```

## Manual QA Gate

Run this matrix after wiring Command Center UI into a real terminal surface. Record terminal profile, shell, macOS version, Flutter device, and whether shell integration is enabled.

| Area | Manual check | Pass condition |
| --- | --- | --- |
| Ctrl-R search | Press `Ctrl-R` from focused terminal, type a history query, arrow through results, press `Enter`, then `Esc`. | `Ctrl-R` opens command search; ordinary terminal text does not leak while search owns input; `Enter` inserts without auto-execute; `Esc` returns to terminal. |
| read-only | Enable read-only, then try command search insert, explicit execute, command bar send, block re-input, and block rerun. | No path writes to the shell; UI shows disabled or blocked reason not only color. |
| IME | Use Chinese IME in terminal, command search, and command bar; press `Enter` while composing. | Composition is not interrupted or sent as a command; `Enter` during composition is not stolen by Command Center. |
| paste | Insert or rerun a multiline command from search/block action; try normal paste and advanced paste. | Multiline text goes through paste policy; paste confirmation is not bypassed. |
| shortcut routing | Exercise `Ctrl-R`, command menu shortcut, search arrows, `Esc`, pane/tab shortcuts, and terminal app shortcuts. | Enhanced mode shortcuts are consumed only while active; ordinary text and unrelated shortcuts pass through according to terminal input policy. |
| scrollback | Run a long-output command and scroll up/down while command blocks and sticky header are enabled. | Current block header follows visible range, does not jump across blocks, and terminal scroll remains smooth. |
| copy output | Select/copy terminal text while context chips, sticky header, search, and block action UI are visible. | Copied text contains real terminal content only; overlay labels are not included. |
| sticky header | View succeeded, running, failed, and unknown command blocks. | Failed state includes `failed` or exit code text; cwd, exit code, and duration are readable by text/semantics, not only color. |
| alt-buffer / pager | Open `less`, `vim`, or another fullscreen/pager/alt-buffer app. | Sticky header is hidden or delayed; it must not show stale command context over fullscreen content. |
| Instant Replay review | From a command block, use `Replay from here` and `Open in Review`. | Replay starts near the relevant frame or row range; review source is read-only; live terminal continues and does not receive review input. |

## Performance Gates

These are stop conditions for profile/release checks on a quiet local machine. If a machine baseline already exists, compare against the latest passing baseline and stop on a regression larger than 2x.

| Gate | Scenario | Pass condition |
| --- | --- | --- |
| 10k history search | Build a 10k-entry command history with mixed cwd, status, timestamps, and repeated commands; type short and filtered queries. | p95 query-to-result update stays under 100 ms in profile/release and does not allocate enough to cause visible jank. |
| Long output block creation | Record at least 1k command blocks and a 10k-line output span with shell hook lifecycle events. | Block range creation and navigation use command metadata/ranges, not full renderer rewrites; scrolling remains responsive. |
| Sticky header visible range | Scroll through long output while sticky header resolves current block from visible row range. | Resolver uses visible range and block metadata; it must not scan all scrollback rows on every scroll tick. p95 resolve time stays under 2 ms for 1k blocks. |
| Context chip update debounce | Rapid cwd/profile/exit/selection/read-only updates while command output streams. | Chips update at most once per frame, never write to shell, and do not trigger layout overflow or terminal focus loss. |

## Stop Conditions

Stop implementation or release verification immediately and fix before continuing if any of these happen:

- Ordinary terminal text is captured by Command Center without an explicit entry or shortcut.
- Any read-only path writes to shell, inserts text, reruns a command, or bypasses paste policy.
- IME composition is interrupted, committed early, or interpreted as command execution.
- `Ctrl-R`, `Esc`, arrow keys, or command menu shortcut leak to shell while their enhanced mode owns input.
- An inactive enhanced mode consumes ordinary text or unrelated terminal shortcuts.
- Search insert, saved command insert, command bar insert, or block re-input auto-executes without explicit execute intent.
- Multiline command insertion bypasses paste confirmation or advanced paste policy.
- Sticky header, context chips, search overlay, or review UI text appears in scrollback, terminal selection, copied output, or exported scrollback.
- Sticky header appears over alt-buffer, pager, or fullscreen app content with stale command context.
- Command block actions copy missing output ranges, use wrong block ranges, or lose failure exit code metadata.
- History search, sticky header, context chips, or block range creation scans full scrollback on every keypress/scroll tick.
- Review/Instant Replay shares a writable input controller with live terminal, pauses live terminal unintentionally, or routes review input into the live shell.
- Future Agent, saved command, or any natural-language mode is triggered by ordinary text instead of an explicit disabled/enabled entry.
- Any required automated command fails, hangs, or shows flaky behavior that cannot be explained and reproduced.

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。本任务是验证文档任务，最小验证为：

```bash
rg -n "Ctrl-R|focus|command input|read-only|IME|paste|shortcut|stop condition|performance|cwd/history" docs/tasks/command-center/T-322-command-center-verification-gates.md
```

## Manual QA

文档任务，无需 UI QA，但要人工检查以下验证门是否已写入：

- `Ctrl-R` 打开后搜索框自动 focus。
- `Enter` 回填后 focus 回到 command input。
- `Esc` 关闭后 focus 回到 command input。
- command block 模式下多行粘贴只能经过 command input。
- UI 中不再出现旧版历史浮层文案或重复的 `cwd/history` 入口。
- Search、Blocks、Command Bar、Review、输入安全和性能门没有遗漏。

## Done When

- 后续实现任务能引用同一验证门，而不是各自发明验收方式。
- 每个高风险输入/渲染/复制/滚动场景都有自动化或人工验证入口。
- stop conditions 清楚列出，不能被实现任务忽略。

## Risks / Follow-ups

- 真正跑 gate 的证据由各实现任务记录。
- 如果后续新增 Agent mode、diff review 或 saved commands，需要扩展本验证门。
- 性能阈值需要根据真实机器基线更新。
