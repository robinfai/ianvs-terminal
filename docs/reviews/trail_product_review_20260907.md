# Trail 功能全景、产品取舍与后续路线建议

评估日期：2026-09-07。对象：当前工作树中的 Trail（仓库及部分文档仍称 Ianvs Terminal）。

> 本文保留退役前的评估快照（62 个动作、39 项白名单）。后续实施状态见 [白名单外功能退役记录](trail_feature_retirement_20260907.md)。

## 1. 核心判断

**项目已有相当厚的终端能力，下一阶段应把投入重心从扩展能力转向完成用户任务、降低使用门槛和验证特色价值。** 当前最值得保住的是本地终端、SSH、多会话、搜索复制、SFTP，以及已经投入较深的回放能力。

建议主定位：**面向个人开发者与小规模服务器维护者，以 macOS 为主、能够方便连接并回看操作过程的终端。** iPhone/iPad 作为远程连接的配套端；SDK 作为复用与外部分发渠道；数据服务作为可选同步设施。三者分别设投入上限，不与主应用同时展开产品扩张。

“回看操作过程”是依据现有资产提出的差异化假设，尚无用户留存或付费证据证明成立。应先验证用户是否反复需要找回刚才的输出、定位失败命令、重看已保存会话，再决定是否继续做复杂录制管理。

最优先的五项调整：

1. **本地保存 SSH 配置应独立于数据服务。** 当前无 API 模式有本地存储，却限制自定义 SSH 配置；iOS 保存主机还依赖远程 API。这会把基础使用行为变成服务部署与密钥管理任务。
2. **统一“回看”入口，补上最小闭环。** 最近画面回看、主动录制和文件回放都存在，但录制库侧栏在当前主界面被 `shelfOpen: false` 关闭。先解决录完后如何再次找到，而不是扩大媒体库功能。
3. **处理隐藏功能的存量成本。** 62 个动作中有 39 个在正式入口白名单，23 个不在。隐藏只是入口策略，不等于实现、状态管理与验证成本已经消失，也不等于底层能力不存在。
4. **把范围文档重新对齐到实际产品。** 当前文档仍有“无云同步”“只支持 macOS”“JSON frame 交互”等陈旧说明；代码已经有远程同步、iOS SSH 和当前 Protobuf packet 边界。继续按这些文档扩功能容易反复推翻决策。
5. **冻结低证据扩张。** 暂不新增协议长尾、独立密码管理器、自动化平台、插件市场、项目/IDE 容器、全面多平台发布，也不同时运营完整云产品与 SDK 产品线。

## 2. 评估方法与边界

本次采用主代理与三个子代理分别检查功能入口、历史/架构、数据/平台，主代理交叉核对关键结论。审查了源码、动作注册、实际回调、平台入口、测试文件、历史验收记录和 Git 演进；未运行应用、Flutter 全量测试、`make verify` 或新一轮性能测试。数据子代理执行了 Go 后端测试、WebUI 单元测试与类型检查，结果见第 12 节。其他现存测试仅说明有验证资产，不表示当前工作树全部通过。

以当前未提交修改在内的工作树为准，Git HEAD 为 `fb32a051`；已有修改涉及界面、主密钥、环境隔离与原生终端颜色。本次仅增加评估文档，不删除功能、不修改这些实现，也不替换已有产品范围决策。

没有收到活跃用户、功能使用频率、故障率、收入或外部 SDK 使用者数据。因此：

- “价值”是相对于上述目标用户的产品判断，不是测得的使用率。
- “成本”是根据状态复杂度、平台依赖、数据/协议边界推断的相对维护负担，不是工时估算。
- “已接入”指源码中有产品调用链；“隐藏”指默认正式入口受限；“底层”指有实现但不能当作完整可发现的用户功能宣传。
- 精简分为保留、合并、收进高级设置、冻结、归档候选。**归档候选必须先检查调用、已有用户数据及外部依赖，不能直接按文件名删除。**

规模快照：Git 已跟踪的 `example/lib` 手写 Dart 文件 234 个、约 93,770 行（排除 l10n generated）；应用测试 Dart 文件 203 个；`docs` 下 Markdown 553 个。仅按文件名匹配 completion/verification/wiring/closure/audit/evidence/manifest，shell 目录就有 33 个相关 Dart 文件、4,633 行。它们说明检查和维护的范围很大，不能据此判定每个文件都无价值。SDK 生成镜像不作为第二套手写实现重复计费。

## 3. 项目如何发展到现在

| 阶段 | 已形成的资产 | 产品上的变化与取舍 |
|---|---|---|
| 4 月：终端基础与应用壳 | 最早可见基线为 4 月 15 日；持续完善 tab、关闭/焦点、复制、滚动、PTY 往返 | 先把终端跑通，方向集中；小步回归留下了大量可复用验证 |
| 5–6 月：本地功能与兼容性体系 | P0–P5、shell hook、搜索/选择、图形、性能证据、完成与接线模型 | 能力增长快，但“实现—接线—证据—完成状态”本身也形成维护面；历史阶段不能无限复制 |
| 7 月：协议、录制和运行时边界 | 大量 OSC 子集、raw recording、checkpoint/replay、frame/asset packet、current-only 合同 | 技术资产变厚；此后新增协议的边际用户价值需要单独证明 |
| 7 月 23 日：明确做过范围收敛 | T-331 将 Project Workspace 收敛为 Terminal Layout、最小 Relaunch Spec、独立 Recording Library | 这是有价值的收敛：文件夹用于启动终端，布局用于组织会话，避免演变成 IDE 容器 |
| 7 月下旬至 8 月：远程与多端扩展 | SSH、Go 数据 API、加密同步、iOS、Web 配置台、SFTP | 应用实际承诺超过 7 月范围文档；新增了服务、账户、密钥和平台生命周期问题 |
| 8 月下旬至 9 月：产品打磨 | 中英文、移动输入、快捷键、设置重设计、默认 profile、加载/错误状态；9 月 7 日改名 Trail | 近期提交已经朝“可日常使用”转向，应该继续完成使用闭环，而不是再开多个能力方向 |

