# T-080 Local Terminal Config Schema Foundation

## Goal

建立 `LocalTerminalConfig` 的最小 schema 模型，为 P1 后续配置迁移、keybinding override、禁用默认快捷键、clipboard/paste/notification/hotkey window 配置提供统一文档对象。

## Scope

- `example/lib/features/config/local_terminal_config_models.dart`
- `example/test/config/local_terminal_config_models_test.dart`
- `docs/tasks/README.md`

## Non-goals

- 不接管现有 `ProfileRepository` 或 `AppPreferencesRepository`
- 不改变 `flutterm_profiles.json` 或 `flutterm_preferences.json` 的读写行为
- 不实现完整配置 UI
- 不实现 live reload
- 不新增 SSH、remote、serial、SFTP 顶层字段

## Current Progress

- 已新增 `LocalTerminalConfigDocument`，覆盖 schemaVersion、defaultProfileId、appearance、keybindings、workspace、clipboard、paste、shellIntegration、notifications、hotkeyWindow。
- 已新增 keybinding override / disabled default action 的 schema 模型。
- 已新增 clipboard、paste、shell integration、notifications、hotkey window 的最小配置对象。
- 已新增 remote-only top-level field 拒绝逻辑，防止把 SSH/remote/SFTP/serial 混入本地配置 schema。
- 已补充本地配置模型的默认值、forbidden fields 和 keybinding roundtrip 测试。

## Functional Acceptance

- `LocalTerminalConfigDocument.fromJson({})` 能返回完整默认配置。
- schema 可表达 keybinding override 和 disabled default action。
- schema 可表达 clipboard/paste/shellIntegration/notifications/hotkeyWindow 的最小配置边界。
- 出现 SSH、remote、SFTP、serial 等顶层字段时抛出格式错误。
- 现有 profile/preferences 读写路径不受影响。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/config/local_terminal_config_models_test.dart
flutter analyze
```

## Manual QA

本任务只新增配置模型，不改变 runtime UI 或启动路径；无需人工 UI 验收。

## Done When

- Local config schema foundation 可被后续 repository/migration 任务复用
- forbidden remote-only fields 有模型级保护
- 相关模型测试通过

## Risks / Follow-ups

- 后续需要独立任务实现 repository、migration adapter 和 legacy file fallback。
- 后续需要把 registry 的 default keybinding metadata 和 config override 合并成实际 resolver。
