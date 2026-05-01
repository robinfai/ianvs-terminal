# Ianvs Terminal 对 flutterm 的反馈

Ianvs Terminal 当前工作树的 path dependency 解析到 `/Users/luobinghui/projects/flutter/flutterm`，并以这份本地 checkout 作为 terminal 实现依赖库。这里记录 Ianvs Terminal 消费 flutterm 时发现的 bug、限制和 feature 需求。

这份文档不是 flutterm 的任务清单。是否进入 flutterm 实现，要另行在对应 flutterm 工作树的 `docs/tasks/` 里写任务文档。

## 记录规则

每条反馈必须包含：

- 编号：使用 `FT-001` 这样的格式。
- 类型：`bug`、`feature` 或 `risk`。
- 影响里程碑：对应 `MILESTONES.md`。
- 现象或需求：具体描述，不写泛泛结论。
- 复现或触发条件：能写步骤就写步骤，不能复现就写触发场景。
- 期望行为：Ianvs Terminal 需要 flutterm 提供什么。
- 候选上游位置：例如 `flutterm_terminal`、`flutterm_pty`、`native/core`。
- 当前处理：`观察`、`产品侧绕行`、`需要上游任务`、`已转上游` 或 `关闭`。

## 当前反馈

### FT-001：需要稳定的命令边界和退出状态

