# 行为与渲染验收记录

更新：2026-10-03。当前 `composer` 工作区，尚未提交。实际系统为 macOS 27.0.1 (26A434)。本记录证明下列执行过的检查，不代表 20 场景全部完成。逐场景缺口见 [IMPLEMENTATION.md](IMPLEMENTATION.md)。

## 环境与证据边界

- 原生集成使用真实 macOS 应用、生产 HTTP 客户端和原生 PTY；模型回复来自隔离 loopback HTTP fixture，目的是确定性验证审批、提交与视图行为，不证明模型回答质量。
- Shell 使用临时 HOME/ZDOTDIR，AI 配置在内存；没有访问个人凭据或远端模型。
- 手机依用户要求仅按固定字号验证，通过生产组件在 macOS 上按 iOS 主题和手机尺寸渲染。没有进行 iPhone 真机、系统软键盘或所有支持 OS 版本的验证。
- SSH 为独立临时密钥与目录的 loopback OpenSSH；本轮没有重连 `ssh cloud`。Bash 5.2.37 编译于 `/tmp/bash`，未全局安装。
- 截图是实际组件/应用渲染；`screens/` 中的 imagegen 设计图是对照稿，不能用作执行结果。

## SSH 重连后续轮次

本轮新增的完整记录见 [D10_RECONNECT.md](D10_RECONNECT.md)：重连保留原任务及来源，显式选择新目标后单独审批；实际 macOS/六组 SSH 通过，手机旧输出阅读位置和选区保持。修复关闭手机最后会话的生命周期异常、保留 SSH 的无效 resize、长字面命令的 zsh 解码瓶颈及 Dart 64KiB 解码边界。当前应用 718 项、共享 runtime/块/时间线 258 项、本地 zsh 4 项通过；原生全量顺序执行 416 通过、1 忽略。并行原生失败日志保留，不能写成并行全量通过。镜像同步与差异格式检查通过。

后续重连轮次进一步覆盖四个 native session、公钥认证拒绝、进入 SSH 设置/取消/明确连接，以及 384 块多来源聚合保留。应用回归 719 项、共享块/时间线 28 项通过，证据和边界见 D10_RECONNECT 的追加章节。

最新一轮实际暂缓 SSH 服务端返回数据，独立确认命令已执行后再断线；原 receipt 从 pending 变 unknown，第五个连接建立并检查后仍未知，不重发、不新增模型请求。修复未知提交卡片的失效提案误导文案，发送按钮与 Enter 在结果未知时保持不可发送，原回执确认后恢复。723 项应用回归、49 项最终 workspace 组件、中继测试、六组真实 SSH 和一项完整 macOS 流程均通过；中英文手机固定字号与桌面截图已查看。原回执数据、执行次数与请求数见 [逐项结果](evidence/ssh-unknown-receipt/disconnect-result.json)，完整步骤和日志见 [D10 重连追加](D10_RECONNECT.md)。仍不代表最终 20 场景设计对照完成。

## D04／D13：持续输出、历史定位与状态播报

2026-10-03，在同一实际 macOS 应用验收中加入分三批输出的本地 zsh 命令。临时 HOME 下的 marker 文件仅控制批次时机，输出通过真实 PTY／原生块协议进入生产时间线。执行凭据文件只写一个 x；完成后仅一个 native block，退出 0，新提案另行审阅并最终拒绝。

- 记录的输出行数为 81、161、241（运行时含末尾光标空行）。800px 可用时间线内，整块分别为 256.4px、254px，均低于 1/3。字体单元从初始估值变为实际测量值时可以变化，未要求整块像素高度恒定。
- 真实滚轮在时间线边缘回看，第二批输出到来时同一条目内偏移保持。点击最新后跟随第三批，显式返回后恢复原条目。命令结束和新提案出现仍不改变阅读锚点；再次定位提案、再次返回均保持 entry-13 内 33px 偏移。总 scrollOffset 因上方布局测量变化约 0.8px，条目身份一致，项内偏移差小于 0.5px。
- [运行中的真实块](evidence/streaming-timeline/D04-streaming-one-native-block.png)、[更新前的历史](evidence/streaming-timeline/D13-stream-history-before-next-batch.png)、[更新后的历史](evidence/streaming-timeline/D13-stream-history-after-next-batch.png)、[命令完成后仍留在历史](evidence/streaming-timeline/D13-stream-completed-proposal-keeps-history.png)、[明确定位待确认提案](evidence/streaming-timeline/D13-stream-explicit-proposal-location.png) 均已查看。原始数值见 [result.json 中 streaming_timeline](evidence/streaming-timeline/result.json)。

