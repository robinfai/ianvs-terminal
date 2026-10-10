# 当前平台与环境台账

2026-10-10。仅记录本次实际检查；本表不能代替 D4-T15 的完整证据和最终候选验证。

| 平台 | 当前入口/能力 | 本次实际环境 | 当前结论 |
|---|---|---|---|
| macOS | `example/macos` 原生宿主；`tools/verify_macos_app.sh` 检查真实 PTY、Composer、签名及 Xcode 测试 | arm64，macOS 27.0.1，build 26A434 | C2 已通过原生冒烟 4 项及真实 PTY 45 项；随后暴露的 Composer 问题已修复，原测试通过，待下一候选完整 gate；implemented_unverified |
| Linux | 当前 `example` 未提供 Linux 原生 App 宿主；共享 Dart/Rust 的存在不代表产品可安装 | 本次没有 Linux/X11/Wayland 运行环境 | 当前 App host 未提供，不能宣称 Linux 产品 verified；不在本轮从零移植 |
| Windows | 当前 `example` 未提供 Windows 原生 App 宿主；不从共享终端库推定完整 ConPTY 产品路径 | 本次没有 Windows 运行环境 | 当前 App host 未提供，不能宣称 Windows 产品 verified；不在本轮从零移植 |
| iPhone | 当前 SSH 移动宿主保留；与桌面共享修改须复验 | 物理 iPhone，iOS 27.0.1；此前有线可用，最新设备枚举显示 tunnel unavailable、无传输连接 | 尚无新候选物理验收证据；构建后安装前重新核对连接 |
| iPad | PRD 要求真实 iPad 宽窄窗、触控/键鼠与缩放 | 设备清单中未发现可用物理 iPad；用户本轮明确暂时没有设备 | 按用户指示记录未验收，要求保留 |

仓库范围依据：[CURRENT_EXECUTION_TARGET](../../../CURRENT_EXECUTION_TARGET.md)、[TERMINAL_PRODUCT_SCOPE](../../../TERMINAL_PRODUCT_SCOPE.md)。macOS 是桌面主交付平台，Linux/Windows 声明继续受真实 host 证据约束。Android 不在移动 PRD 范围。

## 支持窗口与实测窗口

兼容性要求仍取[Apple 基线](../../../APPLE_PLATFORM_COMPATIBILITY.md)：macOS 14/15/26/27，iOS 17/18/26/27。本次静态核对 Xcode 项目：macOS 三个配置最低 14.0，iOS 三个配置最低 17.0，与文档一致。本轮未提高部署目标；新增窗口拖动命中逻辑使用既有 AppKit 通路，旧支持系统仍需实际运行验证。

这不表示旧系统已实际运行。本次只有上述最新宿主/已连接设备信息；旧支持系统、Intel 在支持系统内的运行、真实多显示器/DPI、物理键盘/触摸板和 VoiceOver 仍需分别记录。不得用 macOS 调整逻辑窗口或模拟器替代物理 iPad、实际系统 DPI 或手机软键盘。

本轮只在 macOS 27 宿主审阅并更新了新增底栏影响的 6 张截图基线。macOS 26 对应旧基线未复采，相关截图比较仍待该真实宿主验证；既有文件保留不代表它们适用于新候选。

本次显示器枚举仅包含内置 Liquid Retina XDR：物理 3456×2234，当前界面空间 1728×1117，120 Hz。未检测到外接显示器；没有据此填写跨显示器或不同 DPI 验收通过。

用户本轮已确认“暂时没有，记录未验收项”。实体 iPad 与外接显示器相关场景因此保留明确的环境缺口；不会用模拟器或窗口缩放冒充通过，也不再重复询问相同设备条件。当前 Mac 的可执行验证继续；iPhone 先完成签名构建准备，原地安装前重新核对实时连接。设备枚举中的 `sameMachine` 虚拟设备不计入真机可用性。

## Shell 与模型

优先验证已有本地 zsh、已协商远端 Bash/Zsh、Raw/TUI 回退；无可信 bridge 的环境保持仅编辑/复制或 Raw。没有新增远端文件/历史 provider。

API 与本地 ACP 分开验收。ACP 在 Mac 本地运行，SSH 目标不会把它变为远端 ACP。真实端点、实际返回模型、Finder 最小 PATH、恢复/权限边界与执行计数均需新候选证据；本表不写死未来可用模型版本。旧连接成功或已安装适配器不能替代当前全流程。
