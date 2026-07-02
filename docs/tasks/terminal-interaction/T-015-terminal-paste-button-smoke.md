# T-015 Terminal Paste 按钮 Smoke

## Goal

补一条最小自动化覆盖，验证 terminal 主界面的 `Paste` 按钮会读取剪贴板文本，并将对应 UTF-8 字节写入当前活动 session。

## Scope

- 优先在 `example/integration_test/ianvs_terminal_smoke_test.dart`
  - 新增一条基于现有 `FakeCoreBindings` 的最小 UI smoke。
  - 为测试注入一段可控剪贴板文本，点击可见的 `Paste` 按钮。
  - 断言 active session 收到的最后一次写入等于该文本的 UTF-8 字节。
- `docs/tasks/terminal-interaction/T-015-terminal-paste-button-smoke.md`
  - 记录本次任务范围、验收、验证与风险。
- 如果 Flutter 桌面测试环境里直接控制剪贴板在 `integration_test` 不稳定，可改为在现有 Flutter widget test 面补同等断言；但只允许选择一个已有测试面，不扩展为多套重复覆盖。

## Non-goals

- 不覆盖键盘快捷键粘贴（如 `⌘V` / `Ctrl+V`）；该路径已有独立测试与任务记录。
- 不扩展到 `Copy` 按钮、剪贴板历史、富文本格式、selection 细节或系统菜单项行为。
- 不改动 Rust core、FFI 协议、session 生命周期架构或 terminal renderer。
- 不覆盖 SSH、split pane、跨平台差异或 Phase 1 之外能力。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `example/integration_test/ianvs_terminal_smoke_test.dart`（首选）
- `example/test/widget_test.dart`（仅当需要更稳定的剪贴板控制时二选一替代）
- `docs/tasks/terminal-interaction/T-015-terminal-paste-button-smoke.md`

## Functional Acceptance

- 自动化测试启动后，terminal 主界面可见 `Paste` 按钮，且存在活动 session。
- 测试可为粘贴路径提供一段确定性的 Unicode 文本（例如 `你好, 世界🌟`）。
- 点击 `Paste` 按钮后，fake core 记录到新的输入写入。
- 该写入内容与 `utf8.encode(clipboardText)` 完全一致，而不是按 UTF-16 code unit 或其他形式拆分。
- 本次覆盖保持 UI 可观察与路径闭环，不要求断言真实 shell 回显或系统级剪贴板集成细节。

## Verification Commands

参考 [TESTING.md](../../TESTING.md)：

```bash
cd example
flutter analyze
flutter test
flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
```

如果最终覆盖落在 widget test 面，仍需运行 `flutter analyze` 与 `flutter test`；`integration_test` 命令保留用于确认现有主界面 smoke 未回归。

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 启动应用并进入默认 terminal tab。
3. 在系统剪贴板放入一段包含中文或 Emoji 的文本（例如 `你好, 世界🌟`）。
4. 点击主界面的 `Paste` 按钮。
5. 确认 terminal 行为与现有粘贴预期一致，且无明显乱码或 UI 异常。

## Done When

- 自动化覆盖验证了 `Paste` 按钮 -> 剪贴板读取 -> UTF-8 写入 active session 的最小路径。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- Flutter 桌面测试环境的系统剪贴板稳定性可能影响测试实现位置；如 `integration_test` 不稳定，可在现有 widget test 面补等价覆盖，但不应双写。
- 本任务只验证按钮路径与 UTF-8 写入，不验证真实 PTY 回显、跨平台剪贴板差异或更复杂的 paste/selection 组合流程。
