# SSH 失败后的父会话保持与静默清理

当本地终端已通过 `ssh cloud` 进入第一跳，再执行无法解析的 `ssh sg`，第二跳应作为 cloud 上的一条失败命令结束。它不能新增已连接主机、清空 cloud 的能力状态或把文件面板路由到 sg。

## 实现

- wrapper 的 `enter` 仅登记待连接尝试。收到远端 launcher 的 `init`（或真实的 unsupported-shell 回执）后才激活子上下文、切换 Composer，并发布 `bootstrap.checking`。
- DNS、网络或认证失败时，保留父上下文；`resume` 携带 OpenSSH 退出码 255，注销未激活的尝试。之后到达的旧 `init` / `ready` 无法复活它。父主机目录、能力和连接链保持；命令块仍归属父主机。
- 连接失败留下的空 socket 目录立即删除。有存活 ControlMaster 时，从非交互子进程启动延迟 `rmdir`，不进入用户 Shell 的作业表，不打印 `[1] PID` 或完成提示，不主动停止 master。用户已有后台作业不再受到 `disown %+` 的影响。
- 真实 Fish 验收发现 bootstrap 使用普通 `read` 会启动交互行编辑器、回显大段初始化数据。改为 `read --null --delimiter ''` 与 NUL 结尾载荷，绕过行编辑器；真实 Fish SSH 初始化和失败回退一起通过。

## 真实验收环境

macOS 27.0.1 (26A434) 上使用产品 `spawn_terminal_transport` / PTY、生产 SSH wrapper、系统 OpenSSH 客户端及原生命令块解析器。服务器是临时 Docker 网络中的真实 OpenSSH 10.0p2；第一跳分别运行 Bash 5.2.37、Zsh 5.9、Fish 4.0.2。私钥临时生成，主机公钥从测试容器直接取得并严格校验；未关闭 host-key checking。

`cloud` 是隔离验收服务器别名，**不是用户的生产 cloud 主机**；未修改用户 SSH 配置、远程账户或正在运行的 App。所有测试容器、网络和临时密钥在结束时清理。

每种 Shell 验证：

1. 本地 → 第一跳成功，SFTP 下载第一跳 `role.txt`。
2. `ssh sg` → 真实 DNS 失败；`ssh refused` → 真实 TCP 拒绝；`ssh denied` → 真实认证拒绝；再重复 DNS 失败。
3. 每次失败都检查退出码 255、父上下文恢复、没有子会话 checking/ready、没有后台作业编号；SFTP 仍读到第一跳角色，随后 `false` 仍由父上下文跟踪并上报退出码 1。
4. 将真实 PTY 输出交给生产 VT 解析器，检查 `ssh …` 的父上下文命令块已关闭且退出码为 255，当前目录仍为 `/home/lab`。
5. 确认失败留下的空 socket 目录已立即清理；再成功进入第二跳 `target`，验证文件路由，退出后恢复第一跳；正常退出也不打印清理任务编号，`jobs` 为空。

原始环境、每个场景结果与测试日志见本目录文件。

## 回归

最终真实验收 **1/1 通过**：三种远端 Shell 共 12 次失败、3 次成功第二跳往返；全部父主机路由与清理断言通过。

- bootstrap：21 通过；常规运行跳过 2 个依赖 fixture 的入口，其中本次失败回退入口另行真实执行。未运行旧的全量 SSH boundary fixture。
- 原生 Composer：8/8；本地 Shell 能力和解析边界：5/5。
- 远端 Composer：5/5（包含真实 zsh 内存 bootstrap）。
- 应用 SessionController：106/106，包含失败回退后连接链、能力、目录与退出码检查。
- 应用静态分析、Dart/Rust 格式、生成的 core 镜像一致性及 `git diff --check` 通过。

本轮未新增手机或 Windows/Linux 客户端 UI 验收，未覆盖安装当前 Trail，PR 保持 Draft / OPEN，不合并。

## 复跑

在仓库根目录执行：

```sh
docker --context colima build -f tools/ssh_boundary_lab/rollback.Dockerfile \
  -t ianvs-ssh-rollback:20261018 tools/ssh_boundary_lab
python3 tools/ssh_boundary_lab/rollback.py --output build/ssh-rollback
```

可通过 `--context` / `--image` 指定本地 Docker 环境。镜像摘要和实际 Shell/OpenSSH 版本记录于 `environment.json`。

## Block 界面后续修复

父上下文恢复不代表界面恢复。后续用户在 Block 中复现了模式遗留，根因、修复与真实原生 UI 验收见 [Block 工作区恢复](block-ui/README.md)。

历史验收原件保留在[固定提交目录](https://github.com/robinfai/ianvs-terminal/tree/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/ssh-failure-rollback-2026-10-18)。运行日志和临时产物已按文档归档规则移出当前 `docs/`；此处结果仅对应文中记录的构建与环境。
