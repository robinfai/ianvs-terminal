# Shell hook 能力清单与会话激活状态

范围为本地、SSH 自动注入及客户端已接入的兼容协议。SSH 每一层分别维护检查结果与运行观察。

## 能力清单

内置 zsh/bash/fish 脚本通过 DCS `hook;<hex JSON>` 发出 `precmd`、`precmd.pwd`、`preexec` 和 `command_finished`。配置启用、临时脚本创建成功、SSH 连接成功或获知 shell 名称，都不能证明其他能力激活。内置前 7 项可由当前 Shell 完成的初始化注册检查提前确认可用；下表列出后续可观察的运行证据。

| 稳定 ID | 能力 | 内置 zsh/bash/fish | 运行证据 | 当前用途 |
| --- | --- | --- | --- | --- |
| `current_directory` | 当前目录 | 有 | 合法 hook 的 `pwd/cwd`，或 shell_context 的目录 | 最近目录、同目录启动/恢复、目录规则、会话变量 |
| `prompt_lifecycle` | 提示符生命周期 | 有 | DCS `precmd`，或 OSC 提示符开始/结束事件 | 识别返回提示符；与可跳转的位置分开判断 |
| `command_start` | 命令开始执行 | 有 | DCS `preexec`，或 OSC `command_executed` | 命令生命周期与录制元数据 |
| `command_text` | 命令文本 | 有 | 命令生命周期事件中的非空命令文本 | 最近命令、最后命令、会话变量、录制元数据 |
| `command_finish` | 命令执行结束 | 有 | DCS/OSC `command_finished`，或 output zone 关闭 | 命令完成状态与录制元数据 |
| `exit_code` | 退出码 | 有 | 完成事件携带非负整数退出码，包含 0 | 上次退出码、成功/失败结果 |
| `shell_identity` | Shell 类型 | 有 | 合法 hook 或 integration_version 事件携带 shell | 会话元数据及变量查询 |
| `hostname` | 主机名 | `precmd.pwd` 上报真实 `hostname` | hook/shell_context 实际携带主机名 | 主机上下文、自动配置匹配、本地/远端目录判断 |
| `username` | 用户名 | `precmd.pwd` 上报 `id -un` | hook/shell_context 实际携带用户名 | 用户上下文、自动配置匹配、会话变量 |
| `integration_version` | 集成版本 | `precmd.pwd` 上报内置集成版本 `2` | DCS `integration_version` 或 OSC 1337 integration_version | 版本元数据；不推出其他能力 |
| `prompt_navigation` | 提示符跳转 | 原生解析 Hook 时记录真实提示符行 | 合法提示符绝对行/mark，或已转换并保留的 DCS 提示符位置 | 上一/下一提示符跳转 |
| `command_output_ranges` | 命令输出区域 | 原生解析命令生命周期时记录真实区域 | 关闭的 output zone，含有效 zone ID 与起止行 | Block 输出/AI 上下文使用原生输出区域；普通终端复制动作仍使用相邻提示符位置 |
| `user_variables` | 自定义 shell 变量 | 显式调用 `ianvs_set_user_var` | 接受的非空 `IANVS_` 用户变量 | 会话变量存储与按现有策略处理的查询 |

sh/dash/ash/ksh 等不进行自动注入，使用基础终端；服务器自行发送的兼容 OSC 元数据仍可被观察。历史实验中的 `SH_INIT` 目录回退不属于当前产品注入路径。

### 必须保留的区别

- OSC 133 B / `command_start` 是开始输入命令；OSC 133 C / `command_executed` 才表示开始执行。
- 普通 DCS `precmd` JSON 没有坐标，不能单凭消息名激活提示符跳转。原生解析器在收到它的位置打开 prompt zone，客户端保留有效 `zoneId/absRowStart` 后才确认可跳转。
- 普通命令开始/结束、退出码和提示符位置均不能替代协议提供的精确输出区域边界。当前 `_selectLastCommandOutput` 依据相邻提示符位置选择文本，并有当前画面的提示符回退逻辑，因此“复制命令输出”按钮可用性不等于 `command_output_ranges` 已激活。
- 最近命令和最近目录是数据消费功能，不是额外的传输能力。能力已激活不代表已有可供操作的历史项。
- 主机/用户/目录匹配提供自动配置切换的数据；是否配置匹配规则仍由现有业务逻辑决定。
- 基础输入、粘贴、普通选择/复制、滚动、文本搜索、文件传输、图像协议、通知和进度条不应因本清单未激活而被禁用。这些不由内置 shell hook 提供。
- 命令文本延续现有脚本语义。例如 bash 使用 `BASH_COMMAND`，不保证等于完整的多行输入或历史记录。

