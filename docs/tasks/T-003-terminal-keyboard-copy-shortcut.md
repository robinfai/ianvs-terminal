# T-003 Terminal 键盘复制快捷键

## Goal

当终端处于焦点时，支持 `⌘C`/`Ctrl+C` 将当前选中文本复制到系统剪贴板。

## Scope

- `example/lib/features/terminal/terminal_input_controller.dart`
  - 增加 `⌘C`/`Ctrl+C` 快捷键分支。
  - 将选区文本通过回调交给上层进行剪贴板写入。
- `example/lib/features/shell/shell_screen.dart`
  - 为 `TerminalInputController` 提供快捷键复制回调。
- `example/test/terminal_input_controller_test.dart`
  - 增加覆盖 `⌘C` 复制行为的测试。

## Non-goals

- 不改动 `复制` 按钮逻辑。
- 不引入完整快捷键体系（如快捷键自定义面板）。
- 不改变当前 Rust core 或 PTY 协议。

## Files In Scope

- `example/lib/features/terminal/terminal_input_controller.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/test/terminal_input_controller_test.dart`

## Functional Acceptance

- 光标位于终端时，按 `⌘C` 会把当前文本选区复制到剪贴板。
- 当没有选区时，`⌘C` 不会触发非法写入或发送异常输入。
- 现有 `⌘V`、普通字符输入和按钮粘贴行为不变。

## Verification Commands

```bash
cd example
flutter analyze
flutter test
```

## Manual QA

1. 启动应用。
2. 打开一个本地 shell tab。
3. 运行 `echo hello`。
4. 鼠标拖选 `hello`。
5. 按 `⌘C`。
6. 在外部文本框粘贴，确认内容为 `hello`。

## Done When

- `TerminalInputController` 支持复制快捷键并通过测试。
- 自动化测试覆盖复制快捷键行为。
- 不触发现有输入/粘贴回归。

## Risks / Follow-ups

- 目前仅支持 `⌘C`/`Ctrl+C` 的复制，不包含快捷键自定义。
