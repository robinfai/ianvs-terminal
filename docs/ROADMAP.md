# Trail Roadmap

当前主线是 **`runtime-contract-stability`**。机器可读目标见
[CURRENT_EXECUTION_TARGETS.json](CURRENT_EXECUTION_TARGETS.json)，范围与执行约束见
[CURRENT_EXECUTION_TARGET.md](CURRENT_EXECUTION_TARGET.md)。这里仅列当前优先级，不保留已完成阶段流水。

## 当前能力

- macOS 本地 shell 与 SSH、iOS SSH，使用 Profile/Session 和 tab/pane 模型。
- 本机 Terminal Layout 仅保存拓扑、Profile 引用和 cwd；录制库独立保存。
- 本地优先配置持久化；API 是可选同步目标。
- 原生边界只保留当前版本的配置、请求、事件、帧与图形资产合同。

具体能力以 [产品范围](TERMINAL_PRODUCT_SCOPE.md)、[架构](ARCHITECTURE.md) 与
[协议清单](protocols/RUNTIME_WIRE_INVENTORY.md) 为准。实现存在不代表当前构建已通过所有平台验收。

## 执行顺序

1. 守住 current-only 协议、严格输入校验、发布包镜像一致性和真实 PTY 行为。
2. 修复 [KNOWN_ISSUES.md](KNOWN_ISSUES.md) 中的门禁阻塞，运行聚焦回归及完整 `make verify`。
3. 补齐 iOS 实体设备、可选 API 跨设备同步、辅助访问和发布验收。
4. 按目标机证据推进 Linux / Windows；本机或 Ubuntu package 测试不能代替桌面验收。
5. 录制存储改进先评估 [存储提案](recording/STORAGE_PROPOSAL.md)，明确保真、内存和恢复合同后再实现。

## 延期边界

Project Workspace、团队云/协作、插件市场和替换 renderer 不在当前主线。
新功能分为有界任务，按 [验收标准](ACCEPTANCE.md) 和 [测试入口](TESTING.md) 检查；
执行产物写入 `build/`，当前文档只保留结论、现行合同与未解决问题。
