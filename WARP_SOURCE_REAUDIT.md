# Warp 源码级全量复审

日期：`2026-05-03`

Warp 参考基线：

- 仓库：`https://github.com/warpdotdev/Warp.git`
- commit：`a5fde8f`
- 本机 checkout：`/private/tmp/warp-source-20260503`

Warp 文档基线：

- Legacy 语义参考：[Launch Configurations](https://docs.warp.dev/terminal/sessions/launch-configurations)
- 当前截图 UI 参考：[Tab Configs](https://docs.warp.dev/terminal/windows/tab-configs/)

说明：

- 当前沙箱不允许创建 `/Users/robinfai`，所以这轮源码级对比实际使用 `/private/tmp/warp-source-20260503`，没有落到 `AGENTS.md` 里写的 `/Users/robinfai/personal/warp`。
- Warp 官方文档在 `2026-04-30` 已把 `Launch Configurations` 标记为 legacy，并把日常保存入口转向 `Tab Configs`。但 Ianvs 当前要补的是“应用窗口导出”，对应的语义仍更接近 Warp 源码里的 `launch_configs/save_modal.rs` 和 `launch_config.rs`。
- 因为你新增了“应用导出截图与 Warp 文档截图 UI 一致性达到 80% 水准”的要求，所以本文把 benchmark 拆成两层：
  - 语义 benchmark：Warp `LaunchConfig::from_snapshot` 的 app-level snapshot。
  - 视觉 benchmark：Warp 当前官方文档 `Tab Configs` 截图的入口、层级和主按钮风格，再结合本地 `LaunchConfigSaveModal` 源码。

## 总结

- Ianvs 当前 `M0 -> M6` 按原里程碑定义仍可保持 `done`，已有 widget / smoke / build 验证不需要回滚。
- 但如果目标提高到“功能基本对齐 Warp”，当前仓库还不能宣称已经达到。
- 这轮全量复审后，必须计入的缺口共有五组：
  - `M7A` 多窗口运行时与应用窗口导出
  - `M7B` 导出 UI 对齐与截图验收
  - `M7C` block 呈现层与终端内分组
  - `M7D` 命令搜索与会话导航范围
  - `M7E` 桌面端端到端验证基线
- 另有一组次级差距需要记录但不阻塞当前 M7 主线：
  - 会话设置面仍明显窄于 Warp，尤其是 `new session shell`、`startup shell`、`working directory per source`。

## 逐段复审

### M0 到 M1：本地终端基线

Ianvs 证据：

- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:21) 已覆盖 flutterm-backed shell surface 启动。
- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:605) 已覆盖查找与结果跳转。
- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:1803) 已覆盖平台菜单。
- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:2341) 已覆盖多 tab 基础行为。
- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:2847) 已覆盖设置面板。
- [real_shell_smoke_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/real_shell_smoke_test.dart:24) 到 [real_shell_smoke_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/real_shell_smoke_test.dart:208) 已覆盖真实 shell、退出码、查找复制、多 tab、多 pane。

结果：

- `基本满足 Ianvs 当前基线目标`。
- 这部分不需要重开。
- 但它仍是“单窗口产品壳”。Ianvs 当前没有 `New Window` 行为，也没有窗口级控制器，所以后续 app-level export 不能只当作 launch-config schema 扩展。

### M2：block 能力

Warp 证据：

- [block.rs](/private/tmp/warp-source-20260503/app/src/terminal/model/block.rs:286) 的 `Block` 直接持有 prompt、command、output、cwd、session_id、banner、prompt snapshot、filter query 等状态。
- [block.rs](/private/tmp/warp-source-20260503/app/src/terminal/model/block.rs:617) 的 `BlockState` 区分 `BeforeExecution`、`Executing`、`DoneWithExecution`、`Background`、`Static` 等多种生命周期。
- [block.rs](/private/tmp/warp-source-20260503/app/src/terminal/model/block.rs:644) 的 `BlockMetadata` 把 session 和 cwd 绑定进 block 模型。
- [blocks.rs](/private/tmp/warp-source-20260503/app/src/terminal/model/blocks.rs:135) 的 `BlockHeightItem` 直接支持 restored separator、inline banner、subshell separator、rich content。
- [blocks.rs](/private/tmp/warp-source-20260503/app/src/terminal/model/blocks.rs:239) 的 `BlockList` 是终端滚动与渲染模型的一部分，不是额外的侧边 controller。

