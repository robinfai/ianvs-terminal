# Ianvs Terminal 里程碑

这份文档定义产品推进顺序。每个里程碑完成前，都要确认 flutterm 依赖是否满足本阶段需要；如果不满足，先把问题写入 `FLUTTERM_FEEDBACK.md`。

## M0：项目骨架和依赖边界

目标：让 Ianvs Terminal 从一开始就按“产品壳依赖 flutterm terminal 库”的方式推进。

交付：

- 建立 Flutter 应用项目骨架，产品名使用 `Ianvs Terminal`。
- 首要启用 macOS target。
- 不生成 Windows、Linux、iOS、Android 平台目录；跨平台适配只保留架构边界和文档说明。
- 通过本地 path dependency 接入 `flutterm_terminal` 和 `flutterm_pty`。
- `flutterm_pty` 在产品层只用于 `NativePtyBackend.load()`，不绕过 `flutterm_terminal` 重新实现 terminal 能力。
- 复用 flutterm example 的 macOS Xcode 脚本，构建、复制并签名 `libflutterm_core.dylib`。
- 关闭 macOS App Sandbox，允许 flutterm native core 创建本地 PTY shell。
- 建立产品文档、里程碑文档和 flutterm 反馈文档。
- 明确 `/Users/robinfai/personal/warp` 只作为功能参考。

完成条件：

- macOS 端能打开一个本地 shell session。
- 终端内容来自 flutterm，不是 Ianvs Terminal 自己实现的假终端。
- 真实 shell smoke 使用 `FLUTTERM_CORE_LIB=/Users/robinfai/personal/flutterm/native/core/target/debug/libflutterm_core.dylib flutter test test/real_shell_smoke_test.dart` 验证 `echo ianvs` 输出能进入 flutterm runtime frame。
- `test/macos_entitlements_test.dart` 验证 Debug / Release entitlements 不打开 App Sandbox。
- 平台相关代码已有明确放置位置，不把 macOS 专属逻辑散落到产品核心模型里。
- 已记录第一版 flutterm 依赖边界和已知缺口。
- Windows、Linux、iOS、Android 不作为 M0 验收项。

## M1：日常本地终端

目标：让 macOS 版 Ianvs Terminal 可以替代日常本地终端的基础使用。

### M1A：单会话基础可用

目标：先把一个本地 shell session 做到可持续使用，暂不引入 tab、pane、设置页、blocks 或 SSH。

交付：

- 产品侧 `LocalShellStatus` 和 `LocalShellSessionController` 管理 starting、running、exited、failed 状态。
- shell 退出后保留最后输出，显示退出码和 `Restart` 操作，不自动清屏、不自动新建 shell、不关闭窗口。
- 启动失败时显示错误和 `Retry` 操作。
- Header 显示产品名、`Local shell`、当前状态和 Copy / Paste / Restart 操作。
- 剪贴板通过 `ClipboardClient` 抽象接入，测试使用 fake，产品默认走 Flutter 系统剪贴板。

完成条件：

- Widget tests 覆盖启动成功、退出态、重启、失败重试和粘贴写入。
- 真实 shell smoke 覆盖 `echo ianvs` 输出，以及 `echo ianvs && exit 7` 的输出和退出码。
- `flutter analyze`、`flutter test`、`flutter build macos` 通过。

### M1B：单会话查找和选区复制

目标：补齐单个本地 shell session 内的输出查找、结果跳转、选区复制和退出后查找。

交付：

- 顶部查找栏支持 Search 按钮和 `Cmd+F` 打开，`Escape` 关闭。
- 查找栏显示 query 输入框、结果数量、上一个和下一个操作。
- 查找调用 flutterm `searchText`，跳转调用 `scrollViewportTo`，当前结果通过 `SelectionController` 选中。
- 退出态仍允许查找最后输出和复制选区；粘贴继续禁用。
- 查找栏只做基础输出查找，不进入命令搜索、全局搜索或 command palette。

完成条件：

