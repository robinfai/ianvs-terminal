# T-139 Action Error Diagnostics

## Goal

把 runtime controller 记录的 external executor error 转成稳定用户可见诊断，为后续 command menu / action menu UI 展示失败原因做准备。

## Scope

- `example/lib/features/shell/shell_action_error_diagnostics.dart`
- `example/test/shell/shell_action_error_diagnostics_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接 UI
- 不定义重试策略
- 不处理平台特定错误类型
- 不改变 controller 错误捕获行为
- 不新增 action

## Current Progress

- 已新增 `ShellActionErrorDiagnostic`。
- 已新增 `ShellActionErrorDiagnostics.fromExternalExecutorError()`。
- null error 返回 null。
- 非 null error 会转成 title/description。
- 已补充 null 和 error formatting 测试。

## Functional Acceptance

- external executor error 有稳定诊断标题。
- external executor error 描述包含原始错误信息。
- 无错误时不产生诊断。
- 后续 UI 可直接消费 diagnostic。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/shell/shell_action_error_diagnostics_test.dart
flutter analyze
```

## Manual QA

本任务只新增诊断模型；无需人工 UI 验收。

## Done When

- External side-effect error 可被 UI 转成用户可见文案。
- ShellScreen 接入真实 handler 后有错误展示基础。

## Risks / Follow-ups

- 后续需要为权限、文件写入、通知失败等错误建立更细粒度类型。
- 错误文案应避免泄露敏感路径或命令内容。
