# T-013 Terminal 空状态通过 New Tab 恢复 Smoke

## Goal

补一条最小自动化 smoke，验证 terminal 在关闭最后一个 tab 回到 empty-state 后，仍可通过现有 `New Tab` 入口恢复并重新创建可交互的 shell tab。

## Scope

- `app/integration_test/flutterm_smoke_test.dart`
  - 增加一条“empty-state 下点击 `New Tab` 可恢复 terminal tab”的 UI 冒烟检查。
- `docs/tasks/T-013-terminal-empty-state-recover-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不自动化真实 shell 命令执行或 PTY 往返。
- 不覆盖 SSH、split pane、跨平台桌面行为，或其他 Phase 1 以外能力。
- 不扩展到 tab 重命名、profile 编辑、shell 退出事件自动关 tab 等其他流程。
- 不改动 session 生命周期架构；如果现有逻辑已满足需求，本任务只新增 smoke 覆盖。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。
- 不借机改写 empty-state 文案、`New Tab` 入口形态或主界面结构。

## Files In Scope

- `app/integration_test/flutterm_smoke_test.dart`
- `docs/tasks/T-013-terminal-empty-state-recover-smoke.md`

## Functional Acceptance

- 自动化 smoke 以单 tab terminal 启动，且初始 tab 处于激活状态。
- 通过现有 tab 关闭入口关闭最后一个剩余 tab，进入 empty-state。
- empty-state 下仍可见 `Create a shell to get started` 与 `New Tab` 入口。
- 点击 `New Tab` 后重新创建 terminal tab，并重新显示 `Local Shell` 的 `InputChip`。
- 恢复后 `Copy` / `Paste` 等与活动 session 绑定的主界面控件重新可见，说明 UI 已从 empty-state 返回到可交互 terminal 视图。
- 本次 smoke 只验证 UI 可观察恢复路径，不验证更底层的 session 资源释放或重建细节。

## Verification Commands

参考 [../TESTING.md](/Users/robinfai/personal/flutterm/docs/TESTING.md)：

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test
flutter test integration_test/flutterm_smoke_test.dart
```

## Manual QA

1. 如环境允许，仍建议运行 `flutter run -d macos`。
2. 手工启动应用，确认默认 shell tab 已打开。
3. 关闭最后一个剩余 tab，确认主区域出现 `Create a shell to get started`。
4. 点击 `New Tab`。
5. 确认新的 terminal tab 被创建，且 `Copy` / `Paste` 等主界面控件重新出现。

## Done When

- 自动化 smoke 覆盖了“关闭最后一个 tab 后通过 `New Tab` 恢复 terminal”的最小用户路径。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 若 empty-state 下的 `New Tab` 入口在 integration test 中不够稳定，可在同一 smoke 文件内做最小可测试性调整，但不扩展框架。
- 当前 smoke 只验证 UI 可观察恢复结果，不验证底层 session 对象是否复用或重新创建。
- 若后续需要覆盖“恢复后再次关闭 / 多次重复恢复”的稳定性，建议拆新任务继续扩展。
