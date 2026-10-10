# 文档导航

`docs/` 只保留当前版本的使用说明、架构、合同、维护规范和仍待实施的明确提案。
新运行日志、截图、trace、临时设计与验收产物默认写入 `build/`。
下文明确保留既有归档，并为手机、桌面 Block × AI PRD 分别规定证据交付例外；不扩展为通用归档区。
历史实现可通过 Git 查阅；已完成任务和过期报告不作为当前版本通过验收的依据。

## 开发与产品

- [开发环境](DEVELOPMENT.md)：macOS 工具链、运行与构建。
- [产品范围](TERMINAL_PRODUCT_SCOPE.md)：Profile、Session、Layout、SSH/SFTP、录制和延期边界。
- [架构与模块入口](ARCHITECTURE.md)：源码职责与模块 README。
- [桌面通知与操作反馈](DESKTOP_NOTIFICATIONS.md)：右上角提示队列、复制反馈和系统通知边界。
- [数据持久化与同步](DATA_API_PERSISTENCE.md)：本地优先、可选 API 同步及凭据边界。
- [当前执行目标](CURRENT_EXECUTION_TARGET.md)、[路线图](ROADMAP.md)：当前优先级与退出条件。
- [已知问题](KNOWN_ISSUES.md)：当前限制与未关闭的风险。
- [手机 Block × AI PRD](product/mobile-block-ai-v1/README.md)：分阶段需求、交互合同和真实平台验收要求。
- [桌面 Block × AI PRD v1.1](product/desktop-block-ai-v1/README.md)、[实施状态](product/desktop-block-ai-v1/STATUS.md)、[跨端对照](product/desktop-block-ai-v1/results/CROSS_PLATFORM_REVIEW.md)：桌面交互修订及当前实现／证据缺口。
- [AI 功能与实现](ai/WARP_AI_IMPLEMENTATION.md)、[ACP 边界](ai/ACP_BACKEND.md)、[智能审阅](ai/SMART_APPROVAL.md)。

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

## 既有材料与 PRD 交付例外

`docs/ai/` 和 `docs/design/` 在基线 `29134363aecc20713f9f53e1c9a6c395ebf9ef2e` 已跟踪 1,578 个文件。
这些路径固定记录在 [既有文档清单](../test/fixtures/docs_legacy_inventory.txt)，保留原材料，不按目录整体豁免检查。
AI 当前能力说明仍可随实现维护；其中日期报告、evidence 和设计评审属于当时的历史证据，不能冒充最新构建或实机验收。
清单不是新增归档的入口；新文件放当前规范位置或 `build/`，不要通过日常重生成清单扩大例外。

手机 PRD 的例外仅适用于 `docs/product/mobile-block-ai-v1/`：

- `scripts/validate_evidence.py`、`scripts/validate_shotlist.py` 及各自的 `test_*.py` 是随 PRD 交付的四个校验脚本。其他可复用脚本仍放 `tools/`。
- `evidence/manifest.json` 和 `evidence/S1…S4/<同阶段用例 ID>/<run-id>/`、`evidence/shared/<run-id>/` 保存该 PRD 要求的证据。文件类型限 PNG、JSON/JSONL、TXT、LOG、TRACE，以及 MP4/MOV/WebM；代码和 ZIP 包不属于此例外。
- `design/` 是 PRD 自带的设计参考，不是运行证据；`results/` 的阶段报告须引用实际采集材料。图片、日志与视频的真实性、环境、commit、hash 和必交项按 [证据合同](product/mobile-block-ai-v1/06_EVIDENCE_CONTRACT.md) 及随包校验器检查。

桌面例外仅适用于 `docs/product/desktop-block-ai-v1/` 的两个原包校验脚本 `scripts/validate_evidence.py`、`scripts/test_validate_evidence.py`，以及 `evidence/manifest.json`、`evidence/D1…D4/<同阶段用例 ID>/<run-id>/`、`evidence/shared/<run-id>/`。证据类型与手机例外相同，S/D 阶段路径不可混用。按 [桌面证据合同](product/desktop-block-ai-v1/06_EVIDENCE_CONTRACT.md) 独立验收；两个包都不豁免任意代码、ZIP 或通用运行输出。

文档 gate 不替代 PRD 的证据校验器，不把目录存在或链接有效判为验收通过。

## 维护规则

- 一个概念只有一个当前权威文档；模块说明优先链接源码、测试或对应规范。
- 除上述固定既有清单和指定 PRD 证据外，不新增旧版本文档副本、已完成任务、截图包、构建输出或重复的验收记录。
- 当前测试 fixture 与 golden 保存在对应测试目录，说明正文实际使用的图保留在 `assets/`。
- 实验提案明确标注尚未实施；可复用脚本放 `tools/`，实测输出放 `build/`。
- 文档合同测试继续检查本目录全部 Markdown 正文链接，包括既有归档与 PRD；fenced code block 内的 Markdown 示例不当作真实链接。围栏外的新坏链接仍会失败。
- 文档合同测试同时检查当前执行目标的源码证据，并拒绝固定清单之外的归档路径和不属于指定 PRD 的执行产物。
