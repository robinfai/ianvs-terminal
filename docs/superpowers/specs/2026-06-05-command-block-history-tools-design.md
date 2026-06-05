# Command Blocks 历史工具设计

## 背景

Instant Replay 已经从底部文本回放升级为独立 Replay 工作区。接下来要把相邻的历史能力重新收口：Command Timeline、复制上一条输出、失败快照、时间线标记、输出对比、会话线索和只读浏览模式。

本轮 Product Design 探索了三种方向：

- `History Rail`：右侧轻量历史工具栏。
- `Command Blocks`：把终端输出按命令分段，让每条命令可定位、可复制、可复盘。
- `Review Workspace`：独立只读复盘工作区。

最终方向选择 `Command Blocks` 作为主线，同时吸收 `History Rail` 的轻入口和概览能力，以及 `Review Workspace` 的深度复盘和只读隔离能力。

仓库里已有可复用基础：

- `ShellProductivityState` 已有 prompt marks、command output ranges、recent commands、recent directories 和 read-only 状态。
- `ShellProductivityProductionCallbacks` 已预留 `jumpToCommandBlock`、`copyLastCommandOutput`、`saveCommandOutput` 等操作。
- `InstantReplayStore` 已按 session 保存 terminal frame snapshot 和尺寸 metadata。
- `TerminalViewport`、`SelectionController` 和 `TerminalInputController` 已支持真实终端渲染、选区、复制和只读输入保护。
- 路线图里的 `T-064` row range annotation 设计正好可以承接命令块高亮、gutter 和状态标记。

## 目标

- 让用户在 live terminal 里直接看出“哪些输出属于哪条命令”。
- 每条命令都能执行常用历史动作：复制输出、打开回放、保存失败快照、对比重跑。
- 失败命令有清楚的局部呈现，不需要先打开完整 Replay 才能定位问题。
- 历史概览保持轻量，不把默认界面变成常驻侧边 dashboard。
- 深度 replay、diff 和 snapshot 继续进入独立只读 Review Workspace，不污染 live terminal 输入。
- 设计必须落在现有 Flutter / Material 3 / terminal runtime 架构上，不重写 renderer。

## 非目标

- 不把 PTY 输出改写成富文本文档。
- 不把所有输出都永久保存为日志库。
- 不做跨 session 的全局历史录像库。
- 不把命令块做成聊天式块编辑器。
- 不要求 shell integration 关闭时仍具备完整命令块能力；关闭时应优雅降级。
- 不在第一版实现复杂语义解析，例如自动理解所有测试框架的失败结构。

## 产品结构

采用三层结构：

```text
Command Blocks
  默认 live terminal 主体验
  每条命令以轻量 header / gutter / action row 呈现

History Peek
  从 History Rail 吸收的轻入口
  只在用户打开时显示历史概览和过滤

Review Workspace
  从 Review Workspace 吸收的深复盘
  由命令块动作进入，负责 replay、diff、长输出和完整 snapshot
```

默认用户停留在 live terminal。只有当用户明确打开 `History Peek` 或 `Open in Review` 时，才出现更重的历史界面。

## Command Blocks 交互

### 命令块构成

命令块不是插入到 PTY 内容里的真实文本，而是基于 absolute row range 的 overlay / annotation。

每个命令块包含：

- header：命令、cwd、开始时间、耗时、exit code。
- body：真实 `TerminalViewport` 渲染的原始输出。
- gutter：状态点、prompt mark、manual marker、失败标记。
- action row：只在 hover、focus 或选中命令块时显示。

header 默认要克制，不能抢终端内容：

```text
flutter test     ~/projects/app     23.47s     exit 1     14:12:03
```

状态规则：

- 成功：绿色状态点，header 不改变终端阅读节奏。
- 失败：红色状态点，header 和关键错误行轻微高亮。
- 运行中：脉冲状态点，耗时持续更新。
- 手动标记：gutter 显示 marker，不改变命令本身状态。
- 未知：灰色状态点，动作保留但失败相关动作隐藏。

### 快捷动作

命令块 action row 第一版包含：

- `Copy output`：复制当前命令输出范围。
- `Replay from here`：进入 Review Workspace，并定位到该命令附近的 replay frame。
- `Save failure snapshot`：保存该命令的失败快照；非失败命令显示为 `Save snapshot`。
- `Compare last run`：找同 cwd 下相同命令的上一条记录，进入 diff。
- `Mark`：给当前命令或当前输出行加手动标记。

动作显示规则：

- 鼠标 hover 命令块时显示。
- 键盘 focus 命令块时显示。
- 当前命令失败时，默认展开 `Copy output`、`Replay from here`、`Save failure snapshot` 三个动作。
- terminal 正在选择文本时，不弹出 action row 遮挡选区。

### 失败快照

失败命令完成后，底部出现一条轻量快照提示，而不是自动打开新界面。

快照内容：

- command
- cwd
- exit code
- duration
- failed at
- key error lines
- output range
- replay frame range

快照动作：

- `Copy output`
- `Open in Review`
- `Compare rerun`
- `Dismiss`

