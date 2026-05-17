# T-124 Local Terminal Config Loader

## Goal

补齐 session bootstrap runtime 接入前的组合 loader：统一加载新 `LocalTerminalConfigRepository` 和旧 `AppPreferencesRepository`，并返回 bootstrap resolution。

## Scope

- `example/lib/features/config/local_terminal_config_loader.dart`
- `example/test/config/local_terminal_config_loader_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 `SessionController`
- 不自动写入新 config
- 不读取 profile list
- 不改变现有 app startup 行为
- 不新增 remote/SSH config source

## Current Progress

- 已新增 `LocalTerminalConfigLoader`。
- loader 读取 `LocalTerminalConfigRepository`。
- loader 读取 legacy `AppPreferencesRepository`。
- loader 复用 `LocalTerminalConfigBootstrap.resolve()`。
- 已补充 local-first 和 legacy fallback 测试。

## Functional Acceptance

- local config 存在时优先返回 local config。
- local config 缺失时可返回 legacy app preferences migration。
- loader 隐藏两个 repository 的协调逻辑。
- loader 不接 profile repository 或 remote config source。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/config/local_terminal_config_loader_test.dart
flutter analyze
```

## Manual QA

本任务只新增 loader，不接 runtime；无需人工 UI 验收。

## Done When

- `SessionController` 后续可通过单一 loader 读取 local terminal config。
- 新旧配置优先级在 loader 层可测试。

## Risks / Follow-ups

- 后续 session bootstrap 接入时，要避免重复写入 legacy repaired preferences。
- profile list migration 仍需单独任务。
