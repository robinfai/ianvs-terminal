# T-304 Command Lifecycle Degraded State

## Goal

定义 shell integration 缺失、hook 顺序异常和 range 缺失时的降级状态。

## Scope

- 建立 Command Center unavailable reason、limited capability 和 disabled action reason。
- 覆盖 shell integration disabled、unknown hook、missing command、missing cwd、missing output range 和 out-of-order lifecycle。
- 让 Search、Blocks、Sticky Header 和 Review 可以共享同一套降级判断。

## Non-goals

- 不实现 UI 文案组件。
- 不实现 command search overlay。
- 不实现 command block renderer。
- 不修改 shell hook event schema。
- 不用异常控制正常降级路径。

## Files In Scope

- `example/lib/features/command_center/command_lifecycle_degraded_state.dart`
- `example/test/command_center/command_lifecycle_degraded_state_test.dart`

## Functional Acceptance

- shell integration 关闭时不抛异常。
- Search 可继续使用已有 history；依赖 live hook 的能力显示 unavailable reason。
- Blocks、Sticky Header 和 Review entrypoints 在缺少 lifecycle 或 range 时禁用，并返回明确 reason。
- 缺失 output range 不允许执行 copy output。
- out-of-order lifecycle 不会污染其他 session 的状态。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。建议最小验证：

```bash
cd example
flutter analyze
flutter test test/command_center/command_lifecycle_degraded_state_test.dart
```

## Manual QA

纯状态任务，无需 UI QA。后续 UI 任务必须复用这些 reason，并在对应 widget/manual QA 中验证用户可见文案。

## Done When

- 每个 Command Center action 都能得到 enabled、disabled 或 unavailable 的明确原因。
- 降级状态有单元测试覆盖。
- 后续 UI 不需要自行发明 unavailable 判断。

## Risks / Follow-ups

- 降级 reason 过细会增加 UI 噪音；后续 widget 可将多个内部 reason 映射到同一用户文案。
- 如果 shell hook 契约后续扩展，需要补充新的 reason 和测试。
