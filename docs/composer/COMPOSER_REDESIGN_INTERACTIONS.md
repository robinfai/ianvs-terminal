# Composer 功能、状态与交互梳理

日期：2026-09-29。审查基线：`composer` 分支 `5f164bea`。

本文用于本轮 Composer UI 重设计：把每项现有能力的用途、状态表达、输入行为和验收边界写清楚。
文中的“当前”指上述提交，不表示建议已经实现。视觉结构由 ImageGen 方案决定后再落实；本次只编写本文，未修改产品代码或测试。

证据来自当前源码、测试源码、已有设计预览定义，以及用户明确提供的历史面板和路径补全截图。
历史面板截图已检查：顶部目标和目录标签、无文字状态图标、底栏多枚图标、历史选中行及底部快捷键提示均可见。
没有操作本机 Warp，没有重新执行应用测试，也没有把源码推断描述成物理触摸板、真实输入法或 VoiceOver 实测。

## 证据索引

以下行号固定于审查基线；函数名用于改版后继续定位。

| 简写 | 源文件 | 关键入口 |
|---|---|---|
| `controller` | `packages/ianvs_terminal/lib/src/composer/terminal_composer_controller.dart` | history 107–208；灰字 211–252；权限/可执行 264–300；身份更新 309–405；Tab/请求 408–508；选择/接受 511–583；撤销 614–622；提交/恢复 624–673 |
| `view` | `packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart` | 浮层/滚动 123–176；键盘 178–288；状态 295–305；元信息 347–390；底栏 418–531；反馈/恢复 533–588 |
| `suggestions` | `packages/ianvs_terminal/lib/src/composer/composer_suggestions.dart` | 布局 34–231；历史 281–295；行/悬停/语义 297–390；类型 430–449 |
| `editor` | `packages/ianvs_terminal/lib/src/composer/composer_editor.dart` | 原生编辑与视觉行 34–77；TextField 119–151；灰字独立绘制 165–250 |
| `models` | `packages/ianvs_terminal/lib/src/composer/completion_models.dart` | 查询身份/允许补全 10–53；候选字段 57–124；响应校验 128–164 |
| `pane` | `example/lib/features/terminal_composer/composer_pane.dart` | provider 8–85；会话轮询 101–138；提交 141–169；焦点 221–242；入口/raw 切换 247–298 |
| `layout` | `example/lib/features/shell/shell_screen_state_terminal_layout.dart` | 桌面、只读、退出会话的装配 884–898 |
| `contract` | `docs/protocols/COMPOSER_V1.md` | 静态/本地补全 16–77；shell 提交 79–141 |
| `tests` | `packages/ianvs_terminal/test/composer/composer_test.dart` | 身份/取消、提交、Tab、IME、缩放测试 |
| `suggestion tests` | `packages/ianvs_terminal/test/composer/composer_suggestions_test.dart` | 历史/灰字、复制、软换行、触摸板测试 |
| `app test` | `example/integration_test/composer_acceptance_test.dart` | 真实应用 local zsh、路径、触摸板、焦点测试 |
| `previews` | `example/lib/ui/previews/composer_preview.dart` / `composer_preview_data.dart` | 深浅色、窄窗、历史、灰字预览 |
| `captures` | `example/test/design/composer_visual_capture_test.dart` | 3 种尺寸/主题 × 3 种场景；尚无发送/未知/拒绝等状态图 |

## 现有功能完整矩阵

