# SSH 能力与交互最终审查

审查日期：2026-08-08
审查对象：`codex/tabby` 当前工作区的 macOS Debug/Release 构建
结论：通过。关键 SSH 任务链路完整，当前轮次发现的布局问题已修复并重新验证，没有遗留的阻断级或中优先级 UI 问题。

## 本轮独立审查步骤

1. **新建标签页入口 — 健康**
   - Local shell 与 SSH session 作为同级来源，选择关系清楚。
   - 保存的会话与 `.ssh/config` 主机可以从同一入口搜索和选择。
   - 证据：`01-new-tab-source.png`、`02-ssh-search.png`。

2. **自定义 SSH 表单 — 健康（本轮已修复）**
   - 主机、端口、用户名、认证方式、凭据等信息层级清晰。
   - 本轮在 1437×768 窗口发现“Save this SSH session”被滚动区与底部操作栏裁切；已将其移到固定底部区并增加回归测试。
   - 问题证据：`03-custom-form-clipped.png`；修复证据：`04-custom-form-fixed.png`。

3. **认证方式切换 — 健康**
   - Automatic、Private key、Password、Keyboard interactive / OTP 的选择明确。
   - 切换到 Keyboard interactive / OTP 后不会继续展示无关密码或私钥字段，并解释凭据会在服务器请求时弹出。
   - 证据：`05-keyboard-interactive.png`。

4. **高级 SSH 能力 — 健康**
   - 主机密钥策略、ProxyCommand、ProxyJump、L/R/D 转发、agent forwarding 与 X11 forwarding 均有对应控制。
   - ProxyJump 和端口转发提供输入格式说明，固定底部仍保留保存与连接动作。
   - 证据：`06-advanced-options.png`。

5. **多轮 Keyboard-interactive — 健康**
   - 真实 OpenSSH OTP 容器先请求 Fixture password，再请求 One-time password。
   - 弹窗显示目标主机、当前问题、隐藏输入，并支持取消。
   - 证据：`07-auth-prompt-round1.png`、`08-auth-prompt-round2.png`。

6. **真实 SSH 连接态 — 健康**
   - 两轮响应完成后建立 Rust SSH 会话，标签页切换到远端终端并显示远端提示符。
   - 证据：`09-otp-connected.png`。

7. **用户自定义会话管理 — 健康**
   - 配置列表支持搜索、新建、编辑、删除和直接打开；默认配置有明确标识。
   - 删除前显示不可误解的确认信息，危险动作使用红色强调；本轮仅打开确认并取消，没有修改用户配置。
   - 证据：`10-profile-management.png`、`11-delete-confirmation.png`。

## 自动化验收

- Docker OpenSSH 矩阵：通过。覆盖密码、keyboard-interactive、两轮 OTP、公私钥、两跳 ProxyJump、本地/远端/SOCKS5 转发、agent forwarding、X11 forwarding。
- Flutter/Dart SSH、配置、密钥存储、`.ssh/config` 导入测试：138 项通过。
- Rust 核心单元测试：319 项通过。首次完整运行有一个既有并发时序测试瞬时失败；该用例单独复跑及完整套件复跑均通过。
- Rust Clippy：通过，`-D warnings` 下零警告。
- Dart 静态分析：通过，零问题。
- Dart/Rust 格式检查与 `git diff --check`：通过（全项目 Dart 格式检查另发现一个未改动文件 `example/test/terminal/render_terminal_viewport_test.dart` 的既有格式差异，不属于本轮改动）。
- macOS Release 构建：通过，产物 `example/build/macos/Build/Products/Release/Ianvs Terminal.app`，64.9 MB。

## 可访问性与限制

- 正向项：关键按钮有可读名称；删除动作有明确确认；OTP 响应默认隐藏；表单阅读顺序与视觉层级一致；小高度窗口的关键保存和连接动作始终可见。
- 证据限制：Flutter/macOS 的辅助功能树能读取主要按钮、说明与弹窗，但部分 `TextField` 在自动化树中只暴露空的输入节点，无法仅凭本轮工具输出证明完整的 VoiceOver 标签关联。视觉标签与组件测试均正常，但建议后续单独进行 VoiceOver 人工验收。
- 审查边界：本轮只验证 macOS；Windows/Linux 的系统密钥存储、X11 环境和平台辅助技术未做视觉验收。

## 环境清理

- 本轮临时 OpenSSH 容器已全部停止并删除。
- `[127.0.0.1]:32855` 测试主机密钥已从 `~/.ssh/known_hosts` 移除。
- 用户配置仍仅包含原有 `Local Shell` 与 `Strict VT220`，未保存测试 SSH 会话。
