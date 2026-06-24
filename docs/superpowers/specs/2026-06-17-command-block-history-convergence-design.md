# Command Block / History 收敛设计

## 背景

`2026-06-05-command-block-history-tools-design.md` 将 `History Peek` 定义为轻量历史入口，
将 `command block` 定义为命令动作和复盘锚点。这个拆分在概念上成立，但在当前
Command Center 合流后的体验里出现了三个问题：

1. 用户需要同时理解 `History Peek`、`Ctrl-R`、`command block` 三个相近入口。
2. “找历史”和“对命令做动作”的边界不够清楚，容易形成双轨心智。
3. 手工验收暴露出更具体的体验风险：block action 入口不稳定、焦点可能落到隐藏
   terminal 输入路径、写入入口不够单一。

本设计目标不是简单删除一个名字，而是把历史查找、命令上下文和复盘路径收成一套更稳定
的产品结构。

## 决策摘要

- 移除 `History Peek` 作为独立产品概念、独立入口和独立界面。
- 只保留一个主概念：`command block`。
- `Ctrl-R` 成为唯一历史查找入口。
- `Ctrl-R` 搜索对象不是普通 history 文本，而是可定位的 `command block record`。
- `Ctrl-R` 默认搜索当前 session，可切到全局。
- `Ctrl-R` 结果只显示有 `command block` 上下文的记录；当前 session 和全局都执行同一规则。
- `Enter` 只回填到 `command input`，不直接执行命令。
- `Ctrl-R` 提供次级入口进入对应 `command block`。
- `command block` 负责命令动作、命令状态承载和进入 `review / replay`。
- 在 command block 模式下，唯一可写输入面始终是 `command input`，不允许隐藏 terminal focus 承担写入。

## 目标

- 收敛用户心智，让“找历史”和“对命令做动作”有清楚分工。
- 保留轻量查找的速度，不保留第二套独立历史产品面。
- 用统一的 `command block` 主键承接回填、复制、块内搜索、review 和 replay。
- 消除多入口重复、隐藏焦点写入和动作入口不可达的风险。

## 非目标

- 不保留普通 history 文本结果作为 `Ctrl-R` 的兜底显示。
- 不新增新的历史浏览器、history rail 或 side sheet。
- 不引入 Agent / AI、remote / SSH、cloud sync 或协作能力。
- 不重写 terminal renderer，不改变现有 package 边界。
- 不让 `Ctrl-R` 直接承担 review / replay 的完整工作流。

## 备选方案与结论

### 方案 A：彻底统一到 block-only history

- `Ctrl-R` 只搜有 `command block` 上下文的记录。
- `command block` 负责动作和 review。
- `History Peek` 完全移除。

优点：

- 规则一致，概念最干净。
- `Ctrl-R` 和 `command block` 的职责边界清楚。
- 所有后续动作都能围绕同一条 block 记录建模。

代价：

- 全局召回会少于“普通 history + block 混合结果”方案。
- 对 block 数据沉淀质量要求更高。

### 方案 B：表面统一，底层双轨

- 表面只讲 `command block`。
- `Ctrl-R` 仍混入普通 history 结果。
- 只有部分结果能进入 block / review。

优点：

- 搜索召回更高。
- 对旧数据和降级场景更宽容。

代价：

- 用户会遇到“有些结果可进入 block，有些只能回填”的不一致规则。
- 文案、空态和过滤逻辑都会变复杂。

### 方案 C：极致精简

- `Ctrl-R` 只搜当前 session block。
- 不支持全局切换。
- `command block` 只负责当前终端里的动作和 review。

优点：

- 交互和实现都最轻。

代价：

- 全局价值不足，不符合当前产品方向。

### 结论

采用 **方案 A**。它与当前已确认的约束一致：

- 只保留 `command block`
- `Ctrl-R` 承担历史查找
- 默认当前 session，可切全局
- 结果只显示可进入 block 的记录
- 规则在当前 session 与全局范围内保持一致

## 信息架构与职责边界

### 核心原则

系统对外只保留一个主概念：`command block`。
用户不再需要理解 `History Peek` 是另一套产品面。所有“过去命令的查找、定位、回填、复盘”
都围绕 command block 展开。

### 职责划分

| 面 | 负责内容 | 不负责内容 |
| --- | --- | --- |
| `Ctrl-R` | 历史查找、结果浏览、回填、进入对应 block | 普通 history 兜底浏览、直接执行、完整 review |
| `command block` | 命令状态、命令动作、review / replay 来源锚点 | 全局历史搜索、第二套输入模式 |
| `review / replay` | 深复盘、只读查看、时间线定位 | 历史搜索、写入 live terminal |

### 用户心智

产品收敛后的主路径应当能用一句话解释：

`找历史，用 Ctrl-R；操作这条命令，用 command block。`

## `Ctrl-R` 结果模型与交互规则

### 结果模型

`Ctrl-R` 的每一条结果都是一条可定位的 `command block record`，至少包含：

- `command`
- `cwd`
- `status`
- `last run / time`
- `duration`
- 全局模式下的 `session` 标识

结果项表达的是“一个可以回填，也可以继续查看的命令块实体”，而不是单纯的历史文本。

### 搜索范围

- 默认打开在“当前 session”。
- 用户可以切到“全局”。
- 当前 session 和全局都只显示有 `command block` 上下文的记录。
- 不混入“只能回填、不能进入 block”的普通 history 结果。

### 主次动作

- `Enter`：将选中命令回填到 `command input`。
- 回填后关闭 `Ctrl-R`，focus 回到 `command input`。
- `Ctrl-R` 结果项提供次级入口：`查看命令块`。
- `查看命令块` 进入对应 block 上下文，不直接执行命令。

