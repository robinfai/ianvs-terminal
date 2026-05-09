# T-024 Shell 退出回到空状态 Smoke

## Goal

补一条最小 UI 自动化覆盖，验证最后一个活动 shell session 收到 `exit` 事件后，界面会自动回到空状态。

## Scope

- `example/test/widget_test.dart`
  - 新增一条通过可控 `exit` 事件验证 UI 回到 empty-state 的 widget 测试。
- `docs/tasks/terminal-interaction/T-024-terminal-exit-empty-state-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不改动 Rust core、FFI 协议、renderer 或 session 生命周期架构。
- 不覆盖 SSH、split pane、跨平台行为、崩溃分类或退出确认 UI。
- 不扩展到多 tab 下的复杂退出顺序；该规则已由 controller 级测试覆盖。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `example/test/widget_test.dart`
- `docs/tasks/terminal-interaction/T-024-terminal-exit-empty-state-smoke.md`

## Functional Acceptance

- 测试启动后存在活动 terminal tab。
- 为当前 session 注入 `exit` 事件。
- 事件处理后，tab 条目消失。
- 主区域显示 `Create a shell to get started`。
- `Copy` / `Paste` 不再显示，而 `New Tab` 仍可见。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 启动应用并保持只有一个 terminal tab。
3. 在 shell 中执行 `exit`。
4. 确认界面自动回到 `Create a shell to get started`。

## Done When

- shell `exit` -> empty-state UI 的最小路径有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前只验证最后一个 tab 的退出空状态，不覆盖多 tab 下的 UI 层焦点迁移；该规则已由 controller 级测试覆盖。
- 若后续需要 UI 层验证“非最后一个 tab 的 exit 焦点迁移”，建议拆独立任务继续扩展。
