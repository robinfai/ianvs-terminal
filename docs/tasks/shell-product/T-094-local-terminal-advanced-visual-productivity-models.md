# T-094 Local Terminal Advanced Visual Productivity Models

## Goal

补齐 P5 中剩余的 theme import/export、profile-level theme override、timestamps、command pane、scrollback export 和 graphics/image storage policy 的模型层。

## Scope

- `example/lib/features/visual/local_terminal_visual_models.dart`
- `example/test/visual/local_terminal_visual_models_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 renderer
- 不实现 theme picker UI
- 不实际读写 theme 文件
- 不实现 command pane UI
- 不实际导出 scrollback 文件
- 不实现图片渲染或图片缓存

## Current Progress

- `LocalTerminalThemePreset` 已支持 JSON encode/decode，作为 theme import/export 的模型基础。
- 已新增 `LocalTerminalProfileThemeOverride`。
- 已新增 `LocalTerminalCommandTimestampPolicy`。
- 已新增 `LocalTerminalCommandPanePolicy`。
- 已新增 `LocalTerminalScrollbackExportPolicy`。
- 已新增 `LocalTerminalGraphicsStoragePolicy`。
- 已补充 import/export、profile override、timestamp/command pane、scrollback export 和 graphics storage policy 测试。

## Functional Acceptance

- theme preset 可序列化为可导入/导出的 JSON 结构。
- profile-level theme override 可按 profile id 匹配。
- timestamps 和 command pane 默认可关闭。
- scrollback export policy 可声明格式和 metadata 策略。
- graphics storage policy 可限制图片大小，并默认不启用。

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

- P5 剩余高级视觉和生产力能力都有可复用模型。
- 后续 UI/runtime 接入可以保持默认路径简单、advanced feature 可关闭。

## Risks / Follow-ups

- 后续 theme import/export 需要文件 IO 和错误诊断。
- command pane 与 timestamps 需要和 shell integration feature gates 结合。
- graphics storage policy 后续必须和 renderer decision point 保持解耦。
