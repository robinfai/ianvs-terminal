# Command Blocks 验收记录

日期：2026-09-29。主机：macOS 27.0（26A428），Apple silicon。未在 macOS 14／15／26、Intel 或 iOS 设备验证；支持声明仍以 `APPLE_PLATFORM_COMPATIBILITY.md` 为准。

## 今天的视觉取舍

复核项目内今天的「调整 Composer 边框与焦点色」「对齐 Warp universal input」两次对话，以及 `docs/composer/COMPOSER_REDESIGN_VISUAL_SYSTEM.md`。

- 浅色背景干净，避免脏灰；文字用现有冷蓝灰层级。
- 焦点依靠光标；不增加输入下划线、左侧色条或额外光晕。
- 沿用已确认的 Composer 结构、细边框和占位符高度；运行时禁用且保持高度。
- 滚动不因悬停或状态刷新被拉回选中项；明确导航时才 reveal。

## imagegen 与真实渲染对照

使用用户指定的 imagegen，以上午已确认的 `output/imagegen/composer-caret-only-v4-20260929.png` 为参考生成命令块方向图。提示词和生成原图均保留：

- [生成提示词](../../output/imagegen/command-blocks-reference-20260929.prompt.md)
- [生成参考图](../../output/imagegen/command-blocks-reference-20260929.png)

生成图用于设计判断，不能充当实现截图。采用其清楚的命令／输出／状态层级、小型退出状态和安静留白；没有采用生成图中每块完整卡片描边及暗色输入的重复边框，因为它们偏离已确认的审美。

以下截图由生产 Flutter 组件绘制，使用固定场景和仓库内字体。输出组件实际为 `TerminalViewport`；其中示例命令文字是测试 fixture，不是本项目测试结果的证明。

| 场景 | 截图 | 检查 |
| --- | --- | --- |
| 浅色 | [light](../../output/command-blocks/20260929/light.png) | 白色主题表面、单线分隔、等宽文本、失败小型红色状态 |
| 深色 | [dark](../../output/command-blocks/20260929/dark.png) | 沿用主题颜色；没有额外输入内框 |
| 运行中 | [running](../../output/command-blocks/20260929/running.png) | Terminal 光标、可识别运行状态、Composer 同高度禁用 |
| 360px／2 倍字号 | [narrow](../../output/command-blocks/20260929/narrow-2x.png) | 路径截断、状态换行、输出保持终端网格并可横向滚动，无 RenderFlex 溢出 |
| 高对比 | [contrast](../../output/command-blocks/20260929/contrast.png) | 继承 Composer 高对比主题 token |
| 640×330 短窗口 | [short](../../output/command-blocks/20260929/short.png) | Composer 可见；长列表和固定标题仍可滚动 |

截图审查修复了测试字体回退成 Ahem 方块的问题；这是截图环境问题，改为加载仓库内等宽字体后重新采集。长列表交互测试发现固定标题会在原命令仍可见时出现，已改为按命令文本真实位置判断。

## 自动化验证

| 验证 | 结果 |
| --- | --- |
| Rust core `cargo test --manifest-path native/core/Cargo.toml --lib` | 407 通过，1 项原有忽略；首次沙箱运行的 9 项 socket 权限失败已在允许本地 socket 的环境复跑通过 |
| 仿真器 shell marker 专项 | 27 通过，覆盖原有 OSC 133／633 生命周期、嵌套、重复标记、淘汰和重放规则 |
| 新增原生 Command Blocks 专项 | 7 通过；最终分页优化后复跑通过 |
| Flutter 命令块 + Composer 专项 | 82 通过；最后滚轮／焦点修复后命令块 6 项复跑通过 |
| 独立发布包 Command Blocks | 6 通过；公开 barrel 类型检查通过 |
| UI 截图矩阵 | 6 场景通过，无布局异常 |
| Dart 静态分析 | 规范包、发布镜像、宿主接入与新增测试零问题 |
| 镜像同步 | 使用 `tools/sync_terminal_core.dart`，并以 `--check` 检查 |

原生新增测试验证：提示符隔离、无尾换行、空输出、多行命令、分段 DCS、alternate screen、ANSI 样式、满列和软换行空格、CR 重绘、OSC 8 链接、分页、保留历史淘汰、搜索命令、宽度重放后执行身份与时间稳定。

