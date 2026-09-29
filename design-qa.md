# UI 验证入口与 Composer 专项设计 QA

产品 UI 的检查要求见 [人工验收清单](docs/compatibility/MANUAL_VERIFICATION.md)，
运行方法见 [TESTING](docs/TESTING.md)。以下保留通用入口，并记录本次用户选定方案 1 的
Composer 实现比较；这份专项记录不替代全应用人工验收。

- 组件与交互测试：`example/test/ui/`、`example/test/shell/`。
- 视觉回归测试：`example/test/design/`；当前黄金图保存在
  [goldens](example/test/design/goldens/)，不保存在 `docs/`。
- 平台约束及未解决的视觉差异见 [KNOWN_ISSUES](docs/KNOWN_ISSUES.md)。
- 一般 UI 新截图、对比图和运行日志写入 `build/`；基线更新必须先确认预期视觉变化。
  本次 Composer 用户明确要求的 imagegen 方案与独立 QA 证据集中在
  `docs/composer/redesign-evidence/`。

## Composer：最终独立设计 QA

final result: passed

审查日期：2026-09-29。独立比较角色：Composer visual-system subagent。采用
`product-design/skills/design-qa/SKILL.md` 与 `references/qa-rubric.md`。本次审查只修改本报告，
未修改产品代码，未访问本机 Warp。

在以下明确的组件渲染、交互与平台证据范围内，当前没有可执行的 P0/P1/P2。
首次独立比较为 **blocked**；Q1–Q7 的发现、修复与复核记录保留在下方，最终结论没有
覆盖或抹去早期失败。固定字体截图与初次 CUA 观察没有发现原生命令字体的比例字宽，
后续 Q7 以真实 macOS 应用中的字宽断言重现并验证修复。原生图标与指针操作另有主代理
CUA 观察；该结论仍不代表所有支持 OS、真实触摸板、真实 IME 或 VoiceOver 已完成手工验证。

### Findings：已关闭事项及证据

| 编号 / 原优先级 | 早期发现 | 当前修正及实际复核证据 | 最终状态 |
| --- | --- | --- | --- |
| Q1 / P1 | More 的 Esc 用例在退出动画结束前仍找到 `composer-copy-draft`，当时不能证明临时层已关闭。 | 最终 macOS variant 使用 `pumpAndSettle` 等待退出终态；断言菜单节点消失、草稿仍为 `git`、编辑器恢复焦点、终端 handoff 次数为 0。`composer-redesign-layout-final-2.log` 的此用例通过，9/9 总计通过。此前诊断曾显示焦点已恢复，因此本项记录为动画终态/平台验证修正，不虚构一个已证明的产品“Esc 永远不关”缺陷。 | closed |
| Q2 / P2 | 宽屏 context 将就绪状态排在行中部，偏离源图的尾部状态。 | [最终同密度 light](docs/composer/redesign-evidence/after/final/reference-light-completion.png) 与源同输入比较，cwd 已占用剩余空间，check 与就绪文字在 dock 右端；[dark](docs/composer/redesign-evidence/after/final/reference-dark-completion.png) 同样正确。窄窗继续堆叠，不强挤成一行。 | closed |
| Q3 / P2 | 深色就绪小字用 accent，对 dock 仅 3.593:1；选中 glyph 对 selection 仅 2.451:1。 | 就绪文字改用 `foreground`，当前宿主暗色配对 **14.988:1**；选中 glyph 与高对比标记使用 `onSelection`，暗色为 **6.646:1**。已实际查看最终 dark 与 [contrast-dark](docs/composer/redesign-evidence/after/final/contrast-dark-completion.png)，状态、glyph 和边线可辨。蓝色按钮仍使用其正确的 onPrimary 配对。 | closed |
| Q4 / P2 | 普通焦点边框为 1.5 logical px，在 2× 图中比源细边更重。 | `focusWidth` 当前 normal 1 / high-contrast 2；最终 source/light 同输入比较，普通细蓝边已与设计层级对应；[高对比 history](docs/composer/redesign-evidence/after/final/contrast-light-history.png) 仍有加强的边界和选择标记。 | closed |
| Q5 / P2 | 候选说明在 2× 字体和短窗溢出，出现条纹；初始日志报告 0.6–1.6 px。 | 保留的 [2× early](docs/composer/redesign-evidence/after/iteration-1/narrow-2x-completion.png)、[320 early](docs/composer/redesign-evidence/after/iteration-1/compact-320-completion.png)、[short early](docs/composer/redesign-evidence/after/iteration-1/short-window-longAlias.png) 与对应 final 实际同输入复核；[2× final](docs/composer/redesign-evidence/after/final/narrow-2x-completion.png)、[320 final](docs/composer/redesign-evidence/after/final/compact-320-completion.png)、[short final](docs/composer/redesign-evidence/after/final/short-window-longAlias.png) 无行溢出条纹，所有 127 状态捕获的异常和可见区域边界检查通过。 | closed |
| Q6 / P2 | 主代理后续原生 AX 检查发现 More/close 图标按钮没有可访问名称，自动建议没有可读开关状态。 | More/close 补充 `Icon.semanticLabel`；自动建议语义 label 明确包含 On/Off，同时保留 toggled 与 tap action。主代理 hot reload 后原生 AX 已显示“更多命令操作”与“自动建议 · 关”。独立审查读取了修改源码及语义节点/`SemanticsAction.tap` 回归日志，macOS variant **1/1 passed**；此修改不改变已核对的视觉布局。 | closed |
| Q7 / P2 | 原生命令编辑器使用比例字体；初次外观观察未发现此问题，固定 fixture 注册了 `monospace`，也掩盖了原生缺少该别名时的 fallback 问题。真实 macOS 集成中的 `TextPainter` 测得 `iiiiiiii` 为 **32.7679443359375**、`WWWWWWWW` 为 **119.0400390625**，等宽断言失败。 | `commandStyle` 保留宿主可注册的 `monospace` 首选，随后使用既有 `terminalPrimaryFontFamily`、`terminalFontFamilyFallback`（包括 Menlo 等真实等宽字体），最后接宿主语言 fallback；`resultStyle` 继承这条链。独立核对生产 editor 使用该样式，且测试读取真实应用主题而非固定字体 fixture。修复后原生 macOS 完整集成 **1/1 passed**，两组拉丁字符宽差须小于等于 **0.01 logical px**；日志没有输出修复后具体宽度，不补造该数值。 | closed |

