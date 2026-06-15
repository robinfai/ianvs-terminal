# Command Center Roadmap Intake 设计

## 背景

`/Users/robinfai/Downloads/ianvs-command-center-product-plan.zip` 提供了一套
Command Center 产品规划，覆盖 Command Bar、Command Search、Command History、
Command Blocks、Block Actions、Context Chips、Sticky Header 和验证计划。

当前仓库已经有稳定的终端分层：

- `packages/ianvs_pty` 负责 PTY transport 和 FFI。
- `packages/ianvs_terminal` 负责中性 terminal runtime、viewport、输入、选区和
  `TerminalSessionShellHookEvent`。
- `example/` 负责 shell/productivity/action/menu/profile/visual 等产品层能力。

现有 `docs/ROADMAP.md` 的主线是 `M1-M5`，集中在 xterm/runtime 证据、shell hook
契约、workspace expansion 和跨平台接入。Command Center 不应替换这条主线，而应作为
可并行推进的产品线进入文档体系。

## 已确认决策

- 采用路线图优先的入库方式。
- Command Center 作为独立并行产品线，不替换现有 `M1-M5`。
- 允许完整并行推进，只要守住 terminal-first、安全策略、package 边界和不重写 renderer。
- 任务从 `T-300` 起步，不使用 `CC-*` 编号。
- 任务按更细粒度拆分，并且每个任务都写成完整任务文档。
- zip 里的产品/架构文档只作为来源材料吸收，不复制为新的 `docs/COMMAND_CENTER_*.md`。
- 一次性写入覆盖全阶段的完整任务包。

## ROADMAP 设计

在 `docs/ROADMAP.md` 中新增 **Command Center 并行产品线**，放在当前执行口径之后、
长期方向之前。

这一节说明三类内容：

1. 关系：Command Center 不替换现有 `M1-M5`，可以并行推进。
2. 护栏：普通输入默认发给 shell，不重写 renderer，不把产品 UI 下沉到
   `packages/ianvs_terminal`，不绕过 read-only、paste、shortcut 安全策略。
3. 阶段：使用 `CC0-CC6` 表达产品线阶段。

阶段定义：

- `CC0`：规划和任务包入库。
- `CC1`：command lifecycle 数据基座。
- `CC2`：history repository 和 search index。
- `CC3`：`Ctrl-R` command search overlay。
- `CC4`：command blocks range 和 actions MVP。
- `CC5`：command bar、context chips、mode router。
- `CC6`：sticky header、review 接入、验证收口。

`ROADMAP.md` 是产品线入口；`docs/tasks/command-center/` 是任务执行入口。

## 任务目录设计

新增 `docs/tasks/command-center/README.md`，作为任务目录入口。它说明：

- Command Center 的执行规则。
- 全局 Non-goals。
- 阶段顺序。
- 任务依赖。
- 和现有 `M1-M5` 的并行关系。

新增完整任务文档，从 `T-300` 开始：

- `T-300-command-center-track-intake.md`：冻结并行产品线、护栏、任务包。
- `T-301-command-center-feature-flags.md`：feature flags 和本地配置入口，默认全关。
- `T-302-command-invocation-lifecycle-model.md`：command invocation lifecycle 模型。
- `T-303-shell-hook-lifecycle-adapter.md`：shell hook 到 lifecycle 的 app 层 adapter。
- `T-304-command-lifecycle-degraded-state.md`：lifecycle 异常和降级状态。
- `T-305-session-command-history-buffer.md`：session-local history buffer。
- `T-306-global-command-history-repository.md`：global history repository 和落盘策略。
- `T-307-command-history-privacy-filter.md`：sensitive command filter 和清理策略。
- `T-308-command-search-query-parser.md`：search query parser。
- `T-309-command-search-index-ranking.md`：search index 和 ranking。
- `T-310-command-search-overlay-controller.md`：`Ctrl-R` overlay state/controller。
- `T-311-command-search-overlay-widget.md`：`Ctrl-R` overlay widget 和键盘导航。
- `T-312-command-search-insert-execute-safety.md`：insert-vs-execute 安全行为。
- `T-313-command-block-range-model.md`：command block range model。
- `T-314-command-block-navigation.md`：previous/next/failed block navigation。
- `T-315-command-block-actions-reducer.md`：block actions reducer。
- `T-316-command-block-action-wiring.md`：copy output、re-input、rerun wiring。
- `T-317-command-bar-editor.md`：command bar editor。
- `T-318-command-center-context-chips.md`：context chips。
- `T-319-command-center-mode-router.md`：mode router。
- `T-320-sticky-command-header.md`：sticky command header。
- `T-321-command-review-entrypoints.md`：review / instant replay entrypoints。
- `T-322-command-center-verification-gates.md`：verification gates 和手工 QA 模板。