Flutter 新增测试验证：运行块获得 focus／Ctrl+C 字节、完成块没有 PTY 写入能力、重用只编辑、折叠恢复、过滤不影响复制、跨页软换行、范围选择与书签、历史淘汰、短窗口查找与 Esc、100 块之间远距离跳转，以及输出更新不会拉回正在查看的旧内容。

## 真会话验证

使用 `example/integration_test/composer_acceptance_test.dart`，在真实 macOS App 内启动临时 home 的 zsh，不修改用户 shell 配置。已有补全、历史、草稿、运行时禁用和 Ctrl+C 验证继续执行，并增加命令块存在、中文输出不带下一条提示符、运行块本身的 focus、交互式 `read` 接收输入、完成后恢复 Composer，以及 Composer 到块的快捷键、Esc 返回编辑器、全屏应用输入与退出恢复、后台输出到达后的完整终端回退。

真应用截图和最终运行结果见同目录的 `native-running.png` / `native-completed.png` 及 `verification.txt`。截图仅在传入 `BLOCKS_NATIVE_EVIDENCE_DIR` 时生成。

## 明确差异

本地 Markdown 导出不是云分享；未归属输出使用完整终端回退，不是独立后台块；块操作状态仅在会话内保留。完整文档覆盖、实现范围和未实现项见 [研究与实现矩阵](WARP_COMMAND_BLOCKS_RESEARCH.md)。

## 2026-09-30 块内滚动修复

回归测试复现了两个问题：块内 Terminal 拦截滚轮和触控板事件，将像素位移转换为整行后调用外层 `jumpTo`，吞掉小幅滚动并打断列表手势；进入已经运行的命令块后，首次刷新又被误判为新命令，重新启用尾部跟随并拉回底部。

块输出现在通过 `TerminalViewport.handleScrollGestures: false` 将滚动交给外层纵向列表和块内横向 Scrollable，沿用 Flutter 的手势与惯性。Terminal 仍负责真实单元格渲染、文本选择、键盘与 IME。完整终端默认继续处理自身滚动。挂载时记录当前运行块，避免首次刷新误触发尾部跟随。

- 规范包命令块 9 项与原有 Terminal 手势 16 项共 25 项通过；新增覆盖 4px 滚轮、横向滚轮／触控板、连续 16 次跨块滑动、运行中／已完成输出刷新和持续惯性。新回归在修复前失败、修复后通过。
- 独立发布包命令块 9 项通过；通过同步工具更新并以 `--check` 确认一致。
- 真实 macOS 27.0（26A428）App／zsh 集成验收通过：生成 120 行输出，在输出区域注入连续触控板手势，检查位移和惯性，并继续验证原有输入、运行块焦点、Ctrl+C 与全屏程序切换。
- 修复涉及的规范源码、发布镜像及测试静态分析无问题。此次没有调整视觉样式。

## 2026-09-30 会话模式、tab 入口与应用偏好

采用用户确认的交互：能力失效自动回退 Normal，tab 提示；恢复 Block 由用户手动操作。

- 桌面 tab 右键菜单提供「普通终端／命令块」，当前项有勾选；不可用的命令块项禁用并解释原因。左下角 Composer 开关、Composer 内切换菜单及命令块工具栏的终端切换入口已移除。
- 当前 shell 上下文、SSH 连接链、Composer 所有权和 lease、全屏／鼠标模式、只读及退出状态共同决定能力。SSH 多跳不能因本地 bridge 仍处于 running 就误判可用。富内容与未归属输出保留整会话回退，防止输出遗漏。
- 回退将焦点交给真实终端；能力恢复只在 tab 用低调图标和悬停说明提示，点击图标也可打开同一菜单。用户主动选 Normal 会清除恢复提示；模式和草稿按会话保留，分屏及拆成 tab 不丢失。
- 设置 → 通用 →「优先终端模式」保存 Normal／Blocks 偏好，默认 Normal，影响新会话。改变偏好不覆盖已有会话的选择。已验证本地配置保存、启动加载和未知配置值回退。
- 状态轮询覆盖 Normal 与后台会话；隐藏组件不在卸载流程中同步访问后端，避免布局切换和关闭时出现生命周期异常。

验证结果：