- Widget tests 覆盖打开查找、结果计数、上下跳转、复制当前匹配、退出后查找复制、空结果不滚动。
- 真实 shell smoke 覆盖多行输出中的 `ianvs` 查找和复制。
- `flutter analyze`、`flutter test`、真实 shell smoke、`flutter build macos` 通过。

### M1C：单窗口多 tab

目标：在一个窗口内运行多个真实本地 shell tab，先完成 M1 的多会话基础组织能力，不进入 pane、session restore 或设置页。

交付：

- 一个 tab 对应一个 `LocalShellSessionController` 和一个真实 flutterm shell session。
- 新建 tab 后立即启动本地 shell，并切到新 tab。
- 切换 tab 不停止后台 shell；每个 tab 保留自己的输出、查找状态、退出状态和重启能力。
- tab 标题优先显示 shell/window title；没有 title 时显示 `Local 1`、`Local 2`。
- 关闭 tab 会释放对应 shell controller；最后一个 tab 不允许关闭。
- Header 操作和快捷键只作用于当前 active tab。
- 支持 `Cmd+T` 新建 tab、`Cmd+W` 关闭当前 tab、`Cmd+Shift+[` 和 `Cmd+Shift+]` 切换 tab。

完成条件：

- Widget tests 覆盖新建 tab、切换后的粘贴目标、关闭 active tab、最后 tab 不关闭、后台 tab 退出态、window title 更新和 tab 快捷键。
- 真实 shell smoke 覆盖两个真实本地 shell tab 的独立输出，以及关闭一个 tab 后另一个 tab 仍可见。
- `flutter analyze`、`flutter test`、真实 shell smoke、`flutter build macos` 通过。

### M1D：最小设置

目标：补齐 M1 所需的字体、字号、主题和默认 shell 设置。设置保存到本机文件，重启应用后保留。

交付：

- 设置文件固定为 `~/Library/Application Support/Ianvs/ianvs-terminal/settings.json`。
- 缺失或解析失败时回到默认值：用户 `$SHELL` 或 `/bin/zsh`、字号 `14`、flutterm 默认字体、`Dark` 主题。
- Header 提供 Settings 按钮，`Cmd+,` 可以打开设置面板。
- 设置面板支持字体名称、字号、`Dark / Graphite / Light` 主题和默认 shell 路径。
- 字体、字号和主题对现有 tab 立即生效。
- 默认 shell 只影响新建 tab 和当前 tab 的 Restart。
- 默认 shell 输入为空时显示错误，不保存。
- viewport 测到 cell size 变化时，同步给 flutterm runtime 并触发 resize，避免改字号后 PTY 行列数停留在旧值。

完成条件：

- Unit tests 覆盖设置文件缺失、保存重读和坏 JSON 回退。
- Widget tests 覆盖设置面板、字号变化、主题变化、默认 shell 影响新 tab 和 Restart、空 shell 不保存、`Cmd+,`。
- 真实 shell smoke 覆盖默认 shell 设置能用于新建本地 shell。
- `flutter analyze`、`flutter test`、真实 shell smoke、`flutter build macos` 通过。

### M1E：macOS 收口与本地使用验收

目标：进入 M2 前完成 M1 收口，补齐 macOS 桌面入口、启动 prompt 稳定性验证和本地使用验收说明。

交付：

- 使用 Flutter `PlatformMenuBar` 提供 macOS 原生菜单入口，覆盖 Settings、New Tab、Close Tab、Restart、Copy、Paste、Find。
- 菜单项复用现有 controller 行为，不新增第二套状态逻辑。
- 菜单可用状态跟随 active tab：退出态允许 Copy / Find / Restart，禁用 Paste；最后一个 tab 禁用 Close Tab。
- 保留 FT-006 dirty ranges 合并绕行和 FT-007 启动期空 cursor 行 full repaint 绕行。
- 增加真实启动 prompt smoke：使用可控 `PS1` 重复创建本地 shell，确认 prompt 文本进入 frame。
- README 增加 macOS 菜单、启动 prompt smoke、手工验收步骤，以及 `flutter run -d macos` foreground 警告说明。

完成条件：

