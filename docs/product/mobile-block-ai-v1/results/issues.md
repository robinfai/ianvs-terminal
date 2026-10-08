# 问题登记

2026-10-08 基线；状态随实际修复和验收更新。

| ID | 级别 | 需求 | 现象与证据 | 当前状态 |
|---|---|---|---|---|
| PRD-001 | P0 | S1-R03 | readContext 等待期间来源变化污染已点发送的请求，新稿被旧完成清空；确定性回归失败 | open |
| PRD-002 | P0 | S1-R02 / S2-R02 | 删除最后来源后同一草稿由 AI 回到 Command；确定性回归失败 | open |
| PRD-003 | P1 | S1-R07 / S2-R11 | 检查终端目前总会暂停接管，无独立只读观察和同任务双栏 | open |
| PRD-004 | P1 | S2-R03–R05 | 手机 AI 单行、soft Return 发送、缺本地全屏草稿编辑 | open |
| PRD-005 | P1 | S4-R14 | 仅改 Bundle ID 的现有脚本仍共享生产 Keychain 组 | open；新验收工具隔离中 |
| PRD-006 | P2 | S1-R01 / S3-R02 | 失败块诊断隐藏于菜单，unknown exitCode 显示成功勾 | open |
| PRD-007 | P2 | S3-R07 | 手机固定字号仅在 preview，真实 App 未施加策略 | open |
| PRD-008 | P1 | S1-R12 | 手机设置列出不可运行的本地 ACP | open |
| PRD-009 | P1 | S4-R13 | 文档 gate 与既有归档、PRD 指定证据目录冲突 | open；明确规则调整中 |
| PRD-010 | 验收前提 | S4 | 真实 iPad、可连接 iPhone、iOS 17、真实模型 API/IME/VoiceOver/性能等尚未完成本轮验证 | not_run；不视为产品通过 |
