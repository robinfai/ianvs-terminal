# T-066 macOS App Shortcut Modifier Narrowing for Terminal Control-Key Delivery

## Goal

修掉 macOS terminal focus 下 app shortcut 抢占 `Ctrl` 控制键的问题，
让 `Ctrl+T`、`Ctrl+V` 重新进入 terminal input 路径。

## Scope

- 收窄 macOS / iOS 的 app-scoped shortcut modifier，只认 `Meta`。
- 让 `Ctrl+T`、`Ctrl+V` 在 terminal focus 下不再被 app shortcut /
  paste shortcut 截走。
- 保持非 macOS 平台继续使用 `Ctrl` 作为 app modifier。
- 补齐 shell / input controller / widget 回归。

## Non-goals

- 不扩展 shortcut surface，也不重做 Phase 2B command model。
- 不修改 Rust PTY / core。
- 不把 `Ctrl+C`、`Cmd+T`、`Cmd+Shift+P`、`Cmd+C/V` 的现有契约一起重写。
- 不把这张卡扩成“完整 VT220 兼容性”任务。

## Files In Scope

- `example/lib/features/shell/shell_screen.dart`
- `packages/flutterm_terminal/lib/src/terminal/terminal_input_controller.dart`
- `example/test/widget_test.dart`
- `example/test/shell/shell_screen_phase2b_test.dart`
- `example/test/terminal_input_controller_test.dart`
- `docs/tasks/T-066-macos-app-shortcut-modifier-narrowing-for-terminal-control-key-delivery.md`

## Functional Acceptance

- macOS / iOS 上 app-scoped shortcut 只响应 `Meta` 组合键。
- terminal focus 下，`Ctrl+T` 不再新开 tab，而是继续交给 terminal。
- terminal focus 下，`Ctrl+V` 不再触发 app/session paste shortcut，而是继续交给 terminal。
- 非 macOS 平台仍允许 `Ctrl+T`、`Ctrl+Shift+P` 作为 app-scoped shortcuts。
- `Cmd+T`、`Cmd+Shift+P`、`Cmd+C`、`Cmd+V` 在 macOS 上的现有行为不回归。
- `Ctrl+C` 中断契约不回归。

## Verification Commands

```bash
cd example
flutter analyze
flutter test test/widget_test.dart
flutter test test/shell/shell_screen_phase2b_test.dart
flutter test test/terminal_input_controller_test.dart
flutter test integration_test/flutterm_smoke_test.dart
```

## Manual QA

1. 在 macOS 默认 shell tab 中确认 `Cmd+T` 仍会新开 tab。
2. 在同一 tab 中确认 `Cmd+Shift+P` 仍会打开 launcher。
3. 切到 VT220 profile 运行 `vttest` keyboard / control keys，确认 `Ctrl+T` 不再开新 tab。
4. 在普通 shell 里确认 `Ctrl+V` 不再走 app/session paste shortcut，而是继续交给 terminal。
5. 如有非 macOS 验证环境，补验 `Ctrl+T` / `Ctrl+Shift+P` 仍保持 app-scoped shortcut。

## Done When

- macOS 下 app shortcut modifier 已收窄到 `Meta`。
- `Ctrl+T` / `Ctrl+V` 的 terminal delivery 有自动化护栏。
- `Cmd` 路径和 `Ctrl+C` 路径不回归。
- 文档和 `T-059` 的失败回链保持一致。

## Risks / Follow-ups

- 若后续还要引入更多 app-scoped shortcut，必须先明确 modifier scope，不能再把 `Ctrl` 在 macOS 上默认视作 app modifier。
- 更完整的 VT220 control-key fidelity 仍可能暴露其他输入编码缺口，需要后续单独拆卡。
