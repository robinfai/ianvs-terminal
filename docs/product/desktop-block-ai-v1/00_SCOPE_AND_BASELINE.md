# 00 · 桌面范围、基线与不可回退合同

> 2026-10-10 修订：与本文有关的敏感性、补充要求、收起/Esc、人工编辑保存和未知结果出口，统一以 [v1.1 交互修订](16_REVISION_1_1.md) 为准。原有 64 项需求及全部原生验收门槛保留。


## 1. 产品目标

服务键盘、鼠标/触摸板为主的桌面终端工作：频繁编写和修正命令、同时操作多个 Session、阅读大输出、调用 AI 诊断/执行受审阅动作，以及随时退回真实 TUI。让用户一直看清“我在哪个目标、正在编辑什么、这次 Enter 做什么、谁可以写入 PTY”。

范围是现有 `composer` 分支完善；不是从零重造 Warp，也不是新 IDE、项目容器或永久多侧栏工作台。顶部单层窗口控制/Terminal tabs/新增按钮、底部状态栏、现有三层 Dock 都保留；AI 工作用任务视图描述，代码里的 workspace 类名不代表新增 Project Workspace。

## 2. 已核验基线与证据级别

本轮通过已连接 GitHub 核对分支 HEAD 为 [763dc166bb1e56d6d50ed3379b57f366c9ca06b7](https://github.com/robinfai/ianvs-terminal/commit/763dc166bb1e56d6d50ed3379b57f366c9ca06b7)，提交信息 `fix(terminal): resolve AI and composer review regressions`，时间 `2026-10-08T02:25:26Z`。这是编写时基线，不是未来交付源码。没有运行产品，因此下述是源码/文档事实，不是本轮现场视觉缺陷复现。

|基线事实|来源|本PRD处理|
|---|---|---|
|macOS 是当前主交付平台；Profile/Session/Layout/Recording是产品对象|[产品范围](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/TERMINAL_PRODUCT_SCOPE.md)|不新增项目容器/云会话/第二套持久化|
|多tab、split pane是核心终端行为；Linux/Windows声明仍依赖原生证据|[执行目标](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/CURRENT_EXECUTION_TARGET.md)|D2强化多窗格；D4平台声明分开|
|桌面已选三层Dock、主题tokens、候选/详情与焦点约束|[Composer重设计](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/composer/COMPOSER_REDESIGN.md)|保留已选方向，不把历史已修复问题再当缺陷|
|桌面Block默认整体高度≤所在终端内容区1/3|[Blocks文档](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/command-blocks/WARP_COMMAND_BLOCKS_RESEARCH.md)|按pane计算，支持内部滚动与手动展开|
|输出继续TerminalViewport；TUI和特殊输出保守Raw回退|[Blocks文档](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/command-blocks/WARP_COMMAND_BLOCKS_RESEARCH.md)|不改成普通文本假终端|
|API与本地Codex ACP共存；ACP的进程在桌面本地，即使目标是SSH|[ACP文档](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/ai/ACP_BACKEND.md)|两条验收路径独立；不加远程ACP网关|
|手机固定字号；非手机仍需文字缩放检查|[AGENTS](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/AGENTS.md)|桌面1/1.5/2，不能继承手机clamp|
|canonical生成standalone；完整gate是make verify|[Makefile](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/Makefile)|只改源再同步，聚焦测试不替代完整gate|

仓库文档是分阶段历史，文中的“当前未实现AI”等早期语句必须与最新调用路径核对。文档不一致写入BASELINE，不能选择对验收最有利的段落。

## 3. 不同于手机版

|维度|桌面本包|移动包|
|---|---|---|
|主要输入|实体键盘、鼠标、触摸板；作用域快捷键|触控与系统软键盘|
|布局|单层window chrome、每pane Dock、底部状态栏|手机单栏、紧凑输入|
|Block输出|H/3上限、内外两层滚动、手动展开|末尾六行、单纵向列表+Reader|
|审批|可完整行内审阅；长/窄使用审阅层|手机优先独立全屏审阅|
|上下文|Cmd/Shift多选、文本范围、情境菜单|触控可达与精简动作|
|AI后端|模型API + 本地ACP分别验收|模型API为基础，不冒充本地ACP|
|窗口|分屏、tab、失活、DPI、外接显示器|横竖屏、键盘遮挡、锁屏|
|文字|支持桌面缩放和原生字体验证|固定UI字号，主动终端字号能力仍保留|

16:9用于设计稿与标准验收视口，不强制产品窗口比例。保留可自由resize的原生桌面行为。

## 4. 状态维度不能合并

显示形式（Blocks/任务/Raw/Reader）、输入意图（Auto/Command/AI）、任务阶段（分析/审阅/执行/暂停等）、当前输入所有权（无/人工/单次获批Agent操作）分别管理。连接状态、Shell就绪、命令退出和AI完成也不是一个状态。UI显隐不是授权逻辑。

## 5. 全阶段不可回退

1. 每Session同一时刻只有一个有效人工输入归属；Agent只按当前单次授权写。不同Session可并行，不给同PTY新增竞争写通道。
2. 放入草稿、采用候选/历史、打开诊断、保存设置、查看证据均不隐式提交。普通命令不依赖LLM。
3. 提交继续检查Session、SSH节点、cwd、shell lease、manual-input generation、proposal revision与operation identity。编辑/接管/换目标使旧授权失效。
4. 未知回执先检查，不自动重发；accepted操作计数与受控副作用是一次性判断口径，不是write系统调用次数。
5. 已完成Block和observer只读；终端原始输出、ANSI、分页和保留预算不丢。截断/淘汰明示。
6. TUI、mouse report、特殊图像和未归属输出保守回退；只读覆盖层不偷偷改变TUI几何。支持恢复时由用户手动回Blocks。
7. 草稿、来源、selection、reading anchor按Session/Task隔离；晚到结果不能清新稿，后台回复不能抢焦点。
8. Profile/Layout/Relaunch/Recording与optional sync不变；重启恢复是新PTY，不伪装恢复死进程。
9. 不恢复退役Toolbelt、旧ABI、旧workspace/IDE能力；不扩大ACP工具权限，不自动安装/登录模型工具。
10. 数据测试使用隔离fixture；截图/日志不得包含真实密钥、密码、私人目录与用户提示词。

## 6. 成功指标和实施顺序

失败块到诊断草稿一步可达；准备草稿零模型起始请求、零有效提交；一次批准最多一个有效operation；错目标/越权零容忍。键盘主路径可完成；回看时新输出不抢锚点。响应式、视觉、性能阈值为本轮需求目标，不是当前实测成绩。

D1先行为，D2再键鼠/布局，D3统一视觉，D4原生验收。测试与证据采集从D1开始，不最后补图。各阶段允许独立组件工作并行，但同一控制器、owner逻辑和生成镜像须明确负责人。

## 7. 非目标与变更流程

不新增Android、移动后台保证、云同步聊天、远程ACP、无限历史、永久任务权限、IDE Explorer/Git面板、模型记忆、统一SSH broker、多客户端PTY或新的远端补全。Linux/Windows已有host则按真实范围验证，不借这份PRD从零移植。

安全/数据/平台合同改变须独立设计决策，不得为美观删除保护。新需求记录编号与原因；已实现部分标“保留+回归”，未验证标“需证据”。阶段编号D1–D4不等于严重度：P0执行/数据安全，P1阻断核心流程，P2非阻断体验。
