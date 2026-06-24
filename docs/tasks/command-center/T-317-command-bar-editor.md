# T-317 Command Bar Editor

## Goal

建立 terminal-first command bar editor。

## Scope

- 支持 multiline editing、soft wrap、insert command、read-only 和 paste integration。
- 作为显式增强输入层接入，而不是替换普通 terminal input。
- 保持 IME composition 和现有 shortcut routing 稳定。

## Non-goals

- 不做自然语言自动识别。
- 不实现 Agent / AI command generation。
- 不绕过 read-only 或 paste confirmation。
- 不做 quote/bracket auto-pair 第一版。
- 不把 editor 下沉到 `packages/ianvs_terminal`。

## Files In Scope

- `example/lib/features/command_center/command_bar_editor.dart`
- `example/test/command_center/command_bar_editor_test.dart`
- 必要的 `example/lib/features/shell/` wiring

## Functional Acceptance

- 普通文本默认进 shell。
- `Shift+Enter` 可插入换行。
- 长命令 soft wrap，不改变实际发送文本。
- read-only 阻止发送。
- IME composition 不被抢。
- 从 command search 或 saved command 插入文本时不自动执行。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_bar_editor_test.dart
```

## Manual QA

- 在 app 中输入普通命令。
- 输入多行命令，确认 `Shift+Enter` 行为。
- 输入中文 IME，确认 composition 不被中断。
- 启用 read-only 后尝试发送命令，确认不会写入 shell。
- 插入历史命令，确认不会自动执行。

## Done When

- Command Bar 可作为显式增强输入层接入。
- 默认 terminal 行为不回退。
- 多行、soft wrap、read-only 和 IME 行为有测试或人工验证。

## Risks / Follow-ups

- 第一版不做 IDE 式 word selection 或 auto-pair。
- 如果 editor 与 terminal focus 冲突，需要优先保护 terminal input 语义。
