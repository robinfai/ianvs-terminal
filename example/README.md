# Ianvs Terminal application

`example/` 是工作区的产品应用和集成验收宿主，Flutter package 名保持为 `app`。
当前功能边界以 [Terminal Product Scope](../docs/TERMINAL_PRODUCT_SCOPE.md) 为准。

## 模块边界

| 路径 | 当前职责 |
| --- | --- |
| `lib/startup/`、`lib/app_bootstrap.dart` | 启动、平台准备、运行态组合与关闭 |
| `lib/features/shell/` | tab/pane 窗口壳、菜单、快捷键、搜索和录制入口 |
| `lib/features/sessions/` | 产品 Session 生命周期、Profile 启动和 shell integration |
| `lib/features/profiles/`、`lib/features/ssh/`、`lib/features/sftp/` | Profile 编辑、SSH 导入/认证及 SFTP 文件操作 |
| `lib/features/layout/` | 本机 Terminal Layout；重启意图只包含 Profile 引用和 cwd |
| `lib/features/recording/` | 当前格式的本机录制库、回放和搜索 |
| `lib/features/config/`、`lib/features/preferences/` | 快捷键、终端配置和应用偏好 |
| `lib/features/productivity/` | shell 提示标记、命令输出范围、搜索及最近命令/目录 |
| `lib/features/policies/` | 剪贴板、粘贴安全/历史、通知与热键窗口策略 |
| `lib/features/visual/` | 主题、布局模板、图形资产保存、scrollback 与诊断导出 |
| `lib/features/security/`、`lib/features/persistence/` | 主密钥管理及本机版本化文档边界 |
| `lib/data/`、`lib/persistence_repository_composition.dart` | 本地持久化组合及可选 API 配置同步 |
| `lib/platform/`、`lib/ui/`、`lib/l10n/` | 平台桥接、应用设计系统和本地化 |
| `test/`、`integration_test/` | 模块回归与真实平台验收 |

macOS 支持本地终端和 SSH；iOS 面向 SSH Session，并使用本地持久化。
API 是可选同步目标，不决定本地数据是否可用。Layout 和录制文件留在本机。
SSH 密钥迁移与不可解密密文保留用于保护已有用户数据；旧 Workspace 和旧录制
布局不再由运行时代码发现或迁移。Toolbelt 及其完成度诊断 UI 已退役，内部诊断
模型和用户诊断导出仍保留。

PTY FFI、终端 runtime、viewport、输入与选区共享实现来自
[ianvs_pty](../packages/ianvs_pty/README.md) 和
[ianvs_terminal](../packages/ianvs_terminal/README.md)，通过
`lib/features/pty/pty.dart` 和 `lib/features/terminal/terminal.dart` 接入。
第三方嵌入应用使用 [ianvs_terminal_core](../packages/ianvs_terminal_core/README.md)。

## 常用命令

从仓库根目录执行：

```bash
cd example
flutter analyze --fatal-infos
flutter test
flutter run -d macos
```

真实 PTY 和 iOS/跨设备同步验收入口见 [TESTING](../docs/TESTING.md) 与
[ACCEPTANCE](../docs/ACCEPTANCE.md)。原生库构建、签名与完整门禁由仓库根目录
Makefile 和 `tools/` 维护。