Ianvs 证据：

- [terminal_blocks.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/terminal_blocks.dart:22) 的 `TerminalBlock` 目前只保留 `id`、`sessionId`、`commandText`、`outputText`、`status`、`scrollbackOffset`、`recordedAt`、`targetEnvironment`。
- [terminal_blocks.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/terminal_blocks.dart:66) 的 `TerminalBlocksController` 主要负责跳转、复制和 reinput。
- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:871) 到 [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:1037) 覆盖的是 block history panel 和 toolbar 行为。

结果：

- `不满足 Warp 基本对齐要求`。
- Ianvs 已有 block 事件和 block 历史面板，但还不是 Warp 那种“终端内容本身按 block 组织”的产品层级。
- 后续整改不能只补更多 block 字段，必须补终端内分组、分隔和 active block 呈现。

### M3：现代输入、命令搜索和补全

Warp 证据：

- [terminal.rs](/private/tmp/warp-source-20260503/app/src/terminal/input/terminal.rs:173) 到 [terminal.rs](/private/tmp/warp-source-20260503/app/src/terminal/input/terminal.rs:290) 的 terminal input 已把 `slash commands`、`prompts`、`conversation`、`skills`、`inline history`、`repos` 放进统一输入菜单。
- [command_search/mod.rs](/private/tmp/warp-source-20260503/app/src/search/command_search/mod.rs:1) 到 [command_search/mod.rs](/private/tmp/warp-source-20260503/app/src/search/command_search/mod.rs:10) 同时挂了 `history`、`projects`、`workflows` 等来源。
- [navigation/search.rs](/private/tmp/warp-source-20260503/app/src/search/command_palette/navigation/search.rs:89) 到 [navigation/search.rs](/private/tmp/warp-source-20260503/app/src/search/command_palette/navigation/search.rs:230) 的 session navigation 会把 prompt、最近命令和 hint text 一起做 fuzzy search。

Ianvs 证据：

- [command_history.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/command_history.dart:38) 到 [command_history.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/command_history.dart:253) 的命令搜索只合并当前 block 历史和本地 saved commands。
- [saved_commands.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/saved_commands.dart:8) 到 [saved_commands.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/saved_commands.dart:149) 的保存命令库当前只是字符串列表，不带 workflow 结构。
- [workspace_search.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/workspace_search.dart:6) 到 [workspace_search.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/workspace_search.dart:217) 只搜索当前窗口里已经打开的 tab/pane。
- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:1110) 到 [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:1303) 已证明 Ianvs 当前命令搜索是“当前 tab 历史 + saved commands”的 MVP。

结果：

- `部分满足`。
- 现代输入、raw 切换、括号补全和 Fig specs completion 的 MVP 已经有了，但“命令搜索”和“会话导航”范围还明显窄于 Warp。
- 这里的整改重点不该是继续打磨单个补全规则，而是把搜索源和导航对象做成更完整的 palette。

### M4：pane、restore、workspace、launch config

Warp 证据：

