# T-040 Flutter 侧 PTY prompt 差异 Smoke

## Goal

补一条最小 Flutter 侧自动化测试，验证真实本地 shell session 在使用不同交互 prompt 配置时，仍能正常显示 prompt 并继续完成命令往返。

## Scope

- `example/test/ffi/flutterm_core_test.dart`
  - 新增一条基于真实 `TerminalCoreClient.load()` 的 prompt 差异 smoke 测试。
- `docs/tasks/T-040-flutter-pty-prompt-difference-smoke.md`
  - 记录本次任务边界、验收、验证与风险。
- `docs/TESTING.md`
  - 同步新增 prompt 差异覆盖项，并移除当前 PTY 未覆盖项。

## Non-goals

- 不改动 Flutter UI、widget/integration smoke、tab 管理、滚动或剪贴板路径。
- 不扩展到 SSH、跨平台 prompt 差异、复杂 shell 配置文件或交互式编辑器。
- 不修改 Rust core / FFI 接口设计。
- 不把本任务扩展为完整 shell 启动行为矩阵。

## Files In Scope

- `example/test/ffi/flutterm_core_test.dart`
- `docs/tasks/T-040-flutter-pty-prompt-difference-smoke.md`
- `docs/TESTING.md`

## Functional Acceptance

- 测试通过 Dart 侧 `TerminalCoreClient.load()` 创建真实本地 shell session。
- 测试至少覆盖两种不同的 prompt 配置。
- 每个 session 都能观察到对应 prompt 文本。
- 每个 session 都能在该 prompt 下继续完成最小命令往返。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/ffi/flutterm_core_test.dart
```

## Manual QA

本次主要补 Flutter 侧自动化回归，不直接要求 GUI 手测。

## Done When

- 新增 prompt 差异 smoke 测试通过。
- `flutter analyze` 与目标测试命令通过。
- `docs/TESTING.md` 已同步覆盖现状。

## Risks / Follow-ups

- 当前测试只覆盖简单 `PS1` 差异，不覆盖复杂 shell 初始化脚本、颜色 escape 序列或多平台 prompt 行为。
- 若后续要验证更复杂 shell 配置差异，可在此基础上继续扩展。
