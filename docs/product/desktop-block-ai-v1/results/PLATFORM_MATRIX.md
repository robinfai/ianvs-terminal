# 当前平台与环境台账

2026-10-10。当前共享源码候选 C10 为 `2d18e608c2a1149a093451b5246cb370de0167c3`，整体 `implemented_unverified`。C9 verify11 exit2 的两个输入回归在C10修复；原103项、相关297项及canonical165项定向通过，完整 [verify12](../evidence/shared/C10-gates/verify-12.log) 已 exit0（792秒、源码首尾clean；[metadata](../evidence/shared/C10-gates/verify-12-metadata.json)），应用3090通过／1跳过，原生smoke4／真实PTY45／Composer1／Keychain1及Debug／Release／签名检查／Xcode通过，首次正常UI复验因AX陈旧和提前结束录屏仅留局部观察；第二次有界复验补做遮罩取消及idleAI取消／明确关闭，保留A，未复现AXTree错误，但首轮原因仍未定且没有新增正式场景通过。详见[C9–C10跟进记录](C9_FOLLOWUP.md)。正式记录仍是历史 C8 `19001573d9974c510e1e4cbcfeb01c94368ea157` 的 3 passed / 61 not_run；旧证据不改绑为新候选。手机仍为 C4 `1c95adcaab32fac64fb08142da7a0eb3b8620b5a`。以下局部事实不自动完成 D4-T15 或其他完整场景。

| 平台 | 当前入口/能力 | 本次实际环境 | 当前结论 |
|---|---|---|---|
| macOS | `example/macos` 原生宿主；既有 gate 检查真实 PTY／Composer／签名／Xcode | arm64，macOS 27.0.1 build 26A434；历史 C8 原生窗 1728×1084 points／视频 3456×2168 pixels | C9 完整 verify11 exit2（3083 passed / 1 skip / 2 failed）保留历史；C10已修两个split pane输入回归，原103项、相关297项及canonical165项通过，完整 [verify12](../evidence/shared/C10-gates/verify-12.log) 已 exit0（792秒、源码首尾clean；[metadata](../evidence/shared/C10-gates/verify-12-metadata.json)），应用3090通过／1跳过，原生smoke4／真实PTY45／Composer1／Keychain1及Debug／Release／签名检查／Xcode通过，第一次正常UI因AX异常／录屏提前结束仅留局部；第二次补做遮罩取消及idleAI取消／明确关闭，仍未完成正式用例，首轮AX原因未定。历史 C8 workspace exit 0、首尾 clean、原功能／收尾与录制严格区间通过；verify10 exit 0，应用 3,065 通过／1 跳过、原生 smoke 4／PTY 45／Composer 1／Keychain 1、Debug／Release／签名／Xcode 通过。C3 verify7 历史通过；C8 六组件 48 测试／63 PNG 与预览构建通过、未 launch；C8 正式 3 passed／61 not_run 不迁移为 C10 验收 |
| Linux | 当前 `example` 未提供 Linux 原生 App 宿主；共享 Dart/Rust 的存在不代表产品可安装 | 本次没有 Linux/X11/Wayland 运行环境 | 当前 App host 未提供，不能宣称 Linux 产品 verified；不在本轮从零移植 |
| Windows | 当前 `example` 未提供 Windows 原生 App 宿主；不从共享终端库推定完整 ConPTY 产品路径 | 本次没有 Windows 运行环境 | 当前 App host 未提供，不能宣称 Windows 产品 verified；不在本轮从零移植 |
| iPhone | 独立 `work.ianvs.trail.mobileprd`，与普通 Trail 分开；SSH 移动宿主保留 | 物理 iPhone（iPhone18,3），iOS 27.0.1；C4 安装启动后通过 iPhone 镜像检查 | C4 已安装／启动，DeepSeek 连接 smoke 通过；保存的 manual 保留、Smart 草稿取消。最初 SSH 空列表／未执行和镜像等待均为历史；后续已按授权导入保存 cloud 配置与私钥并恢复。指定临时源由 2459 覆盖为 0 字节，清理前后两次重启及清理后 SSH 只读命令成功；三张原图私有，配置保活 30 秒／3 次来自操作者记录，长时保活未验。未完成模型→SSH／Smart 全流程，不当 C8/C9/C10 真机验收 |
| iPad | PRD 要求真实 iPad 宽窄窗、触控/键鼠与缩放 | 设备清单中未发现可用物理 iPad；用户本轮明确暂时没有设备 | 按用户指示记录未验收，要求保留 |

