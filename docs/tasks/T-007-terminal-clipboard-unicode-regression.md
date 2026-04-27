# T-007 Terminal 粘贴与复制编码回归

## Goal

为终端键盘粘贴/复制快捷键补齐 Unicode 回归验证，确保非 ASCII 文本在输入与复制回调中保持原样字节与字符。

## Scope

- `example/test/terminal_input_controller_test.dart`
  - 新增键盘粘贴与复制的 Unicode 回归用例。

## Non-goals

- 不修改键盘快捷键的实现逻辑。
- 不新增/改动 `ShellScreen` 的按钮交互。
- 不引入其他终端功能（如 selection 多行语义、ANSI 过滤）。

## Files In Scope

- `example/test/terminal_input_controller_test.dart`

## Functional Acceptance

- 使用键盘快捷键触发粘贴时，非 ASCII 文本（如中文、Emoji）能够按 UTF-8 编码完整发送。
- 复制回调读取到的选区文本在 Unicode 下不被截断或替换，测试可断言与输入一致。

## Verification Commands

```bash
cd example
flutter analyze
flutter test
```

## Manual QA

1. 启动应用并打开 shell tab。
2. 复制一段中文或 Emoji 文本。
3. 按 `⌘V`/`Ctrl+V`，确认终端显示未出现乱码。
4. 选中包含中文/Emoji 的内容按 `⌘C`，在外部粘贴校验一致。

## Done When

- 回归测试文件新增并通过。
- 自动化命令 `flutter analyze` 与 `flutter test` 通过。
- 未超出 `Files In Scope`。

## Risks / Follow-ups

- 本任务不覆盖按钮式复制/粘贴（`Copy` / `Paste` 按钮）路径；若按钮路径出现问题，建议再开新任务。