语义检查先复现状态 live region 与任务标题、当前目录合并：[修复前](evidence/streaming-timeline/streaming-semantics.log)。现在桌面状态条、手机任务状态和目标变化提示各自形成独立语义容器。两平台检查实际 semantics node：观察时间和新输出改变可见文字但不改变播报标签或节点身份；暂停、断线、目标变化才更新对应状态，目录不混入。它证明 Flutter 语义树，不等同 VoiceOver 实际听读验收。

## M03：手机持续输出与后台暂停组合

固定字号、390×700、生产 iOS 主题／workspace／CommandBlockTerminal，输出和模型端口为内存 fixture。浅色、深色分别验证末尾六行从 55–60 更新到 115–120、175–180；从预览区开始拖动由外层接收，回看时更新保留条目内位置。进入 inactive 后停止 AI 观察，回 resumed 只读状态，草稿和原观察起点保持；输出继续显示更新的六行，不产生写入或额外模型请求。没有 iPhone 真机或系统键盘测试。

已查看 [深色运行预览](evidence/streaming-timeline/M03-live-six-rows-dark.png)、[浅色回看](evidence/streaming-timeline/M03-live-history-stays-light.png)、[回到前台后的暂停状态](evidence/streaming-timeline/M03-live-paused-after-background-light.png)。截图使用已加载的仓库等宽字体，测试默认占位字形的早期截图不作为视觉证据。暂停后界面的耗时展示与全场景最终设计对照仍需复核。

本轮验证：[727 项 AI/Shell/SessionController](evidence/streaming-timeline/streaming-app-regression.log)、[53 项最终 workspace 及字体截图](evidence/streaming-timeline/streaming-workspace-fonts.log)（前者子集，随后只补齐截图等宽字体配置）、[语义回归](evidence/streaming-timeline/streaming-semantics-verified.log)、[实际 macOS 主流程＋四组手机预览，共 5 项](evidence/streaming-timeline/streaming-ui-settled.log)、[静态分析](evidence/streaming-timeline/streaming-final-analyze.log)、[镜像](evidence/streaming-timeline/streaming-mirror.log) 均通过。原生集成的早期失败来自测试查找器包含底层视图、额外要求高度恒定、未等待异步返回完成，日志同目录保留，未把这些误计为生产问题；语义节点合并则已复现并修复生产代码。

下表是此前各轮次范围的历史记录，不以本轮检查替代其他场景的验收。全部场景的最终设计对照仍待完成。

## 已通过检查

| 检查 | 结果 | 留存证据 |
| --- | --- | --- |
| 完整应用 AI、Shell 与模式单测（含输入、录制、分屏、架构等） | 613 项通过，其中 5 项模式单测 | [target-app-tests.log](evidence/target-app-tests.log) |
| 手机模式与融合流程，实际组件渲染 | 17 项通过，属于上述 613 项的子集；截图来自此前 copy-app 运行，本轮未重新截图 | [target-app-tests.log](evidence/target-app-tests.log)、[截图运行](evidence/copy-app-tests.log) |
| AI、Shell、Composer 与相关测试静态分析 | 无问题；l10n/集成测试此前分析通过 | [copy-app-analyze.log](evidence/copy-app-analyze.log)、[此前范围](evidence/recheck-analyze.log) |
| macOS 原生交互及四组手机组件渲染 | 当前源码 5 项通过，包含新 HTTP 认证/连接/配置恢复链路 | [macos-recovery.log](evidence/macos-recovery.log)、[result.json](evidence/macos-recovery/result.json) |
| Composer、command blocks/mobile/timeline/copy，加终端键盘/触控/渲染/Alt 点击/输入/字符单元 | 312 项通过；其中复制文件 29 项、普通终端触控文件 18 项。边缘测试再扩展到阅读区外坐标后，29 项复制单独重跑 | [edge-core-tests.log](evidence/edge-core-tests.log)、[最终复制复核](evidence/edge-copy-tests.log) |
| 本轮 Composer 修复及测试静态分析 | 无问题 | [composer-analyze.log](evidence/composer-analyze.log) |
| 终端块、时间线、阅读器及对应测试静态分析 | 无问题 | [core-analyze.log](evidence/core-analyze.log) |
| SSH 原生 zsh/bash、emacs/vi、直接及本地 ssh 入口 | 6 组通过 | [SSH results.json](evidence/ssh/results.json)、同目录 `*.test.log` |
| macOS SSH 连续命令、多级跳转、top/vim、手动恢复 | 1 项通过 | [app.test.log](evidence/ssh/app.test.log) |
| 本次终端、Composer、复制与触控测试静态分析 | 无问题 | [edge-core-analyze.log](evidence/edge-core-analyze.log) |
| 发布包源码镜像 | 已同步且无漂移 | [target-mirror.log](evidence/target-mirror.log) |
| 本轮 AI 生产代码及工作区测试静态分析 | 无问题 | [target-analyze.log](evidence/target-analyze.log) |

