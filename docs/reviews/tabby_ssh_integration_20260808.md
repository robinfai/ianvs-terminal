# Tabby SSH 集成对照与 Ianvs 实现记录

日期：2026-08-08

## 参考版本

- Tabby 临时克隆：`/private/tmp/ianvs-terminal-tabby-reference-20260808`
- Tabby commit：`14e2d60`
- russh 临时克隆：`/private/tmp/ianvs-terminal-russh-reference-20260808`
- russh commit：`4882af7`

临时目录只用于分析，不作为 Ianvs 的构建依赖。

## Tabby 如何解析 `~/.ssh/config`

入口位于 Tabby 的 `tabby-electron/src/sshImporters.ts`：

1. 使用 `ssh-config` 解析 OpenSSH 文本。
2. 递归展开 `Include`；相对路径以 `~/.ssh` 为基准，支持 glob，并用已访问路径集合阻止循环引用。
3. 记录主配置及所有 include 文件的最新 mtime，配合内存和磁盘缓存避免重复解析。
4. 只把不含 `*`、`?` 且未以 `!` 开头的具体 `Host` 别名作为可启动会话。
5. 对每个具体别名调用 `config.compute(host)`，让通配符块按照 OpenSSH 的 first-value-wins 规则补全设置。
6. 只有最终得到 `HostName` 的条目才导入。ID 为 `openssh-config:` 加 Host 别名的 SHA-256，保证重复扫描结果稳定。

主要字段映射包括 `HostName`、`User`、`Port`、`IdentityFile`、`StrictHostKeyChecking`、`UserKnownHostsFile`、`ConnectTimeout`、`ServerAliveInterval`、`ServerAliveCountMax`、`ProxyCommand`、`ProxyJump`、转发、agent forwarding 和 X11 forwarding。`IdentityFile` 会展开 `~`，以秒表示的超时和保活参数会转换到 Tabby 内部单位。

## Tabby 如何建立 SSH 会话

主要流程位于 `tabby-ssh/src/session/ssh.ts`，配置模型位于 `tabby-ssh/src/api/interfaces.ts`。Tabby 的 TypeScript 会话层使用 `russh` Node binding，其底层是 Rust SSH 实现。它依次处理 known-hosts 校验、代理命令或跳板连接、agent/私钥/密码/keyboard-interactive 认证、PTY 和 shell 请求、窗口尺寸变化及数据转发。

## Ianvs 当前实现

Ianvs 沿用 Tabby 的分层思路，但不引入 Node 层：

- `native/core/src/ssh_config.rs`：Rust 原生 OpenSSH 导入器，支持递归 `Include`、glob、循环保护、Host 通配/否定匹配和 first-value-wins，并输出版本化 JSON 契约 `ianvs-openssh-profiles-v1`。
- `native/core/src/ssh.rs`：基于纯 Rust `russh` 的 SSH 字节传输，适配现有 `portable_pty` 会话生命周期；支持 PTY、交互 shell、resize、strict/accept-new/insecure known-hosts、连接超时、keepalive、ProxyCommand、逗号分隔的原生多跳 ProxyJump、显式私钥、ssh-agent、密码和多轮 keyboard-interactive。
- OpenSSH 的 `LocalForward`、`RemoteForward`、`DynamicForward`、`ForwardAgent` 和 `ForwardX11` 会由 Rust 导入器进入版本化 FFI 模型，再映射到可直接启动的 Ianvs 会话配置。
- 本地、远端和 SOCKS5 动态端口转发均由 `russh` channel 实现；Agent forwarding 支持显式 Unix socket 或 `SSH_AUTH_SOCK`；X11 支持显式 TCP 目标，也会像 Tabby 一样从 `DISPLAY` 推导 TCP/Unix socket，并在未配置时生成随机 MIT-MAGIC-COOKIE。
- `packages/ianvs_pty/lib/src/ssh_config_importer.dart`：OpenSSH 导入 FFI 桥。
- `packages/ianvs_terminal/lib/src/config/terminal_config.dart`：本地/SSH 共用的版本化会话配置模型。
- `example/lib/features/ssh/new_session_launcher.dart`：新增标签页时选择本地 shell、已保存 SSH、OpenSSH 动态配置或自定义 SSH。
- `example/lib/features/ssh/ssh_auth_prompt.dart`：把 Rust challenge broker 的每一轮 keyboard-interactive challenge 串行呈现，支持密码、OTP 等多轮提示，并避免并发弹窗。
- `example/lib/features/profiles/profile_repository.dart`：配置写入应用支持目录的 `ianvs_profiles.json`。

SSH 密码、私钥口令和 X11 cookie 不写入明文 JSON。`ProfileSecretCipher` 使用 AES-256-GCM 为每个字段生成独立 nonce，并将 profile ID 与字段名作为 authenticated data。32 字节对称密钥首次使用时自动生成，之后通过 `flutter_secure_storage` 从平台 safe storage 复用；iOS Runner 配置 Keychain Sharing，macOS 使用无需 provisioning profile、可由本地 ad-hoc 签名访问的标准登录 Keychain，其他平台沿用插件对应的系统安全存储后端。通用导出文件继续省略敏感字段。

## 验证结果

- Rust SSH/导入集中测试：11 项通过；`cargo test --lib -- --test-threads=1` 共 319 项全部通过。
- Docker OpenSSH 自动化验收：密码、PAM keyboard-interactive、两轮密码/OTP、Ed25519 公私钥、只能经 `jump -> jump2` 到达的目标机、L/R/D 转发、Agent forwarding 和 X11 forwarding 全部通过。测试连接全部使用 Rust `russh`，未调用系统 `ssh` 客户端。
- OpenSSH 导入 Dart 契约测试：1 项通过；SSH 导入映射、新建会话选择器、自定义高级配置和多轮 OTP Flutter 集中测试：5 项通过。
- `cargo clippy --all-targets -- -D warnings`：通过。
- `dart analyze --fatal-infos`：全项目无问题。
- macOS Xcode Debug 跳过签名的完整编译与链接通过，已将 `libianvs_core.dylib` 和 `flutter_secure_storage_darwin` 打进应用。普通可运行构建需要先为 Runner 配置 Apple Development 团队/证书，因为 Keychain entitlement 不能用于未签名应用。

`tools/ssh_e2e/run.sh` 是专用完整验收入口：构建固定 digest/版本的 Ubuntu OpenSSH 镜像，启动 8 个一次性服务，分配随机宿主机端口，验证隔离约束，运行被普通 `cargo test` 忽略的真实服务器测试，最后清理容器、网络、卷和临时密钥。GitHub Actions 的 `ssh-openssh` job 会在 Linux 上执行同一入口。

仓库原有的“切换 split pane 焦点”widget 测试隔离运行仍会失败：终端视图销毁时通过失活的 Riverpod context 查找 ancestor，之后还残留多个 timer。调用栈不经过本次新增的 SSH、加密存储或新建会话选择代码，作为独立既有回归记录。

## 与 Tabby 尚有差异

- 原生多跳 `ProxyJump` 已支持每一跳的 `[user@]host[:port]`，但各跳目前复用目标会话的认证材料；尚未支持引用拥有独立凭据的已保存 jump profile。
- OpenSSH 导入目前按打开新增标签页时动态读取；尚未实现 Tabby 的 mtime 磁盘缓存，因为本地文件解析成本较低且动态读取能避免陈旧配置。

这些差异不会退回系统 `ssh` 作为主 SSH 客户端；最终主机连接、加密、认证和远端 channel 均由 Rust `russh` 完成。
