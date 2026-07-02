# T-014 Terminal 空状态恢复后再次关闭 Smoke

## Goal

补一条最小自动化 smoke，验证 terminal 从 empty-state 通过 `New Tab` 恢复后，还能再次关闭并重新回到 empty-state。

## Scope

- `example/integration_test/ianvs_terminal_smoke_test.dart`
  - 增加一条“恢复后的 tab 再次关闭后回到 empty-state”的 UI 冒烟检查。
- `docs/tasks/terminal-interaction/T-014-terminal-empty-state-repeat-cycle-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不自动化真实 shell 命令执行或 PTY 往返。
- 不覆盖 SSH、split pane、跨平台桌面行为，或其他 Phase 1 以外能力。
- 不扩展到 tab 重命名、profile 编辑、shell 退出事件自动关 tab 等其他流程。
- 不改动 session 生命周期架构；如果现有逻辑已满足需求，本任务只新增 smoke 覆盖。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。
- 不借机改写 empty-state 文案、`New Tab` 入口形态或主界面结构。

## Files In Scope

- `example/integration_test/ianvs_terminal_smoke_test.dart`
- `docs/tasks/terminal-interaction/T-014-terminal-empty-state-repeat-cycle-smoke.md`

## Functional Acceptance

- 自动化 smoke 先关闭最后一个 tab，进入 empty-state。
- 在 empty-state 点击 `New Tab` 后恢复 terminal tab。
- 再次关闭恢复出来的最后一个 tab 后，主区域重新出现 `Create a shell to get started`。
- 第二次回到 empty-state 后，不显示 `Copy` / `Paste`，但仍显示 `New Tab` 入口。

## Verification Commands

参考 [TESTING.md](../../TESTING.md)：

```bash
cd example
flutter analyze
flutter test
flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart
```

## Manual QA

1. 如环境允许，仍建议运行 `flutter run -d macos`。
2. 手工启动应用并关闭最后一个 tab，确认进入 empty-state。
3. 点击 `New Tab` 恢复 terminal。
4. 再次关闭恢复出来的 tab。
5. 确认主区域再次回到 `Create a shell to get started`。

## Done When

- 自动化 smoke 覆盖了“empty-state -> 恢复 -> 再次回到 empty-state”的最小用户路径。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前 smoke 只验证 UI 可观察恢复结果，不验证底层 session 对象的重复创建/释放细节。
- 若后续需要覆盖更多循环次数或更复杂的恢复序列，建议拆新任务继续扩展。