## D10 真实 SSH 传输中断补验

本轮不再只模拟读取失败：独立 loopback SSH 通过临时 TCP 中继真实断线。修复原生 SSH 在缺失远端退出状态时默认成功，以及 runtime/pane/AI 被关闭、原生块视图丢失的问题。原提案撤销、只读历史与原回执保留，草稿附件往返仍在，命令实际只执行一次。详细步骤、已查看的实际截图、测试边界及未完成项见 [D10_DISCONNECT.md](D10_DISCONNECT.md)。

当前最终检查：完整 AI/Shell/模式 **616 项**、SessionController/Shell/恢复组合 **131 项**（与前者部分重叠）、运行时 **231 项**、键盘/触控 **21 项**、原生 SSH **35 项**通过；真实 SSH **6 组 + 1 项 macOS UI**通过。相关证据分别为 `evidence/ssh-retention-regression.log`、`ssh-retention-app.log`、`ssh-retention-core.log`、`ssh-readonly-viewport.log`、`ssh-native-unit.log` 及 `evidence/ssh-disconnect/`。应用和共享包静态分析均无问题。下方其他检查保留各自先前运行范围，未全部重跑。

此轮结束时 SSH 重新连接入口和任务衔接尚未完成；后续已实现并补验，见上文 SSH 重连后续轮次。此次截图发现的复合命令标题缺失现已修复：原生 416 项、两套各六组真实 SSH（包含关闭历史）、本地 zsh 与 macOS UI 均通过，见 [完整命令验收](COMPOUND_COMMANDS.md)。不能声明全部场景完成。

## D09 目标选择与实际触控主题

本轮目标流程四步视觉、12 组长标签布局及重复点击／跨任务隔离已核验，详见 [D09 审计](D09_AUDIT.md)。完整应用回归 613 项；实际字体的 workspace 45 项通过。名称空值、目标信息层级、行内操作与短屏弹窗已修复。测试改用生产 iOS 触控主题后，额外发现并修复极短屏输入不足和长附件范围越界；失败与修复截图均留存。

## 恢复与提交归属

- 终端断线时撤销旧提案、取消推理，晚到模型响应不能恢复批准；只读检查后保留任务、草稿和附件，但不会自动继续或批准。
- 终端读取错误与模型请求错误独立保存；终端恢复不能擦除认证失败。显式中断遇到断线，也通过同一终端检查入口恢复，不自动再发 Ctrl+C。
- 未知提交必须先查询原 submission；重复点击共享一次检查。仍未知时保留人工检查入口，原回执 accepted 后才允许显式继续；不增加命令写入次数。
- 认证错误可以直达配置；保存只更新设置，任务页在固定状态栏反馈保存成功，避免 Snackbar 遮住发送按钮。测试成功单独标明“尚未保存”；配置表单只表达用户需要的连接信息。
- 新增 8 项控制器和 3 项 workspace 回归，属于此前 586 项。原始失败：[恢复流程](evidence/recovery-before.log)、[中断时断线](evidence/interrupt-recovery-before.log)。
- 原生集成暴露 Composer 外部提交锁：shell 已 ready，而 Composer 仍 submitting、草稿编辑被禁用。见 [原生失败诊断](evidence/composer-native-before.log)；确定性 [核心失败复现](evidence/composer-external-before.log) 也失败。修复后 111 项核心测试通过，同时证明自身 pending/unknown 回执仍保持锁、不会重发。
- 新增集成覆盖真实 loopback HTTP 401、断开 socket、测试连接、保存与显式继续。此前 macOS 锁屏停止帧更新，主测试随后在 5 分钟超时，runner 已明确返回 exit 1；同一 runner 后续预览也因未结束帧断言失败。见 [锁屏超时原始日志](evidence/macos-recovery-locked.log)。当次局部步骤不计为完整通过。2026-10-03 本轮只读检查发现 Mac 已可访问，随后在最终源码上重跑 5 项全部通过：[原生恢复日志](evidence/macos-recovery.log)、[结果](evidence/macos-recovery/result.json)。
- 终端断线与未知回执的 workspace 测试使用端口故障注入；不是实际 SSH 掉线重连证明。真实模型、真实远端 cloud 及 20 场景最终视觉审计仍未完成。

