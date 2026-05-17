# T-113 Local Terminal Layout Template Repository

## Goal

补齐 P5 layout templates 的本地持久化边界，让 local-only layout templates 可以独立保存、读取和 corrupt repair。

## Scope

- `example/lib/features/visual/local_terminal_visual_models.dart`
- `example/lib/features/visual/local_terminal_layout_template_repository.dart`
- `example/test/visual/local_terminal_layout_template_repository_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接 workspace runtime
- 不创建真实 pane
- 不保存 remote/SSH template
- 不接 UI
- 不实现模板导入/导出

## Current Progress

- `LocalTerminalLayoutTemplate` 已支持 JSON serialization。
- 已新增 `LocalTerminalLayoutTemplateRepository`。
- template 文件路径为 `flutterm_layout_templates.json`。
- repository 只保存/读取 `localOnly == true` 的 templates。
- 缺失文件返回空列表。
- corrupt 文件会 quarantine 并写入空列表。
- 已补充 missing、local-only roundtrip、corrupt repair 测试。

## Functional Acceptance

- local-only layout templates 可以落盘和读取。
- remote/non-local template 不会被保存或加载。
- corrupt template 文件有 quarantine 和 repair。
- repository 不接 workspace runtime 或 remote session。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/visual/local_terminal_layout_template_repository_test.dart
flutter analyze
```

## Manual QA

本任务只新增 repository，不接 UI；无需人工 UI 验收。

## Done When

- P5 layout template persistence 边界可复用。
- 后续 template picker/UI 可以基于 local-only repository 接入。

## Risks / Follow-ups

- 后续需要把 template 应用到 `TerminalWorkspace`。
- 后续需要模板导入/导出的冲突策略。