可核对的近期提交包括：`a8209dc9`（7/23 回放与文件夹入口）、`b1ce4844`（7/24 回放时间线）、`e9f6807e`（8/14 iOS App Store 工作合入）、`9b63b065`（8/15 主密钥统一）、`2fdf4579`（8/17 SSH Cloud 加密同步）、`578ab1ba`（8/18 SFTP）、`4094b7e2`（8/21 中英文）、`1b0bef8e`（8/26 设置与远程 fallback）、`ce8d2aa7`（9/7 Trail 品牌）。这些是实现历史，不是已经上线、用户采纳或商店审核通过的证明。

## 4. 用户功能逐项评估

表中“高/中/低”分别表示预计用户价值和相对维护成本。下文证据索引 E1–E15 给出源码入口；动作级覆盖另见附录。

### 4.1 启动、连接与会话组织

| 编号 | 功能及当前边界 | 价值 / 成本 | 建议与原因 | 证据 |
|---|---|---|---|---|
| F01 | macOS 本地 shell、启动命令/参数/环境/cwd | 高 / 高 | 核心保留；优先启动、输入延迟、中文输入、TUI 与长输出稳定性 | E1、E5 |
| F02 | macOS 读取 `~/.ssh/config` 连接主机 | 高 / 中 | 保留；复用用户已有配置，避免要求重复录入 | E2 |
| F03 | 手动创建 SSH、一次性连接、保存主机 | 高 / 中高 | 核心保留；把“连接一次”与“保存到本机”直接放在同一流程，解除 API 门槛 | E2、E8 |
| F04 | 密码、公钥、keyboard-interactive/OTP、host-key 提示 | 高 / 高 | 保留；失败时给可操作错误，避免以增加选项代替排障 | E2、E13 |
| F05 | ProxyJump、L/R/D、agent、X11 等高级 SSH 配置 | 特定用户高 / 高 | 已有能力保留，收进高级设置；按真实故障补兼容，不追求 SSH 选项全收录 | E2、E13 |
| F06 | 多标签、切换/重排、关闭、恢复刚关闭标签 | 高 / 中 | 核心保留；恢复表示新建连接/进程，应让用户理解这一点 | E1、E5 |
| F07 | 左右/上下分屏、焦点切换、拖动调尺寸、交换/移动、最大化、关闭/重开 pane | 高 / 高 | 桌面保留；手机降低入口优先级，重连/切换会话优先于复杂分屏编排 | E1、E5 |
| F08 | 在文件夹打开终端、同 cwd 新开 | 高 / 低中 | 保留并归入新建会话；不重新引入 Project Workspace | E1、E5 |
| F09 | Terminal Layout 自动保存/恢复、Relaunch Spec | 高 / 高 | 保留；设备本地保存，重启新会话；不要承诺恢复仍在运行的远端进程 | E5、E8 |
| F10 | 启动加载、空状态、失败恢复、只读、退出确认 | 高 / 中 | 保留并作为发布验收重点；都是避免丢上下文和误操作的基础 | E1、E5 |
| F11 | Launcher / Command Menu 两个动作名 | 高 / 中 | 合并为一个命令面板概念；快捷键和按钮可保留多入口，执行路由只留一份语义 | E1 |

### 4.2 输入、查找与内容处理

| 编号 | 功能及当前边界 | 价值 / 成本 | 建议与原因 | 证据 |
|---|---|---|---|---|
| F12 | 键盘/IME、鼠标、选择复制、粘贴、移动手势与辅助输入 | 高 / 高 | 核心保留；跨焦点、滚动、旋转与输入法问题优先于外观新选项 | E5、E12 |
| F13 | 当前会话/标签/全部会话搜索、文本/正则等搜索模式 | 高 / 中高 | 统一一个搜索面板与作用域；保留能力，减少另一套 Global Search 面板 | E6 |
| F14 | Clear Buffer、输出导出 | 中高 / 低中 | 保留；清空与导出采用会话上下文菜单，不占主工具栏 | E1、E6 |
| F15 | shell integration、cwd/host/user、命令完成信息、前后 prompt 导航 | 高 / 中高 | 保留底层并自动工作；缺少 hook 时正常退化，不强迫用户先学习协议 | E6、E14 |
| F16 | 选择/复制上一条命令输出 | 中高 / 中 | 保留用户价值，合并为“复制命令输出”；独立 select 动作可继续隐藏 | E1、E6 |
| F17 | 命令历史、最近目录 | 中高 / 中 | 合并进命令面板/搜索；不要为这两项重新开放整个 Toolbelt | E6、E7 |
| F18 | Vim 风格 Copy Mode | 特定用户中 / 中 | 正式动作隐藏；冻结独立交互模式，先把键盘选择与系统复制做好 | E1、E7 |
| F19 | 多行/大段粘贴判断、bracketed paste、OSC 剪贴板授权 | 高 / 中高 | 保留安全默认值；高级策略按需展开，不能随入口精简一起删除 | E9、E14 |
| F20 | Advanced Paste 文本变换 | 特定用户中 / 中 | 继续隐藏或收进粘贴菜单；不作为独立产品方向 | E7 |
| F21 | Paste History 与其本地/API 存储 | 中 / 中高 | 默认关闭或明确选择后启用；如保留，统一到输入历史面板；同步不是基础要求 | E7、E8 |
| F22 | 应用层 Autocomplete | 不确定 / 中高 | 当前主要复用命令历史及屏幕文本，不是完整 shell 补全；冻结独立引擎，先避免与 shell 补全冲突 | E6 |
| F23 | Auto Composer | 不确定 / 中 | 已是实验隐藏项；不是已验证的 AI 助手，列为归档候选，移动输入另按实际需求保留 | E1、E6 |
| F24 | 命令完成、bell、活动监控/通知 | 中高 / 中 | 合并为每会话“通知”及全局默认；独立 toggle 动作可隐藏，运行时通知仍保留 | E1、E9 |

### 4.3 文件、回看与录制