## 原生 HTTP 认证与连接恢复补验

本轮完成原先锁屏中断的链路。实际生产 HTTP 客户端收到本地服务的 401 后，保留原任务及终端证据；编辑配置后第一次连接检查遇到 socket 断开，表单编辑与已保存设置分别保留。第二次连接成功明确显示“尚未保存”，保存后返回原任务并显示“任务尚未发送”。只有点击继续才新增一次模型请求，原生命令块数量与 once.txt 的单次写入证明均保持。新增草稿和待附加附件仍未发送；新测试密钥不出现在任务历史中。

已检查实际原生截图：[认证失败](evidence/macos-recovery/D10-authentication-recovery.png)、[连接失败且编辑保留](evidence/macos-recovery/D14-connection-failed-edit-retained.png)、[测试成功未保存](evidence/macos-recovery/D14-connection-tested-not-saved.png)、[保存并保留任务](evidence/macos-recovery/D14-saved-task-retained.png)。这是 loopback HTTP 故障与原生 PTY 的完整交互验证，不是实际 SSH 断线重连，也不证明远端模型质量。手机仍未做真机测试。

## 原生交互断言

`example/integration_test/terminal_ai_workspace_acceptance_test.dart` 通过真实 UI 和原生回执核验：

1. 命令草稿及选区在 AI 往返后逐值保持；独立 AI 草稿保留；打开和关闭不请求模型、不执行命令。
2. 原提案先编辑、保存为新 revision，再批准；`once.txt` 内容仅为 `x`，原生结果只有一个对应 block，submission 映射不重复。
3. 点击证据打开原始输出 reader，关闭后保留未发送追问。
4. 真正的 `ls` 非零退出后，从块菜单附给 AI；请求数与块数不增加。发送并批准另一个检查后，生成唯一新块，旧命令与退出 1 保持。
5. `sleep 12` 保持静默时有等待状态。暂停 AI、恢复观察、补充要求都未打断命令或重新提交；同一块最终退出 0 且含 `SILENT_DONE`。
6. 真实 vim 先按可见终端和实际 cell 尺寸完成 PTY resize，再确认 AI 覆盖页保持同一 44×203 网格；逐键批准退出后交回终端，文件未改变。退出后保持 Normal，由用户手动恢复 Blocks。
7. Cmd 多选与 Shift 连选通过实际标题点击完成。附加 3 块后用删除按钮移除 1 个，只发送剩余 2 块；实际 HTTP selected_blocks 与冻结快照完全一致，原块仍在，执行计数不增加。
8. 原生 `seq 1 800` 通过滚轮阅读并用鼠标选择文本；关闭后重开恢复滚动位置和选区的每个坐标。返回 AI 后独立草稿仍在。

9. 同一原生输出过滤到第 34、35、77 行，用真实鼠标选择并附加；实际 HTTP 仅含 `[33,35)` 与 `[76,77)` 两个原始范围、3 行内容，没有平铺成含隐藏行的连续输出。附加不请求模型，显式发送后仍不执行命令。

手机组件为 390×844、390×480、844×300，包含浅/深色、失败源块草稿及结果。另有 widget 测试以 60 行命令验证横竖屏专用审阅页：完整内容、单个页面滚动、固定确认区、滑动/返回不执行、目标变化撤销确认。桌面保留 2× 字号布局检查。

## 阅读锚点与淘汰回归

- 时间线保存 itemId 与项内像素偏移。测试覆盖上方内容增高超过一屏、插入/删除旧消息、前置 50 项、任务切换后宽度从 960 变为 640，以及补偿后继续惯性滑动。
- Reader 的原始行身份、行内偏移、水平位置和选区保存在 session 的 CommandBlockController，关闭路由不丢失。过滤视图按原始行定位匹配结果，不能把匹配序号当作原始行号。
- iOS 平台分支组件测试：关闭 reader 后淘汰 40 行，重开仍定位同一原始行；随后在 fling 中再次淘汰 4 行，补偿不取消惯性；即使 totalLines 与 evicted 标志不变也刷新缓存。选区来源全部被淘汰时清除选区，避免引用新行。
- 修复前两个复现均失败，见 [reader-before.log](evidence/reader-before.log)；修复后测试与 30 项核心回归均通过，见 [reader-tests.log](evidence/reader-tests.log)。历史 67 项基线日志仍保留为 core-tests.log，不作为本次修改后的完整重跑声明。

