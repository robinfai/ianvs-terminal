# SSH Shell 内存引导

实现日期：2026-09-12。参考 [Warp 的两阶段引导与回执控制](../reviews/warp-shell-bootstrap-20260912.md)。生产实现位于 `native/core/src/shell_bootstrap.rs`、其脚本目录、`ssh.rs` 和 `pty.rs`。

## 配置与入口

| 配置 | 默认 | 作用 |
| --- | --- | --- |
| 全局 `shellIntegration.sshWrapper` | 开启 | 设置 → 常规：在新建的本地 Bash/Zsh/Fish 会话中包装交互式 `ssh` 命令 |
| 全局 `shellIntegration.sshAutoInject` | 开启 | 设置 → 常规：新建协议 SSH 会话自动检查和注入；注入后的远端 shell 继续包装 SSH |
| SSH 连接 `shellIntegration.sshAutoInject` | 继承 | SSH 编辑器 → 高级选项：继承全局 / 开启 / 关闭 |

已有配置无需迁移，缺省值按上表解析。连接覆盖项以省略字段表示继承，显式 `false` 不被默认值覆盖。设置只影响新会话；应用在创建运行时之前解析最终值，保存的 profile 保留继承关系。公开终端包的 `sshWrapper` 默认关闭，由宿主应用显式启用；原有 `enabled` 和仿真模式约束继续有效。

两个全局开关独立：关闭本地命令包装，不会关闭协议 SSH 的自动注入。关闭自动注入，也不会禁止观察服务器自行发送的兼容 Hook。

## 时序

1. 协议连接完成认证、申请 PTY 后发送很小的引导命令；本地命令包装保留 SSH 参数，在适用的交互连接后追加同一命令。
2. 先通过兼容 Bash/Zsh/Fish 的编码进入 `/bin/sh`，再启动目标 shell。Bash 使用进程替换提供小型 rcfile；Zsh 禁用启动文件和 ZLE，并提前打开忽略空格历史；Fish 使用 `--init-command`。
3. 最终 shell 发送带有本层标识的私有 Init 消息。客户端只向当前已登记的层回复一次主体；不依赖提示符文字或固定延时猜测。
4. 主体通过现有 PTY/SSH channel 传入。Bash/Fish 在受控读取阶段消费主体，Zsh 使用以空格开头的单个历史事件，并把物理行限制在 PTY 的行长度以内。连接初始化期间缓冲用户输入，避免混入主体。
5. 加载用户配置，检查实际函数及 DEBUG/PROMPT_COMMAND、Zsh hook 数组或 Fish event 注册。兼容 Hook 复用；残留的已加载标记可以修复；Bash 的第三方 DEBUG trap 保留并报告冲突。内置回调被直接串入额外 PROMPT_COMMAND 命令时也报告冲突，避免误重装递归和提示符内部命令被错误记录；正常用户提示符命令仍由安装器在受保护的回调中保留。
6. 收到 Ready 后先发布检查结果，再显示 Connected。内置 7 项能力在注册检查通过时立即可用，实际命令和提示符事件随后更新各项运行证据。超时转为基础模式，不再向未知 shell 重试粘贴脚本；服务器拒绝 exec 时尝试普通 shell 请求。

认证和启动输出可以在连接阶段显示。检查完成不等于所有功能已被运行验证。

本地 Bash/Zsh/Fish 的初始化同样使用共享检查脚本并发送经当前会话标识验证的 Ready。Bash/Fish 在用户配置和注入完成后检查；Zsh 在首次 precmd 前执行一次检查，覆盖 `.zlogin` 对 Hook 的修改。无需用户先执行命令，不伪造命令生命周期。为了允许本地 rc 的交互式询问，本地根 Shell 等待检查时不缓冲用户输入；SSH / 子 Shell 的主体保护规则保持不变。

## 不持久化与多层控制

远端不上传脚本、不写临时脚本、不修改 dotfiles，也不要求 SFTP、curl 或远端代理安装。脚本通过内存通道传输；受控读取和 Zsh 的首次历史过滤避免把正文送入普通交互历史。主机已有的审计或用户配置自身的写入行为仍由服务端决定。

