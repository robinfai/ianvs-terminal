# Saved Command 保存入口设计

## 背景

Command Center 已经具备 saved command 的本地 repository、action search 展示与插入路径，以及实际使用后的 `useCount` / `lastUsedAt` 更新。

当前缺口是：用户还不能从真实终端工作流里创建 saved command。现有任务文档已经把 saved command 创建、编辑、删除 UI 标记为后续工作；这版先做最小可用保存入口，让 saved command 从“可被搜索和插入”变成“用户能从 command block 保存并复用”。

仓库里已有可复用基础：

- `SavedCommandRepository` 和 `SavedCommandDocument` 负责本地 JSON、normalize、dedupe、limit、privacy filter 和 usage metadata。
- `CommandActionSearchOverlay` 已展示 saved command，并在插入成功后更新使用统计。
- `CommandBlock`、selected block chip 和 action search block actions 已能定位当前 command block。
- `ShellScreen` 已通过 `savedCommandRepositoryProvider` 读取和保存 saved commands，并能刷新 action search controller。

## 已确认方向

采用最小可用保存入口：

- 从 selected block chip 和 action search block action 保存 command block 的命令文本。
- 保存后立即进入 saved command repository，action search 可以马上搜到并插入。
- 暂不做完整管理面板、批量清空、复杂编辑列表或 cloud/team sync。

不采用完整管理面板作为本轮目标，因为那会把一个复用闭环扩成设置页/资源管理器项目。当前最有价值的是让用户在完成一条命令后能立刻保存，并能通过 action search 再次使用。

## 目标

- 用户可以从 selected command block 保存命令为 saved command。
- 用户可以从 action search 的 block action 保存当前有效 command block。
- 保存动作不写 shell，不自动执行命令。
- 保存后的命令能被 action search 搜到并插入。
- read-only 只阻止 shell 写入，不阻止本地保存 saved command。
- privacy filter 继续保护本地落盘，敏感命令不会进入 saved command document。
- 保存入口有自动化测试覆盖，并纳入 Command Bar lane 验证门。

## 非目标

- 不实现完整 saved command 管理页。
- 不实现编辑已保存命令、删除单条命令或清空所有命令。
- 不实现 tags 输入、收藏、分组、排序配置或导入导出。
- 不执行 saved command。
- 不保存 command output；保存对象只包含 command text 和必要 metadata。
- 不做 cloud sync、remote sync、团队共享或插件 saved commands。

## 产品行为

### Selected Block Chip 保存

当当前 session 有 selected block 时，selected block chip 的 block actions 增加 `Save command`。

点击后打开轻量保存对话框：

- `Title`：默认取命令首行，去掉前后空白，过长时截断为可读标题。
- `Command`：默认填入 block command text。允许编辑，以便用户保存更通用的版本。
- `Cancel`：关闭对话框，不写 repository。
- `Save`：保存到本地 saved commands。

保存成功后显示简短反馈，例如 `Saved command.`，并刷新 `_savedCommands`，让 action search 重新构建结果。

### Action Search Block Action 保存

action search 增加 `save command` 可搜索动作，归类为 block action。

选择后使用和现有 block actions 一致的 block 选择规则：

1. 优先 selected block。
2. selected block 无效时回退最近 command block。
3. 找不到 command block 时显示 unavailable feedback，不打开保存对话框。

保存对话框和 selected block chip 共用同一个流程。

### 保存后复用

保存成功后：

- `SavedCommandDocument` 增加或替换同 id entry。
- ShellScreen 内存态 `_savedCommands` 同步更新。
- `_commandActionSearchController` 失效，下一次打开 action search 时包含新 saved command。
- 如果保存是从 action search 发起，保存成功后关闭 action search overlay；下一次打开时使用刷新后的结果。

## 数据模型和 id 规则

保存入口不改变 v1 JSON schema。继续使用现有字段：

