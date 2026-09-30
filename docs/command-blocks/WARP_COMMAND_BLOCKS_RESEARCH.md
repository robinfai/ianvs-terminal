# Command Blocks：文档分析与当前分支实现

研究日期：2026-09-29。实现基于 `composer` 分支；保留其 Composer、PTY、终端渲染器和 shell 所有权协议。

## 文档范围与结论

检索 Warp 官方 Terminal 文档索引及完整 Terminal 文档集，逐项阅读 Blocks 下全部八篇文档，同时检查输入位置、外观、全屏应用、链接、文本选择与快捷键的关联规则。以下为归纳，非逐字转载。

| 官方资料 | 关键行为 | 本项目的实现或取舍 |
| --- | --- | --- |
| [Blocks overview](https://docs.warp.dev/terminal/blocks/) | 一个执行单元包含命令及其输出；对整个单元操作 | 独立 `CommandBlock`，不混用原有 OSC 1337 富内容块 |
| [Block basics](https://docs.warp.dev/terminal/blocks/block-basics/) | 单选、多选、范围选择、键盘导航、执行状态 | 命令点击选择，Shift 范围选择，macOS Cmd 多选；方向键、块首尾跳转；运行／退出码／耗时。失败用小型红色状态，不采用整块红底和左侧色条 |
| [Block actions](https://docs.warp.dev/terminal/blocks/block-actions/) | 复制命令、输出或两者；重用命令；书签；块菜单 | 右键与省略号菜单；复制原始保留输出；插回 Composer 但不执行；书签、折叠、跳转。状态保存在会话中，切换标签页保留，退出应用不持久化 |
| [Block find](https://docs.warp.dev/terminal/blocks/find/) | 从新到旧检索，全文／单块，大小写与正则 | 命令与输出检索、单块作用域、匹配行列表和定位；正则在 Rust 执行。结果有上限，未实现 Warp 的所有逐字符高亮与逐匹配导航交互 |
| [Block filtering](https://docs.warp.dev/terminal/blocks/block-filtering/) | 文本、正则、大小写、反选、上下文；可撤销 | 已完成块支持上述选项；关闭过滤保留查询，源终端不变；复制仍遍历未过滤的输出。运行块保持完整输入通道，不折叠或过滤 |
| [Block sharing](https://docs.warp.dev/terminal/blocks/block-sharing/) | 云端永久链接、嵌入、选择分享内容、撤销分享 | 实现可预览的本地 Markdown 导出，选择命令、输出、目录与状态；不会上传。云端链接、嵌入和撤销需要分享服务，本次未实现 |
| [Background blocks](https://docs.warp.dev/terminal/blocks/background-blocks/) | 将推测为后台进程的输出放入无命令块；前后台并发时归属有歧义 | 当前 DCS 协议没有可靠的 prompt-end 标记。就绪期间检测到未归属变化时退回完整 Terminal，保留输出；未实现独立后台块，也不伪造命令归属 |
| [Sticky command header](https://docs.warp.dev/terminal/blocks/sticky-command-header/) | 滚动后保留当前命令标题；跟随运行尾部时隐藏；可跳转和关闭 | 命令标题离开视口后才固定，点击跳回块首，可到块末或关闭；跟随运行尾部不固定 |
| [Blocks behavior](https://docs.warp.dev/terminal/appearance/blocks-behavior/) | 紧凑间距、分隔线等外观控制 | 会话内可切换紧凑、分隔线与固定标题；未新增全局偏好存储 |
| [Input position](https://docs.warp.dev/terminal/appearance/input-position/) | 输入编辑器位置和块布局联动 | 延续当前分支底部 Composer；未新增顶部／经典位置选择 |
| [Full-screen apps](https://docs.warp.dev/terminal/more-features/full-screen-apps/) | TUI 需要原始终端的光标、鼠标与滚动语义 | alternate screen、鼠标报告、富图像／OSC 1337 小部件使用完整终端视图；运行普通命令仍使用块内真实 Terminal |
| [Files and links](https://docs.warp.dev/terminal/more-features/files-and-links/) | 输出中的链接和文件操作 | 保留 OSC 8 链接范围及原有可见链接识别，打开行为交回宿主处理；不自动执行链接内容 |
| [Text selection](https://docs.warp.dev/terminal/more-features/text-selection/) | 文本选择与整块选择并存；智能选择和矩形选择 | 沿用 `TerminalViewport` / `SelectionController` 的终端单元格选择与复制，不用普通富文本模拟输出 |
| [Keyboard shortcuts](https://docs.warp.dev/getting-started/keyboard-shortcuts/) | 快捷键有平台差异 | Composer 中 Cmd+↑/↓（其他桌面平台 Ctrl）进入块导航；块内方向键、Shift 范围选择、Cmd/Ctrl+B 书签、Alt+↑/↓ 书签导航、Cmd/Ctrl+F 查找、Alt+Shift+F 过滤、Esc 返回输入 |
| [How Warp works](https://www.warp.dev/blog/how-warp-works) | shell 集成建立边界，终端仿真负责输出，编辑器独立处理命令 | 作为 2021 年的架构说明参考；本实现继续使用项目的 Rust 仿真器与 Flutter 渲染器，不将文章当成当前 Warp 内部实现承诺 |

## 输出与焦点合同

用户追加要求：输出必须继续使用 Terminal；已完成块可以只读；执行时从 Composer 转移焦点到运行块的 Terminal。

实现中，每块输出由真正的 `TerminalViewport` 绘制。运行块拥有原 PTY 的输入能力，键盘、粘贴、IME 使用已有输入控制器；完成块拥有独立选择状态，但其输入 sink 没有写入 PTY 的能力，光标隐藏。Composer 运行时禁用且维持高度；shell 返回 ready 后恢复原编辑器焦点。重用只改草稿，不发执行请求。

桌面按用户确认的后续规则，默认整个 Block（标题、输出和状态）不超过终端可用区域的 1/3。标题与状态占用的空间先扣除，输出高度按实际终端行高向下取整，可在块内滚动或手动扩大；扩大选择按会话保留。手机采用后续调整的紧凑预览：最多显示末尾 6 行输出，短输出使用自然高度，键盘出现不再重新压缩每块。预览只跟随命令列表纵向滚动；「查看全部」打开单一滚动的全屏阅读页，按需读取原生输出分页、隐藏键盘并保存阅读位置及 Composer 草稿。手动回看暂停跟随，仅「回到最新」恢复。真实 macOS `top` 和 `vim` 已验证使用与 Normal 模式相同尺寸的完整 Terminal。

全屏／鼠标应用使用完整原生会话视图；退出后在支持的上下文由 tab 提示，用户通过右键菜单手动恢复块视图。图像和特殊协议内容采用保守的整会话回退，避免因投影缺少几何元数据丢失内容。未归属输出同样回退。书签、过滤和折叠是显示状态，不会修改 terminal grid。

## 数据与边界

1. 在仿真器解析 DCS 的准确位置读取既有 `hook;hex(JSON)`，归一化 `precmd / precmd.pwd / preexec / command_finished` 到语义 zone。宿主原有 hook 事件保持单一来源；新增捕获不重复发布 shell 生命周期事件。
2. 输出区间有行、起止列、命令、执行时目录、时间与退出状态。处理无尾换行、空输出、软换行、CR 重绘、满列 pending-wrap；后续提示符不进入复制结果。
3. `terminal.command_blocks` 是只读 session request。默认最近 128 块，每块预览尾部 48 行；显式请求分页最多 2048 行／约 512 KiB，列表预览预算 6 MiB，仍受公共 16 MiB 响应上限约束。历史受原生 scrollback 保留策略约束，不宣称无限历史。
4. 复制跨页遍历完整保留输出，软换行拼接、硬换行保留；复制期间宽度或保留起点变化会要求重试，避免拼错页；剪贴板上限 16 MiB。已淘汰输出明确标识。
5. 正则使用 Rust 的线性时间实现；查询最多 4096 字节，编译预算 1 MiB，上下文最多 20 行。预览和复制不为无过滤的大输出分配整份行号表。
6. 宽度重放后重新建立物理坐标，按命令／zone 身份恢复执行时间，避免窗口缩放改变耗时。协议边界不完整或原始重放已被截断时，沿用终端既有保留约束。

## 使用范围和后续边界

当前桌面宿主通过 tab 右键菜单选择普通终端或命令块，取代左下角 Composer 开关。应用设置的「优先终端模式」作用于新会话；实际使用 Blocks 仍需要当前会话的 Composer 所有权和上下文支持。SSH 跳转、嵌套 shell、全屏程序、只读或退出等能力失效会自动回退 Normal；tab 提示原因，能力恢复后也由用户手动切回。远端 Bash 4+ / Zsh 现通过内存注入协商独立的节点凭据和命令提交，真实 OpenSSH 已覆盖两层跳转、协议/本地 ssh 入口、emacs/vi 以及 macOS App 中的 top/vim。移动端默认优先 Blocks：首次协商成功后启用，能力丢失自动回退 Normal，恢复后保持手动切回。手机通过右上角会话菜单、平板通过顶部会话菜单触控切换；设置支持覆盖平台默认值。远端文件补全和历史仍独立于本轮范围。模式、草稿及块显示状态按会话隔离，分屏移动时保留。

这次完成的是当前架构可承载的本地 Command Blocks。云分享、独立后台块、全局外观持久化及完整 Warp 搜索导航属于尚未实现的差异，上表明确列出；不能把本地导出或完整终端回退宣称为这些功能的完整等价实现。
