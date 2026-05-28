# T-103 Local Terminal Theme Repository

## Goal

补齐 P5 theme import/export 的文件边界，让 theme preset 可以独立保存、读取、导出，并具备 corrupt repair 行为。

## Scope

- `example/lib/features/visual/local_terminal_theme_repository.dart`
- `example/test/visual/local_terminal_theme_repository_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P5_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 theme picker UI
- 不改变 app theme runtime
- 不导入外部文件选择器
- 不实现 profile-level theme application
- 不触碰 renderer

## Current Progress

- 已新增 `LocalTerminalThemeRepository`。
- theme list 文件路径为 `ianvs_themes.json`。
- 缺失 theme 文件时返回空列表。
- corrupt theme list 会 quarantine 并写入空列表。
- 已新增单个 preset export 到 `<id>.ianvs terminal-theme.json`。
- 已补充 missing、roundtrip、export、corrupt repair 测试。

## Functional Acceptance

- theme presets 可以落盘和读取。
- 单个 theme preset 可以导出为 JSON 文档。
- 缺失文件不影响默认路径。
- corrupt theme list 有 quarantine 和 empty repair。
- repository 不接 renderer 或插件系统。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/visual/local_terminal_theme_repository_test.dart
flutter analyze
```

## Manual QA

本任务只新增 repository，不接入 UI；无需人工 UI 验收。

## Done When

- P5 theme import/export 的文件层闭环可用。
- 后续 UI 接入不需要重新实现 theme 文件读写。

## Risks / Follow-ups

- 后续需要导入单个外部 theme 文件并处理 id 冲突。
- 后续需要 profile-level override 与 runtime appearance 合并规则。
