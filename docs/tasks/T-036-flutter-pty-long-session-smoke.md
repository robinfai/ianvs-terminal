# T-036 Flutter 侧 PTY 长会话 Smoke

## Goal

补一条最小 Flutter 侧自动化测试，验证真实本地 shell session 在产生一段较长输出后，仍能继续接收后续命令并返回结果。

## Scope

- `example/test/ffi/flutterm_core_test.dart`
  - 新增一条基于真实 `TerminalCoreClient.load()` 的长会话 roundtrip 测试。
- `docs/tasks/T-036-flutter-pty-long-session-smoke.md`
  - 记录本次任务边界、验收、验证与风险。
- `docs/TESTING.md`
  - 同步新增的长会话覆盖项，并收窄 PTY 未覆盖说明。

## Non-goals

- 不改动 Flutter UI、widget/integration smoke、tab 管理、滚动或剪贴板路径。
- 不扩展到交互式编辑器、复杂 prompt 差异、SSH 或跨平台 PTY 行为。
- 不修改 Rust core / FFI 接口设计。
- 不把本任务扩展为性能基准或压力测试。

## Files In Scope

- `example/test/ffi/flutterm_core_test.dart`
- `docs/tasks/T-036-flutter-pty-long-session-smoke.md`
- `docs/TESTING.md`

## Functional Acceptance

- 测试通过 Dart 侧 `TerminalCoreClient.load()` 创建真实本地 shell session。
- 测试向同一 session 发送一段会产生较长输出的命令序列。
- frame diff 中能观察到长输出序列的后段标记。
- 长输出完成后，再发送一条简单命令，仍能在同一 session 中看到后续输出。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/ffi/flutterm_core_test.dart
```

## Manual QA

本次主要补 Flutter 侧自动化回归，不直接要求 GUI 手测。

## Done When

- 新增长会话 roundtrip 测试通过。
- `flutter analyze` 与目标测试命令通过。
- `docs/TESTING.md` 已同步覆盖现状。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试只覆盖较长输出后的持续交互，不覆盖复杂 prompt 差异或真正长时间运行的交互式程序。
- 若后续要验证 shell prompt 解析与更多持续会话细节，可拆独立任务继续扩展。
