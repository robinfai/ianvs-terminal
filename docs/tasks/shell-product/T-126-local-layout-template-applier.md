# T-126 Local Layout Template Applier

## Goal

把 P5 local-only layout template 推进到可生成 P2 `TerminalWorkspace` intent 的 applier，让 template 不只停留在 repository/model 层。

## Scope

- `example/lib/features/visual/local_terminal_layout_template_applier.dart`
- `example/test/visual/local_terminal_layout_template_applier_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接 UI
- 不启动真实 session
- 不保存 workspace layout
- 不支持 remote template
- 不实现复杂多层布局模板

## Current Progress

- 已新增 `LocalTerminalLayoutTemplateApplyContext`。
- 已新增 `LocalTerminalLayoutTemplateApplier.apply()`。
- applier 可把 one-pane local template 转成 `TerminalWorkspace`。
- applier 可把 two-pane local template 转成 split workspace。
- non-local template 会被拒绝。
- 已补充 one-pane、two-pane、non-local reject 测试。

## Functional Acceptance

- local-only template 可以生成 workspace intent。
- one-pane template 生成单 leaf pane。
- two-pane template 生成 split pane tree。
- non-local template 返回 null。
- applier 不启动或恢复进程状态。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/visual/local_terminal_layout_template_applier_test.dart
flutter analyze
```

## Manual QA

本任务只新增 applier，不接 UI；无需人工 UI 验收。

## Done When

- P5 layout template 可以生成 P2 workspace model。
- 后续 template picker 可把选中模板交给 applier 再更新 workspace。

## Risks / Follow-ups

- 后续需要支持更丰富的 pane topology。
- 后续需要把 applier 接入 visual action reducer / side-effect executor。