另检查了真实鼠标事件分帧拖选详情的新增回归：detail 内 `EditableText` 必须持有焦点和
非折叠选区，结果列表仍打开，draft/selected result/ready lease/ownership/pending submission
保持原值。最终 9/9 日志与测试中的这些断言均已读取。不能以“节点没消失”替代真实选区证据。

### 比较目标、密度与完整视图证据

| 项目 | 最终比较值 |
| --- | --- |
| source visual truth | [option-1.png](docs/composer/redesign-evidence/concepts/option-1.png) |
| implementation screenshot | [final/reference-light-completion.png](docs/composer/redesign-evidence/after/final/reference-light-completion.png) |
| 源像素 | 1712 × 920 |
| 实现像素 | 1712 × 920 |
| 逻辑/CSS 对照尺寸 | 856 × 460；实际为 Flutter logical pixels，不是浏览器页面 |
| density normalization | 双方均按 DPR 2 比较，未缩放、裁切、合成或编辑图像 |
| 状态 | light、`git che`、checkout 选中、候选+独立详情、主操作“采用”、shell ready |
| 实现渲染 | 生产 Flutter Composer 组件及确定性 controller/provider fixture |
| 实际平台 | macOS 27.0 (26A428)、arm64；widget target 显式 macOS |

源与最终实现已在**同一次工具输入中分别以 original detail 显示**并共同评估，没有将
分开查看冒充一张并排对比图。全局比较三层 dock、上方列表/详情比例、编辑面和尾部主操作；
之后在同一原分辨率输入中聚焦 dock context/editor/toolbar（约 y=636–896）、两条候选与
详情（约 y=404–624）。这些 2× 区域的字形、图标、边框与间距已经清晰可读，因此无需
额外裁切或图像合成来判断细节。生成图的非产品背景不参与 Composer 比较。

额外实际打开并检查的最终状态：

- reference-dark empty / completion；light 和 dark 的主布局、禁用执行与就绪状态。
- compact-320 completion；双行工具栏、全部入口、候选详情入口和主操作。
- narrow-2x completion / longAlias / unknown / unknownLoading / More / completionDetails；
  大字行高、长内容折行、省略后的完整详情、菜单与错误恢复动作。
