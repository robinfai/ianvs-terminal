# T-055 Terminal Manual Matrix Execution

## Goal

在 `T-054` 解除主要阻塞后，正式执行并沉淀 terminal 手工兼容性矩阵，把自动化无法证明的真实性风险收敛成明确结果。

## Scope

- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`
- `docs/tasks/T-055-terminal-manual-matrix-execution.md`
- `tools/check_terminal_manual_matrix_prereqs.sh`

## Non-goals

- 不修改 terminal 产品逻辑
- 不修复手工矩阵中发现的问题本身；失败项应拆成新的 focused task
- 不扩展成 SSH / 跨平台 / renderer 验证

## Functional Acceptance

- 逐项执行并记录以下矩阵：
  - VT220 `vttest` 基本矩阵
  - powerline / ANSI prompt fidelity
  - 真实 trackpad scrollback
  - 不同字体度量 / DPI 下的 resize 与 window-size translation
- 每个子项只允许 `pass` / `fail` / `blocked`
- 任一 `fail` 必须拆成新的 focused task，而不是继续挂在矩阵总任务里

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm
./tools/check_terminal_manual_matrix_prereqs.sh

cd /Users/robinfai/personal/flutterm/app
flutter test integration_test/flutterm_smoke_test.dart
flutter run -d macos
```

## Execution Prerequisites

- 一台可把 app 前置到真实可交互桌面的 macOS 开发机
- 已安装 `vttest`；标准准备路径为 `brew install vttest`
- 真实 physical trackpad
- 至少一组替代字体或 DPI 条件，用于验证 resize / window-size translation

## Manual QA

1. 先运行 `./tools/check_terminal_manual_matrix_prereqs.sh`，把前置检查结果贴入本任务和 `docs/TESTING.md`
2. 在 VT220 profile 下执行 `vttest` 基本设备属性 / 键盘 / 屏幕更新矩阵
3. 在真实 powerline / ANSI prompt 下检查颜色、反显、尾随空格背景和 glyph 对齐
4. 使用真实 trackpad 验证 scrollback、thumb drag、返回底部等交互
5. 在至少两组字体度量或 DPI 条件下验证 resize 后内容保留与 window-size translation
6. 将每个子项结果写回文档；若失败，立即拆出新任务

## Execution Record Template

在标准交互式 macOS 开发机上执行时，结果记录固定使用以下格式：

- `command -v vttest`: `pass` / `fail` / `blocked`
- `integration_test/flutterm_smoke_test.dart`: `pass` / `fail` / `blocked`
- `flutter run -d macos`: `pass` / `fail` / `blocked`
  - 绝对日期
  - 是否附着 Dart VM Service
  - 是否观察到 `Failed to foreground app; open returned 1`
  - 是否确认 app 已前置到真实可交互桌面
- `VT220 vttest`: `pass` / `fail` / `blocked`
- `powerline / ANSI prompt fidelity`: `pass` / `fail` / `blocked`
- `trackpad scrollback`: `pass` / `fail` / `blocked`
- `font-metric / DPI resize`: `pass` / `fail` / `blocked`

## Failure Split Contract

若任一矩阵子项为 `fail`，必须立即单开 focused task，并固定包含：

- 最小复现
- 影响范围
- 最小验证命令，或明确的手工验收线
- 任务类型仅限：VT220 行为缺口、prompt / glyph / trailing background fidelity、trackpad scrollback、DPI / resize translation、`flutter run -d macos` / `HardwareKeyboard` 环境排障

若某个子项是 `blocked` 且原因属于 host/tooling（例如 `Failed to foreground app; open returned 1`、缺少 `vttest`、缺少真实 trackpad / DPI 条件），不要把它记成产品回归；先回到 `T-054` 这一类环境排障任务，等标准交互式 macOS 机器准备好后再继续 `T-055`。

## Current Local Status

`2026-04-21` 当前机器状态：`blocked`

- `./tools/check_terminal_manual_matrix_prereqs.sh` 已在 `2026-04-21 14:52 CST` 复跑，结果与此前 blocker 结论一致
- `integration_test/flutterm_smoke_test.dart` 已通过，可作为自动化基线
- `flutter run -d macos` 仍打印 `Failed to foreground app; open returned 1`
- `vttest` 未安装
- 当前执行环境不满足真实 trackpad 与字体度量 / DPI 切换验证条件

因此，本任务在当前机器上不应伪装成“已执行”；应迁移到满足上述前置条件的标准交互式 macOS 开发机完成。

## Done When

- 自动化无法证明的 terminal 矩阵已经得到 `pass` / `fail` / `blocked` 结果
- 所有失败项都已转化为可执行的 focused task
- `docs/TESTING.md` / `docs/KNOWN_ISSUES.md` 与最新手工结果一致

## Post-T-055 Default Next Step

只有当四类手工矩阵都拿到明确结果、且没有新的产品级 `fail` 压住优先级时，后续才默认切到 Hyper-like `Phase 4` 的 PRD + test-spec 规划；在这之前不要跳过 `T-055` 直接开启新的产品迭代。

## Risks / Follow-ups

- 若 `T-054` 未真正解除环境阻塞，本任务可能只能产出部分 `blocked` 结果
- 任何发现的 fidelity / DPI / trackpad 问题都应单独建任务，不要继续堆在矩阵总任务里
