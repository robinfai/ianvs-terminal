# C3 当前交付结论与验收边界

核对日期：2026-10-10。整体状态为 **`implemented_unverified`**。当前实现候选为 `7e9f0dd8e7bd825c655ceb80d817d5fe214337bd`（C3），本轮起点为 `79db5115d1e6c69ac62116f19fdfb2b102724df5`。已确认的实现修复和自动验证已收拢；完整产品场景、真实模型完整流程及部分设备／原生交互仍未验收，不能宣称 D1–D4 或所有平台通过。

## 已修复并纳入 C3 自动验证

| 范围 | 当前行为与回归 |
|---|---|
| 审阅、补充要求与执行身份 | 未知时保留未发送要求，检查回执不发送；人工编辑保留旧版本，保存不执行；API重复操作ID返回原回执，冲突拒绝；旧目标／版本／授权不得写入 |
| 观察与输入归属 | 收起／Esc进入只读观察；Reader／AI打开同步撤销人工Composer权限；旧Run／异步粘贴失效；关闭后依据当前owner恢复；ready、运行Block、路由、窗口和晚到回调不抢其他任务焦点 |
| Block与检查器 | H/3短摘要保留真实状态与退出码；搜索显示单块200／总1000限制；Reader按当前pane打开，可显式并排；边界新手势、长手势及DPR替换维持单一滚动归属 |
| 桌面壳与关闭 | 单层顶栏与原生拖动区域；顶部／溢出／侧栏／折叠组显示待审入口，仅定位原pane；关闭风险确认、取消保留、录制等待后的身份重核对；部分关闭只清理实际关闭pane |
| 状态、主题与移动共享路径 | 底栏同时保留未知回执和当前核对／断连事实；主题目标色对与指定macOS27基线通过；移动隐藏controller生命周期由Shell owner统一分发，手机固定字号合同保留 |

逐项源码和回归入口见 [DESKTOP_COMPARISON](DESKTOP_COMPARISON.md)、[CROSS_PLATFORM_REVIEW](CROSS_PLATFORM_REVIEW.md)。历史红测、修复与定向验证过程见 [ITERATION_1](ITERATION_1.md)，历史局部结果不能冒充新候选的完整验收。

## 当前证据及其适用范围

| 运行 | 已核对结果 | 证据边界 |
|---|---|---|
| `verify-7` | C3完整`make verify` exit 0；首尾源码干净；应用2,965通过、1跳过；macOS原生冒烟4、真实PTY45、Composer1、Keychain1通过；Debug／Release构建与签名检查、Xcode测试通过 | 证明现有自动gate在记录环境通过，不代表64个完整产品场景或真实模型／物理输入全通过 |
| `ssh-c3-native-1` | C3首尾源码干净、exit 0；真实回环OpenSSH六组zsh/bash × emacs/vi及各自local→SSH全部PASS，含受控多跳与返回父Shell恢复 | 已覆盖上述production native session API子集，无GUI；完整App的远端／多跳／审批交互矩阵未验，不计D4-T02完整通过 |
| `acp-c3-protocol-1` | C3首尾源码干净、exit 0；现有生产ACP后端实际回复`OK`；适配器2.1.1，`trail_complete._meta.quota.model_usage`确认实际返回模型为`gpt-5.6-sol` | 真实协议探针，终端写入／工具请求被拒绝；没有原生UI审批或终端执行证据，不计D4-T04通过 |
| `acp-c3-resume-1` | C3首尾源码干净、exit 0；cancel后以相同session ID通过`session/load`恢复，记忆短语核验成功 | 现有生产ACP后端的真实恢复协议探针；只读fixture工具回复，无App／PTY执行，不替代原生恢复与审批矩阵 |
| iPhone `physical-profile.MIDSac` | C3干净源码独立Trail PRD Profile构建成功，签名、描述文件、独立Keychain已校验 | `installed=false`、`device_validated=false`、`acceptance_passed=false`；构建不是安装或真机验收 |
| `native-c3-workspace-1` | 已启动C3自有验收App并产生部分截图；录屏初始化失败，随后CUA明确报告Mac锁屏，UI停在打开Reader；仅终止该自有App，exit79、采集不完整 | 环境／采集阻断，不判定产品失败，不计完整验收通过；Mac解锁后需重跑并独立检查原生产物 |

