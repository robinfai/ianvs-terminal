# Hyper-inspired Gap Matrix

这份矩阵描述 ianvs terminal 当前状态与 Hyper-inspired 目标之间的具体缺口，用于给后续 Phase 1+ 排优先级。

| Area | Current repo state | Desired target | Gap | Primary layer owner | Suggested phase |
| --- | --- | --- | --- | --- | --- |
| Shell frame cohesion | `ShellScreen` 由 sidebar、tab chips、viewport、底部按钮拼接而成；功能成立，但层级更像 MVP 组合件 | 外层 shell frame 像同一套桌面 terminal chrome，而不是松散拼接 | 缺统一 framing、节奏和层级强度 | `example/lib/features/shell/` | 1A |
| Tab hierarchy clarity | 顶部 `InputChip` 可切换/关闭 tab，active/inactive 差异有限 | 活动 tab 与非活动 tab 一眼可区分，且与整体 header 层级一致 | 状态表达偏轻、层级不够明确 | `example/lib/features/shell/` + `example/lib/features/sessions/` | 1A |
| Empty-state quality | 仅显示 `Create a shell to get started`，配合 `New Tab` FAB 可恢复 | 空状态本身像 intentional first-run surface，并明确下一步 | 信息弱、产品感弱、与 shell frame 融合不足 | `example/lib/features/shell/` | 1A |
| Top action discoverability | 当前显式入口分散在 profile list、FAB、Copy/Paste | 一个明显、可预测的顶层 action surface | 缺统一入口；当前动作可发现性依赖用户探索 | `example/lib/features/shell/` | 2A |
| Focus-safe action model | 现有 terminal focus、tab close、exit 行为已有回归；launcher 尚不存在 | 顶层动作打开/关闭不泄漏输入，focus return deterministic | 缺 launcher surface 与 scope model | `example/lib/features/shell/` + `example/lib/features/terminal/` | 2A / 2B |
| Profile identity | profile 已存在且可持久化，但在主界面中 identity 强度有限 | 当前 shell/profile identity 更可感知，默认行为更明确 | profile 对 shell frame 的贡献偏弱 | `example/lib/features/profiles/` + `example/lib/features/shell/` | 3 |
| Default behavior clarity | 启动时自动创建 default profile session；行为可用但文档化的 product surface 还弱 | 用户能预测默认 profile、默认入口和无数据时的回退行为 | 缺 product-facing defaults artifact | `example/lib/features/sessions/` + `example/lib/features/profiles/` | 3 |
| Visual system consistency | 目前已有颜色/圆角/渐变，但更像点状选择，不是系统 | spacing、labels、强调关系更系统化 | 缺 token 和层级规则 | `example/lib/features/shell/` | 1B |
| Protected terminal semantics | 输入、选区、复制粘贴、滚动、resize、PTY 事件已有回归基线 | 在 shell polish 过程中这些语义保持稳定 | 风险不是缺功能，而是 UI 演进时误伤 contract | `example/lib/features/terminal/` + `example/lib/features/sessions/` + `native/core/` | 0-4 guardrail |

## Prioritization Notes

1. 先做 Phase 1A，因为 shell frame、tab hierarchy、empty-state 是用户最容易感知且最不需要触碰 Rust core 的区域。
2. `Top action discoverability` 必须晚于 1A/1B，因为它会引入新的 focus 路径和输入冲突风险。
3. `Profile identity` 和 `Default behavior clarity` 有价值，但不应抢在 shell polish 前面，否则容易演变成设置面板扩张。
4. `Protected terminal semantics` 不是功能缺口，而是整个 Hyper-inspired 计划的冻结边界。

## Exit Criteria for Using This Matrix

当后续任务开始实施时，每个任务至少应能回答：

- 它在解决矩阵中的哪一行缺口？
- 它主要改哪个 layer owner？
- 它是否触碰了 protected terminal semantics？
- 如果触碰了，验证证据是什么？
