# T-125 Local Config Preferences Adapter

## Goal

补齐 local config 到现有 app preferences 形态的兼容 adapter，让后续 `SessionController` 可以先消费 defaults/appearance，而不立刻替换 profile/preferences 全路径。

## Scope

- `example/lib/features/config/local_terminal_config_preferences_adapter.dart`
- `example/test/config/local_terminal_config_preferences_adapter_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 `SessionController`
- 不写入旧 preferences 文件
- 不迁移 profiles list
- 不处理 keybindings/workspace/policy runtime
- 不新增 remote/SSH fields

## Current Progress

- 已新增 `LocalTerminalConfigPreferencesAdapter`。
- adapter 可将 `LocalTerminalConfigDocument.defaultProfileId` 映射到 `TerminalAppDefaults.defaultProfileId`。
- adapter 可将 `LocalTerminalConfigDocument.appearance` 映射到旧 app preferences appearance。
- 已补充 defaults/appearance mapping 测试。

## Functional Acceptance

- local config 可转换为现有 app preferences document。
- default profile 和 theme mode 能保持兼容。
- adapter 不触碰 profile repository。
- adapter 不引入 remote/SSH 配置字段。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/config/local_terminal_config_preferences_adapter_test.dart
flutter analyze
```

## Manual QA

本任务只新增 adapter，不接 runtime；无需人工 UI 验收。

## Done When

- `SessionController` 后续可先用 local config 驱动现有 defaults/appearance 路径。
- 新旧配置兼容接入风险降低。

## Risks / Follow-ups

- 后续 keybindings/workspace/policy 仍需走新 config，不应继续扩展旧 preferences model。
