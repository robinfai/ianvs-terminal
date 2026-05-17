# P3 Execution Plan: Shell Productivity

## Objective

把已有 shell integration 能力产品化，形成 prompt navigation、cwd tracking、command output selection/copy、recent commands/directories、search 和 read-only mode 等本地效率能力。

## Preconditions

- P1 action/config foundation 可用。
- P2 workspace/pane model 至少能稳定定位 active pane 和 local session。
- shell integration 可以被关闭，关闭后 terminal 基础输入输出仍可用。

## Current Baseline

- `T-088-shell-productivity-state-foundation` 已推进，新增 shell integration feature gates、prompt marks、command output range、recent directories 和 read-only guard 的纯状态模型。
- `T-089-shell-productivity-search-block-model` 已推进，scrollback search、block scoped search、next/previous match、clear search 已有纯模型表达。
- `T-092-shell-productivity-recent-items` 已推进，recent commands / recent directories 已有 newest-first、去重和 limit trimming 的纯状态模型。
- `T-098-shell-action-availability-diagnostics` 已推进，prompt/output/recent/read-only 等 action 不可用原因已有统一模型。
- `T-100-shell-action-disabled-reason-copy` 已推进，P3 相关 disabled reason 已有可展示文案。
- `T-101-shell-productivity-event-reducer` 已推进，shell integration event 到 productivity state/recent items 的 reducer 已建立。
- `T-110-shell-productivity-action-reducer` 已推进，productivity action id 到 prompt/output/recent/search/read-only result 的纯 reducer 已建立。
- `T-112-shell-recent-items-repository` 已推进，recent commands/directories 已有本地持久化和 corrupt repair。
- `T-131-productivity-runtime-controller-integration` 已推进，prompt/output/recent directory action 已可通过 runtime controller 记录 intent。
- `T-135-productivity-runtime-event-controller` 已推进，shell productivity event reducer 已有可持有状态的 runtime controller 和 recent items persistence hook。

## Work Plan

1. Shell integration feature gates
   - 定义 `ShellIntegrationFeatureSet`。
   - 为 prompt marks、cwd、command status、recent commands、recent directories、last command output range 建立 feature-level enabled state。
   - 将 feature disabled 的原因暴露给 action enabled predicate。

2. Prompt navigation
   - jump previous prompt。
   - jump next prompt。
   - prompt mark search。
   - 无 prompt marks 时 disabled，不报错。

3. Command output actions
   - select command output。
   - copy last command output。
   - save command output。
   - last command output range 不可用时 disabled。

4. Recent commands/directories
   - recent commands 列表。
   - recent directories 列表。
   - open recent directory。
   - new tab/split from recent directory。

5. Search and scrollback productivity
   - ordinary scrollback search。
   - block scoped search。
   - next/previous match。
   - clear search。
   - clear scrollback。

6. Read-only mode
   - toggle read-only。
   - read-only 下禁止 paste 和 send text。
   - copy/search/selection 仍可用。

## Task Breakdown

1. `T-088`: ShellIntegrationFeatureSet and disabled-action gates
2. `T-088`: prompt navigation state model
3. `T-088`: command output range state model
4. `T-092` / `T-112`: recent commands/directories product state and persistence
5. `T-089`: block scoped search and clear search state model
6. `T-088`: read-only mode input guard model

## Acceptance Criteria

- shell integration 关闭时，prompt/cwd/command-output 相关 action disabled。
- shell integration 关闭不影响 terminal 基础输入输出。
- prompt navigation 不破坏 scrollback、focus、selection。
- command output selection/copy 不跨 pane 污染。
- read-only mode 禁止发送文本和 paste。

## Verification

- Unit tests
  - prompt marks、cwd、command status、recent commands/directories state
  - read-only send-text guard
  - command range lookup

- Widget tests
  - shell integration disabled 时相关 action disabled
  - select/copy command output 不破坏 focus
  - search next/previous match 不破坏 selection

- Manual smoke
  - 本地 zsh/bash 执行多条命令，跳转上一/下一 prompt
  - 复制上一条 command output
  - 切换 read-only 后尝试 paste/send text

## Exit Criteria

- P4 可以在 read-only、paste policy、notifications 上复用 P3 的 command status 和 action enabled state。

## Risks

- 风险：shell integration 信息不完整时 UI 表现像 bug。
- 缓解：disabled action 必须解释是 feature unavailable，而不是执行失败。

- 风险：block scoped search 诱发 renderer 级改造。
- 缓解：第一阶段只做 action 和状态模型，视觉沿用现有 shell surface。

## Added foundation slice: T-156 Shell productivity production callbacks

Status: WIRED / UNVERIFIED. Added a typed production callback and wiring
contract for prompt navigation, command output, recent directory, search,
read-only, and scrollback operations. Current `ShellScreen`,
`TerminalInputController`, runtime, and native request wiring covers the core
search, prompt navigation, command-output copy/select, recent directory,
read-only, clear-scrollback, and scrollback-export baseline. Remaining work:
verify shell-integration disabled states, output ranges, read-only coverage,
clear-scrollback semantics, and export contents before closing P3 production
wiring.
