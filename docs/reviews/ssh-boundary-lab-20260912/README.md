# 多级 SSH hook / ControlMaster / SFTP 边界实测

验证日期：2026-09-12。Colima Docker，20 个一次性 OpenSSH 容器配置，30 项断言全部符合预期；其中包含明确应失败或降级的场景。原始证据见 [results.json](results.json)、[runner.log](runner.log) 和 [manifest.json](manifest.json)。

**结论：hook 可以独立于 ControlMaster、SFTP 工作；多层 SFTP 可以复用正在交互的原连接。实现仍需要逐层 shell 上下文、非 PTY 文件通道、实际复用确认和明确的降级状态。直接向终端发送 eval 不能满足通用的脚本不持久化要求。**

本次新增可复现的容器夹具与实验原型，未修改产品 SSH 后端。当前应用仍未实现无 SFTP 启动注入、展示前检查、逐层上下文切换和 SFTP 面板跟随。本报告不代表 Flutter 界面端到端验收。

## 环境与证据强度

- 远端：Ubuntu 24.04，OpenSSH `9.6p1-3ubuntu13.18`，bash `5.2.21`，zsh `5.9`，fish `3.7.0`，tmux `3.4`；本地主机 OpenSSH `10.2p1`。
- hook 直接提取当前 [`native/core/src/pty.rs`](../../../native/core/src/pty.rs) 中的脚本，实验层仅增加上下文归属、握手和受限的 SSH 包装函数。
- B、C 不发布主机端口。A、B 从启动起就不配置 SFTP 子系统。
- 文件通道使用真正的 SFTP v3 二进制报文，而非解析 `ls` 或交互命令输出。数据覆盖全部字节值、NUL、ESC 和类似 hook 的内容。
- 各层复用客户端只有错误密钥，禁用交互认证。无 master 的对照连接以 255 失败，复用成功；另检查 sshd 的成功认证计数未增加。
- 镜像 ID、包版本、代码与 hook 文件哈希均记录在结果中。归档时重新核对代码哈希，确认与执行版本一致。
- 容器、网络、一次性密钥已清理；仅保留可复用实验镜像和报告文件。

## 已证明可行的路径

| 实测 | 结果 | 证据 ID |
| --- | --- | --- |
| bash 无 SFTP、无 ControlMaster | 7 项 hook 能力均收到事件，退出码 7 正确，ready 在首个提示符之前 | `bash-memory-nosftp-nomaster` |
| zsh / fish 无 SFTP | 在最终交互 shell 中以内存代码安装，7 项能力与退出码正确 | `zsh-memory-nosftp`、`fish-memory-nosftp` |
| 服务器已安装同一套 bash hook | 检查后复用，同一命令只收到一次完成事件 | `bootstrap-preloaded` |
| A→B→C，随后 C→B→A | 每层有不同上下文 ID、父子关联和独立能力证据；返回事件顺序正确 | `nested-a-b-c-return` |
| A 已激活，下一层 hook 不可用 | 子层没有能力事件，父层恢复后继续工作 | `nested-unhooked-child-isolation` |
| A、B 均无 SFTP，访问 C | C 上完成 131,354 字节上传下载，SHA-256 一致 | `multi-hop-sftp-binary-reuse`、`both-intermediates-without-sftp` |
| 复用正在交互的三层连接 | A/B/C 成功认证计数保持 `9/2/4`，没有新增认证 | `live-terminal-sftp-reuse-and-pinning` |
| 传输过程中退出 C 返回 B | 同一已打开文件句柄仍在 C 完成 52,224 字节写入；B 没有误写文件 | `live-terminal-sftp-reuse-and-pinning` |
| 中继服务器禁止 TCP 转发 | 仍可通过允许的 exec session 中继文件数据 | `exec-relay-with-forwarding-disabled` |
| home 和 /tmp 对登录用户不可写 | bash 的管道与 `/dev/fd` 引导仍成功，7 项能力可用 | `readonly-home-tmp-bootstrap` |
| 密码认证 | 先出现密码交互，认证成功后才收到 hook ready | `password-before-readiness` |

大文件往返 SHA-256：`e42bb191fb6dfbc8e70b4bc1daa6888977a96b3430f6e761cee53ebd99f5d542`。

跨退出传输 SHA-256：`1e71dcbaae982fe97e1062ce93c8784b4a6b0300840010ebddee79345038bb03`。

## 实际复现的限制

