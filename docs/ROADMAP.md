# ianvs terminal Roadmap

这份文档定义当前执行顺序和长期方向。具体实现、验收记录和历史结果必须落到
`docs/tasks/`；路线图只负责说明先后关系、进入条件和完成条件。

本地 terminal 功能扩展的竞品分析与功能设计见
[LOCAL_TERMINAL_FEATURE_PLAN.md](LOCAL_TERMINAL_FEATURE_PLAN.md)。

## 当前执行口径

2026-07-23 完成兼容性基线、Recording / Replay、Frame Pipeline Iteration 02
以及 Terminal scope convergence 后，当前继续 **`runtime-contract-stability`**。
产品边界以 Terminal Layout、最小 Relaunch Spec、Recording Library 和
Open Terminal at Folder 为准。权威说明和机器可读
证据见：

- [CURRENT_EXECUTION_TARGET.md](CURRENT_EXECUTION_TARGET.md)
- [CURRENT_EXECUTION_TARGETS.json](CURRENT_EXECUTION_TARGETS.json)
- [T-298](tasks/verification-gates/T-298-current-execution-target-contract.md)
- [T-302](tasks/verification-gates/T-302-compatibility-baseline.md)：当前六层兼容性基线、真实 PTY/TUI 与 Resize Replay 证据
- [T-303](tasks/verification-gates/T-303-vttest-gui-gate-determinism.md)：真实 macOS GUI + PTY + `vttest` 补充门禁已通过
- [T-304](tasks/runtime-pty/T-304-frame-pipeline-damage-extraction.md)：Frame golden 加固与 cache/damage 首次模块抽取
- [T-305](tasks/runtime-pty/T-305-frame-build-context-snapshot-extraction.md)：共同构建上下文与 Snapshot Builder 抽取
- [T-306](tasks/runtime-pty/T-306-frame-delta-builder-extraction.md)：Delta Builder 与独立候选行回归抽取
- [T-307](tasks/runtime-pty/T-307-frame-display-projection-extraction.md)：Display Projection 与 source/display 映射抽取
- [T-308](tasks/runtime-pty/T-308-frame-graphics-projection-extraction.md)：Graphics Projection、viewport 几何与资产快照收集抽取
- [T-309](tasks/runtime-pty/T-309-recording-event-format-v1.md)：已关闭；版本化 Recording Metadata/Event、确定性 codec 与输入隐私契约
- [T-310](tasks/runtime-pty/T-310-live-recording-seam.md)：已关闭；有界 native raw PTY capture、live recorder 与结构化 overflow
- [T-311](tasks/runtime-pty/T-311-replay-backend.md)：已关闭；无子进程 ReplayBackend、实时/无延迟调度与副作用隔离
- [T-312](tasks/shell-product/T-312-versioned-local-workspace-schema.md)：已关闭；Workspace schema v1、旧格式迁移与未来版本保护
- [T-313](tasks/shell-product/T-313-local-workspace-session-restore.md)：已关闭；真实 SessionController 重启恢复、自动持久化与可见失败处理
- [T-314](tasks/shell-product/T-314-versioned-session-descriptor.md)：已关闭；Session Descriptor v1、Workspace schema v2 迁移与真实命令重启接线
- [T-315](tasks/shell-product/T-315-project-workspace-identity-and-recent-index.md)：已关闭；Workspace schema v3、稳定 project identity、多 Workspace 文件集合与 Recent index v1
- [T-316](tasks/shell-product/T-316-project-workspace-switcher.md)：已关闭；原生项目选择、Recent Workspace 菜单与失败安全的运行时切换
- [T-317](tasks/shell-product/T-317-session-recording-lifecycle-and-workspace-association.md)：已关闭；脱敏录制生命周期、原子落盘、失败重试与 Workspace Session Descriptor 关联
- [T-318](tasks/runtime-pty/T-318-versioned-runtime-capability-query.md)：已关闭；Runtime Capabilities v1、可选 FFI 查询与旧动态库回退
- [T-319](tasks/runtime-pty/T-319-runtime-event-envelope-v1-and-dual-stack.md)：已关闭；Runtime Event Envelope v1、序号/丢失检测与旧事件数组回退
- [T-320](tasks/runtime-pty/T-320-session-config-v1-and-profile-wire-migration.md)：已关闭；产品中立 SessionConfig v1、live/replay 可选 FFI 与旧 Profile wire 双向回退
- [T-321](tasks/runtime-pty/T-321-session-request-response-v1-and-dual-stack.md)：已关闭；有关联 identity 的 Session Request/Response v1、结构化错误与旧 request wire 双栈
- [T-322](tasks/runtime-pty/T-322-host-request-response-v1-clipboard-read.md)：已关闭；Host Request/Response v1、OSC 52 文本读取首个双向切片与旧事件/直接回复双栈
- [T-323](tasks/runtime-pty/T-323-diagnostic-event-v1-and-dual-stack.md)：已关闭；Frame/Session Diagnostic Event v1、关联序号与旧 debug-stat FFI 双栈
- [T-324](tasks/runtime-pty/T-324-terminal-frame-packet-v1-and-dual-stack.md)：已关闭；Terminal Frame Packet v1、序号确认/快照重同步与旧 Protobuf/JSON 双栈
- [T-325](tasks/runtime-pty/T-325-replay-speed-control.md)：已关闭；Realtime Replay 0.25x–4x 有界速度与绝对时间轴调度
- [T-326](tasks/runtime-pty/T-326-replay-frame-hash-comparison.md)：已关闭；有界 applied-viewport Frame hash 比较与首个差异定位
- [T-327](tasks/runtime-pty/T-327-replay-checkpoint-contract-v1.md)：已关闭；Recording v2 checkpoint marker、安全 parser 边界与有界 native snapshot materialization
- [T-328](tasks/runtime-pty/T-328-replay-checkpoint-seek.md)：已关闭；基于已物化 checkpoint 的确定性 seek、Event cursor 协调与 realtime 重新调度
- [T-329](tasks/runtime-pty/T-329-replay-graphic-asset-bundle.md)：已关闭；Recording v2 内容寻址 RGBA asset bundle、有界校验与 ReplayBackend native fallback
- [T-330](tasks/runtime-pty/T-330-graphic-asset-packet-v1-and-dual-stack.md)：已关闭；原子 Graphic Asset Packet v1、精确 identity/RGBA 校验与旧 meta/copy 双栈
- [T-331](tasks/shell-product/T-331-terminal-scope-convergence.md)：已关闭；Project Workspace 收敛为 Terminal Layout、最小 Relaunch Spec、独立 Recording Library 与 Open Terminal at Folder

