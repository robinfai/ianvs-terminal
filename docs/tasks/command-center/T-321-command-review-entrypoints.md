# T-321 Command Review Entrypoints

## Goal

从 command block 接入 Review / Instant Replay。

## Scope

- 支持 `Replay from here`、`Open in Review`、failure snapshot source metadata 和 diff extension point。
- 复用现有 Instant Replay store / workspace 路径。
- 保持 live terminal 继续运行，review 不共享可写 input controller。

## Non-goals

- 不重写 Instant Replay workspace。
- 不实现 output diff 完整功能。
- 不实现 Agent explain/fix。
- 不让 review workspace 写入 live terminal。
- 不改变 terminal renderer。

## Files In Scope

- `example/lib/features/command_center/command_review_entrypoints.dart`
- `example/test/command_center/command_review_entrypoints_test.dart`
- `example/lib/features/shell/shell_screen_instant_replay.dart`
- `example/lib/features/shell/instant_replay_store.dart`

## Functional Acceptance

- `Replay from here` 定位到相关 frame 或 row range。
- `Open in Review` 创建只读 review 来源。
- live terminal 继续运行，不接收 review workspace 的写入型输入。
- diff 不可用时有 disabled reason。
- failure snapshot source metadata 能指向 command、cwd、exitCode、duration 和 output range。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_review_entrypoints_test.dart test/shell/instant_replay_store_test.dart
```

## Manual QA

- 从失败 block 打开 review。
- 确认 review 定位到相关输出附近。
- 确认 live terminal 没被切到只读，也不会接收 review 输入。
- 关闭 review 后确认原 session input focus 可恢复。

## Done When

- Command Blocks 能复用现有 Instant Replay 路径进入深复盘。
- Review source metadata 有测试。
- live terminal 与 review input 隔离有验证。

## Risks / Follow-ups

- output diff 可以作为后续独立任务开启。
- 如果 Instant Replay frame range 不足，需要记录 disabled reason 而不是猜测定位。
