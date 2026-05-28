# Hyper-inspired Target for ianvs terminal

这份文档把“让 ianvs terminal 更像 Hyper”收敛成当前仓库可执行、可验证、可分阶段推进的产品目标。

## Inputs

本目标基于以下现有事实整理，而不是脱离仓库另起炉灶：

- `README.md`
- `docs/ROADMAP.md`
- `docs/ARCHITECTURE.md`
- `.omx/plans/prd-hyper-like-terminal-evolution.md`
- `.omx/plans/test-spec-hyper-like-terminal-evolution.md`
- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/sessions/session_controller.dart`
- `example/lib/features/terminal/`

## Repo Baseline Today

当前产品已经具备一个可运行的 `macOS + local shell` terminal MVP：

- 左侧 sidebar 展示 profile，并可创建 session
- 顶部用 `InputChip` 呈现 tab
- 主内容区使用暖色背景 + 深色 terminal viewport
- 空状态只有 `Create a shell to get started`
- 主要显式操作入口是 `New Tab` 浮动按钮与 `Copy` / `Paste` 按钮
- session 生命周期、focus 迁移、复制粘贴、滚动、resize、exit -> empty-state 已有回归覆盖

这意味着“像 Hyper”在本仓库里不应该被理解为重写 terminal，而应该理解为：在保持现有 terminal 主链路稳定的前提下，升级 shell frame、信息层次、入口可发现性和 first-run 观感。

## Repo-specific Target

### 1. Shell chrome 要更像一个有意设计过的桌面 terminal

目标不是增加复杂组件数量，而是让现有结构更 cohesive：

- sidebar、tab strip、viewport、action 区形成统一的 shell frame
- terminal viewport 被明显地框定为核心工作区
- 顶层层级在“应用壳层”与“terminal 内容层”之间更清楚
- 不依赖更多设置项也能获得更成熟的默认观感

受影响模块：

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/sessions/session_state.dart`

### 2. Active / inactive hierarchy 必须一眼可读

当前 tab 可用，但层级和状态表达仍偏轻。Hyper-inspired 目标是：

- 活动 tab 在视觉上 unmistakable
- 非活动 tab 仍可读但不与活动态竞争
- tab strip、header 和 terminal frame 的状态表达一致
- close / focus / exit 后不会留下模糊的“当前到底在操作哪里”感受

受影响模块：

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/sessions/session_controller.dart`

### 3. Empty-state 要从占位提示升级为 intentional first-run surface

当前空状态是功能成立的，但还不像产品 surface。目标是：

- 即使没有活动 session，界面也像一个准备好工作的 terminal app
- 用户能立即知道下一步动作
- 从 empty-state 到首个 shell session 的路径不比现在更长
- 空状态与已有 `New Tab` / profile 默认行为保持一致

受影响模块：

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/profiles/`
- `example/lib/features/sessions/session_controller.dart`

### 4. 顶层动作入口要更明显，但不引入 Hyper 级功能膨胀

当前显式动作只有 `New Tab` / `Copy` / `Paste`。后续 Hyper-inspired 演进可以增加一个更明显的 launcher / action surface，但必须保持 MVP 约束：

- 一个明显入口即可
- 先覆盖 top actions，而不是扩展成 command palette 平台
- 打开 / 关闭 / focus return 必须 deterministic
- 不允许把 launcher 事件泄漏到 terminal input

预期影响模块：

- `example/lib/features/shell/shell_screen.dart`
- `example/lib/features/terminal/terminal_input_controller.dart`
- `example/lib/features/terminal/terminal_viewport.dart`

### 5. Profile / theme identity 要可感知，但先从默认体验做起

ianvs terminal 已有 profile 持久化基础，因此 Hyper-inspired 方向可以增强 identity，但 Phase 1 不把它扩展成复杂的设置系统：

- 用户能更明确地感知“当前 shell 是什么”
- 默认 profile / 默认外观行为应可预测
- 先强化 default experience，再讨论更多 theme/profile 自定义

受影响模块：

- `example/lib/features/profiles/profile_models.dart`
- `example/lib/features/profiles/profile_repository.dart`
- `example/lib/features/shell/shell_screen.dart`

## Non-goals

以下内容不属于这轮 Hyper-inspired 目标：

- Hyper 功能对等
- 插件系统
- split panes
- SSH 优先工作流
- renderer rewrite
- Rust PTY/core 重写
- 新依赖引入作为默认方案
- 把 visual polish 顺手扩展成新的状态/快捷键模型

## Phase Mapping

### Phase 0

先把目标、缺口、边界和受保护 contract 写清楚：

- `docs/HYPER_LIKE_TARGET.md`
- `docs/HYPER_LIKE_GAP_MATRIX.md`
- `docs/DECISIONS/ADR-0001-hyper-phase0-shell-boundaries.md`

### Phase 1A

最小高价值交付：

- shell frame polish
- tab hierarchy clarity
- intentional empty-state

### Phase 1B

在不新增状态规则的前提下统一 spacing / labels / visual tokens。

### Phase 2A / 2B

只在前两阶段稳定后再进入 launcher / shortcut surface；重点是 focus-safe 和 deterministic，而不是功能面扩张。

### Phase 3+

profile/default/theme/persistence 相关 UI 只能在 persistence artifact 明确后推进。

## Done When Phase 0 Is Useful

Phase 0 不是为了“写一堆好看的前期文档”，而是为了让后续实现可以直接对照：

- 哪些变化是 Hyper-inspired shell polish
- 哪些变化会碰到 terminal protected contracts
- 哪些模块负责观察 state，哪些模块有权发起 mutation
- 哪些缺口优先做，哪些先延后
