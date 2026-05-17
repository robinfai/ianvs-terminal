# T-077 Shell Profile Sheets Extraction

## Goal

把 Profiles / Dynamic Profiles 底部弹层从 `ShellScreen` 抽到独立 widget 文件，并为这两个 surface 补独立回归保护，给后续 action/config foundation 缩小改动面。

## Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/profiles/profiles_sheet.dart`
- `example/lib/features/profiles/dynamic_profiles_sheet.dart`
- `example/lib/features/terminal/terminal_input_controller.dart`
- `example/test/profiles/profile_sheets_test.dart`
- `example/test/shell/shell_screen_phase3_test.dart`
- `example/test/terminal_input_controller_test.dart`
- `example/test/widget_test.dart`
- `docs/tasks/README.md`
- `docs/tasks/shell-product/T-077-shell-profile-sheets-extraction.md`

## Current Progress

- `example/lib/features/shell/shell_screen.dart`：已从内联实现中移除 Profiles / Dynamic Profiles 面板实现，改为独立文件组件。
- `example/lib/features/profiles/profiles_sheet.dart`：已补齐 Profiles sheet 的查询与选中行为，并输出对应 `ProfilesSheetResult` 结果类型。
- `example/lib/features/profiles/dynamic_profiles_sheet.dart`：已补齐 JSON 解析、顶部样例、错误展示、导入结果返回。
- `example/lib/features/terminal/terminal_input_controller.dart`：已去除 `profile_models.dart` 依赖并收敛 emulation 类型入口为统一解析函数。
- `example/test/profiles/profile_sheets_test.dart`：新增 profile sheet 与 dynamic sheet 的独立回归测试（含过滤、编辑、导入成功与错误输入）。
- `example/test/shell/shell_screen_phase3_test.dart` 与 `example/test/terminal_input_controller_test.dart`：保持原有受影响回归路径继续覆盖。
- `docs/tasks/README.md`：已纳入 `T-077` 任务清单。
- `docs/tasks/shell-product/T-077-shell-profile-sheets-extraction.md`：本文件当前已进入验收提交阶段，待补充 `Completion Record`。

## Completion Record

- 完成时间：`2026-05-16`（local time）
- 完成状态：`DONE`
- 实际验证：
  - `cd example && flutter analyze`
  - `cd example && flutter test test/profiles/profile_sheets_test.dart`
  - `cd example && flutter test test/shell/shell_screen_phase3_test.dart`
  - `cd example && flutter test test/terminal_input_controller_test.dart`
  - `cd example && flutter test test/widget_test.dart --plain-name "dynamic profiles imports iTerm profile JSON"`
- 验证结果：均通过（含 `00:00 +4 all tests passed!`、`00:03 +11 all tests passed!`、`00:27 +27 all tests passed!`、`00:01 +1 all tests passed!`）
- 剩余风险：
  - 无新增回归风险；如需进一步推进 `P1` action/config foundation，交由后续独立任务补齐。

## Non-goals

- 不引入 action registry
- 不改 profile schema、defaults 语义或 session lifecycle
- 不改 command menu 信息架构
- 不改 Rust / PTY / FFI / terminal input 行为
- 不把这次抽离扩张成 broader `ShellScreen` 拆分工程

## Files In Scope

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/profiles/profiles_sheet.dart`
- `example/lib/features/profiles/dynamic_profiles_sheet.dart`
- `example/lib/features/terminal/terminal_input_controller.dart`
- `example/test/profiles/profile_sheets_test.dart`
- `example/test/shell/shell_screen_phase3_test.dart`
- `example/test/terminal_input_controller_test.dart`
- `example/test/widget_test.dart`

## Functional Acceptance

- command menu 打开的 Profiles surface 行为保持不变
- profile search、open、edit 结果在抽离后仍保持原语义
- dynamic profiles import 的成功和错误路径在抽离后仍保持原语义
- `TerminalInputController` 行为不因为移除 `profile_models.dart` 依赖而改变
- `ShellScreen` 不再内联持有这两个 sheet 的 widget 实现

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

```bash
cd example
flutter analyze
flutter test test/profiles/profile_sheets_test.dart
flutter test test/shell/shell_screen_phase3_test.dart
flutter test test/terminal_input_controller_test.dart
flutter test test/widget_test.dart --plain-name "dynamic profiles imports iTerm profile JSON"
```

## Manual QA

1. 从 shell command menu 打开 `Profiles`，确认搜索、打开 profile、编辑 profile 都正常。
2. 从 shell command menu 打开 `Dynamic Profiles`，导入一份 iTerm 风格 JSON，确认成功提示与新 profile 可见。
3. 用非法 JSON 重试一次，确认错误仍在 sheet 内可见。

## Done When

- Profiles / Dynamic Profiles 抽离完成
- 这两个 surface 有独立测试保护
- shell phase3 与 terminal input 受影响回归通过
- 没有把任务扩张成更大的 shell 架构重写

## Risks / Follow-ups

- 后续 action registry 仍需单独任务，不在本任务中提前吸收
- 如果 profile sheet 抽离后还发现 `ShellScreen` 其他大片私有 surface，可再拆 focused cleanup task
