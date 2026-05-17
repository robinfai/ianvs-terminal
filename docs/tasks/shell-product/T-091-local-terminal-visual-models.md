# T-091 Local Terminal Visual Models

## Goal

建立 P5 的 theme preset、light/dark paired theme、pane visual policy、layout template 和 advanced visual risk 模型，先定义视觉配置语义，不触碰 renderer rewrite。

## Scope

- `example/lib/features/visual/local_terminal_visual_models.dart`
- `example/test/visual/local_terminal_visual_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不改 renderer
- 不接入 theme picker UI
- 不导入/导出 theme 文件
- 不实现 blur/background image/opacity
- 不引入 plugin system

## Current Progress

- 已新增 `LocalTerminalColorScheme`。
- 已新增 `LocalTerminalThemePreset`，支持 light/dark paired scheme。
- 已新增 `LocalTerminalPaneVisualPolicy`。
- 已新增 `LocalTerminalLayoutTemplate`，并明确 local-only apply gate。
- 已新增 `LocalTerminalAdvancedVisualPolicy`，可标记 renderer-risk options。
- 已补充 theme pairing、pane divider、local-only template、renderer-risk 测试。

## Functional Acceptance

- theme preset 可以根据亮/暗模式返回对应配色。
- pane visual policy 可表达 divider 与 inactive pane 规则。
- layout template 必须是 local-only 才可应用。
- advanced visual policy 可以识别 blur/background/opacity 等 renderer-risk 选项。
- 本任务不触碰 renderer rewrite。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/visual/local_terminal_visual_models_test.dart
flutter analyze
```

## Manual QA

本任务只新增纯模型，不接入 UI；无需人工 UI 验收。

## Done When

- P5 的视觉配置和高级能力边界有可复用模型。
- 后续 UI/theme 接入不需要重新定义 local-only 和 renderer-risk 语义。

## Risks / Follow-ups

- 后续 theme import/export 需要文件格式和冲突策略。
- advanced visual options 需要继续作为后置能力，不应阻塞默认路径。
