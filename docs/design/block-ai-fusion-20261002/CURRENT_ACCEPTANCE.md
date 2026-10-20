# 当前场景验收索引

2026-10-04 补充：证据页返回／macOS 窗口按钮避让已修复；当前 AI 真对话完成九轮 imagegen 复核和相应整改，新增 104 项应用、22 项共享、5 项原生工作流与 4 种阅读尺寸的验证记录。原生模型为 ACP `gpt-5.6-sol`，最后的图像标注已通过实际提示画面核实收敛。具体范围、失败记录、提示词及限制见 [当前视觉迭代](IMAGEGEN_CURRENT_REVIEW.md)。下文较早的测试数量仍保留其原始执行语境。

2026-10-03，`composer` 工作区。按 [DESIGN.md](DESIGN.md) 的 D01–D14、M01–M06 逐项核对现有实现、自动回归与专项证据。此文件用于收敛历次记录的当前状态；历史文档中的“尚需核验”保留当时语境，以本索引及后续明确记录为准。

二十个场景的功能与布局已按下表完成实现与验收。2026-10-03 用户明确要求“VoiceOver 跳过”，因此 **VoiceOver 实际朗读记为未验收、排除于本次完成条件**；不再等待字幕读取授权。其余辅助功能要求仍按既有证据核验。历史原生／真实模型专项不冒充本轮重新执行；最近应用 1,025 项、共享终端 74 项、独立原生窗口 1 项通过。

## 场景逐项核对

| 场景 | 已核对的行为合同 | 实现／专项证据与范围 |
| --- | --- | --- |
| D01 输入与上下文 | 命令／AI 两份草稿及选区、显式输入意图、IME 防误提交、待附加范围、缺配置返回草稿 | `terminal_ai_workspace`、`terminal_composer_view`；[模型与原生入口](MODEL_SCENARIOS.md)、[配置](D10_D14_CONFIGURATION.md)。本轮 AI、Shell 回归覆盖 |
| D02 澄清与计划 | 原目标／约束保留，澄清与只分析不写 PTY；取消保留草稿、晚到回复失效 | `terminal_ai_controller`；[实际模型专项](MODEL_SCENARIOS.md)。仅证明所测问题和模型，不保证任意模型回答质量 |
| D03 提案审阅 | 完整命令／目标、编辑新 revision、旧批准失效、逐条批准、双击单次提交、普通 Enter 不批准 | `terminal_ai_workspace`、`terminal_ai_controller`；[原生与模型审阅](MODEL_SCENARIOS.md)、[完整命令](COMPOUND_COMMANDS.md) |
| D04 运行与观察 | 原生块唯一、回执与退出分离、暂停不发中断、追加约束、静默耗时、回看不拉回、桌面整块 1/3 | [实际静默及三批输出](SCENE_REVIEW.md)、[耗时](M03_ELAPSED.md)；新原生窗口再次验证暂停与状态标签，未执行真实命令 |
| D05 结果与证据 | 退出码不冒充需求完成；精确来源及范围、截断／无输出说明、点击原块、焦点与阅读保护、追问保留约束 | [输出边界](D05_OUTPUT_BOUNDARIES.md)、[来源／淘汰](D05_EVIDENCE_IDENTITY.md)、[焦点](D05_FOCUS.md)；本轮相关控制器与 UI 回归通过 |
| D06 失败诊断 | 纠正只附加不发送；先说明再给可审阅提案，保留原失败块，重复失败回诊断 | [实际模型及非零命令](MODEL_SCENARIOS.md)、[缺诊断正文守卫](D05_OUTPUT_BOUNDARIES.md)。不将提案当作保证成功的修复 |
| D07 多块上下文 | 选块／选文／附件独立，Cmd／Shift 多选，移除不删除块，发送冻结版本，跨会话不迁移执行目标 | [实际多选→移除→HTTP 逐值核对](SCENE_REVIEW.md)、[来源隔离](D05_EVIDENCE_IDENTITY.md) |
| D08 桌面阅读 | 分页、搜索／过滤、明确复制范围、精确选段、单次滚动归属、输出刷新不回弹、保留阅读锚点、淘汰提示 | [阅读工具](D08_READER_TOOLS.md)、[淘汰定位](D05_EVIDENCE_IDENTITY.md)；[本轮补齐内部路由](MOTION_REVIEW.md)，74 项共享回归包含复制和阅读 |
| D09 接管与目标 | 手动接管撤销批准，已提交命令继续；恢复先读取、去重，目标选择显式，晚到旧选择失效 | [目标变化／恢复审计](D09_AUDIT.md)；目标选择 UI 用内存端口，真实 SSH 能力链路见 D11 |
| D10 断线与未知 | 区分模型／终端／回执错误，保留目标草稿历史；只查原提交、不重发；重连后新动作重新审批 | [实际断线](D10_DISCONNECT.md)、[实际未知回执／重连](D10_RECONNECT.md)、[恢复状态布局](D10_D14_CONFIGURATION.md) |
| D11 SSH 协商 | 当前节点能力、自动 Normal、tab 原因、同 PTY 输出草稿保持、恢复手动 Blocks、只读重检 | [实际 cloud 两次 ls、嵌套及 Bash/zsh 专项](D11_CLOUD_CLEAR.md)。本轮菜单回归不代替真实 SSH 专项 |
| D12 TUI 交接 | top/vim/k9s 全终端，AI 覆盖不 resize，Esc／Ctrl+C 输入归属，批准按键一次，退出后手动 Blocks | [实际 k9s](D12_K9S.md)、[实际 cloud top/Vim](D11_CLOUD_CLEAR.md)。k9s 的 Kubernetes 与模型为本地隔离 fixture |
| D13 回看与定位 | 新结果不抢锚点，明确定位／返回，异步最新操作生效；任务草稿附件位置隔离，切换不执行 | [导航布局](D13_D14_REVIEW.md)、[异步导航与状态语义](M03_ELAPSED.md)。VoiceOver 实际不重播检查按用户要求跳过，不计为通过 |
| D14 偏好与配置 | 平台默认与显式偏好分离、只影响新会话；缺配置不阻塞终端，连接测试与保存分开，失败保留编辑 | [平台默认](D13_D14_REVIEW.md)、[缺失／慢读／失败／取消／保存状态](D10_D14_CONFIGURATION.md)；本轮设置弹窗动态效果回归通过 |
| M01 手机输入 | 固定字号、六行自然预览、独立草稿、键盘约束不压缩预览、44px 目标、短横屏入口可达 | [生产组件与原生渲染](MODEL_SCENARIOS.md)、`mobile_terminal_modes_test`；系统键盘由组件约束模拟 |
| M02 手机审阅 | 横竖屏专用完整审阅页、长命令滚动、固定确认区、编辑后重审、返回／滑动不执行 | [手机完整审阅](MODEL_SCENARIOS.md)及本轮 workspace 回归；60 行命令、横竖屏、固定字号 |
| M03 手机运行 | 最多六行、无块内纵向滚动、更新不重置回看、暂停不发中断、后台不执行、耗时保留 | [当前浅深色动态证据](SCENE_REVIEW.md)、[耗时](M03_ELAPSED.md)；60→120→180 行与后台恢复为组件场景 |
| M04 手机阅读 | 独立阅读页、原行号＋像素锚点、选段／搜索、返回草稿和选区、前页补偿、淘汰提示、不停止命令 | [阅读工具](D08_READER_TOOLS.md)、[来源定位](D05_EVIDENCE_IDENTITY.md)、本轮共享回归；本轮关闭菜单与阅读路由检查覆盖 iOS 平台组件 |
| M05 手机模式 | 触控会话菜单、自动降级原因、只读重检、能力恢复手动切回、菜单无 PTY 输入或 resize | `mobile_terminal_modes_test` 和 [模式实现记录](IMPLEMENTATION.md)；本轮新增减少动态效果及状态保持检查 |
| M06 手机 TUI | AI 不额外占用 PTY 网格，键盘约束变化可恢复，AI 与辅助键归属隔离，退出后手动 Blocks | `mobile_terminal_modes_test` 及 [原生工作流](BEHAVIOR_VALIDATION.md)；320px／短横屏为固定字号组件，不是 iPhone 真机 |

