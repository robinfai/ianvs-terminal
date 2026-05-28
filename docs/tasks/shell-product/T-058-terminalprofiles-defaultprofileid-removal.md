# T-058 `defaultProfileId` Removal

## Goal

移除 legacy `defaultProfileId` 的 runtime/read-path，使 defaults 只剩 preferences 这一条 source-of-truth。

## Scope

- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/profiles/profile_models.dart`
- `example/lib/features/profiles/profile_repository.dart`
- `example/test/sessions/session_controller_phase3_test.dart`
- `example/test/sessions/session_controller_test.dart`
- `example/test/profiles/profile_repository_test.dart`
- `docs/TESTING.md`
- `docs/tasks/shell-product/T-058-terminalprofiles-defaultprofileid-removal.md`

## Non-goals

- 不改 shell Phase 4 行为
- 不改 Rust / PTY / FFI
- 不吸收其他 defaults/lifecycle cleanup
- 不重开 `T-055` 风险
- 不把本任务扩张成 broader settings / profile UX 重构

## Files In Scope

- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/profiles/profile_models.dart`
- `example/lib/features/profiles/profile_repository.dart`
- `example/test/sessions/session_controller_phase3_test.dart`
- `example/test/sessions/session_controller_test.dart`
- `example/test/profiles/profile_repository_test.dart`
- `docs/TESTING.md`

## Functional Acceptance

- `_legacyDefaultProfileId` 和 bootstrap legacy fallback 从运行时路径移除
- `TerminalProfilesDocument` 不再暴露 `defaultProfileId` 字段
- 旧磁盘文档即使仍带该 key，也能被忽略式读取，不导致启动失败
- tests 从“legacy fallback 受支持”改为“legacy key 被忽略且不再参与默认决策”

## Verification Commands

参考 [TESTING.md](../../TESTING.md)。

```bash
cd example
flutter analyze
flutter test test/sessions/session_controller_phase3_test.dart
flutter test test/sessions/session_controller_test.dart
flutter test test/profiles/profile_repository_test.dart
flutter test -d macos integration_test/ianvs_smoke_test.dart
```

## Manual QA

1. 有 configured default 时，新 tab 继续走 preferences default。
2. 无 configured default 时，新 tab 走 first-profile fallback，但不再依赖 legacy profile key。
3. 旧 profile 文档仍带 legacy key 时，应用仍能正常启动且不会把它当当前默认来源。

## Completion Record

- 完成时间：`2026-05-10 CST`
- 结论：`T-058` 已完成，defaults runtime/read-path 只剩 preferences source-of-truth。
- 实现状态：
  - `_legacyDefaultProfileId` 和 bootstrap legacy fallback 已从运行时路径移除。
  - `TerminalProfilesDocument` 不再暴露或写出 legacy `defaultProfileId` 字段。
  - 旧磁盘文档里的 legacy `defaultProfileId` key 仍可被安全读取，但会被忽略，且不会参与默认 profile 决策。
- 验证通过：
  - `cd example && flutter analyze`
  - `flutter test test/sessions/session_controller_phase3_test.dart`
  - `flutter test test/sessions/session_controller_test.dart`
  - `flutter test test/profiles/profile_repository_test.dart`
  - `flutter test -d macos integration_test/ianvs_smoke_test.dart`
- 环境说明：
  - 当前 host 上不带 `-d macos` 的 integration smoke 可能卡在 Flutter device discovery，因为 Android `adb devices` 路径异常。
  - 这属于验证环境问题，不是 `T-058` 产品回归。

## Done When

- removal 范围内代码与测试完成
- legacy runtime/read-path 已移除，旧磁盘 key 只剩可忽略的历史输入
- 若 `docs/TESTING.md` 文案需要更新则已同步
- 没有把任务扩张成 broader defaults/lifecycle cleanup

## Risks / Follow-ups

- 若 removal 后仍发现旧文档兼容残角，另开 focused follow-up，不回退到 dual-source runtime
- `T-055 forced-closed` 的 terminal manual-matrix 风险继续留在 shared docs，与本任务无关
- 当前 removal 决策继续以 `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md` 为唯一 decision record
