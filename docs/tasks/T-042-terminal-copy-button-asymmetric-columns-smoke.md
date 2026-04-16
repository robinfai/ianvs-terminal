# T-042 Terminal Copy 按钮非对称列范围 Smoke

## Goal

补一条最小自动化覆盖，验证 terminal 多行选区在**首尾列范围不对称**时，通过主界面 `Copy` 按钮写入系统剪贴板仍保持当前线性多行语义。

## Scope

- `app/test/widget_test.dart`
  - 新增一条非对称多行拖选 + `Copy` 按钮的 widget 测试。
- `docs/tasks/T-042-terminal-copy-button-asymmetric-columns-smoke.md`
  - 记录本次任务范围、验收、验证与风险。
- `docs/TESTING.md`
  - 同步当前新增覆盖项，并进一步收窄未覆盖列表。

## Non-goals

- 不改动 Rust core、FFI 协议、selection 算法、renderer 或 clipboard bridge。
- 不实现真正的矩形/block 选区。
- 不扩展到外部应用粘贴验证或桌面自动化。

## Files In Scope

- `app/test/widget_test.dart`
- `docs/tasks/T-042-terminal-copy-button-asymmetric-columns-smoke.md`
- `docs/TESTING.md`

## Functional Acceptance

- 测试能在 terminal 视图上构造一条跨三行、首尾列范围不对称的线性选区。
- 点击 `Copy` 按钮后，平台剪贴板写入被触发。
- 剪贴板内容与当前线性多行语义一致：首行尾段 + 中间整行 + 末行前段。

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 在 terminal 中输出三行文本。
3. 构造首尾列不对称的跨行拖选，点击 `Copy`。
4. 在外部文本框粘贴，确认结果符合线性多行语义。

## Done When

- 非对称多行选区经过 `Copy` 按钮写入系统剪贴板的路径有自动化覆盖。
- 相关验证命令通过。
- `docs/TESTING.md` 已同步覆盖现状。

## Risks / Follow-ups

- 当前测试锁定的是既有线性多行复制语义，不代表已经支持真正的矩形/block 选区复制。
- 若后续要支持 block 选区复制，应拆独立任务重新定义交互与文本提取规则。
