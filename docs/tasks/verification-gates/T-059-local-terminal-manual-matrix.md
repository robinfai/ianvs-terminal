# T-059 Local Terminal Manual Matrix

## Goal

在本地 terminal 功能补强后，重新执行只面向 local shell 的手工兼容性矩阵，并把结果记录为 `pass` / `fail` / `blocked`。

## Scope

- 只验证本地 terminal
- 只记录手工矩阵结果和失败项拆分
- 覆盖 VT220、ANSI / powerline prompt、真实 trackpad scrollback、字体度量 / DPI resize

## Non-goals

- 不复活 `T-055`
- 不推进 SSH
- 不扩展跨平台、renderer、插件或 split pane
- 不在本任务内修复矩阵中发现的产品问题；失败项单独拆任务

## Files In Scope

- `docs/tasks/verification-gates/T-059-local-terminal-manual-matrix.md`
- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`

## Functional Acceptance

- VT220 `vttest` 基本矩阵记录为 `pass` / `fail` / `blocked`
- powerline / ANSI prompt fidelity 记录为 `pass` / `fail` / `blocked`
- 真实 trackpad scrollback 记录为 `pass` / `fail` / `blocked`
- font metric / DPI resize 记录为 `pass` / `fail` / `blocked`
- host/tooling blocked 单独标记，不算产品失败
- 任一 `fail` 都拆成 focused task，并回链到本任务

## Preflight Checks

```bash
command -v vttest
```

```bash
cd example
flutter devices
```

```bash
osascript -e 'tell application "System Events" to get UI elements enabled'
```

```bash
cd example
flutter test integration_test/flutterm_smoke_test.dart
```

```bash
cd example
flutter run -d macos
```

## Verification Commands

```bash
cd example
flutter run -d macos
```

## Manual QA

1. 用本地 shell profile 启动 app，确认 terminal 可输入、可滚动、可 resize
2. 用 VT220 profile 执行 `vttest` 基础设备属性、键盘、屏幕更新矩阵
3. 在真实 ANSI / powerline prompt 下观察颜色、反显、尾随空格背景和 glyph 对齐
4. 使用真实 trackpad 验证 scrollback、滚轮/惯性滚动、thumb drag、回到底部
5. 在至少两组字体度量或 DPI 条件下验证 resize 后内容保留与 window-size translation
6. 记录每个子项的绝对日期、环境、结果和阻塞原因

## Result

### Manual Matrix Result

- Date: 2026-05-06
- Host: macOS 26.3.1 (darwin-arm64)
- Branch/HEAD: `codex/hyper-first-shell / d2bb7b6`
- `vttest`: available at `/opt/homebrew/bin/vttest`
- Accessibility/UI scripting: `osascript -e 'tell application "System Events" to get UI elements enabled'` returned `false`
- `integration_test/flutterm_smoke_test.dart`: `pass`
- `flutter run -d macos`: `pass`
- Manual input path (`y`, `Backspace`, `pwd`, `echo hello`, `ls`): `pass`

### Matrix Verdicts

- `VT220 vttest`: `fail`
- `powerline / ANSI prompt fidelity`: `pass`
- `trackpad scrollback`: `fail`
- `font-metric / DPI resize`: `pass`

### Evidence

- `flutter test integration_test/flutterm_smoke_test.dart` passed on macOS, though the run still printed `Failed to foreground app; open returned 1`.
- `flutter run -d macos` launched successfully and the app came to the foreground.
- `VT220` terminal reports passed:
  - Primary DA returned `VT200 family`
  - Secondary DA returned `Pp=1 (VT220)`
- `VT220` keyboard was mixed:
  - Cursor Keys passed
  - Control Keys failed because `Ctrl+T` opened a new tab instead of reaching the terminal, and `Ctrl+V` behavior was abnormal in the `vttest` control-key screen
- `VT220` screen features failed:
  - Wrap-around test expected 3 equal-width `*` rows
  - Observed the second row shorter than the first and third
- Prompt fidelity looked normal during ordinary shell usage.
- Trackpad behavior was mixed:
  - Ordinary vertical scrolling passed
  - Scrollbar thumb drag passed
  - Inertial scrolling failed because releasing fingers produced no continued motion
  - Return-to-bottom failed because the viewport stayed in mid-scrollback instead of returning to the prompt
- Resize coverage passed:
  - Clean default shell tab resize passed
  - Large-font resize passed
  - Alternate font-family resize passed
  - Cross-screen DPI move plus resize passed
  - The `%` seen during narrow-width testing was traced to `zsh` `PROMPT_EOL_MARK`, not a renderer artifact
  - A narrow-width extra blank line reproduced in `zsh -f` but not in `bash --noprofile --norc`, so current evidence does not support a generic viewport resize bug

### Split Tasks

- `T-066`: macOS app shortcut modifier narrowing for terminal control-key delivery
- `T-067`: VT220 wrap-around fidelity regression
- `T-068`: trackpad momentum and return-to-bottom scrollback behavior

### Follow-up Resolution

- `T-066`: complete on 2026-05-07
  - macOS app shortcut modifier 已收窄到 `Meta`
  - VT220 `Ctrl+T` 和普通 shell `Ctrl+V` 手工复验通过
- `T-067`: complete on 2026-05-07
  - VT220 wrap-around 自动化回归已补齐
  - `vttest` wrap-around 页面在 80 列下人工复验通过
- `T-068`: complete on 2026-05-07
  - trackpad momentum / return-to-bottom 自动化回归已补齐
  - 真实 trackpad 人工复验通过

## Done When

- 四条矩阵 lane 已拿到真实人工结果；若 host/tooling 不满足，只能回退到 `T-054` 类 unblock 任务，不能用全 `blocked` 结果直接关闭
- 失败项都已拆成 focused task，并从本任务显式回链
- `docs/TESTING.md` / `docs/KNOWN_ISSUES.md` 与结果一致

## Risks / Follow-ups

- 当前机器若缺少真实 trackpad、DPI 切换条件或可交互 macOS 前台权限，只能记录 `blocked`
- 本任务只证明 local terminal；SSH 不在本轮范围
