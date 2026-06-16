# Command Block / Command Center 融合设计

## 背景

当前工作树已经合并了两条产品线：

- Command Blocks 历史工具：以 `ShellCommandBlockSnapshot` 为核心，负责真实终端中的
  command block 捕获、输出范围、失败快照、preview、overlay 和 History Peek。
- Command Center：以 `CommandCenterRuntime`、`CommandBlockRangeState`、Action Search、
  saved command、context chips 和 review entrypoints 为核心，负责搜索、动作入口和命令复用。

合并后出现了一个产品和架构上的重复：两套系统都在描述 command block。

- `ShellCommandBlockSnapshot` 从 shell hook、terminal frame、prompt row 和 preview rows
  维护命令块，是更贴近 live terminal 的事实来源。
- `CommandCenterRuntime.blockRangeState(...)` 从 invocation 和 prompt marks 再推导一套
  `CommandBlock`，适合早期 Command Center 路线图，但现在会和 Command Blocks 主线产生边界漂移。

本设计重新评估 Command Center 的需求：Command Blocks 成为主线，Command Center 变成围绕
command block 的搜索、动作、保存、上下文提示和 review 路由层。

## 当前代码证据

已检查的关键文件：

- `example/lib/features/productivity/shell_command_block_controller.dart`
- `example/lib/features/productivity/shell_productivity_models.dart`
- `example/lib/features/shell/shell_screen_state_events.dart`
- `example/lib/features/shell/shell_command_block_view_models.dart`
- `example/lib/features/shell/shell_screen_command_blocks.dart`
- `example/lib/features/shell/shell_screen_history_peek.dart`
- `example/lib/features/command_center/command_center_runtime.dart`
- `example/lib/features/command_center/command_block_models.dart`
- `example/lib/features/command_center/command_block_action_reducer.dart`
- `example/lib/features/shell/shell_screen_state_command_action_search.dart`
- `example/lib/features/shell/shell_screen_state_context_chips.dart`

结论：

- `ShellCommandBlockShellHookReducer` 和 `ShellCommandBlockController` 已经能从 shell hook
  生成 `ShellCommandBlockSnapshot`。
- `ShellScreen` 同时维护 `_commandBlockSnapshotsBySession` 和 `_commandCenterRuntime`。
- Action Search 和 context chips 当前仍通过 `CommandCenterRuntime.blockRangeState(...)`
  获取 command block。
- History Peek 和 Command Blocks overlay 已经消费 `ShellCommandBlockSnapshot`。
- 同一条命令在 overlay / History Peek 与 Action Search / context chips 之间可能拥有不同 id、
  range 和 selected block 语义。

## 设计目标

- 以 Command Blocks 作为 command block 的唯一事实来源。
- 保留 Command Center 已实现的搜索、saved command、Action Search、context chips 和 review 入口。
- 让 Command Center 通过 adapter 消费 `ShellCommandBlockSnapshot`，不再独立判断 block 边界。
- 确保 overlay、History Peek、Action Search、context chips 和 review 对同一条命令使用同一个 block id。
- 保持 terminal-first：不改 terminal renderer，不写入 scrollback，不改变真实终端复制文本。
- 保持安全策略：read-only、paste policy、shortcut/action pipeline 继续生效。
- 第一批融合聚焦事实来源统一，不扩展 Agent、cloud、remote、团队共享或插件能力。

## 非目标

- 不重写 Command Blocks overlay 或 History Peek UI。
- 不删除 Command Center 的 saved command、Action Search 或 search index 能力。
- 不把 Command Center 改成独立 dashboard。
- 不把 command block header 写入 PTY 或 scrollback。
- 不在第一批迁移里删除所有旧 `CommandBlock` / `CommandInvocation` 类型。
- 不实现完整 saved command 管理面板。
- 不新增远程同步、云端历史、团队共享或 Agent 工作流。

## 核心决策

### 1. 产品主语

融合后的主语是 Command Blocks。

用户心智：

> 我先在 live terminal 里看到一条条 command block；需要操作时，用 Command Center 搜索、
> 调用、保存、复盘这些 block。

Command Center 不再作为独立 command lifecycle 产品线存在。它承接五类能力：