| 功能 / 用途 | 当前实现与触发 | 当前状态表达 / 问题 | 重设计要求 |
|---|---|---|---|
| 开启 Composer | 桌面会话底部文字入口；每个 session 保有自己的控制器（`pane:247`、`layout:884`） | 开关与“运行中 · 传统输入”共用按钮，运行态再次点击仍会切换 enabled | 保留文字入口；运行态显示输入当前由终端接管，动作名称应准确说明开启或关闭后续 Composer 恢复 |
| 本地草稿 | 原生 TextField，草稿只在 session 内存；关闭会话销毁（`controller:33`、`editor:119`） | 可编辑与可执行不是同一状态，当前“草稿”图标难解释 | 明确“命令编辑器”；仅编辑状态保持能编辑/复制，不能暗示可直接执行 |
| 执行目标 | `targetLabel` 信息标签，不可点击（`view:349`） | 外观近似可切换 pill，但没有切换逻辑 | 作为被动元信息展示；无目标选择功能时不要画下拉箭头 |
| 当前目录 | 可信 shell cwd；长路径省略，Tooltip 给全文（`view:356`） | 文件夹图标与底栏自动候选按钮重复语义 | 保留目录语义，视觉上与可操作控件区分；不伪装成目录浏览器 |
| shell 就绪 | 只有 active + ready + lease + submit + 非空 + 无 IME 才能 run（`controller:264`） | 顶部仅 14px check，实际文字在 Tooltip | 可见短文本“就绪”或“仅编辑”，状态不能只靠颜色或悬停 |
| 多行编辑 | Shift/Ctrl/Option+Enter 插入换行，最多 6 行后内部滚动（`view:187`、`editor:127`） | hint 只列 Shift；软换行与命令多行容易混淆 | 保留原生编辑；主要提示列常用 Shift+Enter，其他组合放快捷键说明 |
| Tab 按需补全 | 自动候选关闭仍查询本地；唯一结果插入，多结果打开并选第一项（`controller:408`） | 曾因文件夹开关被理解成补全总开关 | 持续说明 Tab 可补全；自动候选开关不能成为 Tab 的前置条件 |
| 中间 token 补全 | 替换被查询 token 的确定范围，保留右侧参数（`controller:558`、`contract:27`） | UI 未说明精确替换，但行为正确 | 接受、撤销均保留选区/光标合同，不改成从光标简单追加 |
| 路径补全 | cwd、`../`、绝对、`~/`、空格、Unicode、symlink；只读显式目录（`contract:58`） | 当前已修复父级路径；非空选区 Tab 提示先定位光标 | 所有结构方案必须保留；仍不支持的表达式给准确反馈，不静默失败 |
| 自动建议 | 每会话关闭默认；开启后自动本地 IO 并显示菜单；关闭后静态/历史灰字仍可存在（`controller:289`） | 文件夹图标不表达开关；“自动补全”容易被理解成所有补全能力 | 用有文字的“自动建议”或“自动展开”控件，明确开/关；帮助说明“Tab 始终可用” |
| 补全列表 | 顶部向上浮层；宽窗右详情，窄窗内联说明（`suggestions:34`） | 宽窗无选中项时详情侧留空；列表缺少明确标题；主执行按钮仍显示 Run | 展示简短“补全”/结果数量与选中态；采用当前候选的主动作必须与 Enter 对齐 |
| 候选类型 | directory/file/option/alias/script/command/argument 各有图标和类型词（`suggestions:430`） | `riskHint` 只替换成警告图标；类型和风险可能互相覆盖 | 类型保持可读文本；如保留既有风险标志，需有明确可读含义，不能仅依赖警告形状 |
| 候选详情 | 宽窗单独卡片，长内容可滚动；窄窗最多一行说明（`suggestions:170`） | 小窗长 alias 定义只在行中截断，无法完整检查 | 选中项的详情必须有可达完整阅读方式；不要因紧凑布局完全丢失说明 |
| alias / package scripts | alias 只插入名称，定义仅显示；scripts 只读当前 cwd 的 package.json 名称（`contract:34`、`:65`） | 当前类型图标与终端操作/执行图标容易相似 | 图标族保持一致，标签明确“别名/脚本”；查看候选不能执行脚本或展开 alias |
| 灰字预测 | 最近匹配历史优先，其次静态候选；独立绘制、不入草稿（`controller:211`） | 主动作 Enter 执行原草稿，→ 才采用预测；需让行为清楚 | 灰字区别于已输入内容；→ 采用提示仅在实际有预测时出现，不因重设计合并到 TextEditingValue |
| 命令历史 | ↑ 首条视觉行、Ctrl+R 或按钮；当前 shell 真实历史，去重、内存保存（`controller:107`） | 按钮显示选中背景，但再次点击只 open，不关闭 | 将其做成真实开关，或改为不暗示 toggle 的入口；历史打开时明确输入框用于筛选 |
| 历史筛选 | 当前输入按词、忽略大小写过滤；最近命令靠近输入框（`controller:139`） | 标题仅“命令历史”，未说明正在搜索；筛选文本暂时取代草稿 | 状态提示“筛选历史”，且明确取消将恢复原草稿；保留关键词强调与结果数 |
| 历史采用 | Enter/Tab/点击仅写回草稿，不执行，可撤销（`controller:178`） | 主按钮 disabled 且 Tooltip 可能写“请输入完整命令”，与真实原因不符 | 主动作变为“采用”且同步 Enter；不允许一次采用就执行 |
| 历史取消 | Esc 或 Down 越过最新恢复进入前文本和选区（`controller:197`） | 只有 footer 提示 Esc；显式关闭入口不足 | 关闭/取消应可用指针操作并恢复原值；不能丢失选区或过滤前草稿 |
| 悬停/滚动 | onHover 只更新高亮；navigation revision 才自动定位（`view:123`、`suggestions:320`） | 此问题刚修复，应视为关键稳定行为 | 鼠标停住时条目经过不重选；任何普通通知不得取消 pan/zoom 或惯性；键盘导航才接管位置 |
| 复制草稿 | 宽窗底栏，复制完整已输入内容，不含灰字（`view:439`） | 无复制成功反馈；“仅保留于当前会话”贴在复制 Tooltip 易让人误以为剪贴板也是 session 私有 | 名称只说“复制命令”；短暂“已复制”反馈；会话草稿生命周期说明放在编辑器说明中 |
| 撤销/重做 | Cmd+Z/Cmd+Shift+Z（非 macOS Ctrl）；200 条，保留 selection；宽窗只有 Undo 按钮（`controller:614`） | 重做不可见；窄窗移除两个菜单入口中的一个，无统一编辑操作入口 | 保留快捷键；低频编辑动作可汇入溢出菜单，窄窗仍可触达复制/撤销/重做 |
| 清空草稿 | Ctrl+C 清空本地草稿，不向 PTY 发信号（`view:283`） | 行为接近终端取消，但当前无可见提示；非 macOS 与 copy 快捷键存在潜在竞争 | macOS 保持既有语义且可撤销；跨平台要显式核对 selected-text copy，不能误称 Ctrl+C 是运行中终止 |
| 返回传统输入 | 底栏 return 图标或 Esc 层层关闭后触发（`view:266`、`:434`） | return 符号也常表示提交/Enter，与真正执行箭头并列有歧义 | 用“终端输入”文字加明确终端图标；此操作不发送草稿、不清空草稿 |
| 提交命令 | Enter 无历史/已选候选时，或 run 按钮；一次 lease、唯一 submission id（`controller:624`） | 箭头图标容易被理解成 AI 发送；候选/历史态按钮语义与 Enter 不一致 | 用明确“执行”/“采用”主动作；sending 避免再次触发，选中候选时主操作只采用 |
| 提交中修改 | 允许继续写草稿；晚到 accepted 只清除原 editorRevision（`controller:640`） | UI sending 仅通用编辑图标，用户看不出在等待接收确认 | 短文本“正在提交”；不可重复提交，但允许保持下一条草稿，晚结果不能清空新内容 |
| 运行 / 续行 / 密码 | host 隐藏 Composer、焦点回终端；ready 后回编辑器（`pane:221`） | 当前 running/suspended 都写“运行中 · 传统输入”，suspended 原因并不一定是命令运行 | 如只有 suspended 数据，可准确写“终端输入中”；不要猜测密码内容或伪造进度 |
| 拒绝 | 留草稿，转 draft，等新 ready；状态“Shell 未接收”（`controller:655`） | pendingSubmission 仍存在，恢复按钮冗余且有后续泄漏 | 保留消息、保留草稿；结束这次 pending，不能提供会误恢复旧已确认命令的入口 |
| 结果未知 / 恢复 | 锁住 unknown，轮询 ready 不能解锁；手动恢复不重新提交（`controller:363`、`:664`） | 提示可被 completion status 覆盖；“恢复草稿”不能解释原稿本已保留 | 持续、独立的执行结果提示；“查看终端”与“继续编辑”动作准确，绝不自动重试 |
| 切换标签 / 窗格 / 生命周期 | inactive 取消 provider、关闭历史并恢复原稿；各 session 独立（`controller:370`、`pane:101`） | 焦点恢复由状态转换控制，重布局不能抢焦点 | 保留隔离、取消和用户当前编辑意图；面板显示不应夺取已切到其他窗格的焦点 |
| 不支持的环境 | 无可信适配器只能 draft/静态建议；桌面非只读才装配（`layout:884`、`contract:87`） | 泛化“shell 未就绪”未能解释只编辑能力 | 显示“仅编辑 · 可复制到终端”；没有能力证据时不能标成已连接/可执行 |