| 验证 | 结果 |
| --- | --- |
| 宿主模式状态、tab 交互、偏好、设置、侧栏及会话控制器 | 143 项通过；补充偏好持久化／启动断言后对应 2 项复跑通过 |
| 规范包 Composer 与 Command Blocks | 85 项通过 |
| 独立发布镜像 Composer 与 Command Blocks | 37 项通过 |
| 宿主及两个包受影响源码与测试静态分析 | 无问题 |
| `tools/sync_terminal_core.dart --check` 与 `git diff --check` | 通过 |
| 真实 macOS 27.0 App 集成验收 | 通过；临时 home 的 zsh → bash → zsh、全屏进入／退出、tab 手动切换、草稿、运行块焦点、Ctrl+C、120 行输出滚动及惯性 |

该阶段的 SSH 单跳、再跳和回到根上下文仅通过生产 `shell_hook` 状态事件验证。后续真实 OpenSSH 和应用验证见下方「SSH 命令块协商」。其他 macOS 版本的覆盖范围不变。

最终真实 App 截图：[tab 菜单](../../output/command-blocks/20260930/terminal-mode-menu.png)、[子 Shell 自动回退](../../output/command-blocks/20260930/terminal-mode-nested-shell.png)、[运行块](../../output/command-blocks/20260930/native-running.png)、[已完成块](../../output/command-blocks/20260930/native-completed.png)。检查白色主题表面、冷蓝灰文字、小型中性色提示、无新增左侧色条或焦点装饰；设置的深色、浅色、窄窗口与放大字号仍由现有布局矩阵验证。最终原生运行日志见 [verification.txt](../../output/command-blocks/20260930/verification.txt)。

## 2026-09-30 整块默认高度与 top／vim

用户明确确认：1/3 限制包含命令标题和状态，作用于整个 Block。

- 默认每块不超过命令历史可用高度的 1/3（因此也不超过 Normal 终端区域的 1/3），预算包含标题、状态、内边距与分隔间距。输出使用剩余空间，并按 `TerminalViewport` 实测行高向下取整；短输出保持自然高度。
- 块内扩大按钮解除该块的默认上限，再次点击恢复。选择按会话和块 ID 保存，状态刷新不会重置，已淘汰块会清理选择。扩大后可使用原有分页入口查看更早输出；复制仍读取全部保留输出。
- 窗口过矮或字号放大时采用紧凑摘要，保留命令、状态与扩大按钮，不挤占 Composer。运行块仍保留真实 Terminal 的输入通道。
- 限高输出可独立纵向滚动；横向和纵向滚动继续由 Flutter Scrollable 接收像素位移和惯性。用户回看时，输出更新不会拉回尾部；扩大后由命令历史列表滚动完整输出页。

在 macOS 27.0（26A428）真实 App 的临时 zsh 会话执行 `/usr/bin/top -s 1` 和 `/usr/bin/vim -Nu NONE -i NONE -n`，验证两者自动回退为完整 Terminal，Composer 和块列表消失，终端视图尺寸与初始 Normal 模式完全一致。`top` 通过 `q` 退出；`vim` 输入 `VIM_BLOCK_INPUT`、Esc、`:q!` 退出。退出后均保持 Normal，出现恢复提示，再从 tab 右键手动切回 Blocks。没有根据命令名称硬编码切换，沿用真实终端模式检测。

回归覆盖：规范包命令块 14 项；新增整块高度、真实行高、不同字体／窗口／2 倍字号、扩大与恢复，以及运行中／已完成块的细小滚轮位移、连续触控板手势、刷新与惯性。深浅色、运行中、窄窗口、2 倍字号、高对比和短窗口 6 个截图场景通过。完整原生集成验收包含真实 `top`／`vim`，最终通过。

截图：[默认高度](../../output/command-blocks/20260930-height/block-default-height.png)、[手动扩大](../../output/command-blocks/20260930-height/block-expanded-height.png)、[top 全屏](../../output/command-blocks/20260930-height/fullscreen-top.png)、[vim 全屏输入](../../output/command-blocks/20260930-height/fullscreen-vim.png)、[深色](../../output/command-blocks/20260930-height/dark.png)、[窄窗口 2 倍字号](../../output/command-blocks/20260930-height/narrow-2x.png)、[短窗口](../../output/command-blocks/20260930-height/short.png)。[原生测试日志](../../output/command-blocks/20260930-height/verification.txt)。其他 OS 版本的验证范围不变。

## 2026-09-30 SSH 命令块协商

能力判断已从「SSH 一律禁用」改为核对当前 context 与独立编辑器握手。Bash 4+ / Zsh 在原有内存引导中接收适配器，不要求安装代理或修改远端 dotfiles。命令按字节编码，只有当前主提示符的有效凭据才能提交；cd/export 在当前远端 Shell 生效。跳转、返回、输入竞争、超时和断连会撤销旧输入权，已提交命令的回执则独立保留。远端不会调用本地文件补全或展示本地历史。