- Widget tests 覆盖菜单项存在、菜单回调作用于 active tab、退出态和最后 tab 的菜单可用状态。
- 真实 shell smoke 覆盖重复启动本地 shell 后 prompt 文本可见。
- `flutter analyze`、`flutter test`、真实 shell smoke、`flutter build macos` 通过。
- `flutter run -d macos` 能构建并启动 app；若出现 `Failed to foreground app; open returned 1` 但 app 已启动且有 VM Service，不阻塞 M1E。

交付：

- 本地 shell 的创建、关闭、输入、输出、resize 和 exit 状态展示。
- 基础复制、粘贴、滚动、选择和查找。
- 单窗口多 tab，关闭 tab 后焦点稳定。
- 最小设置项：字体、字号、主题色、默认 shell。
- macOS 菜单、窗口标题、快捷键和剪贴板符合桌面使用习惯。

参考：

- flutterm：`TerminalRuntimeController`、`TerminalViewport`、`TerminalInputController`。
- Warp：`app/src/terminal/`、`app/src/integration_testing/terminal/`。

完成条件：

- macOS 端可连续完成一小时本地开发命令操作。
- 复制粘贴、滚动、resize 没有明显破坏。
- flutterm 已知手工兼容性风险在 `FLUTTERM_FEEDBACK.md` 中有记录。

## M2：block 化命令历史

目标：把命令和输出整理成可操作的 block，让输出复用和失败定位更直接。

### M2A：block 能力打底

目标：先建立 Ianvs Terminal 自己的 block 模型、控制器和操作入口，不从真实 shell 的原始输出推断命令边界。

交付：

- 产品侧 `TerminalBlockStatus`、`TerminalBlock` 和 `TerminalBlocksController`。
- 每个 `LocalShellSessionController` 持有独立 block controller；多 tab 下 block 状态互不串扰。
- Header 增加 block 操作区：上一个、下一个、复制命令、复制输出、复制命令和输出、重新输入命令。
- 无 block 时操作禁用；有 block 时显示 `Block N/M`、状态和命令预览。
- 跳转 block 复用 `scrollViewportTo(block.scrollbackOffset)`。
- 重新输入命令只写入命令文本，不追加换行；现代输入区留到 M3。
- 真实本地 shell 继续按 M1 能力运行，不自动生成 block。

完成条件：

- Unit tests 覆盖 block 创建、更新、完成、状态、跳转、复制和重新输入。
- Widget tests 覆盖无 block 禁用、注入 block 显示、跳转、active tab 隔离、退出态复制和跳转。
- `FLUTTERM_FEEDBACK.md` 记录当前 flutterm 缺少命令生命周期事件和提交命令 hook。
- `flutter analyze`、`flutter test`、真实 shell smoke、`flutter build macos` 通过。

### M2B：真实命令边界接入

目标：先用 flutterm 的通用 shell hook 事件通道和 Ianvs Terminal 的 zsh integration，把真实 zsh 命令稳定转成 block。

交付：

