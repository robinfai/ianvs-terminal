# Ianvs Terminal 平台适配矩阵

这份文档对应 `M6: Cross-Platform Readiness Planning`，用于回答三个问题：

1. 当前哪些能力只在 macOS 主线完成并验证。
2. 哪些平台边界已经在产品层抽成 adapter 或独立模型。
3. 下一轮应该优先挑哪个平台进入实现，而不是继续泛化讨论。

状态定义：

- `支持`：当前工作树已有实现，并且在本仓库验证链路里有直接证据。
- `降级`：当前有产品模型或局部能力，但范围明显小于长期目标。
- `待验证`：代码或路径边界已准备好，但没有目标平台上的真实构建 / smoke 证据。
- `不支持`：当前明确不做，或现有实现不应被视为该平台可用。

## 桌面矩阵

| 能力 | macOS | Windows | Linux | 证据 / 说明 |
| --- | --- | --- | --- | --- |
| 窗口菜单、Header 操作和快捷键 | `支持` | `待验证` | `待验证` | macOS 通过 `PlatformMenuBar`、widget tests 和 `flutter build macos --release` 验证；其他桌面平台尚无目标平台构建证据。 |
| 本地 PTY shell session | `支持` | `待验证` | `待验证` | 当前真实 shell smoke 和 `NativePtyBackend.load()` 基线只在 macOS 验证。 |
| 本地 `ssh` command session | `支持` | `待验证` | `待验证` | `M5B` 已验证 `New SSH Session` 和 `ssh -V` launch smoke；非 macOS 未验证本地 `ssh` binary 路径、PTY 和退出行为。 |
| session restore / settings / saved commands 状态目录 | `支持` | `待验证` | `待验证` | `lib/src/platform_paths.dart` 统一状态路径；`test/platform_paths_test.dart`、`test/session_restore_test.dart`、`test/launch_config_test.dart` 覆盖路径规则，但没有目标平台运行证据。 |
| zsh shell integration 与 block / cwd hooks | `支持` | `待验证` | `待验证` | 当前实现依赖 `ZDOTDIR` 和本地 zsh；macOS real smoke 已验证，Windows/Linux 未确认默认 shell 与 hook 行为。 |
| 字体、terminal viewport 和 completion 主线 | `支持` | `待验证` | `待验证` | 现有产品模型与 flutterm runtime 不绑定 macOS，但只在 macOS 主线回归。 |
| 桌面打包与发布门槛 | `支持` | `不支持` | `不支持` | 当前只有 macOS target、entitlements、release build gate；Windows/Linux 尚未生成平台目录。 |

## 移动矩阵

| 能力 | iOS | Android | 证据 / 说明 |
| --- | --- | --- | --- |
| 本地 shell / PTY | `不支持` | `不支持` | `MILESTONES.md` 和 `PRODUCT_PLAN.md` 都明确不提前承诺移动端本地 shell。 |
| 远程 terminal / SSH / Ianvs 会话 | `待验证` | `待验证` | 现有 tab、pane、session metadata、audit snapshot 模型可以复用，但没有移动端 transport 和 UI 适配实现。 |
| 触屏输入与移动端编辑体验 | `待验证` | `待验证` | 现代输入控制器可复用，但没有软键盘、触控选区、手势滚动和移动端快捷操作设计。 |
| 系统剪贴板 | `待验证` | `待验证` | `ClipboardClient` 已隔离产品层调用，但没有移动端 widget / integration 证据。 |
| 安全上下文展示 | `待验证` | `待验证` | `Session Context`、tab title、audit snapshot 已是平台无关模型；移动端布局和权限流未设计。 |

## 当前 adapter inventory

- `lib/src/platform_paths.dart`
  - 统一状态目录、`settings.json`、`saved_commands.json`、`session_restore.json`、shell integration `ZDOTDIR` 路径，以及默认 home / cwd fallback。
- `lib/src/clipboard_client.dart`
  - 产品侧只依赖 `ClipboardClient`，避免把 Flutter 系统剪贴板直接散落到会话控制器和 block 逻辑里。
- `lib/src/session_restore.dart`
  - session restore JSON 与 pane / tab 模型独立于平台；文件落点通过 `platform_paths.dart` 决定。
- `lib/src/launch_config.dart`
  - launch config 是 workspace 资产，不绑定某个平台的状态目录；只按目标 OS 处理路径分隔符。
- `lib/src/session_metadata.dart` 与 `lib/src/session_launch.dart`
  - 把“显示 metadata”“安全上下文”“真实 command launch”拆成产品模型，不把 macOS shell 行为写进 pane / tab 元数据。

## 仍然保留在 macOS 主线的边界

- `lib/main.dart` 里的 `PlatformMenuBar` 和当前桌面交互密度仍然按 macOS 优先设计。
- `macos/Runner/*.entitlements` 和 `flutter build macos --release` 仍然是唯一发布门槛。
- `NativePtyBackend.load()` 的真实 smoke 只在 macOS 回归，Windows/Linux 还没有对应的 CI 或手工矩阵。
- `session_launch.dart` 当前对 `ssh` binary 的优先路径是 POSIX 风格，Windows 的 OpenSSH / PATH 约定还没核实。

这些边界仍然存在，但已经被限制在平台入口、路径 adapter 或 runtime launch 层，没有继续渗透到 tab、pane、block、search、launch config 或 audit snapshot 的核心模型里。

## 下一轮候选平台

1. Windows 桌面 spike
   - 目标：先验证 `NativePtyBackend.load()`、本地 shell、`ssh` binary、AppData 状态目录、菜单和快捷键映射。
   - 退出条件：能构建一个最小桌面 app，跑通单 tab 本地 shell 和 `session_restore.json` 落点。
2. Linux 桌面 spike
   - 目标：验证 XDG state 目录、字体度量、zsh hook、pane restore cwd 和 PATH completion。
   - 退出条件：能跑通 real shell smoke 的本地等价版本，并确认 `FT-012` 的上游缺口是否真实存在。
3. iOS / Android remote-only spike
   - 目标：只做远程 terminal、SSH / Ianvs 会话、安全上下文和触屏输入，不引入本地 shell 承诺。
   - 退出条件：给出移动端 transport abstraction、触屏交互稿和权限/剪贴板策略。

推荐顺序：`Windows -> Linux -> Mobile remote-only`。原因是当前产品已经有桌面级 tab / pane / menu / PTY 主线，Windows 的未知数最多但也最接近现有代码结构；移动端需要先收敛 transport 和触屏交互模型，不能直接沿用桌面假设。
