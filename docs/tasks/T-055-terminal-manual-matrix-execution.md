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
   - 先让 prompt / glyph 渲染建立 measured cell size
   - 分别验证 viewport-driven resize 与 shell-driven rows/cols -> window-size translation
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
- 若 `font-metric / DPI resize` 为 `fail`，必须明确说明问题发生在 shell-driven 还是 viewport-driven 路径
- 结果分叉 playbook: `.omx/context/t055-result-branching-playbook-20260421T091946Z.md`
  - 这是分叉任务 playbook，不是新的结果模板
  - 编号不预留；按实际出现顺序取当时下一个可用 `T-0NN`
  - `T-055` 只记录结果和任务回指，不吸收修复过程

若某个子项是 `blocked` 且原因属于 host/tooling（例如 `Failed to foreground app; open returned 1`、缺少 `vttest`、缺少真实 trackpad / DPI 条件），不要把它记成产品回归；先回到 `T-054` 这一类环境排障任务，等标准交互式 macOS 机器准备好后再继续 `T-055`。

## Current Local Status

`2026-04-22` 当前机器状态：`blocked`

- `zsh -lic 'type flutterm_no_proxy'` 当前返回 `flutterm_no_proxy not found`，所以这轮改用显式 no-proxy 环境变量取证
- `command -v vttest` 当前返回 `/opt/homebrew/bin/vttest`，VT220 工具准备已满足
- 显式 no-proxy 的 `./tools/check_terminal_manual_matrix_prereqs.sh` 已在 `2026-04-22 11:11 CST` 复跑：
  - host: `BINGHUILUO-MC6`
  - macOS: `26.3.1 (25D771280a)`
  - branch: `codex/hyper-first-shell`
  - `HEAD`: `758b5c4e57555a7176fe66cbdc7d818cda3ab901`
  - `flutter doctor -v`: `pass`
  - `flutter devices`: `pass`
  - `integration_test/flutterm_smoke_test.dart`: `pass`
  - `flutter run -d macos`: `blocked`
    - 仍打印 `Failed to foreground app; open returned 1`
    - 但已能观测到 Dart VM Service、app process 和 app bundle
- `osascript -e 'tell application "System Events" to get UI elements enabled'` 当前返回 `false`，所以本机会话仍不能完成已确认的 viewport 点击与键盘输入
- 显式 no-proxy 的 `flutter run -d macos --host-vmservice-port 49200` 已在 `2026-04-22 10:11 CST` 重跑：
  - VM Service 已稳定出现于 `http://127.0.0.1:49200/...`
  - app 进程已启动，且 `visible=true`
  - 但 frontmost app 仍不是 `app`
  - 当前会话又缺少 `System Events` 辅助访问与 `screencapture` 显示权限，因此无法完成 viewport 点击和键盘输入确认
- 当前执行环境仍不满足真实 trackpad 与字体度量 / DPI 切换验证条件
- 当前机器继续 `blocked` 的原因已收窄到：foreground failure、`UI elements enabled: false`、未完成人工键盘输入确认，以及真实 trackpad / DPI 条件仍未满足；不是旧的 shell-driven `9x18` Y 轴路径仍未修复

因此，本任务在当前机器上仍不应伪装成“已执行”；当前更准确的本机 verdict 是 `unsuitable local host`。`T-055` 仍应迁移到满足 `vttest`、真实前台交互、真实 trackpad 和字体度量 / DPI 条件的标准交互式 macOS 开发机完成。

## Off-Machine Handoff

- Active off-machine context snapshot: `.omx/context/t055-terminal-manual-matrix-off-machine-20260422T032930Z.md`
- Historical stop-point snapshot: `.omx/context/t055-terminal-manual-matrix-off-machine-20260421T081004Z.md`
  - 旧 snapshot 只保留历史 stop-point 价值，不再是当前 handoff 的事实源
- Target-machine execution runbook: `.omx/context/t055-target-machine-execution-runbook-20260421T085450Z.md`
  - 这是目标机器执行手册，不是新的结果模板；结果仍然只能回填本任务现有 `Execution Record Template`
  - 目标机器执行时应把 active snapshot、runbook 和 branching playbook 一起使用；旧 snapshot 只保留历史 stop-point 价值
- Target machine must continue from the latest pushed `HEAD` on branch `codex/hyper-first-shell`, and must confirm the active snapshot `.omx/context/t055-terminal-manual-matrix-off-machine-20260422T032930Z.md` is present in the workspace.
- Current machine remains a blocked host for `T-055`; do not treat this host as if it can complete the manual matrix locally.
- Current machine is blocked because of foreground / accessibility / keyboard-confirmation conditions, not because `vttest` is still missing.

## Done When

- 自动化无法证明的 terminal 矩阵已经得到 `pass` / `fail` / `blocked` 结果
- 所有失败项都已转化为可执行的 focused task
- `docs/TESTING.md` / `docs/KNOWN_ISSUES.md` 与最新手工结果一致

## Post-T-055 Default Next Step

只有当四类手工矩阵都拿到明确结果、且没有新的产品级 `fail` 压住优先级时，后续才默认切到 Hyper-like `Phase 4` 的 PRD + test-spec 规划；在这之前不要跳过 `T-055` 直接开启新的产品迭代。

- Phase 4 skeleton context snapshot: `.omx/context/hyper-phase4-interaction-polish-skeleton-20260421T084736Z.md`
- Phase 4 formal writeup checklist: `.omx/context/hyper-phase4-formal-writeup-checklist-20260421T093447Z.md`
  - 这是 `T-055` 清空后的正式落笔清单，不是提前创建 `.omx/plans/` 正式文件
- 在 `T-055` 清空前，不要提前创建 `.omx/plans/prd-hyper-like-phase4-interaction-polish.md` 或 `.omx/plans/test-spec-hyper-like-phase4-interaction-polish.md`

## Risks / Follow-ups

- 若 `T-054` 未真正解除环境阻塞，本任务可能只能产出部分 `blocked` 结果
- 任何发现的 fidelity / DPI / trackpad 问题都应单独建任务，不要继续堆在矩阵总任务里