## 过滤片段与任务多选回归

- 两个过滤结果跨度大于 500 行但实际只选两行时，按实际选中行计限额；附加不带入中间隐藏行。请求共享 16k 文本预算，各片段保留原始行范围。
- 同一块、相同外层起止范围但中间选中行不同的附件，保持独立身份；模型请求显式表达分离片段。
- 任务时间线 Shift 多选仅覆盖当前可见块；隐藏的会话块不被带入。附加与清除入口经过真实点击测试。
- 修复前复现日志：[非连续过滤选段](evidence/context-before.log)、[任务内 Shift 多选](evidence/task-selection-before.log)。修复后分别由上述核心与应用回归覆盖。

## 手机融合流程与网格修复

- 使用生产 Shell、AI workspace、终端块和 reader，iOS 平台固定字号，后端协议数据为内存 fixture，不连接真机或真实 SSH。标题 Cloud 是测试会话名称。
- M04：真实触控拖动到历史，长按并拖选原始第 20–22 行，附加后保留 AI 草稿；再次打开 reader 保留滚动位置和四个选区坐标，关闭 AI 后命令草稿仍在。附加不发送问题、不提交命令，不直接设 selection 来替代手势。
- M05：AI 页面上的会话菜单手动切换 Normal/Blocks；从 Blocks 失去能力时自动降级，禁用项带原因，能力恢复仍停留 Normal，用户点选才回 Blocks。菜单本身不增加 resize 或写入，两份草稿均保留。
- M06：发现并修复了打开 AI 时移除手机底部工具栏导致终端高度 730→792 的额外 resize。现在 AI 页覆盖原有布局，底层终端和辅助键保留布局，但排除焦点、触控与语义；中键粘贴也受输入归属限制。
- 竖屏 390×844、键盘 inset 300：AI 打开/关闭不改变该状态下的 viewport 或 PTY grid；键盘出现正常缩小，收起后恢复原网格。终端辅助键 Ctrl+C 只发出一个字节 3；AI 草稿不写 PTY。AI 页显示当前终端程序名称。
- 修复前失败：[mobile-tui-before.log](evidence/mobile-tui-before.log)；修复后行为及实际渲染：[mobile-flows.log](evidence/mobile-flows.log)。留存截图中的键盘区域只是系统 inset，不是实际系统键盘渲染。
- 扩展 Shell 回归同步了 AI 入口加入后的标题可用区域断言、按操作类型验证 ZMODEM 请求以排除只读轮询、滚动到分屏关闭菜单项后点击。架构检查只登记实际跨模块依赖，原有 1,700/4,150/41,700 行限制未放宽；主文件当前 1,696 行。

## 本次能力重检与短屏输入修复

- 桌面 tab 右键和触控会话菜单增加「重新检查命令块支持情况」。读取当前 session 的 `composer.state`，显示能力或不可用原因，不新建连接、不重新注入、不写配置；恢复后仍由用户选择 Blocks。它检查现有协商结果，并不宣称重启协商。
- 模式结果在相同轮询下保持稳定，不重复发出通知；能力变化时更新。桌面及手机生产 Shell 测试验证同一 session、命令草稿、AI 草稿、无命令写入与手动切回。手机截图见 M05-recheck-entry/unavailable/supported。
- 生产 Shell 在 844×390／键盘 180px、568×320 深色／键盘 160px 复现 AI 页底部 30/80px 溢出：[诊断](evidence/short-tui-overflow-before.log)。可用高度低于 200px 时使用紧凑标题与单行输入，保留程序名、状态和 44px 按钮，不改变底层终端布局。
- 三种尺寸（另含 390×844／键盘 300px）验证键盘重复出现/收起时草稿、选区、焦点保持，AI 打开不额外 resize；任务菜单「收起键盘」保留 AI 输入归属，随后 Esc 只关闭 AI，再一次 Esc 才写 PTY 字节 27。终端 Ctrl+C 仅写一次字节 3，退出 TUI 后维持 Normal，手动切回后原命令草稿保持。
- 极窄 320px 同时有提案、附件和键盘时，输入区曾只剩 64px：[失败](evidence/short-controls-before.log)。短屏宽度不足 480px 时次要任务操作进入菜单，发送与附件保留；[28 项 workspace 回归](evidence/short-controls-fixed.log) 验证至少 80px 输入区、定位入口、暂停撤销批准且不执行、不丢草稿和附件。
- 新增菜单项使设置项移入滚动区；设置测试先实际滚动到该项再点击，原设置行为断言保持。完整回归 596 项通过，未放宽架构约束。
- 2026-10-03 原生 UI 只读复查仍返回 [Mac 锁屏](evidence/macos-lock-recheck.txt)；没有新启动原生集成，不能把上述组件证据写成原生或手机真机通过。

