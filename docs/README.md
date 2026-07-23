# ianvs terminal Docs

这个目录是 `ianvs terminal` 的主文档入口。这里负责导航和长期约束；具体迭代记录放在任务文档里。

## 开始开发

新迭代建议先读：

1. [../README.md](../README.md)
2. [CURRENT_EXECUTION_TARGET.md](CURRENT_EXECUTION_TARGET.md)
3. [ROADMAP.md](ROADMAP.md)
4. [tasks/README.md](tasks/README.md)，再选择具体任务或从 [tasks/TEMPLATE.md](tasks/TEMPLATE.md) 新建任务
5. [ACCEPTANCE.md](ACCEPTANCE.md)
6. [TESTING.md](TESTING.md)

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

- [TERMINAL_PRODUCT_SCOPE.md](TERMINAL_PRODUCT_SCOPE.md)：Profile、Session、Terminal Layout、Relaunch Spec、Recording Library 与延期/非目标边界。
- [ARCHITECTURE.md](ARCHITECTURE.md)：稳定设计、模块职责、公开接口和长期约束。
- [FRAME_DIFF.md](FRAME_DIFF.md)：terminal frame diff 的原理图、生命周期、Snapshot/Delta 对比和收益说明。
- [recording/FORMAT_V1.md](recording/FORMAT_V1.md)：Iteration 03 的 Recording Metadata/Event v1 格式、兼容错误和输入隐私边界。
- [recording/FORMAT_V2.md](recording/FORMAT_V2.md)：Recording v2 checkpoint marker、安全 parser 边界、有界 native materialization 与兼容规则。
- [protocols/RUNTIME_CAPABILITIES_V1.md](protocols/RUNTIME_CAPABILITIES_V1.md)：native Runtime Capabilities v1 查询、可选符号和特性清单。
- [protocols/RUNTIME_EVENT_ENVELOPE_V1.md](protocols/RUNTIME_EVENT_ENVELOPE_V1.md)：Event Envelope/Batch v1、序号、丢失检测和旧协议回退。
- [protocols/SESSION_CONFIG_V1.md](protocols/SESSION_CONFIG_V1.md)：live/replay 会话创建的 SessionConfig v1、输入边界和旧 Profile wire 双向兼容。
- [protocols/SESSION_REQUEST_RESPONSE_V1.md](protocols/SESSION_REQUEST_RESPONSE_V1.md)：同步 Dart/native Session Request/Response v1、关联校验、结构化错误与旧 `{kind, ...payload}` 回退。
- [protocols/HOST_REQUEST_RESPONSE_V1.md](protocols/HOST_REQUEST_RESPONSE_V1.md)：native-to-product Host Request/Response v1、OSC 52 首个双向切片、精确一次响应与旧事件回退。
- [protocols/DIAGNOSTIC_EVENT_V1.md](protocols/DIAGNOSTIC_EVENT_V1.md)：Frame/Session Diagnostic Event v1、序号/关联校验与旧 debug-stat FFI 回退。
- [protocols/TERMINAL_FRAME_PACKET_V1.md](protocols/TERMINAL_FRAME_PACKET_V1.md)：现有 Frame Protobuf 的 session/sequence/timestamp 包装、ACK 与 Snapshot 重同步、旧 Frame 双栈。
- [protocols/GRAPHIC_ASSET_PACKET_V1.md](protocols/GRAPHIC_ASSET_PACKET_V1.md)：原子 Graphic Asset Packet v1、精确 identity/RGBA 校验与旧 meta/copy 双栈。
- [protocols/RUNTIME_WIRE_INVENTORY.md](protocols/RUNTIME_WIRE_INVENTORY.md)：当前 FFI 边界分类与后续迁移债务清单。
- [TERMINAL_XTERM_API_ALIGNMENT.md](TERMINAL_XTERM_API_ALIGNMENT.md)：xterm.js 风格 API 对齐现状和剩余语义缺口。
- [TERMINAL_XTERM_RECENT_FIX_AUDIT.md](TERMINAL_XTERM_RECENT_FIX_AUDIT.md)：xterm.js 最近一年修复项对照审计、证据矩阵和后续排查计划。
- [XTERM_MANUAL_CONFIRMATION_QUEUE.md](XTERM_MANUAL_CONFIRMATION_QUEUE.md)：需要平台、视觉或人工判断的 xterm.js 对照风险确认队列。
- [GHOSTTY_CONFIG_COMPARISON.md](GHOSTTY_CONFIG_COMPARISON.md)：Ghostty 官方配置能力与当前仓库配置面的长期对比审计。
- Package README 只描述各自边界：
  - [../packages/ianvs_pty/README.md](../packages/ianvs_pty/README.md)
  - [../packages/ianvs_terminal/README.md](../packages/ianvs_terminal/README.md)
  - [../example/README.md](../example/README.md)

