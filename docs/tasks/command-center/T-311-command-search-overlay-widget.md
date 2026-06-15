# T-311 Command Search Overlay Widget

## Goal

实现 `Ctrl-R` overlay UI 和键盘导航。

## Scope

- 构建 command search overlay widget。
- 显示 command、cwd、exit status、last run 等结果信息。
- 支持 focus、keyboard navigation、loading、empty 和 unavailable states。
- 接入 shell/action wiring 的打开关闭入口。

## Non-goals

- 不默认执行搜索结果。
- 不做 Agent / AI 搜索。
- 不实现 sticky header。
- 不重写 terminal widget。
- 不把 UI 下沉到 `packages/ianvs_terminal`。

## Files In Scope

- `example/lib/features/command_center/command_search_overlay.dart`
- `example/test/command_center/command_search_overlay_test.dart`
- 必要的 `example/lib/features/shell/` wiring

## Functional Acceptance

- `Ctrl-R` 打开 overlay，`Esc` 关闭 overlay。
- fuzzy results 正确显示 command、cwd、exit status 和 last run 信息。
- 键盘上下移动选中项。
- IME 搜索词输入不被中断。
- `Esc`、方向键和 search shortcut 不泄漏控制字符到 PTY。
- shell integration unavailable 时仍可显示已有 local history 或明确 unavailable state。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_search_overlay_test.dart
```

## Manual QA

- 运行 app。
- 按 `Ctrl-R` 打开 overlay。
- 输入英文和中文搜索词。
- 使用上下键移动结果。
- 按 `Esc` 关闭 overlay。
- 确认 shell 未收到控制字符，且终端普通输入恢复。

## Done When

- 用户能看到并导航 command search overlay。
- overlay 与 terminal input focus 不互相污染。
- UI 测试覆盖打开、关闭、结果显示和空态。

## Risks / Follow-ups

- 视觉细节可在后续 UI polish 中调整，但 terminal safety 不可放宽。
- macOS 上 `Ctrl-R` 与 shell reverse search 语义冲突时，需要可配置或明确消费规则。
