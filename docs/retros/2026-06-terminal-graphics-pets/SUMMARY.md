# Terminal Graphics and Pets Summary

## Final Outcome

本轮把 terminal pets 从“不支持图片协议”推进到通用 terminal graphics 平台，并修复了 Codex pet 在 ianvs terminal 中的主要闪烁问题。

阶段性关键指标：

```text
replay demo.cast: emptyAfterGraphic=0
cargo session_test: 104 passed
cargo lib tests: 30 passed
cargo vttest regression: 3 passed
flutter test packages/ianvs_terminal/test: 110 passed
flutter analyze: No issues found
flutter build macos --debug: success
```

2026-06-24 后续复核把退出清理纳入协议语义后，验收口径更新为：

```text
空 graphics frame 必须能对应 cast 中的显式 Kitty delete 或退出清理；
replacement、animation frame、普通文本刷新不能产生无协议依据的空 graphics frame。
```

当前同一份 `demo.cast` 使用 native debug dylib 回放：

```text
frames=171
graphicFrames=137
emptyAfterGraphic=32
uniqueRenderIds=[1,113,118,132]
assetIds=[49374,49375]
timedOut=false
seenExit=true
```

这些空图像输出对应 cast 中的 `a=d,d=I` 显式删除和 Codex shutdown 后的清理状态；动画帧和 replacement 区间没有无依据空图像。

## What Changed Conceptually

起点是 terminal pets 报错：

```text
Pets aren't available in this terminal. Terminal pets need image support...
```

最终方向不是宠物专用补丁，而是：

- Rust 解析 Kitty/Sixel/iTerm2 图片协议。
- Rust 管理 asset 和 placement 生命周期。
- FFI 暴露 RGBA asset meta/copy。
- `TerminalFrameDiff.graphics` 只传 placement 和 asset 引用。
- Dart 懒加载并缓存 `asset_id + asset_version`。
- Flutter 只负责按 Rust 的稳定 frame 状态绘制。

## Main Root Cause for Flicker

20-30fps frame diff 会把 native 中间态采样出来，但它不是根因。

真正的问题是 Rust 曾短暂输出非意图的 `graphics=[]`：

1. Kitty quiet delete 后，Codex 菜单或普通文本刷新到达，replacement 图像还没完成。
2. Codex clear screen 后立即重传 pet，frame extraction 采到空 graphics。
3. multi-chunk Kitty transfer 中间态不应被 frame diff 暴露。

正确修复层级是 Rust/native frame boundary，不是 Dart 延时保留。

## Main Fixes

- 不完整 Kitty transfer 或 synchronized update 期间，`take_frame_diff` 返回 `None` 并保留 dirty。
- quiet delete 不再因为普通文本输出提交。
- 显式 delete 会清理匹配 deferred delete，避免状态残留。
- clear screen 后若上一帧有图、当前为空图，只对同一 damage generation 做一次事件级 deferral。
- Dart/Flutter 保留正常 asset decode 双缓冲，但不猜 protocol lifecycle。
- Kitty `d=a`、默认 delete、按 cell/row/column/z-index 的 delete 统一进入 `GraphicsStore` 的 Kitty-only 删除逻辑，避免绕过 pending clear/deferred delete 状态，也避免误删 iTerm2/Sixel 图像。

## Key Evidence

Replay 录制：

```text
/Users/robinfai/tmp/demo.cast
```

最终 replay：

```text
frames=175
graphicFrames=173
emptyAfterGraphic=0
```

这证明录制场景中不再出现“有图之后突然输出空 graphics frame”的闪烁源。

## Subagent Inputs

本复盘启用了两个只读 subagent：

- 时间线/证据代理：整理 goal 之前和 goal 内的完整可见对话时间线、用户截图/录制信号、关键技术结论和最终验证证据。
- 流程改进/文档结构代理：整理有效流程、走弯路的点、文档目录建议、改进 backlog、agent-first maturity 评分和 next-session instructions。

主线程负责整合、落文档和链接项目入口，避免多个代理同时写文件造成结构分叉。

## User Feedback That Drove the Fix

- “还是这个错误”：说明 capability advertise/query 仍未让 Codex 输出图片。
- payload 和多 pet 截图：说明 Kitty 序列处理和 placement/delete 不完整。
- “codex input 的背景色也没改回来”：说明文本背景与图片层需要分开。
- iTerm2 对照截图：明确正确视觉行为。
- “图片为什么会有背景乱码”：定位到 RGBA premultiply。
- “不要硬改光标所在行的背景色”：形成 UI 修复边界。
- “有没有可能跟 frame diff 20-30帧刷新有关”：推动从 Flutter 观察回到 Rust frame 边界。

## Files in This Retrospective

- [README.md](README.md)：目录入口。
- [01-timeline-and-evidence.md](01-timeline-and-evidence.md)：完整时间线。
- [02-architecture-record.md](02-architecture-record.md)：架构记录。
- [03-debugging-log.md](03-debugging-log.md)：调试过程。
- [04-frame-diff-flicker-analysis.md](04-frame-diff-flicker-analysis.md)：闪烁根因分析。
- [05-verification-evidence.md](05-verification-evidence.md)：验证证据。
- [06-workflow-retro-and-followups.md](06-workflow-retro-and-followups.md)：流程改进和后续动作。

## Next Time

处理终端协议/渲染问题时，先做 replay 和分层定位：

```text
PTY bytes -> Rust parser/store -> TerminalFrameDiff -> Dart merge/cache -> Flutter render
```

不要先写 UI 层遮挡补丁。尤其不要用固定时间窗口掩盖协议中间态，也不要硬编码某个应用的背景色。
