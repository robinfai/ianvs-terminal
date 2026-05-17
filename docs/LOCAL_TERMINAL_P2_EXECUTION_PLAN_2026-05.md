# P2 Execution Plan: Local Workspace

## Objective

建立稳定的本地 workspace 模型，让 tabs、panes、layout、focus、resize、close、restore 都收口到可测试的数据结构和 action 边界。

## Preconditions

- P1 已提供稳定 action id 和 action registry。
- P1 已提供 config schema 的 workspace 区域或明确预留。
- 本阶段只管理 local session，不恢复 SSH/remote session。

## Current Baseline

- `T-084-local-workspace-model-foundation` 已推进，新增纯模型 `TerminalWorkspace`、`TerminalWorkspaceTab`、`TerminalPaneNode`、`TerminalPaneSessionIntent`，覆盖 empty state、split active pane、close active pane、close/reopen tab 的最小闭环。
- `T-085-local-workspace-layout-serialization` 已推进，workspace/tab/pane tree 已支持 local-only layout serialization，并拒绝 remote-only layout 字段。
- `T-086-local-workspace-pane-operations` 已推进，pane focus、resize、swap、zoom 已在纯模型层可表达。
- `T-087-local-workspace-same-cwd-intent` 已推进，new tab / split 可以从 active pane 派生 local session intent，并支持 fallback。
- `T-096-local-workspace-undo-close-pane` 已推进，close/reopen pane 的最小模型闭环已建立。
- `T-099-local-workspace-layout-repository` 已推进，workspace layout 已有独立文件 repository、missing fallback 和 corrupt repair。
- `T-109-local-workspace-action-reducer` 已推进，workspace action id 到 workspace state change 的纯 reducer 已建立。
- `T-134-workspace-runtime-persistence-hook` 已推进，workspace update path 已可通过注入式 hook 触发布局持久化。

## Work Plan

1. Workspace data model
   - 定义 `TerminalWorkspace`。
   - 定义 `TerminalTab`。
   - 定义 `TerminalPaneNode`。
   - 明确 pane tree 的 split、leaf、active pane 和 empty state 表达。

2. Core tab operations
   - new tab。
   - close tab。
   - reopen closed tab。
   - duplicate current cwd。
   - close last tab 后进入 empty state。

3. Core pane operations
   - split right。
   - split down。
   - auto split。
   - focus next / previous。
   - focus by direction。
   - resize pane。
   - move / swap pane。
   - zoom / unzoom pane。
   - close pane。
   - undo close pane。

4. Same-cwd behavior
   - new tab from current cwd。
   - split from current cwd。
   - shell integration 不可用时降级为 profile/default cwd。

5. Layout persistence
   - save layout。
   - load layout。
   - layout restore 不保存或恢复 remote 概念。
   - layout restore 不恢复外部进程状态，只恢复本地 session 启动意图和 pane topology。

## Task Breakdown

1. `T-084`: workspace/tab/pane model and unit tests
2. `T-086` / `T-109`: split/focus/resize/swap/zoom model operations and action reducer
3. `T-096` / `T-109`: close/undo close/empty state behavior
4. `T-087`: same-cwd new tab/split behavior
5. `T-085` / `T-099` / `T-134`: layout save/load local-only schema, repository, and runtime persistence hook

## Acceptance Criteria

- 多 pane 操作稳定，active pane 始终明确。
- 关闭 active pane 后 focus fallback 正确。
- 关闭最后一个 pane/tab 后 empty state 正确。
- split/new tab 可以继承当前 cwd；不可用时有可解释降级。
- layout restore 不包含 SSH、remote、serial、SFTP 概念。

## Verification

- Unit tests
  - split、focus、resize、move、swap、zoom、close、undo close
  - layout serialization/deserialization
  - invalid layout recovery

- Widget tests
  - split right/down 后 active pane 正确
  - close active pane 后 focus fallback 正确
  - close last tab 后 empty state 正确
  - same-cwd new tab/split 使用当前 cwd

- Manual smoke
  - 使用 `/bin/zsh` 或 `/bin/bash` 打开多 tab、多 pane
  - 连续 split/resize/close/undo close
  - 保存 layout 后重新打开

## Exit Criteria

- P3 可以把 command output、prompt navigation、search 等能力挂到 workspace/pane/action 模型上，不需要重做 pane tree。

## Risks

- 风险：pane model 与现有 `ShellScreen` 状态重复。
- 缓解：先建最小数据模型，再逐步迁移调用点，不做一次性大重构。

- 风险：layout persistence 被误用为 session process restore。
- 缓解：文档和 schema 明确只恢复本地 session 启动意图与 pane topology。

## Added foundation slice: T-155 Local workspace production callbacks

Status: WIRED / UNVERIFIED. Added a typed production callback and wiring
contract for tab, pane, split, focus, resize, swap, zoom, and layout operations.
Current `ShellScreen` / `SessionController` wiring covers the core tab, split,
focus, close, resize, swap, zoom, duplicate-cwd, and reopen-closed-tab baseline.
Remaining work: verify focus fallback, close-last-pane behavior, layout
expectations, and multipane manual behavior before closing P2 production wiring.
