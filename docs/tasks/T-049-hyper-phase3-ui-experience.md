# T-049 Hyper-like Phase 3 UI Experience

## Goal

在已完成的 Phase 3 persistence artifact 之上，补齐剩余的 user-facing defaults / appearance experience：提供单一 shell-scoped `Defaults & appearance` surface，让 default profile 和 theme mode 变得可见、可预测、可验证，而不扩展成完整 settings platform。

## Scope

- `example/lib/app.dart`
- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/sessions/session_state.dart`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/shell/defaults_appearance_dialog.dart`
- `example/test/app/app_theme_mode_test.dart`
- `example/test/shell/shell_screen_phase3_test.dart`
- `example/test/sessions/session_controller_phase3_test.dart`
- `example/integration_test/flutterm_smoke_test.dart`
- `docs/TESTING.md`
- `docs/tasks/T-049-hyper-phase3-ui-experience.md`

## Non-goals

- 不扩展成 general settings platform
- 不引入新的 persistence schema 字段
- 不改动 Rust PTY/core
- 不改变 terminal input / selection / copy-paste / resize / scroll / exit contract
- 不新增新的 inline default mutation path

## Functional Acceptance

- `Defaults & appearance` modal/sheet 是唯一 defaults/theme mutation surface
- sidebar 不再 inline `Set as default`
- `SessionController` 保持 defaults/theme 的唯一写入口
- UI 明确区分：
  - configured default
  - effective fallback default
- repaired/missing defaults 只显示为 fallback，不伪装成 user-selected
- `MaterialApp` 真正消费 persisted `themeMode`
- 关闭 defaults surface 后，launcher / focus / terminal input 行为不回归

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/shell/shell_screen_phase2a_test.dart
flutter test test/shell/shell_screen_phase2b_test.dart
flutter test test/shell/shell_screen_phase3_test.dart
flutter test test/sessions/session_controller_phase3_test.dart
flutter test test/preferences/app_preferences_repository_test.dart
flutter test test/preferences/app_preferences_repository_phase3_test.dart
flutter test test/app/app_theme_mode_test.dart
flutter test integration_test/flutterm_smoke_test.dart
```

## Manual QA

1. 打开 `Defaults & appearance`，确认可以看到 default profile / theme mode 当前状态
2. 切换 default profile 后新建 tab，确认使用新的 effective default
3. Reset default 后确认 UI 显示 fallback，而不是伪装成 user-selected
4. 切换 light / dark / system，确认 app chrome 真实响应
5. 关闭 defaults surface 后继续键盘输入 terminal，确认 focus 正常恢复
6. 再次确认 top actions launcher、copy/paste、tab lifecycle 无回归

## Done When

- Phase 3 剩余 UI experience 以单一 mutation surface 落地
- configured / effective default contract 有显式状态与测试保护
- themeMode 持久化与 `MaterialApp.themeMode` 真正接通
- targeted tests、integration smoke、analyze 全部通过

## Risks / Follow-ups

- 目前 shell 仍有较多硬编码颜色，theme consumption 先落在 app-level chrome，不扩成全面 reskin
- `TerminalProfilesDocument.defaultProfileId` 仍处于兼容窗口，后续要单独做 deprecation review
- 若未来扩展更多 appearance/customization，必须继续保持 `SessionController` / app preferences 为唯一写路径