- flutterm native core 解析通用 DCS hook：`ESC P hook;<hex-json> ESC \`，生成 `shell_hook` event，不把 hook 序列绘制到 terminal 内容里。
- `flutterm_terminal` 公开 `TerminalSessionShellHookEvent`，payload 保留 shell integration 发来的结构化字段。
- Ianvs Terminal 只在默认 shell 为 zsh 时生成 shell integration 文件，并通过 `ZDOTDIR` 注入；bash、fish 和其他 shell 保持 M2A 行为。
- zsh integration 使用 `preexec` / `precmd` 发送 `preexec`、`command_finished` 和 `precmd` hook。
- `LocalShellSessionController` 将 `preexec` 创建为 running block，将 `command_finished` 映射为 succeeded、failed、interrupted 或 unknown。
- block 输出文本通过 flutterm 现有 selection text 能力读取，不从普通输出或 frame diff 猜边界。
- 现有 block toolbar 继续支持复制命令、复制输出、复制全部、重新输入和上一个 / 下一个跳转。

参考：

- Warp：`app/src/terminal/model/block.rs`、`app/src/terminal/model/blocks.rs`、`app/src/integration_testing/block/`。

flutterm 依赖检查：

- M2A 已确认当前 flutterm 不提供稳定的命令边界、输出归属、命令退出状态归属或“用户提交命令”回调。
- M2B 已补通用 shell hook 事件通道；该通道不绑定 Ianvs，其他消费方也可使用。
- Ianvs Terminal 本阶段只实现 zsh shell integration；bash / fish 留到后续。
- 不采用从 PS1、echo 文本、cursor 位置或 frame diff 推断 block 的方案。

完成条件：

- `/bin/zsh` 下执行 `echo ianvs-block` 能形成 succeeded block，输出包含 `ianvs-block`。
- `/bin/zsh` 下执行 `false` 能形成 failed block。
- `Ctrl-C` 或 exit code `130` 能标记为 interrupted。
- 非 zsh 默认 shell 不注入 `ZDOTDIR`，不会自动生成真实 shell block，仍保留 M2A 手动 block 能力。
- flutterm native core、flutterm terminal runtime、Ianvs widget tests 和真实 shell smoke 覆盖 M2B 路径。

### M2C：Block 历史面板与 M2 收口

目标：不改 flutterm 渲染层，先把 M2B 生成的真实 zsh blocks 做成产品侧可见、可选、可操作的历史面板。

交付：

- `TerminalBlocksController` 支持按 id 和 index 选择 block，选择后跳转到对应 scrollback offset。
- 右侧 block 历史面板只显示当前 active tab 的 blocks；没有 block 时不显示面板，Header 仍显示 `Block 0/0`。
- 面板显示序号、状态、命令预览和输出首行预览，active block 高亮。
- 点击面板中的 block 行会同步 Header 的 `Block N/M`，并滚动到该 block 的 offset。
- 面板提供 Copy command、Copy output、Copy all 和 Reinput 操作，复用已有 block controller。
- shell 退出后仍允许选择、跳转和复制已有 block；Reinput 受当前 shell 是否可输入限制。
- 多 tab 切换时，面板和 Header 始终跟随 active tab，不共享 block 状态。
- 暂不做 terminal 内 inline block card、block divider、bash/fish integration、pane、session restore 或 M3 现代输入区。

完成条件：

- Unit tests 覆盖按 id / index 选择 block、无效选择不滚动、复制和重新输入作用于新选中的 active block。
- Widget tests 覆盖无 block 不显示面板、有 block 显示列表和预览、点击列表跳转、多 tab 隔离、退出态复制和 Reinput 禁用。
- 真实 shell smoke 继续覆盖 zsh block 生成、failed block，以及 M1 的 shell、tab、查找、设置和 prompt 稳定性。
- `FLUTTERM_FEEDBACK.md` 记录 M2C 暂不做 flutterm render-layer inline block divider；后续如果要在终端内容里做行内分组，需要 flutterm 暴露 block/range 渲染扩展点。

## M3：现代输入和命令复用

目标：让输入区接近现代编辑器体验，并把历史命令和保存命令变成可搜索资产。

交付：

- 多行输入和软换行。
- 括号、引号的基础补全。
- 命令历史搜索。
- 命令搜索面板，覆盖历史命令和保存命令。
- 基础补全，优先覆盖命令名、路径和常用参数。

参考：

- Warp：`app/src/terminal/input/`、`app/src/search/command_search/`、`app/src/search/command_palette/`、`app/src/integration_testing/input/`。

flutterm 依赖检查：

- 需要确认 Ianvs Terminal 能在提交前接管输入缓冲区，并在提交时把最终命令写入 flutterm session。
- 如果 flutterm 的 `TerminalInputController` 不适合现代输入区，应记录需要的低层输入接口。

### M3A：默认现代输入栏与 Raw 输入切换

目标：先建立产品侧现代输入缓冲和提交通道，默认接管普通命令输入，同时保留 Raw 输入处理 `vim`、`top`、REPL 等交互场景。

交付：

- 每个 `LocalShellSessionController` 持有独立 `ModernInputController`，保存 draft、手动 Raw 状态和自动 Raw 提示。
- 底部输入栏默认显示并聚焦；`Enter` 提交 draft，`Shift+Enter` 插入换行，空 draft 不提交。
- 提交时写入 `command + Enter` 到 flutterm runtime，Enter 字节遵循当前 frame 的换行模式。
- Paste 在 Modern 模式下插入 draft；Raw 模式下继续走 flutterm 的 paste 输入。
- `Cmd+K` 回到 Modern 输入，`Cmd+Shift+I` 切换手动 Raw，输入栏内 `Escape` 切到 Raw。
- 自动 Raw 条件为 `mouseMode != off`、`applicationCursor`、`applicationKeypad` 或 `focusTracking`；不使用 `bracketedPaste` 避免普通 shell 误判。
- block Reinput 改为填入现代输入 draft 并聚焦输入栏，不直接写 PTY。
- 暂不做命令搜索、补全、保存命令、持久化历史或复杂输入解析。

完成条件：

- Unit tests 覆盖 draft 更新、多行、提交清空、空提交 no-op、手动 / 自动 Raw 状态和 reset。
- Widget tests 覆盖默认聚焦、提交前不写 PTY、提交后写入、Shift+Enter、Raw 切换、auto Raw、多 tab 隔离、退出 / 重启、Paste 和 block Reinput。
- 真实 shell smoke 覆盖现代输入提交 `echo ianvs-modern`，以及 zsh block 继续从现代输入提交的命令生成。
- `FLUTTERM_FEEDBACK.md` 记录 flutterm 当前未公开 alternate screen / raw app hint；M3A 以产品侧自动提示和手动 Raw 兜底。

### M3B：当前 Tab 命令历史搜索

目标：复用 M2B / M2C 的真实 zsh blocks 和 M3A 的现代输入栏，先让当前 tab 的历史命令可搜索、可预览、可重新输入。

交付：

- 每个 `LocalShellSessionController` 持有独立 `CommandHistoryController`。
- 历史来源只使用当前 tab 已完成、命令非空的 blocks；running block 不进入历史。
- 搜索按大小写不敏感 substring 匹配命令文本；结果按最新优先，相同命令只保留最新一条。
- 底部输入栏提供 History 按钮；`Cmd+R` 打开命令历史搜索面板。
- 面板显示 `N/M`、命令、状态和输出首行预览；`Up / Down` 切换，`Enter` 回填现代输入栏，`Escape` 关闭。
- 选择命令只填入 draft，不自动提交、不写 PTY、不追加换行。
- Raw 输入模式下不打开历史搜索；shell 退出后仍可查看历史，但不能重新输入。
- 暂不做持久历史、保存命令、跨 tab 搜索、补全、pane、session restore 或 flutterm 修改。

完成条件：

- Unit tests 覆盖 blocks 派生历史、排除 running / 空命令、去重、最新优先、大小写不敏感搜索、上下切换和回填 draft。
- Widget tests 覆盖 `Cmd+R`、History 按钮、搜索计数、`Up / Down / Enter / Escape`、多 tab 隔离、Raw no-op 和退出态只读。
- 真实 shell smoke 覆盖 `/bin/zsh` 生成真实 block 后，可搜索 `history` 并回填 `echo ianvs-history`。

### M3C：本地保存命令库

目标：把常用命令从一次性的历史搜索结果提升为本地保存命令资产，并与当前 tab 历史统一搜索、预览和重新输入。

交付：

- 新增本地保存命令文件：`~/Library/Application Support/Ianvs/ianvs-terminal/saved_commands.json`。
- `SavedCommandsStore` 读写 `version + commands[]` JSON；缺失或坏 JSON 返回空列表。
- `SavedCommandsController` 支持保存、删除、trim、忽略空命令、精确去重和最近保存优先。
- 命令搜索结果合并全局 saved commands 和当前 tab history；saved 优先，已保存命令不重复显示 history。
- 底部输入栏提供 Save command 按钮，保存当前非空 draft。
- 命令搜索面板显示 `Saved` / `History` 来源；History 行可保存，Saved 行可删除。
- 选择任意结果只填入 modern draft，不自动提交、不写 PTY、不追加换行。
- 暂不做标题、标签、云同步、跨设备共享、参数化模板、补全、pane、session restore 或 flutterm 修改。

完成条件：

- Unit tests 覆盖 store 缺失 / 保存重读 / 坏 JSON、controller trim / 空命令 / 去重 / 删除，以及 saved + history 合并和回填。
- Widget tests 覆盖保存 draft、来源标记、history 保存、saved 删除、多 tab 全局 saved、active tab history 隔离和 app 重建恢复。
- 真实 shell smoke 覆盖 `/bin/zsh` 生成真实 block 后保存为 saved command，重新加载后可搜索并回填。

### M3D：现代输入括号与引号补全

目标：补齐现代输入栏里的基础编辑补全，只处理括号和常用引号，不进入命令名、路径或 shell 语法解析。

交付：

- 新增现代输入编辑 helper，支持 `()`、`[]`、`{}`、`'`、`"`。
- 不自动补反引号，避免 shell 命令输入误触。
- 输入左符号时插入成对符号，光标停在中间。
- 有选区时，用成对符号包裹选区。
- 光标后方已经是对应右符号时，输入右符号只跳过，不重复插入。
- 光标夹在空成对符号中间时，`Backspace` 删除一整对。
- 补全只作用于现代输入栏；Raw 输入模式继续交给 flutterm terminal。
- `Enter`、`Shift+Enter`、`Escape`、Paste、Raw 切换、History 和 Save command 保持既有行为。
- 暂不做命令名补全、路径补全、反引号补全、复杂 shell 语法或 flutterm 修改。

