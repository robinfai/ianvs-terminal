# 文档导航

`docs/` 只保留当前版本的使用说明、架构、合同、维护规范和仍待实施的明确提案。
运行日志、截图、trace、临时设计与验收产物写入 `build/`，不在这里归档。
历史实现可通过 Git 查阅；已完成任务和过期报告不作为当前版本的依据。

## 开发与产品

- [开发环境](DEVELOPMENT.md)：macOS 工具链、运行与构建。
- [产品范围](TERMINAL_PRODUCT_SCOPE.md)：Profile、Session、Layout、SSH/SFTP、录制和延期边界。
- [架构与模块入口](ARCHITECTURE.md)：源码职责与模块 README。
- [桌面通知与操作反馈](DESKTOP_NOTIFICATIONS.md)：右上角提示队列、复制反馈和系统通知边界。
- [数据持久化与同步](DATA_API_PERSISTENCE.md)：本地优先、可选 API 同步及凭据边界。
- [当前执行目标](CURRENT_EXECUTION_TARGET.md)、[路线图](ROADMAP.md)：当前优先级与退出条件。
- [已知问题](KNOWN_ISSUES.md)：当前限制与未关闭的风险。

## 协议与实现

- [Runtime wire 清单](protocols/RUNTIME_WIRE_INVENTORY.md)：当前 native ABI 与各协议的边界。
- [Runtime Capabilities](protocols/RUNTIME_CAPABILITIES_V1.md)、[事件封装](protocols/RUNTIME_EVENT_ENVELOPE_V1.md)。
- [SessionConfig](protocols/SESSION_CONFIG_V1.md)、[Session 请求响应](protocols/SESSION_REQUEST_RESPONSE_V1.md)。
- [Host 请求响应](protocols/HOST_REQUEST_RESPONSE_V1.md)、[运行诊断](protocols/DIAGNOSTIC_EVENT_V1.md)。
- [Frame Packet](protocols/TERMINAL_FRAME_PACKET_V1.md)、[Graphic Asset Packet](protocols/GRAPHIC_ASSET_PACKET_V1.md)。
- [OSC 支持矩阵](protocols/osc_support_matrix.md)、[ZMODEM](protocols/ZMODEM_V1.md)、[Shell integration](protocols/shell_integration_capabilities.md)。
- [Frame Diff](FRAME_DIFF.md)、[xterm API 对齐](TERMINAL_XTERM_API_ALIGNMENT.md)。
- [当前录制格式](recording/FORMAT_CURRENT.md)、[录制存储提案](recording/STORAGE_PROPOSAL.md)（尚未实施）。
- [架构决策](DECISIONS/README.md)。

## 验证与维护

- [验收标准](ACCEPTANCE.md)、[测试入口](TESTING.md)、[Lint 规则](LINTING.md)。
- [兼容能力矩阵](compatibility/CAPABILITY_MATRIX.md)、[测试资产](compatibility/TEST_ASSET_INVENTORY.md)。
- [兼容性限制](compatibility/KNOWN_ISSUES.md)、[人工验收](compatibility/MANUAL_VERIFICATION.md)。
- [当前任务规则](tasks/README.md)、[任务模板](tasks/TEMPLATE.md)。
- [iOS 发布检查](app-store/IOS_RELEASE_CHECKLIST.md)、[商店文案](app-store/IOS_LISTING.zh-CN.md)、[隐私政策](app-store/PRIVACY_POLICY.md)。

## 维护规则

- 一个概念只有一个当前权威文档；模块说明优先链接源码、测试或对应规范。
- 不保存旧版本文档副本、已完成任务、截图包、构建输出或重复的验收记录。
- 当前测试 fixture 与 golden 保存在对应测试目录，说明正文实际使用的图保留在 `assets/`。
- 实验提案明确标注尚未实施；可复用脚本放 `tools/`，实测输出放 `build/`。
- 文档合同测试检查本目录全部 Markdown 链接与当前执行目标的源码证据。
