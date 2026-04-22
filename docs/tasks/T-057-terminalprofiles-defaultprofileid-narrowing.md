# T-057 `defaultProfileId` Narrowing

## Goal

把 `defaultProfileId` 的 legacy 兼容窗口收紧到“保留兼容读取与过渡启动”，不再把 legacy field 当 steady-state live source。

## Scope

- `app/lib/features/sessions/session_controller.dart`
- `app/lib/features/profiles/profile_models.dart`
- `app/lib/features/profiles/profile_repository.dart`
- `app/lib/features/shell/defaults_appearance_dialog.dart`
- `app/lib/features/shell/shell_screen.dart`
- `app/test/sessions/session_controller_phase3_test.dart`
- `app/test/sessions/session_controller_test.dart`
- `app/test/profiles/profile_repository_test.dart`
- `app/test/shell/shell_screen_phase3_test.dart`
- `app/integration_test/flutterm_smoke_test.dart`
- `docs/TESTING.md`
- `docs/tasks/T-057-terminalprofiles-defaultprofileid-narrowing.md`

## Non-goals

- 不做 `defaultProfileId` 完全 removal
- 不删除 preferences 缺失时的 bootstrap legacy fallback
- 不改 Rust core / PTY / FFI / terminal 行为
- 不改 `T-055 forced-closed` 留下的 manual-matrix 风险状态
- 不创建 removal task，也不把本任务扩张成完整 deprecation

## Files In Scope

- `app/lib/features/sessions/session_controller.dart`
- `app/lib/features/profiles/profile_models.dart`
- `app/lib/features/profiles/profile_repository.dart`
- `app/lib/features/shell/defaults_appearance_dialog.dart`
- `app/lib/features/shell/shell_screen.dart`
- `app/test/sessions/session_controller_phase3_test.dart`
- `app/test/sessions/session_controller_test.dart`
- `app/test/profiles/profile_repository_test.dart`
- `app/test/shell/shell_screen_phase3_test.dart`
- `app/integration_test/flutterm_smoke_test.dart`
- `docs/TESTING.md`

## Functional Acceptance

- preferences 继续是唯一 canonical default source
- 正常 `saveProfile()` / `deleteProfile()` 流程不再把 legacy `defaultProfileId` 当 steady-state live state 回写
- 旧 profile 文档仍能被 tolerant read，preferences 缺失时的 bootstrap legacy fallback 继续保留
- shell/defaults UI 不再把 legacy fallback 表述成常态默认路径

## Verification Commands

参考 [TESTING.md](/Users/robinfai/personal/flutterm/docs/TESTING.md)。

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/sessions/session_controller_phase3_test.dart
flutter test test/sessions/session_controller_test.dart
flutter test test/profiles/profile_repository_test.dart
flutter test test/shell/shell_screen_phase3_test.dart
flutter test integration_test/flutterm_smoke_test.dart
```

## Manual QA

1. 设置显式 default profile 后，新 tab 继续走 preferences default。
2. 删除当前 configured default 后，UI 回到正常 fallback 表达，但不把 legacy fallback 写成 steady-state。
3. 在 preferences 缺失、旧 profile 文档仍带 legacy field 的情况下，应用仍能 bootstrap。
4. defaults / shell 文案没有回退到兼容窗口措辞。

## Done When

- narrowing 范围内代码与测试完成
- 兼容读取仍在，steady-state legacy write-through 已收紧
- 若 `docs/TESTING.md` 文案需要更新则已同步
- 没有创建 removal task，也没有把本任务扩张成完整 deprecation

## Risks / Follow-ups

- removal 仍需后续单独任务，不在 `T-057` 内提前吸收
- `T-055 forced-closed` 的 terminal manual-matrix 风险继续留在 shared docs，与本任务无关
- 当前唯一 decision record 继续是 `.omx/plans/review-terminalprofiles-defaultprofileid-deprecation.md`
