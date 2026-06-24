# 实现记录

## 总体数据流

本轮方案的核心数据流是：

```text
PTY bytes
  -> Rust terminal parser
  -> GraphicsStore 管理 asset 和 placement
  -> TerminalFrameDiff.graphics 输出布局和资产引用
  -> Dart frame model 解析
  -> TerminalGraphicsCache 按 asset_id + asset_version 懒加载 RGBA
  -> Flutter viewport 绘制图片
```

这个方向是正确的：frame diff 不传大图片 bytes，只传稳定引用和布局。

## Rust / native 侧

当前已涉及的主要区域：

- `native/core/src/session.rs`
- `native/core/tests/session_test.rs`
- `native/vendor/par-term-emu-core-rust/src/graphics/mod.rs`
- `native/vendor/par-term-emu-core-rust/src/graphics/kitty.rs`
- `native/vendor/par-term-emu-core-rust/src/terminal/graphics.rs`
- `native/vendor/par-term-emu-core-rust/src/terminal/sequences/**`

主要职责：

- 识别是否启用 graphics。
- 设置 graphics 内存限制。
- 解析 Kitty / Sixel / iTerm2 序列。
- 管理 image asset 和 placement。
- 生成 `TerminalFrameDiff.graphics`。
- 缓存 asset snapshot，供 FFI 读取。
- 在 synchronized update 或 Kitty transfer 未完成时暂停 frame extraction。

## Frame diff 相关变化

`TerminalSession::take_frame_diff` 当前会：

- 在 `synchronized_updates()` 或 `kitty_graphics_transfer_in_progress()` 时返回 `None`，并保留 dirty。
- 生成 `graphics` placement 列表。
- 缓存当前可见 asset snapshot。
- 记录 frame debug stats，包括 active graphics、scrollback graphics 和 placement 数量。
- 通过 `should_defer_clear_graphics_frame` 对部分 clear-screen 空图层 frame 做一次延后。

当前已知不足：

- `should_defer_clear_graphics_frame` 只识别 `snapshot_fallback_reason == "clear_screen"`。
- 同一轮 clear 后如果又产生 `conflicting_scroll_regions` 等 fallback，仍可能输出空 `graphics`。
- 它只处理一次 damage generation，不足以覆盖 clear 后 replacement 到达前的多个中间 frame。

## GraphicsStore 相关变化

当前 `GraphicsStore` 已引入：

- `deferred_kitty_deletes`：延后处理 quiet delete，避免 replacement 前短暂删除。
- `cleared_kitty_placements`：clear 后记住之前的 Kitty placement，用于尝试复用 render identity。
- `matching_cleared_kitty_graphic_id`：在新 graphic 到达时尝试复用 clear 前的 id。

当前已知不足：

- `matching_cleared_kitty_graphic_id` 目前要求 `kitty_placement_id` 和 `position` 都一致。
- replay 中 replacement 可能同一个 Kitty placement id 但位置改变，例如 row/col 改了。
- 位置改变时 render id 没有复用，Flutter 会认为这是一个全新 overlay。
- `cleared_kitty_placements` 只是用于匹配 id，当前没有作为“过渡期仍可见 placement”输出给 frame。

## Dart / Flutter 侧

当前已涉及的主要区域：

- `packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_graphics_cache.dart`
- `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
- `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`
- `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`

主要职责：

- 解析 `TerminalFrameDiff.graphics`。
- 按 `asset_id + asset_version` 懒加载并缓存 `ui.Image`。
- 对 RGBA 做 premultiply，避免透明通道污染背景。
- 按 `row`、`col`、`width_cells`、`height_cells`、pixel offset 和 z-index 绘制。

当前关键行为：

- `_TerminalGraphicOverlay` 的 key 是 `terminal-graphic-${graphic.renderId}`。
- 同一个 render id 更新 asset 时，旧 `_visibleImage` 可以留到新图片加载完成。
- render id 变化时，旧 overlay state 被 dispose，旧 `_visibleImage` 被清空。
- 新 overlay 在 `imageFor` 完成前会返回 `SizedBox.shrink()`，所以这段时间不画 pet。
- `_syncGraphicsCache` 会按当前 frame 的 live asset key 做 `evictExcept`，如果 Rust 输出空 `graphics`，旧 asset 可能被清理。

## 配置和能力宣告

本轮方案包含这些配置：

- `graphics.enabled`
- `graphics.advertise`
- `graphics.maxImageBytes`
- `graphics.maxTotalBytes`

长期边界：

- 默认支持直接内联图片。
- Kitty file/shared-memory medium 默认关闭。
- `vt220` 保持纯文本。
- 对 xterm256 类 profile 开启 graphics。

## 当前实现判断

整体分层方向是对的，但当前闪烁说明 frame 边界还没有完全稳定。特别是 clear-screen 与 pet replacement 之间，Rust 还可能把“中间状态”暴露给 Dart；同时 replacement 的 render identity 还不够稳定。

