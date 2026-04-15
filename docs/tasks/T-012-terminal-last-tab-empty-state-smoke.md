# T-012 Terminal 最后一个 Tab 关闭后回到空状态 Smoke

## Goal

补一条最小自动化 smoke，验证关闭最后一个剩余 tab 后，terminal 主区域会返回空状态提示，而不是停留在失焦或异常 UI。

## Scope

- `app/integration_test/flutterm_smoke_test.dart`
  - 增加一条“关闭最后一个 tab 后返回 empty-state prompt”的 UI 冒烟检查。
- `docs/tasks/T-012-terminal-last-tab-empty-state-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不自动化真实 shell 命令执行或 PTY 往返。
- 不覆盖 SSH、split pane、跨平台桌面行为，或其他 Phase 1 以外能力。
- 不扩展到 tab 重命名、profile 编辑、shell 退出事件自动关 tab 等其他流程。
- 不改动 session 生命周期架构；如果现有逻辑已满足需求，本任务只新增 smoke 覆盖。
- 不引入新的测试框架、桌面自动化依赖或额外 harness。
- 不借机改写 empty-state 文案或主界面结构。

## Files In Scope

- `app/integration_test/flutterm_smoke_test.dart`
- `docs/tasks/T-012-terminal-last-tab-empty-state-smoke.md`

## Functional Acceptance

- 自动化 smoke 以单 tab terminal 启动，且初始 tab 处于激活状态。
- 通过现有 tab 关闭入口关闭最后一个剩余 tab。
- 关闭后 tab 条目消失，不再显示任何 terminal tab `InputChip`。
- terminal 主区域显示空状态提示 `Create a shell to get started`。
- 与活动 session 绑定的主界面控件（如 `Copy` / `Paste`）不再显示，而 `New Tab` 入口仍可见，说明 UI 已回到可恢复的 empty-state，而不是残留在失效 terminal 视图。

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
3. 关闭最后一个剩余 tab。
4. 确认主区域出现 `Create a shell to get started`。
5. 确认 `Copy` / `Paste` 已消失，且仍可看到 `New Tab` 入口用于重新创建 shell。

## Done When

- 自动化 smoke 覆盖了“关闭最后一个 tab 后返回 empty-state prompt”的最小用户路径。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 若当前 `InputChip.onDeleted` 入口不足以稳定表达“关闭最后一个 tab”，可在同一 smoke 文件内做最小可测试性调整，但不扩展框架。
- 当前 smoke 只验证 UI 可观察结果，不验证更底层的 session 资源释放或 core 生命周期清理。
- 若后续需要覆盖“关闭最后一个 tab 后立即再次新建 tab”的恢复路径，建议拆新任务继续扩展。
