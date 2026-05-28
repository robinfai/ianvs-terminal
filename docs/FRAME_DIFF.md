# Frame Diff

这份文档说明当前 terminal frame diff 的工作方式、回退边界和收益。图中的字段与代码路径对应：

- Rust 端生成：`native/core/src/session.rs`
- Dart frame 模型与合并：`packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
- Runtime 拉取与派发：`packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- Flutter 行缓存渲染：`packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`

## 总览

![Frame Diff 原理与优势](assets/frame-diff/frame-diff-overview.png)

Frame diff 的核心原则是：全量 `snapshot` 作为安全基线，局部 `delta` 作为高频快路径。Rust 端只在确定可复用旧基线时发送变化行；Dart 端把变化合并进当前 viewport state；Flutter 渲染端复用行缓存，只重建脏行。

## 生命周期

![Frame Diff 生命周期](assets/frame-diff/frame-diff-lifecycle.png)

数据流从 PTY 输出开始。Rust core 解析字节流并记录 `TerminalDamage`，再和 `last_rows`、`CachedFrameMeta` 对比，生成 `TerminalFrameDiff` JSON。Dart runtime 通过 `takeFrameDiffJson()` 拉取 diff，解码后交给 `TerminalViewportController`；viewport state 再根据 `frame_kind` 选择 `applySnapshot` 或 `applyDelta`。

## Snapshot 和 Delta

![Snapshot vs Delta](assets/frame-diff/frame-diff-snapshot-vs-delta.png)

`snapshot` 用于建立或重建完整基线，适合首帧、resize、模式变化、metadata 不一致、清空 scrollback 等场景。`delta` 用于普通输出、滚屏、局部 repaint 等高频路径，只携带变化行、`dirty_ranges`、`viewport_row_shift` 和必要元数据。遇到不确定性时回退 `snapshot`，避免状态漂移。

## 收益

![Frame Diff 的收益](assets/frame-diff/frame-diff-benefits.png)

收益主要来自四处：

- 传输层：JSON 只携带变化行和必要元数据，减少序列化与传输开销。
- Runtime 层：Dart 端复用旧 frame，只按 `dirty_ranges`、`viewport_row_shift` 和 incoming rows 合并。
- Render 层：`RenderTerminalViewport` 复用 row visual cache，只重建脏行或 snapshot 全量重建。
- 正确性：`snapshot_fallback_reason` 把不确定情况导向全量同步，快路径不承担状态风险。