## 状态表达矩阵

执行状态与建议状态应是两个独立维度。顶部元信息表达命令将到哪里，以及当前是否可执行；建议面板内部表达候选是否正在加载。
不可让补全 loading 图标替换结果未知、发送中等执行状态。

| 状态 | 输入是否可编辑 | 主动作 | 必须可见的信息 | 可操作反馈 |
|---|---|---|---|---|
| 未启用 | 原终端接收输入 | 打开命令编辑器 | “命令编辑器”入口 | 不改变现有终端 buffer |
| ready + 空草稿 | 是 | 执行 disabled | “就绪”；输入提示 | Tab 可按需请求；↑ 可查看历史 |
| ready + 非空草稿 | 是 | 执行 | 目标/cwd；Enter 执行 | 提交只使用实际草稿 |
| ready + 灰字 | 是 | 执行 | → 采用建议；Tab 补全 | → 接受后仍停留编辑器 |
| 多候选 + 未选中 | 是 | 执行或先明确选择（必须同 Enter） | “补全”及数量；↑↓选择 | 不能把不可见候选自动当成已接受内容 |
| 多候选 + 已选中 | 是 | 采用 | 候选名称、类型；Enter/Tab 采用 | 采用后关闭菜单，下一次 Enter 才执行 |
| history + 有结果 | 筛选文本可编辑 | 采用 | “搜索历史”及数量；Esc 恢复草稿 | 点击采用/关闭都保留编辑焦点 |
| history + 空结果 | 筛选文本可编辑 | 采用 disabled | “没有匹配的历史命令” | 可清除筛选或取消；不可提交筛选词 |
| 查找候选中 | 是 | 不重复 Tab | 建议区域的局部 loading | 不闪烁覆盖 shell 状态；取消后旧结果不可返回 |
| 无匹配 / 不支持表达式 | 是 | 依草稿/lease 决定 | 低干扰提示，无伪错误颜色 | 修改文本/光标后清理过期反馈 |
| 非空选区 + Tab | 是 | 无替换 | “先定位光标；→ 取消选区” | 不覆盖整段草稿 |
| IME composition | 原生输入法处理 | 不执行、不采用 | 保持输入法浮窗，不额外抢焦点 | Enter/Tab/方向键交回输入法 |
| submitting | 是 | 提交中 disabled | “正在提交”；实际目标 | 晚 accepted 不能清除更新后的草稿 |
| running | 原终端 | 终端输入 | “命令运行中” | Ctrl+C 由终端处理；不再操作 local draft |
| suspended | 原终端 | 终端输入 | “终端输入中” | 续行/密码/交互程序不由 Composer 接管 |
| rejected | 是 | 等待新 ready 后执行 | “未执行，草稿已保留” | 不自动重试；无恢复旧命令按钮 |
| unknown | 是 | 执行 disabled | “执行结果无法确认，请先检查终端” | 查看终端；继续编辑只解除本地恢复态，不提交 |
| 无适配器 / draft | 是 | 执行 disabled | “仅编辑”；可复制到终端 | 保留静态候选；不得假装能本地目录 IO |
| inactive / exited / replay | 不触发请求 | 按宿主可用性处理 | 无可执行误导 | 不泄漏别的 session 草稿；Replay 继续只读 |

