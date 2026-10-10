# 当前平台与环境台账

2026-10-10。当前实现候选 C3 为 `7e9f0dd8e7bd825c655ceb80d817d5fe214337bd`，整体状态 `implemented_unverified`。仅记录本次实际检查；C3 自动验证通过不代替 D4-T15 或其他完整产品场景的证据。

| 平台 | 当前入口/能力 | 本次实际环境 | 当前结论 |
|---|---|---|---|
| macOS | `example/macos` 原生宿主；`tools/verify_macos_app.sh` 检查真实 PTY、Composer、签名及 Xcode 测试 | arm64，macOS 27.0.1，build 26A434 | C3 完整 make verify exit 0、首尾源码干净；原生冒烟4项、真实PTY45项、Composer1项、Keychain1项、构建／签名及Xcode测试通过；完整产品原生验收仍未完成，implemented_unverified |
| Linux | 当前 `example` 未提供 Linux 原生 App 宿主；共享 Dart/Rust 的存在不代表产品可安装 | 本次没有 Linux/X11/Wayland 运行环境 | 当前 App host 未提供，不能宣称 Linux 产品 verified；不在本轮从零移植 |
| Windows | 当前 `example` 未提供 Windows 原生 App 宿主；不从共享终端库推定完整 ConPTY 产品路径 | 本次没有 Windows 运行环境 | 当前 App host 未提供，不能宣称 Windows 产品 verified；不在本轮从零移植 |
| iPhone | 当前 SSH 移动宿主保留；与桌面共享修改须复验 | 物理 iPhone，iOS 27.0.1；此前有线可用，最新设备枚举显示 tunnel unavailable、无传输连接 | C3 独立 Trail PRD Profile 构建成功，签名／描述文件及独立 Keychain 校验通过；尚未安装、未完成设备验证或验收。USB重连已询问，待可用后安装 |
| iPad | PRD 要求真实 iPad 宽窄窗、触控/键鼠与缩放 | 设备清单中未发现可用物理 iPad；用户本轮明确暂时没有设备 | 按用户指示记录未验收，要求保留 |

仓库范围依据：[CURRENT_EXECUTION_TARGET](../../../CURRENT_EXECUTION_TARGET.md)、[TERMINAL_PRODUCT_SCOPE](../../../TERMINAL_PRODUCT_SCOPE.md)。macOS 是桌面主交付平台，Linux/Windows 声明继续受真实 host 证据约束。Android 不在移动 PRD 范围。

## 支持窗口与实测窗口

兼容性要求仍取[Apple 基线](../../../APPLE_PLATFORM_COMPATIBILITY.md)：macOS 14/15/26/27，iOS 17/18/26/27。本次静态核对 Xcode 项目：macOS 三个配置最低 14.0，iOS 三个配置最低 17.0，与文档一致。本轮未提高部署目标；新增窗口拖动命中逻辑使用既有 AppKit 通路，旧支持系统仍需实际运行验证。

这不表示旧系统已实际运行。本次只有上述最新宿主/已连接设备信息；旧支持系统、Intel 在支持系统内的运行、真实多显示器/DPI、物理键盘/触摸板和 VoiceOver 仍需分别记录。不得用 macOS 调整逻辑窗口或模拟器替代物理 iPad、实际系统 DPI 或手机软键盘。

本轮只在 macOS 27 宿主审阅并更新了单层顶栏、底栏及正确桌面分支影响的 6 张截图基线。macOS 26 对应旧基线未复采，相关截图比较仍待该真实宿主验证；既有文件保留不代表它们适用于新候选。

本次显示器枚举仅包含内置 Liquid Retina XDR：物理 3456×2234，当前界面空间 1728×1117，120 Hz。未检测到外接显示器；没有据此填写跨显示器或不同 DPI 验收通过。

用户本轮已确认“暂时没有，记录未验收项”。实体 iPad 与外接显示器相关场景因此保留明确的环境缺口；不会用模拟器或窗口缩放冒充通过，也不再重复询问相同设备条件。当前 Mac 的 C3 自动验证已完成；额外 workspace 原生 UI 验收因录屏工具初始化失败和锁屏中止，Mac 解锁已询问。iPhone 签名构建已完成但未安装，USB重连已询问；安装前仍须重新核对实时连接。设备枚举中的 `sameMachine` 虚拟设备不计入真机可用性。

## Shell 与模型

C3 的原生 PTY gate 已通过；`build/desktop-prd-v1/iteration-1/ssh-c3-native-1/run-metadata.json` 另记录首尾源码干净、exit 0。真实回环 OpenSSH 六组 zsh/bash × emacs/vi 及各自 local→SSH 场景全部通过，包含受控多跳和返回父Shell恢复，结果见同目录 `runner.log`／`results.json`。此检查已覆盖上述 production native session API 子集，无 GUI；完整 App 的远端／多跳／审批矩阵未验，不代表 D4-T02 完整场景通过。测试使用 Homebrew Bash 5.3.20 满足 Bash4+ 要求，未修改登录 Shell；安装附带 json-c，并更新 libunistring/gettext 依赖。

已有本地 zsh、已协商远端 Bash/Zsh 和 Raw/TUI 回退的完整交互仍按场景核验；无可信 bridge 的环境保持仅编辑/复制或 Raw。没有新增远端文件/历史 provider。

`native-c3-workspace-1` 的录屏工具初始化失败，随后 CUA 明确报告 Mac 锁屏，UI 停在打开 Reader。仅停止该自有验收 App，exit 79、`capture_artifacts_complete=false`；保留部分证据，不登记为产品失败或完整场景通过。见同目录 `run-metadata.json` 和 `environment-stop.json`。

API 与本地 ACP 分开验收。ACP 在 Mac 本地运行，SSH 目标不会把它变为远端 ACP。C3 的 `acp-c3-protocol-1` 实际回复 `OK`，适配器版本2.1.1，`trail_complete._meta.quota.model_usage`确认实际返回模型为`gpt-5.6-sol`。`acp-c3-resume-1` 在cancel后以相同session ID通过`session/load`恢复，记忆短语核验成功。二者exit 0、首尾源码干净，记录分别位于`build/desktop-prd-v1/iteration-1/acp-c3-protocol-1`与`acp-c3-resume-1`。

上述为现有生产ACP后端的真实协议探针：拒绝终端写入，恢复探针只返回只读fixture工具结果，没有原生UI审批或App／PTY执行证据，不能标D4-T04通过。真实API完整链路、Finder最小PATH、原生恢复／权限、Manual／Smart和执行计数全流程仍需当前候选证据；已返回模型仅记录本次实测，不写死未来可用版本。完整gate与SSH／ACP支撑记录已归档到 `evidence/shared/C3-*`，入口见 [C3支撑证据](C3_GATE_EVIDENCE.md)。经核对不含凭据的ACP原始协议输出已原样归档。
