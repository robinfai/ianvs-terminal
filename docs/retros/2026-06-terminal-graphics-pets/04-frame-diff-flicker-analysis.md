# Frame Diff Flicker Analysis

## 问题

用户问 20-30fps 的 frame diff 是否会导致 terminal pets 闪烁。

答案：

- 会参与暴露问题。
- 不是根因。

frame diff 轮询会把 Rust/native 的中间状态采样成 frame。如果 native 状态在图像 replacement 期间短暂变成 `graphics=[]`，Flutter 会正确地不画图，于是用户看到 pet 消失一瞬间。

所以根因不在刷新频率，而在 Rust 不应输出这种中间空图层帧。

## 为什么 Dart 不能猜

在当前设计中，`TerminalFrameDiff.graphics` 是权威渲染列表：

- 有 placement：Flutter 画。
- 空列表：Flutter 不画。

如果 Dart 遇到 `graphics=[]` 后自行保留旧图，就会混淆两种不同语义：

- 真删除。
- replacement 中间态。

因此不应使用“保留 250ms”之类时间窗口修复协议中间态。正确做法是 Rust 在输出 frame 前保证 graphics 已经稳定。

## 根因 1: Kitty quiet delete 与文本刷新

terminal pets 更新时可能出现：

```text
old graphic visible
Kitty quiet delete q=2
Codex menu/startup text refresh
replacement transfer
new graphic visible
```

如果 quiet delete 在文本刷新时被提交，Rust 会输出：

```text
graphics=[old]
graphics=[]
graphics=[new]
```

用户看到闪烁。

修复后：

- quiet delete 进入 deferred 状态。
- 普通文本刷新不提交 deferred quiet delete。
- replacement 或明确 graphic operation 负责解决 pending delete。

结果应该是：

```text
graphics=[old]
graphics=[old]
graphics=[new]
```

## 根因 2: Clear screen 与 pet 立即重传

Codex 启动阶段可能出现：

```text
old graphic visible
clear screen
pet retransmit
new graphic visible
```

clear screen 会触发 snapshot fallback。如果 frame extraction 恰好在 retransmit 前发生，会输出：

```text
frame_kind=snapshot
snapshot_fallback_reason=clear_screen
graphics=[]
```

这是录制中剩余的明显空图层窗口。

修复后：

- 仅在上一帧有 graphics、当前是 `clear_screen` fallback、当前 placements 为 0 时触发。
- 同一 damage generation 只 deferral 一次。
- 下一次 extraction 如果仍无图，则允许输出空图，避免真实 clear 被永久吞掉。

这不是猜时间，而是基于 frame work 和 damage generation 的事件级合并。

## 根因 3: Incomplete transfer 中间态

Kitty multi-chunk transfer 在最后 chunk 到达前，不能构造完整图片。

修复原则：

```text
kitty_graphics_transfer_in_progress() == true
  -> take_frame_diff returns None and keeps dirty
```

这样 Dart 不会收到半成品状态。

## 最终输出性质

修复后 Rust 应只输出三种稳定事实：

1. 旧图仍然有效。
2. 新图已经完成并替换旧图。
3. 协议确认图像被删除。

不输出：

- quiet delete 和 replacement 之间的空图。
- multi-chunk transfer 中间态。
- clear screen 与紧随 pet replacement 之间的单帧空图。

## 关键代码

- `native/core/src/session.rs`
  - `take_frame_diff`
  - `should_defer_clear_graphics_frame`
- `native/vendor/par-term-emu-core-rust/src/terminal/graphics.rs`
  - `kitty_graphics_transfer_in_progress`
  - `commit_deferred_kitty_deletes_for_visual_output`
- `native/vendor/par-term-emu-core-rust/src/graphics/mod.rs`
  - `KittyDeferredDelete`
  - `delete_kitty_graphics`
  - `commit_deferred_kitty_deletes_preserving_replacement`

## 验证指标

replay `/Users/robinfai/tmp/demo.cast` 的关键指标：

```text
frames=175
graphicFrames=173
emptyAfterGraphic=0
```

`emptyAfterGraphic=0` 是本次修复的核心验收信号。
