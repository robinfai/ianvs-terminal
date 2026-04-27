# T-010 Terminal 多 Tab 关闭焦点自动化 Smoke

## Goal

为多 tab 场景补一条最小自动化 smoke，用来验证关闭当前激活 tab 后，剩余 tab 会保持正确焦点。

## Scope

- `example/integration_test/flutterm_smoke_test.dart`
  - 增加多 tab close/focus 的 UI 冒烟检查。
- `docs/tasks/T-010-terminal-multi-tab-close-focus-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不自动化真实 shell 命令执行或 PTY 往返。
- 不覆盖 tab 重命名、退出事件自动关 tab、profile 编辑等其他流程。
- 不改动 session 生命周期核心逻辑；如果现有逻辑已满足需求，本任务只新增 smoke 覆盖。
- 不引入新的测试框架或桌面自动化依赖。

## Files In Scope

- `example/integration_test/flutterm_smoke_test.dart`
- `docs/tasks/T-010-terminal-multi-tab-close-focus-smoke.md`

## Functional Acceptance

- 自动化 smoke 能创建两个 tab，并切换激活目标 tab。
- 关闭当前激活 tab 后，剩余 tab 仍为激活状态。
- 关闭动作后 terminal 主界面基础控件（如 `Copy` / `Paste`）仍保持可见，说明主视图未失焦或异常消失。

## Verification Commands

参考 [../TESTING.md](../TESTING.md)：

```bash
cd example
flutter analyze
flutter test
flutter test integration_test/flutterm_smoke_test.dart
```

## Manual QA

1. 如环境允许，仍建议运行 `flutter run -d macos`。
2. 手工打开两个 shell tab。
3. 切换到第二个 tab，再关闭当前激活 tab。
4. 确认剩余 tab 成为当前焦点，terminal 仍可继续交互。

## Done When

- 自动化 smoke 覆盖了多 tab close/focus 的最小用户路径。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前 smoke 只验证 UI 可观察焦点结果，不验证更底层的 session 资源释放。
- 若后续要覆盖“关闭非激活 tab 不改变焦点”等更细规则，建议拆新任务继续扩展。
