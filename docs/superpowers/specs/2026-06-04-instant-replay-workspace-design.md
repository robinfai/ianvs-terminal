# Instant Replay 工作区设计

## 背景

当前 Instant Replay 是轻量文本帧回放：`InstantReplayStore` 从 `TerminalFrameDiff` 提取文本，底部面板用滑条切换文本帧，支持复制和清空。

这版要重设边界。用户明确不想继续做文本回放，而是要在真实终端组件里回放历史画面，并且可以按历史记录里的终端尺寸来适配渲染效果。

仓库里已有可复用基础：

- Flutter 侧有 `TerminalViewport`、`TerminalViewportController`、`SelectionController` 和 `TerminalInputController`。
- `TerminalFrameDiff` 已包含 rows、cursor、viewport rows/cols、scrollback、modes、hyperlinks、inline images 等渲染信息。
- runtime 已有 resize 事件和 `resizeWindowBy` 通道，可以按 cols/rows、cell size、viewport size 推导窗口尺寸变化。
- native vendor 文档里已有 cell-level Instant Replay 概念：snapshot、delta input、timeline seek、timestamp seek。

## 目标

- 把 Instant Replay 做成独立 Replay 工作区，而不是底部文本 sheet。
- Replay 主画面必须使用真实 `TerminalViewport` 渲染历史帧。
- Live terminal 不被替换；Replay 退出后回到原 session/pane。
- Replay 默认不改变应用窗口大小。
- 当历史帧尺寸和当前窗口不一致时，显示历史尺寸，并提供明确的 `Fit recorded size` 操作；有窗口记录时按窗口记录适配，没有窗口记录时按终端视口尺寸推导。
- 支持时间线拖动、前后跳帧、播放/暂停、按时间点定位。
- 支持在 replay 历史里搜索，并把结果高亮到真实终端视口。
- 支持复制可见内容和复制选区。
- 清空 replay 历史必须保留当前 live session，不影响 shell 运行。

## 非目标

- 不把这版做成完整诊断导出工具。
- 不在 replay 里向 PTY 写输入。
- 不默认自动 resize 用户窗口。
- 不承诺永久保存 replay 历史。
- 不把 replay 历史跨 session 合并成全局录像库。
- 不在第一版支持任意外部录制文件导入。

## 设计方向

采用“独立 Replay 工作区 + 来源感”的结构。

用户从当前 session/pane 打开 Instant Replay 后，进入一个专用 Replay 工作区。顶部显示来源，例如 `Replay from: main / zsh / pane 1`。主区域渲染历史终端画面，右侧放时间线、搜索、帧信息和动作。退出后回到原来的 live pane。

不采用“当前 pane 原地切 Replay 模式”，因为 live terminal 和 replay terminal 的输入、焦点、窗口尺寸、复制和快捷键容易混在一起。独立工作区更适合真实回看，也更不容易误操作。

## 主界面

### 顶栏

顶栏内容：

- `Replay mode`
- 来源 session/pane 名称
- 当前历史帧时间
- 当前历史尺寸，例如 `Recorded at 120x36`
- `Fit recorded size`
- `Exit replay`

`Fit recorded size` 只有在历史 cols/rows 和当前可用渲染尺寸不一致时突出显示。点击后按当前 cell size 推导窗口 delta，再走现有窗口 resize 通道。操作完成后保留 replay 当前位置。

如果 replay 记录里有当时的应用窗口内容尺寸或窗口 frame，`Fit recorded size` 优先使用窗口记录。没有完整窗口记录时，再用 `viewportCols * cellWidth` 和 `viewportRows * cellHeight` 推导目标终端视口大小。

### 终端回放区域

中间主区域是只读 `TerminalViewport`：

- 使用 replay 专用 `TerminalViewportController`。
- 使用 replay 专用 `SelectionController`。
- 使用禁用写入的 `TerminalInputController` 或只读输入适配器。
- 允许鼠标选择、复制、链接打开和搜索高亮。
- 不允许向 live PTY 发送键盘输入。

