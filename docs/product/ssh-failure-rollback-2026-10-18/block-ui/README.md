# SSH 失败后恢复 Block 工作区

## 原因与行为

上一轮修复了 SSH wrapper 的父上下文回退、退出码和后台清理，但 Rust 协议验收没有覆盖 Flutter 的显示模式。`TerminalModeController` 原来把每次能力暂时不可用都降为普通模式，恢复后只提示手动切回。因而即使 `ssh sg` DNS 失败后 cloud 的跟踪已正确恢复，界面仍停留在普通终端。

真实原生验收另发现：远端 adapter 已注册、尚未提供 ready lease 的 `draft` 状态被误判为不支持 Shell，进一步清除了恢复意图。现在已注册远端未声明 degraded 时，该状态表示等待协商；只有匹配上下文的 ready lease 才允许恢复输入。

- SSH 连接或认证期间继续由普通终端接管；原先选择 Block 的会话在协商恢复后自动回到 Block。
- 失败第二跳不改变当前 cloud 目标，也不要求重新切模式或新建任务。两次失败之后可继续使用同一个 cloud 任务输入命令。
- 显式选择普通模式、重新检查、LLM 限制、只读、全屏和其他非 SSH 能力丢失会取消自动恢复；不自动发送草稿，不主动抢焦点。
- 成功进入另一台主机仍保留 AI 任务的执行目标确认。原生用例在第一跳成功后通过 UI 明确新建 cloud 任务；随后两次失败第二跳之间没有切模式、确认目标或重建任务。

## 验证

- 相关 Composer、桌面和移动模式组件回归 **126/126**。
- 新增 SSH 模式测试在旧源码失败，修复后通过；覆盖协商中的 draft、不同上下文隔离、退出码 255 后恢复、保留草稿与不抢焦点。
- 模式控制器覆盖显式 Normal、只读、全屏、重新检查和 LLM 限制取消恢复，以及 running/unknown 不能作为 ready 授权。
- macOS **27.0.1 (26A434)** 原生 Flutter App、真实产品 PTY / zsh、隔离 OpenSSH **10.0p2** 和远端 Bash **5.2.37**，UI 验收 **1/1**：从 Block 输入第一跳命令，进入 cloud 后显式新建目标任务；两次从共享输入框发送 `ssh sg`，分别验证同一 cloud 上下文、更新的 ready lease、Block 自动恢复及命令块退出码 **255**；再从同一输入框执行 `printf` 并收到输出。无后台 `[1] PID` 提示。
- 使用临时容器、临时密钥与独立配置；严格检查 fixture 的主机公钥，结束后自动清理。没有使用用户生产 cloud、SSH 配置或凭据。environment.json 列出 fixture 中可用 Shell；本轮 UI 实际使用 Bash cloud，不能视为本轮 Zsh/Fish 远端 UI 验收。
- 静态分析、Dart 格式、Python 语法及 diff 检查通过。本轮未新增手机实机验收。

## 复跑

在仓库根目录执行：

```sh
python3 tools/ssh_boundary_lab/rollback.py --flutter-ui --flutter /path/to/flutter --output build/ssh-block-rollback
```

默认使用已有 `ianvs-ssh-rollback:20261018` 镜像；构建方式见上级 README。未传 `--flutter-ui` 时保持原 Rust 协议测试入口。

## 交付

保持 PR Draft / OPEN，不合并。生产入口签名 Release 构建与完整签名校验通过，待安装包已准备。本轮没有重启用户当前生产 Trail 或打断其 SSH 会话；安装状态在 PR 描述中单独列明。