## 需要优先修正的确定缺口

### P0：执行结果未知不可被建议反馈覆盖

当前 `controller:624` 将 unknown 同时写入 `ownership` 与共用 `status`。
随后 `_edited` 可以排队建议请求，`_requestCompletions` 未排除 unknown，
`publishCompletions` (`controller:382`) 将 `status` 写成 `unsupported_context` 或空字符串。
`view:533` 虽然因为 ownership unknown 仍保留反馈行，但 `_statusText()` 只按 `status` 映射，
可能显示补全反馈，甚至空行。`view:368` 同时使用补全 loading 替换状态图标。
这不自动执行命令，但掩盖了“是否已执行还未确定”的关键事实。

建议：提交结果状态与完成反馈分开存储/派生；unknown 的文案与操作由 ownership/pending transaction 决定，优先且持久。
是否允许 unknown 继续静态补全可以保留既有编辑便利，但不能恢复 Run 或改变提交结果提示。

必须新增的行为测试：

1. 提交返回 unknown；保持 pending 命令文本与提交 id，Run disabled。
2. 输入新草稿、移动光标、Tab 触发静态查询，分别返回成功空结果、有候选、不支持、异常；unknown 提示始终可见。
3. localSuggestions 开/关、开始/结束 loading、shell ready polling 都不能抹掉 unknown，也不能发生第二次 submit。
4. “继续编辑”是显式动作，不调用 submit；恢复时只在当前草稿为空才取回原提交文本，新草稿不被覆盖。
5. 修改新草稿前后的选区应保持，不能把恢复动作当作接受预测或历史。

