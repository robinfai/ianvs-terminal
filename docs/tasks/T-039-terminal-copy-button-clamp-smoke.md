# T-039 Terminal Copy 按钮裁剪越界选区 Smoke

## Goal

补一条最小自动化覆盖，验证 terminal 多行选区在结束列超过行尾时，通过主界面 `Copy` 按钮写入系统剪贴板仍会**安全裁剪**到可用文本范围。

## Scope

- `app/test/widget_test.dart`
  - 新增一条跨行拖选到行尾之外 + `Copy` 按钮的 widget 测试。
- `docs/tasks/T-039-terminal-copy-button-clamp-smoke.md`
  - 记录本次任务范围、验收、验证与风险。
- `docs/TESTING.md`
  - 同步当前新增覆盖项。

## Non-goals

- 不改动 Rust core、FFI 协议、terminal renderer、selection 算法或系统剪贴板桥接实现。
- 不覆盖矩形选区、富文本复制、键盘快捷键复制、系统菜单项行为或跨平台差异。
- 不把本任务扩展为真实外部应用粘贴验证。

## Files In Scope

- `app/test/widget_test.dart`
- `docs/tasks/T-039-terminal-copy-button-clamp-smoke.md`
- `docs/TESTING.md`

## Functional Acceptance

- 测试能在 terminal 视图上构造一条结束列超过行尾的多行选区。
- 点击 `Copy` 按钮后，平台剪贴板写入被触发。
- 剪贴板内容会被安全裁剪到真实文本边界，不包含越界垃圾内容。

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 在 terminal 中输出一组短行文本。
3. 选择跨多行并故意拖到末尾之外，点击 `Copy`。
4. 在外部文本框粘贴，确认结果只包含真实文本。

## Done When

- 越界多行选区经过 `Copy` 按钮写入系统剪贴板的路径有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试主要覆盖线性多行拖选裁剪，不覆盖矩形选区或更复杂 clipboard 组合行为。
- 若后续要验证真实外部应用粘贴结果，应拆独立任务继续扩展。