| 编号 | 功能及当前边界 | 价值 / 成本 | 建议与原因 | 证据 |
|---|---|---|---|---|
| F25 | SSH 会话内 SFTP 列目录/刷新/路径导航/复制路径 | 高 / 中 | 保留为 SSH 上下文侧栏；不扩展成本地项目文件浏览器 | E3 |
| F26 | SFTP 下载、新建目录、删除 | 高 / 中 | 保留并做好失败/取消反馈；复杂批量文件管理暂缓 | E3 |
| F27 | SFTP “本地编辑”下载后监听保存并上传 | 中高 / 高 | 已有真实回写链；收进高级操作，明确保存/上传/失败状态；不继续发展双向目录同步 | E3 |
| F28 | 任意本地文件上传、重命名等完整文件管理 | 高低取决于用户任务 / 中 | 不能宣称现有完整支持：目前 panel 上传主要用于编辑回写，没有独立通用上传入口，菜单无 rename；若用户频繁上传文件，优先补小闭环而非复杂编辑器 | E3 |
| F29 | ZMODEM 收发、取消/失败恢复 | 特定用户中 / 高 | 保留兼容路径并冻结扩张，默认文件操作统一推荐 SFTP；不能把二者当作可随意互删的同一协议 | E13 |
| F30 | 终端协议内联文件下载/保存 | 特定用户中 / 高 | 作为按需协议能力保留，维持确认与限制；与 SFTP 共用面向用户的传输反馈 | E14 |
| F31 | Instant Replay 最近画面回看 | 潜在高 / 中高 | 保留并优先验证特色价值；它是有界画面/语义缓存，不是完整持久录制 | E4 |
| F32 | 手动开始/停止会话录制、保存/失败重试 | 潜在高 / 高 | 保留；默认输入脱敏，但输出仍可能包含敏感内容；不自动承诺录制文件完全脱敏 | E4、E5 |
| F33 | 打开录制文件、播放/暂停、步进、速度、seek、搜索、复制、视图适配 | 潜在高 / 高 | 已有产品链，合并为一个回放体验；围绕“快速找到发生了什么”取舍控件 | E4 |
| F34 | 录制库搜索/排序/筛选、导入、重命名、导出、删除 | 中 / 高 | 当前库侧栏不可达；先做“最近保存的录制+打开文件”的小列表，再决定是否复活全部管理功能 | E4 |
| F35 | 回放语义事件、checkpoint、图形资产、确定性重放 | 间接高 / 高 | 保留核心实现和回归；属于准确回放的基础，不逐个包装成用户菜单功能 | E4、E14 |

### 4.4 配置、个性化与高级功能

| 编号 | 功能及当前边界 | 价值 / 成本 | 建议与原因 | 证据 |
|---|---|---|---|---|
| F36 | Profile 新建/编辑/删除、默认配置 | 高 / 中 | 保留；“主机”突出连接参数，“终端配置”突出启动与显示，内部仍复用 profile | E2、E10 |
| F37 | SSH config 导入、iTerm 动态 profile 导入 | 前者高、后者不确定 / 中 | SSH 导入保留；动态 profile 是隐藏长尾，保留明确导入入口即可，不继续追求全量互通 | E2、E7 |
| F38 | Profile 标签、匹配规则、自动切换 | 标签中、自动切换特定用户中 / 中高 | 标签与搜索合并；自动切换收进高级，避免新用户不知道设置为何变化 | E10 |
| F39 | Profile 正则触发通知/发送文本、Captured Output | 特定用户中 / 高 | 保留已有配置解释能力，暂停自动化扩张；不要因 Toolbelt 隐藏就认为触发器不运行 | E7、E10 |
| F40 | tmux 辅助面板 | 不确定 / 中高 | 当前可见代码是命令发送与屏幕标记检测，不应宣传成完整原生 tmux control-mode 编排；冻结该面板，保留运行普通 tmux 的兼容性 | E7 |
| F41 | Coprocess | 不确定 / 中高 | 当前 shell 层是输出匹配后自动回写，启动只存状态，不是通用外部子进程管道；归档候选，避免发展第二套自动化系统 | E7 |
| F42 | Annotations、Captured Output 管理、Toolbelt 聚合侧栏 | 不确定 / 中高 | 正式 Toolbelt 入口隐藏；抽出有用的命令历史/复制能力后，侧栏与手动标注面板归档候选；协议标注单独保留 | E1、E7、E14 |
| F43 | 独立 Password Manager | 低至不确定 / 高 | 已隐藏且待重设计；建议停止独立密码产品方向。SSH 凭据保险库是核心，必须保留 | E1、E7、E8 |
| F44 | Hotkey Window / 全局唤起 | 特定桌面用户中 / 中高 | 当前动作隐藏；等待明确用户需求再开放，先保障普通窗口快捷键 | E1、E9 |
| F45 | 浅色/深色/跟随系统、终端配色预设、字体/光标/边距 | 高 / 中 | 保留少量可靠预设与必要调节；独立 Theme Picker/ApplyTheme 动作并入外观设置 | E9、E10 |
| F46 | 完整 ANSI/特殊颜色、渲染细项、布局模板 | 特定用户中 / 高 | 高级项按需展开；冻结模板产品扩张，不删除已有终端颜色语义 | E10、E14 |
| F47 | 自定义快捷键、冲突提示 | 高 / 中 | 保留；只默认展示已开放动作；统一 native 菜单、命令面板和应用按键的结果 | E1、E9 |
| F48 | 中英文、文本缩放、语义标签、键盘焦点、移动适配 | 高 / 高 | 核心质量要求；先完善现有两种语言和目标设备，不并行新增语言/平台 | E9、E12 |
| F49 | 用户诊断导出 | 中高 / 中 | 保留一个“导出诊断”入口；以可帮助排障的内容为准 | E1、E11 |
| F50 | debug completion/wiring/verification 面板与状态模型 | 开发间接价值 / 中高 | 调试可保留；与发布业务对象解耦，逐步将纯证据逻辑放测试/工具，不再持续扩展状态体系 | E7、E11 |

### 4.5 数据、平台与对外能力

