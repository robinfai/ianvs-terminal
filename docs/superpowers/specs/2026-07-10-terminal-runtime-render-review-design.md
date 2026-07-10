# Terminal Runtime 与渲染评审改进设计

## 背景与基线

本设计落实 `ianvs_terminal_codex_review_20260710.zip` 中的七个 Phase。目标代码基于
`main` 的 `4b19f04e1c2d43b4ed50200ea8e3ba809a44b30d`。首次门禁发现 Runner Release
配置误删 hardened runtime；该回归已用既有契约测试复现并在独立提交 `a81b140`
恢复。修复后，隔离 worktree 上的非 GUI 总门禁退出码为 0。

评审中以下事实已经由代码核对确认：

- runtime 使用 33ms polling，连续空刷新后最多跳过 48 个 tick；下一次完整拉取的
  名义最坏间隔是 `(48 + 1) × 33ms = 1617ms`。
- 纯 PTY 外部输出没有主动通知 Dart；输入、滚动和 resize 才会清退避。
- steady-state paint 会固定创建多个 `Paint`、List、Set，并遍历全部可见行。
- graphics cache 同步在每次 frame 通知时执行 `map().toSet()` 与 eviction scan。
- cursor blink 通过 viewport `setState` 触发整棵 surface 重建和主 RenderBox paint。
- runtime、viewport、render、models 文件仍承担多种职责；domain models 直接导入
  protobuf 生成代码。

“1.6 秒延迟一定会出现”“cursor overlay 一定更快”仍属于待测假设，不能直接作为
修复结论。

## 目标

- 用真实 PTY 和可追踪指标测量 idle output 的发现、请求、拉取、应用各段延迟。
- 把无 hint 的完整拉取 fallback 变成按单调时钟管理、名义上限约 396ms 的有界行为。
- 增加向后兼容的 native refresh hint，使 active idle 外部输出的名义发现时间不超过
  一个 33ms hint 周期，同时保留完整 polling fallback。
- 用纯 Dart refresh policy 表达 interactive、streaming、background、idle，并保持
  现有公开 API 和默认行为兼容。
- 降低 steady-state paint 固定分配，保留 debug getter 与 benchmark 可观测性。
- 仅在 graphics asset 集合变化时执行 cache eviction，同步语义覆盖新增、删除、版本
  变化、权威空列表和 cache/controller 替换。
- 用 profile A/B 证明 cursor overlay 的收益；只有收益明确且正确性门禁完整时才切换
  生产路径。
- 低风险拆出 frame pump、focus reporting、graphics sync 与 wire decoder 边界，不增加
  Widget 层级，不改变公共 terminal API。
- 保留 JSON compatibility path、protobuf/JSON final viewport hash parity、现有测试与
  benchmark gate。

## 非目标

- 不删除 JSON fallback，不变更 frame JSON/protobuf schema。
- 不引入新的状态管理框架，不做一次性 runtime/viewport/models 大重写。
- 不以宿主瞬时 CPU 数字作为普通 CI 的硬阈值。
- 不在没有数据前引入 tile cache、isolate decode 或全尺寸透明 cursor layer。
- 不把 SSH、跨平台、native renderer 等既有延期范围并入本轮。

## 方案比较

### 方案 A：一次性完成所有结构重写

优点是最终文件边界看起来最整齐；缺点是 refresh、transport、render、IME 与 cursor
同时变化，无法把性能收益归因，也很难定位 parity 回归。本轮不采用。

### 方案 B：只调退避参数并关闭部分 debug 收集

优点是改动最少；缺点是没有外部输出 hint、没有明确 refresh policy，graphics 与
transport 的结构问题仍存在。本轮只把参数收紧作为 Phase 1 的安全兜底，不把它当
最终方案。

### 方案 C：测量先行、逐 Phase 小步演进

每个 Phase 先写失败测试或基准，再做单一变更，跑聚焦验证与总门禁并独立提交。
实验达不到收益门槛时保留证据而不切生产路径。本轮采用此方案。

## 架构设计

### 1. Frame pump 与 idle 唤醒

`TerminalFramePumpBackoff` 改为由注入的单调时钟计算完整拉取 deadline，不再用剩余
tick 个数表达时间。无 hint 时，idle fallback 最大延迟设为约 396ms；事件循环恢复时
若 deadline 已过，下一次 tick 立即拉取。

Phase 2 新增可选能力 `PtySessionRefreshHintBackend`。Rust 只暴露非消费型 bitmask，
首版 bit 0 表示 `TerminalSession.dirty`。Dart 每 33ms 读取廉价 hint；hint ready 时无视
idle full-poll deadline并请求现有 throttled refresh。新 Dart 连接旧 dylib、第三方 fake
或不支持 hint 的 backend 时自动回到有界 full polling。

