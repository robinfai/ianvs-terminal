# T-033 Flutter 侧 PTY 多命令往返 Smoke

## Goal

补一条最小 Flutter 侧自动化测试，验证同一个真实本地 shell session 能连续接收多条命令并分别产生产出。

## Scope

- `example/test/ffi/ianvs_core_test.dart`
  - 新增一条基于真实 `TerminalCoreClient.load()` 的多命令 roundtrip 测试。
- `docs/tasks/runtime-pty/T-033-flutter-pty-multi-command-smoke.md`
  - 记录本次任务边界、验收、验证与风险。

## Non-goals

- 不改动 Flutter UI、widget/integration smoke、tab 管理或剪贴板路径。
- 不扩展到长会话、复杂提示符、交互式编辑器或性能基线。
- 不修改 Rust core / FFI 接口设计。
- 不覆盖 SSH、split pane、跨平台 PTY 行为。

## Files In Scope

- `example/test/ffi/ianvs_core_test.dart`
- `docs/tasks/runtime-pty/T-033-flutter-pty-multi-command-smoke.md`

## Functional Acceptance

- 测试通过 Dart 侧 `TerminalCoreClient.load()` 创建真实本地 shell session。
- 测试向同一 session 连续发送两条简单命令。
- frame diff 中能先后观察到两次对应输出。
- 证明 Flutter 侧 FFI client 在同一会话里具备基本的多命令往返能力。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/ffi/ianvs_core_test.dart
```

## Manual QA

本次主要补 Flutter 侧自动化回归，不直接要求 GUI 手测。

## Done When

- 新增多命令 roundtrip 测试通过。
- `flutter analyze` 与目标测试命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试只覆盖两条简单命令，不覆盖长会话、提示符差异或更复杂交互。
- 若后续要验证 shell 持续可交互与更多命令序列，可在此基础上继续扩展。
