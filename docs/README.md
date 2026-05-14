# flutterm Docs

这个目录是 `flutterm` 的主文档入口。这里负责导航和长期约束；具体迭代记录放在任务文档里。

## 开始开发

新迭代建议先读：

1. [../README.md](../README.md)
2. [ROADMAP.md](ROADMAP.md)
3. [tasks/README.md](tasks/README.md)，再选择具体任务或从 [tasks/TEMPLATE.md](tasks/TEMPLATE.md) 新建任务
4. [ACCEPTANCE.md](ACCEPTANCE.md)
5. [TESTING.md](TESTING.md)

推荐任务 prompt：

```text
请按 docs/tasks/<topic>/T-xxx-*.md 实施。
必须遵守 docs/ACCEPTANCE.md 和 docs/TESTING.md。
如果涉及稳定边界，遵守 docs/ARCHITECTURE.md。
不要扩展到 Non-goals。
完成前运行相关验证命令。
最终回复使用：变更 / 验证 / 剩余风险。
```

## 架构边界

- [ARCHITECTURE.md](ARCHITECTURE.md)：稳定设计、模块职责、公开接口和长期约束。
- [TERMINAL_XTERM_API_ALIGNMENT.md](TERMINAL_XTERM_API_ALIGNMENT.md)：xterm.js 风格 API 对齐现状和剩余语义缺口。
- [TERMINAL_XTERM_RECENT_FIX_AUDIT.md](TERMINAL_XTERM_RECENT_FIX_AUDIT.md)：xterm.js 最近一年修复项对照审计、证据矩阵和后续排查计划。
- [XTERM_MANUAL_CONFIRMATION_QUEUE.md](XTERM_MANUAL_CONFIRMATION_QUEUE.md)：需要平台、视觉或人工判断的 xterm.js 对照风险确认队列。
- Package README 只描述各自边界：
  - [../packages/flutterm_pty/README.md](../packages/flutterm_pty/README.md)
  - [../packages/flutterm_terminal/README.md](../packages/flutterm_terminal/README.md)
  - [../example/README.md](../example/README.md)

## 测试验收

- [ACCEPTANCE.md](ACCEPTANCE.md)：全局完成定义、任务字段、失败处理和文档同步规则。
- [TESTING.md](TESTING.md)：当前真实可用的验证命令和人工检查入口。

任务完成前必须执行对应验证命令；如果某项验收暂时跳过，必须在任务文档或 [KNOWN_ISSUES.md](KNOWN_ISSUES.md) 里说明原因。

## 路线图

- [ROADMAP.md](ROADMAP.md)：阶段目标、非目标、进入条件和完成条件。
- [HYPER_LIKE_TARGET.md](HYPER_LIKE_TARGET.md)：Hyper-inspired 产品目标。
- [HYPER_LIKE_GAP_MATRIX.md](HYPER_LIKE_GAP_MATRIX.md)：Hyper-inspired 缺口矩阵和阶段优先级。

路线图只写阶段目标；具体实现、验收和历史结果必须落到任务文档。

## 决策记录

- [DECISIONS/README.md](DECISIONS/README.md)：ADR 写作规则。
- [DECISIONS/ADR-0001-hyper-phase0-shell-boundaries.md](DECISIONS/ADR-0001-hyper-phase0-shell-boundaries.md)：Hyper-inspired shell 边界与 terminal protected contracts。
- [DECISIONS/ADR-0002-terminal-core-fork-rationale.md](DECISIONS/ADR-0002-terminal-core-fork-rationale.md)：保留 vendored terminal core fork 的理由。

重要且长期影响后续边界的选择写 ADR；一次性实现细节留在任务文档。

## 风险

- [KNOWN_ISSUES.md](KNOWN_ISSUES.md)：当前接受的限制、真实产品缺口、环境风险和延期风险。

如果限制不再成立，更新 `KNOWN_ISSUES.md`，并同步当前任务文档。

## 任务历史

- [tasks/README.md](tasks/README.md)：任务目录规则、主题分组、状态口径和新建任务方式。
- [tasks/TEMPLATE.md](tasks/TEMPLATE.md)：新任务模板。

任务文档按主题分目录，不按完成状态分目录。目录位置只表示主题归属，不表示任务已经完成或通过验收。

## 维护规则

- 一个概念只保留一个权威文档，避免重复定义。
- 任务文档必须写 `Non-goals`，防止顺手扩 scope。
- 产品级说明放根目录和 `docs/`；子项目 README 只写本包职责、边界和常用命令。
- `native/vendor/**` 是上游或 vendored 文档，本仓主文档重构不主动改那里。
