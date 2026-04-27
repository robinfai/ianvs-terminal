# T-030 Flutter 侧 shell exit 事件传播 Smoke

## Goal

补一条最小 Flutter 侧自动化测试，验证真实本地 shell session 退出后，Dart FFI client 能读取到 `exit` 事件及退出码。

## Scope

- `example/test/ffi/flutterm_core_test.dart`
  - 增加一条真实本地 shell `exit` 事件回归测试。
- `docs/tasks/T-030-flutter-exit-event-smoke.md`
  - 记录本次任务边界、验收、验证与风险。

## Non-goals

- 不改动 Flutter UI、widget/integration smoke、tab 管理或剪贴板路径。
- 不扩展到复杂 shell 生命周期、崩溃分类、信号矩阵或多 session 并发场景。
- 不修改 Rust core / FFI 接口设计。
- 不覆盖 SSH、split pane、跨平台 PTY 行为。

## Files In Scope

- `example/test/ffi/flutterm_core_test.dart`
- `docs/tasks/T-030-flutter-exit-event-smoke.md`

## Functional Acceptance

- 测试通过 Dart 侧 `TerminalCoreClient.load()` 创建真实本地 shell session。
- shell 进程退出后，`pollEvents()` 能读取到 `exit` 事件。
- 事件 payload 中的退出码与预期一致。
- 证明 Flutter 侧已具备“真实 shell 退出 -> FFI event -> Dart 事件读取”最小链路。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/ffi/flutterm_core_test.dart
```

## Manual QA

本次主要补 Flutter 侧自动化回归，不直接要求 GUI 手测。

## Done When

- 新增 exit 事件测试通过。
- `flutter analyze` 与目标测试命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试只覆盖单一退出码场景，不覆盖信号终止或更复杂 shell 生命周期。
- 若环境里真实 dylib / app bundle 装配不稳定，可能需要单开任务梳理测试加载路径。