## 测试验收

- [ACCEPTANCE.md](ACCEPTANCE.md)：全局完成定义、任务字段、失败处理和文档同步规则。
- [TESTING.md](TESTING.md)：当前真实可用的验证命令和人工检查入口。
- [compatibility/CAPABILITY_MATRIX.md](compatibility/CAPABILITY_MATRIX.md)：Iteration 01 的六层兼容性证据矩阵。
- [compatibility/TEST_ASSET_INVENTORY.md](compatibility/TEST_ASSET_INVENTORY.md)：可复用测试与本地验证 helper 清单。
- [compatibility/KNOWN_ISSUES.md](compatibility/KNOWN_ISSUES.md)：兼容性基线暴露的平台、宿主与截断边界。
- [compatibility/MANUAL_VERIFICATION.md](compatibility/MANUAL_VERIFICATION.md)：字体、DPI、物理输入与真实 `vttest` 人工步骤。

任务完成前必须执行对应验证命令；如果某项验收暂时跳过，必须在任务文档或 [KNOWN_ISSUES.md](KNOWN_ISSUES.md) 里说明原因。

## 路线图

- [CURRENT_EXECUTION_TARGET.md](CURRENT_EXECUTION_TARGET.md)：根据当前仓库校准的 live lane、证据、执行顺序和边界。
- [CURRENT_EXECUTION_TARGETS.json](CURRENT_EXECUTION_TARGETS.json)：由 docs contract test 校验的机器可读目标、状态、证据和验收命令。
- [ROADMAP.md](ROADMAP.md)：当前 live lane、历史 `M1-M5` 目标和长期阶段方向。
- [HYPER_LIKE_TARGET.md](HYPER_LIKE_TARGET.md)：Hyper-inspired 产品目标。
- [HYPER_LIKE_GAP_MATRIX.md](HYPER_LIKE_GAP_MATRIX.md)：Hyper-inspired 缺口矩阵和阶段优先级。
- [LOCAL_TERMINAL_MILESTONE_EXECUTION_INDEX_2026-05.md](LOCAL_TERMINAL_MILESTONE_EXECUTION_INDEX_2026-05.md)：P0-P5 执行计划索引，以及竞品可吸收功能到各里程碑的映射说明。
- [LOCAL_TERMINAL_COMPETITOR_COVERAGE_MATRIX_2026-05.md](LOCAL_TERMINAL_COMPETITOR_COVERAGE_MATRIX_2026-05.md)：竞品可吸收功能到 P0-P5 计划、任务和当前 wiring 状态的覆盖矩阵。
- [LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md](LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md)：P0-P5 完成审计清单，区分 foundation、wired 和 verified。
- [LOCAL_TERMINAL_COMPLETION_AUDIT_SNAPSHOT_2026-05-16.md](LOCAL_TERMINAL_COMPLETION_AUDIT_SNAPSHOT_2026-05-16.md)：当前完成审计快照，记录哪些证据已存在、哪些验证仍阻塞最终关闭。
- [LOCAL_TERMINAL_VERIFICATION_READINESS_CHECKLIST_2026-05.md](LOCAL_TERMINAL_VERIFICATION_READINESS_CHECKLIST_2026-05.md)：验证 readiness 清单，区分“已有执行入口”和“已有通过证据”。
- [LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md](LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md)：验证 evidence ledger，用于记录后续真实命令输出和人工观察结果。
- [LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md](LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md)：验证记录示例，说明 ledger 结果如何转换为 `LocalTerminalVerificationGateRecord`。
- [LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md](LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md)：验证命令批次清单，用于后续按 gate 执行并记录结果。
- [LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md](LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md)：验证失败 triage log，用于记录首个阻塞、归属里程碑和后续修复任务。
- [LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md](LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md)：验证 helper 脚本索引，区分只读查看命令和会执行验证的命令。
- [LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json](LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json)：机器可读验证 manifest，列出 gate、batch、helper 和 closure rules。
- [LOCAL_TERMINAL_VERIFICATION_MANIFEST_MAINTENANCE_2026-05.md](LOCAL_TERMINAL_VERIFICATION_MANIFEST_MAINTENANCE_2026-05.md)：verification manifest 维护说明，明确 JSON 只是派生索引而不是完成证据。
- [LOCAL_TERMINAL_VERIFICATION_AUTHORIZATION_GATE_2026-05.md](LOCAL_TERMINAL_VERIFICATION_AUTHORIZATION_GATE_2026-05.md)：验证授权 gate，明确哪些用户指令才允许运行最终验证批次。
- [LOCAL_TERMINAL_VERIFICATION_BLOCKED_STATE_2026-05.md](LOCAL_TERMINAL_VERIFICATION_BLOCKED_STATE_2026-05.md)：当前验证阻塞状态，明确下一步应是恢复额度后复跑 broader、继续 integration/manual，或暂停。
- [LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md](LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md)：最终验证 handoff，串联审计、命令批次、ledger、record examples、runbook 和 manual template。
- [LOCAL_TERMINAL_MILESTONE_IMPLEMENTATION_STATUS_2026-05.md](LOCAL_TERMINAL_MILESTONE_IMPLEMENTATION_STATUS_2026-05.md)：P0-P5 实现状态总览，区分 `FOUNDATION`、`WIRED` 和 `DONE`。
- [TECHNICAL_BLOG_PROJECT_ACTION_PLAN_2026-05.md](TECHNICAL_BLOG_PROJECT_ACTION_PLAN_2026-05.md)：从技术文章反馈反推出来的工程行动计划，记录 benchmark、Instant Replay、粘贴安全、Shell Hook 和视觉正确性证据 gate。