仓库范围依据：[CURRENT_EXECUTION_TARGET](../../../CURRENT_EXECUTION_TARGET.md)、[TERMINAL_PRODUCT_SCOPE](../../../TERMINAL_PRODUCT_SCOPE.md)。macOS 是桌面主交付平台，Linux/Windows 声明继续受真实 host 证据约束。Android 不在移动 PRD 范围。

## 支持窗口与实测窗口

兼容性要求仍取[Apple 基线](../../../APPLE_PLATFORM_COMPATIBILITY.md)：macOS 14/15/26/27，iOS 17/18/26/27。本次静态核对 Xcode 项目：macOS 三个配置最低 14.0，iOS 三个配置最低 17.0，与文档一致。本轮未提高部署目标；新增窗口拖动命中逻辑使用既有 AppKit 通路，旧支持系统仍需实际运行验证。

这不表示旧系统已实际运行。本次只有上述最新宿主/已连接设备信息；旧支持系统、Intel 在支持系统内的运行、真实多显示器/DPI、物理键盘/触摸板和 VoiceOver 仍需分别记录。不得用 macOS 调整逻辑窗口或模拟器替代物理 iPad、实际系统 DPI 或手机软键盘。

本轮只在 macOS 27 宿主审阅并更新了单层顶栏、底栏及正确桌面分支影响的 6 张截图基线。macOS 26 对应旧基线未复采，相关截图比较仍待该真实宿主验证；既有文件保留不代表它们适用于新候选。

本次显示器枚举仅包含内置 Liquid Retina XDR：物理 3456×2234，当前界面空间 1728×1117，120 Hz。未检测到外接显示器；没有据此填写跨显示器或不同 DPI 验收通过。

C10普通UI局部运行的[C10原生局部复验摘要](../evidence/shared/C10-native-partial/review-summary.json)保留App PID77686／window31265、首尾clean及关闭取消检查。10条AXTree错误后的陈旧树没有确定首因；Cmd+T有响应不证明Flutter组合键或物理键验收。录像仅09:41:51–09:47:04、312秒，SCStream -3822提前结束；后两张支撑图不在录像内，部分截图窗口非前台。不新增正式场景通过。

[第二次C10有界复验摘要](../evidence/shared/C10-native-fixed-window/review-summary.json)补做A遮罩取消与B idleAI草稿的取消／明确关闭，保留A；日志0 AXTree错误、1 Window move警告，不消除第一轮异常。7个截图点均非前台，256秒录像包含检查点但不覆盖整段App生命周期，SCStream停止与Ctrl-C精确关系未记录。原生局部观察不增加formal pass。

用户本轮已确认“暂时没有，记录未验收项”。实体 iPad 与外接显示器保留明确环境缺口，不用模拟器／窗口缩放冒充，也不重复询问。Mac 已解锁，历史 C8 实际前台 native App 完成本地流程；iPhone C4 已安装启动、连接 smoke，并完成后续 cloud 导入恢复和清理后 SSH 只读验证，见[独立恢复摘要](../evidence/shared/C4-cloud-restoration/independent-review-summary.json)。设备枚举中的 `sameMachine` 不算真机。历史 C3 Profile 包当时未安装不改写为 C4 安装结果；上述结果亦不改绑为当前 C10。

C4组件册测试DPR=1、导出PNG2×、固定仓库／SDK字体；不是系统DPI／系统字体证据。C8 native实际pixel_ratio=2；font_scale=1.0仅由相同SDK macOS embedder固定值与无override源码推导，非运行时测量。C8组件同候选复采48/48、63PNG及预览构建完成，仍widget DPR1／PNG导出2×／固定资产字体，未launch；4/63代表图复核没有新增阻断，完整跨系统／字体／多DPI矩阵未齐。

## Shell 与模型

C3 的原生 PTY gate 已通过；`build/desktop-prd-v1/iteration-1/ssh-c3-native-1/run-metadata.json` 另记录首尾源码干净、exit 0。真实回环 OpenSSH 六组 zsh/bash × emacs/vi 及各自 local→SSH 场景全部通过，包含受控多跳和返回父Shell恢复，结果见同目录 `runner.log`／`results.json`。此检查已覆盖上述 production native session API 子集，无 GUI；完整 App 的远端／多跳／审批矩阵未验，不代表 D4-T02 完整场景通过。测试使用 Homebrew Bash 5.3.20 满足 Bash4+ 要求，未修改登录 Shell；安装附带 json-c，并更新 libunistring/gettext 依赖。