- 类型：feature
- 影响里程碑：M2 block 化命令历史
- 现象或需求：Ianvs Terminal 要把一次命令和对应输出整理成 block，并显示成功、失败、运行中和中断状态。M2A 已建立产品侧 block 模型和 UI 操作；M2B 开始接入真实 zsh 命令。
- 复现或触发条件：执行 `echo ok`、`false`、长时间运行命令、`Ctrl-C` 中断命令时，产品侧需要知道命令开始、命令文本、输出归属、命令结束、退出码和中断状态。`TerminalInputController` 仍没有公开的“用户提交命令”回调，不能只靠键盘输入判断真实命令边界。
- 期望行为：flutterm 提供通用 shell hook 事件通道，shell integration 可以通过 DCS / OSC 等控制序列发送结构化事件。最低需要 command start、command text、command finish 和 exit code；输出范围可以先由消费方结合当前 frame 和 selection text 读取。
- 候选上游位置：`native/core` 的控制序列解析，`flutterm_terminal` 的 runtime event 模型。
- 当前处理：M2B 已推进上游修改。flutterm native core 增加通用 DCS hook：`ESC P hook;<hex-json> ESC \`，`flutterm_terminal` 透出 `TerminalSessionShellHookEvent`。Ianvs Terminal 先实现 zsh integration；bash / fish 和更完整的 command lifecycle 仍待后续。

### FT-002：现代输入区需要清晰的提交接口

- 类型：feature
- 影响里程碑：M3 现代输入和命令复用
- 现象或需求：Ianvs Terminal 要在提交前由产品侧管理多行输入、软换行、括号补全、历史搜索和命令搜索。
- 复现或触发条件：用户编辑多行命令，选择历史命令，或从命令搜索面板把命令放回输入区。
- 期望行为：flutterm 保持低层 session 输入能力稳定，允许 Ianvs Terminal 在产品侧管理输入缓冲区，并在提交时写入最终字节。
- 候选上游位置：`flutterm_terminal` 的 `TerminalInputController` 和 runtime 输入接口。
- 当前处理：M3A-M3E 已在产品侧接管现代输入缓冲、历史搜索、保存命令、括号补全和 Fig 风格补全。提交仍通过 flutterm runtime `sendInput` 写入最终字节；当前阶段不需要修改 flutterm。

### FT-003：多 session 并发和恢复需要资源边界

- 类型：risk
- 影响里程碑：M4 工作区、pane 和启动配置
- 现象或需求：Ianvs Terminal 要在一个窗口中运行多个 tab 和 pane，并在恢复布局时重新创建 session。
- 复现或触发条件：打开多个 pane，频繁 resize，关闭窗口后恢复项目布局。
- 期望行为：flutterm 的 session 创建、关闭、resize、轮询和资源释放在多 session 下保持稳定。
- 候选上游位置：`flutterm_terminal` 的 `TerminalRuntimeController`，`flutterm_pty` 的 session backend。
- 当前处理：M4A 已在 Ianvs Terminal 产品侧实现每个 pane 独立 `LocalShellSessionController` 和真实 flutterm session。M4B 已实现基础 session restore，恢复时重新创建 flutterm session，只恢复布局、cwd 和 active focus，不要求 flutterm 提供进程快照或 scrollback 持久化。新增 widget tests 和真实 shell smoke 覆盖 split、关闭、resize、两个 pane 独立输出，以及恢复后的新 shell 使用保存 cwd；暂未发现需要修改 flutterm 的资源释放问题。后续仍需做多 pane 长时间运行和恢复压力验证。

### FT-004：手工兼容性矩阵仍是产品风险

- 类型：risk
- 影响里程碑：M1 日常本地终端
- 现象或需求：flutterm 文档记录了 VT220、powerline / ANSI prompt、真实 trackpad scrollback、字体度量 / DPI resize 等人工矩阵仍缺真实完成证据。
- 复现或触发条件：使用复杂 prompt、宽字符、真实触控板滚动或不同 DPI / 字体设置时，可能出现显示或交互偏差。
- 期望行为：M1 进入日常使用前，Ianvs Terminal 要么复用 flutterm 的验证结论，要么在产品侧记录风险和限制。
- 候选上游位置：`flutterm` 文档和手工验证任务。
- 当前处理：需要上游任务。M1 完成前不能把这些风险写成已通过。

### FT-005：M0 使用的 flutterm 本地基线不是完整绿灯

- 类型：risk
- 影响里程碑：M0 项目骨架和依赖边界
- 现象或需求：M0 决定临时固定当前本地 flutterm 工作树推进。`flutterm_pty` 与 `flutterm_terminal` 包级测试通过，Ianvs Terminal 真实 shell smoke 也能通过 flutterm runtime 看到 `echo ianvs` 输出；但 `native/core cargo test` 当前有 1 个失败项，flutterm 工作树也存在未提交修改。
- 复现或触发条件：在 `2026-04-29` 本地执行 `cd /Users/robinfai/personal/flutterm/native/core && cargo test`，失败项为 `damage_driven_delta_reports_low_rows_scanned_for_single_line_scroll`。同日 `git status --short` 显示 example shell、macOS window、widget tests 和 `packages/flutterm_terminal/lib/src/terminal/terminal_input_controller.dart` 有修改。
- 期望行为：Ianvs Terminal M0 可以继续验证真实 shell，但不能把 flutterm native/core 写成稳定基线。后续进入 M1 前，需要重新确认 flutterm 测试和手工兼容性风险。
- 候选上游位置：`native/core`，`packages/flutterm_terminal`。
- 当前处理：产品侧记录并继续。M0 不先修 flutterm；M1 前重新跑 flutterm 基线和真实 shell smoke。

### FT-006：delta 帧携带行文本时 dirty ranges 可能不足导致行缓存不重绘

- 类型：bug
- 影响里程碑：M1 日常本地终端
- 现象或需求：Ianvs Terminal 偶发启动后 PS1 文本没有显示，但光标已经在 prompt 后的正确列位置。产品侧测试复现为：先绘制空白 snapshot，再收到携带 prompt 文本的 delta 帧；如果该 delta 帧没有把对应行纳入 `dirty_ranges`，`RenderTerminalViewport` 会保留旧的空白行缓存，只更新光标。
- 复现或触发条件：启动本地 shell 时首帧为空白，随后 prompt 文本通过 delta 帧进入；delta 帧包含 `rows` 但 `dirty_ranges` 为空或没有覆盖这些行。
- 期望行为：flutterm 发出的 delta 帧中，所有携带的行都应能触发渲染重建；可以由上游保证 `dirty_ranges` 覆盖 `rows`，也可以由 `TerminalViewportController` 或渲染层在消费 delta 帧时补齐。
- 候选上游位置：`flutterm_terminal` 的 `TerminalViewportController` / `RenderTerminalViewport`，以及 `native/core` 的 frame diff 生成。
- 当前处理：产品侧绕行。Ianvs Terminal 在接收 `TerminalSessionFrameEvent` 时，会把 delta 帧里实际携带的行合并进 dirty ranges 后再交给显示层。

### FT-007：启动期可能出现只有光标位置、没有 prompt 行文本的帧

- 类型：bug
- 影响里程碑：M1 日常本地终端
- 现象或需求：Ianvs Terminal 偶发启动后 PS1 没有显示，但光标已经移动到 prompt 结束位置。与 FT-006 不同，这条路径里产品侧可能收到的当前帧没有 prompt 行文本，只有 cursor row / col 更新。
- 复现或触发条件：启动本地 shell，初始 prompt 输出与首个 viewport resize / warm-up refresh 交错；native core 可能先给出 cursor col 已更新、当前行为空的 frame。
- 期望行为：flutterm 在启动期 resize 与 shell 初始输出交错时，仍能保证 prompt 所在行进入 snapshot 或 delta rows；如果只更新 cursor，也应提供可请求全量重绘的公开 API。
- 候选上游位置：`flutterm_terminal` 的 `TerminalRuntimeController` refresh 策略，`native/core` 的 frame diff / resize damage 生成。
- 当前处理：产品侧绕行。Ianvs Terminal 在启动期检测到“光标可见且列号大于 0，但当前 cursor 行为空或缺失”时，会对当前 scrollback offset 请求一次 `scrollViewportTo`，利用 native core 的 full repaint 路径恢复 prompt 行。

### FT-008：terminal 内行内 block 分隔需要渲染层扩展点

- 类型：feature
- 影响里程碑：M2 block 化命令历史，M4 工作区、pane 和启动配置
- 现象或需求：M2C 先用 Ianvs Terminal 产品侧右侧历史面板展示 blocks，没有在 terminal 内容中绘制 inline block card、分隔线或范围背景。后续如果要把 block 分组直接画进 terminal scrollback，需要 flutterm 能把产品侧 block/range 信息传入渲染层。
- 复现或触发条件：用户执行多条命令后，希望在 terminal 内容区域内看到命令块边界、状态标记、hover 操作或范围背景，而不是只在右侧面板看到历史列表。
- 期望行为：flutterm 提供 terminal render-layer 的范围标注扩展点，例如按 scrollback absolute row range 绘制分隔线、背景、状态 gutter 或 overlay action anchor；同时不破坏选择、滚动、搜索和复制行为。
- 候选上游位置：`flutterm_terminal` 的 `TerminalViewport`、`RenderTerminalViewport`、selection/search/range rendering 模型。
- 当前处理：观察。M2C 不修改 flutterm 渲染层；产品侧只消费 block 数据并通过右侧面板操作。进入 inline block 体验前再写独立上游任务。

### FT-009：现代输入需要更明确的 Raw 应用状态

- 类型：feature
- 影响里程碑：M3 现代输入和命令复用
- 现象或需求：M3A 默认让 Ianvs Terminal 的现代输入栏接管普通命令输入，但 `vim`、`top`、REPL 等交互场景需要回到 Raw 输入。当前 flutterm Dart frame 暴露了 mouse、application cursor、application keypad 和 focus tracking 等 modes，但没有公开 alternate screen 或更明确的 raw app hint。
- 复现或触发条件：启动 `vim`、`less`、`top` 或某些 REPL 时，terminal 可能进入 alternate screen 或 raw-like 交互；Ianvs Terminal 只能从现有 modes 做部分自动判断，不能覆盖所有程序。
- 期望行为：flutterm 在 `TerminalFrameModes` 或 runtime event 中公开 `alternate_screen_active` 或通用 raw app hint，让产品层能更可靠地决定是否自动切到 Raw 输入。
- 候选上游位置：`native/core` frame meta，`flutterm_terminal` 的 `TerminalFrameModes` / `TerminalFrameDiff`。
- 当前处理：产品侧绕行。M3A 使用 `mouseMode != off`、`applicationCursor`、`applicationKeypad`、`focusTracking` 作为自动 Raw 条件，并提供 `Cmd+Shift+I` 手动 Raw 兜底。

### FT-010：当前 native core debug dylib 与 flutterm_pty 绑定符号不匹配

- 类型：risk
- 影响里程碑：M1 日常本地终端，M2 block 化命令历史，M3 现代输入和命令复用，M4 工作区、pane 和启动配置
- 现象或需求：Ianvs Terminal 在 `2026-05-01` 本地执行真实 shell smoke 时，`NativePtyBackend.load()` 直接失败，报 `Failed to lookup symbol 'flutterm_session_search_json'`。这说明当前 debug `libflutterm_core.dylib` 与 `flutterm_pty` / `flutterm_terminal` Dart 侧绑定不匹配，导致真实本地 shell 路径无法稳定验证。
- 复现或触发条件：在当前本机依赖树 `/Users/luobinghui/projects/flutter/flutterm` 下运行 `FLUTTERM_CORE_LIB=/Users/luobinghui/projects/flutter/flutterm/native/core/target/debug/libflutterm_core.dylib flutter test test/real_shell_smoke_test.dart`，前两个 smoke 用例会立即在 `NativePtyBackend.load()` 处失败；随后其他真实 shell 用例也会因为 runtime 无法正常工作而超时。
- 期望行为：当前 `libflutterm_core.dylib` 应导出 `flutterm_session_search_json`、`flutterm_session_selection_text` 等 `flutterm_pty` 当前绑定需要的符号；或者 `flutterm_pty` / `flutterm_terminal` 与 native core 一起以同一基线构建和验证，避免出现 Dart 层 API 已升级而 native dylib 仍停留在旧 ABI 的情况。
- 候选上游位置：`native/core` 导出符号与构建产物，`flutterm_pty` 的 FFI 绑定基线，`flutterm` 本地开发工作流。
- 当前处理：关闭。`2026-05-02` 在 `/Users/luobinghui/projects/flutter/flutterm` 重新构建 debug native core 后，`nm -gU native/core/target/debug/libflutterm_core.dylib` 已确认导出 `_flutterm_session_search_json` 和 `_flutterm_session_selection_text`。真实 shell smoke 不再因缺符号失败；后续 shell-hook / cwd / block 超时另记为 `FT-011`。

### FT-011：真实 zsh shell_hook / cwd 事件链路未贯通

- 类型：bug
- 影响里程碑：M2 block 化命令历史，M3 现代输入和命令复用，M4 工作区、pane 和启动配置
- 现象或需求：在 `FT-010` 的 FFI 符号预检通过后，Ianvs Terminal 真实 shell smoke 仍有 6 个用例失败，集中表现为 zsh `preexec` / `command_finished` / `precmd.pwd` hook 没有到达产品层：真实 command block 列表为空，pane restore / split pane / path completion 等用例等待 cwd 更新超时。
- 复现或触发条件：在当前本机依赖树 `/Users/luobinghui/projects/flutter/flutterm` 下运行 `FLUTTERM_CORE_LIB=/Users/luobinghui/projects/flutter/flutterm/native/core/target/debug/libflutterm_core.dylib flutter test test/real_shell_smoke_test.dart`。截至 `2026-05-02`，结果为部分通过但 zsh hook / cwd / block 相关用例失败。
- 期望行为：flutterm native/core 应解析 Ianvs zsh integration 发送的通用 DCS hook：`ESC P hook;<hex-json> ESC \`，生成 `shell_hook` 事件并避免把 hook 控制序列渲染为 terminal 内容；`flutterm_pty` / `flutterm_terminal` 应把该事件稳定透出给消费方，使 Ianvs Terminal 能创建真实 command blocks、更新 cwd，并驱动 cwd-aware completion。
- 候选上游位置：`native/core` 控制序列解析，`flutterm_pty` 的 `PtyEvent` 透出，`flutterm_terminal` 的 runtime event 模型。
- 当前处理：关闭。`2026-05-02` 已在 `/Users/luobinghui/projects/flutter/flutterm` 的 `native/core` 实现 DCS `hook;<hex-json>` 解析，并通过 `TerminalEvent(kind: "shell_hook")` 透出到 `flutterm_pty`。验证通过：`cargo test shell_hook`、`dart test packages/flutterm_pty/test/native_pty_backend_test.dart`、`./tools/build_core.sh`、以及 Ianvs Terminal 真实 shell smoke `+15`。后续若要清理产品侧 `PtySessionBackend` adapter，可在 flutterm_terminal typed runtime event 层另开非阻塞 follow-up。

## 模板

```markdown
### FT-XXX：标题

- 类型：
- 影响里程碑：
- 现象或需求：
- 复现或触发条件：
- 期望行为：
- 候选上游位置：
- 当前处理：
```
