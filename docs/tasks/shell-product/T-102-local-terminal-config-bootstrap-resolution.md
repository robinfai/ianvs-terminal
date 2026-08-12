# T-102 Local Terminal Config Bootstrap Resolution

> Historical task record. Compatibility resolution was superseded by the
> current-schema-only bootstrap; predecessor preference files are not read.

## Goal

补齐 P1 的 current `LocalTerminalConfig` 与内建 defaults 的 bootstrap 规则。

## Scope

- `example/lib/features/config/local_terminal_config_bootstrap.dart`
- `example/test/config/local_terminal_config_bootstrap_test.dart`
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 session bootstrap runtime
- 不替换 `ProfileRepository`
- 不读取 `ianvs_profiles.json`
- 不自动写入 `ianvs_config.json`
- 不新增 remote/SSH config source

## Current Progress

- 已新增 `LocalTerminalConfigBootstrapResult`。
- 已新增 `LocalTerminalConfigBootstrapSource`。
- 已新增 `LocalTerminalConfigBootstrap.resolve()`。
- bootstrap 优先级：current local config > defaults。
- 已补充 local-first、defaults fallback 与 noncurrent fail-closed 测试。

## Functional Acceptance

- 新 config 存在时优先使用新 config。
- current config 缺失时使用 safe defaults。
- bootstrap 不改变旧 profile repository 的读取职责。
- bootstrap 不引入 SSH/remote config source。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter test test/config/local_terminal_config_bootstrap_test.dart
flutter analyze
```

## Manual QA

本任务只新增 bootstrap resolver，不接入 runtime；无需人工 UI 验收。

## Done When

- P1 current config 的配置优先级有可复用 resolver。
- 后续 session bootstrap 接入可以直接使用该 resolver。

## Risks / Follow-ups

- 后续仍需实际接入 session controller。
- profile list 仍由独立 current `ProfileRepository` 负责。
