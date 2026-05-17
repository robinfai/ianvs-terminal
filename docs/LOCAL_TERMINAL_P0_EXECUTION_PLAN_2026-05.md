# P0 Execution Plan: Documentation And Boundaries

## Objective

冻结本地 terminal 后续路线的产品边界，确保路线图、功能计划和任务拆分都以 local-first 为主线，不再把 SSH 或 remote 能力作为默认下一阶段。

## Inputs

- `docs/LOCAL_TERMINAL_FEATURE_PLAN.md`
- `docs/ROADMAP.md`
- `docs/GHOSTTY_CONFIG_COMPARISON.md`
- `docs/HYPER_LIKE_TARGET.md`
- `docs/HYPER_LIKE_GAP_MATRIX.md`
- `docs/tasks/README.md`

## Preconditions

- 当前仓库已确认 macOS local shell 主链路可作为后续产品能力扩展基础。
- Phase 3 已重新定位为 Local Workspace Expansion。

## Work Plan

1. 路线图对齐
   - 确认 `docs/ROADMAP.md` 中 Phase 3 是 Local Workspace Expansion。
   - 确认 Phase 3 非目标包含 SSH、remote domain、SFTP、serial、协作 Web session。
   - 确认 Phase 4/Phase 5 不会反向污染 Phase 3 范围。

2. 里程碑边界冻结
   - 将 P0-P5 保持为从基础设施到高级能力的顺序。
   - 明确 P1 是 action/config foundation。
   - 明确 P2 是 local workspace。
   - 明确 P3 是 shell productivity。
   - 明确 P4 是 clipboard/notifications/hotkey window。
   - 明确 P5 是 visual/advanced local features。

3. 任务目录同步
   - 确认 `docs/tasks/README.md` 中任务分类能承载 P1-P5 的后续任务。
   - 后续新增任务仍按 `T-NNN-short-title.md` 编号，不复用旧编号。

4. 验收规则固化
   - 确认新增任务必须写明 `Goal`、`Scope`、`Non-goals`、`Functional Acceptance`、`Verification Commands`、`Done When`。
   - 对任何涉及 terminal input 的任务加入 protected-contract 验收说明。

## Deliverables

- 已冻结的路线图和本地 terminal feature plan。
- 每个后续里程碑的独立执行计划。
- 一套新任务拆分规则，保证后续任务不会扩张到 remote/SSH 范围。

## Acceptance Criteria

- 文档中没有把 SSH、remote domain、SFTP、serial 写成 Phase 3 或 local terminal v1 的交付项。
- P1-P5 的里程碑名称、目标、交付项和验收项互相一致。
- 新任务的验收口径可以直接追溯到某个里程碑。

## Verification

- 文档检查：`docs/ROADMAP.md`、`docs/LOCAL_TERMINAL_FEATURE_PLAN.md`、`docs/tasks/README.md`
- 关键词检查：确认 SSH/remote/SFTP/serial 只出现在非目标、拒绝项或未来平台验证语境中。

## Exit Criteria

- P0 完成后，P1 可以直接进入 action/keybinding/config 的任务级实现，不需要再次讨论产品边界。

## Risks

- 风险：后续实现时把竞品 remote 能力误吸收到本地配置模型。
- 缓解：每个 config schema 或 action registry 任务都必须显式写 `Non-goals`，禁止新增 remote/SSH 顶层字段。

## Added foundation slice: T-162 Local terminal P0 boundary closure manifest

Status: FOUNDATION. Added a P0 boundary closure manifest and connected it to the cross-milestone production wiring manifest builder. Remaining work: populate the manifest from real documentation review evidence and verification status before closing P0.
