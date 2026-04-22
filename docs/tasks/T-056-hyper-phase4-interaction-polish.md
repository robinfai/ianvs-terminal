# T-056 Hyper-like Phase 4 Interaction Polish

## Goal

在既有 terminal 合同不变的前提下，落地 Hyper-like `Phase 4` 的 interaction polish：只改 shell/UI 表达，让 session lifecycle、focus transition 和行为反馈更清晰、更完整。

## Scope

- `app/lib/features/shell/`
- `app/test/shell/`
- `app/test/widget_test.dart`
- `app/integration_test/flutterm_smoke_test.dart`
- `app/test/sessions/session_controller_test.dart`
  - 仅在实现直接消费 session lifecycle state 时才纳入
- `docs/TESTING.md`
- `docs/tasks/T-056-hyper-phase4-interaction-polish.md`

## Non-goals

- 不改 Rust core / PTY / FFI
- 不改 terminal input / selection / copy-paste / scroll / resize / host-feature 语义
- 不扩展到 settings IA、renderer、SSH、cross-platform 或 broader customization
- 不激活 `defaultProfileId` deprecation review
- 不把 `T-055 forced-closed` 留下的 manual-matrix 风险伪装成“已验证完成”
- 不吸收任何与本 phase 无关的问题；发现后直接拆 focused task

## Functional Acceptance

- `session start / exit presentation` 更清晰，但不改变 session lifecycle contract
- `focus transition clarity` 更强，尤其是 launcher close、dialog close、tab close、empty-state recovery 等路径
- `behavior-preserving feedback` 更完整、更一致，但不引入新命令面、持久化状态或后台流

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/widget_test.dart
flutter test test/shell/shell_screen_phase2a_test.dart
flutter test test/shell/shell_screen_phase2b_test.dart
flutter test integration_test/flutterm_smoke_test.dart
```

若实现直接消费 session lifecycle state，追加：

```bash
cd /Users/robinfai/personal/flutterm/app
flutter test test/sessions/session_controller_test.dart
```

## Manual QA

1. session start -> active state
2. launcher open/close -> focus return
3. defaults/dialog close -> terminal viewport regain focus
4. tab close / shell exit -> empty-state transition
5. empty-state -> `New Tab` recovery
6. `pwd`、`echo hello`、`ls`、copy/paste、scroll、resize 的 keyboard-heavy smoke 继续符合当前行为

## Done When

- `T-056` 范围内的三个 Phase 4 polish slice 已完成
- protected regression baseline 通过
- 若 shell verification wording 有变化，`docs/TESTING.md` 已同步
- 没有把 `defaultProfileId` review 或 `T-055 forced-closed` 的未完成 manual-matrix 风险吸收入本任务

## Risks / Follow-ups

- `defaultProfileId` deprecation review 继续 parked，等 `T-056` 完成或明确不再阻塞后再激活
- 若 Phase 4 实施中发现非本 phase 的问题，拆 focused task，不吸收入 `T-056`
