# 10 · 必交截图逐帧清单与审阅约定

本文件把 07 的“每个场景要交截图”进一步落实到**具体可见状态**。阶段功能仍由 01–04 约束；本文件不要求新增产品页面。`Fnn` 是证据帧编号，不是新的产品需求。

## 如何执行

先运行实际产品，走 07 的 Given/When/Then；在下面指定时点保存完整原始 PNG。文件名可调整，但 screenshot artifact 必须用 `shot_ids` 绑定本文件 ID。每帧应保留顶部环境、完整内容布局和底部动作/键盘；超长审阅要分别记录首尾。每个通过用例仍需日志，动态场景仍需连续录屏。**静态图片从来不能证明没写 PTY、没重复执行或没丢草稿。**

S1–S3 的可见改动还需同设备、同主题、同数据的 before 对比；新功能不存在时，before 拍“缺少入口”的真实现状，不编造旧功能。before 独立存 baseline 清单，不计 after 帧。

一个原图可以满足多个真正同时可见的检查点，但必须在 `description`、`reuse_reason` 和 results 段落说明。不能用一张图证明不同时刻（未发送/已发送）、不同主题、横竖屏或不同设备。不要为了达到数量复制同一图片并改名。数量是覆盖约束，不是绩效指标。

## 元数据增量

在 06 的 screenshot artifact 上增加：

```json
{"shot_ids":["S1-T01-F01"],"keyboard":"hidden","description":"真实拍摄时观察到的状态和对应检查点；不是预填通过"}
```

`keyboard` 统一取 `hidden / system_visible / hardware / not_applicable`；模板旧样例中的值须按实际更新。`theme` 为 light/dark 或真实高对比方案，`orientation` 为 portrait/landscape。`shot_ids` 仅给截图，不给视频/日志。其余 hash、commit、尺寸与来源等级沿用 06。

## 结果文档格式

每阶段报告必须使用 `### S1-T01 · 标题` 这类三级用例标题；段落内写需求、操作、实测、结论，并以 Markdown `![]()` 嵌入覆盖本用例检查点的原图。长报告可以附一个索引，但不能只链接目录或在聊天里发图。共用原图也需在对应场景段落内引用，并说明共用原因。

所有帧初始状态均为“尚未采集”；当前包中的 `design/stage-*.png` 不能填写为这些检查点的证据。


## S1 · 31 个可见状态检查点

### S1-T01 · 失败块的直接 AI 入口

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T01-F01` | `after-01-failed-block.png` | 失败块未展开菜单：命令、非零退出码、AI 诊断、查看输出 |
| `S1-T01-F02` | `after-02-diagnosis-draft.png` | 点 AI 诊断后：来源 Chip、诊断草稿、发送给 AI；尚未发送 |

### S1-T02 · 上下文与诊断发送

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T02-F01` | `after-01-source-detail.png` | 上下文详情：源会话、命令、实际行范围与截断/淘汰说明 |
| `S1-T02-F02` | `after-02-request-sent.png` | 显式发送后：用户问题、来源引用、分析中状态 |

### S1-T03 · 命令审批完整审阅

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T03-F01` | `after-01-proposal-card.png` | 手机提案摘要：待审阅、目的、审阅完整命令；不能直接批准截断文本 |
| `S1-T03-F02` | `after-02-review-top.png` | 审阅页顶部：目的、完整目标/节点/目录、审阅原因 |
| `S1-T03-F03` | `after-03-review-bottom.png` | 审阅页滚到命令尾部：完整末行可见，执行一次/编辑/拒绝可达 |

### S1-T04 · 编辑使旧审批失效

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T04-F01` | `after-01-revision-a.png` | 进入 revision A 的完整审阅页 |
| `S1-T04-F02` | `after-02-edit-b.png` | 编辑后的 B 草稿与保存并重新审阅；不得直接执行 |
| `S1-T04-F03` | `after-03-revision-stale.png` | 旧页/旧回调失效提示，以及 B 重新审阅入口 |

