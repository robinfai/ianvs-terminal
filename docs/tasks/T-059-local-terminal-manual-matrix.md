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

- `docs/tasks/T-059-local-terminal-manual-matrix.md`
- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`

## Functional Acceptance

- VT220 `vttest` 基本矩阵记录为 `pass` / `fail` / `blocked`
- powerline / ANSI prompt fidelity 记录为 `pass` / `fail` / `blocked`
- 真实 trackpad scrollback 记录为 `pass` / `fail` / `blocked`
- font metric / DPI resize 记录为 `pass` / `fail` / `blocked`
- host/tooling blocked 单独标记，不算产品失败
- 任一 `fail` 都拆成 focused task，并回链到本任务

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm/app
flutter test integration_test/flutterm_smoke_test.dart
flutter run -d macos
```

## Manual QA

1. 用本地 shell profile 启动 app，确认 terminal 可输入、可滚动、可 resize
2. 用 VT220 profile 执行 `vttest` 基础设备属性、键盘、屏幕更新矩阵
3. 在真实 ANSI / powerline prompt 下观察颜色、反显、尾随空格背景和 glyph 对齐
4. 使用真实 trackpad 验证 scrollback、滚轮/惯性滚动、thumb drag、回到底部
5. 在至少两组字体度量或 DPI 条件下验证 resize 后内容保留与 window-size translation
6. 记录每个子项的绝对日期、环境、结果和阻塞原因

## Result Template

- Date:
- Host:
- `integration_test/flutterm_smoke_test.dart`: `pass` / `fail` / `blocked`
- `flutter run -d macos`: `pass` / `fail` / `blocked`
- `VT220 vttest`: `pass` / `fail` / `blocked`
- `powerline / ANSI prompt fidelity`: `pass` / `fail` / `blocked`
- `trackpad scrollback`: `pass` / `fail` / `blocked`
- `font-metric / DPI resize`: `pass` / `fail` / `blocked`
- Split tasks:

## Done When

- 所有矩阵项都有结果
- 失败项都已拆成 focused task
- `docs/TESTING.md` / `docs/KNOWN_ISSUES.md` 与结果一致

## Risks / Follow-ups

- 当前机器若缺少真实 trackpad、DPI 切换条件或可交互 macOS 前台权限，只能记录 `blocked`
- 本任务只证明 local terminal；SSH 不在本轮范围