视口按历史 frame 的 `viewportRows` 和 `viewportCols` 渲染。当前容器不足时，优先保持真实行列比例并出现滚动或缩放提示；不静默裁掉内容。

### 右侧面板

右侧面板包含四块：

1. 时间线
   - 拖动定位到历史点。
   - `Back` / `Forward` 按帧或按记录点移动。
   - `Play` / `Pause` 按记录时间播放，必要时可做速度限制。
2. 搜索
   - 输入 query 后搜索 replay 历史。
   - 结果显示数量，例如 `3 matches across 42 frames`。
   - 选择结果后跳到对应帧，并在 `TerminalViewport` 中高亮。
3. 帧信息
   - 时间戳。
   - cols/rows。
   - primary/alternate screen。
   - cursor visible 状态。
   - frame 是否来自 snapshot 或 reconstructed frame。
4. 动作
   - `Copy visible`
   - `Copy selection`
   - `Clear history`

## 交互规则

### 打开 Replay

从 command menu、Toolbelt 或快捷键打开时：

1. 冻结当前 session 的 replay timeline。
2. 进入 Replay 工作区。
3. 默认定位到最新历史帧。
4. 保留原 live session 继续运行，不向 replay viewport 写入新 live frame。

如果没有 replay 历史，显示空状态：

```text
No replay frames captured yet.
Run some terminal output, then open Instant Replay again.
```

### 退出 Replay

点击 `Exit replay`、按 Escape，或关闭工作区时：

- 销毁 replay 专用 controller。
- 回到来源 pane。
- 不改变 live session 的 frame、selection、scrollback 或 input focus。

### 播放

播放只推进 replay timeline，不影响 live terminal。

规则：

- 默认从当前位置向后播放。
- 到达末尾后停在最新帧。
- 用户拖动时间线、搜索跳转或手动前后移动时暂停播放。
- 如果重建帧耗时过高，播放可以降采样，但 seek 到的最终帧必须准确。

### 搜索

搜索基于 replay timeline 的文本索引，但结果必须落到真实终端视口：

- 搜索可以先用每帧可见文本建立轻量索引。
- 点击结果时重建对应 frame。
- 高亮使用现有 `TerminalViewport.searchMatches` 能力。
- 搜索空状态用明确文案：`No matches in replay history.`

### 尺寸适配

Replay 打开时不改窗口大小。

当历史帧尺寸和当前渲染空间不一致时：

- 顶栏显示历史尺寸。
- 终端区域显示轻量提示：`Recorded at 120x36. Current view is 100x30.`
- 用户点击 `Fit recorded size` 后才请求窗口调整。

尺寸调整算法：

1. 读取 replay frame 的 `viewportCols` 和 `viewportRows`。
2. 如果 replay metadata 有 recorded window/content size，优先用它作为目标。
3. 如果没有窗口记录，读取当前测量到的 cell size，计算目标终端内容宽高。
4. 与当前 terminal viewport 或窗口内容逻辑尺寸做差。
5. 通过现有 `resizeWindowBy` 或等价 app bridge 调整窗口。
6. 调整后重新布局 replay workspace，但不改变 replay timeline 位置。

如果平台不支持窗口 resize，按钮禁用并说明：

```text
Window resizing is unavailable on this platform.
```

### 清空历史

`Clear history` 只清空当前 session 的 replay 历史。

清空后：

- Replay 工作区进入空状态。
- Live session 继续运行。
- 不清除 terminal scrollback。
- 不关闭来源 pane。

## 数据和架构

### Replay 数据模型

新增 replay 数据应从文本帧升级为 terminal frame / reconstructed frame 结构：

- `sessionId`
- `capturedAt`
- `viewportRows`
- `viewportCols`
- `viewportLogicalSize`
- `viewportPixelSize`
- `devicePixelRatio`
- `windowContentSize` 或 `windowFrameSize`，如果平台能记录
- `frameKind`
- normalized `currentFrame`，由 snapshot frame 或 native replay handle 重建得出
- `screenKind`
- `estimatedSizeBytes`

