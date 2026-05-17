# T-078 Action Registry Foundation

## Goal

建立稳定的 action 命名与执行入口，先打通 command menu/action surface 到统一 `TerminalActionId`，为后续 Keybinding 冲突诊断和 config 体系留出边界。

## Scope

- `example/lib/features/shell/` 下 command menu / shell action 调度相关入口
- `example/lib/features/terminal/` 下输入路径与动作网关的边界抽象（按最小面修改）
- 与本任务直接相关的现有回归测试

## Non-goals

- 不一次性完成 keybinding schema 全量重构
- 不改 pane/layout/workspace 持久化模型
- 不在本任务引入新依赖或新的远端/PTY 配置能力
- 不改动 profile sheet 抽离后的行为细节（该项已在 T-077 收口）

## Files In Scope

- `example/lib/features/shell/*`
- `example/lib/features/terminal/*`（间接引用）
- `example/test/shell/terminal_action_registry_test.dart`
- `docs/tasks/shell-product/T-078-action-registry-foundation.md`

## Current Progress

- 已新增 `shell_action_registry.dart`，建立 `TerminalActionId` 与 `ShellActionRegistry`。
- `ShellScreen` 的 command menu / shortcut 分发从局部 enum 重写为统一 `TerminalActionId`。
- 为 registry 覆盖补了独立回归 `terminal_action_registry_test.dart`。
- 已通过 `flutter analyze` 与 `command menu/shortcut` 回归路径。
- 已补跑真实 PTY acceptance 集成测试。

## Completion Record

- 完成时间：`2026-05-16`（local time）
- 完成状态：`DONE`
- 主要验证：
  - `cd example && flutter analyze`
  - `cd example && flutter test test/shell/terminal_action_registry_test.dart`
  - `cd example && flutter test test/shell/shell_screen_phase3_test.dart`
  - `cd example && flutter test -d macos integration_test/real_pty_acceptance_test.dart`
  - `cd example && flutter test test/widget_test.dart --plain-name "command menu"`

## Functional Acceptance

- 关键动作（例如 `open_profiles`, `open_dynamic_profiles`, `open_command_menu`, `new_tab`, `close_tab`）使用统一 action id 表达，不直接散落为页面私有调用。
- 触发动作优先级保持 `TerminalInputController` 与输入/IME/selection 的现有行为一致，且可在一处做集中治理。
- `command menu` 现有调用路径能通过 action 注册入口接管。
- 该任务不要求一次性完成全部 action 覆盖，只要建立“稳定 action id + registry 骨架”并验证关键路径可运行。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter analyze
flutter test
flutter test test/shell/terminal_action_registry_test.dart
flutter test test/shell/shell_screen_phase3_test.dart
flutter test -d macos integration_test/real_pty_acceptance_test.dart
```

## Manual QA

1. 打开 command menu，触发已有命令（如 Profiles）确认能正常打开。
2. 执行新接入 action 的快捷键，确认行为与现有路径一致。
3. 修改命名或新增 action 时，现有 menu/快捷键行为不回归。
4. 真机/本机条件满足时，执行并复核 `integration_test/real_pty_acceptance_test.dart` 全量结果。

## Done When

- action registry 结构建立（最小闭包）
- 行为路径切到 registry 后回归通过
- 本任务不扩张为完整 keybinding/config 系统重构

## Risks / Follow-ups

- 配置层面（schema、冲突检测、快捷键层级）建议在后续任务继续补齐。
- 成功接入后可在下一个任务推进 keybinding routing 和冲突诊断。
