# Ianvs Terminal Privacy Policy

Effective date: September 22, 2026

Ianvs Terminal is a terminal and SSH client. This policy describes how the iOS app handles information.

## Information handled by the app

The app may process terminal input and output, terminal session recordings, SSH host details, usernames, connection preferences, and optional remote data-service settings. The master encryption key is stored using the operating system credential vault. Saved SSH authentication secrets and remote API session tokens are encrypted with that key in the app container. Other app data remains local; optional API synchronization transfers supported configuration documents to the destination chosen by the user. Terminal layouts and recordings are not part of API synchronization.

## Data collection

The Ianvs Terminal developers do not collect, sell, use for advertising, or track the information processed by the app. The app does not include third-party advertising or analytics SDKs.

## User-directed network connections

The app connects only to SSH hosts and HTTP API endpoints configured by the user. Information sent to those destinations is governed by the destination operator's policies. Ianvs Terminal does not operate a default cloud service and does not receive data sent to user-selected destinations.

## Diagnostics and support

The app does not automatically upload diagnostics. If a user voluntarily opens a GitHub issue or otherwise contacts the developers, the information included in that message is processed only to provide support. Users should remove credentials and personal information before sharing logs or screenshots.

## Data retention and deletion

App-container data is removed when the app is deleted. The master key stored in the operating system credential vault may remain after uninstall. Switching off API synchronization does not delete local profiles or recordings. Remote API logout and credential cleanup follow the account settings and may require a reachable service. Data sent to a user-selected SSH host or HTTP API must be deleted through that service or its operator.

## Children

Ianvs Terminal is a general-purpose developer tool and is not directed to children under 13.

## Changes

This policy may be updated when the app's data practices change. The effective date above will be revised when a new version is published.

## Contact

For privacy questions or support, open an issue at:

https://github.com/robinfai/ianvs-terminal/issues

---

# Ianvs Terminal 隐私政策

生效日期：2026 年 9 月 22 日

Ianvs Terminal 是终端与 SSH 客户端。iOS App 可能在设备上处理终端输入与输出、会话记录、SSH 主机信息、用户名、连接偏好以及可选的远程数据服务配置。主密钥使用系统凭据保险库存储；已保存的 SSH 认证凭据和远程 API 会话 Token 使用该密钥加密后保存在 App 沙盒中。可选 API 同步只传输用户所选目标支持的配置文档，终端布局和录制不参与 API 同步。

Ianvs Terminal 开发者不收集、出售、用于广告或跟踪上述数据，App 也不包含第三方广告或分析 SDK。App 只连接用户自行配置的 SSH 主机或 HTTP API；相关数据受目标服务运营方的政策约束，Ianvs Terminal 不运营默认云服务，也不会收到发送到用户所选目标的数据。

App 不会自动上传诊断信息。用户若主动通过 GitHub Issue 联系开发者，所提交的信息仅用于支持；分享日志或截图前应移除凭据和个人信息。

卸载 App 会清除 App 沙盒内的数据。系统凭据保险库中的主密钥在卸载后可能仍然保留。停用 API 同步不删除本地 Profile 或录制；API 注销和凭据清理遵循账号设置，并可能需要服务可连接。发送到用户所选 SSH 主机或 HTTP API 的数据，需要通过对应服务或其运营方删除。

如有隐私或支持问题，请访问：

https://github.com/robinfai/ianvs-terminal/issues