- contrast-light history / contrast-dark completion；边界、文字和选中标记。
- short-window longAlias / longHistory / shortcutHelp；受限高度下滚动表面与关闭动作。

不同尺寸截图用于响应式可用性检查，不与唯一宽屏源图做虚假的逐像素匹配。矩阵与字体
配置详见 [after/README.md](docs/composer/redesign-evidence/after/README.md) 和
[capture-manifest.json](docs/composer/redesign-evidence/after/final/capture-manifest.json)。

### 五项 fidelity 最终审查

| 必查面 | 最终观察与判定 |
| --- | --- |
| 字体与排版 | 命令为 16/1.5，候选 14/1.4，系统 UI context/action 12，层级与源对应。固定字体矩阵中 CJK 可读；2× 字体无压缩来规避布局，说明截断后有“详情”入口，完整描述可滚动、可选中。原生命令等宽由 Q7 修复后的真实 macOS `TextPainter` 断言证明；固定 fixture 的 `monospace` 注册不能提供这一证据。初次 CUA 外观观察曾漏掉比例字宽，已被后续测量纠正，不再以“原生字体正常”概括所有字体行为。 |
| 间距与结构 | 三层 dock、独立双 panel、尾部主操作保持。Ready 已靠右；窄窗 context/rail 有序换行。normal 1 px 细边与源相符，高对比仍加强。短窗结果由容器滚动；出现局部下一行不是溢出，持久动作仍在视口。没有新的重大比例、折行或密度漂移。 |
| 颜色与 tokens | 浅深色使用宿主语义配对；Q3 已修。当前源颜色计算：暗色就绪 14.988:1，暗色选中图标/标记 6.646:1，主按钮最小 4.591:1。边框、焦点、error、disabled、loading 都有明确角色。数字是实际 token 值计算，不宣称所有抗锯齿像素或任意宿主配色已认证。 |
| 图像质量与图标资产 | UI 为真实文字/控件/向量 glyph，无截图贴皮、手工 SVG 仿图或位图文字。采用/执行、history、More、auto toggle、ownership glyph 含义一致；现有字体资产及许可沿用。固定捕获的 SDK MaterialIcons 与原生 TrailLightIcons 笔画有差异；主代理后续 CUA 观察确认原生 TrailLightIcons 显示正常，不以固定字体截图冒充原生截图。 |
| 文案与内容 | “采用”与“执行”严格区分；自动建议为显式可逆开关，Tab仍可按需补全。More保留复制/撤销/重做/清空/终端输入/快捷键。未知结果提示先查看终端，恢复独立可操作；loading不会顶替所有权或错误。真实catalog英文详情属于动态内容差异，不伪造翻译。 |

### 明确接受的设计差异

- 不复制生成图中的伪模式下拉；当前仅有命令模式。
- Ready 使用宿主蓝色 check 与可读状态文字，不复制绿色 dot。
- 图标采用项目已有真实库资产，不把生成 glyph 栅格化或手工描摹成运行时资产。
- 详情来自实际 catalog，中文界面允许英文说明。
- fixture 不画方案图的示例 shell 输出；这些输出不属于 Composer UI，也不是运行证据。
- 窄窗堆叠 context 与 rail，次要提示按可用宽度缩减，全部功能通过按钮/More/详情保持可达。
- 宽屏候选处的末尾关闭按钮是有用的真实动作；它增强指针可达性，不伪造新模式。

### 比较与修复历史（保留首次 blocked）