### P0：pendingSubmission 必须在已确定结果时结束

`controller:632` 对所有 run 写入 pendingSubmission，accepted/rejected 分支都没有清除；仅 recoverDraft 清除。
`view:548` 则在任何 status 行出现时，仅凭 pendingSubmission 非空就显示“恢复草稿”。
因此一次成功提交后，回到 prompt 并得到“无匹配”反馈，也可能出现上一次命令的恢复入口。
若此时草稿为空，`recoverDraft` 会重新填入已经接收过的命令；若非空也会改变 ownership。

建议：accepted/rejected 已确认的交易立即清掉 pending；unknown 才保留恢复资料。
恢复入口只在 unknown 且存在相应 pending 时可用；controller 也做相同条件检查，不能仅依赖按钮隐藏。
保留 accepted 后只清理匹配 revision 的行为，不能为清 pending 连带清除较新的草稿。

必须新增的行为测试：

1. accepted → ready → 无匹配/选区提示/补全错误，都不出现恢复入口；pending 为空。
2. rejected 草稿与选区保持且 pending 为空；下一次独立提交使用新的 id。
3. accepted 的结果晚于新草稿，新的文本、选区、撤销历史按既有合同保留，pending 正常清空。
4. unknown 仍可恢复；其他 ownership 直接调用 recoverDraft 是无副作用操作。
5. accepted/rejected 后绝不能因任意辅助反馈复活前一次执行的文本。

### P1：主动作与 Enter 的行为一致

`view:187` 的 Enter 优先 history → selected completion → run；底部按钮 `view:515` 永远 run，
历史状态还因 `canRun` 为 false 显示“请输入完整命令后执行”。这是已存在的语义差异。

建议建立单一派生主动作：选择历史/候选时“采用”，正常草稿“执行”，submitting“提交中”。
主动作文本、图标、enabled、Tooltip、快捷键 hint 与点击 handler 使用同一判断。
灰字仍由 → 接受；Enter 继续只执行真实草稿，不自动接受灰字。