### 焦点与安全规则

- 打开 `Ctrl-R` 时，搜索框自动获得 focus。
- `Esc` 关闭后，focus 明确回到 `command input`。
- 搜索输入、上下移动、关闭和查看 block 的过程都不能向 PTY 泄漏控制字符。
- `Ctrl-R` 不通过隐藏 terminal focus 完成回填或执行。

## `command block` 的职责收敛

### 保留的核心动作

以下动作继续由 `command block` 承担：

- `re-input`
- `rerun`
- `copy command`
- `copy output`
- `copy command + output`
- `search within block`
- `open in review`
- `replay from here`

这些动作都与具体命令块强绑定，保留在 block 上最自然。

### 从 `History Peek` 吸收的价值

被吸收的不是独立能力，而是两类体验价值：

- 轻量查找：在不离开 live terminal 的前提下快速找回刚才的命令。
- 紧凑摘要：快速扫到 `command / cwd / status / time / duration` 这些关键信息。

这两类价值分别落在：

- `Ctrl-R` 的结果列表
- `Ctrl-R -> 查看命令块 -> block actions / review` 这条路径

### 明确不再保留的内容

以下内容不再作为独立产品面存在：

- `History Peek` 名称
- `Open history peek` 类文案
- 独立 `History Peek` toolbar / status bar / menu 入口
- 独立 side sheet / popover 历史预览面
- 历史列表和命令块列表双轨并存的结构

## 输入模型与安全约束

### 唯一写入口

在 command block 模式下，唯一可写输入面始终是 `command input`。

这意味着：

- 黑色 terminal 区域不承担隐藏焦点写入。
- 多行粘贴经过 `command input`。
- 回填经过 `command input`。
- 用户二次编辑经过 `command input`。

### read-only 规则

- 搜索、查看、复制、review 可以继续可用。
- `re-input`、`rerun` 等写入型动作必须禁用。
- disabled reason 需要稳定、明确，不能靠猜测状态。
- 进入 block 或 review 不得偷偷恢复 live terminal 的可写输入。

## 降级场景与空态

### 当前 session 没有可用 block

- `Ctrl-R` 打开在当前 session 时显示明确空态。
- 不回退成普通 history 文本搜索。

### 搜索词无匹配

- 说明当前范围内存在 block 记录，但当前 query 无结果。
- 与“当前范围完全没有 block”分开表达。

### 全局范围也没有可用 block

- 显示全局空态。
- 不引导用户寻找另一套历史预览入口。

### 有摘要但无完整复盘数据

- 记录仍可出现在 `Ctrl-R`。
- 可以回填命令。
- 可以打开对应 block。
- `open in review` / `replay from here` 可置灰并给出 disabled reason。

## 迁移与删除策略

### 旧能力到新落点的映射

- “快速找刚才那条命令” -> `Ctrl-R`
- “看命令摘要信息” -> `Ctrl-R` 结果项
- “对某条命令做 re-input / rerun / search / review” -> 对应 `command block`
- “进入更深复盘” -> `command block -> review / replay`

### 迁移顺序

1. 将 `Ctrl-R` 定义为唯一历史查找入口。
2. 为 `Ctrl-R` 结果补齐 block 摘要信息和 `查看命令块` 入口。
3. 确保 `command block` 动作全部有可达入口。
4. 删除 `History Peek` 的名称、入口、文案、测试和 feature flag 分支。

### 迁移原则

- 先完成能力承接，再移除旧入口。
- 先统一用户心智，再清理内部命名。
- 任何原本能完成的关键任务，都必须有新的明确落点。

## 验收标准

### 产品一致性

- 产品里不再出现 `History Peek`。
- 不再存在独立 `History Peek` 菜单、按钮、面板或空态。

### 搜索一致性

- `Ctrl-R` 只返回有 block 上下文的结果。
- 默认当前 session，可切全局。
- 两种范围执行同一套筛选规则。

### 焦点一致性

- 打开 `Ctrl-R` 时搜索框自动 focus。
- `Enter` 回填后 focus 回到 `command input`。
- `Esc` 关闭后 focus 回到 `command input`。
- 搜索相关快捷键不向 PTY 泄漏控制字符。

### 动作可达性

- 从 `Ctrl-R` 可进入对应 `command block`。
- 从 `command block` 可触发 `re-input`、`rerun`、复制、块内搜索、review 和 replay。
- 不再出现“能力在代码里存在，但界面上不可达”的状态。

### 输入安全

- command block 模式下不能通过隐藏 terminal focus 写入。
- 多行粘贴只能经过 `command input`。
- read-only 下写入型动作全部失效且原因明确。

## 对任务分解的影响

该收敛设计不会改变 Command Center 并行产品线的总体阶段划分，但会影响相关任务的实现口径：

- History/Search lane 需要把 `Ctrl-R` 结果模型收敛到 `command block record`。
- Blocks lane 需要保证 block action 和 review 入口真正可达。
- Command Bar lane 需要落实“`command input` 是唯一写入口”的模式约束。
- 与 `History Peek` 相关的入口、文案、开关和测试需要进入清理范围。

## 成功标准

如果收敛完成，用户应该能稳定感知到下面这条主路径：

`Ctrl-R 搜索 -> 回填或查看命令块 -> 必要时进入 review / replay`

同时，用户不再需要分辨“这是 History Peek 还是 command block”，也不会再遇到
“看起来在 command block 模式，实际写进了隐藏 terminal 焦点”的行为不一致。