hint 只是提示，不能成为唯一真相。child exit、clock-driven graphics animation 和同步
输出超时仍依赖定期完整拉取，因此 false hint 不能无限延后 fallback。

刷新诊断使用独立 schema，至少记录：

- `empty_refresh_count`
- `backoff_skip_ticks`
- `refresh_class`
- `refresh_requested_micros`
- `refresh_started_micros`
- `frame_taken_micros`
- `frame_applied_micros`
- `hint_poll_count`
- `full_poll_count`

真实 PTY 用 FIFO/唯一 marker 控制输出时刻，条件轮询只负责观察；固定 sleep 只允许在
子进程制造 3～5 秒 idle 和测试总超时保护中出现。

### 2. 自适应 refresh policy

新增纯 Dart `TerminalRefreshPolicy`，输入为近期 input、连续 frame activity、session
active、alternate screen、mouse tracking 与 idle 时长，输出：

- `interactive`：近期输入或交互模式，目标 16～33ms。
- `streaming`：连续 frame activity，目标 33～66ms。
- `background`：非活动 session，目标 100～500ms。
- `idle`：33ms hint probe + 不超过约 396ms 的完整 fallback。

默认未知 session 按 active 处理，避免新版本降低现有交互刷新。session activation、
focus gain、input 和 resize 都必须清退避并重新评估 policy。分类只影响调度，不改变
frame decode、event 顺序或 cooldown 的互斥语义。

### 3. Paint 固定分配

`RenderTerminalViewport` 复用 canvas/background/span/selection/cursor/search Paint 和
scratch List/Set。debug collections 在 debug 模式继续完整维护；release 且无 benchmark
sink 时不构造只为调试服务的 row text、rebuilt row 和 resolved cell 集合。row cache
只在新 frame 或缓存结构变化时裁剪，cursor/selection/search repaint 不重复裁剪。

benchmark 增加 `rows_visited`、`picture_draw_count`、`row_cache_hits`、
`row_cache_misses` 与 `debug_collection_enabled`。`cursorVisible` setter 对相同值短路，
避免外层无关 rebuild 额外 `markNeedsPaint()`。

### 4. Graphics revision 与同步

`TerminalViewportController` 维护两种单调 revision：

- `graphicsAssetRevision`：去重后的 `(asset id, asset version)` 集合变化时增长，驱动
  cache eviction。
- `graphicsRevision`：有序 placement 的所有语义字段深比较后增长，供 overlay/UI 使用。

不使用现有简化 `terminalGraphicsSignature` 作为正确性判断。delta 中的 graphics 是
权威完整列表，空列表表示清除。初次挂载、controller/cache 替换必须强制同步；文字、
cursor 或 placement geometry-only 变化不得触发 asset eviction。

Phase 4 先在 viewport state 内用 controller/cache identity 与 asset revision 做私有同步，
直接消费 controller 缓存的 live asset key，避免每帧 `map().toSet()`；Phase 6 再把这段
已验证行为等价提取为纯对象 `TerminalGraphicsSync`，并复用 live-key scratch set。

### 5. Cursor overlay 实验

先扩展 profile harness，加入静态 40×120、显式 focus、无 frame 更新、至少 20 次 blink
的 `cursor_blink_idle_profile`。报告必须区分 repeated-frame 主 surface paint 与 cursor
layer paint，记录 build/raster/paint p50/p95、picture draw 和 row rebuild。

实验 overlay 使用紧贴 cursor rect 的独立 leaf render object/repaint boundary，位于主
surface 之后、正 z graphics 之前。blink 只通知 overlay；frame、font、colors、DPR 或
cursor config 变化时才重算 visual。切换生产路径的门槛是：

- 每次 blink 为 1 次 cursor overlay paint。
- 主 surface paint 为 0，row visual rebuild 为 0。
- block cursor 字符反色、CJK 宽单元格、smart contrast、scrollback hide、focus 生命周期、
  IME caret geometry 和 graphics 遮挡顺序测试全部通过。
- profile p95 有稳定收益，且新增 layer 内存与复杂度可控。

门槛不满足时，不启用生产 overlay；只提交 benchmark 能力与“无充分收益”的结论。

### 6. 低风险职责拆分

按依赖从少到多拆分：

1. `TerminalFramePumpController`：deadline、hint probe、policy state 与计数，不读 Widget。
2. `TerminalFocusReporter`：focus tracking 的 attach/detach/report 状态机。
3. `TerminalGraphicsSync`：asset revision 到 cache eviction 的同步。
4. `TerminalRefreshPolicy`：保持纯函数/纯状态对象。

