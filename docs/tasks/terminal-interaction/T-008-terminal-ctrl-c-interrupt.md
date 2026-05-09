# T-008 Terminal Ctrl+C 中断恢复

## Goal

恢复终端内 `Ctrl+C` 的中断能力，避免它被误当成复制快捷键吞掉。

## Scope

- `example/lib/features/terminal/terminal_input_controller.dart`
  - 调整 `Ctrl+C` 与复制快捷键的判定。
- `example/test/terminal_input_controller_test.dart`
  - 增加 `Ctrl+C` 中断回归测试，并保留现有复制回归。

## Non-goals

- 不重做整套 control-key 映射（如 `Ctrl+D`、`Ctrl+L`、`Ctrl+Z`）。
- 不新增 Linux / Windows 的快捷键适配。
- 不修改 Rust core、PTY 或 FFI 协议。
- 不改动按钮式复制/粘贴行为。

## Files In Scope

- `example/lib/features/terminal/terminal_input_controller.dart`
- `example/test/terminal_input_controller_test.dart`

## Functional Acceptance

- 当终端获得焦点并按下 `Ctrl+C` 时，当前 session 会收到 ETX (`0x03`) 中断字节。
- 当按下 `⌘C` 且存在选区时，仍通过现有复制回调把文本写入剪贴板。
- 普通字符输入（如直接输入 `c`）保持现有行为，不被本次修改破坏。

## Verification Commands

参考 [TESTING.md](../../TESTING.md)：

```bash
cd native/core
cargo fmt --check
cargo test

cd example
flutter analyze
flutter test
flutter run -d macos
```

## Manual QA

1. 启动应用。
2. 打开一个本地 shell tab。
3. 运行长时间输出或阻塞命令（例如 `yes`）。
4. 按 `Ctrl+C`。
5. 确认命令被中断，terminal 仍可继续输入。
6. 再选中一段文本后按 `⌘C`，确认复制仍正常。

## Done When

- `Ctrl+C` 不再被复制逻辑吞掉，并能通过回归测试证明会发送中断字节。
- 相关验证命令已执行并记录结果。
- 未超出 Scope / Non-goals。

## Risks / Follow-ups

- 本次只修复 `Ctrl+C`；其他 control 组合键仍保持现状，后续如要补齐可拆成独立任务。
- 当前环境执行 `flutter run -d macos` 时，应用能完成构建与启动，但因为无法将 app 前置到可交互桌面，未完成真实 `Ctrl+C` / `⌘C` 人工 smoke；该缺口需在有前台 GUI 的 macOS 环境补做。
- 在本任务复核的一次 `flutter run -d macos` 中，曾观察到 Flutter 在 app 启动后抛出 `HardwareKeyboard` 重复 `Backspace` `KeyDownEvent` 断言；后续复跑未再次出现。该异常发生在框架键盘状态校验阶段、早于 `TerminalInputController.handle`，所以不属于本任务新增逻辑；当前先记录为运行环境 / Flutter 输入链路风险，后续若继续复现，应单开任务排查。
