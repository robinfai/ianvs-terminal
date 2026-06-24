# 当前闪烁分析

## 用户现象

最新现象是：

```text
偶尔会 3-5 秒的间隔消失接近 1 秒
```

这更像周期性更新链路里的状态空窗，而不是每帧绘制性能问题。

## 最可能的解释

terminal pet 会周期性更新图片或位置。更新过程可能包括：

```text
旧 pet 可见
  -> quiet delete 或 clear screen
  -> 中间文本刷新 / snapshot fallback
  -> replacement 图片传输和解码
  -> 新 pet 可见
```

如果 Rust 在中间输出了：

```json
"graphics": []
```

Flutter 会按照协议事实把 pet 移除。如果随后 replacement 的 `render_id` 又变了，旧 overlay 也无法作为新图片加载期间的显示保险。于是用户看到 pet 消失接近 1 秒。

## 为什么看起来是 3-5 秒一次

这是推断，不是最终结论。

3-5 秒的节奏很可能来自 terminal pets 自己的更新循环，或者 Codex 启动期/状态刷新期的图像重传节奏。只要每次更新都经历“删除或 clear -> replacement”的序列，而 native 又暴露了中间空图层，就会在同样的周期上闪烁。

## 为什么会接近 1 秒

这也是推断。

接近 1 秒说明空窗不只是 Flutter 下一帧没有画，而可能包含：

- PTY 输出分批到达。
- clear-screen snapshot 之后还有第二个 fallback frame。
- Kitty replacement 图片传输尚未完成。
- Dart 通过 FFI 加载 asset。
- Flutter 解码 `ui.Image`。
- render id 改变导致旧 overlay 不能继续显示旧图。

单个 30fps frame 大约只有几十毫秒，不会自然造成接近 1 秒的消失。接近 1 秒说明某个状态被提交并保持了多个 frame。

## 与 frame diff 20-30fps 的关系

frame diff 刷新频率是放大器，不是根因。

如果 native 状态是：

```text
graphics=[old]
graphics=[]
graphics=[new]
```

20-30fps 会把 `graphics=[]` 采样出来，用户就看到消失。

如果 native 状态是：

```text
graphics=[old]
graphics=[old]
graphics=[new]
```

同样的 frame diff 频率不会造成闪烁。

所以修复重点仍在 native 输出稳定 frame，而不是降低或提高 frame diff 频率。

## 当前已确认的高风险点

### 1. 单帧 deferral 覆盖不够

当前 `should_defer_clear_graphics_frame` 只对满足这些条件的 frame 延后一次：

- graphics enabled。
- 当前 placement 数为 0。
- fallback reason 是 `clear_screen`。
- 上一帧有 graphics。
- 同一 damage generation 尚未延后过。

最新 replay 线索显示，空窗可能是两个 frame：

```text
index 102: graphics=0, fallback=clear_screen
index 103: graphics=0, fallback=conflicting_scroll_regions
index 104: graphics=1, replacement
```

这说明只拦第一帧不够，第二帧仍可能被 Flutter 看见。

### 2. clear 后 replacement 位置变化导致 render id 变化

当前 `matching_cleared_kitty_graphic_id` 要求 clear 前后 position 一致。

但 replay 线索显示 replacement 可能换了 row/col：

```text
replacement after empty: render=100, asset=49374, row=20, col=217
```

如果 clear 前 render id 是 `1`，replacement 后变成 `100`，Flutter key 从：

```text
terminal-graphic-1
```

变成：

```text
terminal-graphic-100
```

这会销毁旧 overlay state。旧图不能继续显示，新图未加载完成前就是空。

### 3. 空 graphics 会触发缓存收缩

`terminal_viewport.dart` 中 `_syncGraphicsCache` 会用当前 frame 的 graphics asset keys 调用 `evictExcept`。

如果 Rust 输出空 `graphics`，Dart 看到 live keys 是空集合。这样旧 image cache 可能被清理，下一次 replacement 即使 asset id 相同，也要重新加载或重新解码。

### 4. clear screen 的协议语义和用户体验之间需要明确边界

Kitty 文档里 clear screen 会清理图片，这是协议语义。但 terminal pets 的动画更新会借助 clear/replacement 形成一个视觉动作。如果实现把中间 clear 立即暴露给 Flutter，用户体验就是闪烁。

因此需要在 Rust 侧判断“这是最终清图”还是“replacement 事务中的中间态”。这个判断不能靠固定 sleep，最好靠协议事件、pending transfer、pending replacement 和 frame work 状态。

## 当前不建议的修复

不建议用这些方法作为主修复：

- Dart 固定保留旧图 250ms 或 1s。
- 硬改光标所在行背景色。
- Flutter 看到空 `graphics` 就永远保留旧 pet。
- 降低 frame diff 频率来减少看到空窗的概率。

这些方法可能让现象短期变少，但会混淆真实删除、清屏、replacement 中间态，也可能引入新的视觉错误。

## 本轮最终修复

最终修复没有修改 Flutter 的时间策略，也没有硬改 Codex input 或光标所在行背景。

Rust 侧做了两件事：

1. ED 2/3 clear 后，把被清掉的 Kitty placement 暂存在 pending cleared 列表中。frame diff 在 replacement 到达前继续输出旧 placement 和旧 asset 引用，避免 Dart 收到 `graphics=[]`。
2. replacement 到达时，即使 row/col 已经变化，只要同一 Kitty placement 只有一个候选，就复用旧 `render_id`。这样 Flutter overlay key 不变，旧图可以一直显示到新 asset 加载完成。

修复后的 replay 指标：

```text
emptyAfterGraphic=0
uniqueRenderIds=[1]
framesAroundRenderChanges=[]
```

这说明 3-5 秒闪烁的直接原因已经从 frame diff 输出中消除。
