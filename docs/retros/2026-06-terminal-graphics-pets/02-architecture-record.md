# Architecture Record

## 目标

本轮目标不是给 terminal pets 做专用补丁，而是让 `ianvs_terminal` 拥有通用终端图片能力。terminal pets 只是首个验收场景。

核心原则：

- Rust 负责协议解析、图片解码、资产存储、placement 生命周期和 frame 边界。
- FFI 只暴露资产元数据和 RGBA copy。
- Dart 负责 frame model、asset cache 和 bridge。
- Flutter 负责绘制，不猜协议状态。

## 数据流

```text
PTY bytes
  -> Rust terminal parser
  -> GraphicsStore asset + placement
  -> TerminalFrameDiff.graphics
  -> Dart TerminalGraphicPlacement
  -> TerminalGraphicsCache lazy asset load
  -> Flutter viewport overlay/render path
```

## Native 层职责

Native/Rust 侧负责：

- Kitty graphics APC parser。
- Sixel DCS 管线。
- iTerm2 OSC inline image 归一到 graphics store。
- tmux/screen passthrough 解包。
- asset 与 placement 分离。
- frame diff 生成。
- `graphics` placement 列表作为当前 viewport 的权威输出。
- 内存限制、decode error、diagnostics 和 frame debug stats。

关键代码区域：

- `native/vendor/par-term-emu-core-rust/src/terminal/graphics.rs`
- `native/vendor/par-term-emu-core-rust/src/graphics/mod.rs`
- `native/core/src/session.rs`

## FFI 边界

FFI 不把图片塞进 frame JSON。frame JSON 只传资产引用和 placement 几何信息。

资产通过二进制接口读取：

```text
ianvs_session_graphic_asset_meta(session_id, asset_id, asset_version, out_meta)
ianvs_session_graphic_asset_rgba_copy(session_id, asset_id, asset_version, dst, len)
```

这样做的原因：

- 避免大图片 bytes 反复 JSON encode/decode。
- asset 可以按 `asset_id + asset_version` 被 Dart 缓存。
- frame diff 仍然小而稳定。

## Dart 层职责

Dart 层新增或维护：

- `TerminalGraphicPlacement`
- `TerminalGraphicAssetKey`
- `TerminalGraphicsCache`
- `TerminalFrameDiff.graphics` 解析和合并
- `TerminalRuntimeController.loadGraphicAsset`

设计边界：

- `graphics=[]` 应被理解为 Rust 的权威删除或无图状态。
- Dart 不根据时间窗口猜“这可能只是短暂缺图”。
- Dart cache 可以保留 asset 解码结果，但不拥有 placement 生命周期。

## Flutter 渲染职责

Flutter 侧负责：

- 按 Rust 输出的 row/col、pixel offset、cell span 和 z-index 绘制图像。
- 支持透明度、DPR、scroll、clear、repaint。
- 在新 asset decode 完成前，允许同一 render identity 保留旧 `ui.Image`，避免 decode 空窗。

保留的安全渲染行为：

- 同一 image asset 的并发 load 去重。
- 同一 render identity 更新 asset version 时，旧图可作为 decode 期间的显示保险。

不应保留的协议猜测：

- 用固定时间保留消失的 placement。
- 用 Dart 自己推断 graphics scroll shift。
- 为某个 app 的 input 行硬编码背景色。

## 本轮重要状态机调整

### Kitty quiet delete

Kitty quiet delete `q=2` 是 terminal pets 更新过程中的关键路径。它可能先删除旧图，再传输新图。如果 Rust 在中间状态输出 `graphics=[]`，Flutter 会正确地把图删掉，于是用户看到闪烁。

本轮调整：

- quiet delete 进入 deferred 状态。
- 普通文本输出和 Codex 菜单刷新不再提交该 deferred delete。
- 后续 graphic operation 成功时再解析为替换或真实删除。

### Incomplete Kitty transfer

frame extraction 遇到未完成 Kitty transfer 时，不应输出 frame：

```rust
if state.terminal.synchronized_updates()
    || state.terminal.kitty_graphics_transfer_in_progress()
{
    self.dirty.store(true, Ordering::SeqCst);
    return Ok(None);
}
```

这避免了 Rust 把 multi-chunk transfer 的中间态暴露给 Dart。

### Clear-screen 空图层帧

Codex 启动阶段可能出现 clear screen 后立即重传 pet。短暂 `clear_screen + graphics=0` frame 会被 20-30fps diff 采样成闪烁。

本轮调整：

- 当上一帧有 graphics。
- 当前 frame 是 `clear_screen` fallback。
- 当前 graphics placement 数为 0。
- 同一 damage generation 尚未 deferral。

则 Rust 推迟这一次 frame extraction，让紧随其后的 pet replacement 合并进稳定 frame。

这是事件级合并，不是 sleep 或 timeout。

## 不变的长期边界

- `docs/FRAME_DIFF.md` 仍是 frame diff 机制的权威说明。
- 本文只记录本次 graphics 能力迭代的设计决策和排查结论。
- 后续若要稳定化为长期架构文档，应再补 `docs/TERMINAL_GRAPHICS.md` 或 ADR。