| 迭代 | 当时发现与证据 | 后续行动与验证 | 当时结论 |
| --- | --- | --- | --- |
| implementation iteration-1 | 2×/320/短窗 row overflow；三张原图仍保留。紧凑菜单复制测试还未通过。 | 行高按真实缩放文字计算；最终三场景已实际看图且无条纹。复制的初始失败未直接归为产品缺陷，最终精确草稿内容与焦点回归通过。 | blocked |
| implementation iteration-2 / interaction runs | More/Esc退出过程尚未满足终态断言（Q1）；失败日志中菜单节点仍存在而编辑器焦点已经恢复。 | 等退出动画完全settle后验证菜单不可见、draft/focus/handoff；最终9/9包含该用例。此处不把测试平台/debug变量配置修正计作视觉修复。 | blocked |
| 独立 QA iteration-3 | 源图与同密度实现已在同输入实际比较；发现Q2尾对齐、Q3对比、Q4边宽；Q5大字溢出已有消除的视觉证据。 | 中间iteration-3图后来被清理，原图仅保留在本线程工具比较上下文；本报告不留下不存在的文件链接，也不重造当时图。可重复打开的历史文件是iteration-1三图，最终修复证据为final。 | blocked |
| 最终独立 QA | 同输入重新比较option-1与final/reference-light，实际看dark/2×/320/高对比/短窗/错误/菜单/详情。 | Q1–Q5均按上表关闭；capture127/127，interaction9/9，以及macOS应用1/1日志已读取。没有新的可执行P0/P1/P2。 | passed |
| 原生 UI 与 AX 补充 | 主代理成功连接已启动的 Trail Development 原生窗口，检查 TrailLightIcons、双面板、采用/复制/执行路径；发现 Q6 的可访问语义缺口。初次对系统字体的外观判断后来被 Q7 实测纠正。 | Q6 修复后原生 AX 名称/状态可见，定向语义回归1/1通过。主代理提供原生工具观察；独立审查核对了代码与日志。未取得可靠反馈的 CUA 修饰键组合不计作验证证据。 | passed（其后的字体复查重新阻断） |
| 原生字体复查 | Q7：主代理复看原生窗口发现比例字体，新增原生字宽断言；修复前 `iiiiiiii` 与 `WWWWWWWW` 宽差为 86.2720947265625 logical px，真实应用集成失败。固定字体捕获没有覆盖此问题。 | 恢复 blocked 判断；复用终端真实字体 fallback，保留现有 `monospace` alias 与宿主语言 fallback。修复不改变已注册该别名的固定截图字形。 | blocked |
| Q7 修复复核 | 独立读取字体链、生产 editor 用法、真实主题的字宽断言及修复前后完整日志。 | `/private/tmp/composer-redesign-native-font-fixed.log` 的完整原生集成1/1通过，其中两组字宽误差容限为0.01 logical px。Q7关闭，当前无未修的P0/P1/P2。 | passed |
| 最终封版复核 | Q7 后重新运行127状态捕获、9份既有金图与9项布局交互；旧 preview/golden 的 target label 已统一为 `Local Shell`，避免与独立 dialect 重复。 | 独立读取统一日志145/145通过；主代理另核对127张 final PNG 的前后 SHA256 完全一致，字体 fallback 没有改变固定 fixture。Release build/sign 日志也已读取并通过。 | passed |

### 验证记录与范围

已检查的终态日志与对应范围：

| 证据 | 结果 | 证明范围 |
| --- | --- | --- |
| `/private/tmp/composer-redesign-evidence-final.log` | 145/145 passed | Q7修复后的最终统一运行：127状态捕获、9份既有金图、9项布局交互。独立审查已读取日志；以下 earlier final-2 日志保留用于定位此前比较与修复。 |
| `/private/tmp/composer-redesign-after-final-2.log` | 127/127 passed | controller fixture状态、布局异常、editor/primary/More与结果/详情/菜单的视口边界；不等于逐张人工看过127图。 |
| `/private/tmp/composer-redesign-layout-final-2.log` | 9/9 passed | 采用再执行、history恢复、跨帧鼠标选详情、320px/2×、精确copy、auto开关、More/Esc、unknown恢复、详情/快捷键关闭与焦点。 |
| `/private/tmp/composer-redesign-macos.log` | 1/1 passed | 真实macOS Debug应用的Composer自动集成路径。日志同时报告`Failed to foreground app; open returned 1`，因此不是前台原生截图证据。 |
| 主线程 CUA 的原生窗口截图与 AX 工具输出 | 主代理已查看并操作 | 主代理重新绑定完整 Debug app 路径、等待启动后成功看到前台 Trail Development；TrailLightIcons 正常，候选双面板可见，点击“采用”只把 `git checkout` 写入草稿，More 菜单可读，点击复制显示“命令已复制”，点击执行无副作用 `printf` 后有输出且草稿清空/状态回到就绪。系统 Edit > Paste 把精确草稿 `printf 'composer-native-reviewn'` 回填空 editor，原生剪贴板往返有 AX 与图像观察；普通 Escape 回到 Composer 折叠入口。原生图片只在主线程工具输出，没有磁盘文件，不提供虚构路径。初次字体外观判断以 Q7 后续实测为准。 |
| `/private/tmp/composer-redesign-semantics-test.log` | 1/1 passed | More/关闭语义名称、自动建议 On/Off/toggled 状态与语义 tap action 的 macOS 定向回归。独立审查已实际读取日志与相应断言。 |
| `/private/tmp/composer-redesign-native-font-before.log` | 0/1，字宽断言 failed | 真实 macOS Debug 应用中复现比例字宽；记录两个实测宽度，证明固定截图和初次外观观察遗漏的原生问题。 |
| `/private/tmp/composer-redesign-native-font-fixed.log` | 1/1 passed | 使用真实应用主题验证命令拉丁字符等宽，并继续完成 Composer 编辑、采用、执行和恢复焦点完整集成路径；不扩大为所有字符或所有 OS 的字体认证。 |
| `/private/tmp/composer-redesign-release-final.log` | build / 本地签名验证 passed | 最终 `Trail.app` Release 构建成功，Mach-O alignment/host dlopen 与本地签名验证通过；这不是额外的 Release 原生交互测试或发布证明。 |

