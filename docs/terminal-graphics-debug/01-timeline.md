# 时间线

## 1. 初始问题：terminal pets 不可用

用户最初看到终端提示：

```text
Pets aren't available in this terminal. Terminal pets need image support, and this terminal environment doesn't expose a supported image protocol.
```

第一层问题不是“图片画歪了”，而是 Codex 判断当前终端没有可用图片协议。用户先要求解释实现原理，随后要求“不考虑性价比，多方面重新考虑这个特性的实现方案”。

## 2. 目标升级：从 pet 补丁变成通用终端图片能力

用户给出《终端图片能力平台方案》，明确要求：

- terminal pets 只是第一个验收场景。
- 实现通用 terminal graphics，不做宠物专用补丁。
- Rust 负责协议解析、图片解码、图片资产和 placement 生命周期。
- Flutter 不再从 frame JSON 中拿图片 bytes，而是通过 FFI 懒加载 RGBA asset。
- 支持 Kitty graphics、Sixel、iTerm2 OSC 1337。
- 新增 `TerminalFrameDiff.graphics`，旧 `inline_images` 只做兼容读取。
- 默认开启直接内联图片数据，Kitty 文件路径和共享内存读取默认关闭。

## 3. 初次拉起：Codex 仍认为不支持图片

用户拉起应用后仍看到 pets 不可用提示，并说明进程已经退出后重新启动仍复现。

这个阶段暴露出：只实现渲染管线不够，还要让上层程序看到正确能力：

- Kitty query 响应。
- Sixel / XTSMGRAPHICS 查询能力。
- profile gating，例如仅对 `xterm_256` 类 profile 开启。
- 可选 `graphics.advertise=kitty` 兼容只看环境变量或能力标识的工具。

## 4. Kitty payload 泄漏和多 pet 叠加

后续截图显示屏幕中出现大量 `OKGi=49374`、base64 片段，并叠出很多 pet。

这说明图像协议序列没有被完整吞掉，或者 Kitty chunk、tmux passthrough、delete 和 placement replacement 没有按同一套状态机处理。

阶段性处理方向：

- 接通 Kitty APC parser。
- 处理 chunked transmit。
- 解包 tmux/screen passthrough。
- 将 asset 和 placement 分开，避免每次更新都创建新实例。

## 5. Codex input 背景问题

用户指出 Codex 启动后的 input 行应有灰色背景，但当前应用里看不到。用户提供 iTerm2 对照图，并明确指出：

```text
不要硬改光标所在行的背景色
```

这条约束很重要：input 背景属于文本样式渲染，不应该通过 graphics 或 app-specific 补丁解决。后续修复需要保持这一边界。

## 6. 默认背景色和 iTerm2 对照

用户要求改 default 背景方便观察，并多次给出“左边当前应用、右边 iTerm2”的对照截图。

这一阶段同时暴露：

- 背景色渲染和 iTerm2 有差异。
- pet 有时完全没画出来。
- pet 的位置和 iTerm2 不一致。
- 当前应用中 pet 的平滑度低于 iTerm2。

## 7. 透明背景乱码

用户截图显示 pet 周围有条纹和脏背景，并问“图片为什么会有背景乱码？”后续用户反馈“渲染正常了”。

这类问题更接近 RGBA 像素边界，不是 Kitty placement 坐标问题。当前实现中 `TerminalGraphicsCache` 有 RGBA premultiply 逻辑，用来符合 Flutter 解码期望。

## 8. 明显闪烁

用户反馈：

- iTerm2 中 pet 是顺滑变化。
- 当前应用中有明显闪烁。
- 刚启动 Codex 阶段特别明显。
- 稳定后仍有轻微闪烁。

用户一度要求用 computer-use 验证，随后表示不需要电脑自动验证，自己手动验证即可。

## 9. 录制和 frame diff 讨论

用户提供 `/Users/robinfai/tmp/demo.cast`，要求分析录制。随后用户问：

```text
有没有可能跟 frame diff 20-30帧刷新的这个事情有关？
```

阶段性结论：

- 20-30fps frame diff 会把 native 中间态采样出来，因此会放大闪烁。
- 但它不是根因。
- 如果 native 不输出短暂 `graphics=[]`，Flutter 不会因为帧率自己把图片删掉。

## 10. 当前最新状态：偶尔 3-5 秒消失近 1 秒

用户最新反馈：

```text
现在还是偶尔会3-5秒的间隔还是会消失接近1秒的样子。这是为什么？
```

当前主代理仍在修复。最新可见分析显示，问题还没有关闭：

- 现有单帧 clear-screen deferral 只能挡住一部分场景。
- replay 中仍出现过连续两个空图层 frame。
- replacement 后 `render_id` 从 `1` 变成 `100`，Flutter overlay key 因此变化，旧图会被销毁。
- 新 overlay 在 asset 加载和解码完成前 `_visibleImage == null`，于是用户看到 pet 消失。

