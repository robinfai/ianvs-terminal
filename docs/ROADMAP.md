# flutterm Roadmap

这份文档只定义阶段目标，不写具体实现细节。具体开发任务应落到 `docs/tasks/`。

本地 terminal 功能扩展的竞品分析与功能设计见 [LOCAL_TERMINAL_FEATURE_PLAN.md](LOCAL_TERMINAL_FEATURE_PLAN.md)。

## Phase 1: macOS Local Shell Stabilization

目标：

- 稳定当前 `macOS + local shell` 主链路
- 补齐 terminal 基础交互
- 让文档、测试和验收流程成型

非目标：

- SSH
- split pane
- Linux / Windows 适配
- native renderer

进入条件：

- Flutter + Rust + FFI 主链路已打通

完成条件：

- 本地 shell 日常可用
- 多 tab、复制粘贴、滚动、resize 稳定
- 文档布局适合持续迭代
- 测试与验收规则已经固化

## Phase 2: Terminal UX Hardening

目标：

- 提升 terminal 日常使用体验
- 补强输入、选区、滚动、状态反馈等边角
- 收敛已知行为不一致

非目标：

- SSH
- 跨平台
- renderer 替换

进入条件：

- Phase 1 完成

完成条件：

- 主要交互缺陷收敛
- 已知问题和剩余风险更明确
- 至少形成一轮稳定的人工 smoke 流程

## Phase 3: Local Workspace Expansion

目标：

- 把本地 tabs / panes / workspace / layout 能力收口成稳定产品模型
- 建立统一 action registry，让快捷键、菜单和 command palette 共享同一动作入口
- 建立本地配置模型，覆盖 profiles、keybindings、layouts、clipboard/paste policy、notification policy 和 hotkey window
- 把 shell integration 的 prompt marks、cwd tracking、command status、recent commands / directories 做成本地效率能力

非目标：

- SSH、remote domain、SFTP、serial、协作 Web session
- 插件系统
- Linux / Windows 适配
- renderer 重构

进入条件：

- 本地 shell 能力稳定
- profile 模型、session 生命周期和 pane/tab 状态足够清晰
- Phase 2 的 terminal 输入、选区、滚动、复制粘贴、resize 风险已收敛

完成条件：

- 本地 workspace 支持 tab、split right/down、focus、resize、close、undo close、same-cwd open
- keybinding / menu / command palette 通过统一 action id 触发，不向 terminal input 泄漏事件
- 旧 profile/preferences 配置仍可读取，新配置 schema 不引入 SSH/remote/serial/SFTP 顶层能力
- shell integration 关闭时，相关本地效率动作正确降级为不可用
- 验收清单覆盖本地 workspace、配置迁移、焦点安全、粘贴安全和通知策略

## Phase 4: Linux / Windows Integration

前置验证门槛见 [tasks/verification-gates/T-065-phase4-windows-linux-validation-gate.md](tasks/verification-gates/T-065-phase4-windows-linux-validation-gate.md)。

目标：

- 在尽量不改 Flutter 业务层的前提下接入更多桌面平台
- 验证 PTY 适配和构建链的跨平台可行性

非目标：

- 全量体验对齐
- renderer 升级

进入条件：

- macOS 版本已相对稳定
- 架构边界和 FFI 协议稳定

完成条件：

- 至少新增一个平台可运行
- 文档明确记录平台差异
- 不破坏 macOS 现有能力

## Phase 5: Renderer Decision Point

目标：

- 决定是否继续使用 Flutter Canvas
- 如果需要，再评估 native renderer 升级路径

非目标：

- 在没有证据前提前重写 renderer

进入条件：

- 已有足够的性能和交互反馈

完成条件：

- 有明确结论：继续保留 Canvas，或进入 renderer 升级计划
- 如需升级，先写决策文档再开实现任务