### S1-T05 · 执行映射真实 Block

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T05-F01` | `after-01-submitting.png` | 批准后的提交中状态，重复批准已禁用 |
| `S1-T05-F02` | `after-02-native-result.png` | 同一 operation 对应的原生 Block 与确定退出状态 |
| `S1-T05-F03` | `after-03-cited-conclusion.png` | AI 结论及有效行号证据入口；不以结论替代退出码 |

### S1-T06 · 只读观察与接管

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T06-F01` | `after-01-readonly.png` | 只读终端：AI 继续运行、本页不接收输入、接管入口 |
| `S1-T06-F02` | `after-02-taken-over.png` | 显式接管后：AI 已暂停、人工输入归属明确；运行命令未被自动中断 |

### S1-T07 · 阅读旧输出时新内容到达

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T07-F01` | `after-01-reading-old.png` | 停在历史块中部的可识别行和原阅读锚点 |
| `S1-T07-F02` | `after-02-pending-offscreen.png` | 新提案到达后原位置不动，有待审阅定位入口 |
| `S1-T07-F03` | `after-03-reading-restored.png` | 定位并返回后同一锚点附近、键盘未自动弹出 |

### S1-T08 · 未知回执禁止重发

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T08-F01` | `after-01-receipt-unknown.png` | 提交结果未知：可能已执行、原操作身份、检查原提交；没有重发 |
| `S1-T08-F02` | `after-02-receipt-inspected.png` | 核对原提交后的实际状态；未确定时继续标未知 |

### S1-T09 · 切换执行目标

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T09-F01` | `after-01-target-changed.png` | 原目标 A / 当前目标 B 的可辨差异与旧提案失效 |
| `S1-T09-F02` | `after-02-target-replanned.png` | 在当前目标继续后的新上下文/提案，不自动批准旧命令 |

### S1-T10 · TUI 回退与手动恢复

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T10-F01` | `after-01-tui-active.png` | 真实 vim/top 运行的完整终端区域与输入归属 |
| `S1-T10-F02` | `after-02-blocks-offer.png` | 退出 TUI 后仍为终端，明确提供返回 Blocks |
| `S1-T10-F03` | `after-03-blocks-restored.png` | 用户主动返回后的 Blocks 和原草稿 |

### S1-T11 · 无 AI 配置和请求失败

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T11-F01` | `after-01-unconfigured.png` | 无 AI 配置且保留草稿/来源的引导状态 |
| `S1-T11-F02` | `after-02-configured-unsent.png` | 保存配置后草稿仍未发送 |
| `S1-T11-F03` | `after-03-request-error.png` | 受控认证/网络/响应错误之一及恢复入口；其余分支补日志 |

### S1-T12 · 普通 Shell 操作不退化

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S1-T12-F01` | `after-01-history-adopt.png` | 采用历史/插回命令后的草稿，未执行 |
| `S1-T12-F02` | `after-02-session-isolation.png` | 另一 Session 的独立草稿与来源 |
| `S1-T12-F03` | `after-03-completed-readonly.png` | 已完成 Block 的阅读/复制状态，没有有效终端写入口 |

## S2 · 27 个可见状态检查点

### S2-T01 · 统一输入与自动意图

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T01-F01` | `after-01-auto-command.png` | 自动 · 命令，主动作执行 |
| `S2-T01-F02` | `after-02-auto-ai.png` | 自动 · AI，主动作发送给 AI |
| `S2-T01-F03` | `after-03-manual-override.png` | 手动输入意图选择及含糊输入安全路由 |

### S2-T02 · 多行输入与展开编辑

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T02-F01` | `after-01-four-lines.png` | 软键盘打开，主编辑器增长至四行 |
| `S2-T02-F02` | `after-02-expanded-edit.png` | 全屏展开编辑，完整草稿、去向、取消/完成编辑 |
| `S2-T02-F03` | `after-03-edit-return.png` | 完成编辑回主输入，草稿保留且未执行 |

### S2-T03 · 系统中文候选不提交

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T03-F01` | `after-01-ime-composing.png` | 真实系统拼音候选/组合输入正在显示 |
| `S2-T03-F02` | `after-02-ime-confirmed.png` | 确认候选后文本完整，尚未提交 |

### S2-T04 · 键盘出现不压缩块

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T04-F01` | `after-01-keyboard-hidden.png` | 键盘未显示：历史块固定预览与阅读位置 |
| `S2-T04-F02` | `after-02-keyboard-visible.png` | 系统键盘显示：相同输出预览与可读主操作 |

