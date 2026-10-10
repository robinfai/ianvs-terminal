# 当前平台与环境台账

2026-10-10。当前候选 C8 为 `19001573d9974c510e1e4cbcfeb01c94368ea157`，整体 `implemented_unverified`。C8真实macOS workspace及完整gate verify-10均通过，后者exit0／886秒、源码首尾clean；C8组件48/48、63PNG与Debug预览入口构建也通过，首尾clean／unchanged、未launch，4/63代表图复核无新增阻断；C3历史gate、C4组件／手机结果不改写为C8。以下事实不自动完成D4-T15或其他完整场景。

| 平台 | 当前入口/能力 | 本次实际环境 | 当前结论 |
|---|---|---|---|
| macOS | `example/macos` 原生宿主；既有gate检查真实PTY／Composer／签名／Xcode | arm64，macOS27.0.1 build26A434；C8原生窗1728×1084 points／视频3456×2168 pixels | C8 workspace exit0、首尾clean、原功能／收尾与录制严格区间通过；完整gate verify-10 exit0，应用3,065通过／1跳过、原生smoke4／PTY45／Composer1／Keychain1、Debug／Release／签名／Xcode通过。C3 verify-7历史通过；C8同候选六组件48测试／63PNG与预览构建通过、未launch；正式3passed／61not_run，整体未验完 |
| Linux | 当前 `example` 未提供 Linux 原生 App 宿主；共享 Dart/Rust 的存在不代表产品可安装 | 本次没有 Linux/X11/Wayland 运行环境 | 当前 App host 未提供，不能宣称 Linux 产品 verified；不在本轮从零移植 |
| Windows | 当前 `example` 未提供 Windows 原生 App 宿主；不从共享终端库推定完整 ConPTY 产品路径 | 本次没有 Windows 运行环境 | 当前 App host 未提供，不能宣称 Windows 产品 verified；不在本轮从零移植 |
| iPhone | 独立`work.ianvs.trail.mobileprd`，与普通Trail分开；SSH移动宿主保留 | 物理iPhone（iPhone18,3），iOS27.0.1，C4安装启动后通过iPhone镜像检查 | C4已安装／启动，DeepSeek连接smoke通过；保存Manual保留、Smart草稿取消；原观察SSH列表空／未执行；新授权导入 cloud 配置及私钥已准备；USB 已恢复，镜像仍待本人解锁，尚未转移私钥或保存 SSH，连接待测。无正式原图归档／完整模型→SSH／Smart执行，不当C8真机验收 |
| iPad | PRD 要求真实 iPad 宽窄窗、触控/键鼠与缩放 | 设备清单中未发现可用物理 iPad；用户本轮明确暂时没有设备 | 按用户指示记录未验收，要求保留 |

仓库范围依据：[CURRENT_EXECUTION_TARGET](../../../CURRENT_EXECUTION_TARGET.md)、[TERMINAL_PRODUCT_SCOPE](../../../TERMINAL_PRODUCT_SCOPE.md)。macOS 是桌面主交付平台，Linux/Windows 声明继续受真实 host 证据约束。Android 不在移动 PRD 范围。

## 支持窗口与实测窗口

兼容性要求仍取[Apple 基线](../../../APPLE_PLATFORM_COMPATIBILITY.md)：macOS 14/15/26/27，iOS 17/18/26/27。本次静态核对 Xcode 项目：macOS 三个配置最低 14.0，iOS 三个配置最低 17.0，与文档一致。本轮未提高部署目标；新增窗口拖动命中逻辑使用既有 AppKit 通路，旧支持系统仍需实际运行验证。

这不表示旧系统已实际运行。本次只有上述最新宿主/已连接设备信息；旧支持系统、Intel 在支持系统内的运行、真实多显示器/DPI、物理键盘/触摸板和 VoiceOver 仍需分别记录。不得用 macOS 调整逻辑窗口或模拟器替代物理 iPad、实际系统 DPI 或手机软键盘。

本轮只在 macOS 27 宿主审阅并更新了单层顶栏、底栏及正确桌面分支影响的 6 张截图基线。macOS 26 对应旧基线未复采，相关截图比较仍待该真实宿主验证；既有文件保留不代表它们适用于新候选。

本次显示器枚举仅包含内置 Liquid Retina XDR：物理 3456×2234，当前界面空间 1728×1117，120 Hz。未检测到外接显示器；没有据此填写跨显示器或不同 DPI 验收通过。

