# T-313 Command Block Range Model

## Goal

建立 command block 的 row range 模型。

## Scope

- 定义 command block input range、output range、status、session/pane isolation 和 missing range。
- 将 command invocation 与 terminal row range 关联。
- 为 block navigation、actions、sticky header 和 review entrypoints 提供稳定输入。

## Non-goals

- 不实现 block overlay UI。
- 不实现 sticky header。
- 不实现 copy output wiring。
- 不修改 renderer 或把 header 写入 scrollback。
- 不扩展 `packages/ianvs_terminal` API，除非另开 focused task。

## Files In Scope

- `example/lib/features/command_center/command_block_models.dart`
- `example/test/command_center/command_block_models_test.dart`

## Functional Acceptance

- block lifecycle 与 invocation 对齐。
- output range 不串命令。
- missing range 时禁用依赖 range 的动作。
- 多 pane/session block 隔离。
- shell integration unavailable 时 block 能力可降级。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_block_models_test.dart
```

## Manual QA

纯模型任务，不改变 UI 或 runtime；无需人工 UI QA。

## Done When

- Block navigation 和 actions 可以消费稳定模型。
- range、status、missing range 和 session isolation 有测试。
- Block model 不改写 terminal scrollback。

## Risks / Follow-ups

- package 层 row range API 未冻结时只做 app 层适配。
- alt-buffer / pager 的特殊行为由后续 sticky header 或 verification 任务处理。