### S2-T05 · 手机横屏极短可用区

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T05-F01` | `after-01-landscape-keyboard.png` | 手机横屏和真实系统键盘：输入去向、主动作与收键盘 |
| `S2-T05-F02` | `after-02-short-editor.png` | 极短窗口展开编辑或收键盘后的可操作状态 |

### S2-T06 · 长命令与特殊字符

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T06-F01` | `after-01-unicode-edit.png` | 长命令、中间选区、中文路径/引号/emoji 的完整草稿 |
| `S2-T06-F02` | `after-02-long-title.png` | 两行命令标题以及可到完整值的详情入口 |

### S2-T07 · 输出阅读器与错误位置

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T07-F01` | `after-01-reader-match.png` | Reader 中原始错误匹配行、行号、查找范围 |
| `S2-T07-F02` | `after-02-reader-page.png` | 另一原生分页的输出和保留/淘汰边界 |
| `S2-T07-F03` | `after-03-reader-return.png` | 退出 Reader 后原草稿与主列表阅读锚点 |

### S2-T08 · 上下文 Chips 与删除

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T08-F01` | `after-01-multiple-contexts.png` | 多来源 Chips：数量、来源摘要、删除入口 |
| `S2-T08-F02` | `after-02-removed-context.png` | 删除一个后的剩余来源和原草稿；没有意图误切换 |

### S2-T09 · 触控与选择不冲突

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T09-F01` | `after-01-text-selection.png` | 长按/拖选原生输出，选择工具可达且无层级冲突 |
| `S2-T09-F02` | `after-02-block-menu.png` | 通过普通点击打开的完整 Block 菜单 |

### S2-T10 · 外接键盘

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T10-F01` | `after-01-hardware-focus.png` | 外接键盘焦点、输入去向与主动作 |
| `S2-T10-F02` | `after-02-candidate-adopt.png` | 候选/历史采用后的草稿，不隐式执行 |

### S2-T11 · iPad 宽窄分栏

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T11-F01` | `after-01-ipad-wide.png` | iPad 实际宽窗口：任务与只读终端双栏、单一输入所有者 |
| `S2-T11-F02` | `after-02-ipad-narrow.png` | 同一 iPad 窄窗口：单栏、保留草稿和任务状态 |

### S2-T12 · macOS 原 Composer 回归

最低来源：`app_desktop`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S2-T12-F01` | `after-01-desktop-dock.png` | macOS 实际 App：三层 Dock、历史/补全和灰字 |
| `S2-T12-F02` | `after-02-desktop-split.png` | macOS 分屏：活动窗格和输入归属正确 |

## S3 · 21 个可见状态检查点

### S3-T01 · 浅色核心页面

最低来源：`widget_golden`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S3-T01-F01` | `after-01-light-blocks.png` | 浅色：成功、失败、运行 Block 与 Composer 的语义层级 |
| `S3-T01-F02` | `after-02-light-review.png` | 浅色：完整审批页、目标和固定主动作 |

### S3-T02 · 深色核心页面

最低来源：`widget_golden`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S3-T02-F01` | `after-01-dark-blocks.png` | 深色：与浅色同 fixture 的 Block 层级与原有 ANSI |
| `S3-T02-F02` | `after-02-dark-review.png` | 深色：与浅色同 fixture 的完整审批页 |

### S3-T03 · 命令和 AI 主动作

最低来源：`widget_golden`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S3-T03-F01` | `after-01-intent-actions.png` | 采用/执行/发送/补充要求的真实组件状态册 |
| `S3-T03-F02` | `after-02-disabled-reason.png` | 主动作禁用时的明确原因及可见输入去向 |

### S3-T04 · 任务层级与证据

最低来源：`widget_golden`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S3-T04-F01` | `after-01-task-hierarchy.png` | 用户意图、AI 计划、原生 Block、总结的不同层级 |
| `S3-T04-F02` | `after-02-task-folded.png` | 完成步骤收起后仍有明确展开与证据入口 |

