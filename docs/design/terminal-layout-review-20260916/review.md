# Trail 四分屏布局优化：代码与现场核对版

日期：2026-09-16。代码基线：`e2f4efd0`。范围：macOS 主窗口、标签栏、四分屏标题、焦点、菜单和现有侧边栏。本轮完成只读分析及方案整理，未修改应用代码。

建议先解决状态与操作混淆、后台窗格可读性、操作归属和标签宽度，再考虑减少栏高。继续采用现有 Ianvs 主题及 macOS 窗口结构。上一版生成图仅是概念稿，不再作为功能依据。

配套[优化建议标注图](/Users/robinfai/personal/ianvs/ianvs-terminal/docs/design/terminal-layout-review-20260916/annotated-review.png)由内置 imagegen 生成，仅用于说明建议；下文 01–06 的现场截图才是本轮直接观察证据。[完整生成提示词](/Users/robinfai/personal/ianvs/ianvs-terminal/docs/design/terminal-layout-review-20260916/imagegen-prompts.md)。

## 必须修正的上一版判断

| 上一版建议或假设 | 本轮证据 | 修订决定 |
| --- | --- | --- |
| 把“粘贴按钮”收进更多菜单 | 实际是 bracketed paste 模式标记；点击调用 onActivate，只聚焦窗格 | 普通协议模式收为“模式”摘要/详情；不能把它当成粘贴命令。真正粘贴沿用已有输入、只读检查与确认流程 |
| 窗格标题直接改为目录 | title 会由终端标题事件更新；目录来自独立 shell integration 元数据 | 保留动态标题；仅在标题仍为默认 Profile 名且有可靠目录信息时，才考虑以目录作显示层补充或回退 |
| 强制四个终端同底色 | 当前确有非活动蒙层，但每个窗格还允许独立 Profile 主题 | 减弱或去除“非活动蒙层”，保留各 Profile 的颜色，不覆盖终端主题 |
| 对齐四个 prompt 首行 | 所有窗格已共用同一 viewport padding | 不改写或平移 shell 输出；首行差异可能来自输出/光标/滚动状态，具体原因未做帧级定位 |
| 分隔线改成 1px，保留宽热区 | 代码已实现静态 1px 线、8 逻辑像素拖拽区域 | 保留现有能力；仅检查边框与背景叠加造成的视觉厚度 |
| 标签完全按内容宽度 | 当前拖拽插入位置依赖统一 tabWidth，且标签聚合多种状态 | 优先“有最大宽度的等宽标签”；不在第一期引入随标题变化的宽度 |
| 优先压缩三层栏位 | 当前高度为 44 / 38 / 32 逻辑像素，单窗格不显示窗格标题 | 第一阶段保留高度；后续最多单独试验标签栏密度，不能把截图物理像素当布局单位 |
| 原有历史入口 | 顶部时钟图标是“回看”，关联近期画面与录制库 | 保留其名称和功能归属，不能泛化为普通历史列表 |

## 功能地图与优化落点

| 界面区域 | 代码中的真实职责 | 优化约束 |
| --- | --- | --- |
| 窗口工具栏 | 侧边栏开关、回看、搜索、默认设置与外观、命令面板 | 保留全局入口，不挤入每个窗格 |
| 标签栏 | 会话组选择、快捷编号、拖拽排序、拆入/拆出窗格、溢出选择、聚合输出/通知/徽章/错误等 | 缩短宽度不能丢失信号来源或拖拽目标；⌘数字仍表示标签位置 |
| 窗格标题 | 动态 title、位置编号、激活、拖拽；活动窗格提供拆分/缩放/关闭 | 新菜单必须绑定目标 sessionId；不能点击非活动窗格菜单却操作另一个活动窗格 |
| 非活动窗格状态条 | 远端上下文、进度、通知、徽章、ALT、鼠标、粘贴协议、焦点上报、键盘协议、只读 | 协议状态与任务状态需要分级；关键状态不应因获得焦点就消失 |
| 标签右键菜单 | 同目录新建、向右/下拆分、重开窗格、增大/交换/关闭窗格、关闭标签 | 区分“此窗格”和“整个标签”；继续显示禁用原因 |
| 命令面板 | 搜索、新建、配置、只读、清缓冲、SFTP、导出、能力、录制/回看等 | 保持全量命令入口；就近菜单是补充，不是复制整个命令面板 |
| 会话侧边栏 | 已有会话导航与目录分组；开启后隐藏横向标签栏 | 延续两种导航方式互斥；四分屏默认不强制开启侧栏 |
| 终端正文 | PTY 输出、选择、链接、搜索覆盖层、Profile 字体/颜色、输入模式 | 不用布局美化改写终端输出、首行、字体或颜色主题 |

