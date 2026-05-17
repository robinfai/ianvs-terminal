# T-092 Shell Productivity Recent Items

## Goal

补齐 P3 recent commands / recent directories 的产品状态模型，让 shell integration 后续可以把命令历史和目录跳转能力映射到统一数据结构。

## Scope

- `example/lib/features/productivity/shell_productivity_models.dart`
- `example/test/productivity/shell_productivity_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入真实 shell integration event stream
- 不实现 command palette UI
- 不落盘 recent items
- 不实现 remote directory
- 不启动新 shell session

## Current Progress

- 已新增 `ShellRecentCommandEntry`。
- 已新增 `ShellRecentDirectoryEntry`。
- 已新增 `ShellRecentItemsState`。
- recent items 支持 newest-first、去重和 limit trimming。
- command entry 可表达 exitCode 和 succeeded 状态。
- 已补充 recent command/directory 去重与 limit 测试。

## Functional Acceptance

- recent commands 保留最新唯一项。
- recent directories 保留最新唯一项。
- recent items 能按 limit 截断。
- command entry 可以表达成功/失败状态。
- 模型不表达 remote directory 或 SSH session。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/productivity/shell_productivity_models_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯模型，不接入 UI；无需人工 UI 验收。

## Done When

- P3 recent commands/directories 的状态语义可复用。
- 后续 shell integration event adapter 不需要重新定义 recent items 逻辑。

## Risks / Follow-ups

- 后续需要定义 recent items 的落盘策略和隐私边界。
- 后续需要接入 command palette 或 recent directory picker。
