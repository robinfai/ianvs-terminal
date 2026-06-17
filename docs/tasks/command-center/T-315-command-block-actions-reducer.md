# T-315 Command Block Actions Reducer

## Goal

将 block actions 归约为 clipboard、input、search、save 和 review intents，并作为
post-search 唯一的 action surface。

## Scope

- 定义 copy command、copy output、copy both、re-input、rerun、search within
  block、save output 和 review intent，作为 post-search 唯一的 action surface。
- 统一 action availability 和 disabled reason。
- 确保写入型 action 受 read-only 与 safety policy 限制。

## Non-goals

- 不直接调用系统剪贴板。
- 不直接发送 terminal input。
- 不实现 action menu UI。
- 不实现 Agent explain/fix。
- 不绕过 read-only、paste confirmation 或 shortcut isolation。

## Files In Scope

- `example/lib/features/command_center/command_block_actions.dart`
- `example/lib/features/command_center/command_block_action_reducer.dart`
- `example/test/command_center/command_block_action_reducer_test.dart`

## Functional Acceptance

- block actions 是 post-search 的唯一 action surface。
- copy output 需要有效 output range。
- re-input 只插入命令，不执行。
- rerun 需要显式触发。
- read-only 下写入型 action disabled。
- search within block 不污染 global search。
- save output 和 review entrypoints 在缺少 range 或 frame 时给出 disabled reason。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_block_action_reducer_test.dart
```

## Manual QA

纯 reducer 任务，无需 UI QA。

## Done When

- Wiring 任务可以把 reducer intent 接到真实 clipboard/input/review。
- search、sticky header 或 review 之后的后续动作只通过 block actions 暴露。
- 每个 MVP action 都有 enabled 和 disabled 测试。
- Reducer 不拥有 platform bridge 或 terminal runtime controller。

## Risks / Follow-ups

- save output 的 action-search 路径由 T-384 定义为 Application Support 下的 `scrollback_exports`。
- copy output 与用户选区冲突时，后续 wiring 应让用户选区优先。
