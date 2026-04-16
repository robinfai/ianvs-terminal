# T-019 Flutter 侧 PTY 命令往返 Smoke

## Goal

补一条最小 Flutter 侧自动化测试，验证 Dart FFI client 能向真实本地 shell session 发送输入并读取到对应输出。

## Scope

- `app/test/ffi/flutterm_core_test.dart`
  - 增加一条基于真实 `TerminalCoreClient.load()` 的最小 roundtrip 测试。
- `docs/tasks/T-019-flutter-pty-roundtrip-smoke.md`
  - 记录本次任务边界、验收、验证与风险。

## Non-goals

- 不改动 Flutter UI、widget/integration smoke、tab 管理或剪贴板路径。
- 不扩展到复杂 shell 脚本、多命令流水线、长会话交互或性能基线。
- 不修改 Rust core / FFI 接口设计。
- 不覆盖 SSH、split pane、跨平台 PTY 行为。

## Files In Scope

- `app/test/ffi/flutterm_core_test.dart`
- `docs/tasks/T-019-flutter-pty-roundtrip-smoke.md`

## Functional Acceptance

- 测试通过 Dart 侧 `TerminalCoreClient.load()` 创建真实本地 shell session。
- 测试发送一条简单命令。
- 在 frame diff 中观察到对应输出。
- 证明 Flutter 侧已具备“输入 -> FFI -> PTY -> 输出”最小往返能力。

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/ffi/flutterm_core_test.dart
```

## Manual QA

本次主要补 Flutter 侧自动化回归，不直接要求 GUI 手测。

## Done When

- 新增 Flutter 侧 roundtrip 测试通过。
- `flutter analyze` 与目标测试命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试只覆盖单条命令往返，不覆盖更复杂 shell 交互或提示符差异。
- 若环境里真实 dylib / app bundle 装配不稳定，可能需要单开任务梳理测试加载路径。
