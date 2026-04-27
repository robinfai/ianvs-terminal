# T-021 Terminal 多行 Copy 按钮 Smoke

## Goal

补一条最小自动化覆盖，验证 terminal 多行选区通过主界面 `Copy` 按钮写入系统剪贴板时，换行与选区顺序保持正确。

## Scope

- `example/test/widget_test.dart`
  - 新增一条基于现有 `FakeCoreBindings`、`SelectionController` 和平台通道 mock 的多行复制按钮测试。
- `docs/tasks/T-021-terminal-multiline-copy-button-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不改动 Rust core、FFI 协议、terminal renderer 或 session 生命周期架构。
- 不覆盖键盘快捷键复制、矩形选区、富文本复制、系统菜单项行为或跨平台差异。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。
- 不把本任务扩展为真实外部应用粘贴验证。

## Files In Scope

- `example/test/widget_test.dart`
- `docs/tasks/T-021-terminal-multiline-copy-button-smoke.md`

## Functional Acceptance

- 测试可在 terminal 视图上构造稳定的多行选区。
- 点击 `Copy` 按钮后，平台剪贴板写入被触发。
- 剪贴板内容与多行选区文本完全一致，包含正确换行。
- 本次覆盖保持 UI 可观察路径闭环：选区 -> `Copy` 按钮 -> 系统剪贴板写入。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 在 terminal 中输出多行文本并进行跨行拖选。
3. 点击 `Copy` 按钮。
4. 在外部文本框粘贴，确认内容、顺序和换行与选区一致。

## Done When

- 多行选区经过 `Copy` 按钮写入系统剪贴板的路径有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试主要覆盖规则的多行线性选区，不覆盖矩形选区或更复杂选择语义。
- 若后续需要验证真实外部应用粘贴结果，应拆独立任务继续扩展。