每次包装的 SSH 调用建立独立 context。进入时保存父层能力和目录，返回时恢复。每层使用独立控制标识；子层拿不到父层的控制凭据，不能伪造返回本地后再挂接其他控制 socket。会话级标识不传给 SSH 的环境转发。

同一层只接受一次 Init/Ready，处理分片、重复、过期和跨层消息。最多支持 128 个同时存在的层；退出层回收，历史文件请求保留自己的目标快照。控制帧上限 8 KiB，初始化输入缓冲上限 64 KiB，主体阶段等待上限 10 秒。

## 交互式子 Shell

支持在已集成的本地或远端 Shell 中直接执行 `bash`、`zsh`、`fish`，以及 `-i` / `--interactive`。包装函数发送 `enter_shell`，在相同主机下登记新的 Shell context，使用内存引导重新检查 Hook；普通子 Bash 加载 `.bashrc`，子 Zsh 不加载登录 profile。退出时恢复父 Shell 的能力快照。子 Shell 包装由 shell integration 总开关控制，本地关闭 SSH 包装不会关闭此能力。

`context_kind=shell` 表示同主机的子 Shell，`host_context_id` 固定为所属 SSH 层或本地主机 root。界面不为它新增 SSH 节点或跳数；SFTP 使用稳定的主机 context，在 Shell 检查阶段也保留面板。原生层只允许当前 Shell 或其所属主机 context 发起新文件操作，不能借此访问其他祖先主机。

脚本执行、`-c`、登录/自定义启动参数及非 TTY 调用保留原命令行为；`command bash`、绝对路径和 `exec bash` 绕过函数包装，当前不会自动重新集成。此边界不影响直接输入 Shell 名称进行交互式切换的修复。旧会话不自动补装新包装函数，更新运行中的应用后需新建会话。

## ControlMaster 与 SFTP

Hook 注入本身不依赖 ControlMaster。命令包装会优先复用配置中仍存活的 master；没有可用 master 时，创建只包含 socket 的目录并使用 `ControlMaster=auto`、`ControlPersist=60`。已有 master 不由本功能停止。自建 master 空闲后由 OpenSSH 退出，包装函数尝试回收空目录；这些是连接元数据，不包含注入脚本。

SFTP 请求携带 `contextId`，由原生层解析到已验证的 socket 链。在协议连接上新增 exec channel，在本地通过 OpenSSH 子进程建立二进制流。中间层只需要 SSH exec；最后一层才需要 SFTP subsystem。每一步都禁用重新建网连接的回退，socket 消失即失败，不会重新认证或切到其他主机。

列表、下载、上传及上传后的原子替换共享同一个目标快照，进行中的操作不随 shell 切换而改变主机。新发起的文件操作要求目标层仍为当前层；旧编辑器的后续自动回传会明确失败并保留本地修改，需返回原层后再尝试。已退出的层不会因重新连接同一主机而自动复用旧 ID。

文件面板在检查期间暂不展示旧层内容，完成后按新 context 创建面板，返回时恢复到父层。服务器没有 SFTP 时显示文件服务不可用，终端 Hook 仍可正常工作。

## 适用边界

自动包装针对没有远端命令的交互式 `ssh`。远端命令、`-T`、`-W`、`-N`、后台/无 stdin 模式、master 管理命令以及不能可靠解释的参数保持原命令行为。`command ssh`、绝对路径 SSH、自定义连接程序和已有 shell 中未安装的包装函数不会自动跟踪。

当前支持 Bash、Zsh、Fish；不支持的 shell、强制命令、被 rc 文件替换的 shell 或 tmux 会话不能承诺自动恢复完整能力。检测失败时保留基础终端，不绕过服务器限制。递归文件通道仍受 MaxSessions、exec 权限和最后一跳 SFTP 配置约束。

验证步骤和结果见 [产品验收](../reviews/ssh-product-bootstrap-20260912/README.md)。