完成条件：

- Unit tests 覆盖成对插入、选区包裹、右符号跳过、空成对符号删除，以及普通字符、反引号和无关按键 no-op。
- Widget tests 覆盖现代输入栏中的括号 / 引号补全、选区包裹、右符号跳过、`Backspace` 删除、Raw 模式不启用补全，并确认提交、换行、粘贴、历史和保存命令不回退。
- `flutter analyze`、`flutter test`、真实 shell smoke、`flutter build macos` 通过。

### M3E：Fig Specs 转换框架与现代输入补全

目标：参考 Fig completion spec 模型，建立构建期 TypeScript specs 转换框架，并在现代输入栏中提供命令、选项、参数、路径和可转换 generator 补全。

交付：

- `tool/fig_spec_converter` 提供 Node 转换工具，输入为本地 `withfig/autocomplete/src`，通过 `FIG_AUTOCOMPLETE_DIR` 指定。
- Fig 源固定为 `withfig/autocomplete@aef52acff84c45edde61ae610cc2c964802b9a38`，转换产物写入 `assets/fig_specs/`。
- 转换字段覆盖 command、subcommand、option、arg、suggestion、template 和字符串型 generator script。
- `diagnostics.json` 记录 JS `postProcess`、`custom`、函数型 `script` 和转换失败 spec；运行时不执行这些 JS 逻辑。
- Dart 运行时提供 Fig 风格模型、输入 tokenizer、resolver 和 completion controller。
- root command 补全来自 Fig `index.json` 和当前环境 `PATH` 的可执行文件。
- `filepaths` / `folders` template 使用 Dart `Directory` 读取当前 tab cwd。
- zsh `precmd.pwd` 更新当前 tab cwd；非 zsh 使用 session launch cwd 或 `$HOME`。
- 现代输入栏 `Tab` 打开或接受补全；面板打开时 `Up / Down` 切换，`Enter / Tab` 接受，`Escape` 关闭。
- 接受补全只替换当前 token，不提交命令、不写 PTY。
- Raw 输入模式和 shell 退出态不触发现代补全。
- 不修改 flutterm，不新增云同步、用户自定义 spec 编辑器、参数模板 UI 或 shell 原生补全桥接。

