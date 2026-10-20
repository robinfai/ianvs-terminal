# 当前源码的场景设计复核

2026-10-03，当前 `composer` 工作区，macOS 27.0.1（26A434）。本轮直接查看 imagegen 设计稿与实际渲染截图，并核对生产组件源码和原生断言。图像生成模型没有充当自动验收器；以下明确保留发现的缺口。

## D04 运行、静默与输出更新

对照 [D04 设计](screens/D04-v3.png)、[暂停后的静默命令](evidence/scene-review/D04-silent-command-ai-paused-elapsed.png)与[持续输出](evidence/scene-review/D04-streaming-one-native-block.png)：单列时间线中真实命令块、原生运行状态与耗时可辨认，AI 暂停单独显示“命令未被中断”。没有把静默当作失败或展示假进度。底部补充要求／暂停／中断／定位属于现有任务控制，未增加第二个聊天栏。

当前源码实际执行的静默命令耗时 12,027ms，显示 12.0s。三批输出 81→161→241 行；整块从 257.4px 到 255px，低于可用 800px 的三分之一。回看后新输出不拉回，显式定位后可返回原锚点；执行证明文件只有一个 `x`。本轮桌面这些状态的设计对照通过。截图中的测试命令很长，执行后标题可截断，审批时的完整命令仍由 D03 审阅页负责，不能用标题截图替代审批完整性验证。

## D07 多选、待附加与已发送证据

对照 [D07 设计](screens/D07-v2.png)与当前源码的三个阶段：

- [块标题多选](evidence/scene-review/D07-header-multi-selection.png)：显示选择数量和浅色边界，失败块仍有原始输出和退出 1；选择没有复制执行记录。
- [待附加](evidence/scene-review/D07-pending-contexts.png)：移除一个附件后剩余两个，各自显示命令及行范围；删除入口位于附件，顶部块选择数量仍为三个，二者是独立状态。
- [已发送](evidence/scene-review/D07-sent-contexts.png)：两个固定证据位于用户问题下面，输入区附件清空，原块没有删除。

真实 Cmd／Shift 多选、移除和发送已逐步断言；实际 HTTP 消息与发送前冻结快照逐值相等，没有新 PTY 命令。本轮桌面视觉对照通过。手机长命令及范围仍以既有 320px 固定字号测试为证，不将桌面截图冒充手机验收。

## D08 / M04 阅读页仍需整改

后续整改已增加固定行号、阅读范围、选段数量及独立查找导航，并通过本机原生截图复核，见 [D08_READER_TOOLS.md](D08_READER_TOOLS.md)。以下保留整改前观察作为历史证据；D05 历史引用淘汰后的定位现已继续补齐，见 [来源定位验收](D05_EVIDENCE_IDENTITY.md)。

[D08 设计](screens/D08-v2.png)与[当前原生阅读页](evidence/scene-review/D08-native-reader-selected.png)存在可确认的展示差距。源码 `command_block_reader.dart` 也证实这些差距，不能因复制／滚动测试通过而标为完整实现：

1. 阅读页没有常驻原始行号与当前阅读范围／总量。截图中的 `31…77` 是 `seq` 的输出内容，不是 UI 行号；换成普通日志就无法从界面核对引用位置。
2. 已选范围的附加入口只有回形针图标及 tooltip，没有设计中直接显示的“将所选 N 行附给 AI”。需要在桌面与手机可用空间内明确范围和数量，不引入第二个纵向滚动区域。
3. 当前菜单提供“过滤输出”，还没有设计中的独立行内查找、匹配计数及上一处／下一处导航。过滤不能替代保留上下文的查找。

已成立的行为继续保留：真实 800 行分页、关闭重开恢复位置和选区、草稿不丢失；过滤后仅发送原第 34–35 行和第 77 行，附带各自精确引用，不能合并成覆盖中间未发送行的连续范围。本轮重新执行已验证这些事实。后续整改需一起核对 D05 引用在早期输出淘汰后的定位，防止 UI 显示原行号而点击仍使用已偏移的相对行号。

## M03 对照范围

