# T-022 Terminal 滚轮事件链路 Smoke

## Goal

补一条最小自动化覆盖，验证 terminal 视图收到滚轮事件后，会把滚动行数正确传递给 core scroll 调用。

## Scope

- `app/test/support/fake_core_bindings.dart`
  - 记录 scroll 调用参数，供测试断言。
- `app/test/widget_test.dart`
  - 新增一条通过 `TerminalViewport` 发送滚轮事件的 widget 测试。
- `docs/tasks/T-022-terminal-scroll-wheel-plumbing-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不验证真实 scrollback 内容变化或渲染结果。
- 不改动 Rust core、FFI 协议、terminal renderer 或 session 生命周期架构。
- 不扩展到惯性滚动、性能基线、触控板手势或跨平台差异。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `app/test/support/fake_core_bindings.dart`
- `app/test/widget_test.dart`
- `docs/tasks/T-022-terminal-scroll-wheel-plumbing-smoke.md`

## Functional Acceptance

- 测试启动后存在活动 terminal 视图。
- 向 `TerminalViewport` 发送滚轮事件后，fake core 记录到一条 scroll 调用。
- 记录到的滚动行数非零，证明 UI 事件已通过现有链路传递到 core。

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 打开 terminal tab 并制造一定输出。
3. 滚动滚轮，确认 terminal 保持可交互且滚动行为正常。

## Done When

- 滚轮事件 -> core scroll 调用的最小路径有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试只验证调用链路，不验证真实 scrollback 视觉结果。
- 若后续需要验证滚动后的可见文本变化，应拆独立任务继续扩展。
