# 当前功能入口的 iTerm2 对照分析与改进规划

本轮只分析 Ianvs 当前已经开放的入口：终端、标签与窗格、搜索、Profile、设置、SSH/SFTP、Shell 能力、录制回放和 Block + AI。参考 iTerm2 的行为与修复历史，改进这些入口的确定性；不新增 tmux、热键窗口、插件市场或高级粘贴产品范围。Tabby 本轮不参与比较。

本文保留分析时的观察，并记录后续实现。不能把 iTerm2 的历史缺陷直接认定为 Ianvs 缺陷。下方入口表和历史分析描述原始基线；已调整行为以“实施记录”为准。

## 实施记录

在主线 `28e7efed` 上落实以下调整：

- “复制当前目录”改为“在当前目录新建终端”，保留 action ID 兼容已有快捷键。新会话使用源窗格 Profile 快照和启动 cwd，不再额外发送 `cd`；创建失败也不会写入旧 session。
- 分屏使用被操作窗格的 Profile 快照，并继承其可用本地目录；缺少目录时保留 Profile 原目录。SSH Profile 和报告为远端的目录不进入本地 cwd 继承。
- 通用图标按钮和主要 AI 工具栏按钮增加明确的语义名称，保留原 tooltip 与焦点行为。
- 移除同目录操作退役后不再使用的文本发送与 shell 路径转义辅助方法。

新增回归覆盖含中文/空格/引号的目录、不发送隐式命令、创建失败不写旧会话、分屏保留源 Profile、远端 cwd 不继承，以及按钮名称与点击。真实 macOS AX 的最终表现仍需运行构建核验；widget 语义断言不能替代 VoiceOver 测试。

IME、搜索、粘贴、窗格缩放、配置恢复和 replay 历史案例用于审查与运行现有回归，未发现对应缺陷前不改动这些底层机制。特别是 replay 已具备 native 副作用隔离，应继续复用；Profile 自动化已是现有功能，不增加新的自动化类型。

## 证据与限制

分析日期：2026-10-26。Ianvs 源码 `099274789bac9f49d96bea32c09d8ffa60d5219c`；iTerm2 源码 `ad80b196b4447bd6a99b572de7009dc1ad59db8d`。

Computer Use 核验对象是用户已打开的 `/Applications/Trail.app`（`work.ianvs.trail`）。尚未证明该安装包与上述 Ianvs commit 完全一致，因此下文分别标注界面观察和源码结论。未连接用户保存的 SSH 主机，未保存 Profile/设置，未发送 AI 请求。临时创建的第五个标签及两个测试窗格已关闭，恢复到原第二个标签。

iTerm2 本地 Development 构建成功，并使用 `-suite iTerm2` 启动；构建记录在相邻仓库 `build/reference-audit/build.log`。Computer Use 对安装版和本地构建的 `com.googlecode.iterm2` 均拒绝访问。**本报告尚未完成双应用实机对比**；iTerm2 优点和修复机制来自源码、commit diff 与 issue 正文，不能声称本轮亲测其交互。不会通过变更 bundle ID 绕过工具限制。

本地截图、AX 和 issue JSON 位于 `build/iterm2-entry-audit/`，不纳入版本控制。截图编号见下表。测试文件只作为后续验证入口，本轮未运行终端产品回归。GitLab issue 状态为抓取时状态；无法读取的 issue、未获取的讨论均明确标出。

## 当前入口清单

“观察”表示已打开该入口或看到条件状态；“验证”仅适用于具体执行的步骤，不代表整项验收通过。Action registry 的 40 个 ID 包含别名和子动作，不等于 40 个独立功能。