- 找：搜索历史命令、saved command 和可执行动作。
- 做：复制输出、保存输出、重新输入、重新运行、进入 review。
- 收：把当前或选中的 command block 保存为 saved command。
- 提示：展示 selected block、last failed、cwd、read-only 和 shell integration 状态。
- 路由：把 block 动作送到 action pipeline、terminal safety 和 Instant Replay。

### 2. 数据事实来源

唯一 command block 事实来源：

```text
Terminal shell hook / frame
  -> ShellCommandBlockShellHookReducer
  -> ShellCommandBlockSnapshot
  -> Command Blocks UI / History Peek / Command Center adapters
```

规则：

- `ShellCommandBlockSnapshot` 是唯一 command block state。
- `ShellCommandBlock.id` 是 selected block、block action、review、save output 和 saved command
  entrypoint 的统一 id。
- `ShellCommandBlockRange` 是唯一 command/output row range 来源。
- Command Center 不再通过 prompt marks 和 invocation 重建当前 block range。
- `CommandCenterRuntime` 后续只保留非 block 职责，例如 global command history、saved command
  repository 状态、search index 输入和必要的持久化编排。

### 3. Adapter 边界

新增 adapter：

```text
ShellCommandBlockCommandCenterAdapter
```

职责：

- 从 `ShellCommandBlockSnapshot` 找 active / selected / last failed block。
- 将 `ShellCommandBlock` 转成 Action Search、context chips、block actions 和 review 需要的轻量 target。
- 保留现有 `CommandBlockActionReducer` 可消费的短期兼容模型。
- 给出统一 unavailable reason，例如 no block、missing output range、read-only、shell integration disabled。

禁止职责：

- 不重新解析 shell hook。
- 不重新计算 prompt mark range。
- 不生成第二套 command lifecycle。
- 不写入 repository。
- 不直接写 shell。

建议 API：

```text
activeBlockFor(sessionId, selectedBlockId)
lastFailedBlockFor(sessionId)
blocksForSearch(sessionId)
contextChipStateFor(sessionId)
blockActionTargetFor(blockId)
reviewSourceFor(blockId)
```

第一批可以让 adapter 输出现有 `CommandBlock`，但 `CommandBlock` 只能是兼容 target，不再是事实来源。

## 交互设计

### Command Blocks Overlay

Command Blocks overlay 是主入口。用户在 live terminal 里看到当前或最近 command block，可直接执行：

- Copy output
- Save output
- Search within block
- Open in review
- Reinput command
- Rerun command
- Save command

动作必须作用于 `ShellCommandBlockSnapshot` 中的同一个 block id。

### Action Search

Action Search 保留为统一动作入口，但排序和上下文转为 command block 优先。

默认排序：

1. 当前 selected block 的动作。
2. 最近失败 block 的动作。
3. 当前 session 的 saved commands。
4. 普通全局动作。

结果文案需要显示作用对象，例如：

```text
Copy output · flutter test
Open in review · npm run build
Save command · cargo test
```

没有 command block 时，block action 显示明确 unavailable feedback，不回退到另一套推导逻辑。

### Context Chips

Context chips 只做状态展示和快捷入口，不再自己推断 block。

保留 chips：

- selected block
- last failed block
- cwd
- read-only
- shell integration 状态

点击 selected / last failed block chip 时，使用 adapter 返回的同一个 block id 执行导航和动作。

### History Peek

History Peek 继续用 `ShellCommandBlockSnapshot`。它负责“找 block”，Action Search 负责“对 block 做事”。

当用户从 History Peek 选中 block 时，更新同一份 selected block id，Action Search 和 context chips
立刻围绕该 block 排序和展示。

### Saved Command

保存入口优先来自 selected/current command block。

规则：

- 保存 command text，不保存 output。
- 保存后进入本地 `SavedCommandDocument`。
- Action Search 可以马上搜到并插入 saved command。
- 插入 saved command 不自动执行。
- read-only 阻止 shell 写入，但不阻止本地保存 saved command。
- privacy filter 继续保护本地落盘。

## 迁移设计

### 第一批：事实来源统一

第一批目标是让 Command Center 消费 Command Blocks，不继续并行推断。

改动范围：

- 新增 `ShellCommandBlockCommandCenterAdapter`。
- 替换 `ShellScreen` 中以下路径：
  - `_activeCommandActionSearchBlock(...)`
  - `_contextChipBlockFor(...)`
  - `_contextChipsForPane(...)`
  - review entrypoint 的 block 来源
  - copy/save/search within block 的 output range 来源