完成条件：

- Node converter tests 覆盖 TS fixture 转换、JSON 产物、unsupported diagnostics。
- Dart unit tests 覆盖 tokenizer、root command、subcommand、option、arg、path template、generator 和 token 替换。
- Widget tests 覆盖 `Tab` 补全面板、单候选直接接受、多候选切换、tab 隔离、Raw no-op 和退出态 no-op。
- 真实 shell smoke 覆盖 zsh cwd 驱动的路径补全，以及临时 `PATH` 可执行文件的 root command 补全。
- `flutter analyze`、`flutter test`、真实 shell smoke、`flutter build macos` 通过。

M3 总体完成条件：

- 用户可以编辑长命令而不被终端原始输入限制打断。
- 历史命令和保存命令可以被搜索、预览、重新输入。
- 普通 shell 输入和多行编辑输入之间切换稳定。

## M4：工作区、pane 和启动配置

目标：把终端从单个 tab 提升到按项目恢复的工作区。

交付：

- split panes。
- session restore，恢复窗口、tab、pane、目录和焦点。
- launch configuration，用文件保存项目启动布局。
- 项目模板，包含目录、tab、pane 和启动命令。
- 会话搜索和快速跳转。

参考：

- Warp：`app/src/pane_group/`、`app/src/session_management.rs`、`app/src/launch_configs/`、`app/src/integration_testing/pane_group/`、`app/src/integration_testing/launch_configs.rs`。