| 编号 | 功能及当前边界 | 价值 / 成本 | 建议与原因 | 证据 |
|---|---|---|---|---|
| F51 | 无服务、本地 API、远程 API 三模式 | 用户低、架构有用途 / 高 | 用户默认“保存在本机”，只在需要时开启同步；第一步隐藏技术选择，第二步再判断是否移除本地 sidecar | E8 |
| F52 | 本地 Profile/设置/布局/历史/录制持久化 | 高 / 中高 | 核心保留；目标是断网仍能保存基础数据；布局、录制继续与云主机配置区分 | E8 |
| F53 | 远程账户、配置同步、迁移/冲突、服务不可用恢复 | 特定用户高 / 很高 | 限定为可选同步，先稳定既有流程；明确“配置同步”不会接续运行中的 SSH/PTY | E8、E15 |
| F54 | 主密钥、凭据存储、跨端密钥导入/导出/恢复 | 必需 / 高 | 保留安全边界，缩减用户被迫管理的密钥概念；本机基础使用不应要求先完成跨端密钥流程 | E8、E15 |
| F55 | Go API、SQLite/MySQL、服务部署与备份责任、Web 配置台 | 条件性中 / 很高 | 仅服务现有同步；冻结新数据库/管理功能。Web 是 SSH profile vault 管理，不是网页远程终端 | E15 |
| F56 | macOS 桌面应用 | 高 / 高 | 主交付平台，优先安装、升级、长会话及系统交互；本机可安装不代表完整发布分发闭环 | E12 |
| F57 | iOS/iPadOS SSH、输入/旋转/会话切换 | 中高 / 高 | 保留配套端，优先无 API 保存主机、键盘和前后台；不把桌面高级功能全部搬到手机 | E2、E12 |
| F58 | Linux/Windows/Android 或 Flutter Web 终端产品 | 尚无充分交付证据 / 很高 | 暂不承诺全面支持。代码目录、条件分支、CI 编译不能替代真实目标机用户流程验收 | E12 |
| F59 | Flutter 可嵌入终端 SDK `ianvs_terminal_core` | 条件性高 / 高 | 维持生成、构建与最小示例；有真实外部集成者后再扩大支持，不另维护一套实现 | E11 |
| F60 | 终端兼容、Unicode/TUI、图形与 Host 协议扩展 | 基础高、长尾不确定 / 很高 | 兼容性维护保留；新协议需真实工具复现或明确用户任务，停止以协议数量作为里程碑 | E14 |

后端/安全子功能单列，避免被“三模式”一行掩盖：

| 编号 | 功能及当前边界 | 价值 / 成本 | 建议与原因 | 证据 |
|---|---|---|---|---|
| F61 | 远程注册、登录、两阶段提交/取消、会话退出/撤销 | 同步用户必需 / 高 | 保留已有账户可靠性，延后到用户选择同步之后；暂不扩团队身份体系 | E8、E15 |
| F62 | 资源 CRUD、revision 冲突、删除标记 | 同步基础 / 高 | 保留；不能为了简化界面删除并发/删除一致性合同 | E15 |
| F63 | 本地向远程导出/合并、配置切换事务与失败恢复 | 迁移用户高 / 高 | 保留明确确认与原数据保护；流程只在切换服务时出现 | E8、E15 |
| F64 | macOS 远程不可用时 last-known-good mirror / fallback | 中高 / 高 | 维护当前边界；不把它宣传成 iOS/全平台离线同步；暂不扩多层 fallback | E8 |
| F65 | 普通配置、敏感信封分开，客户端加密与系统钥匙串 | 高 / 高 | 保留；准确说明敏感字段加密，不暗示主机等所有元数据服务端均不可见 | E8、E15 |
| F66 | portable key 导入/导出、替换、旧密钥迁移、Apple 同步及开发环境隔离 | 换设备/恢复用户高 / 高 | 作为恢复/同步高级功能；先验证全新设备、错误密钥和失败回退，再考虑增加更多密钥模式 | E8 |
| F67 | WebUI 登录、查看/编辑/删除 SSH、私钥文件导入、按需解密、退出/忘记密钥 | 条件性中 / 高 | 冻结扩展；如果真实用户只在 App 管理主机，后续归档重复编辑面；现阶段不直接删在用管理渠道 | E15 |

布局始终使用本地 repository；Profile、偏好、terminal config、paste history 在 API 模式有各自 API adapter，录制文件仍本地。不能把远程同步简单写成“只有 SSH”，也不能写成“完整工作区同步”。Theme/template/recent 等边界分别核对，不能从名称推断同步范围。

## 5. 必须分清的能力边界

### 5.1 回看、录制与会话恢复是三件事

- **最近画面回看**：`InstantReplayStore` 默认每会话帧数上限 60、总估算字节预算 16 MiB；生产 provider 设置最短采集间隔 100ms。帧数和采样策略不构成固定时长承诺，不能写成“必定保留最近 N 分钟”。
- **保存录制后回放**：独立 recording 文件及 replay backend，可搜索、seek、播放；默认原始输入做 redact，终端输出仍可能回显密码、token 或业务数据。
- **布局恢复/重开**：按 Relaunch Spec 新建 PTY/SSH，不能恢复已死亡进程，也不等于跨端接管连接。

推荐用户只看到一个“回看”入口，其中清楚区分“本次最近内容”和“已保存录制”；“继续执行原会话”不在这个承诺里。

### 5.2 SFTP 与现有“上传”不要过度宣传

当前 SFTP UI 已有浏览、下载、新建目录、删除和本地编辑自动回写。`uploadFile` 的 panel 调用用于“本地编辑”的保存回传；通用“选择文件上传”与 rename 没有在当前菜单中找到。是否补通用上传应由常见任务决定，但它比继续完善自动编辑重试策略更容易构成用户可理解的收益。

### 5.3 隐藏动作不等于隐藏整个能力

`openThemePicker` 隐藏，设置里仍有主题；通知 toggle 隐藏，通知事件仍可能运行；Annotations 面板隐藏，终端协议仍可触发注释；`globalSearch` 隐藏，统一搜索仍能有跨会话作用域。应逐层记录“入口、行为、协议、持久化”，防止精简时误删基础。

反过来，存在 Widget、callback 或 passing test 也不表示正式用户能到达。录制库的 `shelfOpen: false` 就是明确例子；Toolbelt 的调试菜单入口也不能代替 release 可达性验证。

### 5.4 终端协议按用途维护

| 能力族 | 包含内容 | 建议 |
|---|---|---|
| 日常终端正确性 | VT/SGR、光标、滚动、alternate screen、resize、Unicode/宽字符、键盘与鼠标协议、同步输出 | 持续维护；真实 shell/TUI 失败优先修 |
| 命令上下文 | OSC 7、133、shell metadata、prompt/cwd/exit 信息 | 保留，服务跳转、搜索、复制和回放 |
| 链接与颜色 | OSC 8、palette/dynamic color、title/tab appearance | 保留现有兼容，不单独为每条协议增加设置入口 |
| 图形内容 | Kitty/Sixel/iTerm 图形相关路径、尺寸/缓存/重排 | 保留已有支持边界；补现有工具显示错误，暂缓新协议扩展 |
| 主机副作用 | OSC 剪贴板、URL、通知/attention、文件传输 | 保留授权、速率、尺寸与只读限制，统一少量用户策略 |
| 富内容长尾 | OSC 72、block/render/button、annotation、captured-output 扩展 | 按已实现子集兼容，冻结新增产品包装 |
| 纯元数据与可选查询 | 如 UAPI OSC 3008，及变量/能力查询 | 不计为独立可见功能；无消费者不加 UI；遵守现有 deny/no-op 边界 |