## 连续提案与复制范围

- `terminal_ai_workspace_test.dart` 新增桌面与手机完整 UI 路径：三个连续响应分别返回独立提案；第一条快速点击同一批准位置两次只执行一次，第二条必须重新审阅且 Enter 不会隐式批准，拒绝第三条后执行数仍为 2。同一个 task 保留两条 accepted、一条 rejected，不把上一条批准传给下一条。它验证既有单响应单提案协议的连续交互，不新增批量自动执行。
- 阅读器键盘复制原先调用焦点页的 `SelectionController.textForFrame`，预设原始第 126–130 行却只复制第 126、127 行。先修正测试点击焦点位置，再以旧的页内键盘路径重现真实截断：[修复前日志](evidence/reader-keyboard-copy-before.log)。
- 新实现按原始选区、字符列与显式过滤条件跨 native page 读取；默认不传过滤条件，复制全部保留输出。Reader 菜单区分「复制全部保留输出」「复制过滤结果」「复制所选文本」；键盘复制使用同一个选区读取实现。
- 五项复制测试覆盖：跨页键盘复制、全部/过滤/非连续选区的剪贴板值、复制中途淘汰保持原剪贴板、选择后第一读取前淘汰不复制替代行、中文/emoji 列宽与矩形选择、跨页软换行。原生源行身份或列宽变化会中止复制；写入剪贴板前完整读取成功，不发布部分结果。
- 上一轮的五项复制测试使用内存原生协议页和预设 SelectionController 范围，证明范围读取与剪贴板语义。本轮补齐下述实际指针／长按到复制菜单的组件链路；仍不声称它是 iPhone 系统原生弹层或真机证据。
- 本次实际 Shell 的手机长按选区继续通过，并新增打开复制菜单截图、Esc 关闭菜单后 reader 与选区仍在，再附给 AI 的路径。没有触发命令或模型请求。

## 跨页拖选、触控复制与放大镜

- 128 行分页把活动拖动限制在起始页：第 126→130 行停在 127，反向停在 128。用同一组 macOS/iOS 平台变体临时停用跨页命中回调，8 组正反向、过滤／未过滤真实手势全部复现失败，随后恢复源码：[分页失败](evidence/reader-drag-before.log)。修复由 reader 根据实际滚动偏移和字体单元映射全局位置，再保留过滤行的原始索引。
- macOS 从首列拖选还会触发 Cupertino 路由的左边缘返回识别，焦点从终端移至 Navigator，导致 Cmd+C 不复制：[焦点失败](evidence/reader-drag-focus-before.log)。仅 macOS reader 关闭此返回手势，iOS/Android 保留原设置；不通过额外点击来掩盖失焦。
- iOS 长按跨页时放大镜仍使用起始页坐标，实测停后 66px：[放大镜失败](evidence/reader-magnifier-before.log)。它现与选区使用同一跨页单元及全局几何，正反向及过滤场景逐值验证放大镜指向手指所在行。
- 触控 Copy 菜单打开前完整读取选区；菜单打开后原生历史变化仍复制此前捕获文本。若读取前范围已淘汰，显示不可读取，不开复制菜单、不改原剪贴板；异步读取期间选区被清除或页面已关闭，也不弹出过期菜单。
- 新增 10 项 reader 回归：8 组实际跨页手势与复制、1 项触控范围失效、1 项水平滚动后的 Option 矩形拖选。过滤场景显示序号 126–130 对应原始行 378、381、384、387、390，复制不含隐藏行；矩形复制保留每行分隔，普通复制保留软换行。另增加 2 项普通终端异步菜单失效回归。手机采用 iOS 平台变体、390×844、固定字号，无软键盘唤起。
- 上一轮仅覆盖阅读区内跨页；本轮进一步验证以下边缘扩选路径。

## 阅读区边缘扩选与持续输出

