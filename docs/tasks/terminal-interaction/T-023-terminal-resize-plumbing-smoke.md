# T-023 Terminal resize 事件链路 Smoke

## Goal

补一条最小自动化覆盖，验证 terminal 主界面的布局尺寸变化会触发 core resize 调用。

## Scope

- `example/test/widget_test.dart`
  - 新增一条通过改变测试 surface size 验证 resize 调用链路的 widget 测试。
- `docs/tasks/terminal-interaction/T-023-terminal-resize-plumbing-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不验证真实 scrollback/文本重排后的视觉结果。
- 不改动 Rust core、FFI 协议、renderer 或 session 生命周期架构。
- 不扩展到性能基线、连续 resize 压测、跨平台差异或 trackpad/gesture 行为。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `example/test/widget_test.dart`
- `docs/tasks/terminal-interaction/T-023-terminal-resize-plumbing-smoke.md`

## Functional Acceptance

- 测试启动后存在活动 terminal 视图。
- 初次布局会产生至少一次 resize 调用。
- 当 surface size 变化后，fake core 记录到新的 resize 调用。
- 新的 resize 调用参数与前一次不同，证明 UI 尺寸变化已通过现有链路传递到 core。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 打开 terminal tab。
3. 改变窗口大小。
4. 确认 terminal 仍可交互，且光标/内容无明显错位。

## Done When

- resize 事件 -> core resize 调用的最小路径有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前测试只验证调用链路，不验证视觉布局结果或高频 resize 稳定性。
- 若后续需要验证 viewport 内容重排，应拆独立任务继续扩展。
