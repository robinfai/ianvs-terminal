# T-052 Terminal Manual Verification Matrix

## Goal

把当前自动化无法证明的 terminal compatibility / fidelity 矩阵正式写成手工验收清单，并记录本环境下已知的执行阻塞。

## Scope

- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`
- `docs/tasks/T-052-terminal-manual-verification-matrix.md`

## Non-goals

- 不新增自动化测试框架
- 不修复 `flutter run -d macos`、前置台或 `HardwareKeyboard` 断言
- 不修改 Rust PTY/core 或 Flutter shell/viewport 逻辑
- 不把手工矩阵顺手扩展成 SSH / 跨平台验证

## Files In Scope

- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`

## Functional Acceptance

- 文档显式列出当前仍需人工确认的 terminal 矩阵：
  - VT220 `vttest` 基本矩阵
  - powerline / ANSI prompt fidelity
  - 真实 trackpad scrollback 交互
  - 不同字体度量 / DPI 下的 resize 与 window-size translation
- 每个矩阵项都有明确的观察目标，而不是笼统写“手测一下”
- 当前环境阻塞会被记录到 `KNOWN_ISSUES.md`，而不是只停留在任务汇报里

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm
command -v vttest || true

cd example
flutter test integration_test/flutterm_smoke_test.dart
flutter run -d macos
```

## Manual QA

1. 准备 VT220 profile；若机器未安装 `vttest`，先记录阻塞并停止该子项
2. 使用 `vttest` 运行基础设备属性 / 键盘 / 屏幕更新矩阵，记录 pass / fail / blocked
3. 在真实 shell prompt（含 powerline / ANSI 样式）下检查颜色、反显、尾随空格背景是否保持
4. 使用真实 trackpad 进行 scrollback、thumb drag、回到底部等交互，确认行为与自动化结果一致
5. 在至少两组字体度量或 DPI 条件下检查 resize 后的内容保留与 window-size translation
6. 若 `flutter run -d macos` 无法前置台或触发 `HardwareKeyboard` 断言，记录为环境风险，不把它误记成产品层回归

## Done When

- 自动化未覆盖的终端矩阵已经被正式列入手工验收标准
- 当前环境阻塞已经在 `KNOWN_ISSUES.md` 明确记录
- `docs/TESTING.md` 的“当前未覆盖”与实际状态一致

## Risks / Follow-ups

- 当前环境未必具备 `vttest` 与真实 trackpad / DPI 切换条件，矩阵可能在本机只能部分执行
- 若 `flutter run -d macos` 的前置台或重复 `KeyDownEvent` 断言持续复现，应单开运行态排障任务