逐协议已有更详细的支持/子集/待验收记录，参见 [OSC support matrix](/Users/robinfai/flutter_projects/ianvs-terminal/docs/protocols/osc_support_matrix.md)。本次没有重跑其中数十条协议的端到端门禁，也不把表中 supported subset 改称全面兼容。

## 6. 精简后的体验与架构

建议主界面围绕：新建本地/SSH、切换标签/分屏、查找、回看。SSH 会话出现“文件”，其他操作放上下文菜单或命令面板。设置当前已有 general/appearance/shortcuts/security/data 五类，可沿用，不再为一次功能增加一个一级设置区。

**先改承诺和流程，再精简实现。**

| 主题 | 当前问题 | 第一阶段调整 | 后续有证据再做 |
|---|---|---|---|
| 本地保存 | 保存自定义 SSH 绑定 API；iOS 需远程 API | 在当前 repository/credential 边界内支持本机保存；数据服务延后到同步入口 | 用技术试验比较直接本地 repository 与隐藏 sidecar 的迁移/维护成本 |
| 同步 | 服务配置、登录、主密钥、迁移混在基础使用路径 | 本地先完成使用闭环，明确同步状态、失败和恢复 | 如改成真正 local-first，同步队列、revision、删除标记、密钥和冲突必须单独设计；不是加一个离线 fallback |
| 回看 | 最近帧、录制、文件打开和库管理分离 | 一个入口；最近保存列表；保留原有 recording 格式与回放 | 有重复使用后再做分类、批量、分享或更复杂管理 |
| 搜索与历史 | 普通搜索、全局搜索、Toolbelt 历史多套入口 | 一个搜索面板；历史命令/目录通过命令面板查找 | 保留高级筛选的条件是用户确实需要 |
| 自动化 | profile triggers、coprocess、autocomplete、composer 等各自扩张 | 冻结新能力；抽出仍需的通知/命令输出行为 | 有真实用户场景后至多选择一条自动化路径 |
| SDK | app 与对外 package 各有验证责任 | canonical source + 自动生成 + parity 门禁不变 | 外部采用明确后再承诺更广 ABI/平台支持 |
| 文档与测试 | 历史任务与当前范围混杂，元状态模型众多 | 一个现状表、一个当前路线图、一个已知问题入口；旧任务保留历史标记 | 只合并重复证据/结构测试，保住真实 PTY、数据恢复和协议边界回归 |

不建议此时全面重写成原生 UI、更换终端内核、删除 Go 后端或手工合并 SDK 镜像。它们都可能让已验证边界失效，成本需要专项证据。本轮更合理的是先减少未来承诺与用户步骤，再逐个清理共享状态和重复路由。

## 7. 方向选择与外部参照

| 可选主方向 | 对现有资产的利用 | 主要新增负担 | 结论 |
|---|---|---|---|
| 通用高性能桌面终端 | 本地 core、tab/split、兼容性利用率高 | 需要持续竞争启动/渲染/系统体验，难靠更多设置拉开差异 | 可作为基础，不宜把“功能比别人多”当定位 |
| 个人远程工作与可回看终端 | SSH/SFTP、录制、macOS/iOS 都能围绕同一用户任务 | 需解决保存/连接门槛，验证回看价值 | **推荐主线：macOS 优先，iOS 配套；先小范围验证** |
| 团队云 SSH 平台 | API、加密、WebUI 有基础 | 账户运营、共享授权、服务可靠性、支持与信任成本明显增加 | 暂缓，已有远程能力维护即可 |
| Flutter 终端 SDK 产品 | 已有 standalone 分发、构建 hook 与测试 | 外部 API 生命周期、平台工具链和集成支持 | 条件性副线；如实际需求以 SDK 为主，应独立重排优先级 |