## 公共合同与交付边界

- 高对比、浅深色与桌面 2×：主题、焦点边界、配置和审阅布局有独立证据，见 [辅助功能复核](ACCESSIBILITY_REVIEW.md)。系统特征注入测试不声称覆盖所有支持版本的系统设置。
- Reduce Motion：AI、Block、内部阅读路由、Shell 模式／会话／设置菜单均已补齐；普通动画保留，菜单退出及焦点恢复通过，见 [动态效果复核](MOTION_REVIEW.md)。
- 实际朗读：按用户 2026-10-03 的明确要求跳过，保留未验收记录，不声称通过。此前授权尝试、字幕读取限制与完成清理见 [VoiceOver 验收尝试](VOICEOVER_ATTEMPT.md)，窗口归属保护见 [窗口归属核验](MOTION_REVIEW.md)。本次完成范围不再包含实际 VoiceOver 检查，也不再需要全局字幕读取授权。
- 发布镜像：本轮 `dart run tools/sync_terminal_core.dart --check` 通过。`shell_screen.dart` 1,699 行，架构门禁保持原阈值，本轮应用测试通过。
- 手机只验收固定字号，遵从根 AGENTS.md；用户明确取消真机测试，故 iPhone 键盘与辅助技术实机表现不作为本次已测结论。原生运行环境仅 macOS 27.0.1（26A434），其他支持 OS 没有实机覆盖声明。
- 归档完整性检查只证明证据文件完整；旧源码哈希保留历史含义，不据此宣称旧专项在当前源码重新运行。最终记录见 [完成核对](evidence/completion/checks.json)。
- 按用户确认的范围，本次场景实现与验收完成。未提交或推送。

本轮日志、失败复现、原生截图、结果和源码哈希在 [motion-and-fixture 清单](evidence/motion-and-fixture/manifest.json)。更早的实施过程保留在 [IMPLEMENTATION.md](IMPLEMENTATION.md)，各专项页面保留真实失败、修复和验证限制。