静态渲染采用固定 Roboto、JetBrains Mono、Noto Sans SC 和 SDK MaterialIcons，并注册
`monospace`；生产 app 的 UI 文字采用宿主字体，命令/结果采用 Q7 修正的终端字体回退链，
图标采用 `TrailLightIcons.ttf`。早期自动测试的前台激活失败不等于原生窗口最终不可用：
主代理后续重绑完整 Debug 路径并等待启动后已看到原生 UI，图标和实际指针路径可用。
初次“字体正常”的外观判断没有验证等宽，后来被失败的字宽断言推翻，再由修复后的原生
集成测试关闭 Q7。独立审查已核对该测试源码与日志，没有重新操作原生窗口；CUA 截图
保留在主线程工具输出而非磁盘，不能把固定字体 PNG 标记成原生截图。

精确剪贴板内容既有 mock 平台通道回归，也有主代理通过系统 Edit > Paste 实际回填草稿
的原生往返观察。CUA 的 Ctrl+C 尝试经临时 key trace 定位为收到 C 的 KeyDown/Up，
但 `ctrl=false`、`meta=false`；这次工具没有传递修饰键，不能归为产品 Ctrl+C 失败。
trace 已删除。普通 Escape 有原生折叠观察，其余未获可靠反馈的 CUA 组合键不计作
快捷键验证；相应行为以自动组件/集成测试为准。该捕获与交互矩阵仍不证明真实物理
触摸板惯性、真实 IME 输入、VoiceOver、其他支持 OS 或全部原生生命周期路径已手工
测过。浏览器 console 不适用于 Flutter 桌面，本次已检查对应 Flutter 渲染异常与测试日志。

### 最终实施检查表

- [x] Q1：More退出终态与draft/focus/handoff断言通过，区分动画settlement与产品修复。
- [x] Q2/Q4：同尺寸、同密度复拍并与源同输入比较；状态尾对齐、细蓝边可见。
- [x] Q3：Ready文字和选中glyph/marker采用正确前景；深色与高对比最终图复核。
- [x] Q5：2×、320与短窗历史/最终图比较，行高溢出消除。
- [x] Q6：原生 AX 语义缺口补齐，主代理复查名称/状态，独立审查定向语义节点与 tap 回归通过。
- [x] Q7：保留原生比例字宽失败证据，核对真实字体 fallback 链，修复后原生等宽断言与完整集成1/1通过。
- [x] Q7后最终145/145捕获/金图/交互统一运行与Release构建/本地签名日志已核对。
- [x] 最终loading/empty/unknown、长alias、详情、菜单与短窗可达性有代表性视觉和全矩阵自动证据。
- [x] 初次blocked记录、五项fidelity、允许差异、日志和平台/字体/真实输入边界均已保留。

暂无独立的 P3 修改要求。真实设备输入、VoiceOver、其他 OS 覆盖及原生截图的独立磁盘
归档属于已明确记录的后续验证范围，不把未执行的检查写成通过。