## 任务依赖设计

任务分为四条可并行但有依赖的 lane。

Foundation lane：

```text
T-300 -> T-301 -> T-302 -> T-303 -> T-304
```

这条 lane 建立开关、生命周期模型、shell hook adapter 和降级状态。后续 Search、
Blocks、UI 只能消费这层，不重复解析 shell hook。

History/Search lane：

```text
T-305 -> T-306 -> T-307 -> T-308 -> T-309 -> T-310 -> T-311 -> T-312
```

这条 lane 先建立 session/global history，再建立 parser/index/ranking，最后接
`Ctrl-R` UI。默认 `Enter` 只插入，不执行；显式执行必须走安全策略。

Blocks lane：

```text
T-313 -> T-314 -> T-315 -> T-316 -> T-320 -> T-321
```

这条 lane 先做 block range 和导航，再做 actions，最后做 sticky header 与
review / instant replay 接入。Block UI 不写入 scrollback，不改变真实终端复制文本。

Command Bar lane：

```text
T-317 -> T-318 -> T-319
```

这条 lane 后置现代输入框、context chips 和 mode router。普通文本默认仍走 terminal。

`T-322` 贯穿全程，但作为收口任务沉淀自动化、手工模板、性能门和 stop conditions。

## 任务文档标准

每个 `T-3xx` 必须使用完整任务文档格式：

- `Goal`
- `Scope`
- `Non-goals`
- `Files In Scope`
- `Functional Acceptance`
- `Verification Commands`
- `Manual QA`
- `Done When`
- `Risks / Follow-ups`

写作要求：

- 中文为主，保留代码符号和文件名英文。
- 不复制 zip 原文，只吸收结论。
- 不提前锁死不必要的实现细节；如果文件名还不确定，使用目录级范围。
- 每个任务都重复关键护栏：不做 Agent v1、不做 remote/cloud、不改 renderer、不绕过
  terminal safety。
- 涉及 GUI、输入、IME、复制粘贴、滚动、快捷键的任务必须保留人工 QA。

## 验证设计

文档入库本身不运行 Flutter 或 Rust 验证；后续实现任务按 `docs/TESTING.md` 选择最小
验证命令。任务文档中必须写出对应命令，例如：

- 纯 app 层模型：`cd example && flutter analyze` 和定向 `flutter test`。
- 触达 package 层：额外运行 `cd packages/ianvs_terminal && flutter test`。
- 触达 runtime / FFI / viewport：按 `docs/TESTING.md` 扩展到 package/native 链路。
- 触达输入、IME、paste、read-only、shortcut routing、viewport scroll 或 renderer：
  增加明确 Manual QA。

## 非目标

- 本轮不实现 Command Center 功能。
- 本轮不修改 `packages/ianvs_terminal` 或 `packages/ianvs_pty` API。
- 本轮不复制 zip 里的 `COMMAND_CENTER_*.md` 文档。
- 本轮不引入 Agent / AI、remote / SSH、cloud sync、协作或插件生态。
- 本轮不重写 terminal renderer。

## 完成标准

- `docs/ROADMAP.md` 有 Command Center 并行产品线。
- `docs/tasks/command-center/README.md` 存在并能作为任务入口。
- `T-300` 到 `T-322` 都是完整任务文档。
- 任务依赖和全局护栏清楚，不与现有 `M1-M5` 冲突。
- 设计先作为 brainstorming 规格通过审阅，再进入 implementation plan。
