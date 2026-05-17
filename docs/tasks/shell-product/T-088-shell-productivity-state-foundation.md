# T-088 Shell Productivity State Foundation

## Goal

建立 P3 shell productivity 的状态模型，覆盖 shell integration feature gates、prompt navigation、command output range、recent directories 和 read-only guard 的基础语义。

## Scope

- `example/lib/features/productivity/shell_productivity_models.dart`
- `example/test/productivity/shell_productivity_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P3_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入真实 shell integration event stream
- 不接入 terminal viewport selection
- 不改 paste runtime
- 不实现搜索 UI
- 不新增 remote/SSH command model

## Current Progress

- 已新增 `ShellIntegrationFeatureSet`。
- 已新增 `ShellPromptMark`。
- 已新增 `ShellCommandOutputRange`。
- 已新增 `ShellProductivityState`。
- prompt navigation、command output range、recent directory 和 read-only guard 已有纯模型表达。
- shell integration disabled 时相关高级能力会降级为不可用。

## Functional Acceptance

- prompt marks 可查找 previous/next prompt。
- shell integration disabled 时 prompt navigation 不可用。
- command output range 可取最后一个有效范围。
- read-only mode 禁止 send text 和 paste。
- recent directories 在 feature disabled 时不可用。

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

- P3 的 prompt navigation、command output selection、recent directory 和 read-only guard 有可复用状态模型。
- 后续 runtime 接入可以只映射 shell integration events，不重定义产品语义。

## Risks / Follow-ups

- 后续需要接入真实 shell hook events。
- 后续需要把 disabled action 原因暴露到 command palette 或 action surface。