- `id`
- `title`
- `command`
- `cwd`
- `tags`
- `createdAt`
- `updatedAt`
- `useCount`
- `lastUsedAt`

本轮新增一个 document-level upsert 方法：

- 输入：title、command、cwd、now。
- 输出：更新后的 `SavedCommandDocument`。
- 同一 normalized command 可以生成稳定 id，重复保存时更新 title/cwd/updatedAt，保留 createdAt、useCount 和 lastUsedAt。
- 不同 command 生成不同 id。

id 生成规则：

- 基于 normalized command text 的短 hash，例如 `cmd-<hash>`。
- hash 前先 normalize 换行和前后空白。
- 如果未来需要同一 command 保存多个变体，可以在后续管理 UI 里引入 duplicate action；本轮选择 dedupe，符合 repository 已有去重倾向。

## 架构

### 纯逻辑层

`saved_command_repository.dart` 增加小型纯逻辑能力：

- `SavedCommandDocument.upsertCommand(...)`
- 增加私有 title/command normalize helper，供 upsert 和测试共同覆盖。

这一层不依赖 Flutter widget，不读取 terminal state，只处理 document 变换，便于单测。

### ShellScreen 状态层

ShellScreen 增加一个保存编排方法：

```text
saveCommandBlockAsSavedCommand(sessionId, block)
  -> build default draft from block
  -> show save dialog
  -> upsert document
  -> repository.save
  -> update _savedCommands
  -> invalidate action search controller
  -> show feedback
```

保存方法归属于 app shell 层，因为它需要读取 selected block、弹对话框、保存 repository、刷新 action search 和显示 snackbar。

### UI 层

新增一个 ShellScreen 私有 dialog builder：

- 不做成大管理面板。
- 使用项目现有 Material 3 theme。
- 文本字段支持键盘输入、取消和保存。
- Save 按钮在 command 为空时禁用，并在 command 字段显示简短校验。

dialog 的文本不描述功能说明，只提供必要字段标签和操作按钮。

## 错误处理

- 空 command：不保存，停留在 dialog 并显示简短校验信息。
- 空 title：使用 command 首行作为 title。
- privacy filter 拒绝：不写入 document，显示 `Command was not saved because it may contain sensitive data.`。
- repository save 失败：保留 dialog，在 dialog 内显示错误，不更新 `_savedCommands`。
- block 不存在：显示 unavailable feedback，不打开 dialog。
- read-only：允许保存；read-only 不是本地 repository 写入限制。

## 测试策略

### 单元测试

扩展 `saved_command_repository_test.dart`：

- upsert 新 command 会新增 entry。
- 重复保存同一 normalized command 会更新 title/updatedAt，但保留 createdAt、useCount 和 lastUsedAt。
- 空 command 不生成 entry。
- privacy filter 拦截敏感命令。

### Widget 测试

扩展 `widget_test.dart`：

- selected block chip 可以保存 block command，不写 shell。
- action search 可以执行 save command block action，不写 shell。
- 保存后 action search 能搜到新 saved command，并插入到 shell。
- read-only 下保存仍可用，但插入 saved command 仍被 read-only 阻止。
- 没有 command block 时 action search save command 显示 unavailable feedback。

### 验证门

更新 `T-322` Command Bar lane：

```bash
cd example
flutter analyze
flutter test test/command_center/saved_command_repository_test.dart
flutter test test/widget_test.dart --plain-name "saved command"
flutter test test/widget_test.dart --plain-name "action search"
```

## 文档任务

新增 `T-390-saved-command-save-entrypoints.md`：

- 记录最小保存入口范围。
- 明确完整管理面板后置为 `T-391`。
- 把 T-328、T-334、T-389 的 follow-up 指向 T-390。
- README Command Bar lane 追加 `T-390`。

## 后续任务

T-391 建议承接完整管理：

- saved command list。
- edit/delete。
- clear all。
- tags。
- optional import/export。

本轮 T-390 只提供从真实 command block 保存并复用的最小闭环。