flutterm 依赖检查：

- 需要确认多个 flutterm session 并发运行时的资源释放、resize 和轮询策略稳定。
- 如果恢复 session 只恢复布局而不能恢复进程状态，要在产品文案和验收里写清楚。

### M4A：单窗口 Split Panes 基础可用

目标：先在一个 tab 内支持多个真实本地 shell pane，建立 M4 后续 session restore 和 launch configuration 可复用的运行模型。

交付：

- 每个 tab 持有 pane tree；leaf 是一个独立 `LocalShellSessionController`，split node 保存方向和比例。
- Header、菜单、Copy / Paste / Restart / Find / History / Completion 始终作用于 active pane。
- 支持 Split Right、Split Down、Close Pane、Next Pane、Previous Pane。
- 新 pane 立即启动真实本地 shell，并继承 active pane 当前 cwd；cwd 不存在时回退默认启动 cwd。
- pane divider 支持拖动调整比例，比例限制在 `20% ~ 80%`。
- 关闭 pane 会释放对应 shell；最后一个 pane 禁止关闭；关闭 tab 会释放该 tab 下所有 panes。
- 多 pane 的现代输入、Raw 状态、blocks、history、completion cwd 和查找状态互不串扰。
- 暂不做 session restore、launch configuration、项目模板、pane 持久化、SSH、跨窗口或 flutterm 修改。

完成条件：

- Unit tests 覆盖 pane tree、split、cwd 继承、pane 切换、关闭 pane、最后 pane 禁止关闭和关闭 tab 释放全部 panes。
- Widget tests 覆盖 Header / 菜单入口、active pane 高亮、点击切换、快捷键、divider resize 和 active pane 操作隔离。
- 真实 shell smoke 覆盖两个 pane 的独立输出、关闭 pane 后剩余 pane 可用，以及 zsh cwd 继承后的路径补全。
- `flutter analyze`、`flutter test`、真实 shell smoke、`flutter build macos` 通过。

### M4B：Session Restore 基础可用

目标：在 M4A pane tree 基础上，自动保存并恢复单窗口内的 tab、pane 布局、cwd 和 active focus。恢复时重新创建真实本地 shell，不恢复旧进程状态。

交付：

