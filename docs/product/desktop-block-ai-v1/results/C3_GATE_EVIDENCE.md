# C3 自动门禁与协议支撑证据

实现候选：`7e9f0dd8e7bd825c655ceb80d817d5fe214337bd`。这些记录支持自动门禁和协议层结论，不声明任何完整 PRD 场景通过。

| 证据 | 结果与范围 |
|---|---|
| [make verify 原始日志](../evidence/shared/C3-gates/verify.log)、[运行身份](../evidence/shared/C3-gates/verify-metadata.json) | exit 0，首尾源码干净；macOS 27.0.1 arm64。包含原生 Composer／PTY／Keychain、构建签名与 Xcode 检查。 |
| [SSH 运行记录](../evidence/shared/C3-ssh-native-1/runner.log)、[结果](../evidence/shared/C3-ssh-native-1/results.json)、[身份](../evidence/shared/C3-ssh-native-1/run-metadata.json) | 六组真实回环 OpenSSH 全通过；含受控多跳及父节点恢复。生产 native session API，未运行 GUI。各组 test／sshd 原始日志同目录。 |
| [ACP 连接原始日志](../evidence/shared/C3-acp-protocol-1/probe.log)、[身份与返回模型](../evidence/shared/C3-acp-protocol-1/run-metadata.json) | 实际回复 OK，适配器 2.1.1，返回模型 gpt-5.6-sol；所有终端工具拒绝。 |
| [ACP 取消恢复原始日志](../evidence/shared/C3-acp-resume-1/probe.log)、[身份](../evidence/shared/C3-acp-resume-1/run-metadata.json) | cancel 后恢复同一 session，记忆标记一致；只读 fixture 回答，不含 App 审阅／PTY 操作。 |
| [iPhone 构建身份摘要](../evidence/shared/C3-gates/iphone-build-summary.json) | 独立 Trail PRD Profile 包，签名／Keychain 校验通过；未安装、未设备验收。摘录原记录非账号字段，并对保留 App 补算文件树与运行时指纹，明确标注为摘要。 |

[归档索引](../evidence/shared/C3-gates/archive-index.json)列出原始本地路径与 SHA-256。除明确标注的 iPhone 摘要外，日志和 metadata 原样复制；归档后的文件名去掉 `.private` 后缀，内容未改写。Dart 的 `Running build hooks...` 前缀保留在 ACP 原始输出中。

本组支撑证据不是完整场景截图／连续视频包，不加入正式 manifest 的 `passed` 统计。中止的 workspace 运行和手机安装包仍保留在本地。完整结论、已知条件和未验收清单见 [FINAL_REVIEW](FINAL_REVIEW.md)。
