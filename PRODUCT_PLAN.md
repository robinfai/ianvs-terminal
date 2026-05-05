# Ianvs Terminal 产品规划

## 产品定位

Ianvs Terminal 是 Ianvs 产品族下的现代终端客户端。它以 terminal 为核心，面向本地开发、SSH 会话、项目工作区和远程排障场景。

本项目以 Warp 的 terminal 体验作为功能参考，重点学习 blocks、现代输入编辑、命令搜索、补全、会话管理和启动配置。Warp 只是参考目标，不作为 fork、复刻对象或兼容承诺。

Ianvs Terminal 的 terminal 实现当前通过 path dependency 解析到 `/Users/luobinghui/projects/flutter/flutterm`。产品侧负责窗口、tab、pane、block、命令搜索、启动配置和 Ianvs 安全访问上下文；底层 PTY、终端渲染、输入编码、选区、滚动和基础搜索优先交给 `flutterm_terminal`。如果发现 flutterm 的 bug 或缺少能力，先记录到 `FLUTTERM_FEEDBACK.md`，再决定是否推动上游修改。

客户端开发框架固定为 Flutter。macOS 是首要目标平台，优先完成桌面端窗口、菜单、快捷键、PTY 打包和日常 terminal 体验。Windows 和 Linux 保留桌面适配目标，iOS 和 Android 保留移动端适配目标；跨平台适配要作为架构边界保留，但不抢占 macOS 首版交付。

参考资料：

- [Warp Blocks](https://docs.warp.dev/terminal/blocks)
- [Warp Universal Input](https://docs.warp.dev/terminal)
- [Warp Modern Text Editing](https://docs.warp.dev/terminal/editor)
- [Warp Completions](https://docs.warp.dev/terminal/command-completions/completions)
- [Warp Session Management](https://docs.warp.dev/terminal/sessions)
- [Warp Launch Configurations](https://docs.warp.dev/terminal/sessions/launch-configurations)

本地功能参考入口：`../../warp/app/src/terminal/`、`../../warp/app/src/pane_group/`、`../../warp/app/src/launch_configs/` 和 `../../warp/app/src/integration_testing/`。当前本机 Warp 源码基线是 `../../warp` 的浅克隆，最新复审见 `WARP_SOURCE_REAUDIT.md`。

## 客户端与平台策略

- 客户端框架：Flutter。
- 首要目标：macOS 桌面端。
- 保留适配：Windows、Linux、iOS、Android。
- 桌面端优先能力：本地 shell、PTY、系统剪贴板、窗口菜单、快捷键、tab、pane、项目启动配置。
- 移动端预留能力：远程 terminal、SSH / Ianvs 会话、触屏输入、安全上下文展示。
- 平台差异通过适配层处理，不把 macOS 专属行为写进产品核心模型。
- iOS / Android 不提前承诺本地 shell；移动端首要价值是安全远程会话，而不是复制桌面 terminal 的全部能力。

## 目标用户

- 开发者：需要稳定的本地终端、项目工作区和命令复用。
- 运维工程师：需要管理多台机器、多组 SSH 会话和排障命令。
- 安全工程师：需要在访问生产环境时保留身份、会话和审计上下文。
- 需要安全远程访问生产环境的人：需要清楚知道当前身份、目标环境和操作上下文。

## 核心场景

- 本地开发终端：运行 shell、编辑命令、查看输出、复制结果。
- SSH 会话：连接远程机器，并保持接近本地终端的输入和输出体验。
- 项目工作区：按项目恢复 tab、pane、目录和启动命令。
- 命令复用：搜索历史命令，重新输入常用命令，保存项目启动命令。
- 输出整理：把命令和输出成组，复制命令、复制输出，定位失败命令。
- 远程排障：在多个环境之间切换，保留会话上下文，减少误操作。

## 功能规划

### P0：基础终端能力

- PTY 会话创建、输入、输出、调整大小和关闭。
- 终端渲染、滚动、光标、选择、复制和粘贴。
- 基础键盘输入、快捷键和鼠标选择。
- 单窗口多 tab。
- 最小本地设置：字体、字号、主题预设和默认 shell。
- macOS 菜单入口和启动 prompt 稳定性验收。
- macOS 桌面端可日常使用。
- Flutter 应用骨架保留 Windows、Linux、iOS、Android 的适配空间，但 P0 不要求这些平台可用。

### P1：blocks

- 将一次命令和对应输出整理成一个 block。
- 支持复制命令、复制输出、复制命令和输出。
- 支持把历史命令重新放回输入区。
- 显示命令完成状态，失败命令要有清晰标记。
- 支持快速跳到某个 block 的开始位置。

### P2：现代输入编辑

- 输入区支持软换行和多行编辑。
- 支持括号、引号的基础补全。
- 支持命令历史浏览。
- 支持命令搜索，覆盖历史命令和保存的命令。
- 支持基础补全，优先覆盖命令名、路径和常见参数。

### P3：会话组织

- 支持 split panes。
- 支持关闭后恢复窗口、tab 和 pane。
- 支持 launch configuration，用文件保存项目启动布局。
- 支持项目启动模板，包括目录、tab、pane 和启动命令。
- 支持在会话之间快速搜索和跳转。

### P4：Ianvs 安全访问预留

- SSH 会话显示会话标签，例如目标主机、账号、环境和项目。
- 显示身份上下文，例如当前登录身份、授权来源和会话有效期。
- 预留审计导出接口，用于记录命令、输出摘要、时间和目标环境。
- 只做 Ianvs Terminal 内的展示和接口预留，不实现网关。

### P5：跨平台适配预留

- Windows / Linux：保留桌面端窗口、菜单、快捷键、PTY 启动和路径差异的适配层。
- iOS / Android：保留远程 terminal、SSH / Ianvs 会话、触屏输入和安全上下文的适配层。
- 统一产品模型：tab、pane、block、命令搜索、会话标签和审计接口不绑定某一个平台。
- 不在 macOS 首版中实现全平台交付，只保证架构不主动堵死后续适配。

## 非目标

- 不做 AI 网关。
- 不做零信任网络控制面。
- 不做接入客户端。
- 不做虚拟网络。
- 不做流量网关。
- 不做 SSH 网关。
- 不做管理后台。
- 不做云端 block 分享。
- 不承诺 Warp 插件兼容。
- macOS 首版不交付 Windows、Linux、iOS、Android 可用版本。
- iOS / Android 不承诺本地 shell。

## 成功标准

- macOS 版本可以替代日常本地终端使用。
- macOS 版本可以替代日常 SSH 终端使用。
- 命令查找比传统终端更快。
- 命令输出更容易复制、复用和定位。
- 多会话管理比单纯 tab 更清楚。
- 代码和产品模型为 Windows、Linux、iOS、Android 留出适配空间。
- 后续可以和 Ianvs 其他子项目对接，但不会把网关或控制面逻辑放进本项目。

## 推进文档

- [MILESTONES.md](MILESTONES.md)：当前里程碑顺序和完成条件。
- [FLUTTERM_FEEDBACK.md](FLUTTERM_FEEDBACK.md)：Ianvs Terminal 对 flutterm 的反馈入口。
- [PLATFORM_MATRIX.md](PLATFORM_MATRIX.md)：M6 跨平台适配矩阵、adapter inventory 和下一候选平台。
