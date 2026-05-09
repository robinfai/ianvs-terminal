# T-025 Terminal Paste 空剪贴板 No-op

## Goal

让 terminal 主界面的 `Paste` 按钮在系统剪贴板为空时不向活动 session 写入空输入。

## Scope

- `example/lib/features/shell/shell_screen.dart`
  - 让按钮式 `Paste` 与现有键盘粘贴路径保持一致：空文本直接返回。
- `example/test/widget_test.dart`
  - 新增空剪贴板按钮粘贴回归测试。
- `docs/tasks/terminal-interaction/T-025-terminal-paste-empty-clipboard-noop.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不改动键盘快捷键粘贴逻辑；该路径已有独立测试。
- 不改动 Rust core、FFI 协议、session 生命周期或 terminal renderer。
- 不扩展到剪贴板历史、富文本粘贴、selection 语义或跨平台差异。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/test/widget_test.dart`
- `docs/tasks/terminal-interaction/T-025-terminal-paste-empty-clipboard-noop.md`

## Functional Acceptance

- 当剪贴板返回空字符串时，点击 `Paste` 按钮不会触发 session 写入。
- 当剪贴板有内容时，现有按钮粘贴行为保持不变。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 清空系统剪贴板。
3. 点击 terminal 主界面的 `Paste` 按钮。
4. 确认 terminal 没有产生空输入副作用。

## Done When

- 空剪贴板按钮粘贴 no-op 有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 本任务只约束空字符串情况，不覆盖 `Clipboard.getData` 返回 `null` 或异常时的更复杂策略。
