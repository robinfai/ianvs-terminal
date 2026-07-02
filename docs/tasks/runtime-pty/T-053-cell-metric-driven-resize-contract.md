# T-053 Cell-Metric-Driven Resize Contract

## Goal

让 Flutter 侧 session resize 使用 terminal viewport 的真实 cell size，而不是长期依赖硬编码 `9x18`，从而降低字体度量、prompt 样式和 DPI 变化时的列数/行数漂移风险。

## Scope

- `example/lib/features/terminal/terminal_viewport.dart`
- `example/lib/features/terminal/render_terminal_viewport.dart`
- `example/lib/features/sessions/session_controller.dart`
- `example/test/terminal/render_terminal_viewport_test.dart`
- `example/test/sessions/session_controller_test.dart`
- `docs/TESTING.md`
- `docs/tasks/runtime-pty/T-053-cell-metric-driven-resize-contract.md`

## Non-goals

- 不修改 Rust FFI、core frame schema 或 terminal emulation
- 不重做 terminal 字体、主题或 shell 视觉设计
- 不把 `char_protected` 升级成新的 Flutter/UI 契约
- 不修复 `flutter run -d macos` 的环境前置台问题

## Functional Acceptance

- `TerminalViewportController` 暴露内部 measured cell-size 状态，供 session 层读取
- `RenderTerminalViewport` 在完成字形测量后把 cell size 写回 controller
- `SessionController.resizeActiveSession()` 优先使用 measured cell size
- 在首帧尚未测得 cell size 时，仍允许一次性 fallback 到现有默认值
- dedupe 逻辑继续基于 `cols` / `rows` / pixel size，不改变现有 resize contract

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/sessions/session_controller_test.dart
flutter test test/terminal/render_terminal_viewport_test.dart
flutter test
flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
```

## Manual QA

1. 以默认 shell profile 启动 app，并在 terminal viewport 首次显示后调整窗口大小
2. 在至少一种与默认度量不同的 prompt / glyph 组合下重复 resize
3. 确认列数/行数与视觉宽高变化保持一致，不出现明显“比文本实际更宽/更窄”的 resize 漂移
4. 再次确认 scroll、selection、cursor blink 与 visible-content repaint 不回归

## Done When

- resize 计算链已经由 render 实测 cell size 驱动
- fallback 只在首帧未测得 cell size 时兜底
- targeted tests、`flutter test`、integration smoke、`flutter analyze` 全部通过

## Risks / Follow-ups

- 当前 cell size 仍由 Flutter 文本测量得出；若后续 terminal 字体/字号变成用户可配置项，需要继续让同一条测量链产出 resize 输入
- 更完整的字体度量 / DPI 真实性验证仍依赖 `T-055` 的手工矩阵
