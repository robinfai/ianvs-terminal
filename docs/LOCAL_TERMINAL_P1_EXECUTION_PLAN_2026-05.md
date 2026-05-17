# P1 Execution Plan: Action And Config Foundation

## Objective

把 action registry、keybinding、config schema、配置迁移和冲突诊断收口成后续 workspace/productivity 能复用的基础设施。

## Current Baseline

- `T-077-shell-profile-sheets-extraction` 已完成，Profiles / Dynamic Profiles surface 已从 `ShellScreen` 抽离。
- `T-078-action-registry-foundation` 已完成，`TerminalActionId` 与 `ShellActionRegistry` 骨架已建立。
- `T-079-action-keybinding-metadata-foundation` 已推进，registry descriptor 已能承载 default keybinding metadata、input policy 和默认冲突诊断入口。
- `T-080-local-terminal-config-schema-foundation` 已推进，LocalTerminalConfig schema 已覆盖 keybindings/workspace/clipboard/paste/shellIntegration/notifications/hotkeyWindow 的最小本地配置边界，并拒绝 remote-only 顶层字段。
- `T-081-local-terminal-config-repository-migration` 已推进，独立 `flutterm_config.json` repository 与 legacy app preferences migration adapter 已建立。
- `T-082-local-terminal-keybinding-resolver` 已推进，registry defaults 与 LocalTerminalConfig disabled/override 能合成为 resolved keybinding，并可诊断最终冲突。
- `T-083-shell-shortcut-registry-dispatch` 已推进，`ShellScreen` 的 shortcut dispatch 开始消费 registry/resolver 默认 keybinding metadata。
- `T-095-planned-action-id-expansion` 已推进，P2-P5 的关键规划能力已有稳定 `TerminalActionId` 与 descriptor metadata。
- `T-098-shell-action-availability-diagnostics` 已推进，action disabled reason 已有统一诊断模型。
- `T-100-shell-action-disabled-reason-copy` 已推进，disabled reason 已有稳定 title/description 文案入口。
- `T-102-local-terminal-config-bootstrap-resolution` 已推进，local config、legacy app preferences、defaults 的 bootstrap 优先级已有 resolver。
- `T-108-shell-action-view-models` 已推进，command palette/action menu 已有可复用 view-model adapter。
- `T-114-shell-action-dispatcher` 已推进，workspace/productivity/policy reducers 已有统一 action dispatch 入口。
- `T-116-shell-action-side-effect-plan` 已推进，dispatcher result 已能映射成 UI/runtime side-effect plan。
- `T-117-shell-action-side-effect-executor` 已推进，side-effect plan 已有可注入 executor 协议。
- `T-118-shell-action-pipeline` 已推进，dispatcher、side-effect planner 和 executor 已组合成单入口 pipeline。
- `T-119-shell-action-runtime-controller` 已推进，action pipeline 已有可持有状态的 runtime controller。
- `T-120-shell-command-menu-adapter` 已推进，command menu 已有 action view-model + runtime controller adapter。
- `T-121-shell-command-menu-model` 已推进，现有 command menu action order 已抽成可复用模型。
- `T-122-local-terminal-key-event-resolver` 已推进，key event snapshot 可通过 resolved keybinding 映射到 action id。
- `T-123-shell-shortcut-bridge` 已推进，平台 shortcut modifier 与 LocalTerminalKeybindingsConfig 可解析为 action id。
- `T-124-local-terminal-config-loader` 已推进，local config 与 legacy app preferences 已有组合 loader。
- `T-125-local-config-preferences-adapter` 已推进，local config defaults/appearance 可映射到现有 app preferences 兼容形态。
- `T-136-shell-action-test-harness` 已推进，ShellScreen action pipeline 接入前已有 side-effect executor 测试 harness。
- `T-137-runtime-controller-external-executor-hook` 已推进，runtime controller 已可把 side-effect plan 转交给外部 executor。
- `T-138-runtime-controller-external-error-state` 已推进，external executor 失败可记录到 controller state。
- `T-139-action-error-diagnostics` 已推进，external executor error 可映射为用户可见诊断。
- `T-140-shell-command-menu-diagnostics` 已推进，command menu 可合成 disabled reason 与上次 action error。

## Preconditions

- P0 文档边界已冻结。
- 后续新增 action 不允许引入 SSH、remote、serial、SFTP 语义。

## Work Plan