辅助脚本：

- `tools/LOCAL_TERMINAL_VERIFICATION_HELPERS.md`：local terminal 验证 helper 的本地说明，解释脚本职责、调用方式和 evidence 边界。
- `tools/technical_blog_action_benchmark.sh`：运行技术文章反馈对应的 Frame Diff、行缓存和输入回显 benchmark 场景，并输出可复现证据目录。
- `tools/local_terminal_verification_batches.sh`：列出、打印或显式运行 local terminal 验证命令批次；脚本不会自动更新 evidence ledger。
- `tools/local_terminal_verification_capture.sh`：显式运行验证批次并把 `output.log`、`summary.txt`、`ledger-entry.md` 捕获到 `build/local-terminal-verification/`，仍需人工回填 evidence ledger。
- `tools/local_terminal_verification_status.sh`：打印 local terminal 最终验证入口和当前阻塞状态；不会运行验证。

路线图只写执行顺序和阶段目标；具体实现、验收和历史结果必须落到任务文档。

## 决策记录

- [DECISIONS/README.md](DECISIONS/README.md)：ADR 写作规则。
- [DECISIONS/ADR-0001-hyper-phase0-shell-boundaries.md](DECISIONS/ADR-0001-hyper-phase0-shell-boundaries.md)：Hyper-inspired shell 边界与 terminal protected contracts。
- [DECISIONS/ADR-0002-terminal-core-fork-rationale.md](DECISIONS/ADR-0002-terminal-core-fork-rationale.md)：保留 vendored terminal core fork 的理由。
- [DECISIONS/ADR-0003-terminal-scope-convergence.md](DECISIONS/ADR-0003-terminal-scope-convergence.md)：从 Project Workspace 收敛到 Terminal Layout 与最小 Relaunch Spec。

重要且长期影响后续边界的选择写 ADR；一次性实现细节留在任务文档。

## 风险

- [KNOWN_ISSUES.md](KNOWN_ISSUES.md)：当前接受的限制、真实产品缺口、环境风险和延期风险。

如果限制不再成立，更新 `KNOWN_ISSUES.md`，并同步当前任务文档。

## 任务历史

- [tasks/README.md](tasks/README.md)：任务目录规则、主题分组、状态口径和新建任务方式。
- [tasks/TEMPLATE.md](tasks/TEMPLATE.md)：新任务模板。

任务文档按主题分目录，不按完成状态分目录。目录位置只表示主题归属，不表示任务已经完成或通过验收。

## 工程复盘

- [retros/README.md](retros/README.md)：跨多轮实现、调试、验证形成的复盘记录入口。

复盘文档记录历史过程、证据和改进点；它不替代任务文档、架构权威文档或当前验证状态。

## 维护规则

- 一个概念只保留一个权威文档，避免重复定义。
- 任务文档必须写 `Non-goals`，防止顺手扩 scope。
- 产品级说明放根目录和 `docs/`；子项目 README 只写本包职责、边界和常用命令。
- `native/vendor/**` 是上游或 vendored 文档，本仓主文档重构不主动改那里。
