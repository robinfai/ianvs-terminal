# T-097 Hotkey Window Failure State Model

## Goal

补齐 P4 hotkey window 的失败状态模型，确保 macOS 权限、平台不可用或 bridge 调用失败可以进入可见状态，而不是静默失败。

## Scope

- `example/lib/features/policies/local_terminal_policy_models.dart`
- `example/test/policies/local_terminal_policy_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P4_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不调用 `WindowBridge`
- 不请求系统权限
- 不打开真实 hotkey window
- 不接入 UI toast/banner
- 不新增平台适配代码

## Current Progress

- 已新增 `LocalTerminalHotkeyWindowFailureKind`。
- 已新增 `LocalTerminalHotkeyWindowFailure`。
- 已新增 `LocalTerminalHotkeyWindowState`。
- hotkey window state 可记录 visible 与 lastFailure。
- failure state 可被 UI 识别为 visible failure。
- 成功 toggle 会清除旧 failure。

## Functional Acceptance

- permission denied、platform unavailable、bridge error 都有可表达 failure kind。
- hotkey window 调用失败后 `hasVisibleFailure` 为 true。
- 成功 toggle 时旧 failure 被清除。
- 本任务不触发真实平台调用。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/policies/local_terminal_policy_models_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯模型，不接入 UI；无需人工 UI 验收。

## Done When

- P4 hotkey window failure state 有可复用模型。
- 后续 UI/runtime 接入时不能再静默吞掉 hotkey window 失败。

## Risks / Follow-ups

- 后续需要把 `WindowBridge.toggleHotkeyWindow()` 的异常映射到 failure kind。
- 后续需要定义 failure state 在 UI 中的展示位置。
