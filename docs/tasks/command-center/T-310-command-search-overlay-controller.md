# T-310 Command Search Overlay Controller

## Goal

建立 `Ctrl-R` overlay 的 state/controller。

## Scope

- 管理 open/close、query update、selection movement。
- 根据键盘意图产生 insert 或 explicit execute intent。
- 将 search index results 转成 overlay state。

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

- `Ctrl-R` intent 打开搜索。
- `Esc` 关闭搜索并清理临时 query state。
- 上下键更新选中项。
- `Enter` 产生 insert intent。
- `Cmd/Ctrl+Enter` 产生 explicit execute intent。
- 空结果有稳定 empty state。

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
- open/close、query、selection、insert 和 explicit execute intent 有测试。
- controller 不直接写入 PTY。

## Risks / Follow-ups

- 快捷键消费和 IME 行为由 `T-311` 与 `T-312` 验证。
- Search result detail panel 若后续需要，应单独拆任务。
