# T-005 多 Tab 会话生命周期稳定性

## Goal

确保 local shell 的多 tab 在创建、切换、关闭流程中行为稳定。

## Scope

- `example/test/sessions/session_controller_test.dart`
  - 增加会话创建/切换/关闭路径回归用例。
- `example/lib/features/sessions/session_controller.dart`
  - 仅限验证使用，避免超范围改动。

## Non-goals

- 不改动 tab 视觉样式。
- 不引入 split pane。
- 不修改 profile 持久化方案。

## Files In Scope

- `example/test/sessions/session_controller_test.dart`

## Functional Acceptance

- 可以从 profile 创建新 session tab。
- 切换 active tab 后继续显示/发送输入到目标 session。
- 关闭任一 tab 后，状态集中维护剩余 tabs，active 迁移到剩余 tab；关闭最后一个 tab 后无活动 session。

## Verification Commands

```bash
cd example
flutter test
```

## Manual QA

1. 启动应用。
2. 从 profile 新建两个 tab。
3. 分别执行不同命令（如 `printf a` / `printf b`）。
4. 切换 tab，确认每个 tab 的终端显示不互串。
5. 依次关闭 tab，确认关闭前端状态与焦点迁移合理。

## Done When

- 新增测试覆盖主要生命周期路径。
- 测试命令通过。

## Risks / Follow-ups

- 手工 smoke 覆盖仍建议加 tab 关闭动画/快捷键用例。