代码入口：

- [工具栏和标签栏](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_chrome.dart:3)
- [窗格与终端布局](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_terminal_layout.dart:364)
- [窗格状态来源](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_terminal_layout.dart:1215)
- [标签右键菜单](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_command_actions.dart:832)
- [已有目录/远端信息展示](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_sidebar.dart:129)
- [共享主题适配](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/ui/foundation/app_theme.dart:6)

## 推荐方案

### 1. 状态与操作分开，先解决“粘贴”的误导

保留标题行，分成可拖拽身份区、状态区、操作区。状态区不再把普通协议状态画成与操作按钮相似的独立控件。

状态优先级建议：

1. **始终可辨认**：只读、远端主机、运行失败。处于活动窗格时也保留。空间不足时使用有名称和键盘入口的摘要，不静默消失。
2. **按需显示**：运行进度、新通知、新输出、应用徽章。保留定位来源窗格和查看详情的能力。
3. **详情收纳**：括号粘贴、MIME 粘贴、鼠标上报、焦点上报、扩展键盘等协议模式。默认显示一个“模式”摘要，展开后说明“括号粘贴：已启用”，避免叫“安全粘贴”等无法保证的名称。

代码目前只在非活动标题显示 indicators，活动标题换为 actions。这会把“切换焦点”和“改变信息结构”绑定。建议两块区域位置保持稳定，切换焦点只改变强调程度和可用操作。

证据：[模式标记构建](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_terminal_layout.dart:1349)、[活动/非活动分支](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_terminal_layout.dart:1920)、[标记点击行为](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_terminal_layout.dart:1998)。

### 2. 标签采用“等宽但设上限”，保留数量与状态预算

建议桌面初始最大宽度 **240 逻辑像素**，这是待验证设计值。少量标签靠左，不再平分整条栏；“+”紧随标签，余下空间留白。多标签时继续使用现有 180 / 104 的常规/紧凑阈值作为起点，并为溢出入口和“+”分别预留空间。

保留快捷数字、关闭、运行错误和新输出摘要；多窗格标签可显示一个小型窗格数量，窗格内部只保留自身序号，避免四处重复“窗格 n/4”。序号不是新的快捷键。

当前溢出分支会用溢出按钮替换“+”，需要在设计中保留可见新建入口。已有命令面板新建仍可用，本轮未动态创建大量标签验证溢出。

统一宽度是当前拖拽计算的前提，限定上限比改成每个标题各自宽度更容易保持稳定。若未来做可变宽标签，需要同步调整插入索引和拖拽反馈，不能只换视觉布局。

证据：[宽度计算](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_chrome.dart:1155)、[插入位置计算](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_chrome.dart:987)、[溢出与新建分支](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_chrome.dart:1336)。

### 3. 保留动态标题，身份信息按可靠程度补充

窗格显示顺序建议为：**位置编号 → 动态标题 → 可选目录/主机信息**。

第一阶段保留真实 title，仅把“窗格 n/4”缩成位置标识。目录只从 shellIntegration.currentDirectory 读取，不解析彩色 prompt；没有元数据时保留原标题，不伪造“~”。目录和主机可放在提示信息中。未来若标题与默认 Profile 名相同，可考虑用目录 basename 作显示回退，但不修改会话底层 title。

活动标签本来会跟随活动窗格标题变化，新增的展示策略必须同时定义标签和窗格如何协调，避免一侧显示目录、另一侧看起来像另一个会话。