### S3-T05 · 执行状态总览

最低来源：`widget_golden`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S3-T05-F01` | `after-01-pending.png` | 待审批与智能审阅中的合法状态与文案 |
| `S3-T05-F02` | `after-02-unknown.png` | 未知回执的优先级高于普通 loading，无成功/重发 |
| `S3-T05-F03` | `after-03-paused-running.png` | AI 暂停但命令继续运行，暂停/中断区别明确 |

### S3-T06 · 长文本与本地化

最低来源：`widget_golden`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S3-T06-F01` | `after-01-zh-long.png` | 中文长路径/主机名/错误信息不遮挡关键信息 |
| `S3-T06-F02` | `after-02-en-long.png` | 英文长文案下相同主要操作仍可触达 |

### S3-T07 · 移动固定字号政策

最低来源：`app_simulator`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S3-T07-F01` | `after-01-phone-default-font.png` | 手机固定字号的正常系统字号环境 |
| `S3-T07-F02` | `after-02-phone-large-system-font.png` | 系统字号调大后手机 UI 仍按项目固定策略；主动终端缩放另测 |

### S3-T08 · 高对比与减少动画

最低来源：`app_simulator`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S3-T08-F01` | `after-01-focus-visible.png` | 手机真实 App/模拟器中可辨的焦点与选择状态 |
| `S3-T08-F02` | `after-02-reduced-motion.png` | 减少动态效果启用后，同功能状态的稳定画面 |

### S3-T09 · 组件交互状态册

最低来源：`widget_golden`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S3-T09-F01` | `after-01-component-states.png` | 真实 Flutter 组件状态册：default/focused/disabled/loading/error |
| `S3-T09-F02` | `after-02-contrast-report.png` | 真实 token 对比测量报告的可读结果；原始数值必须另交 |

### S3-T10 · 跨端统一与桌面缩放

最低来源：`app_desktop`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S3-T10-F01` | `after-01-macos-parity.png` | macOS 实际窗口的共享组件与主题回归 |
| `S3-T10-F02` | `after-02-nonphone-scale.png` | iPad 或 macOS 放大文字后的布局；标明实际平台 |

## S4 · 31 个可见状态检查点

### S4-T01 · iPhone 实机完整闭环

最低来源：`app_physical`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T01-F01` | `after-01-physical-failed.png` | iPhone 实机：失败 Block 和 AI 诊断入口 |
| `S4-T01-F02` | `after-02-physical-review.png` | iPhone 实机：完整审批、目标、执行一次 |
| `S4-T01-F03` | `after-03-physical-result.png` | iPhone 实机：原生结果与有效 AI 证据引用 |

### S4-T02 · iPhone 实机中文 IME

最低来源：`app_physical`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T02-F01` | `after-01-physical-composing.png` | iPhone 实机：真实中文候选/组合输入 |
| `S4-T02-F02` | `after-02-physical-composed.png` | iPhone 实机：候选确认后未提交，文本/光标正确 |

### S4-T03 · iPhone 实机横竖屏

最低来源：`app_physical`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T03-F01` | `after-01-physical-portrait.png` | iPhone 实机：竖屏编辑且系统键盘打开 |
| `S4-T03-F02` | `after-02-physical-landscape.png` | iPhone 实机：同一草稿横屏、去向/按钮未丢失 |

### S4-T04 · iPhone VoiceOver

最低来源：`app_physical`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T04-F01` | `after-01-vo-review.png` | iPhone 实机 VoiceOver 焦点到完整审批内容 |
| `S4-T04-F02` | `after-02-vo-result.png` | VoiceOver 完成执行并找到原生结果；连续操作见录屏/观察记录 |

### S4-T05 · 断网与恢复

最低来源：`app_physical`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T05-F01` | `after-01-physical-network-error.png` | 实机：网络错误或提交确认丢失的准确状态 |
| `S4-T05-F02` | `after-02-physical-reconnect.png` | 恢复后检查原回执/目标，未重复发送 |

### S4-T06 · 锁屏与前后台

最低来源：`app_physical`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T06-F01` | `after-01-foreground-recheck.png` | 锁屏/后台返回后的重新核对与准确输入归属 |
| `S4-T06-F02` | `after-02-process-restart.png` | 终止应用再启动，未伪装恢复已死亡的内存任务 |

