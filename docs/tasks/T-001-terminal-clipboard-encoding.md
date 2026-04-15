# T-001 Terminal 粘贴 UTF-8 编码修复

## Goal

修复终端粘贴按钮在包含非 ASCII 字符（如中文、Emoji）时的输入编码问题，确保发送给 PTY 的字节为 UTF-8。

## Scope

- `app/lib/features/shell/shell_screen.dart`：修复粘贴分支的字节编码。
- `app/test/widget_test.dart`（可选）：在必要时补充回归测试覆盖粘贴行为。

## Non-goals

- 不新增/修改键盘快捷键粘贴实现（如 ⌘V / Ctrl+V）。
- 不调整剪贴板历史或格式化策略。
- 不修改 profile 保存逻辑或 terminal 内核协议。

## Files In Scope

- `app/lib/features/shell/shell_screen.dart`
- `app/test/widget_test.dart`（若本次回归测试需要）

## Functional Acceptance

- 当用户通过界面“Paste”按钮粘贴文本时，终端输入发送到 core 的字节应使用 UTF-8 编码。
- 含中文或 Emoji 的文本不应被按 16-bit code unit 拆分后逐码位发送。
- 现有粘贴行为在 ASCII 文本下继续正常。

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test
```

## Manual QA

1. 启动应用。
2. 打开 shell tab。
3. 在外部复制一段中文或 emoji 文本（例如 `你好🌟`）。
4. 在终端里点击 `Paste` 按钮。
5. 终端应原样输出对应字符串（不出现乱码）。

## Done When

- 目标代码修改完成且验证命令通过。
- 任务文档已新增。
- 未超出 Scope 进行额外改动。

## Risks / Follow-ups

- 本次仅覆盖按钮粘贴路径；键盘粘贴快捷键仍使用现有实现，后续可另开任务补齐。
