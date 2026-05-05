# Ianvs Terminal 项目规则

## 产品身份

- 产品名固定为 `Ianvs Terminal`。
- 目录名固定为 `ianvs-terminal`。
- 本项目只承载 terminal 产品，不承载 Ianvs 产品族里的其他子项目。

## 范围

本项目可以包含：

- PTY 会话
- 终端渲染
- 输入编辑
- 会话、tab、pane
- block
- 搜索
- 补全
- 启动配置
- SSH 会话里的终端体验

本项目不实现：

- 零信任接入客户端
- 虚拟网络
- 流量网关
- SSH 网关
- AI 网关
- 管理后台

这些能力可以作为其他 `ianvs-*` 子项目存在。Ianvs Terminal 只保留必要的展示、调用或对接位置。

## 技术参考

- Ianvs Terminal 客户端使用 Flutter 开发。
- Ianvs Terminal 当前工作树的 path dependency 解析到 `/Users/luobinghui/projects/flutter/flutterm`，并以这份本地 checkout 作为 terminal 实现依赖库。
- 首选依赖 `flutterm_terminal` 承载 terminal runtime、viewport、输入编码、选区、滚动和基础搜索。
- `flutterm_pty` 可以作为直接 path dependency，但产品层只允许用于 `NativePtyBackend.load()`；不要绕过 `flutterm_terminal` 重新实现 terminal 能力。
- 初期可以使用本地 path dependency。是否发布、版本化或搬迁 flutterm，要另写决策文档。
- 不复制 flutterm 源码，不在 Ianvs Terminal 内做 flutterm 的影子实现。
- 发现 flutterm 的 bug、限制或缺少能力时，先写到 `FLUTTERM_FEEDBACK.md`，记录复现、期望行为、影响里程碑、候选上游包和当前绕行方式。
- 只有用户明确要求修改 flutterm 时，才进入 `/Users/luobinghui/projects/flutter/flutterm` 改代码；否则只在 Ianvs Terminal 里记录需求和影响。
- 产品命名和面向用户的文案不把 Flutter 当卖点；技术文档要明确 Flutter 是客户端框架。
- macOS 是首要目标平台。窗口、菜单、快捷键、PTY 打包和桌面交互先按 macOS 打磨。
- macOS 本地 PTY 需要启动 `/bin/sh` 或用户默认 shell。`macos/Runner/DebugProfile.entitlements` 和 `macos/Runner/Release.entitlements` 不能打开 `com.apple.security.app-sandbox`；修改 entitlements 后必须跑 `test/macos_entitlements_test.dart` 和真实 shell smoke。
- Windows 和 Linux 保留桌面适配目标；iOS 和 Android 保留移动端适配目标。跨平台代码要避免把 macOS 专属行为写死在产品层。
- 平台相关能力要通过清晰适配层进入产品，例如窗口管理、菜单、系统剪贴板、文件路径、PTY / SSH 会话启动、快捷键和权限。
- iOS / Android 的本地 shell 能力不要提前承诺。移动端优先保留远程 terminal、SSH / Ianvs 会话、触屏输入和安全上下文的适配空间。

## 功能参考

`../../warp` 只作为 terminal 功能标杆，重点参考：

- blocks：命令和输出成组。
- 现代输入编辑：多行输入、软换行、括号补全、复制粘贴。
- 命令搜索：搜索历史命令、保存的命令和工作流。
- 补全：命令、参数、路径和常用工具补全。
- 会话恢复：恢复窗口、tab 和 pane。
- tab / pane：多会话组织。
- launch configuration：保存并恢复项目启动布局。

不要复制 Warp 的品牌、素材、文案、云服务形态或私有实现。文档里应写“参考 Warp 的某类能力”，不要写“兼容 Warp”或“复刻 Warp”。

本地代码阅读优先入口：

- terminal 主体：`../../warp/app/src/terminal/`
- block 模型：`../../warp/app/src/terminal/model/block.rs` 和 `model/blocks.rs`
- 输入区：`../../warp/app/src/terminal/input/`
- 命令搜索：`../../warp/app/src/search/command_search/` 和 `search/command_palette/`
- pane 与会话组织：`../../warp/app/src/pane_group/`
- 启动配置：`../../warp/app/src/launch_configs/`
- 对应验收参考：`../../warp/app/src/integration_testing/`

## 产品推进文档

- `PRODUCT_PLAN.md` 写产品定位、用户、场景和长期方向。
- `MILESTONES.md` 写当前推进顺序、每个里程碑的完成条件和依赖风险。
- `FLUTTERM_FEEDBACK.md` 写 Ianvs Terminal 对 flutterm 的 bug 反馈和 feature 需求。
- `MANAGER_TASK_BOARD.md` 写 manager-only 多 agent 推进的 lane、triage、watchdog、verification 和 open blockers。
- 每次开始新里程碑或新一轮 manager-only rollout 前，先读这些文档，再决定是否需要补充任务文档。

## 多 Agent 推进

- 主 agent 只负责推进进度、维护 `MANAGER_TASK_BOARD.md`、分派 scope、监控卡死、收敛问题和安排下一轮路由；默认不直接改业务代码、不亲自做 review。
- 子 agent 的回报格式固定为：`done`、`blocked`、`needs-manager` 三选一，并附 `涉及文件`、`执行过的检查`、`剩余风险`。
- 问题标签固定使用：`BASELINE`、`SESSION`、`UI`、`INPUT`、`COMPLETION`、`INTEGRATION`、`UPSTREAM-BLOCKED`。
- 写集固定分为 `core/session`、`workspace/ui`、`input/command`。一个写入 owner 只负责一组写集，避免交叉改同一批文件。
- 常态化分组固定为：`Baseline Lane`、`Session/UI Fix Lane`、`Input/Command Fix Lane`，以及 `Fresh Core Review`、`Fresh Workspace Review`、`Fresh Command UX Review`。
- fresh review 组不复用实施组结论，直接按 `README.md` 与 `MILESTONES.md` 的验收点从头核对已完成功能。
- watchdog 固定为：子 agent 在 `15 分钟` 或 `8 次工具动作` 内必须产出有效进展；超时后主 agent 先 `interrupt` 索取部分结果，再超时 `10 分钟` 仍无有效进展则关闭并拆成更小 scope 重派。
- 真实 shell smoke 在当前工作树里默认视为两段式验证：先确认 dylib 导出当前绑定需要的符号；若 native / Dart 侧基线失配，则在 `MANAGER_TASK_BOARD.md` 与 `FLUTTERM_FEEDBACK.md` 记录为 `UPSTREAM-BLOCKED`，不把它误判为 Ianvs Terminal 产品层回归。