实施可以分阶段，但不回到文本回放。最低可接受形态是 Dart 层保存 `TerminalFrameDiff` snapshot ring buffer，并由真实 `TerminalViewport` 渲染历史 frame。完整形态接 native `ReplaySession`，用 snapshot + input delta 重建任意时间点。

### Replay controller

新增 `InstantReplayController`，负责：

- 冻结 session timeline。
- 管理 active index / active timestamp。
- 提供 play / pause / seek / step。
- 输出当前 `TerminalFrameDiff` 给 replay `TerminalViewportController`。
- 提供 search index 和 search result。
- 暴露 clear 操作。

### Live 与 Replay 隔离

Replay 必须使用独立 controller：

- live `TerminalViewportController` 不复用。
- live `SelectionController` 不复用。
- live input controller 不复用。
- replay key handling 明确拦截写入型输入。

这样可以保证用户在 replay 里按键不会写入 shell。

### Native 接入路径

最终形态应从 native core 暴露 replay session 能力到 Dart：

- enable/disable replay capture
- begin replay session
- replay total entries / duration
- seek to timestamp / index
- step forward / backward
- current frame as `TerminalFrameDiff`
- frame metadata
- clear session replay history

如果 native API 暂时不完整，可以先用 runtime 已收到的 `TerminalFrameDiff` 维护 ring buffer，完成 UI 和交互闭环；但产品文案和代码命名必须说明这是 frame replay，不声称已经具备完整 native timeline replay。

## 状态

### Loading

打开 Replay 后如果 timeline 需要冻结或 native session 需要初始化，显示：

```text
Preparing replay...
```

### Empty

没有历史：

```text
No replay frames captured yet.
```

### Unsupported

底层 replay 能力不可用：

```text
Instant Replay is unavailable for this session.
```

### Reconstruction failed

某个时间点重建失败：

```text
This frame could not be reconstructed. Try a nearby point in the timeline.
```

### Resize unavailable

平台或窗口 bridge 不支持：

```text
Window resizing is unavailable on this platform.
```

## 可访问性和键盘

- Replay 工作区打开时设置 route semantics：`Instant Replay workspace`。
- `Exit replay` 是明确按钮，也支持 Escape。
- 时间线可键盘左右移动。
- 播放按钮有清楚的 pressed/paused 状态。
- 搜索输入拿到焦点时，普通文字输入只进入搜索，不进入 terminal。
- Terminal replay 区域可选择文本，但不接受写入型 key event。
- 所有按钮使用现有 theme tokens，不硬编码颜色。

## 测试策略

### Unit tests

- replay timeline seek clamps 到有效范围。
- play 到末尾后停止。
- search result 能映射到 frame index 和 row/column range。
- clear 只清当前 session replay history。
- recorded window size 优先于行列推导。
- recorded size delta 计算正确。

### Widget tests

- 打开 Instant Replay 进入独立 workspace。
- Replay workspace 显示来源 session/pane 和历史尺寸。
- Replay `TerminalViewport` 渲染历史 frame，而不是文本预览框。
- replay 输入不会写入 fake PTY。
- 搜索跳转会更新 viewport frame 并显示高亮。
- `Fit recorded size` 触发 resize callback，但打开 replay 默认不触发。
- `Exit replay` 回到来源 pane。
- 空状态和 unsupported 状态文案正确。

### Integration / manual checks

- 在真实 macOS app 中打开 replay，不改变 live shell。
- 清屏后可以回看清屏前画面。
- 历史尺寸不一致时，默认不改窗口。
- 点击 `Fit recorded size` 后窗口尺寸向记录尺寸靠拢。
- 退出 replay 后当前 shell 可以继续输入。

## 验收标准

- Instant Replay 不再展示旧的文本滑条 sheet。
- Replay 打开后是独立工作区。
- 主画面由真实终端组件渲染历史状态。
- 默认不调整窗口大小。
- `Fit recorded size` 是显式操作，并且只在用户点击后执行。
- Replay 模式不能向 live PTY 写入输入。
- 搜索、跳帧、播放、复制和清空都有清楚状态。
- 退出 replay 后 live terminal 状态保持稳定。