### S4-T07 · 真实 TUI 及密码接管

最低来源：`app_physical`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T07-F01` | `after-01-physical-tui.png` | 实机真实 TUI：完整画面与输入归属 |
| `S4-T07-F02` | `after-02-password-boundary.png` | 一次性账号密码交互前/后的安全边界；不拍密码本身 |
| `S4-T07-F03` | `after-03-physical-takeover.png` | 接管后 AI 后续写入撤销，运行命令状态准确 |

### S4-T08 · 长输出与保留边界

最低来源：`app_physical`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T08-F01` | `after-01-physical-reader.png` | 大输出 Reader 的分页/查找原始行 |
| `S4-T08-F02` | `after-02-eviction-notice.png` | 超出保留范围后的准确淘汰提示 |
| `S4-T08-F03` | `after-03-copy-retained.png` | 复制全部保留输出后的反馈，另交 hash/字节一致性断言 |

### S4-T09 · 错误注入与重复批准

最低来源：`app_physical`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T09-F01` | `after-01-fault-unknown.png` | 故障注入造成未知回执时的受保护状态 |
| `S4-T09-F02` | `after-02-fault-stale.png` | 重复批准/旧版本回调被拒绝时的当前有效状态 |

### S4-T10 · 实机性能样本

最低来源：`app_physical`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T10-F01` | `after-01-perf-app.png` | 实机 profile 构建的被测场景与性能叠层（另次录制，不混入采样） |
| `S4-T10-F02` | `after-02-memory-cycle.png` | 同一实机被测 App 完成循环后的稳定场景；内存曲线另附辅助报告 |

### S4-T11 · iPad 实机与外接键盘

最低来源：`app_physical`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T11-F01` | `after-01-physical-ipad-wide.png` | 真实 iPad 宽窗口双栏和外接键盘焦点 |
| `S4-T11-F02` | `after-02-physical-ipad-narrow.png` | 真实 iPad 窄窗口保持同一任务和草稿 |

### S4-T12 · macOS API 与本地 ACP 回归

最低来源：`app_desktop`；连续录屏：必须。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T12-F01` | `after-01-macos-api.png` | 真实 macOS App 的模型 API 完整闭环结果 |
| `S4-T12-F02` | `after-02-macos-acp.png` | 真实 macOS App 本地 ACP 的独立闭环结果 |

### S4-T13 · 升级/回滚与数据边界

最低来源：`app_physical`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T13-F01` | `after-01-upgraded-data.png` | 隔离升级后 Profile/录制/布局保留的实际页面 |
| `S4-T13-F02` | `after-02-rollback-data.png` | 回滚后实际可访问数据状态，没有恢复旧执行的假提示 |

### S4-T14 · 最终 GitHub 证据与构建一致

最低来源：`app_desktop`；连续录屏：按 07；此项不强制。

| 帧 ID | 建议文件名 | 必须可见的内容 |
|---|---|---|
| `S4-T14-F01` | `after-01-candidate-app.png` | 最终 macOS 候选构建的完整 App 场景；构建身份由 environment/build 日志关联 |
| `S4-T14-F02` | `after-02-candidate-terminal.png` | 最终候选的实际终端/AI 闭环末态；GitHub 清单和校验结果另交日志 |

## 校验命令

先运行 06 的文件/构建校验器，再运行逐帧覆盖与嵌图校验器：

```sh
python3 scripts/validate_evidence.py evidence/manifest.json --gate S4 --repo-root /实际仓库路径
python3 scripts/validate_shotlist.py evidence/manifest.json --gate S4
```

S1/S2/S3 可以用相应 `--gate`。第二个校验器只检查声明的帧覆盖、环境相容、文档嵌图和已知文件关系；**无法从图像内容判断真正实现或造假**。两者通过后仍必须实际打开原图和录屏并对照源码。

性能曲线、GitHub Actions 或 token 对比报告可以作为辅助报告图；它们不是“正在运行的产品原图”，不使用 app_physical 标签冒充 App 截图。其原始数据按 metrics/log 交付。
