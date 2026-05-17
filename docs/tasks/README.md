# flutterm Tasks

这个目录保存迭代任务和历史验收记录。任务按主题分目录，不按完成状态分目录；目录位置只说明“问题属于哪里”，不说明任务是否完成。

## 编号规则

- 任务文件名固定使用 `T-NNN-short-title.md`。
- 新任务取当前最大编号之后的下一个编号，不复用旧编号。
- 新任务先复制 [TEMPLATE.md](TEMPLATE.md)，再填写 `Goal`、`Scope`、`Non-goals`、验收和验证命令。
- 每个任务只解决一个可验证目标；发现相邻问题时新建后续任务。

## 主题目录

- `terminal-interaction/`：terminal 输入、复制粘贴、选区、滚动、resize、tab/exit 可观察行为和相关回归。
  - 当前包括 `T-001` 到 `T-008`、`T-010` 到 `T-016`、`T-018`、`T-020` 到 `T-027`、`T-029` 到 `T-032`、`T-034`、`T-037` 到 `T-043`、`T-060`、`T-061`、`T-066` 到 `T-068`、`T-070`、`T-071`、`T-074`、`T-075`。
- `runtime-pty/`：PTY、runtime、native/core、VT/xterm API、shell hook、row-range annotation 和底层 session 合同。
  - 当前包括 `T-017`、`T-019`、`T-030`、`T-033`、`T-036`、`T-040`、`T-050`、`T-053`、`T-063`、`T-064`、`T-069`、`T-072`、`T-073`。
- `shell-product/`：应用壳层、Hyper-inspired UI、profile/defaults、launcher、visual polish 和产品体验。
  - 当前包括 `T-044` 到 `T-049`、`T-056` 到 `T-058`、`T-077` 到 `T-297`。
- `verification-gates/`：自动化 smoke、测试覆盖、人工矩阵、平台 validation gate 和 host/tooling 阻塞记录。
  - 当前包括 `T-009`、`T-028`、`T-035`、`T-051`、`T-052`、`T-054`、`T-055`、`T-059`、`T-065`、`T-076`。
- `feedback-handoffs/`：外部反馈、跨仓 handoff 和需要拆分回本仓任务的反馈记录。
  - 当前包括 `T-062`。

## 状态口径

- 任务状态只能从任务正文中的 `Result`、`Completion Record`、`Final Disposition`、验收记录或后续回链判断。
- 目录名不是状态。移动到 `verification-gates/` 不表示已验证通过；移动到 `shell-product/` 不表示仍待做 UI。
- `T-055` 是 forced-closed 历史记录，不是“人工矩阵已通过”的证明；当前 local-only 人工矩阵入口是 [verification-gates/T-059-local-terminal-manual-matrix.md](verification-gates/T-059-local-terminal-manual-matrix.md)。
- 若任务内记录了 `blocked` 或 host/tooling 风险，不要把它改写成产品失败或完成状态，除非有新的验证证据。

## 新建任务

1. 选择主题目录。
2. 复制 [TEMPLATE.md](TEMPLATE.md) 到对应目录，文件名使用下一个 `T-NNN`。
3. 只写本次允许修改的能力和模块。
4. 在 `Verification Commands` 里引用 [../TESTING.md](../TESTING.md) 的最小必要命令；复制到主题子目录后，链接通常应写成 `../../TESTING.md`。
5. 完成后把结果、验证证据和剩余风险写回任务文档，必要时同步 [../KNOWN_ISSUES.md](../KNOWN_ISSUES.md)。

## 引用方式

- 从仓库根目录引用任务时使用完整路径，例如 `docs/tasks/terminal-interaction/T-068-trackpad-momentum-and-return-to-bottom-scrollback-behavior.md`。
- 从 `docs/` 内引用任务时使用 `tasks/<topic>/T-NNN-*.md`。
- 从任务文档内部引用 [TESTING.md](../TESTING.md)、[ACCEPTANCE.md](../ACCEPTANCE.md) 等上层 docs 文件时，注意按所在子目录计算相对路径；主题子目录里的任务通常要退两级。
