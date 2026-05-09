# T-031 活动 Tab shell 退出后的 UI 焦点迁移 Smoke

## Goal

补一条最小 UI 自动化覆盖，验证当前活动 shell session 收到 `exit` 事件后，界面会自动切到剩余 tab，而不是停留在失焦状态。

## Scope

- `example/test/widget_test.dart`
  - 新增一条通过可控 `exit` 事件验证活动 tab 退出后 UI 焦点迁移的 widget 测试。
- `docs/tasks/terminal-interaction/T-031-terminal-exit-active-focus-ui-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不改动 Rust core、FFI 协议、renderer 或 session 生命周期架构。
- 不覆盖 SSH、split pane、跨平台行为、崩溃分类或退出确认 UI。
- 不扩展到最后一个 tab 的空状态路径；该规则已由 `T-024` 覆盖。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `example/test/widget_test.dart`
- `docs/tasks/terminal-interaction/T-031-terminal-exit-active-focus-ui-smoke.md`

## Functional Acceptance

- 测试启动后创建两个 terminal tab，并让第二个 tab 处于活动状态。
- 为当前活动 session 注入 `exit` 事件。
- 事件处理后，退出的 tab 消失。
- 剩余 tab 自动成为活动状态。
- `Copy` / `Paste` 仍可见，说明主界面保持在可交互 terminal 视图。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 打开两个 terminal tab，并切换到第二个 tab。
3. 让第二个（当前活动）tab 内的 shell 退出。
4. 确认第二个 tab 自动消失，焦点切到第一个 tab。

## Done When

- shell `exit` -> UI 焦点迁移到剩余 tab 的最小路径有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前只验证两 tab 场景，不覆盖更多 tab 组合或连续退出序列。
- 若后续需要 UI 层验证更复杂焦点迁移规则，应拆独立任务继续扩展。
