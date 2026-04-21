# T-055 Terminal Manual Matrix Execution

## Goal

在 `T-054` 解除主要阻塞后，正式执行并沉淀 terminal 手工兼容性矩阵，把自动化无法证明的真实性风险收敛成明确结果。

## Scope

- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`
- `docs/tasks/T-055-terminal-manual-matrix-execution.md`

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
command -v vttest || true

cd /Users/robinfai/personal/flutterm/app
flutter test integration_test/flutterm_smoke_test.dart
flutter run -d macos
```

## Manual QA

1. 在可交互桌面环境下运行 app，并确认 integration smoke 作为自动化基线仍通过
2. 在 VT220 profile 下执行 `vttest` 基本设备属性 / 键盘 / 屏幕更新矩阵
3. 在真实 powerline / ANSI prompt 下检查颜色、反显、尾随空格背景和 glyph 对齐
4. 使用真实 trackpad 验证 scrollback、thumb drag、返回底部等交互
5. 在至少两组字体度量或 DPI 条件下验证 resize 后内容保留与 window-size translation
6. 将每个子项结果写回文档；若失败，立即拆出新任务

## Done When

- 自动化无法证明的 terminal 矩阵已经得到 `pass` / `fail` / `blocked` 结果
- 所有失败项都已转化为可执行的 focused task
- `docs/TESTING.md` / `docs/KNOWN_ISSUES.md` 与最新手工结果一致

## Risks / Follow-ups

- 若 `T-054` 未真正解除环境阻塞，本任务可能只能产出部分 `blocked` 结果
- 任何发现的 fidelity / DPI / trackpad 问题都应单独建任务，不要继续堆在矩阵总任务里