用户本轮已确认“暂时没有，记录未验收项”。实体iPad与外接显示器保留明确环境缺口，不用模拟器／窗口缩放冒充，也不重复询问。Mac已解锁，C8实际前台native App完成本地流程；iPhone C4已安装启动和连接smoke。设备枚举中的`sameMachine`不算真机。历史C3 Profile包当时未安装不改写为C4安装结果。

C4组件册测试DPR=1、导出PNG2×、固定仓库／SDK字体；不是系统DPI／系统字体证据。C8 native实际pixel_ratio=2；font_scale=1.0仅由相同SDK macOS embedder固定值与无override源码推导，非运行时测量。C8组件同候选复采48/48、63PNG及预览构建完成，仍widget DPR1／PNG导出2×／固定资产字体，未launch；4/63代表图复核没有新增阻断，完整跨系统／字体／多DPI矩阵未齐。

## Shell 与模型

C3 的原生 PTY gate 已通过；`build/desktop-prd-v1/iteration-1/ssh-c3-native-1/run-metadata.json` 另记录首尾源码干净、exit 0。真实回环 OpenSSH 六组 zsh/bash × emacs/vi 及各自 local→SSH 场景全部通过，包含受控多跳和返回父Shell恢复，结果见同目录 `runner.log`／`results.json`。此检查已覆盖上述 production native session API 子集，无 GUI；完整 App 的远端／多跳／审批矩阵未验，不代表 D4-T02 完整场景通过。测试使用 Homebrew Bash 5.3.20 满足 Bash4+ 要求，未修改登录 Shell；安装附带 json-c，并更新 libunistring/gettext 依赖。

已有本地 zsh、已协商远端 Bash/Zsh 和 Raw/TUI 回退的完整交互仍按场景核验；无可信 bridge 的环境保持仅编辑/复制或 Raw。没有新增远端文件/历史 provider。

历史`native-c3-workspace-1`有录屏初始化错误，后来CUA明确报告锁屏并停在Reader，exit79／capture false；后续还修正了driver陈旧Reader定位，无法把停顿全归锁屏。C6缺D12当时owner诊断无法定因；C7功能已完成但SemanticsHandle结束校验失败。C8仅driver诊断／录像握手变化，无运行中CUA AX，原生产权限与清理检查保留后通过；失败历史见[ITERATION_1](ITERATION_1.md)。

C8 `native-c8-workspace-1`是实际本地Shell／PTY＋确定性本地HTTP模型。Reader引用与过滤范围、暂停运行命令、真实vim网格与只读／明确接管子集已验证，但没有真实SSH／模型、系统IME／触摸板或VoiceOver动作。`run-metadata.json`和`result.json`归档至`evidence/shared/C8-native-workspace-1/`，不能把该run的内部D12标签误认为正式D4-T12 DPI已通过。

API 与本地 ACP 分开验收。ACP 在 Mac 本地运行，SSH 目标不会把它变为远端 ACP。C3 的 `acp-c3-protocol-1` 实际回复 `OK`，适配器版本2.1.1，`trail_complete._meta.quota.model_usage`确认实际返回模型为`gpt-5.6-sol`。`acp-c3-resume-1` 在cancel后以相同session ID通过`session/load`恢复，记忆短语核验成功。二者exit 0、首尾源码干净，记录分别位于`build/desktop-prd-v1/iteration-1/acp-c3-protocol-1`与`acp-c3-resume-1`。

上述为现有生产ACP后端的真实协议探针：拒绝终端写入，恢复探针只返回只读fixture工具结果，没有原生UI审批或App／PTY执行证据，不能标D4-T04通过。真实API完整链路、Finder最小PATH、原生恢复／权限、Manual／Smart和执行计数全流程仍需当前候选证据；已返回模型仅记录本次实测，不写死未来可用版本。完整gate与SSH／ACP支撑记录已归档到 `evidence/shared/C3-*`，入口见 [C3支撑证据](C3_GATE_EVIDENCE.md)。经核对不含凭据的ACP原始协议输出已原样归档。

手机DeepSeek连接通过只证明授权端点连接：配置标签`deepseek-flash`不是实际返回模型身份；首个请求遇系统网络权限，明确重试后显示成功。保留既存Manual、取消Smart草稿，原观察SSH未配置／未执行，后续用户已授权导入本机cloud配置与私钥，USB 已恢复有线连接，镜像仍待本人解锁，尚未转移私钥或保存SSH，未有SSH成功结论；原观察摘要见 `evidence/shared/C4-gates/ui-followup-summary.json`。未读取任何密钥值，不从设置可见推断所有SSH Profile／私钥已保留。