- [launch_config.rs](/private/tmp/warp-source-20260503/app/src/launch_configs/launch_config.rs:15) 到 [launch_config.rs](/private/tmp/warp-source-20260503/app/src/launch_configs/launch_config.rs:40) 的 `LaunchConfig` 顶层直接是 `active_window_index + windows[]`。
- [launch_config.rs](/private/tmp/warp-source-20260503/app/src/launch_configs/launch_config.rs:92) 到 [launch_config.rs](/private/tmp/warp-source-20260503/app/src/launch_configs/launch_config.rs:140) 的 pane template 还支持 per-pane commands、shell override 和 pane mode。
- [save_modal.rs](/private/tmp/warp-source-20260503/app/src/launch_configs/save_modal.rs:94) 到 [save_modal.rs](/private/tmp/warp-source-20260503/app/src/launch_configs/save_modal.rs:265) 的 `LaunchConfigSaveModal` 直接从当前 app state 做 snapshot。
- [integration_testing/mod.rs](/private/tmp/warp-source-20260503/app/src/integration_testing/mod.rs:20) 到 [integration_testing/mod.rs](/private/tmp/warp-source-20260503/app/src/integration_testing/mod.rs:38) 已把 `launch_configs`、`navigation_palette`、`pane_group`、`window`、`workspace` 独立成模块。

Ianvs 证据：

- [terminal_tabs_controller.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/terminal_tabs_controller.dart:174) 到 [terminal_tabs_controller.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/terminal_tabs_controller.dart:181) 的 `currentLaunchConfiguration()` 只导出当前 `TerminalTabsController` 的 tabs。
- [terminal_tabs_controller.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/terminal_tabs_controller.dart:332) 到 [terminal_tabs_controller.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/terminal_tabs_controller.dart:364) 的 `applyLaunchConfiguration()` 只恢复单窗口 tabs/panes。
- [launch_config.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/launch_config.dart:9) 到 [launch_config.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/launch_config.dart:95) 顶层只有 `activeTabIndex` 和 `tabs`。
- [main.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/main.dart:3520) 到 [main.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/main.dart:3703) 当前 `Launch Config` UI 仍是手填路径的 `AlertDialog`。
- [main.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/main.dart:523) 到 [main.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/main.dart:667) 平台菜单没有 `New Window` 或窗口级管理入口。
- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:1873) 只验证单窗口 workspace file 的保存 / 回放。

结果：

- `pane / restore 基础可用，但 launch config 与窗口层明显不足`。
- 这里至少有三层缺口：
  - 没有多窗口运行时。
  - 没有 app-level export/import。
  - 当前导出 UI 与 Warp 文档 / 源码的交互层级差距很大。

### M5：SSH 会话与会话设置

Warp 证据：

- [ssh/mod.rs](/private/tmp/warp-source-20260503/app/src/terminal/ssh/mod.rs:1) 到 [ssh/mod.rs](/private/tmp/warp-source-20260503/app/src/terminal/ssh/mod.rs:10) 表明 Warp 的 SSH 已经进入更重的 remote-native 模块。
- [new_session_shell.rs](/private/tmp/warp-source-20260503/app/src/terminal/session_settings/new_session_shell.rs:23) 定义了 `NewSessionShell`。
- [startup_shell.rs](/private/tmp/warp-source-20260503/app/src/terminal/session_settings/startup_shell.rs:13) 定义了 `StartupShell`。
- [working_directory_config.rs](/private/tmp/warp-source-20260503/app/src/terminal/session_settings/working_directory_config.rs:112) 开始定义按 `SplitPane / Tab / Window` 区分的工作目录策略。

Ianvs 证据：

- [session_launch.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/session_launch.dart:9) 到 [session_launch.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/session_launch.dart:78) 当前 SSH launch 只是把 program 改写成 `ssh` 并传 `authority`。
- [terminal_tabs_controller.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/terminal_tabs_controller.dart:206) 到 [terminal_tabs_controller.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/terminal_tabs_controller.dart:227) 当前只支持新建本地 `ssh` command tab。
- [terminal_settings.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/terminal_settings.dart:57) 到 [terminal_settings.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/lib/src/terminal_settings.dart:215) 目前设置面只覆盖字体、字号、主题和一个 `defaultShell`。

结果：

- `SSH 当前口径可接受，但设置面明显更窄`。
- remote-native SSH、warpify、网关或远端文件能力不计入 Ianvs Terminal 当前必做范围。
- 但会话设置 breadth 仍应记为次级差距，否则后续多窗口和导出能力会持续受限于“所有 session 共享一个 default shell”的简单模型。