- 本地保存文件固定为 `~/Library/Application Support/Ianvs/ianvs-terminal/session_restore.json`。
- JSON 保存 `version`、`activeTabIndex` 和 `tabs[]`；每个 tab 保存 fallback title、active pane id、pane tree、split direction / ratio 和 leaf cwd。
- app 启动时优先恢复上次布局；restore 文件缺失、损坏、空 tabs 或字段非法时，回退为一个默认 tab / 一个默认 pane。
- 新建 tab、split pane、关闭 tab / pane、切换 active tab / pane、拖动 divider 和 zsh `precmd.pwd` 更新 cwd 后触发 debounce 保存。
- 恢复 leaf cwd 时，存在则作为新 shell 的启动目录；不存在则回退设置默认 cwd、`$HOME` 或当前目录，并保存回退后的 cwd。
- 恢复后 Header、菜单、现代输入栏、block panel、history 和 completion 继续只作用于 active pane。
- 暂不恢复进程、scrollback、blocks、modern draft、selection、find query、history query、completion panel、窗口尺寸或窗口位置。
- 暂不做 launch configuration、项目模板、会话搜索、SSH、跨窗口或 flutterm 修改。

完成条件：

- Unit tests 覆盖 restore store 缺失、坏 JSON、保存重读、空 tabs、非法 split ratio、cwd 回退和 debounce 保存。
- Controller tests 覆盖从 restore state 创建 tabs / pane tree、active tab / pane 恢复、cwd 作为 session config、结构变化和 active 变化触发保存。
- Widget tests 覆盖首次启动默认布局、损坏 restore 回退、重建 app 后恢复布局和 active focus、active pane 操作作用域，以及 divider ratio 恢复。
- 真实 shell smoke 覆盖两 tab / 两 pane 布局恢复、active pane 恢复，以及恢复后的新 zsh shell 使用保存的 cwd。
- `flutter analyze`、`flutter test`、真实 shell smoke、`flutter build macos` 通过。

M4 总体完成条件：

- 一个项目可以保存并重新打开相同的 tab、pane 和目录结构。
- 多 pane 并发运行时输入焦点清楚。
- 关闭和恢复不会留下失效 session。

## M5：SSH 会话和 Ianvs 安全上下文

目标：在 terminal 产品内支持安全远程访问的显示和记录，但不实现网关。

交付：

- SSH 会话作为一种 terminal session 类型。
- 会话标签显示主机、账号、环境和项目。
- 身份上下文显示当前用户、授权来源和会话有效期。
- 审计导出接口预留，记录命令、输出摘要、时间和目标环境。

参考：

- Warp：`app/src/terminal/ssh/`、`app/src/terminal/remote_tty/`、`app/src/terminal/session_settings/`。

边界：

- 不实现 SSH 网关。
- 不实现零信任网络控制面。
- 不实现 AI 网关。
- 不把管理后台能力塞进 terminal。

完成条件：

- 本地终端和 SSH 终端使用同一套 tab、pane、block、输入和搜索体验。
- 安全上下文可见，不依赖用户记忆当前连到哪里。
- 网关相关能力只通过接口或占位文档表达。

## M6：跨平台适配预留

目标：在 macOS 主线稳定后，把 Flutter 客户端的跨平台边界整理成可执行计划。

交付：

- Windows / Linux 桌面端适配评估：窗口、菜单、快捷键、PTY、路径、字体和打包。
- iOS / Android 移动端适配评估：远程 terminal、SSH / Ianvs 会话、触屏输入、系统剪贴板和安全上下文。
- 平台能力矩阵，标注 `支持`、`降级`、`不支持` 和 `待验证`。
- flutterm 平台能力反馈，必要时补充到 `FLUTTERM_FEEDBACK.md`。

边界：

- M6 之前不要求 Windows、Linux、iOS、Android 可运行。
- iOS / Android 不承诺本地 shell。
- 移动端不要求完整复制桌面 tab / pane 操作密度。

完成条件：

- 有明确的平台适配矩阵。
- macOS 专属实现被适配层隔离。
- 下一阶段可以单独选择 Windows、Linux、iOS 或 Android 进入实现计划。

## 当前推进顺序

1. 先完成 M0，保证依赖边界和项目骨架正确。
2. 再推进 M1，让本地终端可日常使用。
3. M2 和 M3 分别处理 block 和输入区，不混在同一轮。
4. M4 处理工作区组织。
5. M5 再接入 SSH 和 Ianvs 安全上下文。
6. M6 在 macOS 主线稳定后整理跨平台适配计划。