验收：每一种主动作状态均测试点击与 Enter 结果相同；采用必须使 submit 次数保持 0，第二次 Enter 才增加至 1。
历史空结果不能执行筛选文本；未选择候选不能擅自采用第一项。

### P1：把默认关闭的自动候选说清楚

当前 bottom folder toggle 只靠图标和 Tooltip 表达，用户此前已将它理解成目录补全所需开关。
Tab 能按需查询的事实已经实现且有回归，不能通过重设计退回“先开自动候选”。

建议显式标签与开/关状态。适合三种视觉结构的共同语义为：
“自动建议：关/开”，帮助文案“输入时自动显示候选；Tab 始终可补全”。
目录标签继续用目录图标；建议开关采用列表/建议语义图标，不再复用文件夹。

验收：关闭状态下 `ls ./`、`cd ../../../`、绝对路径和 `~/` 的 Tab 工作；开启后输入弹出菜单；
再次关闭立即撤销旧 IO 权限和菜单，不隐藏可用的历史灰字；设置仅影响当前 session。

### P1：明确历史的搜索、取消与采用

当前历史与草稿共用 TextField，取消能精确恢复，但视觉上没有明确搜索模式；历史按钮显示 toggle 选中态却不关闭。
建议打开后显示“筛选历史”，提供可点击关闭动作，按钮二次点击也应关闭并恢复原草稿。
保持最近命令位于输入框附近，键盘 ↑ 按时间回溯，不因新视觉排序改变已有肌肉记忆。

验收：空草稿/非空草稿/选区进入历史均能关闭恢复；过滤只影响列表；点击、Enter、Tab 都仅采用；
Down 越过最新恢复草稿；多行及软换行中非首条视觉行的 ↑ 不打开历史。

### P2：补齐动作反馈与窄窗可达性

- 复制后以轻量“已复制”短暂反馈，不占用执行结果状态；复制失败也不能修改草稿。
- 复制/撤销/重做可归入“更多”，但窄窗不能只删除控件而没有指针替代入口。
- 所有新图标都保留明确文字 Tooltip、语义标签、toggle 状态；长路径和详情要可读全文。
- 状态不依赖颜色：Ready、仅编辑、提交中、未知应有文字；unknown 的语义提示应可被辅助技术读取。
- 覆盖短窗、分屏、2x 文本；浮层不能只用全窗口高度估算而挡住全部编辑器或超出可见区域。

这些可在选定的视觉结构内完成，不需要增加新的 shell 能力。

## 快捷键合同

| 输入上下文 | 按键 | 必须保持的结果 |
|---|---|---|
| 原生 IME 正在组合 | 任意 Composer 快捷键 | 不截获；Enter 不提交，Tab 不补全 |
| 普通草稿，无候选选择 | Enter | 仅 ready 时提交一次真实草稿 |
| 历史/补全有选中项 | Enter / Tab | 只采用，关闭浮层；不执行 |
| 任意编辑态，无 IME | Shift/Ctrl/Option+Enter | 在选区位置换行 |
| 无菜单，光标位于首条视觉行 | ↑ | 打开历史，定位最新匹配 |
| 多行或软换行非首行 | ↑ | 原生移动光标 |
| 历史/补全面板 | ↑ / ↓ | 移动选择，必要时定位；正常通知不定位 |
| 有灰字且光标在末尾 | → / Ctrl+F / Ctrl+E | 接受整个灰字后缀，不执行 |
| 有灰字且光标在末尾 | Ctrl+→ | 接受下一段，不执行 |
| 非空选区 | Tab | 提示先定位；不替换整个选区 |
| 无前置浮层的选区 | → | 原生折叠选区，再按 Tab 可补全 |
| 历史 → 补全 → 灰字 → 选区 → 编辑器 | Esc | 只处理最先存在的这一层；最后才返回终端 |
| 无 IME | Cmd+Z / Cmd+Shift+Z | 撤销/重做，恢复关联 selection；非 macOS 使用 Ctrl |
| macOS 本地草稿 | Ctrl+C | 清空草稿，可撤销；不发送 PTY 中断 |
| 编辑器 | Shift+Tab | 回到上一可聚焦控件 |
| 应用保留组合键 | Ctrl+Tab 等 | 需要实际应用核对，不能仅因包含 Tab 就误触发补全 |

