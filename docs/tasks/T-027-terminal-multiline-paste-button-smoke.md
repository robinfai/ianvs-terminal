# T-027 Terminal 多行 Paste 按钮 Smoke

## Goal

补一条最小自动化覆盖，验证 terminal 主界面的 `Paste` 按钮在剪贴板包含多行文本时，会把完整文本按 UTF-8 原样写入当前活动 session。

## Scope

- `app/test/widget_test.dart`
  - 新增一条多行剪贴板按钮粘贴测试。
- `docs/tasks/T-027-terminal-multiline-paste-button-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不覆盖键盘快捷键粘贴（如 `⌘V` / `Ctrl+V`）；该路径已有独立测试。
- 不改动 Rust core、FFI 协议、session 生命周期或 terminal renderer。
- 不扩展到富文本粘贴、剪贴板历史、selection 语义或跨平台差异。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `app/test/widget_test.dart`
- `docs/tasks/T-027-terminal-multiline-paste-button-smoke.md`

## Functional Acceptance

- 自动化测试可为按钮式粘贴路径提供确定性的多行文本。
- 点击 `Paste` 按钮后，fake core 记录到新的输入写入。
- 写入内容与 `utf8.encode(multilineClipboardText)` 完全一致，包含换行。
- 本次覆盖保持 UI 可观察与路径闭环，不要求断言真实 shell 回显。

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 在系统剪贴板放入多行文本。
3. 点击 terminal 主界面的 `Paste` 按钮。
4. 确认 terminal 行为与换行预期一致。

## Done When

- 按钮式多行粘贴有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 本任务只验证按钮路径与 UTF-8 写入，不验证真实 PTY 回显或更复杂剪贴板格式。