证据：[动态标题更新](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/sessions/session_controller.dart:5141)、[shell 元数据](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/sessions/session_state.dart:855)、[现有动态标题测试](/Users/robinfai/personal/ianvs/ianvs-terminal/example/test/widget_test.dart:1626)。

### 4. 窗格操作就近、稳定且区分作用范围

活动窗格的常用操作保持可发现：**分屏、放大/还原、更多**。宽度充足时可继续分别显示向右/向下拆分；变窄时收为同一分屏菜单，不让命令直接消失。

非活动窗格保留状态与“更多”入口。更多菜单先提供本窗格的拆分、缩放、增大、交换、关闭；重开和关闭整个标签放在明确标出的标签级区段。关闭窗格与关闭标签不相邻堆成两个相似图标。

无论从活动或非活动窗格打开，执行对象都应固定为发起菜单的窗格。鼠标、键盘聚焦均能发现入口，避免只在悬停时出现。现有只读、缩放限制、默认 Profile 缺失、最小行列限制与禁用理由必须复用。

菜单中的“复制当前目录”实际会新建会话并发送进入原目录的命令，容易被理解成复制路径到剪贴板。建议改成“在当前目录新建标签页”，保留远端目录不可用理由。

证据：[现有窗格按钮及宽度阈值](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_terminal_layout.dart:1813)、[同目录新建实现](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_command_actions.dart:1041)。

### 5. 焦点明确，后台正文仍可读

保留活动窗格细边框和标题强调，降低非活动蒙层强度，优先让用户能同时阅读四个窗格。暗色主题当前 inactiveScrim 为 0x8A000000，约 54% 黑色覆盖；正文颜色被明显压暗，现场切换焦点可观察到。

第一版建议取消覆盖正文的强蒙层，以边框、标题和当前光标作为主要线索；若需要“专注”效果，再作为可选偏好验证。每个 Profile 的配色继续生效。不要全局直接修改 inactiveScrim：录制库也使用这个 token，应该采用窗格专属语义或局部调整。

边框厚度和正文几何最好在活动/非活动间保持一致，只改变颜色，避免焦点切换影响可用内容尺寸。

证据：[非活动覆盖层](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_terminal_layout.dart:777)、[暗色蒙层值](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/ui/foundation/app_theme_tokens.dart:345)、[Profile 配色来源](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_sessions.dart:1251)。

### 6. 保留现有密度和拖拽能力，不把装饰调整当功能优化

窗口栏 44、标签栏 38、窗格标题 32 先保持。单窗格本来就没有窗格标题，多窗格才需要身份与操作层。侧边栏打开时横向标签栏本来就隐藏，不新增重复导航。

分隔线已有 1px 视觉线和 8px 拖拽区，沿用即可。内容 padding 已是用户配置，不能固定改成 12px。终端首行位置由终端帧决定，长命令由终端单元格与 resize 处理，不做应用层省略或视觉“修齐”。

证据：[单窗格标题隐藏](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_terminal_layout.dart:419)、[共用 padding](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_state_shortcuts_status.dart:262)、[分隔线](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_command_menu.dart:630)、[侧栏与标签栏互斥](/Users/robinfai/personal/ianvs/ianvs-terminal/example/lib/features/shell/shell_screen_chrome.dart:123)。

## 本轮实际查看的步骤

### 01 · 四分屏初始状态 — 可用，信息层级需要调整

两个标签和四个窗格可见。活动标题展示操作，非活动标题展示“粘贴”标记，正文亮度差异明显。保留清楚的分屏结构和焦点边框。

![01 四分屏初始状态](/Users/robinfai/personal/ianvs/ianvs-terminal/docs/design/terminal-layout-review-20260916/01-current-window.png)

### 02 · 标签右键菜单 — 功能完整，作用范围与文案有改进空间

菜单有拆分、增大、交换、重开、关闭等；不可用项给出原因是优点。“复制当前目录”的行为需依据代码理解；窗格与标签关闭需要更明显区分。

