# T-016 Terminal Copy 按钮 Smoke

## Goal

补一条最小自动化覆盖，验证 terminal 主界面的 `Copy` 按钮会把当前选中文本写入系统剪贴板。

## Scope

- `example/test/widget_test.dart`
  - 新增一条基于现有 `FakeCoreBindings` 和 Flutter 平台通道 mock 的最小 UI 测试。
  - 在 terminal 视图中制造线性选区后，点击可见的 `Copy` 按钮。
  - 断言系统剪贴板写入内容与当前选区文本一致。
- `docs/tasks/terminal-interaction/T-016-terminal-copy-button-smoke.md`
  - 记录本次任务范围、验收、验证与风险。
- `docs/TESTING.md`
  - 同步当前自动化覆盖范围，避免文档落后于实现。

## Non-goals

- 不覆盖键盘快捷键复制（如 `⌘C` / `Ctrl+C`）；该路径已有独立测试与任务记录。
- 不扩展到 `Copy` 历史、富文本格式、多行 selection 语义或系统菜单项行为。
- 不改动 Rust core、FFI 协议、session 生命周期架构或 terminal renderer。
- 不覆盖 SSH、split pane、跨平台差异或 Phase 1 之外能力。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `example/test/widget_test.dart`
- `docs/tasks/terminal-interaction/T-016-terminal-copy-button-smoke.md`
- `docs/TESTING.md`

## Functional Acceptance

- 自动化测试启动后，terminal 主界面可见 `Copy` 按钮，且存在活动 session。
- 测试可在当前 terminal 视图上生成一段稳定的线性选区。
- 点击 `Copy` 按钮后，平台剪贴板写入被触发。
- 剪贴板写入内容与选区文本完全一致。
- 本次覆盖保持 UI 可观察与路径闭环，不要求断言真实外部应用粘贴结果。

## Verification Commands

参考 [TESTING.md](../../TESTING.md)：

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 启动应用并进入默认 terminal tab。
3. 在 terminal 中拖选一段文本。
4. 点击主界面的 `Copy` 按钮。
5. 在外部文本框粘贴，确认内容与选区一致。

## Done When

- 自动化覆盖验证了 `Copy` 按钮 -> 选区读取 -> 系统剪贴板写入的最小路径。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试主要覆盖单行、线性选区，不验证复杂多行 selection 语义。
- 本任务只验证按钮路径，不验证真实外部应用粘贴或跨平台剪贴板差异。
