# T-100 Shell Action Disabled Reason Copy

## Goal

给 action availability 的 disabled reason 增加稳定用户可见文案入口，让后续 command palette、action menu 和配置 warning UI 可以复用同一套不可用原因说明。

## Scope

- `example/lib/features/shell/shell_action_availability.dart`
- `example/test/shell/shell_action_availability_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`
- `docs/LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 command palette UI
- 不实现 toast/banner 展示
- 不改变 action availability 判定
- 不改变 shortcut dispatch
- 不新增 remote/SSH 诊断

## Current Progress

- 已给 `ShellActionDisabledReason` 增加 title。
- 已给 `ShellActionDisabledReason` 增加 description。
- 文案覆盖 active session、shell integration、read-only、command output、recent directory。
- 已补充 disabled reason 文案测试。

## Functional Acceptance

- 每个 disabled reason 都有稳定 title。
- 每个 disabled reason 都有稳定 description。
- read-only、missing recent directory 等原因可以被 UI 直接展示。
- 文案不把 remote/SSH 作为恢复路径。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_availability_test.dart
flutter analyze
```

## Manual QA

本任务只新增诊断文案模型，不接入 UI；无需人工 UI 验收。

## Done When

- 后续 command palette/action menu 可以显示 disabled reason，而不用各自硬编码说明。

## Risks / Follow-ups

- 后续接入 UI 时应优先使用这些 title/description，避免多处文案漂移。