![02 标签右键菜单](/Users/robinfai/personal/ianvs/ianvs-terminal/docs/design/terminal-layout-review-20260916/02-tab-context-menu.png)

### 03 · 聚焦右上窗格 — 切换正常，状态与按钮相互替换

右上正文变亮并出现操作图标；左上变暗并出现模式标记。验证“粘贴”不是只有某些窗格才提供的操作按钮。

![03 切换活动窗格](/Users/robinfai/personal/ianvs/ianvs-terminal/docs/design/terminal-layout-review-20260916/03-second-pane-focused.png)

### 04 · 命令面板 — 全量能力入口存在，范围提示可加强

面板包含只读、搜索、新建、SFTP、录制/回看等，并说明不可用理由。建议会话级命令补充清楚的目标窗格信息。仅打开查看，未执行清空、粘贴、录制或远程操作。

![04 命令面板](/Users/robinfai/personal/ianvs/ianvs-terminal/docs/design/terminal-layout-review-20260916/04-command-panel.png)

### 05 · 会话侧边栏 — 替代导航正常，四分屏可用宽度减少

侧栏存在目录分组，新建入口可见；横向标签栏自动隐藏。继续作为多会话场景的可选导航，不把它强制加入本次四分屏默认方案。

![05 会话侧边栏](/Users/robinfai/personal/ianvs/ianvs-terminal/docs/design/terminal-layout-review-20260916/05-session-sidebar.png)

### 06 · 恢复初始导航与焦点 — 已完成

侧栏关闭，回到横向标签栏和左上活动窗格。终端窗口、标签与会话均保留。查看侧栏导致正常终端 resize，未执行终端命令或会话关闭。

![06 恢复窗口](/Users/robinfai/personal/ianvs/ianvs-terminal/docs/design/terminal-layout-review-20260916/06-restored-window.png)

## 实施顺序与验收边界

**第一阶段：语义与可读性。** 修正“粘贴”模式展示、同目录新建文案，稳定状态区/操作区，减弱正文蒙层，保留标题和关闭作用域。

**第二阶段：布局与发现性。** 标签等宽上限、“+”与溢出并存、就近窗格菜单、紧凑编号。保留拖拽能力，必要时同步修改索引计算。

**第三阶段：扩展状态复核。** 窄窗口、多标签、仅单窗格、缩放后的隐藏窗格信号、远端/只读/错误/运行进度、长动态标题、不同 Profile 主题、文本缩放与键盘访问。第二阶段不以所有状态都塞进日常标题为目标。

后续实现的验证重点：

- 标签宽度策略及溢出；现有“平分可用宽度”的测试是当前明确契约，需要有意识更新。
- 标签排序、窗格移入/移出标签、分隔线拖拽和最小行列限制；保持 PTY/session 标识稳定。
- 获得焦点后关键状态仍可见；普通模式有完整详情；非活动窗格菜单固定正确目标。
- 缩放/还原、关闭窗格/关闭标签、重新打开、已有只读和粘贴确认行为不回退。
- 动态标题更新不触发不必要的布局变化；共享主题与独立 Profile 外观均保留。
- 键盘入口、菜单焦点返回、语义名称、非仅靠颜色区分焦点；触控与 iOS 路径不受 macOS 密度改动影响。

现有测试落点：[标签布局与输出聚合](/Users/robinfai/personal/ianvs/ianvs-terminal/example/test/shell/shell_screen_phase1b_test.dart:174)、[窗格标题操作](/Users/robinfai/personal/ianvs/ianvs-terminal/example/test/widget_test.dart:1564)、[缩放与关闭](/Users/robinfai/personal/ianvs/ianvs-terminal/example/test/widget_test.dart:1777)、[只读粘贴保护](/Users/robinfai/personal/ianvs/ianvs-terminal/example/test/widget_test.dart:3412)。

本轮仅阅读代码、测试源码和实际窗口，未执行单测、构建、完整端到端测试、VoiceOver、文本缩放或多 Profile/远端状态验收；也未核验运行中的应用二进制与此 Git 提交完全一致。现场截图与代码结构相互印证，但不能据此宣称所有隐藏状态已经验证。