真实验证使用临时目录和一次性密钥的回环 OpenSSH 服务，宿主 macOS 27.0（26A428）、OpenSSH 10.3p1、系统 Zsh 5.9，以及临时编译的 GNU Bash 5.2.37。未连接用户的 cloud，也不将这些结果扩展为 Linux 或其他 macOS 版本已验收。

- `tools/ssh_boundary_lab/composer.py` 六种场景通过：Bash/Zsh 的 emacs、vi，以及各自的本地 ssh 入口；均执行两层跳转和逐层返回，检查旧凭据拒绝、每层环境变量、中文多行、重复提交、原始输入竞争和续行。
- 真实 macOS App 的 `ssh_composer_acceptance_test.dart` 通过：Tab 菜单开放命令块、真实远端输出、节点切换后的手动恢复，以及 SSH 内 top/vim 占满终端、获得输入焦点、正常退出并保持 Normal。
- 5 项模式/widget 回归和 3 项原有本地 Composer PTY 集成通过；原生全量单元回归 410 通过、1 项既有 Docker 验收忽略。全量首次并发运行遇到既有 proxy PID 文件短暂为空，顺序复跑通过。
- 修改的 Dart 文件静态分析通过。Rust Clippy 保留 `completion_host.rs` 中既有的 `collapsible_if` 建议，本次新增实现无新增建议。

实际截图：[SSH 命令块](../../output/command-blocks/20260930-ssh/ssh-block-completed.png)、[Tab 菜单](../../output/command-blocks/20260930-ssh/ssh-mode-menu.png)、[跳转后提示](../../output/command-blocks/20260930-ssh/ssh-hop-ready.png)、[远端 top](../../output/command-blocks/20260930-ssh/ssh-fullscreen-top.png)、[远端 vim](../../output/command-blocks/20260930-ssh/ssh-fullscreen-vim.png)。检查沿用白色表面、冷蓝灰文字、细分隔线；全屏程序不保留 Composer 或 Block 容器。日志和结果同目录保存。

