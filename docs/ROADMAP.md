# flutterm Roadmap

这份文档只定义阶段目标，不写具体实现细节。具体开发任务应落到 `docs/tasks/`。

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

## Phase 3: SSH Session Support

目标：

- 为 profile 增加 SSH 会话能力
- 明确本地 shell 与 SSH session 的统一模型

非目标：

- 插件系统
- Linux / Windows 适配
- renderer 重构

进入条件：

- 本地 shell 能力稳定
- profile 模型与 session 生命周期足够清晰

完成条件：

- SSH profile 可创建、编辑、删除
- 至少有一条可用的 SSH 会话链路
- 验收清单覆盖 SSH 基本连接场景

## Phase 4: Linux / Windows Integration

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
