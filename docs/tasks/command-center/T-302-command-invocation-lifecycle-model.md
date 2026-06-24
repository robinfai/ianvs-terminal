# T-302 Command Invocation Lifecycle Model

## Goal

建立 command invocation lifecycle 的 app 层模型，为 history、search 和 blocks 共用。

## Scope

- 定义 command invocation、lifecycle state、status、duration、cwd、session 和 pane metadata。
- 表达 running、succeeded、failed、unknown 状态。
- 提供后续 reducer、repository、search index 和 block model 可以复用的数据结构。

## Non-goals

- 不解析 raw shell hook payload。
- 不实现 command history repository。
- 不实现 command block range。
- 不实现 UI、overlay 或 sticky header。
- 不修改 `packages/ianvs_terminal` 的事件 schema。

## Files In Scope

- `example/lib/features/command_center/command_invocation_models.dart`
- `example/test/command_center/command_invocation_models_test.dart`

## Functional Acceptance

- 模型能表达 command、cwd、startedAt、finishedAt、exitCode、duration、sessionId 和可选 pane/profile metadata。
- `running` invocation 没有 `finishedAt` 和最终 exitCode。
- `succeeded` 与 `failed` 可由 exitCode 派生，也可被明确状态覆盖。
- `unknown` 状态可表达 shell hook 或 range 信息不足。
- 多 session 数据不会混淆。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_invocation_models_test.dart
```

## Manual QA

纯模型任务，不改变 UI、输入或 runtime 行为；无需人工 UI QA。

## Done When

- History/Search/Blocks 任务不需要重新定义 invocation 字段。
- lifecycle 状态和时间字段有单元测试覆盖。
- 模型不依赖 Flutter widget 或 platform API。

## Risks / Follow-ups

- shell hook 顺序异常和 unavailable reason 由 `T-304` 处理。
- row range、output preview 和 replay frame 归属由后续 block/review 任务处理。