## 图标与文案的职责

图标可全部重画，但同一个符号在同屏内应保持同一个动作含义。
元信息采用中性视觉，真正动作有 hover/focus/pressed/disabled，toggle 还必须有开/关语义。

| 语义 | 可采用的视觉方向 | 必须同时存在的文本/行为 |
|---|---|---|
| 执行目标 | 终端窗口 / 主机 | 目标名称；不画未实现的下拉 |
| cwd | 文件夹 / 路径 | 完整路径可见或 Tooltip；与自动建议区别 |
| 就绪 / 仅编辑 | 小圆点/勾 / 文档 | “就绪” / “仅编辑”文字 |
| 发送中 | 小进度环 | “正在提交”，独立于补全加载 |
| 未知结果 | 提示标记 | 持续明确文案与查看终端动作 |
| 返回终端 | 终端光标/窗口 | “终端输入”；不能复用提交的 return 符号 |
| 历史 | 时钟回溯 | “历史”；打开时可取消 |
| 自动建议 | 候选列表/建议标记 | “自动建议 开/关”，说明 Tab 不受影响 |
| 复制 / 已复制 | 叠页 / 勾 | 名称和短暂反馈，不更改草稿 |
| 撤销 / 重做 | 成对回转箭头 | 对应 enabled 状态与快捷键 |
| 执行 | 单一执行方向/终端动作 | “执行”；不以无文字 AI 发送箭头代替含义 |
| 采用 | 插入/确认 | “采用”；绝不直接执行 |
| 关闭 | × | “关闭历史并恢复草稿”或“关闭补全”，依上下文准确命名 |
| 更多 | 省略号 | 可通过键盘/指针访问低频编辑动作 |
| 候选类型 | 文件、目录、命令、参数、别名、脚本的同族符号 | 类型词保留，不依赖图标猜测 |

## 不可回退的实现边界

1. Composer 不拥有直接 terminal input sink；所有本地编辑、筛选、选择、复制均不写 PTY。
2. 执行只使用当前 session 的 authenticated ready lease；旧 lease、未知结果、续行/密码/raw 不得执行。
3. unknown 不自动重试，轮询 ready 不自动解锁；接受响应只代表 shell 接收，不代表命令成功。
4. 晚 accepted 只清除提交时相同 editorRevision；用户期间写的新命令必须保留。
5. 候选接受要验证 session/context/editor/selection/policy/catalog 身份及 grapheme 边界；旧结果不得贴入新文档。
6. IME composition 和非空选区不能查/接受补全；灰字不能进入剪贴板、selection、历史或提交文本。
7. 关闭自动建议仍允许每次 Tab 的临时本地读取，不能改为总权限开关。
8. `cd ../../../`、`/absolute/`、`~/`、空格、中文、symlink 与 tilde quoting 的既有行为必须保留。
9. 本地只读显式目录，scripts 只读当前 cwd regular no-follow package.json 名称；不加隐式父目录扫描或 shell 执行。
10. 历史来自可信 shell 内存快照，按 session 隔离；不新增历史文件、终端输出抓取或持久草稿。
11. 滚动只在 opening、键盘 navigation、历史过滤时 reveal；hover/background update 不能触发 jumpTo。
12. Replay 只读、iOS 不显示此桌面 Composer，缺少适配器的 shell 不伪装成 enhanced-ready。

## 选定设计后的验收清单

这份清单是重设计完成证据的目标，不是本次已通过的测试声明。