1. TerminalActionId 收口
   - 为 Session、Pane、Clipboard、Search、Shell Integration、View、Profile、Monitor 分类建立稳定 action id。
   - 把 top-level menu、command palette、shortcut dispatcher 逐步接到 registry。
   - 为每个 action 标注 label、category、default keybinding、enabledWhen、terminalInputPolicy、palette visibility。

2. Keybinding model
   - 支持默认快捷键。
   - 支持用户覆盖。
   - 支持禁用默认快捷键。
   - 支持 scope：global、focused app、terminal focused、command palette open。
   - 支持消费策略：terminal first、app first、performable only。

3. Conflict diagnostics
   - 当两个 action 绑定同一个 scope/key 时，配置加载阶段产生可见诊断。
   - 冲突不得静默覆盖。
   - 冲突不得把 app action 泄漏到 terminal input。

4. LocalTerminalConfig schema
   - 定义 version、profiles、defaultProfileId、appearance、keybindings、workspace、clipboard、paste、shellIntegration、notifications、hotkeyWindow。
   - 明确优先级：built-in defaults、user config、profile override、session temporary state。
   - 明确热重载范围：theme/font/keybindings/notification policy 可热重载；program/args/env/cwd/emulation 只影响新 session。

5. Legacy config compatibility
   - 保持 `flutterm_profiles.json` 可读。
   - 保持 `flutterm_preferences.json` 可读。
   - 首次写入新 config 时保留旧文件 fallback。
   - schema 校验禁止 SSH/remote/serial/SFTP 顶层字段。

## Task Breakdown

1. `T-079`: keybinding default table and action metadata completion
2. `T-082`: keybinding override/disable/scope resolver
3. `T-082`: resolved conflict diagnostics
4. `T-080`: LocalTerminalConfig schema foundation
5. `T-081`: LocalTerminalConfig repository and migration adapter
6. `T-083`: shell shortcut dispatch consumes registry defaults
7. `T-095`: planned P2-P5 action id expansion
8. `T-098`: action availability and disabled diagnostics
9. `T-100`: disabled reason user-visible copy
10. `T-102`: legacy app preferences compatibility bootstrap resolver
11. `T-108`: action menu / command palette view-model adapter
12. `T-114`: unified shell action dispatcher
13. `T-116`: shell action side-effect planning
14. `T-117`: side-effect executor protocol
15. `T-118`: shell action pipeline
16. `T-119`: shell action runtime controller
17. `T-120`: shell command menu adapter
18. `T-121`: shell command menu model bridge
19. `T-122`: key event to resolved action bridge
20. `T-123`: shell shortcut bridge
21. `T-124`: local terminal config loader
22. `T-125`: local config to app preferences adapter
23. `T-136`: shell action side-effect test harness
24. `T-137`: runtime controller external executor hook
25. `T-138`: runtime controller external executor error state
26. `T-139`: action external error diagnostics
27. `T-140`: command menu diagnostics bundle
28. `T-next`: SessionController config bootstrap integration

## Acceptance Criteria

- 所有 top-level 菜单和 command palette 通过 action id 触发。
- 快捷键不直接调用 `ShellScreen` 私有方法。
- terminal 正在处理文本输入、IME composition、paste、selection drag 时，app action 不抢输入。
- keybinding 冲突有可见诊断。
- 旧配置文件仍能启动默认 shell。
- 新 schema 不包含 SSH、remote、serial、SFTP 顶层能力。

## Verification

- Unit tests
  - registry lookup、duplicate id、enabled predicate
  - keybinding default、override、disable、scope matching
  - conflict diagnostics
  - config migration and forbidden-field validation

- Widget tests
  - command palette/action menu 不向 terminal 输入字符
  - profiles/dynamic profiles action 可从 registry 触发
  - disabled action 有明确状态

- Integration/manual
  - 旧 profile/preferences 文件存在时仍能启动默认 local shell

## Exit Criteria

- P2/P3 可以只依赖 action id 和 config schema 扩展新能力，不需要继续修改基础 action/keybinding 边界。

## Risks

- 风险：过早做完整 DSL，拖慢 P2。
- 缓解：第一阶段只用 JSON schema，保留未来 TOML/YAML 入口但不实现。

- 风险：registry 扩展时破坏 terminal input protected contracts。
- 缓解：所有 input/focus/paste/selection 相关 action 必须带回归测试。

## Added foundation slice: T-140 Shell command menu diagnostics

