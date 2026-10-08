# 问题登记

核对日期：2026-10-08。实现 C：`fe1556fc99af6ecca45caf7780604c9f8e541bd9`。以下区分确定缺陷的修复回归与 PRD 场景验收；完整 make verify 已通过，同 C 正式 After 的 42 widget 捕获及原生 App 烟测 passed，49 张原图及视频已按限定方法审阅，公开原字节已归档，manifest 结构／完整性校验通过。物理 profile 成品严格预检通过但尚未安装；48 个完整 PRD 用例仍为 not_run，另保留 open P3 PRD-019。本提交 E 仅含文档与证据。

| ID | 级别 | 需求 | 现象与证据 | 当前状态 |
|---|---|---|---|---|
| PRD-001 | P0 | S1-R03 | readContext 等待期间来源变化污染已点发送的请求，新稿被旧完成清空；确定性基线回归失败 | 已实现修复，16 项发送快照回归通过；App 验收待执行 |
| PRD-002 | P0 | S1-R02 / S2-R02 | 删除最后来源后同一草稿由 AI 回到 Command；确定性基线回归失败 | 已保留 AI 意图，控制器/界面回归通过；App 验收待执行 |
| PRD-003 | P1 | S1-R07 / S2-R11 | 基线检查终端总会暂停接管，无独立只读观察和同任务双栏 | 已实现只读 sink、输入代际撤销及双栏；回归通过，App 验收待执行 |
| PRD-004 | P1 | S2-R03–R05 | 基线手机 AI 单行、soft Return 发送、缺本地全屏草稿编辑 | 已实现并通过 Composer/Workspace 回归；真实 IME 待验收 |
| PRD-005 | P1 | S4-R14 | 仅改 Bundle ID 的原脚本仍共享生产 Keychain 组 | 独立工具与签名身份校验已完成；构建工具 29 项回归通过，最终 C 物理 profile 成品严格预检及 Keychain 隔离校验通过；尚未安装 |
| PRD-006 | P2 | S1-R01 / S3-R02 | 基线失败块诊断隐藏于菜单，unknown exitCode 显示成功勾 | 已实现直接入口和 unknown 图标；组件回归通过，App 验收待执行 |
| PRD-007 | P2 | S3-R07 | 基线手机固定字号仅在 preview，真实 App 未施加策略 | 已接入 App，策略回归通过；真实设备验收待执行 |
| PRD-008 | P1 | S1-R12 | 基线手机设置列出不可运行的本地 ACP | 手机仅显示 API，8 项设置回归通过；App 验收待执行 |
| PRD-009 | P1 | S4-R13 | 文档 gate 与既有归档、PRD 指定证据目录冲突 | 已修复明确目录例外及 fenced 示例边界，20 项文档检查通过 |
| PRD-010 | 验收前提 | S4 | 独立物理 profile 正常 App 构建及严格预检通过，但精确有线目标 iPhone 未唯一可用；installed=false、launched=false，待 USB 恢复。真实 API 由用户填写，iPad、iOS 17 及 IME/VoiceOver/性能证据仍缺 | not_run；不视为已安装或设备验收通过 |
| PRD-011 | P1 | S2-R12 / S4-R13 | 真实 macOS gate 发现：阅读旧块后人工提交命令，lazy timeline 未揭示对应运行块，焦点落到 ModalScope，Ctrl+C 无法抵达运行终端 | 已按原生收据单次定位，保留编辑焦点及显式导航语义；6 项应用、32 项 canonical 回归及真实 macOS Composer gate 通过 |
| PRD-012 | P1 | S2-R12 / S4-R13 | zsh 向私有 Composer socket 同步发布 history/inventory；GUI 不查询 Composer 时 socket 未被持续读取，普通键盘命令停滞。无 UI 查询的真实 PTY 回归先失败 | 既有 session 50ms 循环持续排空非阻塞 socket，不新增线程或 PTY 提交/唤醒；zsh 7、Composer 8、bridge 5、session 526 项及最终 C 完整 verify 通过；设备验收 pending |
| PRD-013 | P2 | S2-R12 / S4-R13 | split 原 pane 关闭后，tab 保留原稳定 ID；UI 误按活 pane 查找 tab，剩余 pane 无法经 tab 关闭按钮关闭 | 按 tab.sessionId 解析目标，继续保留关闭/引用保护；2 项关闭回归通过，确认剩余原生会话释放且无写入；设备验收 pending |
| PRD-014 | P2 | S2-R06 / S2-R08 | Reader 在短窗口、键盘和 SafeArea 条件下，控制区将输出挤到 43px；错误提示增长时 retained 输出不可见。3 项布局回归实际失败 | 控制区独立受限滚动并给输出保留空间；错误说明与输出均可达。应用布局/observer 64 项、canonical Reader 63 项组合回归通过；真实键盘验收 pending |
| PRD-015 | P2 | S2-R03 / S2-R06 | 手机横屏键盘场景中，外层 SingleChildScrollView 移除 Composer 的高度边界，使内部短布局无法正确适配 | 去除外层无界滚动，由 Composer 使用实际可用高度；横屏深浅色输入场景包含于通过的 64 项应用回归；真实旋转/IME pending |
| PRD-016 | P2 | S1-R07 / S2-R11 | 从 AI 显式进入只读 observer 后未取得硬件键盘焦点，Esc 清选区/返回任务链路失效；3 个场景回归实际失败 | 仅显式 observer 导航请求焦点，被动宽屏投影不抢 AI 草稿焦点；3 项定向及 64 项组合回归通过，验证任务/草稿保持、未接管前零 PTY 写入；真实外接键盘 pending |
| PRD-017 | P2 | S1-R12 / S4-R13 | ACP 安装发现器默认读取完整 Platform.environment，被既有 Data API 环境架构门槛拒绝 | 改为专用环境模块与显式不可变快照，保留 FNM/NVM/VOLTA/ASDF/npm prefix 发现覆盖，child env 仍为原六项；精确函数/键边界回归和 ACP 组合 63 项通过，lint 清理后 22 项复核通过 |
| PRD-018 | P1 | S4-R13 / S4-R15 | 真实 macOS Debug 增量构建更新内层 App.framework 后，外层 App CodeSign 被跳过，CodeResources 仍封存旧 CDHash，导致成品签名校验失败 | Xcode project 声明 App、FlutterMacOS、ianvs_core、objective_c 四个 framework 及 Resources/ianvs-api 输出，使外层签名依赖跟随变化；无手动补签。永久 gate 增加重复 Debug；最终 clean C 完整 verify 已通过两次 Debug／两次 Release 严格签名及原生 Xcode tests |
| PRD-019 | P3 | 英文来源计数文案 | 单来源英文复数文案：12 张英文 AI widget After 原图中，单一附件显示 `1 sources`，预期为 `1 source`；独立 reviewer 与主节点确认 | open，core_flow=false；保留冻结 C 与原图，未修复，不阻止保留本轮部分验收证据 |

