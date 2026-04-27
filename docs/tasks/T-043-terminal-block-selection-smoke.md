# T-043 Terminal block selection Smoke

## Goal

补齐 terminal 自动化 backlog 里的最后一个显式缺口：实现并验证真正的矩形 / block selection 语义。

## Scope

- `example/lib/features/terminal/selection_controller.dart`
  - 增加 block selection 模式与逐行裁剪文本提取语义。
- `example/lib/features/terminal/render_terminal_viewport.dart`
  - 在 Alt / Option 拖选时进入 block selection，并按矩形范围高亮。
- `example/test/terminal/selection_controller_test.dart`
  - 新增 block selection 语义单元测试。
- `example/test/widget_test.dart`
  - 新增 Alt / Option 拖选 + `Copy` 按钮的 widget 测试。
- `docs/tasks/T-043-terminal-block-selection-smoke.md`
  - 记录本次任务边界、验收、验证与风险。
- `docs/TESTING.md`
  - 同步覆盖现状。

## Non-goals

- 不扩展到键盘扩展选择、系统菜单项、外部应用粘贴验证或桌面自动化。
- 不引入 padding 空格对齐；较短行只裁剪到已有文本范围。
- 不改动 Rust core、FFI 或 PTY 生命周期。

## Files In Scope

- `example/lib/features/terminal/selection_controller.dart`
- `example/lib/features/terminal/render_terminal_viewport.dart`
- `example/test/terminal/selection_controller_test.dart`
- `example/test/widget_test.dart`
- `docs/tasks/T-043-terminal-block-selection-smoke.md`
- `docs/TESTING.md`

## Functional Acceptance

- Alt / Option 拖选可进入 block selection 模式。
- block selection 在每一行使用相同列范围提取文本。
- 当矩形范围超出某一行长度时，该行只裁剪到已有文本，不补空格。
- `Copy` 按钮可把 block selection 文本写入系统剪贴板。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/terminal/selection_controller_test.dart
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 输出多行且长度不同的文本。
3. 按住 Alt / Option 拖选矩形区域。
4. 点击 `Copy`，在外部文本框粘贴并确认逐行裁剪结果。

## Done When

- block selection 语义已实现。
- 单元与 widget 自动化验证通过。
- `docs/TESTING.md` 已同步到最新覆盖现状。

## Risks / Follow-ups

- 当前 block selection 只覆盖 Alt / Option 拖选 + Copy 路径。
- 后续若要支持键盘扩展选择、空格 padding 或更复杂 block UX，应拆独立任务继续设计。