如果无法提取关键错误行，仍保存命令 metadata 和完整输出范围，并显示：

```text
No key error extracted. Full command output is still available.
```

### 只读浏览

`Read-only review` 可以在 live terminal 原位打开。

规则：

- 普通文字键不会写入 PTY。
- 复制、搜索、命令块跳转、marker、review 动作仍可用。
- 底部状态栏明确显示 `READ-ONLY REVIEW`。
- 退出只读浏览后恢复原 session input focus。

只读浏览适合快速检查当前输出；长时间回放和 diff 仍进入 Review Workspace。

## History Peek

History Peek 是从 `History Rail` 吸收的轻入口，不默认常驻。

入口：

- toolbar 小图标。
- command menu：`Open history peek`。
- 命令块 action row 的更多菜单。
- 底部状态栏历史状态点。

界面形态：

- 作为右侧 popover 或临时 side sheet。
- 宽度保持紧凑，避免挤压 terminal。
- 关闭后不改变 live terminal 状态。

内容：

- 过滤：`All`、`Failed`、`Marked`、`Recent`。
- 搜索命令文本和 cwd。
- 命令列表：时间、状态、命令、cwd、耗时、exit code。
- 细时间标尺：失败、marker、idle gap、replay frame。

History Peek 的目标是“快速找回刚才那条命令”，不是承担完整复盘。

## Review Workspace

Review Workspace 是从 `Review Workspace` 方向吸收的深复盘容器。

进入方式：

- `Replay from here`
- `Open in Review`
- `Compare last run`
- `View failure snapshot`
- Instant Replay 原有入口

打开规则：

1. 冻结来源 session 的相关历史范围。
2. 创建独立只读 review controller。
3. 默认定位到触发命令的输出范围或失败行。
4. live terminal 继续运行，不接收 review workspace 的写入型输入。

Review Workspace 需要支持：

- 左侧 command timeline。
- 中间真实 `TerminalViewport` 回放。
- 右侧 failure snapshot / command metadata / diff summary。
- 底部 replay timeline。
- 搜索 replay 历史并高亮真实 viewport。
- `Fit recorded size` 显式操作。

这部分应复用 Instant Replay 工作区设计，不重新发明第二套 replay 界面。

## 数据模型

新增命令块模型建议放在 productivity 层，作为 shell integration 和 terminal annotation 的中间表示。

```text
ShellCommandBlock
  id
  sessionId
  command
  cwd
  startedAt
  finishedAt?
  duration?
  exitCode?
  status
  promptMarkId?
  outputRange
  replayFrameRange?
  markers
  failureSnapshot?
```

```text
ShellCommandBlockRange
  commandRow
  outputStartRow
  outputEndRow?
  absoluteStartRow
  absoluteEndRow?
```

```text
ShellFailureSnapshot
  commandBlockId
  capturedAt
  command
  cwd
  exitCode
  duration
  keyErrorLines
  outputRange
  replayFrameRange?
```

```text
ShellHistoryMarker
  id
  commandBlockId?
  row
  createdAt
  label?
  kind: manual | failure | idleGap | replayFrame
```

命令块状态：

```text
running | succeeded | failed | unknown
```

### 数据来源

优先级：

1. shell integration typed event。
2. prompt marks + recent command / cwd。
3. command output ranges。
4. replay frame timestamp 和 frame text。
5. fallback prompt mark，只作为降级展示，不声称准确命令块。

如果 shell integration 关闭：

- 不显示完整命令块 header。
- 保留搜索、复制选区、Instant Replay。
- command block 相关 action 在 command menu 中显示 disabled reason。

## 架构设计

### Controller 边界

新增 `ShellCommandBlockController`：

- 消费 shell integration events、prompt marks、command output ranges。
- 维护当前 session 的 `ShellCommandBlock` 列表。
- 计算当前 viewport 内可见命令块。
- 输出 annotation view model 给 terminal surface。
- 提供 `copyOutput`、`saveSnapshot`、`mark`、`compareLastRun` 的输入数据。

新增 `ShellHistoryPeekController`：

- 从 `ShellCommandBlockController` 读取当前 session 历史。
- 处理搜索、过滤、选中、跳转。
- 不持有 terminal viewport controller。

复用 / 扩展 `InstantReplayController`：

- 支持从 command block id 或 row range 打开 review。
- 支持根据 command block 定位 replay frame range。
- 不和 live terminal 共享 input controller。

### UI 组件

新增组件建议：

- `CommandBlockOverlayLayer`
- `CommandBlockHeader`
- `CommandBlockActionRow`
- `CommandBlockGutter`
- `FailureSnapshotBar`
- `HistoryPeekSheet`

组件规则：

- 使用现有 `AppThemeTokens`、`ColorScheme` 和 Material 3。
- 不在 widget 内硬编码颜色。
- 不把每条命令做成大卡片；默认只用 header、gutter、细边框和轻量背景。
- action row 必须避开选区和搜索浮层。
- 长命令文本单行截断，tooltip 或详情区显示完整命令。

### Runtime 与渲染

第一版不改 terminal parser。