| 当前入口 | Computer Use 证据 | 源码定位与本轮边界 |
|---|---|---|
| 命令面板、启动器、新建标签 | 01、06、07：打开面板和新建选择器，创建本地 shell | `shell_screen_command_menu.dart`、`shell_action_registry.dart`；两种入口的默认动作应统一解释 |
| 标签切换、关闭、重新打开 | 05：标签菜单；实际切换并关闭临时第五标签 | `shell_screen_state_command_actions.dart`；未验证关闭撤销及应用重启恢复 |
| 向右/向下分屏、焦点、缩放、调整、交换、关闭窗格 | 08—11：向右分屏、右窗格输入、缩放/还原；缩放时分屏禁用且解释原因 | `SessionController.splitSession`；调整、交换、重开仅入口/源码确认，不宣称实测 |
| “复制当前目录”、在文件夹中新建标签 | 05 标签菜单；20 快捷键设置列出文件夹新建 | 前者源码实际新建 session 再发送 `cd`，并非复制路径；后者已有启动 cwd 路径 |
| 原始终端输入、选择/复制/粘贴、只读、清空 | 09、13：右侧打印标记，左侧未出现；菜单存在相关动作 | `shell_screen_state_clipboard.dart`、`terminal_input_controller.dart`；未覆盖真实 IME、多行粘贴和 TUI |
| 搜索、范围、前后匹配、清除 | 02—04b：活动窗格/当前标签/所有标签范围；查询 `Filesystem`，2/2 → 上一个 → 1/2 | `shell_screen_state_search_completion.dart`；未验证持续输出、淘汰、跨标签及正则错误 |
| Shell 能力、提示符跳转、命令输出复制 | 12：能力弹窗显示 12/13，用户变量仍等待实际事件；状态栏可查看上下文 | 能力弹窗已观察；跳转/输出复制仅源码与动作入口确认，精准输出区域需单独验收 |
| 即时回看、录制、打开录制 | 13：最近画面与保存库区分；空库有录制/打开入口 | `terminal_replay_backend.dart`；未写录制、未导入外部文件或实测 seek |
| Profile 管理及编辑 | 14—17：列表、新建编辑器，常规/启动/终端/外观/按键/自动化/高级；显示“更改仅应用于新会话” | `profile_models.dart`；触发器和自动切换有实际 UI，不能归为仅模型字段；未保存 |
| 默认设置、外观、快捷键、安全与权限、数据同步、AI 配置 | 19—20：设置导航及快捷键清单；“暂无更改” | 本轮只读查看常规及快捷键，不推定连接、同步或权限操作成功 |
| 新建 SSH、SFTP | 01、06：SSH 启动入口；SFTP 依赖活动 SSH 的禁用说明 | 本轮无远端连接/传输证据；保留现有连接实现，不以 iTerm2 的 SSH 包装方式替代 |
| 普通终端 / Block + AI 切换、共用输入 | 05、18：条件不满足时解释原因；新会话可切换，已有命令卡含输出及退出码 0 | 已验证入口和一条历史命令卡，未验证 AI 调用或远端执行；终端基本输入不得依赖模型可用 |
| 滚动导出、诊断导出、退出确认 | Action registry/快捷键可配置动作与处理器 | 源码可达性证据，未进行导出或退出；不冒充实机通过 |

主要代码位于 `example/lib/features/shell/`；具体链接见文末。仍需逐个补齐未执行动作的条件状态和结果证据，不能以本表替代完整验收。

## 已观察到的优点与可改进处

1. **保留有原因的禁用状态。** SFTP、分屏和 Block 切换已经能解释依赖条件，优于让用户点击后才报错。继续把“没有 SSH”“正在输入”“先退出缩放”等原因绑定到具体目标 session。
2. **保留 Profile 生效范围提示。** 编辑器明确仅对新会话生效。快捷键设置则说明保存后立即生效，这种区别应扩展到自动切换和外观覆盖，避免一律使用含糊的“保存”。
3. **优先修正目录动作语义。** “复制当前目录”容易被理解为复制路径，但 `duplicateCurrentCwd` 创建默认 Profile 会话并发送 `cd`。建议改成“在当前目录新建终端”，复用已有启动 cwd 通道；剪贴板复制路径如需保留应是不同动作。命令发送时机风险来自实现结构，尚未实测证明发生竞态。
4. **明确分屏的配置和目录来源。** 实测左窗格在 `~/projects`，新右窗格在 home；源码确实传入默认 Profile，不继承活动窗格 cwd。这是行为选择而非已证实缺陷。建议默认继承可验证的本地工作目录，Profile 来源明确展示；远端目录不能直接套给本地 PTY。
5. **让无障碍目标与视觉目标一致。** Block 工具栏和部分编辑器按钮的 AX 仅显示无名称按钮，回放面板在所取 AX 树中也缺少对应内容。需要补核语义节点和焦点顺序；这只是观察到的可访问性风险，不是完整 VoiceOver 审核结论。
6. **保留能力证据和记录边界。** Shell 能力区分初始化与真实事件，回看区分临时帧与已保存记录。这些现有优点应成为后续设计约束。

## iTerm2 历史问题：为什么会有这些特殊逻辑

以下每项均从已开放入口出发。commit 说明与 diff 解释机制，issue 正文提供用户症状；二者不相同时，不把引用编号当作完整因果证明。