- 保留现有 `CommandBlockActionReducer`，通过 adapter 生成兼容 target。
- 标记 `CommandCenterRuntime.blockRangeState(...)` 为迁移路径，不再新增依赖。
- 更新 Action Search 排序和 block action 文案。

第一批完成后，以下行为必须成立：

- overlay、History Peek、Action Search、context chips 对同一条命令使用同一个 `ShellCommandBlock.id`。
- Action Search 不再从 `CommandCenterRuntime.blockRangeState(...)` 推导当前 block。
- selected block 失效时，只在 `ShellCommandBlockSnapshot` 内回退最近 block。
- block output range 来自 `ShellCommandBlockRange`。
- 没有 block 时显示 unavailable feedback。

### 第二批：清理重复模型

在第一批稳定后：

- 将 `CommandBlockActionReducer` 泛化到 command-block target，减少对旧 `CommandBlock` 的依赖。
- 逐步删除或降级 invocation-derived block range 测试。
- 将 `CommandCenterRuntime` 收敛到 history/search/persistence 职责。
- 更新 `docs/tasks/command-center/README.md`，明确 Command Blocks 为执行主线。

### 第三批：产品体验收口

在数据边界稳定后：

- Action Search 支持 block context grouping。
- History Peek 选中 block 后同步 Action Search 上下文。
- selected block chip 和 overlay action row 使用同一动作文案。
- review entrypoint 显示同一来源 metadata。
- saved command 保存入口接入 overlay、context chip 和 Action Search。

## 错误和降级

- `ShellCommandBlockSnapshot` 为空：block actions 不可用，Action Search 仍显示普通动作和 saved commands。
- shell integration disabled：不显示完整 block action；context chips 显示 shell integration 状态。
- output range 缺失：copy/save/search within/review 禁用，reinput/rerun 仍可按 command text 判断。
- read-only：reinput/rerun/insert saved command 走 read-only 禁用；copy/save local saved command 仍可用。
- replay frame 缺失：Open in review 禁用，copy/save output 不受影响。
- privacy filter 拒绝：saved command 不落盘，并显示敏感命令保护反馈。

## 测试策略

### 纯逻辑测试

- adapter 能从 `ShellCommandBlockSnapshot` 找到 selected block。
- selected block id 失效时回退最近有效 block。
- 最近失败 block 能被 context chips 和 Action Search 使用。
- `ShellCommandBlockRange` 转换到兼容 target 时不丢 command row 和 output rows。
- 没有 block、read-only、缺 output range 时返回正确 disabled reason。
- block action target 使用 `ShellCommandBlock.id`。

### Widget 测试

- Action Search 的 block action 作用到 overlay / History Peek 同一条 block。
- selected block chip 打开的动作和 Action Search 作用到同一 block id。
- save output、copy output、search within block 使用同一 output range。
- 保存当前 block command 后，Action Search 能搜到 saved command。
- 没有 command block 时 Action Search 显示 unavailable feedback。

### 人工验证

- macOS app 中运行成功命令和失败命令。
- overlay、History Peek、Action Search 看到同一条命令。
- 复制输出不包含 command block header。
- read-only 下不会写 shell，但允许保存本地 saved command。
- review 打开后不影响 live terminal。

## 文档更新策略

本 spec 是新的融合口径。

后续实现计划需要更新：

- `docs/superpowers/specs/2026-06-15-command-center-roadmap-intake-design.md`
  - 标记为早期并行产品线口径。
  - 增加指向本融合 spec 的说明。
- `docs/superpowers/specs/2026-06-05-command-block-history-tools-design.md`
  - 增加 Command Center 作为消费层的关系。
- `docs/tasks/command-center/README.md`
  - 增加执行规则：Command Blocks 为主线，Command Center 不再创建第二套 block range。
- `docs/tasks/command-center/T-313` 到 `T-321`
  - 标记相关 block-range / action / review 任务需要按 adapter 口径迁移。

## 验收标准

- 设计文档明确 Command Blocks 是主线。
- 设计文档明确 `ShellCommandBlockSnapshot` 是唯一 command block 事实来源。
- 设计文档明确 Command Center 的保留职责和非职责。
- 设计文档给出第一批融合范围、后续清理路径、测试策略和文档更新策略。
- 后续 implementation plan 可以直接从第一批迁移范围拆任务。
