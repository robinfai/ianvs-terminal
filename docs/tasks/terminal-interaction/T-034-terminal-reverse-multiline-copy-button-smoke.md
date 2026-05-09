# T-034 Terminal 反向多行 Copy 按钮 Smoke

## Goal

补一条最小自动化覆盖，验证 terminal 多行选区在**反向拖选**时，通过主界面 `Copy` 按钮写入系统剪贴板仍保持正确顺序与换行。

## Scope

- `example/test/widget_test.dart`
  - 新增一条反向多行拖选 + `Copy` 按钮的 widget 测试。
- `docs/tasks/terminal-interaction/T-034-terminal-reverse-multiline-copy-button-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不改动 Rust core、FFI 协议、terminal renderer 或 session 生命周期架构。
- 不覆盖键盘快捷键复制、矩形选区、富文本复制、系统菜单项行为或跨平台差异。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。
- 不把本任务扩展为真实外部应用粘贴验证。

## Files In Scope

- `example/test/widget_test.dart`
- `docs/tasks/terminal-interaction/T-034-terminal-reverse-multiline-copy-button-smoke.md`

## Functional Acceptance

- 测试可在 terminal 视图上构造稳定的**反向**多行选区。
- 点击 `Copy` 按钮后，平台剪贴板写入被触发。
- 剪贴板内容与归一化后的多行选区文本一致，包含正确换行。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 在 terminal 中输出多行文本。
3. 从后往前跨行拖选并点击 `Copy`。
4. 在外部文本框粘贴，确认内容顺序与换行正确。

## Done When

- 反向多行选区经过 `Copy` 按钮写入系统剪贴板的路径有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试主要覆盖规则的线性反向拖选，不覆盖矩形选区或更复杂选择语义。
- 若后续需要验证真实外部应用粘贴结果，应拆独立任务继续扩展。
