# T-032 Shell 退出空状态恢复 Smoke

## Goal

补一条最小 UI 自动化覆盖，验证最后一个活动 shell session 收到 `exit` 事件后，界面回到 empty-state，且仍可通过 `New Tab` 恢复 terminal。

## Scope

- `app/test/widget_test.dart`
  - 新增一条通过可控 `exit` 事件验证 empty-state 后恢复路径的 widget 测试。
- `docs/tasks/T-032-terminal-exit-empty-state-recover-smoke.md`
  - 记录本次任务范围、验收、验证与风险。
- `docs/TESTING.md`
  - 同步自动化覆盖清单，避免文档再次漂移。

## Non-goals

- 不改动 Rust core、FFI 协议、renderer 或 session 生命周期架构。
- 不覆盖 SSH、split pane、跨平台行为、崩溃分类或退出确认 UI。
- 不扩展到更复杂的多轮恢复序列；本任务只覆盖一次 `exit -> empty-state -> New Tab 恢复`。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。

## Files In Scope

- `app/test/widget_test.dart`
- `docs/tasks/T-032-terminal-exit-empty-state-recover-smoke.md`
- `docs/TESTING.md`

## Functional Acceptance

- 最后一个活动 session 收到 `exit` 事件后，界面进入 empty-state。
- empty-state 下仍显示 `Create a shell to get started` 与 `New Tab`。
- 点击 `New Tab` 后重新创建 terminal tab，并重新显示 `Copy` / `Paste`。
- 本次覆盖只验证 UI 可观察恢复路径，不验证底层 session 复用策略。

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/widget_test.dart
```

## Manual QA

1. 如环境允许，运行 `flutter run -d macos`。
2. 启动应用并保持只有一个 terminal tab。
3. 在 shell 中执行 `exit`。
4. 确认界面自动回到 `Create a shell to get started`。
5. 点击 `New Tab`，确认 terminal 恢复。

## Done When

- shell `exit` -> empty-state -> `New Tab` 恢复 的最小路径有自动化覆盖。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前只覆盖单次恢复，不覆盖重复恢复或更多 tab 组合。
- 若后续需要验证 shell `exit` 后立即再次关闭/恢复的稳定性，可拆独立任务继续扩展。