## 每个会话的状态

| 状态 | 含义 | 判定 |
| --- | --- | --- |
| `pending` / 待确认 | 本次会话尚无对应证据 | 新会话默认状态；等待本身不会升级成不支持 |
| `pending` + `awaitingEvent` / 等待实际事件 | 当前实现已提供，但尚未收到本项有效运行数据 | `provided` 回执；典型为尚未执行命令的输出范围、尚未设置的变量 |
| `notProvided` / 尚未提供 | 检查明确表明当前内置实现未提供本项 | `not_provided` 回执；不把超时或没有事件等同于未提供 |
| `active` / 已激活 | 本次 Shell 初始化检查通过，或收到有效事件 | 逐能力、逐窗格记录初始化与运行证据 |
| `disabled` / 已关闭 | 当前 profile 关闭 shell 集成 | 覆盖已有观察结果，忽略新的激活事件 |
| `unavailable` / 不可用 | 当前仿真模式不支持，或会话已退出 | 使用明确原因，不由沉默或超时推断 |

每项包含 `status`、`reason` 和可选的 `evidence`（初始化证据为 `bootstrapRegistration`）。初始化检查仅直接激活内置 7 项。其余 6 项可标记实现 `provided`，但必须有对应实际数据才能激活。状态不包含原始命令、目录、用户、主机名或自定义变量内容。

`active` 表示能力已可用，依据分为 `initializationChecked`（初始化注册检查通过）和 `observed`（收到实际事件）。本地初始化及 SSH / 子 Shell 的 `bootstrap.ready` 确认内置 7 项能力，不需要先执行命令。实际事件到达后把对应项的依据升级为 `observed`；重复初始化回执不会抹掉运行证据。

检查会确认必要函数、编码工具和 Shell 回调注册位置，不直接调用命令回调，也不自动执行测试命令，因此不产生最近命令、退出码、录制事件或历史记录。注册成功不等于完整的运行验证，也不是持续探活保证。提示符坐标、输出区域、扩展协议等仍需要各自的有效数据。明确检查失败使用 `initializationFailed` / `unavailable`，未知或超时维持待确认。

## 状态生命周期与查看入口

- `TerminalShellIntegrationSnapshot.capabilities` 保存会话独立的观察结果。
- `TerminalPane.shellCapabilities` 应用 profile、仿真模式和退出状态，提供完整 13 项有效状态。
- `SessionController` 消费已有 shell_hook、shell_context、shell_command、shell_user_var 事件更新能力，保留原有元数据与功能路径。
- 创建、恢复或重新打开会话：新进程从 `pending` 开始；不从旧布局、旧 shell 名称、cwd 或最近命令推断激活。
- 窗格移动/分离：同一 session 保留状态，不能把另一个窗格的证据复制过来。
- 终端 reset：清除观察结果并重新等待，保留现有 shell/版本元数据行为，但不能据此重新激活能力。
- 窗格退出：能力有效状态不可用；如果界面仍打开，显示会话已关闭。
- 桌面命令菜单、移动端会话菜单 → **会话能力**。对话框固定观察打开时的 session，并随其状态更新。
- 诊断导出的 `sessions.json` → `summary.shell_capabilities` 包含同一份完整状态与依据。

## SSH 初始化与逐层状态

已接入 [SSH 内存引导协议](ssh_shell_bootstrap.md)：小型初始化命令 → 最终交互 shell 请求主体 → 加载用户配置并检查/修复 Hook → 明确回执。原来的 SFTP 上传启动脚本路径已移除。