外部资料只用于校准用户已有选择，不作性能或市场份额结论：Ghostty 明确强调终端速度、原生交互与丰富功能；Termius 将本地 vault、SSH/SFTP 和移动/桌面同步分别放在产品能力中；Blink 的快速开始围绕 SSH/Mosh 连接。由此推断，Trail 单靠“也支持 SSH/分屏/主题”很难说明迁移理由，低门槛加上实用回看值得先验证。[Ghostty 官方介绍](https://ghostty.org/docs/about)、[Termius 官方方案](https://www.termius.com/pricing)、[Blink 官方指南](https://docs.blink.sh/)（检索日期：2026-09-07）。

不建议现在加入内置大模型账户、自然语言执行和 Agent 编排来寻求差异化。兼容用户已经在 shell 里运行的工具即可；当前 Auto Composer 的存在不能当作已经具备 AI 产品基础。

## 8. 接下来 6–8 周的工作顺序

按个人或小团队可投入精力设计；时间是规划窗口，不是工程工期承诺。资源不足时按顺序往后推，不同时开四条线。

| 顺序 | 工作包 | 可验收结果 |
|---|---|---|
| 第 1 周：事实与发布面 | 对齐 Trail 品牌、产品范围、平台矩阵；建立 release 入口清单；明确默认后端政策 | 一个文档能回答“正式用户今天能做什么”；逐项区分历史、隐藏、底层、正式支持 |
| 第 1–3 周：降低基础门槛 | macOS/iOS 无 API 创建并保存 SSH；凭据仍走系统保险库；新建与重连错误可恢复 | 全新安装、不配 API：连接→保存→重启→再次连接；离线仍能管理基础配置；连接真实主机时再要求网络 |
| 第 3–4 周：回看最小闭环 | 统一回看入口，接通最近保存列表；明确最近缓存与录制文件差别 | 用户完成“录制→停止→退出/重开应用→找到录制→定位一条输出”；不必手工找应用目录 |
| 第 4–5 周：隐藏功能清理 | 优先 Auto Composer、独立 Password Manager、Coprocess、Toolbelt 聚合壳；搜索/设置动作别名合并 | 删除候选各有调用/数据/协议影响说明；一次一项，保留存量数据；核心路径回归通过 |
| 第 5–6 周：实际使用验证 | 邀请 5–10 位符合定位的用户，以自己的任务使用；记录连接与回看障碍 | 能说明用户为何留下、哪里失败、哪些高级功能确实需要，而不只收集“希望增加什么” |
| 第 7–8 周：按证据选择一项扩展 | 基础 SFTP 上传、iOS 体验、同步稳定性、SDK 集成支持四选一 | 每项有用户任务、验收与停止条件；其余保持维护 |

建议近期投入比例：约 50% 主路径稳定性与保存/恢复、25% 回看闭环、15% 目标平台发布质量、10% 文档和存量清理。比例只是约束并行扩张的办法，不是测得的最佳分配。

## 9. 用什么证据决定继续或停止

不要把“又支持一个协议”“关闭更多任务”“测试文件更多”当作主要产品进度。

| 问题 | 建议采集方式 | 继续/停止条件 |
|---|---|---|
| 新用户能否独立开始？ | 观察 clean install→首次成功 shell/SSH 的步骤和失败点 | 先消除必须理解 API/密钥部署才能保存主机的阻碍；不要在此之前扩功能 |
| 用户是否愿意持续使用？ | 小规模自愿试用日志、每周访谈，不上传原始终端内容 | 用户能举出真实重复任务，才说明定位初步有效；小样本不当作统计结论 |
| 回看是否成为迁移动机？ | 给出“找回某命令输出”的任务，观察是否比原工作方法有效 | 至少出现多位用户在无人提示时重复使用；如果长期不用，停止媒体库扩张，保留轻量回看 |
| SFTP 哪个动作最缺？ | 观察下载日志、上传配置、编辑远程文件三类任务 | 通用上传需求优先于更复杂自动回写；没有需求就不补成完整文件管理器 |
| 同步值不值得运营？ | 记录主动提出跨设备需求及使用频率、恢复工单 | 无明显多设备需求时，维持可选自建能力，暂缓团队云产品 |
| SDK 值不值得投入？ | 外部应用的真实集成、版本升级与问题记录 | 建议以至少两个独立集成场景作为扩张条件；没有采用证据则维护生成/构建，不扩产品承诺 |
| 性能是否退化？ | 使用现有 benchmark，在固定 host/config 比较输入、滚动、resize、CPU/RSS | 新功能造成可重复回归就先修复/撤回；本次没有新基线，不能承诺任意毫秒目标 |

可以用本地诊断与明确自愿的反馈完成早期验证，无需为了验证产品价值先搭新的遥测后台。即使以后增加计数，也不应默认收集命令、主机、终端输出或凭据。

## 10. 文档与实际产品的主要冲突

| 现有说法 | 当前源码/仓库证据 | 应如何更新 |
|---|---|---|
| Product Scope / Current Target 将 cloud sync 排除 | README、远程配置仓库、加密和跨端同步实现已经存在 | 重新决定“可选配置同步”的当前地位，区分已实现与未来团队云 |
| Known Issues 只支持 macOS | iOS SSH launch policy、iOS 工程和发布准备已存在 | 分开“已实现平台、已验收平台、已上架平台”，本次无法证明商店上架 |
| Known Issues 写 JSON frame diff | 架构文档已有 Protobuf Frame/Graphic Asset Packet current 边界 | 更新运行时事实；旧路线图中 dual-stack/迁移描述归入历史 |
| Product Scope 把 layout 列入 API 目标持久化 | 当前 composition 始终创建本地 layout repository | 明确布局是设备本地，云同步不迁移屏幕拓扑 |
| App Store 文案称没有默认开发者服务器 | 配置文件含默认远程域名及 fallback，具体是否运营不能仅从常量判断 | 核实远程模式默认值、用户主动选择和实际运营方，再对齐文案与隐私声明；不是说应用未经选择就上传 |
| 文档描述 Recording Library | 当前 shell 将 shelfOpen 固定为 false | 当前能力写成录制/文件回放，库管理标为未开放，直到恢复真实入口 |
| Trail 改名已提交 | README、iOS listing/checklist 等仍出现 Ianvs 与旧标识 | 区分必须兼容的包名/存储标识与面向用户的品牌，不做盲目全局替换 |

## 11. 关键源码与验证资产索引

- **E1 动作/正式入口**：[动作注册与枚举](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_action_registry.dart:4)、[39 项白名单](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_action_registry.dart:772)、[命令菜单过滤](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_command_menu.dart:107)、[实际派发](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_state_command_actions.dart:205)。
- **E2 SSH/Profile**：[新连接流程](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/ssh/new_session_launcher.dart)、[API 保存门槛](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/ssh/ssh_feature_access.dart:5)、[SSH 导入服务](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/ssh/ssh_profile_import_service.dart)、[入口测试](/Users/robinfai/flutter_projects/ianvs-terminal/example/test/ssh/new_session_launcher_test.dart)。
- **E3 SFTP**：[目录/文件接口](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/sftp/sftp_side_panel.dart:31)、[下载与本地编辑](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/sftp/sftp_side_panel.dart:481)、[上下文菜单](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/sftp/sftp_side_panel.dart:549)、[编辑保存回传](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/sftp/sftp_file_actions.dart:329)、[文件动作测试](/Users/robinfai/flutter_projects/ianvs-terminal/example/test/sftp/sftp_file_actions_test.dart)。
- **E4 回看/录制**：[有界最近帧缓存](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/instant_replay_store.dart:94)、[生产采样配置](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_models.dart:322)、[库入口关闭](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen.dart:1406)、[文件打开路径](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_state_recording_library.dart:4)、[回放实现](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_recording_library.dart:782)、[录制仓库测试](/Users/robinfai/flutter_projects/ianvs-terminal/example/test/recording/local_session_recording_repository_test.dart)。
- **E5 会话/布局**：[SessionController](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/sessions/session_controller.dart)、[录制默认输入脱敏](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/sessions/session_controller.dart:1666)、[布局状态行为](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_state_terminal_layout.dart)、[Relaunch Spec](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/layout/local_terminal_relaunch_spec.dart)。
- **E6 搜索/上下文**：[搜索作用域](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_state_search_completion.dart:121)、[补全来源](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_state_search_completion.dart:510)、[Composer](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_state_search_completion.dart:767)、[shell productivity 模型](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/productivity/shell_productivity_models.dart)。
- **E7 隐藏/高级功能**：[Toolbelt](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_toolbelt.dart:3)、[tmux 辅助路径](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_state_integrations.dart:65)、[Coprocess 和触发器](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_state_coprocesses.dart:4)、[密码面板路径](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_state_integrations.dart:255)。
- **E8 数据/密钥**：[持久化组合根](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/persistence_repository_composition.dart:30)、[模式与默认域名](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/data/configuration/data_api_configuration.dart:3)、[配置与切换事务](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/data/configuration/data_api_configuration_repository.dart)、[portable master key](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/data/services/portable_master_key.dart)、[恢复测试](/Users/robinfai/flutter_projects/ianvs-terminal/example/test/data/services/data_api_startup_recovery_test.dart)。
- **E9 设置/权限**：[五类设置](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/defaults_appearance_dialog.dart:56)、[偏好模型](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/preferences/app_preferences_models.dart)、[粘贴/通知策略](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/policies/local_terminal_policy_models.dart)、[快捷键编辑](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/config/shortcut_editor.dart)。
- **E10 Profile 高级项**：[编辑器类别](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/profiles/profile_editor.dart:280)、[触发器/自动切换模型](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/profiles/profile_models.dart:52)、[外观模型](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/visual/local_terminal_visual_models.dart)。
- **E11 架构/SDK/开发支持**：[架构分层](/Users/robinfai/flutter_projects/ianvs-terminal/docs/ARCHITECTURE.md:5)、[SDK README](/Users/robinfai/flutter_projects/ianvs-terminal/packages/ianvs_terminal_core/README.md)、[生成工具](/Users/robinfai/flutter_projects/ianvs-terminal/tools/sync_terminal_core.dart:6)、[用户诊断导出](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/visual/local_terminal_diagnostics_exporter.dart)。
- **E12 平台与发布**：[启动策略](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/sessions/terminal_session_launch_policy.dart)、[移动输入](/Users/robinfai/flutter_projects/ianvs-terminal/example/lib/features/shell/shell_screen_mobile_input.dart)、[iOS 发布清单](/Users/robinfai/flutter_projects/ianvs-terminal/docs/app-store/IOS_RELEASE_CHECKLIST.md)、[macOS 构建/安装入口](/Users/robinfai/flutter_projects/ianvs-terminal/Makefile:156)。
- **E13 真实连接与传输验证资产**：[SSH e2e](/Users/robinfai/flutter_projects/ianvs-terminal/tools/ssh_e2e/README.md)、[ZMODEM 协议/边界](/Users/robinfai/flutter_projects/ianvs-terminal/docs/protocols/ZMODEM_V1.md)、[已知兼容性边界](/Users/robinfai/flutter_projects/ianvs-terminal/docs/KNOWN_ISSUES.md)。
- **E14 终端/协议/回放基础**：[逐 OSC 支持矩阵](/Users/robinfai/flutter_projects/ianvs-terminal/docs/protocols/osc_support_matrix.md)、[兼容性矩阵](/Users/robinfai/flutter_projects/ianvs-terminal/docs/compatibility/CAPABILITY_MATRIX.md)、[录制格式](/Users/robinfai/flutter_projects/ianvs-terminal/docs/recording/FORMAT_CURRENT.md)、[Runtime wire inventory](/Users/robinfai/flutter_projects/ianvs-terminal/docs/protocols/RUNTIME_WIRE_INVENTORY.md)。
- **E15 后端与 Web**：[后端说明](/Users/robinfai/flutter_projects/ianvs-terminal/backend/README.md)、[Web 源码](/Users/robinfai/flutter_projects/ianvs-terminal/backend/webui/src)、[敏感数据加密 ADR](/Users/robinfai/flutter_projects/ianvs-terminal/docs/DECISIONS/ADR-0004-client-side-sensitive-encryption.md)。

## 12. 本次验证结果与后续验证重点

数据子代理本次执行并回传的结果：

- 在 `backend` 执行 `GOCACHE=/tmp/ianvs-go-cache go test ./...`：exit 0，有测试的包均通过。
- 在 `backend/webui` 执行 `npm run test:unit`：exit 0，6/6 通过；`npm run typecheck`：exit 0。
- Flutter 定向测试未启动：工具尝试写入工作区外的 Flutter SDK cache，被当前文件系统沙箱拒绝。SDK sync check 也遇到相同环境限制。这些结果既不能证明 Flutter 测试失败，也不能证明其通过。
- 主代理核对了 62 个动作与 39 项 release 白名单、录制库关闭路径、SFTP 文件调用、数据 repository 选择和主要引用位置。本次没有新运行的 release UI、真实 SSH/SFTP、iOS 前后台、性能或全仓验证证据。

未来实施精简时，最值得保留的验证是：真实 PTY 输入/输出与 resize、常用 TUI/IME、SSH 认证与 host key、配置/凭据恢复、录制停止与再次打开、SFTP 传输失败、release 实际入口可达。仅证明某 callback 已注册或某 evidence model 状态正确，不能替代这些用户路径。

## 附录：62 个动作的逐项处置

与源码枚举逐项对应，已脚本核对无遗漏。白名单共 39 项，隐藏 23 项；白名单表示 registry 允许作为产品入口，不表示每个平台、每种会话状态都可执行，也不表示一定显示在命令面板。隐藏动作仍可能有 debug 入口、运行时消费、设置中的等价能力或历史配置依赖。

| Action ID | 功能 | 当前入口分类 | 处置建议 | 功能编号 |
|---|---|---|---|---|
| `openLauncher` | 命令面板入口 | 白名单 | 合并到统一 command menu；保留默认快捷键 | F11 |
| `openCommandMenu` | 命令菜单入口 | 白名单 | 与 openLauncher 共用同一语义和执行入口 | F11 |
| `newTab` | 新建本地/默认会话 | 白名单 | 保留；尊重默认 profile 和平台能力 | F01/F06 |
| `newSshSession` | 新建 SSH | 白名单 | 保留直接按钮/快捷键；descriptor 在命令面板隐藏不等于没有入口 | F03 |
| `openTerminalAtFolder` | 在文件夹打开终端 | 白名单 | 保留，放新建菜单 | F08 |
| `openRecording` | 打开录制文件 | 白名单 | 保留，纳入统一回看入口 | F33 |
| `duplicateCurrentCwd` | 同目录新开终端 | 白名单 | 保留，纳入新建菜单 | F08 |
| `reopenClosedTab` | 重新打开关闭的标签 | 白名单 | 保留，明确是重新启动会话 | F06 |
| `toolbelt` | 工具侧栏 | 隐藏 | 冻结聚合壳；抽取命令/目录历史价值 | F17/F42 |
| `openSftpPanel` | SSH 文件侧栏 | 白名单 | 保留，按会话能力出现 | F25 |
| `splitRight` | 向右分屏 | 白名单 | 桌面保留 | F07 |
| `splitDown` | 向下分屏 | 白名单 | 桌面保留 | F07 |
| `focusNextPane` | 下一个 pane | 白名单 | 保留快捷键 | F07 |
| `focusPreviousPane` | 上一个 pane | 白名单 | 保留快捷键 | F07 |
| `resizePane` | 调整 pane 尺寸 | 白名单 | 保留直接拖动/必要快捷键 | F07 |
| `swapPane` | 交换 pane | 白名单 | 保留上下文操作 | F07 |
| `zoomPane` | 最大化/还原 pane | 白名单 | 保留 | F07 |
| `closePane` | 关闭 pane | 白名单 | 保留，复用生命周期处理 | F07 |
| `reopenClosedPane` | 重开 pane | 白名单 | 保留，明确新进程/连接 | F07 |
| `closeActiveTab` | 关闭当前标签 | 白名单 | 保留 | F06 |
| `openDefaults` | 打开设置 | 白名单 | 与 defaults 合并语义 | F45/F47 |
| `activateTab` | 激活标签 | 白名单 | 保留 | F06 |
| `copy` | 复制选择 | 白名单 | 保留 | F12 |
| `copyMode` | 键盘复制模式 | 隐藏 | 冻结独立模式；保留普通键盘选择能力 | F18 |
| `copyCommandOutput` | 复制命令输出 | 白名单 | 保留 | F16 |
| `paste` | 粘贴 | 白名单 | 保留现有安全策略 | F12/F19 |
| `advancedPaste` | 高级粘贴 | 隐藏 | 继续隐藏或收进粘贴上下文 | F20 |
| `pasteHistory` | 粘贴历史 | 隐藏 | 按需启用，合并历史入口 | F21 |
| `toggleReadOnly` | 只读会话 | 白名单 | 保留 | F10 |
| `toggleSessionRecording` | 开始/停止录制 | 白名单 | 保留，纳入回看入口 | F32 |
| `clearBuffer` | 清空缓冲 | 白名单 | 保留上下文动作 | F14 |
| `shellIntegrationUtilities` | Shell 集成工具 | 隐藏 | 底层自动工作，低频安装/排障放高级 | F15 |
| `selectCommandOutput` | 选择命令输出 | 隐藏 | 合并到复制命令输出相关操作 | F16 |
| `openRecentDirectory` | 最近目录 | 隐藏 | 并入命令面板 | F17 |
| `tmuxIntegration` | tmux 辅助面板 | 隐藏 | 冻结，保留普通 tmux 兼容 | F40 |
| `coprocess` | 输出匹配自动回写 | 隐藏 | 归档候选 | F41 |
| `annotations` | 标注管理面板 | 隐藏 | 面板冻结；终端协议能力独立维护 | F42 |
| `capturedOutput` | 捕获输出面板 | 隐藏 | 将有价值的输出查找并入历史/搜索 | F39/F42 |
| `passwordManager` | 独立密码管理器 | 隐藏 | 停止独立产品方向，保留 SSH 凭据管理 | F43 |
| `instantReplay` | 最近画面回看 | 白名单 | 保留，验证重复使用价值 | F31 |
| `search` | 当前/作用域搜索 | 白名单 | 保留统一面板 | F13 |
| `nextSearchMatch` | 下一匹配项 | 白名单 | 保留搜索面板内操作 | F13 |
| `previousSearchMatch` | 上一匹配项 | 白名单 | 保留搜索面板内操作 | F13 |
| `clearSearch` | 清空搜索 | 白名单 | 保留搜索面板内操作 | F13 |
| `globalSearch` | 另一全局搜索入口 | 隐藏 | 合并到 search 的全部会话作用域 | F13 |
| `autocomplete` | 应用层补全 | 隐藏 | 冻结独立引擎 | F22 |
| `autoComposer` | 命令编辑/建议 | 隐藏 | 归档候选，不以 AI 功能宣传 | F23 |
| `hotkeyWindow` | 全局热键窗口 | 隐藏 | 维持隐藏，待真实需求 | F44 |
| `defaults` | 默认设置入口 | 白名单 | 与 openDefaults 合并语义 | F45/F47 |
| `profiles` | Profile 管理 | 白名单 | 保留；主机与终端配置按任务呈现 | F36 |
| `dynamicProfiles` | 动态 Profile 导入 | 隐藏 | 保留兼容资产，入口继续高级/隐藏 | F37 |
| `requestQuitConfirmation` | 退出确认 | 白名单 | 保留 | F10 |
| `previousPrompt` | 前一个 prompt | 白名单 | 保留，缺 hook 时合理禁用 | F15 |
| `nextPrompt` | 后一个 prompt | 白名单 | 保留，缺 hook 时合理禁用 | F15 |
| `toggleCommandFinishedNotify` | 命令完成通知切换 | 隐藏 | 并入会话通知设置；事件处理保留 | F24 |
| `toggleBellNotify` | Bell 通知切换 | 隐藏 | 并入会话通知设置；事件处理保留 | F24 |
| `toggleActivityMonitor` | 活动监控切换 | 隐藏 | 并入会话通知设置；事件处理保留 | F24 |
| `exportScrollback` | 导出终端输出 | 白名单 | 保留 | F14 |
| `exportDiagnostics` | 导出诊断 | 白名单 | 保留唯一排障入口 | F49 |
| `openThemePicker` | 独立主题选择器 | 隐藏 | 合并到外观设置 | F45 |
| `applyTheme` | 应用主题动作 | 隐藏 | 保留底层应用，合并用户入口 | F45 |
| `applyLayoutTemplate` | 应用布局模板 | 隐藏 | 冻结模板扩张 | F46 |

行动层面的目标不是把 62 个动作硬砍成某个漂亮数字。必要的焦点、搜索导航和关闭操作应该存在；真正要减少的是重复产品概念、无正式入口却持续扩张的功能、基础操作所需的服务依赖，以及没有用户证据支持的长期承诺。
