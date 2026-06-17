# T-310 Command Search Overlay Controller

## Goal

建立 `Ctrl-R` overlay 的 state/controller。

## Scope

- 管理 open/close、query update、selection movement。
- 支持 current/global scope，并将当前 session 搜索作为默认入口。
- 过滤只保留有 command block 上下文的搜索记录。
- 根据键盘和结果动作产生 insert 或 view-block intent。
- 将 search index results 转成 overlay state，但不直接写入 PTY。

## Non-goals

- 不实现 overlay widget。
- 不直接发送 terminal input。
- 不执行命令。
- 不处理 IME widget 细节。
- 不做 Agent / AI 搜索。

## Files In Scope

- `example/lib/features/command_center/command_search_overlay_controller.dart`
- `example/test/command_center/command_search_overlay_controller_test.dart`

## Functional Acceptance

- `Ctrl-R` 打开当前 session 搜索。
- controller 支持 current/global scope。
- 结果只保留有 command block 上下文的记录。
- `Enter` 产生 insert intent。
- `查看命令块` 产生 view-block intent。
- controller 不直接写入 PTY。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_search_overlay_controller_test.dart
```

## Manual QA

纯 controller 任务，无需 UI QA。

## Done When

- Widget 任务不需要自行管理搜索状态。
- current/global scope、结果过滤、selection、insert 和 view-block intent 有测试。
- controller 不直接写入 PTY。

## Risks / Follow-ups

- 快捷键消费和 IME 行为由 `T-311` 与 `T-312` 验证。
- Search result detail panel 若后续需要，应单独拆任务。