`bootstrap.checking` 切换到新的 shell context 并清空观察，`bootstrap.ready` 写入 `bootstrapPhase`、`bootstrapSource` 和 13 项 `registrationChecks`；`bootstrap.resume` 恢复父层快照并回收已退出层。检查事件不计入用户命令；通过检查的内置能力立即标为 active，依据为 initializationChecked。

注册检查使用 `registered / unavailable / provided / not_provided / unverified`，与有效状态 `pending / active / disabled / unavailable / notProvided` 一起保存。内置脚本确认前 7 项 Hook 注册；其余 6 项在当前 Hook 检查通过后记为 provided，等待各自的实际事件；检查明确失败记为 not_provided。未知或超时仍为 unverified。能力界面显示当前层、检查来源和已激活数，并区分初始化检查与实际事件；诊断导出包含同样的依据和检查结果。

能力对话框顶部的“连接链路”展示本机起点、SSH 连接配置中的 ProxyJump、逐层进入的 SSH Shell，以及当前所在层。SSH 节点包含用户名、主机和端口；IPv6 使用方括号。转发跳板与运行 Hook 的 Shell 分开标记，下方能力始终属于当前 Shell。对话框打开期间，进入子层会追加节点，返回父层会恢复原链路；重复的 checking/ready 不会产生重复节点，结束的会话标为“最后所在层”。

链路保存在会话的 `connectionChain` 中，不写回 profile 或布局，不包含认证信息或 ControlMaster socket。根连接使用本次会话的配置快照，ProxyJump 的独立连接覆盖与原生层保持一致。自定义 ProxyCommand 只标为代理通道；未被包装跟踪的命令、嵌套 OpenSSH 自身隐藏的代理跳板、代理内部路径不能由 Shell 事件推导，不把它们假装成已发现的节点。

交互式 Bash/Zsh/Fish 切换使用独立 Shell context 重新检测，但 `context_kind=shell` 不追加 SSH 节点。能力记录属于当前 Shell，文件通道属于稳定的 `host_context_id`；返回父 Shell 时两者分别恢复，避免同主机切 Shell 被误判为 SSH 跳转。链路采用紧凑纵向轨道、终端/服务器图标、当前行高亮与跳数摘要，窄屏自动把状态置于地址下方。

[生产 OpenSSH runner](../../tools/ssh_boundary_lab/product.py) 使用实际 Rust SSH/PTY transport；
客户端状态和显示分别由 [session 测试](../../example/test/sessions/session_controller_test.dart) 与
[能力对话框测试](../../example/test/sessions/shell_capabilities_dialog_test.dart) 覆盖。

## 本地运行验证与自定义变量

内置集成版本为 `2`，检查包含公开的 `ianvs_set_user_var` 函数；旧 Hook 缺少它时，不再被认作当前完整实现。主机名与用户名在安装时读取真实系统值并缓存，避免每次显示提示符启动外部命令。读取为空时不伪造元数据。

默认纯净本地会话在首个提示符后为 11/13：7 项基础能力，加主机、用户、版本及真实提示符坐标。第一次命令完成后输出区域激活，达到 12/13。只有显式设置有效非空变量时才会成为 13/13，例如：

```sh
ianvs_set_user_var IANVS_PROJECT 'my-project'
```

该函数适用于内置 zsh/bash/fish。名称须为 `IANVS_` 开头的 ASCII 字母、数字或下划线，最长 80；值最长 512 字符。参数不合法返回 2。函数发出带当前 context 的 DCS `user_variable`，原生端沿用现有 SetUserVar 的有界存储与事件链路；旧 context、备用屏幕和超长输入均不接受。不会自动遍历或上报环境变量；空值也不会单独证明能力已激活。普通 OSC 1337 SetUserVar 仍兼容。

这些计数是纯净 fixture 的验证结果，不是所有用户配置必须达到的固定指标。用户配置冲突、缺少系统身份命令或会话未出现对应事件时，界面保留具体原因。

真实验证记录见 [2026-10-17 本地 Shell 能力验收](../product/local-shell-capabilities-2026-10-17/README.md)。