### M6：验证体系

Warp 证据：

- [integration_testing/mod.rs](/private/tmp/warp-source-20260503/app/src/integration_testing/mod.rs:5) 到 [integration_testing/mod.rs](/private/tmp/warp-source-20260503/app/src/integration_testing/mod.rs:38) 直接拆出 `terminal`、`pane_group`、`launch_configs`、`navigation_palette`、`window`、`workspace` 等 app-level harness。

Ianvs 证据：

- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:1459) 已覆盖 shell hook block 流。
- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:1873) 已覆盖 launch config MVP。
- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:2160) 已覆盖 workspace search。
- [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:2513) 与 [widget_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/widget_test.dart:2685) 已覆盖 pane 和 restore。
- [real_shell_smoke_test.dart](/Users/luobinghui/projects/flutter/ianvs/ianvs-terminal/test/real_shell_smoke_test.dart:317) 之后还覆盖了 restore、prompt、zsh blocks、completion、SSH smoke。

结果：

- `现有验证很有价值，但方法层不对齐`。
- Ianvs 现在的问题不是“没有测试”，而是“没有可复用的桌面端 app-level E2E harness”。
- 只靠 widget + real-shell smoke，后续多窗口 / app-export / UI benchmark 会越来越难维护。

## 必须进入整改的待办

### M7A：多窗口运行时与应用窗口导出

- 先补产品侧窗口集合模型和窗口创建 / 激活 / 关闭入口，再谈 app-level export。
- launch config 顶层从 `activeTabIndex + tabs[]` 升级为 `activeWindowIndex + windows[]`。
- 导出 / 导入要覆盖窗口内 tab、pane、cwd、startup command、session metadata、launch profile。

### M7B：导出 UI 对齐与截图验收

- 当前 Ianvs 是手填路径的 `AlertDialog`，与 Warp 文档截图和 `LaunchConfigSaveModal` 交互层级差距过大。
- UI benchmark 采用：
  - 语义：Warp legacy `Launch Configurations` 的 app snapshot 流程。
  - 视觉：Warp 当前 `Tab Configs` 文档截图的入口、层级、命名输入和主按钮风格。
- 验收新增一条硬条件：Ianvs 导出 UI 截图与 Warp 文档对应截图达到约 `80%` 一致度，重点看布局层级、主 CTA、信息密度和保存成功反馈；不要求品牌素材或文案逐字复制。

### M7C：block 呈现收口

- 把 block 从“旁路历史面板”提升到“终端内可感知的内容分组”。
- 至少补齐 active block 呈现、block divider / separator、复制输出定位与 restore 后的 block 可视一致性。
- 不要求复制 Warp 的 AI block、rich content 或 cloud pane，但必须达到“命令和输出确实按 block 组织”的产品感知。

### M7D：命令搜索与会话导航收口

- 把当前 “saved + current-tab history” 扩成更像 palette 的统一搜索入口。
- 至少补齐：
  - 会话导航
  - 更宽的 workspace / project 维度搜索
  - 可继续扩展到 workflow-like 保存命令结构的 schema
- 这一阶段不要求把 Warp 的 AI queries、repos、skills 全搬进来。

### M7E：桌面端端到端验证基线

- 建立桌面端 E2E harness，统一封装 window、tab、pane、launch config、session context、SSH、workspace search 动作与断言。
- 首批必须覆盖：
  - 新建两个窗口并切换 active window
  - app-level export / destroy / re-apply
  - 导出 UI 成功反馈
  - pane / restore / workspace search
  - SSH command session 创建、metadata 更新、restart

## 次级差距

- 会话设置 breadth 仍明显窄于 Warp。
- 当前先记为 `secondary backlog`，不阻塞 M7A 到 M7E 的先后顺序。
- 等 app-level export 与 E2E 基线收口后，再决定是否单独立项做 `new session shell`、`startup shell`、`working directory per source`。