- 先以 macOS/iOS、向上/向下 4 组真实手势复现边缘完全不滚动：[失败](evidence/reader-edge-before.log)。分页视口本身没有 scrollback，不能用它的滚动上限判断外层是否可继续阅读。现在使用 reader 的可视范围与统一 ScrollController，普通终端保留原生历史滚动逻辑。
- 活动拖动、尚未完成的触控复制菜单和键盘复制焦点会保留其起始页；结束交互并移开焦点后恢复正常分页回收。没有通过永久缓存所有页面来维持手势。
- 8 组组合覆盖 macOS/iOS、上下方向、过滤/未过滤：向下连续扩选越过两个分页边界，向上扩选到首行；指针移回内部停止、回到边缘继续，期间新增 100 行保持原位置。松手停止，完整复制后打开菜单使旧页回收，再关闭重开 reader 逐值比较原始行、像素偏移及选区。向上指针移到阅读区外的标题区域；macOS 向下移出窗口底边；手机向下停在屏幕内底边。过滤复制只包含每三行中的可见行。
- 上述加入输出刷新后还复现了构建阶段的父级 setState：[失败](evidence/reader-edge-refresh-before.log)。选区仍即时更新，reader 的 UI 刷新在子页构建期间合并到下一帧，不中断手势。
- 点过最新后开始选段，新增 20 行曾使输出在手指下跳动 440px：[失败](evidence/reader-selection-follow-before.log)。现在用户选段暂停跟随，恢复保存选区不修改跟随意图；显式点击最新后重新跟随后续输出。两平台均比较滚动位置和选区坐标。
- 本轮新增 14 项：8 项连续扩选、4 项取消/卸载停止计时器、2 项选段暂停与显式恢复跟随。不会唤起手机软键盘；触控仍为固定字号生产组件，并非真机。
- 该轮只读 CUA 复查仍报告 Mac 锁屏：[记录](evidence/macos-edge-lock-recheck.txt)，当时未启动新原生集成。本轮 D09 工作期间解锁已解除，恢复链路补验见上文。

## 视觉复核

- [D04 静默命令观察](evidence/macos/D04-silent-command-observation.png)：运行块与 AI 等待分列，没有伪造进度；暂停和中断为独立入口。
- [D06 原失败与新结果](evidence/macos/D06-failure-retained-after-correction.png)：两块保留不同命令、输出和退出码；错误仅小图标/状态文字，无整块红底。
- [M01 固定字号草稿](evidence/macos/M01-fixed-text.png)：原失败块、来源范围、AI 标签和输入区可见。
- [D07 待附加上下文](evidence/macos/D07-pending-contexts.png)：删除后的两个附件与请求一致；命令与来源范围分行，长命令省略时范围仍完整可见。手机 320px 组件测试同时核验范围不溢出。
- [D08 复制菜单](evidence/mobile-flows/D08-reader-copy-actions.png)：全部保留输出与所选文本分别命名，保留原选区；手机固定字号，菜单无溢出。
- [D08 原生 reader 重开](evidence/macos/D08-native-reader-reopened.png)：保留可见行及鼠标选区，固定标题/状态和单一滚动区。
- [D08 非连续片段](evidence/macos/D08-disjoint-context-preview.png)：附件明确显示 3 行、2 个片段，保留返回任务的草稿；发送范围与原生选区相符。
- [M02 横屏审阅](evidence/macos/M02-landscape-review.png)：已修正横屏使用桌面批准的问题，目标/命令和固定确认区保持可达。

- [M04 触控选段](evidence/mobile-flows/M04-touch-selected.png) 与 [返回任务](evidence/mobile-flows/M04-return-to-task.png)：选区、原始范围标签和保留草稿均可见，reader 没有 Composer 或嵌套纵向滚动。
- [M05 能力原因](evidence/mobile-flows/M05-task-capability-reason.png)：融合任务上的会话菜单显示 Normal 选中、Blocks 禁用及原因。
- [M05 重检结果](evidence/mobile-flows/M05-recheck-supported.png)：支持结果可见，Normal 仍被选中，Blocks 等待手动选择。
- [M06 横屏输入](evidence/mobile-flows/M06-landscape-ai-keyboard.png) 与 [深色短屏](evidence/mobile-flows/M06-short-dark-ai-keyboard.png)：程序、状态、AI 意图与单行草稿可见，无溢出；极短窗口优先保留输入和主操作。
- [M06 收起键盘](evidence/mobile-flows/M06-short-dark-keyboard-dismissed.png)：恢复阅读区域，保留原 AI 草稿；截图键盘空白仅为 inset，不是系统键盘。

