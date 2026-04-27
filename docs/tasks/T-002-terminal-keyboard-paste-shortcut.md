# T-002 Terminal 键盘粘贴快捷键

## Goal

在终端处于焦点时，支持 `⌘V`/`Ctrl+V` 触发粘贴，把剪贴板文本发送到当前会话。

## Scope

- `example/lib/features/terminal/terminal_input_controller.dart`
  - 增加 `⌘V`/`Ctrl+V` 快捷键分支。
- `example/lib/features/shell/shell_screen.dart`
  - 为 `TerminalInputController` 提供粘贴文本读取入口。
- `example/test/terminal_input_controller_test.dart`
  - 新增键盘粘贴快捷键单测。
- `example/test/support/fake_core_bindings.dart`
  - 捕获写入字节用于单测断言（仅测试用途）。

## Non-goals

- 不修改复制（`⌘C`）快捷键行为。
- 不改变 FFI 协议、Rust core、PTY 逻辑。
- 不新增新的快捷键映射策略（如方向键增强、Ctrl+Shift 等组合）。

## Files In Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/terminal/terminal_input_controller.dart`
- `example/test/terminal_input_controller_test.dart`
- `example/test/support/fake_core_bindings.dart`

## Functional Acceptance

- 当终端获得焦点并按下 `⌘V`（macOS）或 `Ctrl+V` 时，当前会话收到 UTF-8 编码后的剪贴板内容。
- 无修饰符的普通字符输入行为保持不变（如按 `v` 仍发送字符 `v`）。
- 变更限制在现有输入路径内，不涉及 core 或 session 生命周期。

## Verification Commands

```bash
cd example
flutter analyze
flutter test
```

## Manual QA

1. 启动应用，打开一个 local shell tab。
2. 选中外部文字（例如 `hello flutterm`）。
3. 在终端内聚焦后按 `⌘V`（或 `Ctrl+V`）。
4. 验证终端收到的内容与剪贴板一致。

## Done When

- 终端输入层完成键盘粘贴快捷键实现且测试通过。
- `flutter analyze` 与 `flutter test` 命令通过。
- 无改动超出 `Files In Scope`。

## Risks / Follow-ups

- 本次仅覆盖终端主输入视图内的粘贴，菜单按钮粘贴路径继续沿用现有实现。
- 若后续要支持更完整的快捷键策略（例如 macOS 特定修饰键、快捷键自定义），建议新开独立任务。
