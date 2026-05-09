# T-026 Terminal Copy 空选区 No-op

## Goal

让 terminal 主界面的 `Copy` 按钮在没有选区时不向系统剪贴板写入空字符串。

## Scope

- `example/lib/features/shell/shell_screen.dart`
  - 让按钮式 `Copy` 与现有键盘复制路径保持一致：空选区直接返回。
- `example/test/widget_test.dart`
  - 新增空选区按钮复制回归测试。
- `docs/tasks/terminal-interaction/T-026-terminal-copy-empty-selection-noop.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不改动键盘快捷键复制逻辑；该路径已有独立测试。
- 不改动 Rust core、FFI 协议、session 生命周期或 terminal renderer。
- 不扩展到多行选区、富文本复制、菜单项行为或跨平台差异。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/test/widget_test.dart`
- `docs/tasks/terminal-interaction/T-026-terminal-copy-empty-selection-noop.md`

## Functional Acceptance

- 当没有活动选区时，点击 `Copy` 按钮不会触发系统剪贴板写入。
- 当存在选区时，现有 `Copy` 按钮行为保持不变。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 启动应用并进入 terminal tab，但不要选择任何文本。
3. 点击 `Copy` 按钮。
4. 确认不会把空字符串覆盖到外部剪贴板。

## Done When

- 空选区按钮复制 no-op 有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 本任务只约束无选区情况，不覆盖复杂多行选区或外部应用粘贴结果。