### A. 粘贴：等待提示符为何需要放行键盘

[issue 5749](https://gitlab.com/gnachman/iterm2/-/issues/5749) 报告在 `psql` 中使用逐行等待 shell prompt 的高级粘贴，第一行后挂起。[修复 5164130](https://github.com/gnachman/iTerm2/commit/5164130b25d57ba1cea9b314135a60275aede05d) 处理更一般的交互死锁：密码/纠错提示不发 OSC 133，而粘贴等待期间又把用户按键排队，用户无法回答提示。修复提供键盘透传与独立取消；不等待提示符时，多行粘贴保持一个 bracketed envelope。

值得吸收的是“等待自动化事件时仍可恢复人工控制”，不是引入高级粘贴菜单。Ianvs 当前剪贴板路径已捕获 sessionId 与 inputEpoch，并在读取及确认后重新检查，应该保留。下一步验证普通粘贴不依赖 Shell Hook、不添加隐式执行，等待确认时切换/关闭目标不会发给其他窗格。不要因为参考实现复杂就删除现有目标检查。

### B. 输入法：提交组合文本不等于消费全部按键

[issue 13030](https://gitlab.com/gnachman/iterm2/-/issues/13030) 描述韩文 IME 提交 marked text 后，交回的 Backspace 被丢弃。[首次修复 52fdf26](https://github.com/gnachman/iTerm2/commit/52fdf260e0822ffb655fe3cd44d041dc876aadae) 后，[后续修复 7f4ff73](https://github.com/gnachman/iTerm2/commit/7f4ff739721f95d0b93003d8701c4523a7edf261) 补充 Tab/方向键，并保留明确 selector 列表和每次按键最多发送一次的标记。原因是一个按键可能调用多个 selector，简单“全部放行”会重复写入终端。

Ianvs 的 `TerminalViewport.updateEditingValue` 与键盘路径并不是 AppKit selector 模型，不能直接移植条件分支。应吸收事件序列约束：候选确认只确认；确实交回的按键恰好一次；搜索框/Composer 拥有焦点时不向 PTY 泄漏。回归覆盖中日韩 IME 的 Return、Backspace、Tab、方向键，分别记录组合态、提交文本和实际 PTY 字节。

### C. 搜索：为什么不能只用行号删旧结果

[issue 12716](https://gitlab.com/gnachman/iterm2/-/issues/12716) 报告连续 Cmd+G 时匹配数减少且漏跳。[修复 17f3789](https://github.com/gnachman/iTerm2/commit/17f3789404361a8183d6b693d6fe2ec2f6c11015) 指出增量搜索范围从一行中间开始，但清理旧结果时丢弃了 x 坐标，导致该行范围前的匹配被删且不重建。修复按绝对二维坐标判断包含关系，并补测试。

Ianvs 当前搜索有三个范围，实测前后跳转正常；没有证据说明存在同一缺陷。吸收方式是把结果身份定义为 session + 稳定位置，不只保存可见行号或全局序号。验收同一行多个匹配、尾部继续输出、scrollback 淘汰、resize 和跨窗格切换；数量变化必须能由内容变化解释。

### D. 窗格缩放：隐藏视图仍属于原拓扑

[修复 31ea322](https://github.com/gnachman/iTerm2/commit/31ea32275204ea9199515577e3a39ed72db8738d) 解释：缩放时根节点只持有活动视图，其余放在映射里；删除、替换或回放交换没有同步映射，就会在还原时崩溃。修复在结构变更前还原，更新 synthetic view 映射，并在不一致时从保存布局恢复。

commit 引用的 [issue 12992](https://gitlab.com/gnachman/iterm2/-/issues/12992) 正文是 tmux 长会话内存问题；讨论未获授权读取。本报告只能确认 commit 中的缩放 teardown 修复，不能宣称它解决了正文的 100GB 内存问题。

Ianvs 已禁用缩放状态下的新分屏，保留此规则。还需覆盖缩放时进程退出、关闭活动窗格、切入/退出回放和重开窗格；恢复后拓扑、活动 session 与输入目标一致。吸收拓扑不变量，不扩大到 tmux 功能。

### E. 工作目录：检查路径必须等于启动路径

[issue 12997](https://gitlab.com/gnachman/iterm2/-/issues/12997) 报告 `~/www` 被误判不存在并回退 home。[修复 3a5c1cd](https://github.com/gnachman/iTerm2/commit/3a5c1cda08a2772019c7aa58ddc79783ca460b93) 在存在性检查前标准化路径，使检查与 PTY 实际 `chdir` 使用同一解释。另一个 [修复 1a319c9](https://github.com/gnachman/iTerm2/commit/1a319c9fe5925e317ce7d03d6b176597ea19bd99) 防止空字符串 cwd 覆盖登录启动器；该提交只有 QA 编号，未找到对应公开 issue。

Ianvs 可复用 `openTerminalAtFolder` 已有启动 cwd 路径，统一同目录新建、分屏和布局重开。区分未指定、有效目录与无效目录；支持的本地路径语法只解析一次。远端 cwd 由远端上下文判断，不交给本地文件系统校验。验收含空格、中文、`~`、已删除目录、空值及 SSH 上下文。

### F. 外观恢复：“不存在”不能变成默认值

[issue 13058](https://gitlab.com/gnachman/iterm2/-/issues/13058) 报告退出 SSH 后重置标签颜色出现红色。[修复 54cba43](https://github.com/gnachman/iTerm2/commit/54cba431cd8d10b53f5c4a281f7d87f1889750f4) 保存不存在键的显式哨兵，恢复时删除键。之前跳过缺失键会在下一次写入捕获中间颜色，替换成默认值又会制造更高优先级的覆盖。抓取时 issue 仍为 opened，不能写成已关闭。

对 Ianvs 已开放的 Profile 外观与自动切换，吸收配置三态：继承/未设置、显式值、临时覆盖。退出远端或取消覆盖后恢复原来源，不能把临时显示值写回 Profile。先沿现有配置合并与持久化检查，再决定是否修改；此处不认定 Ianvs 支持相同 OSC 或存在相同 bug。

### G. 本地/远端：主机名推断不应覆盖已验证上下文

[issue 13117](https://gitlab.com/gnachman/iterm2/-/issues/13117) 报告第三方 hook 发出陈旧主机名，将本地标签误判远端，粘贴文件只剩上传选项。[修复 6735207](https://github.com/gnachman/iTerm2/commit/6735207797957436f011afb86571749db55a3b7e) 区分验证过与推断的 locality；在同一提示符阶段避免低可信 OSC 7 覆盖已验证报告，并在仅推断远端时保留本地路径选项。

Ianvs 的同目录动作目前根据 shell hostname 判远端；SFTP 则应始终依赖真实 SSH session/文件提供者。建议把连接身份、嵌套 shell 上下文和目录来源分别保存。对既有同目录、SFTP、文件粘贴入口，检查本地主机别名、嵌套 ssh 返回、过期 hook 报告，不因一个显示字符串改变文件操作目标。

### H. 回放：只读输入不等于没有副作用

[修复 5964ff2](https://github.com/gnachman/iTerm2/commit/5964ff23177814d752e95a6e57931863842131d4) 说明 `.itr` 内嵌 Profile 原样创建 replay session，可能带入运行命令的 trigger；改为只允许经验证的绘制设置、分配新 GUID，并要求新增 Profile 字段显式分类。引用 issue 13128 无法访问（本轮 API 返回 404），因此这里只使用 commit/diff 证据，不推断 issue 正文或讨论。

Ianvs 已有多层隔离，不能按“只有 UI 只读”评估：专用 replay backend 忽略历史 userInput/shellSemantic；回放窗口创建独立 runtime，输入控制器固定 readOnly；native 的 `spawn_replay` 不创建子进程，`replay_output` 调用 `ingest_pty_output(bytes, false)`，禁止发布宿主 callback 和写回协议响应。现有 `replay_fixture_frame` 以不存在的程序创建 replay，断言 OSC 52、OpenURL 不产生事件，手工写入返回 ReadOnlyReplaySession。上述是源码和测试断言证据，本轮未运行该 native 测试。

应保留这些既有保护，复用原测试覆盖新增协议，而不是重新设计一套回放隔离。剩余审查集中在导入数据到 sessionConfig 的字段来源，以及自动化/配置新增字段能否越过上述边界；现有断言不能自动证明所有未来字段均安全。此项是预防性验证任务，不是已确认漏洞。详见 [native replay 与事件门禁](../native/core/src/session.rs)、[回放窗口](../example/lib/features/shell/shell_screen_recording_library.dart)、[native 回放测试](../native/core/tests/session_test.rs)。

## 只改现有入口的执行顺序

| 批次 | 具体任务 | 验收结果 | 当前证据状态 |
|---|---|---|---|
| 1：消除目录与目标歧义 | 改同目录动作名称；统一启动 cwd；明确分屏 Profile/cwd 来源；检查本地/远端判断来源 | 新会话直接从目标目录启动；无隐式命令文本；失败可解释；不把远端路径用于本地 | 语义差异与实现已确认；改动待实施 |
| 2：守住输入 | 保留 session/epoch 检查；核验 IME 提交、粘贴取消、只读、焦点恢复；为无名称按钮补语义 | 一次意图对应一次正确目标写入；关闭弹层恢复正确控件；中日韩实际输入结果有证据 | 普通单 pane 输入已观察，边界待实测 |
| 3：稳定阅读与布局 | 搜索结果定位与淘汰测试；缩放中退出/关闭/回放交换测试；命令输出边界核验 | 匹配不凭空丢失；活动目标稳定；布局还原无孤立 session；输出复制不声称超出真实边界 | 搜索单场景、缩放/还原已观察 |
| 4：配置与回放 | 核验继承/覆盖/还原；回放副作用白名单；区分临时回看与保存录制 | 配置未设值保持未设；导入录制不启动自动化或连接；空/错误状态可恢复 | Profile/Replay 入口已观察，行为待验 |
| 5：已有远程和增强入口 | SSH 失败/取消/重连、SFTP 失败/取消；Block 能力丢失/恢复与模式切换 | 连接状态真实；不自动重发历史命令；无 hook/无模型时基本终端仍可用 | 条件入口已观察，远程与 AI 未实测 |

以上顺序是分析后的建议，不替代当前唯一工程主线。每项实施前先复现或建立缺失验证，再复用现有测试；不把全部历史案例机械转成重复测试。只有出现实际输入串线、回放副作用或会话丢失时才按阻断缺陷处理，不能给所有预防性检查统一贴 P0。

## 后续双应用实测清单

正式允许 iTerm2 Computer Use 后，使用相同本地 shell、字体/窗口与测试文本，逐项补齐：

1. 新建/分屏的 Profile 和 cwd 来源；当前目录操作是否清楚区分复制与新建。
2. 搜索输入焦点、前后匹配、回绕、持续输出及 resize。
3. 中文/日文/韩文组合输入与普通多行粘贴；确认取消和 pane 切换。
4. 缩放后关闭/进程退出/回放切换；还原布局和输入目标。
5. Profile 更改的生效时间、继承恢复、录制打开与只读边界。

对没有对应 iTerm2 入口的 Ianvs Block/AI 与同步，只对照相关的输入归属和配置原则，不虚构一一对应。SSH/SFTP 实测需要明确的测试连接，不使用用户保存主机作为默认实验环境。

完成标准仍包含真实 iTerm2 交互证据、Ianvs 未执行入口的核验，以及安装包与源码来源核对。当前证据不能支持“所有功能已对比”或“改进已交付”。

## 代码与测试入口

- [动作注册表](../example/lib/features/shell/shell_action_registry.dart)、[命令菜单](../example/lib/features/shell/shell_screen_command_menu.dart)、[动作处理与目录操作](../example/lib/features/shell/shell_screen_state_command_actions.dart)。
- [会话/分屏/启动目录](../example/lib/features/sessions/session_controller.dart)、[布局序列化](../example/lib/features/layout/local_session_layout_codec.dart)、[Profile 模型](../example/lib/features/profiles/profile_models.dart)。
- [剪贴板目标检查](../example/lib/features/shell/shell_screen_state_clipboard.dart)、[输入控制](../packages/ianvs_terminal/lib/src/terminal/terminal_input_controller.dart)、[Viewport/IME](../packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart)。
- [搜索状态](../example/lib/features/shell/shell_screen_state_search_completion.dart)、[搜索视图](../example/lib/features/shell/shell_screen_search.dart)、[Shell 能力合同](protocols/shell_integration_capabilities.md)。
- [回放 backend](../packages/ianvs_terminal/lib/src/recording/terminal_replay_backend.dart)。
- 既有验证入口：[键盘测试](../packages/ianvs_terminal/test/terminal_viewport_keyboard_test.dart)、[粘贴决策测试](../example/test/policies/local_terminal_paste_decision_test.dart)、[关闭保护测试](../example/test/shell/shell_close_protection_test.dart)、[测试说明](TESTING.md)。

完整 GUI 证据保留在本地构建目录；Profile 列表截图含用户连接信息，不应随公开报告发布。
