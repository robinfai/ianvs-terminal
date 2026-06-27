# ianvs terminal Roadmap

这份文档定义当前执行顺序和长期方向。具体实现、验收记录和历史结果必须落到
`docs/tasks/`；路线图只负责说明先后关系、进入条件和完成条件。

本地 terminal 功能扩展的竞品分析与功能设计见
[LOCAL_TERMINAL_FEATURE_PLAN.md](LOCAL_TERMINAL_FEATURE_PLAN.md)。

## 当前执行口径

Hyper-like `Phase 0` 到 `Phase 4` 连同 defaults 清理已经进入历史阶段，不再沿
这套编号继续新增后续阶段。依据包括：

- `T-056` Phase 4 interaction polish 已完成：
  [T-056](tasks/shell-product/T-056-hyper-phase4-interaction-polish.md)
- `T-057` defaultProfileId narrowing 已完成：
  [T-057](tasks/shell-product/T-057-terminalprofiles-defaultprofileid-narrowing.md)
- `T-058` defaultProfileId removal 已完成：
  [T-058](tasks/shell-product/T-058-terminalprofiles-defaultprofileid-removal.md)

当前 live lane 已经转到 runtime / xterm 审计后续。
[T-062](tasks/feedback-handoffs/T-062-ianvs-terminal-feedback.md) 和
[T-063](tasks/runtime-pty/T-063-shell-hook-typed-runtime-event-and-multi-shell-contract.md)
已经把后续工作迁移到终端契约、证据和扩展基座，不再继续沿旧 shell 产品化阶段编号展开。

因此，近期执行顺序固定为 `M1` 到 `M5`。旧的 `Phase 3/4` 保留为长期方向，
但实际启动条件以下面的里程碑为准。

## M1: 终端一致性自动化收口

目标：

- 完成所有可自动化、可源码证明的 xterm 差距收口。
- 只补 probe、回归测试和明确的 unsupported / deferred 结论。
- 不新增 workspace、settings、renderer 或跨平台产品能力。

任务范围：

- [T-069](tasks/runtime-pty/T-069-synchronized-output-mode-contract.md)
- [T-071](tasks/terminal-interaction/T-071-xterm-scroll-resize-alt-buffer-probes.md)
- [T-072](tasks/runtime-pty/T-072-wrapped-line-search-regression.md)
- [T-073](tasks/runtime-pty/T-073-parser-osc-sgr-xterm-probes.md)
- [T-074](tasks/terminal-interaction/T-074-platform-input-ime-paste-probes.md) 的自动化部分
- [T-075](tasks/terminal-interaction/T-075-rendering-glyph-dpr-probes.md) 的自动化部分
- [T-076](tasks/verification-gates/T-076-terminal-performance-baseline-xterm-probes.md) 的本地基线部分

完成条件：

- [TERMINAL_XTERM_RECENT_FIX_AUDIT.md](TERMINAL_XTERM_RECENT_FIX_AUDIT.md) 里的
  `Gap` 只剩真正需要手工、平台证据或产品决策的项。
- `wrapped-line search`、`synchronized output`、`OSC / SGR / APC / base64`、
  `alt-buffer / resize`、`IME / paste`、`render / glyph` 都有命名 probe
  或明确 deferred 结论。
- 新增 probe 的最小专项命令写回对应任务文档和审计表。

## M2: 手工 / 平台 / 性能证据收口

目标：

- 集中处理自动化无法证明的手工、平台、视觉和性能证据。
- 把每个待确认项记录成 `pass`、`fail` 或 `blocked`。
- 任何 `fail` 立即拆成更小的实现任务。

任务范围：

- [XTERM_MANUAL_CONFIRMATION_QUEUE.md](XTERM_MANUAL_CONFIRMATION_QUEUE.md) 的
  `M-001` 到 `M-013`
- [T-065](tasks/verification-gates/T-065-phase4-windows-linux-validation-gate.md)
- `tools/cat_log_benchmark.sh --profile release` 的安静主机基线

完成条件：

- 每个 manual queue item 都有结果、日期、平台和必要观察记录。
- Linux 或 Windows 至少一个平台拿到真实 host 证据，或明确记录为 host /
  toolchain / Flutter target / 桌面权限 blocker。
- release benchmark 有一版带 host/toolchain 信息的基线；可疑结果拆为独立任务。

## M3: Runtime 扩展基座冻结

目标：

- 在证据面收敛后，定义下一阶段产品能力依赖的 runtime 基座。
- 以已落地的 `TerminalSessionShellHookEvent` 为稳定起点。
- 先冻结公共契约，再允许产品层消费。

任务范围：

- `bash` / `fish` logical hook 对齐。
- 输出归属和 command row range。
- [T-064](tasks/runtime-pty/T-064-terminal-row-range-annotation-extension-design.md)
  的 row-range annotation 设计冻结。

完成条件：

- 下一批公共 runtime contract 已定稿并写入任务文档或 ADR。
- 产品层不需要再临场决定 absolute row 语义、annotation 绘制顺序、
  shell-hook 兼容口径。