这些截图只覆盖指定状态。完整 20 场景对照、任务主时间线的持续输出与回看、真实 macOS 恢复链路等仍需继续核验。reader 的边缘扩选和输出刷新已有组件行为证据，但本轮没有新增视觉截图。

## 复现

仓库根目录（Flutter/Dart SDK 已加入 PATH）：

```sh
dart run tools/sync_terminal_core.dart --check
python3 tools/ssh_boundary_lab/composer.py --bash /tmp/bash --ui --output build/block-ai-fusion-20261002/ssh-ui
```

`example/` 目录：

```sh
flutter test --no-pub test/ai/terminal_ai_workspace_test.dart --dart-define=AI_WORKSPACE_EVIDENCE_DIR=/absolute/path/to/ianvs-terminal/docs/design/block-ai-fusion-20261002/evidence/target-after --reporter expanded
flutter test --no-pub test/ai test/shell test/terminal_composer/terminal_mode_test.dart --dart-define=MOBILE_BLOCKS_EVIDENCE_DIR=/absolute/path/to/ianvs-terminal/build/block-ai-fusion-20261002/mobile-flows --reporter expanded
flutter analyze --no-pub lib/features/ai lib/features/shell lib/features/terminal_composer lib/l10n test/ai test/shell test/terminal_composer/terminal_mode_test.dart integration_test/terminal_ai_workspace_acceptance_test.dart
flutter test --no-pub test/shell/mobile_terminal_modes_test.dart --dart-define=MOBILE_BLOCKS_EVIDENCE_DIR=/absolute/path/to/ianvs-terminal/build/block-ai-fusion-20261002/mobile-flows --reporter expanded
flutter test --no-pub integration_test/terminal_ai_workspace_acceptance_test.dart -d macos --dart-define=TRAIL_FUSION_EVIDENCE=/absolute/path/to/ianvs-terminal/build/block-ai-fusion-20261002/macos --reporter expanded
```

`packages/ianvs_terminal/` 目录：

```sh
flutter test --no-pub test/composer test/terminal test/terminal_viewport_keyboard_test.dart test/terminal_viewport_mobile_gesture_test.dart test/terminal_viewport_render_test.dart test/terminal_viewport_alt_click_test.dart test/terminal_input_controller_test.dart test/terminal_text_cells_test.dart --reporter expanded
flutter analyze --no-pub lib/src/terminal lib/src/composer test/terminal test/composer test/terminal_viewport_mobile_gesture_test.dart
```

上述核心范围为 312 项。此前 OAuth 代理测试脚本尚未迁移到新 workspace；不能把它当成本轮模型质量或完整 UI 验收依据。

## M03 耗时与 D13 快速导航补验

手机预览与阅读页、桌面运行块已显示独立命令耗时；暂停 AI 后保留，完成后按原生时间戳冻结。另修复未完成的历史恢复覆盖“查看最新”的问题，新增修复前失败证据与三种时机的回归。最终 728 项应用、70 项共享终端、5 项原生／组件流程通过；实际静默命令耗时 12,023ms、显示 12.0s。截图、原始结果、日志与证明范围见 [完整补验记录](M03_ELAPSED.md)。

## 2026-10-03 真实模型与 Markdown 回复补验

真实模型最终运行 5 次请求、2 条实际本机命令，覆盖澄清、只分析计划、审批、退出 0 的有限结论，以及退出 7 后先诊断再提出独立只读检查。修复正文代替审批卡片、引用缺失、只有提案没有诊断，以及回复原始 Markdown 和原生等宽字体回退问题。最终 818 项应用回归、5 项原生／手机组件流程及 1 项真实模型流程通过；手机仍仅使用固定字号生产组件。证据、失败记录与逐场景对照见 [MODEL_SCENARIOS.md](MODEL_SCENARIOS.md)。D05 的焦点恢复与其余矩阵待验项继续保留，未将局部通过视为整体完成。

## 2026-10-03 D05 焦点恢复补验

键盘批准命令后，审批按钮消失导致焦点退回此前 Tab 经过的正文区域。现在桌面仍跟随当前任务且未转去其他操作时，最终回复会恢复 AI 输入焦点。11 项专项交互覆盖直接续问和不抢阅读／选区／弹窗／后台／新任务／手机键盘；全部 829 项应用及 5 项原生／手机组件流程通过。真实 macOS 验证没有再次点击输入框就能续写，并保留阅读器往返后的草稿。截图、失败复现和范围见 [D05_FOCUS.md](D05_FOCUS.md)。