使用更新后的构建需要新建终端 Tab，再执行 `ssh cloud`；旧 Shell 不会被追加重装包装函数。关闭自动注入、Fish、Bash 3 或 Hook 注册失败时保留 Normal。协议细节见 [Composer V1](../protocols/COMPOSER_V1.md#ssh-and-nested-shell-negotiation)。


## 2026-09-30 移动端默认命令块

iOS / Android（包括平板）的未配置默认值为 Blocks，桌面保持 Normal。初始化和协商期间使用原始终端；当前节点获得输入权后，首次自动进入 Blocks。之后 SSH 跳转、失去输入权、全屏应用或其他能力失效会自动回退 Normal；恢复只显示提示，由用户手动切回。用户主动选 Normal 后，后续协商不会覆盖该选择。

手机右上角「…」会话菜单顶部提供「普通终端 / 命令块」，显示当前选中项和不可用原因；菜单打开期间会随协商结果更新。回退或恢复时入口显示小圆点与辅助功能播报。平板顶部的会话菜单也能直接触摸操作。设置 → 通用 → 优先终端模式可改新会话默认值，当前会话不受影响。未设置的偏好不写成显式 Normal；既有明确设置继续优先。

触控窄屏输入区使用目录、命令编辑和单排操作。短横屏优先保留输入与执行，过高内容可滚动；深色和两倍字号均使用现有主题。软键盘入口根据输入所有权选择 Composer 或原始终端：就绪草稿不发送原始控制字节，运行中命令仍能用 Ctrl-C，Normal / 全屏程序使用原有终端附加键。软键盘压缩高度时的工具栏溢出已修复。

验证在 macOS 宿主上使用 Flutter Widget 测试模拟 iOS / Android 平台、手机 / 平板尺寸及键盘 inset，尚未完成 iOS / Android 真机验收。9 个移动端场景覆盖首次协商、菜单实时更新、手动 Normal、草稿保留、经协商接口执行命令、SSH 跳转、全屏回退、触摸块内滚动与扩大、运行中 Ctrl-C，以及设置仅影响新会话。应用相关回归 173 项通过，公共 Composer / Block 组件 90 项通过。修改文件静态分析、同步镜像与 diff 检查通过。真实 SSH 和 top/vim 的验证范围仍为上一节所列 macOS。

截图使用真实字体和生产组件；测试截图的键盘区域为空白，不包含系统键盘绘制：[默认 Block](../../output/command-blocks/20260930-mobile/ios-block.png)、[触控菜单](../../output/command-blocks/20260930-mobile/iOS-menu.png)、[回退原因](../../output/command-blocks/20260930-mobile/ios-fallback.png)、[手机键盘](../../output/command-blocks/20260930-mobile/ios-phone-keyboard.png)、[短横屏](../../output/command-blocks/20260930-mobile/ios-landscape-keyboard.png)、[深色两倍字号](../../output/command-blocks/20260930-mobile/ios-large-text-dark-keyboard.png)、[iPad](../../output/command-blocks/20260930-mobile/ios-ipad-keyboard.png)、[Android 菜单](../../output/command-blocks/20260930-mobile/android-menu.png)。日志保存在同目录。

## 2026-09-30 cloud 的 Bash 命令块缺失修复

按用户指定的真实 `ssh cloud` 复现：Bash 4.4.20 中连续两次 `ls` 都执行成功，但只有 `precmd` / `precmd.pwd`，没有 `preexec` / `command_finished`，因此两次均无 `ls` Block。远端加载的 bash-preexec 在首次 prompt 接管 DEBUG trap；先前的引导把它的延迟安装包在自己的 PROMPT_COMMAND 中，启动时的注册检查不足以发现随后丢失的命令事件。

修复改用 [bash-preexec 官方回调数组](https://github.com/rcaloras/bash-preexec#usage)，保留其 DEBUG / PROMPT_COMMAND 和用户回调。兼容旧版将 Readline 私有按键误当作交互命令的行为：忽略按键回调，回调结束后恢复其交互标志，实际命令执行时才记录输出边界。未知 DEBUG trap 仍不接管。

- 真实 cloud：本地 Zsh 的 `ssh cloud` 包装入口和原生直接 SSH 入口均验证两次 `ls` 各生成独立、完成、退出码 0 的 Block；每块有完整输出。未修改远端 dotfiles。
- 真实 macOS App 连接 cloud 的烟雾验收通过：中文输出、两次 `ls`、三个实际完成的 Block，以及最终 Composer 恢复就绪；[实际截图](../../output/command-blocks/20260930-bash-preexec/cloud/ssh-block-completed.png)。此场景未在 cloud 执行多跳或 top/vim。
- bash-preexec 0.5.0 / 0.7.0 上游脚本分别运行 6 个回环 SSH 场景；覆盖 Bash/Zsh、emacs/vi、本地 SSH 入口、重复命令、两层跳转、父节点恢复、输入竞争和续行。0.7.0 同时通过真实 macOS UI 的多跳及 top/vim 全屏验收。
- 原生单元回归 410 通过、1 项既有忽略；界面测试新增实际 Block 数量、输出和退出码断言，避免仅凭原始屏幕有输出或存在 Block 容器而判定成功。

汇总、日志和截图位于 `output/command-blocks/20260930-bash-preexec/`。外部脚本仅作为临时验收样本：`tools/ssh_boundary_lab/composer.py --bash <Bash 4+> --bash-preexec <上游脚本路径> --ui --output <结果目录>`。本节的功能验收平台为 macOS 27.0；iPhone 安装和启动不等同于已完成 iOS 真机交互验收。更新后需要重新连接 SSH，以载入修复的内存注入脚本。

修复版 Release 已安装到 `/Applications/Trail.app` 并重启，主界面正常；iPhone 17（iOS 27.0）也已保留数据更新安装。两端签名验证通过。iPhone 启动检查被设备锁屏阻止，未将此次安装记录为 iOS 真机交互验收。

## 2026-09-30 手机预览、全屏阅读与滑动稳定性

手机不再沿用键盘压缩后可用高度的 1/3。命令列表最多预览末尾 6 行输出，短输出保留自然高度；标题、状态和「查看全部」使用触控尺寸。预览没有独立纵向滚动，列表承担整页纵向手势。点开后隐藏键盘，进入全屏输出阅读页，通过单一纵向列表按需读取原生分页。返回保留 Composer 草稿，重新打开恢复阅读位置。手动滑动会暂停尾部跟随，仅点击「回到最新」恢复。桌面继续沿用整块 1/3 高度和手动扩大。

滑动回拉的进一步原因是行高测量发生在绘制阶段：惰性列表会布局尚未绘制的输出页，这些页把默认行高当作实测行高上报；相邻页面再上报真实行高，导致列表高度反复变化。组件测试复现了 18/22 像素交替和无法稳定的跨页滚动。测量现已移至布局阶段，字体或像素比例变化触发布局；已完成的输出视图也不会再连接 IME。

真机还发现 Cloud 的 procps-ng `top 3.3.12` 不进入备用屏幕，而是使用主缓冲区的应用光标、应用键盘及隐藏光标模式。宿主现通过这组实际模式在运行期间回退完整 Terminal，并保持到命令结束；普通隐藏光标的进度输出及主提示符不会单独触发。退出后保持 Normal，由会话菜单手动恢复 Blocks。模式回归在修复前失败，修复后通过；控制序列证据仅保留模式，不保存进程列表。

组件和宿主验证：

- 命令块组件 20 项通过，其中 6 项新增手机场景覆盖六行预览、键盘高度稳定、跨页触摸滚动、只读 IME、阅读位置、运行输出跟随及深色/放大字号/短横屏。
- 原有终端渲染、键盘和触摸回归 70 项通过。
- 同步后的独立发布包命令块 20 项通过；最终规范包 6 项手机回归复跑通过。
- 宿主移动端、桌面模式和模式控制器共 15 项通过，包含新补充的主缓冲区全屏应用回归。
- 规范包、发布包与宿主修改静态分析无问题；同步检查与差异空白检查通过。

证据目录：[手机阅读验收](../../output/command-blocks/20260930-mobile-reader/)。`widget/` 是生产组件、项目字体和模拟尺寸的截图，覆盖深浅色、2 倍字号、横屏、iPad 与键盘 inset；不代表这些设备均做过真机验证。真机 Flutter 截图不包含系统键盘图层，键盘显隐另通过真实 `FlutterView.viewInsets` 验证。

完整真机自动化在 iPhone 17、iOS 27.0（24A437）、402 × 874 逻辑尺寸上通过，使用手机已有 Cloud 配置连接用户指定的真实目标。验收会话、偏好和布局使用内存仓库，不复制 SSH 凭据、不覆盖用户设置，也不修改远端配置文件。签名 Release 中的输入通过实际 EditableText 客户端进入；页面切换与系统键盘分别等待原生状态，滚动位置在 iOS 惯性结束后比较。

| 真机检查 | 结果 |
| --- | --- |
| 连续两次 `ls` | 两个独立、完成且退出码为 0 的 Block |
| 240 行输出，连续 8 次触摸滑动 | 从 0 前进到 4483.63，跨过原生 128 行分页边界，无回拉 |
| 键盘出现后的整块高度 | 实测仍为 237；键盘 inset 为 329，预览保持 6 行 |
| 关闭／重新打开阅读页 | 恢复到惯性结束后的 4573 位置；Composer 草稿保留，键盘保持收起 |
| 持续输出 | 回看时新输出继续增长，阅读位置不变；点击「回到最新」恢复跟随 |
| Normal、Linux top、vim | 界面均为 402 × 664，实际终端网格均为 45 列 × 29 行 |
| 全屏程序输入和退出 | top 用 `q` 退出；vim 实际输入 `TRAIL_VIM_INPUT`，再用 `:q!` 退出，不写文件 |
| 全屏退出后的模式 | 保持 Normal、出现恢复提示，再通过手机会话菜单手动切回 Blocks |

最终结果：[results.json](../../output/command-blocks/20260930-mobile-reader/iphone/results.json)。真机截图：[六行预览](../../output/command-blocks/20260930-mobile-reader/iphone/list-preview.png)、[全屏阅读](../../output/command-blocks/20260930-mobile-reader/iphone/expanded-after-scroll.png)、[持续输出时回看](../../output/command-blocks/20260930-mobile-reader/iphone/live-reading-paused.png)、[top](../../output/command-blocks/20260930-mobile-reader/iphone/fullscreen-top.png)、[vim 编辑](../../output/command-blocks/20260930-mobile-reader/iphone/fullscreen-vim.png)。其他 iOS 版本与 Android 仍未完成真机验证；横屏和大字号覆盖来自上述组件测试。

验收完成后，iPhone 已保留数据更新回正常 `lib/main.dart` 入口的 Release，并成功启动；签名验证通过。本机 `/Applications/Trail.app` 同步更新并重启，三个本地 Shell 会话正常恢复。两端安装记录见 [install.json](../../output/command-blocks/20260930-mobile-reader/install.json)。
