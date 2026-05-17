# P5 Execution Plan: Visual And Advanced Local Features

## Objective

在基础 action/config/workspace/productivity/input-safety 稳定后，推进主题、视觉身份和高级本地效率能力，但不引入 plugin ecosystem 或 renderer rewrite 作为前置。

## Preconditions

- P1-P4 的基础路径完成并通过验收。
- 默认体验不依赖高级视觉和高级功能。
- advanced feature 必须可关闭。

## Current Baseline

- `T-091-local-terminal-visual-models` 已推进，theme preset、light/dark pair、pane visual policy、layout template local-only gate 和 renderer-risk advanced visual policy 已有纯模型表达。
- `T-094-local-terminal-advanced-visual-productivity-models` 已推进，theme import/export、profile theme override、timestamps、command pane、scrollback export 和 graphics storage policy 已有纯模型表达。
- `T-103-local-terminal-theme-repository` 已推进，theme preset list 和单个 preset export 已有独立文件 repository。
- `T-104-local-terminal-scrollback-exporter` 已推进，plain text、ANSI text 和 JSON scrollback payload 已有本地文件写出边界。
- `T-107-local-terminal-graphics-store-planner` 已推进，graphics/image storage 已有容量限制和 eviction 计划模型。
- `T-113-local-terminal-layout-template-repository` 已推进，local-only layout templates 已有本地持久化和 corrupt repair。
- `T-115-local-terminal-visual-action-reducer` 已推进，theme picker 和 scrollback export action 已有 reducer result。
- `T-126-local-layout-template-applier` 已推进，local-only layout template 可生成 P2 workspace intent。
- `T-127-layout-template-runtime-controller-integration` 已推进，layout template action 已可通过 runtime controller 更新 workspace state。
- `T-128-scrollback-export-runtime-controller-integration` 已推进，scrollback export action 已可通过 runtime controller 写出本地文件并记录路径。
- `T-132-theme-picker-runtime-controller-integration` 已推进，theme picker action 已可通过 runtime controller 记录 UI intent。

## Work Plan

1. Theme presets
   - theme preset selection。
   - light/dark paired theme。
   - profile-level theme override。
   - theme import/export。

2. Pane visual identity
   - active/inactive pane boundary。
   - split divider color。
   - terminal background。
   - selection color。
   - cursor color。

3. Layout templates
   - 常用本地 layout template。
   - template 只表达 local pane topology 和 profile intent。
   - 不保存 remote/SSH/session process state。

4. Command pane and timestamps
   - command pane 作为本地辅助入口。
   - timestamps 作为可关闭增强。
   - 不作为 shell integration 的硬依赖。

5. Scrollback and graphics policies
   - scrollback export。
   - save command output。
   - graphics/image storage policy。
   - storage limits and cleanup rules。

6. Deferred visual experiments
   - background image。
   - blur。
   - opacity。
   - variable font axis。
   - per-style font family。

## Task Breakdown

1. `T-091`: theme preset and paired light/dark theme model
2. `T-094` / `T-103` / `T-132`: profile-level theme override, import/export model/repository, and picker intent
3. `T-091`: active/inactive pane and split divider visual policy
4. `T-091` / `T-113` / `T-126` / `T-127`: layout templates local-only schema, repository, applier, and runtime controller integration
5. `T-094`: timestamps and command pane optional surfaces model
6. `T-094` / `T-104` / `T-107` / `T-128`: scrollback export and graphics storage policy model/exporter/planner/runtime integration

## Acceptance Criteria

- 不引入 plugin system 作为前置条件。
- 不触碰 renderer rewrite。
- advanced feature 可关闭。
- 默认路径仍简单，不要求用户先写配置。
- layout templates 不恢复 remote/SSH/session process state。

## Verification

- Unit tests
  - theme config parse/merge
  - profile-level theme override priority
  - layout template local-only validation
  - storage policy limit calculations

- Widget tests
  - theme preset selection changes expected shell appearance
  - active/inactive pane visuals update on focus change
  - optional surfaces disabled 时不出现入口或显示 disabled state

- Manual smoke
  - 切换 light/dark theme
  - 导入/导出 theme
  - 使用 layout template 创建 workspace
  - 导出 scrollback / command output

## Exit Criteria

- 本地 terminal v1 形成完整产品闭环：workspace、config、actions、shell productivity、input safety、notifications、hotkey window、visual identity。

## Risks

- 风险：视觉增强诱发 renderer rewrite。
- 缓解：P5 只使用现有 renderer 能承载的配置面；renderer 决策仍留给独立 Phase 5 decision point。

- 风险：高级功能默认暴露太多。
- 缓解：默认只暴露成熟路径，高级能力按配置或 command palette 发现。

## Added foundation slice: T-158 Local terminal visual production callbacks

Status: FOUNDATION / WIRED / UNVERIFIED. Added a typed production callback and
wiring contract for theme, layout template, scrollback export, command-output
export, pane visual policy, graphics storage, timestamps, command pane, and
scrollback editor operations. Current `ShellScreen`, runtime, and native wiring
covers theme picker intent, two-pane layout application, pane sizing/zoom,
historical scrollback export, and clear-scrollback support for the required
baseline. Remaining work: verify runtime/manual behavior and split optional
advanced scope such as theme import/export, layout save/load, graphics policy,
timestamps, command pane, and scrollback editor into explicit follow-up UI tasks
before claiming those items implemented.