| 条件 | 观察到的结果 | 对实现的要求 |
| --- | --- | --- |
| 只有 `__IANVS_SHELL_INTEGRATION_LOADED=1`，没有函数/注册 | 原脚本跳过安装，没有 hook 能力 | 检查真实注册，不能相信环境变量标记 |
| 启动配置已有 `trap ':' DEBUG` | 本版本 bash 安装器最终将其替换为 `__ianvs_preexec` | 先解决 DEBUG trap 共存或明确放弃安装；当前 guard 在本场景未保护原 trap |
| `command ssh`、`exec /usr/bin/ssh` | 绕开包装；不会产生子上下文握手，后者没有父层返回事件 | 保留未知/失联状态，不能继续展示父层能力为当前能力 |
| 非交互远程命令 | 实验包装器原样透传，保留带空格参数 | 不应把所有 SSH 调用改成交互 bootstrap |
| 目标解析/连接失败 | SSH 返回 255，父层恢复，没有子 ready | 连接尝试与已建立 shell 上下文分开 |
| 目标没有 SFTP | 子系统被拒绝，shell 继续可用 | 文件能力独立降级 |
| `PermitTTY no` | PTY 被拒绝，SFTP 仍可用 | PTY 能力与文件能力分开 |
| `MaxSessions 1`，已有终端 | 额外 SFTP channel 失败，终端仍能执行命令 | 不承诺有 master 就一定能开文件通道 |
| `ForceCommand` | bootstrap 被替换，SFTP 也无法正常握手 | 按实际请求结果降级，不自动发送更多注入命令 |
| 中继节点 `.bashrc` 往 stdout 输出文字 | SFTP 报文长度解析立即失败 | 中继必须提供干净的二进制 stdout，不能随意丢弃未知前缀 |
| 最后一层 master 被关闭 | 错误密钥无法重新认证，文件通道失败 | 精确报告复用失效，不能把回退重连伪装成原连接 |
| ControlPath 过长 | OpenSSH 拒绝 Unix socket 路径 | 使用短路径并给临时后缀留余量 |
| bash 未配置 `HISTCONTROL=ignorespace` | 前导空格的 `eval … base64 -d` 仍写入 `.bash_history` | 盲发 PTY eval 不是通用无持久化方案 |
| bash 启动配置 `exec fish` | 原 bash 引导未发 ready，最终进程是 fish；换用 fish 适配才成功 | 检查最终 shell，不能仅用登录 shell 或 `$SHELL` 决定 |
| tmux 默认处理普通 DCS | hook 帧未到达客户端；启用 passthrough 并包装后到达 | 需要显式适配；本实验不代表可以静默更改用户 tmux 全局配置 |
| POSIX sh 回退 | 仅有 OSC 7 目录事件，没有完整命令生命周期 | 按能力逐项表达支持范围 |
| 缺少 `od` / `tr` | 安装未激活，普通 shell 命令可运行 | 辅助工具检查失败与 SSH 连接失败分开 |

## “无持久化”和“显示前检查”的精确范围

实验扫描了 A、zsh、fish、只读节点的 home 与 `/tmp`，没有找到本轮注入代码的文件或历史副本；同时检查 sshd 子进程的文件系统调用，没有 `/tmp` 脚本创建尝试。结果中的 `created_paths` 是 `O_CREAT` **调用尝试**，包括只读节点写历史失败的情况。fish 自身会更新变量缓存和普通命令历史，因此这里的要求是注入脚本不持久化，不是服务器完全没有文件写入。与之对应，关闭忽略空格历史配置的独立负例确实发现了脚本进入历史。

bash 原型使用管道 rc-file 引导，实测 ready 早于第一个提示符；它尚未保证完整登录启动文件语义。zsh/fish 原型先等待已知夹具提示符，缓存其输出，再向同一个交互进程安装 hook。这个结果证明内存安装可行，但没有解决任意主机的提示符识别、认证/TUI 区分或产品 UI 的展示门槛。

ready 表示本轮检查阶段结束，不能直接等同于所有能力均已运行过。各项能力仍由对应事件验证；命令结束与退出码在执行测试命令后才得到证据。

不应将本结果扩大为“任意 OpenSSH 版本、所有第三方 hook、任意 shell 配置或所有复用工具都可用”。本轮没有覆盖 screen、受限 shell 的全部变体、MFA/OTP、进程崩溃/挂起的全部时序，也没有验证应用 UI 的跨上下文文件操作。现有独立 SSH acceptance 夹具包含原生传输的其他认证测试，但不被计入这里的 30 项。

## 对下一步实现的约束

1. 将终端窗格、SSH transport、shell context、文件 endpoint 分开建模。UI 只展示当前 context 的能力；在途传输固定 endpoint。
2. 检查必须发生在最终交互 shell；保留已检查/已注册与已观察到事件的区别。密码等认证交互先正常展示。
3. 优先实现 bash 的内存引导，处理登录启动文件语义与 DEBUG trap 共存；zsh/fish 需要独立解决无历史泄漏的引导时机。
4. 每层记录可复用连接的发起端与控制路径；原生 SSH 复用 handle，远端 OpenSSH 在 socket 所在主机接入，再传回独立的非 PTY 二进制流。
5. 将缺少 SFTP、master 消失、channel 配额、stdout 污染和未知 shell 等原因呈现为明确状态。禁止将上一层主机名称替换后继续对旧 endpoint 操作。

复现步骤和原型范围见 [实验工具 README](../../../tools/ssh_boundary_lab/README.md)。