本轮还直接查看 [M03 设计](screens/M03-v2.png)、既有[深色六行预览](evidence/elapsed-navigation/M03-live-six-rows-dark.png)和[浅色暂停](evidence/elapsed-navigation/M03-live-paused-after-background-light.png)：六行末尾预览、总量、查看全部、独立运行耗时和 AI 暂停状态均可辨认。该组是早先生产组件证据，本轮未重新运行同一个动态截图用例，因此保留 M03 最终整体审计，不把旧图重新标成当前源码完成证据。

## 本轮运行记录

[最终原生日志](evidence/scene-review/scene-review-final.log)共 5 项通过：一个完整 HTTP→原生 PTY 流程和四个固定字号手机组件渲染。结果同时核对 D04、D07、D08、D10/D14 配置恢复及 vim 44×203 网格，详见[原始结果](evidence/scene-review/result.json)。`native_command_count: 1` 是脚本首条编辑命令阶段的计数，不是整条流程的命令总数。

首次重跑失败于旧测试预期缺少上轮新增的 `citation` 字段，见[原始失败](evidence/scene-review/scene-review-native.log)。现已在每个非连续片段的逐值期望中增加真实 block ID 和正确一基范围，没有删除断言或放宽范围验证。[静态分析](evidence/scene-review/scene-review-analyze.log)通过。证据与关键源码哈希见[清单](evidence/scene-review/manifest.json)。

本轮不以局部视觉通过替代完整 20 场景审计。D12 的独立 k9s 运行与菜单缺陷修复见 [D12_K9S.md](D12_K9S.md)。没有提交或推送。

## 后续：D13 导航及 D14 模式偏好

已继续对照 D10/D13/D14 设计稿与当前原生图。修复 D13 宽桌面只有导航图标、D14 缺少恢复平台默认入口的问题；保留仍待核验的恢复／配置状态，详见 [导航与偏好整改](D13_D14_REVIEW.md)。

## 后续：D10 恢复及 D14 配置状态

未知回执补齐中英文、浅深色、桌面 2× 及手机固定字号短横屏；配置补齐缺配置、读取失败、保存失败、取消和移除的状态区分。真实 macOS 入口状态与已有 HTTP 401 恢复链路重测通过，详见 [恢复与配置复核](D10_D14_CONFIGURATION.md)。

## 当前 M03 浅深色复核

已重新运行当前源码的两项动态生产组件流程，并直接对照 M03 设计稿与[深色六行预览](evidence/mobile-current/M03-live-six-rows-dark.png)、[浅色后台暂停](evidence/mobile-current/M03-live-paused-after-background-light.png)。六行末尾输出、完整行数、查看全部、独立命令耗时与 AI 暂停说明清楚。60→120→180 行更新时，手动回看的原项与偏移不变；明确查看最新才恢复跟随。回前台保留草稿且不发 PTY 输入、不增加模型请求；完成耗时固定为 1m 32s。测试、8 张截图及 7 个源码哈希见[清单](evidence/mobile-current/manifest.json)。全部固定字号，属于组件验收。

## 实际 cloud 与 TUI 历史

真实 cloud 补验发现并修复 Linux top 清主屏时删除已完成命令块。最终两次 ls 的身份、输出、退出码及来源行保持，top/vim 使用 44×203 全屏网格；恢复菜单和块截图已直接复核。六组隔离 SSH、认证和未知回执恢复也重新通过，详见 [cloud 验收](D11_CLOUD_CLEAR.md)。

最终整体审计仍继续。当前场景专项并不证明 DESIGN.md 要求的高对比、减少动态效果及实际 VoiceOver 听读已通过；这些项目需要独立证据，不以语义树测试替代。

## 高对比与动态效果补验

现已补齐应用浅深色高对比主题、保持独立键盘焦点，并关闭减少动态效果下的 AI 页面、弹窗及任务菜单装饰动画。六组生产工作区检查、24 张截图、972 项应用回归和 5 项原生流程通过，详见 [ACCESSIBILITY_REVIEW.md](ACCESSIBILITY_REVIEW.md)。实际 VoiceOver 朗读尚未验证；全局读取被自动审批拒绝，未执行。用户同意后已关闭 VoiceOver。最终场景审计和其余动态效果覆盖继续进行。