已有本地 zsh、已协商远端 Bash/Zsh 和 Raw/TUI 回退的完整交互仍按场景核验；无可信 bridge 的环境保持仅编辑/复制或 Raw。没有新增远端文件/历史 provider。

历史`native-c3-workspace-1`有录屏初始化错误，后来CUA明确报告锁屏并停在Reader，exit79／capture false；后续还修正了driver陈旧Reader定位，无法把停顿全归锁屏。C6缺D12当时owner诊断无法定因；C7功能已完成但SemanticsHandle结束校验失败。C8仅driver诊断／录像握手变化，无运行中CUA AX，原生产权限与清理检查保留后通过；失败历史见[ITERATION_1](ITERATION_1.md)。

C8 `native-c8-workspace-1`是实际本地Shell／PTY＋确定性本地HTTP模型。Reader引用与过滤范围、暂停运行命令、真实vim网格与只读／明确接管子集已验证，但没有真实SSH／模型、系统IME／触摸板或VoiceOver动作。`run-metadata.json`和`result.json`归档至`evidence/shared/C8-native-workspace-1/`，不能把该run的内部D12标签误认为正式D4-T12 DPI已通过。

API 与本地 ACP 分开验收。ACP 在 Mac 本地运行，SSH 目标不会把它变为远端 ACP。C3 的 `acp-c3-protocol-1` 实际回复 `OK`，适配器版本2.1.1，`trail_complete._meta.quota.model_usage`确认实际返回模型为`gpt-5.6-sol`。`acp-c3-resume-1` 在cancel后以相同session ID通过`session/load`恢复，记忆短语核验成功。二者exit 0、首尾源码干净，记录分别位于`build/desktop-prd-v1/iteration-1/acp-c3-protocol-1`与`acp-c3-resume-1`。

上述为现有生产ACP后端的真实协议探针：拒绝终端写入，恢复探针只返回只读fixture工具结果，没有原生UI审批或App／PTY执行证据，不能标D4-T04通过。真实API完整链路、Finder最小PATH、原生恢复／权限、Manual／Smart和执行计数全流程仍需当前候选证据；已返回模型仅记录本次实测，不写死未来可用版本。完整gate与SSH／ACP支撑记录已归档到 `evidence/shared/C3-*`，入口见 [C3支撑证据](C3_GATE_EVIDENCE.md)。经核对不含凭据的ACP原始协议输出已原样归档。

手机 DeepSeek 连接通过只证明授权端点连接：配置标签 `deepseek-flash` 不是实际返回模型身份；首个请求遇系统网络权限，明确重试后显示成功。保留既存 manual、取消 Smart 草稿，以及最初 SSH 未配置／未执行均见[原观察摘要](../evidence/shared/C4-gates/ui-followup-summary.json)。此前 USB／镜像阻断和未转移记录只描述当时状态；当前用户授权的 cloud 配置／私钥导入、保存和恢复已完成，清理前后两次重启及清理后只读命令成功见[独立恢复摘要](../evidence/shared/C4-cloud-restoration/independent-review-summary.json)和 [C9 跟进记录](C9_FOLLOWUP.md)。三张原图经独立查看并核对哈希，因包含账号与主目录信息保留私有；没有连续视频或精确网络／执行计数，不从单次连接推断所有 SSH Profile／私钥已保留。

第二次恢复只对精确指定的临时导入源做零字节覆盖，独立摘要记录唯一同名文件从 2459 变为 0 字节、配置文件全部已记录元数据相同；未读取／比较配置内容，逻辑大小归零不证明闪存安全擦除或排除未知副本。第一次目录清理 exit 1/error7000 后出现 onboarding／空 SSH 列表和配置目录重建；具体清理范围与唯一原因未定，不能将错误退出视为无副作用，也不能据此认定产品持久化缺陷；后续恢复成功单独记录。

手机保活 30 秒／3 次来自操作者已保存设置的记录，独立 reviewer 未重新读取配置值。最后独立审阅的成功图之后，镜像显示手机正在被使用而结束，后续 Shell 状态不可见；镜像中断不等于 SSH 断连，不将离散截图换算为连续可用时长。长时间保活、后台锁屏、完整真实模型到 SSH 与 Smart 执行仍未验；公开摘要不包含私钥／API Key 正文，原始设备 JSON 与三张原图继续私有。