T-312 到 T-317 保留为历史实现记录；其中 Project Workspace、Recent Workspace、
Session Descriptor 录制关联等当前产品声明由 T-331 取代。

当前执行顺序：

1. Frame Pipeline Iteration 02 已通过最终 `make verify` 关闭；golden、schema parity
   和六组 benchmark correctness hash 均保持不变。
2. Recording Metadata/Event v1 格式已由 T-309 关闭；raw PTY output、input、resize、
   exit 的有界 live recorder seam 已由 T-310 通过最终全仓门禁关闭。
3. ReplayBackend 已由 T-311 通过最终 `make verify` 关闭，支持无延迟确定性测试和
   1x 实时调度；Iteration 03 完成。T-325 已以独立后续切片增加 0.25x–4x 速度控制，
   T-326 再增加有界 applied-viewport Frame hash 比较与首个差异定位。T-327 已增加
   Recording v2 checkpoint marker 与安全、有界的 native snapshot materialization。T-328 已在
   其上关闭确定性 backend seek；T-329 再增加有界、内容寻址的 decoded RGBA asset bundle，
   ReplayBackend 对精确录制 identity 优先并保留 native fallback。这些切片不同时引入 pause、
   scrubber、Replay UI 或 live asset capture 产品接线。现有 viewport
   `InstantReplayStore` 仍不等于
   raw session replay。
4. 每轮使用 focused regression 和 `make verify` 形成新鲜证据；不同时扩张 Host
   Protocol、Frame Wire、live asset capture、remote、plugin 或 renderer。