- `TerminalRowRangeAnnotationController`、`TerminalRowRangeAnnotation` 及其
  absolute-row 语义只在本里程碑冻结后进入实现。

## M4: Local Workspace Expansion 启动

目标：

- 启动长期 `Phase 3` 的第一批本地 workspace 能力。
- 第一批只做最小闭环，避免同时展开 layout、settings 和 notification 面。

任务范围：

- 统一 action id。
- launcher、menu、keybinding 共用同一 action 入口。
- same-cwd open。
- shell integration 驱动的 command / cwd 状态消费。

完成条件：

- 开始实现前已经有新的 phase/task 文档。
- keybinding、menu 和 launcher 都通过统一 action id 触发，不向 terminal input
  泄漏事件。
- `split right/down`、layout、notifications、hotkey window 暂不进入首轮，除非
  `M1` 到 `M3` 的契约已经稳定。

## M5: 条件性跨平台接入

目标：

- 只在有目标机证据后推进 Linux / Windows 接入。
- 保持 macOS 主链路不回退。

进入条件：

- `T-065` 已经在 Linux 或 Windows 上跑出非 `blocked` 的关键证据。
- 证据至少覆盖 build、PTY spawn、resize、search、selection text、
  shell-hook propagation 和 runnable app。

完成条件：

- 至少一个新增平台达到可运行标准。
- 文档明确记录平台差异和 blocker。
- 另一个平台继续保持 gate 状态，不写成已支持。

## 公共接口和约束

- 现阶段唯一稳定、可供后续产品层依赖的新公共 runtime 接口，是
  [T-063](tasks/runtime-pty/T-063-shell-hook-typed-runtime-event-and-multi-shell-contract.md)
  落地的 `TerminalSessionShellHookEvent`。
- kitty keyboard protocol 仍由
  [T-070](tasks/terminal-interaction/T-070-kitty-keyboard-protocol-scope.md)
  做 scope decision。未完成决策前，不把它写成默认支持面。
- `T-055 forced-closed` 继续视为共享历史风险，不单独阻塞后续里程碑；只有当
  `M-001` 到 `M-013` 需要同类证据时，才在对应 manual item 内重新记录。
- Flutter Canvas 是当前已验证可行的 renderer 方案；后续只有新的性能、视觉、
  平台证据证明现有方案不足时，才单开 focused task 重评 renderer。
- 任一 probe 或 manual item 得到 `fail` 后，必须拆 focused task，不把失败继续
  挂在里程碑描述里。

## 长期方向

以下阶段保留为长期方向，但不再代表当前执行顺序。

### Phase 1: macOS Local Shell Stabilization

目标：

- 稳定当前 `macOS + local shell` 主链路。
- 补齐 terminal 基础交互。
- 让文档、测试和验收流程成型。

完成条件：

- 本地 shell 日常可用。
- 多 tab、复制粘贴、滚动、resize 稳定。
- 文档布局适合持续迭代。
- 测试与验收规则已经固化。

状态：

- 已作为历史基础阶段处理。后续只在回归证据出现时拆 focused task。

### Phase 2: Terminal UX Hardening

目标：

- 提升 terminal 日常使用体验。
- 补强输入、选区、滚动、状态反馈等边角。
- 收敛已知行为不一致。

完成条件：

- 主要交互缺陷收敛。
- 已知问题和剩余风险更明确。
- 至少形成一轮稳定的人工 smoke 流程。

状态：

- 已作为历史基础阶段处理。后续 terminal 行为工作进入 `M1` 和 `M2` 的证据链。

### Phase 3: Local Workspace Expansion

目标：

- 把本地 tabs / panes / workspace / layout 能力收口成稳定产品模型。
- 建立统一 action registry，让快捷键、菜单和 command palette 共享同一动作入口。
- 建立本地配置模型，覆盖 profiles、keybindings、layouts、clipboard/paste
  policy、notification policy 和 hotkey window。
- 把 shell integration 的 prompt marks、cwd tracking、command status、recent
  commands / directories 做成本地效率能力。

进入条件：

- `M1` 到 `M3` 已完成。
- profile 模型、session 生命周期和 runtime 扩展契约足够清晰。

完成条件：

- 本地 workspace 支持 tab、split right/down、focus、resize、close、undo close、
  same-cwd open。
- keybinding、menu 和 command palette 通过统一 action id 触发。
- 旧 profile / preferences 配置仍可读取，新配置 schema 不引入 SSH、remote、
  serial、SFTP 顶层能力。
- shell integration 关闭时，相关本地效率动作正确降级为不可用。

### Phase 4: Linux / Windows Integration

前置验证门槛见
[T-065](tasks/verification-gates/T-065-phase4-windows-linux-validation-gate.md)。

目标：

- 在尽量不改 Flutter 业务层的前提下接入更多桌面平台。
- 验证 PTY 适配和构建链的跨平台可行性。

进入条件：

- `M5` 的目标机证据已经满足。
- macOS 主链路和 FFI 协议稳定。

完成条件：

- 至少新增一个平台可运行。
- 文档明确记录平台差异。
- 不破坏 macOS 现有能力。
