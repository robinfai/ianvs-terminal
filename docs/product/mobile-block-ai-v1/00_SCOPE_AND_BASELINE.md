# 00 · 产品范围、基线与不可回退的合同

## 1. 产品目标

面向通过 iPhone 连接远程 Shell、阅读输出并借助 AI 完成终端任务的开发者。手机是首要优化端，iPad 与 macOS 为共享组件的适配和回归端。本轮不新增 Android 产品承诺。

核心任务是：**看清当前环境，提交明确意图，读懂执行结果，在需要时让 AI 介入，并始终知道谁拥有终端输入权。**

成功不是界面更“像 Warp”，而是核心闭环不再靠隐藏菜单、多个输入框、无文字状态图标来理解；错误、审批、执行结果未知时仍然可恢复、可追溯。

## 2. 已核验的代码基线

基线分支 `composer`，commit `763dc166bb1e56d6d50ed3379b57f366c9ca06b7`，提交信息 `fix(terminal): resolve AI and composer review regressions`，提交时间 `2026-10-08T02:25:26Z`。这些是文档编写基线，不是未来 Codex 完成后的版本。

| 事实 / 约束 | 本轮依据 | PRD 的处理 |
|---|---|---|
| 手机明确固定字号，系统字号跟随不在手机要求内 | [AGENTS.md](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/AGENTS.md) | 撤回前轮泛化的手机 Dynamic Type 要求；保留 VoiceOver、固定字号可读性和点击区域验收 |
| 手机末尾最多六行原生终端预览；查看全部进入分页阅读器 | [docs/command-blocks/WARP_COMMAND_BLOCKS_RESEARCH.md](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/command-blocks/WARP_COMMAND_BLOCKS_RESEARCH.md) | 沿用，不把末尾摘要改成丢失结构的 AI 文字替代品 |
| Block 输出仍由 TerminalViewport 渲染；完成块只读；原生 PTY 负责执行 | 同上 | 不改成普通 Text / Markdown 模拟终端输出 |
| 手机 AI 紧凑输入当前 `maxLines: compact ? 1 : 3` | [example/lib/features/ai/terminal_ai_workspace.dart](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/example/lib/features/ai/terminal_ai_workspace.dart) | S2 提供有高度上限的多行输入及独立展开编辑 |
| 本地 Codex ACP 是桌面能力，移动宿主与远程 ACP 网关未实现 | [docs/ai/ACP_BACKEND.md](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/ai/ACP_BACKEND.md) | 手机验收基于模型 API；桌面 ACP 回归单列 |
| 当前 active lane 是 runtime-contract-stability | [docs/CURRENT_EXECUTION_TARGET.md](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/CURRENT_EXECUTION_TARGET.md) | 不恢复旧 Toolbelt、不新增 IDE/项目容器或第二套终端运行时 |
| standalone 包由 canonical 来源生成 | [Makefile](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/Makefile) | 只改 canonical，然后 `make terminal-core-sync` 与 `make terminal-core-check` |

说明：仓库文档包含不同日期的阶段记录，某些旧段落仍写“iOS 不显示桌面 Composer”或早期 AI 未实现。不能据此否认当前代码的移动交互或 AI 能力。Codex 开始时必须重新核对最新入口、平台分支和调用关系；冲突记入 `results/BASELINE.md`，不能静默选择有利的记录。

## 3. 三个独立状态维度

| 维度 | 用户可理解的状态 | 不允许的混淆 |
|---|---|---|
| 显示内容 | Blocks / 原始终端 / 全屏输出阅读器 | 查看原始终端不等于输入已交给人 |
| 输入意图 | 自动识别 / 命令 / AI；自动时显示解析结果 | AI 标签不代表已允许它执行任何命令 |
| 执行控制 | 空闲 / AI 处理中 / 待审阅 / 已暂停 / 人工接管 / 回执未知 | 暂停 AI 不等于 Ctrl+C；Shell ready 不等于上一条成功 |

实现可保留现有枚举与控制器。这里是产品语义要求，不强制把所有枚举换名或合并成一个巨大 state machine。

## 4. 不可回退的合同（全阶段 P0）

1. **一个会话只有一个有效写入所有者。** AI、Composer、人手 raw 输入和密码/TUI 不可同时写入。只读观察不能隐式获取写权限。
2. **建议不等于执行。** 候选采用、历史采用、插回 Composer、AI 诊断草稿、设置保存、重新打开任务不会写 PTY。
3. **提交绑定目标和版本。** Session、SSH 节点、cwd、shell 租约、proposal revision、manual-input generation 的既有校验不能删减。
4. **回执未知禁止自动重发。** 连点、超时、重连、恢复任务不得生成第二次同一操作。先核对原 operation/submission receipt。
5. **AI 权限仍由宿主审阅。** 手工模式与 Smart 审阅保留。编辑命令使旧审批失效；本轮不引入“整个任务永久允许”。
6. **完成的输出不可写。** Block 阅读器只读、复制保留原始保留内容；淘汰/截断明确显示；跨页数据必须同一来源与版本。
7. **原始终端回退仍保守。** alternate screen、mouse reporting、特殊图像协议、无法归属的输出使用原始终端；能力恢复给明确按钮，不强制切回 Blocks。
8. **输入法优先。** composing 区间有效时，确认汉字的 Enter/Tab/方向键不得转成命令执行或候选采用。
9. **草稿和阅读位置按 Session / Task 隔离。** 本轮只承诺应用存活期间；不暗示进程被杀后仍可恢复内存会话。
10. **AI 上下文有限且可解释。** 使用已有受限读取、行范围、截断标识，不把整个文件系统或完整滚屏偷偷上传。
11. **数据默认不外传为“埋点”。** 性能和行为度量优先本地测试日志，不自动收集用户 Shell 内容、主机名、路径或提示词。
12. **不动无关产品域。** SSH 配置、录制、布局恢复、Profile、optional API sync 与现有授权边界保持。

## 5. 本轮明确不做

不新增云任务服务、远程 ACP 网关、无限历史、跨设备聊天同步、跨进程后台执行保证、Android 适配、AI 记忆服务、IDE 文件编辑器、远程文件补全 provider 或新的敏感数据扫描服务。示例中的主机/路径/命令均是测试 fixture，不要求产品硬编码。

## 6. 顺序与变更管理

S1 先建立行为闭环与基本语义样式；S2 统一输入和响应式；S3 收口完整视觉系统；S4 补齐真实平台验证。S4 的测试计划与日志设计从 S1 开始，不能最后才发现没有证据。

新需求必须有 `Sx-Rnn`；用例是 `Sx-Tnn`；设计是 `Dx-nn`；截图场景与用例一一对应。严重度：P0 为误执行、越权、错目标、丢关键数据；P1 为阻断核心流程/不可恢复/主操作不可达；P2 为不阻断的视觉和效率问题。

本 PRD 优先约束可见行为；需要改变现有安全/数据合同、支持平台或固定字号政策时，必须记录设计变更并由产品负责人确认，不能由 Codex 为“顺手优化”自行扩范围。