完整 gate、SSH 和 ACP 的原始日志／metadata 已原样归档到 [C3 支撑证据](C3_GATE_EVIDENCE.md)，可随本分支独立审查；手机仅归档明确标注的构建身份摘要，不公开签名配置或设备资料。分支为 [composer](https://github.com/robinfai/ianvs-terminal/tree/composer)。

本地原始证据位置：

- `build/desktop-prd-v1/iteration-1/verify-7-metadata.json`、`verify-7.log`。
- `build/desktop-prd-v1/iteration-1/ssh-c3-native-1/run-metadata.json`、`runner.log`、`results.json`。
- `build/desktop-prd-v1/iteration-1/acp-c3-protocol-1/run-metadata.json`、`acp-c3-resume-1/run-metadata.json`。对应原始日志经内容核对后原样归档为 `probe.log`，只含连接／模型／回执／短语断言。
- `build/mobile-prd-v1.1/ios/physical-profile.MIDSac/build-metadata.json`；Runner宿主二进制SHA-256为 `dc56f718ccdf48579dfdfe6d22c111f541ed8f573457fb668a0f7d03395938ac`；完整App文件树和Flutter AOT指纹另见[iPhone摘要](../evidence/shared/C3-gates/iphone-build-summary.json)，不将宿主hash等同于完整App身份。
- `build/desktop-prd-v1/iteration-1/native-c3-workspace-1/run-metadata.json`、`environment-stop.json`及保留的部分截图。

完整 `verify-7`、SSH／ACP 原始日志与元数据已经归档到 `evidence/shared/C3-*`；它们仍不是正式 manifest 的完整场景截图／录像证据包。中止运行的部分窗口原图、录像诊断和手机安装包留在本地。正式 [manifest](../evidence/manifest.json) 的64个完整场景仍为`not_run`，没有将失败／中止运行或局部回归改成`passed`。各集合测试数存在不同层级，不能相加作为独立产品场景数。证据结构检查 exit 0；`--gate final` 为 exit 1（4 阶段和 64 场景未达，共 68 项），因此整体仍是 `implemented_unverified`。

## 尚未验证及恢复条件

| 未完成范围 | 当前条件与后续动作 |
|---|---|
| 单层栏真实拖窗、窗控命中、标签拖放／溢出、侧栏待审导航、关闭告警、前后台焦点和四pane组合 | Mac锁屏已确认并向用户询问解锁；恢复后重跑隔离原生场景。完整窗口录像不能单独证明位移，还需前后Bounds；原生告警需捕获同PID告警窗口 |
| 真实模型API／本地ACP完整链路、Finder PATH、原生恢复／权限、Manual与Smart矩阵 | ACP真实回复、实际模型`gpt-5.6-sol`及cancel后同会话load恢复已有C3协议证据；当前候选的正常UI配置／审批／执行全流程仍须验收。只读探针、mock、局部fixture或旧手机连接不替代该流程 |
| 中文IME物理候选确认、触摸板惯性、VoiceOver／Full Keyboard Access、系统减少动画 | 分别按实际系统功能操作并留证；注入composing／pan事件及Semantics测试不能替代 |
| 完整TUI／密码／特殊输出、睡眠恢复、断连竞争、长输出性能、升级回滚 | 现有自动子集通过；仍须完成PRD要求的实际组合、原始采样／副作用和数据保留证据 |
| 全部主题／状态／长路径中英文本、四窗口尺寸、1／1.5／2倍文字、字体及DPI矩阵 | 已更新6张指定macOS27基线，macOS26未复采；逻辑缩放不等于实际系统DPI与外接屏 |
| iPhone当前候选安装与验收 | C3构建已就绪但未安装；USB重连已向用户询问，待设备可用后先核对连接再安装验收 |
| 实体iPad、外接显示器 | 用户已明确暂时没有，按其指令保留未验收；不再次询问，不用模拟器或窗口缩放替代 |
| 支持系统／架构与其他桌面平台 | macOS14／15／26／27、iOS17／18／26／27支持要求保留；本轮宿主为arm64 macOS27.0.1，旧系统及Intel仍缺实测。Linux／Windows未提供当前App原生宿主，本轮不从零移植或声称可交付 |

手工入口 [tools/desktop_prd/README.md](../../../../tools/desktop_prd/README.md) 已提供独立AI配置、Profile／布局存储及本地Shell HOME／ZDOTDIR／XDG。它不复制生产私钥或API配置，不预设模型、不注入任务、不自动审批；SSH使用人工配置的远端环境。此入口是数据隔离，不是系统沙箱；Development窗口位置／尺寸偏好仍与普通Development应用共享，ACP既有认证路径可能使用宿主登录。入口接线测试不代表已经使用该入口完成全部原生手验。

## 无需再次作产品决策的事项

[v1.1修订](../16_REVISION_1_1.md)和[DECISIONS](DECISIONS.md)已明确三档审核、未知时补充要求、收起／Esc只读观察、编辑版本和结束未知跟进。手机固定字号、API基础模式、不做Android／远程ACP／跨进程聊天恢复，以及Linux／Windows不从零移植的范围均已明确。

本轮没有新的必需产品决策。当前缺口是环境恢复、真实执行和证据收集；环境暂缺不自动删减已承诺要求。实体iPad和外接显示器的缺口按已确认条件记录，其余可执行工作继续推进。
