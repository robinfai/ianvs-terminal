# T-316 Command Block Action Wiring

## Goal

接入 copy output、re-input、rerun 的实际 shell/action wiring。

## Scope

- 在统一 action registry 中加入 block actions。
- 接入 action availability、clipboard bridge 和 terminal input intent。
- 将 block action reducer 的 intents 映射到现有 shell action pipeline。

## Non-goals

- 不实现复杂 action menu 视觉 polish。
- 不实现 sticky header。
- 不做 Agent explain/fix。
- 不绕过 read-only 或 paste confirmation。
- 不改变普通 terminal selection copy 的优先级。

## Files In Scope

- `example/lib/features/shell/shell_action_registry.dart`
- `example/lib/features/shell/shell_action_availability.dart`
- `example/lib/features/shell/shell_action_dispatcher.dart`
- `example/test/shell/shell_action_availability_test.dart`
- `example/test/shell/shell_action_dispatcher_test.dart`

## Functional Acceptance

- block actions 出现在统一 action registry。
- availability 使用 reducer reason。
- copy output 使用正确 output range。
- re-input 插入命令但不执行。
- rerun 走 read-only 和 paste safety。
- 用户手动选区复制仍优先按真实 terminal selection 处理。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/shell/shell_action_availability_test.dart test/shell/shell_action_dispatcher_test.dart
```

## Manual QA

- 手动运行成功命令、失败命令和长输出命令。
- 测试 copy output、re-input、rerun。
- 启用 read-only 后确认 rerun 不可用。
- 建立 terminal selection 后确认普通复制不被 block action 覆盖。

## Done When

- MVP block actions 能通过统一 action pipeline 触发。
- 写入型动作全部经过 safety policy。
- 复制范围和 disabled reason 有测试。

## Risks / Follow-ups

- save output 和 review entrypoints 可在后续任务接入。
- 如果 action registry 增加太多条目，需要后续整理 command menu 分组。