渲染方案：

- `TerminalViewport` 继续负责真实终端内容。
- 命令块 UI 作为 overlay / annotation 层绘制。
- row range 通过 absolute row 映射到当前 viewport。
- 不把 header 写入 scrollback，不改变复制原始终端文本。

复制规则：

- `Copy output` 复制 output range，不包含 header。
- `Copy command with output` 可作为后续动作，第一版不默认展示。
- 手动选区复制仍优先按真实终端选区处理。

## 状态和错误

### Loading

```text
Preparing command history...
```

### Empty

```text
No command history yet.
Run a command with shell integration enabled.
```

### Shell integration disabled

```text
Command blocks need shell integration.
```

### Output range unavailable

```text
This command output range is unavailable.
```

### Compare unavailable

```text
No previous run found for this command.
```

### Snapshot unavailable

```text
Failure snapshot could not be created.
```

## 键盘和可访问性

- 命令块 header 可被键盘聚焦。
- 上下方向键在 read-only review 中按命令块跳转。
- `Enter` 打开命令块 action row。
- `Escape` 关闭 action row、History Peek 或 Review Workspace。
- action row 的每个按钮有明确 semantics label。
- 失败状态不能只靠颜色表达，必须包含 `exit 1` 或 `failed` 文本。
- History Peek 过滤 tabs 支持键盘切换。
- Review Workspace 继续使用独立 route semantics。

## 实现阶段

### 阶段 1：命令块数据闭环

- 新增 `ShellCommandBlock`、range、marker、snapshot 模型。
- 从现有 shell integration / productivity state 推导命令块。
- 为 `copyLastCommandOutput`、`jumpToCommandBlock`、`saveCommandOutput` 补 reducer 和 callback 输入。
- 不改默认 UI，只先加单元测试。

完成条件：

- 成功 / 失败 / 运行中命令块能从事件序列稳定生成。
- command output range 能映射到命令块。
- shell integration 关闭时能给出 disabled reason。

### 阶段 2：Command Blocks UI

- 在 `ShellScreen` terminal pane 上叠加命令块 gutter、header 和 action row。
- 实现 `Copy output`、`Replay from here`、`Save snapshot`。
- 实现 read-only review 状态栏和输入保护。
- 保持 terminal 选择、搜索、滚动行为不回退。

完成条件：

- 默认 live terminal 仍是主画面。
- 命令块 overlay 不改变 terminal 文本复制结果。
- 失败命令能展示快捷动作和失败快照。

### 阶段 3：History Peek

- 新增 History Peek sheet / popover。
- 支持过滤、搜索、跳转命令块。
- 显示细时间标尺。
- 接入 command menu 和 toolbar 入口。

完成条件：

- 用户能从 History Peek 跳到最近失败命令。
- 关闭 History Peek 后 live terminal 状态不变。

### 阶段 4：Review Workspace 深复盘

- `Replay from here` 按 command block 定位 Instant Replay。
- `Compare last run` 打开 diff review。
- `View snapshot` 打开完整 failure snapshot。
- 复用 Instant Replay 的只读 viewport、timeline、search 和 `Fit recorded size`。

完成条件：

- 深复盘不会向 live PTY 写入输入。
- replay、diff、snapshot 都能从同一 command block id 进入。

## 测试策略

### Unit tests

- shell hook event 生成 running / succeeded / failed command block。
- prompt marks 推导 output range。
- `copyLastCommandOutput` 选择最后有效 output range。
- failure snapshot 提取 command、cwd、exit code、duration、key error lines。
- `compareLastRun` 找同 cwd 下上一条相同 command。
- shell integration disabled 返回 disabled reason。

### Widget tests

- 失败命令块显示 header、exit code 和 action row。
- hover / focus 后显示快捷动作。
- terminal 选区存在时 action row 不遮挡选区。
- `Copy output` 不包含 command block header。
- read-only review 阻止文本写入，但允许复制和搜索。
- History Peek 能过滤 failed / marked。
- `Open in Review` 创建独立只读工作区。

### Integration / manual checks

- 真实 macOS app 中运行成功和失败命令，命令块边界稳定。
- 长输出滚动后 header / gutter 位置不漂。
- 搜索浮层、command menu、autocomplete 和 action row 不互相抢焦点。
- 清屏后仍能从 replay 或 command history 找到清屏前失败命令。
- 关闭 shell integration 后界面降级明确，terminal 基础输入不受影响。

## 验收标准

- Command Blocks 是默认主体验，用户不必离开 live terminal 就能复制输出、保存失败和进入 replay。
- History Peek 是轻入口，不常驻挤压 terminal。
- Review Workspace 只承接深复盘，不替代默认命令块体验。
- 所有历史动作都通过 action id / production callback 接入，不绕过现有 action pipeline。
- 命令块 overlay 不写入 PTY、不改 scrollback 原文、不破坏选区复制。
- read-only review 明确保护 live PTY 输入。
- shell integration 关闭时功能清楚降级。
- 文档、单元测试、widget 测试覆盖数据模型、UI 状态和输入保护。
