# T-011 Terminal 非激活 Tab 关闭焦点自动化 Smoke

## Goal

补一条最小自动化 smoke，验证在多 tab 场景下关闭**非激活** tab 时，当前激活 tab 不会被错误抢焦点。

## Scope

- `example/integration_test/flutterm_smoke_test.dart`
  - 增加一条“关闭非激活 tab 后保持当前焦点”的 UI 冒烟检查。
- `docs/tasks/terminal-interaction/T-011-terminal-inactive-tab-close-focus-smoke.md`
  - 记录本次任务范围、验收、验证与风险。

## Non-goals

- 不自动化真实 shell 命令执行或 PTY 往返。
- 不覆盖 tab 重命名、退出事件自动关 tab、profile 编辑等其他流程。
- 不改动 session 生命周期核心逻辑；如果现有逻辑已满足需求，本任务只新增 smoke 覆盖。
- 不引入新的测试框架或桌面自动化依赖。
- 不扩展到 SSH、split pane、跨平台桌面行为。

## Files In Scope

- `example/integration_test/flutterm_smoke_test.dart`
- `docs/tasks/terminal-interaction/T-011-terminal-inactive-tab-close-focus-smoke.md`

## Functional Acceptance

- 自动化 smoke 能创建两个 tab，并切换到目标激活 tab。
- 当 `Shell B` 为当前激活 tab 时，关闭**未激活**的 `Shell A` 后，`Shell B` 仍保持激活状态。
- 关闭动作后 terminal 主界面基础控件（如 `Copy` / `Paste`）仍保持可见，说明主视图未失焦或异常消失。
- 本次 smoke 只验证 UI 可观察焦点结果，并与 `T-006` 的既有非激活关闭规则保持一致。

## Verification Commands

参考 [TESTING.md](../../TESTING.md)：

```bash
cd example
flutter analyze
flutter test
flutter test integration_test/flutterm_smoke_test.dart
```

## Manual QA

1. 如环境允许，仍建议运行 `flutter run -d macos`。
2. 手工打开两个 shell tab，并切换到第二个 tab。
3. 在第二个 tab 保持激活时，关闭第一个（非激活）tab。
4. 确认第二个 tab 仍保持焦点，terminal 仍可继续交互。

## Done When

- 自动化 smoke 覆盖了“关闭非激活 tab 不改变当前焦点”的最小用户路径。
- 相关验证命令通过。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 当前 smoke 只验证 UI 可观察焦点结果，不验证更底层的 session 资源释放。
- 若现有 `InputChip` 删除入口不足以稳定表达“关闭非激活 tab”，可在同一 smoke 文件内做最小可测试性调整，但不扩展框架。
- 更复杂的多 tab 顺序、批量关闭或退出事件联动，建议继续拆独立任务。
