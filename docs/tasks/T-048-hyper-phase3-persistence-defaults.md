# T-048 Hyper-like Phase 3 Persistence Artifact and Defaults Model

## Goal

在 richer defaults / theme UI 之前，先落地最小 app-scoped preferences artifact 与 deterministic defaults model：把 profile catalog 与 app defaults 拆分持久化，并让 bootstrap 在 preferences / legacy profile default / fallback 之间保持可预测行为。

## Scope

- `example/lib/features/preferences/app_preferences_models.dart`
- `example/lib/features/preferences/app_preferences_repository.dart`
- `example/lib/features/sessions/session_controller.dart`
- `example/test/preferences/app_preferences_repository_test.dart`
- `example/test/sessions/session_controller_test.dart`
- `docs/TESTING.md`
- `docs/tasks/T-048-hyper-phase3-persistence-defaults.md`

## Non-goals

- 不扩展成完整 settings platform
- 不新增 defaults UI hook；若没有严格必要则继续 defer
- 不改动 Rust PTY/core
- 不改变 terminal input / selection / copy-paste / resize / scroll / exit contract
- 不引入新依赖

## Functional Acceptance

- `TerminalProfilesDocument` 继续只承载 profile catalog；app defaults 改由单独 preferences document 承载
- 启动路径执行 dual-read：preferences 优先，legacy `defaultProfileId` 仅在兼容窗口内兜底
- 新写入遵守 single-write：profile catalog 只写 profiles doc，app defaults 只写 preferences doc
- preferences 缺失时不阻塞启动；损坏时 quarantine 并 repair-write 默认文档
- default profile 指向已删除 profile 时会清空 preferences default，并 deterministic fallback 到首个可用 profile

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/preferences/app_preferences_repository_test.dart
flutter test test/sessions/session_controller_test.dart
flutter test
flutter test integration_test/flutterm_smoke_test.dart
```

## Manual QA

1. 启动 app，并确认没有 preferences 文件时仍能打开默认 session
2. 人工写入 / 修改 default profile 后重启，确认 bootstrap 选中的 profile deterministic
3. 删除当前 default profile 后重启，确认 fallback 到首个可用 profile 且不会 fatal
4. 若人为破坏 preferences JSON，重启后确认 app 可继续启动，且会生成修复后的 defaults 文档
5. 再次检查 tab lifecycle、copy / paste、scroll、resize、exit baseline 无回归

## Done When

- Phase 3 的最小 preferences artifact 已独立可持久化
- Session bootstrap precedence / migration / repair-write 合同由测试显式保护
- `docs/TESTING.md` 已同步 Phase 3 persistence/defaults 验证入口
- Flutter analyze、目标测试、全量 test、integration smoke 全部通过

## Risks / Follow-ups

- legacy `TerminalProfilesDocument.defaultProfileId` 仍处于只读兼容窗口，后续需要单独 deprecation review
- `appearance.themeMode` 目前只冻结在 schema 中，未扩展 UI 消费路径
- 若后续引入 defaults UI，必须继续沿用 app preferences 作为 source of truth，避免回写 legacy profile doc