5. T-331 已将旧 Local/Project Workspace 基线收敛为单一 Terminal Layout：恢复仍只
   创建新 PTY，Relaunch Spec 只含 profile/command/cwd；`Open Terminal at Folder`
   只新增 cwd 指向所选目录的 Session，不切换容器。新录制写入独立平面库，旧嵌套录制
   仍可发现。Workspace v1-v3、project index 与旧 `workspace` config 只读迁移且不删除。
   Project/Recent Workspace、IDE/project context、plugin/cloud/collaboration 不再是当前能力；
   SSH 保持延期扩展，并必须基于 Profile/Session 设计。
6. Runtime Contract 已由 T-318 增加只读、版本化 capability query，由 T-319 完成
   Event Batch/Envelope 的 identity、sequence、timestamp 和丢失检测，再由 T-320 将
   session create 主路径迁移到产品中立、带上限的 SessionConfig v1。T-321 再把通用
   Dart-to-native session command 主路径迁移到有关联 identity、带上限和结构化错误的
   Request/Response v1。T-322 再把首个真实 native-to-product 双向请求限定为 OSC 52
   `clipboard.read_text`，加入 Host Request/Response v1、精确一次消费和旧事件/直接回复双栈。
   T-323 再把 Frame/Session 运行指标迁移到有关联 identity、sequence 和 timestamp 的
   Diagnostic Event v1，保留旧 debug-stat FFI，并且不改诊断导出包。
   T-324 继续为现有 `terminal-frame-diff-v1` Protobuf 增加 session identity、sequence、
   timestamp 和确认漂移后的 Snapshot 重同步，不改变 Frame payload 或资产通道。
   T-330 再把 decoded RGBA 资产主路径迁移到有关联 identity、带 100 MiB 上限的原子
   Protobuf packet，同时保留旧 meta/copy symbols 和旧动态库回退。
   旧事件数组、Profile-shaped create symbols、旧 `{kind, ...payload}` request symbol、旧
   Frame Protobuf/JSON 和 debug-stat symbols 仍作为可验证的升级回退；其他 Host operation、
   asset 等 wire 的后续迁移必须
   分别立项并先补兼容测试。
7. Linux / Windows 仍由 T-065 的真实目标机证据驱动；Ubuntu CI 中的 package
   验证不能替代 desktop app 验收。

旧 M1-M5 仍保留在下文作为历史目标和依赖说明，但不再代表尚未启动的当前状态：

- M1 的审计自动化切片已经收口；当前 xterm 审计没有 `Gap` 行，未实现能力已明确
  标成 `Deferred`。
- M2 的 macOS 手工/性能证据已有历史记录，Windows、Android 和 fractional-DPR
  宿主证据仍是明确 blocker 或后续 smoke。
- M3 的 typed shell-hook、bash/fish 和 kitty keyboard 路径已经落地；T-064 的
  generic row-range annotation candidate API 没有按原设计实现，后续 block 能力走了
  `TerminalBlock` frame/viewport 路径。
- M4 已经实际展开到统一 action、split workspace、profiles、preferences、session
  restore 和本地持久化，当前需要收敛稳定性而不是再次“启动”。
- M5 仍未满足真实 Linux / Windows desktop host 证据门槛。

### 历史口径

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

下列 M1-M5 内容保留原始目标、范围和完成条件，供追溯与后续拆任务使用。

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

- 稳定的公共 runtime 接口包括
  [T-063](tasks/runtime-pty/T-063-shell-hook-typed-runtime-event-and-multi-shell-contract.md)
  落地的 `TerminalSessionShellHookEvent`，以及 T-318 的只读 Runtime Capabilities v1；
  capability query 只描述编译进 native core 的 wire surface，不等于产品或宿主已启用。
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

Data API 密钥轮换是独立的长期安全里程碑，当前 v1 明确不支持。进入实现前必须满足
[ADR-0004](DECISIONS/ADR-0004-data-api-key-lifecycle-v1.md) 的 old+new key 验证、
全量敏感资源事务性或可恢复重加密、并发写入隔离、失败回滚和版本化 KDF 兼容要求；
不得通过只替换 verifier 的方式伪装成轮换。

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