本轮不强行抽完整 `TerminalImeCoordinator`。IME 当前与 FocusNode、TextInputConnection、
key state、selection 和 caret geometry 强耦合；若无法用现有测试在一次小提交中保持
行为，则只在最终报告记录边界与后续计划。拆分不增加 Widget 层级、不改 public API。

### 7. Transport/domain 解耦

新增 `lib/src/transport/`：

- `terminal_json_frame_decoder.dart`
- `terminal_protobuf_frame_decoder.dart`
- `terminal_frame_validation_limits.dart`
- `terminal_wire_compatibility.dart`

`TerminalFrameDecoder` 继续作为 runtime facade，并增加显式 JSON/protobuf 入口；runtime
不再直接做 backend 能力探测、wire 拉取和 protobuf factory 调用。生成代码只由
protobuf codec 理解。现有 `TerminalFrameDiff.fromJson` / `fromProtobufBytes` 已是公开
兼容入口，不能在小版本中删除；若移除 models 对生成代码的直接依赖会引入循环依赖或
破坏工厂 API，本轮允许把该工厂保留为明确标注的 compatibility seam，并在最终报告
记录 major 版本迁移方案。JSON 与 protobuf 共用 validation limits、枚举 fallback 与
可无损统一的归一化规则，corpus/parity 测试逐字段验证最终 frame 等价；只比较 viewport
hash 不足以证明 cursor、style、modes 与 graphics 等价。既有
`preserve_aspect_ratio` 是非 optional proto3 bool：Rust/prost 会省略真实 false，无法靠
Dart presence 区分 false 与缺失。本轮保留 JSON 缺失默认 true、protobuf 缺失默认 false
的旧兼容语义，paired fixture 显式提供该字段，并用独立 characterization 测试和文档记录
这个 schema migration 才能消除的默认值接缝。

## 错误处理与兼容

- refresh hint symbol 使用 optional lookup；缺失时不得导致 dylib load 失败。
- hint 读取错误作为 backend error event 记录，并回退 full polling。
- malformed JSON/protobuf 继续返回 null，不应用 stale/partial frame。
- unknown hint bits 忽略；已知 bit 含义固定。
- 所有 policy 定时器、session state 和 cache sync state 在 close/dispose 时移除。
- 每次修复只处理一个根因；同一问题连续三次假设失败时停止补丁叠加并复查架构。

## 验证策略

每个行为变更遵循红→绿→重构：先运行新增测试并确认按预期失败，再写最小实现；绿后
运行相关 package 全量测试。每个 Phase 提交前至少运行：

- 触达 Rust/FFI：`cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、
  `cargo test -- --test-threads=1`、`ianvs_pty` analyze/test。
- 触达 terminal：`flutter analyze --fatal-infos`、`flutter test`。
- 触达 example/profile：`flutter analyze --fatal-infos`、模块化 `flutter test`，以及相关
  macOS integration/profile 命令。
- 跨 FFI/runtime/viewport：`VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION=1
  ./tools/verify_flutter_terminal.sh`。

最终必须额外连续两次运行完整 `./tools/verify_flutter_terminal.sh`、真实 macOS PTY
acceptance、profile/correctness/hash parity，并使用电脑操作 release app 验收创建
session、输入、idle 异步输出、resize/focus/tab activation、cursor blink 与关闭流程。
电脑验收发现任何问题都使门禁失效：红测修复后重新连续跑两次总门禁、重建 Release，
再完整重复电脑验收。

## 提交与停止条件

preflight 修复、设计/计划和 Phase 1～7 分别独立提交。每个提交只包含该阶段的代码、
测试和证据；不顺手重构其他范围。

迭代停止需要同时满足：

- 自动化总门禁连续重跑无失败。
- JSON/protobuf correctness 与 final viewport hash parity 无回归。
- 真实 PTY idle wake、active/background/max-backoff 均有可量化证据。
- cursor 实验有明确“启用”或“无充分收益、不启用”结论。
- 电脑验收没有可复现的功能、交互或视觉问题。
- 最终两份 review 文档区分已确认问题、benchmark 推断和尚未验证假设，并列出每个
  Phase 的 commit SHA、执行命令与未执行原因。

## 需求确认

用户提供的 `REVIEW.md`、`TASKS.md`、`ACCEPTANCE.md` 和 `/goal` 已明确选定“先验证、
逐 Phase 修复、自动化与电脑双门禁、循环直至无问题”的方向。本设计只收紧实现边界，
不扩展产品范围。