Status: FOUNDATION. Added a UI-facing diagnostics aggregation layer for command menu disabled reasons and external executor failures. Remaining work: wire the diagnostics state into ShellScreen command menu rendering and verify with the relevant shell tests.

## Added foundation slice: T-141 Shell action runtime production bindings

Status: FOUNDATION. Added a structured production binding seam between `TerminalActionId` and UI/session callbacks. Remaining work: register real `ShellScreen` and `SessionController` handlers, then verify missing binding coverage for the user-facing action set.

## Added foundation slice: T-143 Shell action runtime binding audit

Status: FOUNDATION. Added a structured audit for required, missing, and unplanned production action bindings. Remaining work: define the supported production action set during ShellScreen wiring and require this audit to be clean before closing P1 production wiring.

## Added foundation slice: T-144 Shell action production action set

Status: FOUNDATION. Added a default required/optional production action set that resolves action names to `TerminalActionId` values and feeds the runtime binding audit. Remaining work: reconcile unknown planned names with the action registry and require a clean audit during ShellScreen/SessionController wiring.

## Added foundation slice: T-145 Shell action production binding builder

Status: FOUNDATION. Added a production binding builder that resolves action-name keyed UI/session callbacks into `ShellActionRuntimeBindings` and returns binding audit results. Remaining work: use this builder from the real ShellScreen wiring layer and make the audit clean for the required action set.

## Added foundation slice: T-146 Shell action production binding diagnostics

Status: FOUNDATION. Added blocking/advisory diagnostics for production binding build and audit results. Remaining work: render these diagnostics in the production wiring/debug UI and require zero blocking diagnostics before closing P1.

## Added foundation slice: T-147 Shell action production callbacks

Status: FOUNDATION. Added a typed callback contract for ShellScreen/SessionController production action handlers. Remaining work: populate these callbacks from real UI/session methods and require the resulting binding diagnostics to have zero blocking items.

## Added foundation slice: T-148 Shell action production wiring state

Status: FOUNDATION. Added a single wiring state that combines typed callbacks, runtime bindings, build/audit results, and blocking diagnostics. Remaining work: instantiate this state from real ShellScreen/SessionController callbacks and use readiness/diagnostics as the P1 production wiring closure gate.

## Added foundation slice: T-149 Shell action production executor

Status: FOUNDATION. Added a production executor that runs actions through the wiring state only when blocking diagnostics are clear and captures callback exceptions as platform failures. Remaining work: connect this executor to `ShellActionRuntimeController.run(..., externalExecutor: ...)` or the equivalent ShellScreen dispatch path.

## Added foundation slice: T-150 Shell action production runtime adapter

Status: FOUNDATION. Added an adapter from typed production callbacks into a runtime-facing external executor function that returns `ShellActionBindingResult`. Remaining work: connect the adapter to the actual ShellScreen/runtime dispatch path.

## Added foundation slice: T-151 Shell action production wiring report

Status: FOUNDATION. Added a JSON-compatible readiness/diagnostics report for production action wiring. Remaining work: render or persist this report from the real ShellScreen/runtime wiring path and require zero blocking report items before closing P1.

## Added foundation slice: T-152 Shell action production dispatch report

Status: FOUNDATION. Added a JSON-compatible report for individual production action dispatches, including readiness before dispatch and structured execution result fields. Remaining work: emit this report from the real ShellScreen/runtime dispatch path when production actions run.

## Added foundation slice: T-153 Shell action production audit snapshot

Status: FOUNDATION. Added a JSON-compatible audit snapshot that combines production wiring readiness and recent dispatch reports. Remaining work: persist or expose the snapshot from the real ShellScreen/runtime wiring path after production callbacks are connected.

## Added foundation slice: T-154 Shell action production closure manifest

Status: FOUNDATION. Added a closure manifest that requires production wiring readiness, passing tests, and passing static analysis before P1 action wiring can close. Remaining work: populate this manifest from real ShellScreen/runtime wiring and verified command output.

## Current implementation update

Status: WIRED / UNVERIFIED. T-230 records the current required P1 production
action baseline wired through `ShellScreen`, the production runtime adapter, the
typed callback surface, the required action set, and action-name resolver
aliases. T-239 makes this visible in completion diagnostics as
implemented-but-unverified evidence.

Remaining work: run formatting, static analysis, focused shell action tests,
widget/shortcut tests, and manual command-menu/shortcut checks. Any failure from
those gates should reopen a focused implementation task instead of changing this
plan to verified by assertion.