| 编号 | 验收 | 证据要求 |
|---|---|---|
| A01 | 每项现有功能都有准确入口、文案、enabled/disabled 和空/错误状态 | 与“现有功能完整矩阵”逐项对照选定结构和实现 |
| A02 | 主动作与 Enter 同行为：正常执行、候选采用、历史采用、空结果禁用、发送中禁用 | controller/widget tests；真实应用至少一轮完整采用→执行 |
| A03 | pending 只保留未知结果；成功/拒绝不会重现旧命令恢复入口 | 新增上述 P0 状态测试，包含晚 ack 与新草稿 |
| A04 | unknown 提示在所有补全反馈、loading、编辑、polling 下持久存在且不重复 submit | 新增 controller + widget 状态交叉测试 |
| A05 | 自动建议开关与 Tab 解耦、scope 仅当前 session、取消撤销 IO 授权 | 现有 Tab/策略回归继续通过，测试新开关语义 |
| A06 | cwd、父级、绝对、HOME、空格/中文、symlink 路径连续 Tab 并实际进入 | 现有 Rust/provider/真实 zsh/app 测试；不只看候选截图 |
| A07 | 历史搜索、采用、点击关闭、按钮再次关闭、Esc/Down 恢复精确 selection | 新旧 controller/widget tests；真实 shell 历史验证 |
| A08 | 触摸板连续 pan/zoom 与 wheel、惯性期间 pointer hover/后台更新不卡顿 | 保留 suggestion tests 的滚动位移断言；macOS app 测试；物理手测单独记录 |
| A09 | 切换 session、隐藏 pane、上下文变化、快速打字与 cursor move 不接收过期结果 | 既有 identity/cancellation/session tests |
| A10 | 灰字视觉对齐且不入原稿，复制反馈不污染 unknown 状态，复制内容正确 | 复制/ghost tests + 图像检查 |
| A11 | 多行、软换行、Unicode、选区、撤销/重做、Ctrl+C 与恢复行为完整 | 现有编辑回归；窄窗功能菜单的新测试 |
| A12 | IME composition 不抢 Enter/Tab/方向键；真实拼音确认不执行命令 | 自动化 composition tests；真实输入法另行实测，不能用模拟替代 |
| A13 | 首次打开、执行后、密码/交互程序、return to raw、切换 pane 的焦点准确 | 真实 macOS 应用测试 + 焦点断言 |
| A14 | light/dark、360px/2x、大窗口、短窗、长路径、长 alias、空/加载/错误全部可读 | 扩展 previews/captures，实际看图；不得仅凭无 overflow 断言判断视觉完成 |
| A15 | tooltip、语义标签、toggle/selected/disabled、focus ring、键盘 traversal 完整 | Widget semantics tests；VoiceOver 完整操作另行记录 |
| A16 | 镜像包一致、静态分析通过、相关组件/原生/应用门禁通过 | `tools/sync_terminal_core.dart --check`、分析输出、目标测试日志 |
| A17 | 最终运行产物与审核源码一致，签名可校验 | macOS Release 构建与仓库签名流程；不把其他 OS 标为已验证 |

## 当前覆盖与未验证范围

现有测试源码已经覆盖查询身份/取消、Unicode 边界、IME simulation、按需 Tab、历史/灰字、
每 session 隔离、晚 accepted 不清新草稿、拒绝/未知不重试、深浅/窄窗、触摸板模拟。
`docs/composer/WARP_VIDEO_ALIGNMENT_20260929.md` 记录上一轮执行结果，但本审查没有重跑，不能把历史通过状态用于证明新设计完成。

原有 golden captures 只有候选、历史、灰字三类场景。本轮另已完成
[设计前基线](redesign-evidence/before/README.md)：16 状态 × 浅色、深色、窄窗 2×，共 48 张
真实 Flutter 渲染，涵盖空输入、多行、草稿、运行、发送、暂停、拒绝、unknown、补全不可用、
无匹配、非空选区提示和加载等状态。它们证明当前界面的表现，不证明重设计已经实现；
选定方案后仍需补齐菜单/溢出入口、复制确认、短窗、高对比与长内容场景，并生成 after 对照。
当前源码审查不能证明真实输入法、完整 VoiceOver、物理触摸板、多 OS 渲染和键盘插件组合；最终报告必须将这些与模拟/本机验证分开。
