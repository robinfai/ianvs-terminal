# Timeline and Evidence

## 复盘窗口

覆盖当前可见对话中与终端图片能力有关的完整过程：

- 用户看到 `Pets aren't available in this terminal...`，要求解释终端图片能力实现原理。
- 用户要求“不考虑性价比”，重新设计更完整的平台化方案。
- 用户给出《终端图片能力平台方案》，要求实现。
- 用户反复拉起应用并用截图反馈问题。
- 用户提供 iTerm2 对照截图和 `/Users/robinfai/tmp/demo.cast`。
- 最后围绕 “frame diff 20-30 帧刷新是否导致闪烁” 做深入排查和修复。

## 阶段 1: 从 pet 专用问题升级为通用终端图片能力

用户最初的问题是 terminal pets 不可用，终端提示需要 Kitty graphics 或 Sixel 支持。后续用户明确要求不要只做宠物专用补丁，而是实现通用终端图片能力。

可见需求：

- Rust 解析 Kitty graphics、Sixel、iTerm2 OSC 1337。
- `TerminalFrameDiff` 新增 `graphics` 字段。
- frame JSON 只传布局和资产引用，不塞图像 bytes。
- FFI 增加 asset meta 和 RGBA copy。
- Dart 增加 `TerminalGraphicPlacement`、`TerminalGraphicAssetKey`、`TerminalGraphicsCache`。
- Flutter 在 viewport 内按 z-index 绘制图像。
- 默认开启直接内联图片数据，文件路径和 shared memory 默认关闭。

技术结论：

- 目标从 “让 terminal pets 不报错” 转为 “ianvs_terminal 自己成为支持图片的终端”。
- 正确数据流是 Rust 负责协议和图片资产，Dart/Flutter 负责按稳定 frame 状态渲染。

## 阶段 2: 初次实现后 Codex 仍提示不可用

用户截图显示 Codex 启动后仍提示：

```text
Pets aren't available in this terminal. Terminal pets need image support...
```

信号：

- 仅有渲染能力还不够，host 应用需要看到正确能力宣告。
- Kitty 查询响应、Sixel/XTSMGRAPHICS、配置 `graphics.advertise` 和 profile gating 都会影响上层是否输出图片。

后续实现方向：

- 响应 Kitty 查询。
- 对 xterm256 类 profile 开启图形能力。
- 提供 `graphics.advertise=kitty` 兼容只看环境变量或终端能力的工具。

## 阶段 3: Kitty payload 泄漏和 pet 多实例

用户随后提供截图：屏幕上出现大量 `OKGi=49374` 和 base64 片段，同时叠出很多 pet。

信号：

- 图像协议字节没有被完全吞掉，或者 Kitty chunk/response/passthrough 处理不完整。
- placement/delete 语义没有稳定处理时，会出现多实例叠加。

阶段性修复方向：

- 补 Kitty APC parser。
- 处理 tmux/screen passthrough 包装。
- 处理 chunked transmit。
- 将 image asset 与 placement 区分，避免每次更新都变成新实例。

## 阶段 4: Codex input 背景和 iTerm2 对照

用户指出 Codex 启动后的 input 行有灰色背景，在当前应用中被吞掉，并提供 iTerm2 对照图。

信号：

- 图像层修复不能破坏文本背景色和输入行背景。
- 不能通过硬改光标所在行背景色来掩盖问题。
- 需要让文本层的 SGR/background 语义自然流到 Flutter 渲染。

用户明确要求：

```text
不要硬改光标所在行的背景色
```

这条约束应作为后续 UI 修复原则保留：图像修复不能引入针对 Codex input 的硬编码背景。

## 阶段 5: 透明通道背景乱码

用户截图显示 pet 四周有条纹和脏背景，并问“图片为什么会有背景乱码？”随后反馈“渲染正常了”。

信号：

- RGBA 像素直接交给 Flutter 解码时，如果 alpha 预乘处理不符合 Flutter 预期，透明区域可能污染背景。

当前代码证据：

- `packages/ianvs_terminal/lib/src/terminal/terminal_graphics_cache.dart` 中保留 RGBA premultiply 逻辑。

技术结论：

- 图片 asset cache 层需要在 decode 前处理 alpha premultiply。
- 这是 Dart/Flutter 图像解码边界的问题，不是 Kitty 协议语义问题。

## 阶段 6: pet 位置不稳定和重复启动偏移

用户反馈重复启动时图片展示位置不对，并继续用 iTerm2 对照。

信号：

- Kitty placement 的 cell 坐标、pixel offset、DPR 和 viewport row 映射必须统一由 Rust 输出。
- Dart 不能根据旧 frame 自行猜测图像位置。
- render identity 应稳定，不应因为 asset version 变化导致 overlay 被当作新实例。

阶段性审查曾指出：

- 无 `p=` 的 Kitty 图需要稳定默认 placement，而不是回退到内部 transient graphic id。
- 同一内容重复传输不应制造无意义 asset churn。
- scrollback 图像未来还需要更完整的裁剪和历史坐标模型。

## 阶段 7: 闪烁问题暴露

用户反馈：

- iTerm2 中 pet 是顺滑变化。
- 当前应用有明显闪烁。
- 刚启动 Codex 阶段尤其明显。
- 稳定后仍有轻微闪烁。

用户随后提供 `/Users/robinfai/tmp/demo.cast`，用于复现和分析。

关键发现：

- replay 统计曾捕获 `graphics=0` 的中间 frame。
- 两类主要空图层窗口：
  - Kitty quiet delete 后，Codex 菜单/启动文本刷新到达，但 replacement 图像还没完成。
  - `clear_screen` 后立即重传 pet，frame diff 采样到短暂空 graphics。

## 阶段 8: frame diff 20-30fps 讨论

用户问：

```text
有没有可能跟 frame diff 20-30帧刷新的这个事情有关？
```

结论：

- 有关，但它不是根因。
- 20-30fps 轮询会把 native 侧短暂 `graphics=[]` 的中间状态采样出来。
- 根因是 Rust/native 状态和 frame 边界不应产生“非意图删除”的空 graphics frame。

最终修复方向：

- Rust 在 Kitty transfer 进行中暂停 frame extraction。
- quiet delete 不因普通文本输出提交。
- clear-screen 后出现的单个空图层 frame 做事件级合并。
- Dart 不靠 250ms retention 或类似时间猜测遮挡闪烁。

## 最终状态

最终 replay 结果：

```text
frames=175
graphicFrames=173
emptyAfterGraphic=0
```

验证结果见 [05-verification-evidence.md](05-verification-evidence.md)。