以上“回归通过”只描述实际执行的控制器、组件和工具测试；48 项 PRD 验收仍按各自要求单独取证。

正式 After combined receipt（15:17:25–15:19:04 UTC）记录 42 widget 与 7 个原生 App 检查点、诊断准备零额外请求/执行、明确审批后一次原生修复成功。S1-T01/02/03/05 可复用其中真实子步骤作为 partial 记录，其余完整路径、命令逐字段审阅、unknown/重复审批及设备行为没有因此补齐；不按用例记 passed，也不填 shot_ids。公开索引只作整理 metadata，不是原始 receipt。

待核对观察：原后台输出 fixture 的 `sleep 0.4` 不能保证输出发生于原生 ready 之后；在一次采样中该输出已与首个 ready 快照合并。当前证据不足以判断它位于上一 Block 输出还是 prompt 准备区，未定性为已确认产品缺陷。最终 idle-output gate 使用真实新 lease、已完成 Block 和 release 文件屏障，检查独立输出行及 `unattributedOutput` 普通终端回退，不将本次通过扩大为全部归属时序已验证。


本轮冻结前的 265 文件诊断首轮不是全绿：2747 通过、1 跳过、20 失败，后续相关范围分别修复并复跑。9 项 Composer golden 在核对实际渲染结果后更新并复验通过，只属于组件基线；不等同于完整 App/设备 After。旧 C `649c7769` 的后续完整 verify 已通过 Rust/Go/Flutter 前置门槛，example 全量 2776 通过、1 跳过；整体 exit 2，失败点为 macOS smoke 旧断言未声明实际存在的 hasTapAction。断言对齐后 smoke 4、真实 PTY 45、Composer 1、Keychain 1 项通过；这是测试合同修正，不新增产品缺陷编号。最终 C 完整 verify 已 exit 0（2026-10-08 15:00:37–15:13:48 UTC，源始终 clean，macOS 未跳过）。完整原日志保持私有，SHA-256 为 `85a3a13c11c8e9a8f077255b2a19587d77606ac75b8579446ab852c11e6d4d2d`；结果摘要不能充当公开完整 gate log。当前没有把缺失硬件或未采集证据标为已通过，也未将未定性的后台输出时序观察升级为确定缺陷。

Before B6 原始视频的审阅另记录证据限制：容器 95.461667 秒、393 解码帧，主业务 checkpoint PTS 19.302–29.967 秒；尾部 DTS/PTS 不一致，不把标称时长当连续播放保证。审阅方法为全部画面的缩略图顺序检查与 9 个关键帧放大，原 MP4 未更改，未在播放器连续播放全部内容；这项证据限制不记为产品缺陷。

Before B4 的 42 份 widget sidecar 缺 captured_at，只作辅助比较，未补造时间，未进入 C 的主 manifest。After 原生 7 张 PNG 已人工查看，长终端输出有水平视口截断，单图不能证明完整输出可读。After 的 12 张中英文 widget 图中，草稿 `🧭` 均显示缺字框，经 reviewer 交叉确认，登记为测试字体／特殊字符证据缺口；原图和 C 均保持不变，不能宣称真实 App emoji 验证成功。上述属于证据适用范围，不新增未经运行证明的产品缺陷。

After 视频审阅为全部 393 帧缩略图和 9 个放大关键帧；15.053333 秒、PTS 0–15.04 秒无倒退，七个 checkpoint 对应，未见 Before 尾部异常。原视频未改，不是连续播放器观看或每帧全尺寸审阅。4.218–4.842 秒 SSH 启动可见 `dquote cmdsubst>`，Before 同样存在；仅记为可见但未定因的旧现象，不宣称启动无杂讯，也不凭录屏新增产品回归编号。
