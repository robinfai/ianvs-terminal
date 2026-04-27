# T-006 多 Tab 关闭行为保留当前活跃会话

## Goal

修复关闭非当前激活 tab 时不应改变当前激活会话的问题，保证关闭任意 tab 后，焦点只在被关闭 tab 被激活时才迁移。

## Scope

- `example/lib/features/sessions/session_controller.dart`
- `example/test/sessions/session_controller_test.dart`

## Non-goals

- 不改变 tab 的创建、重命名或退出行为。
- 不改动 profile 持久化逻辑。
- 不调整 session 生命周期事件（如 `exit` 自动关闭）——本任务仅处理关闭动作对 active 切换的逻辑。

## Files In Scope

- `example/lib/features/sessions/session_controller.dart`
- `example/test/sessions/session_controller_test.dart`

## Functional Acceptance

- 当关闭当前未激活的 tab 时，`activeSessionId` 保持原值，不发生跳转。
- 关闭当前激活的 tab 时，仍按既有行为切换到剩余 tabs 的 `last` 会话。
- 变更有对应回归测试。

## Verification Commands

```bash
cd example
flutter analyze
flutter test
```

## Manual QA

1. 启动应用。
2. 打开 3 个 shell tab（A/B/C），并保持 B 为当前焦点。
3. 关闭 A tab。
4. 验证焦点仍在 B，终端画面不切换。
5. 再关闭 B tab，验证焦点切到剩余的 C。

## Done When

- 关闭非激活 tab 时不改变 active session。
- 单测覆盖该行为。
- `flutter analyze` 与 `flutter test` 命令通过。

## Risks / Follow-ups

- `exit` 事件自动关闭 tab 的策略已拆到 `docs/tasks/T-018-terminal-exit-tab-handling.md` 单独推进，避免与本任务的手动关闭焦点规则耦合。
