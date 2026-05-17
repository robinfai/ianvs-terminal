# P4 Execution Plan: Clipboard, Notifications, Hotkey Window

## Objective

把粘贴安全、clipboard/paste 策略、通知监控和 hotkey window 变成可配置、可测试、可诊断的本地产品能力。

## Preconditions

- P1 config schema 可用，至少包含 clipboard、paste、notifications、hotkeyWindow 区域。
- P1 action registry 可用。
- P3 read-only mode 和 command status 可用。

## Current Baseline

- `T-090-local-terminal-policy-models` 已推进，clipboard/paste/notification/hotkey window 策略已有纯模型表达。
- `T-093-paste-history-policy-model` 已推进，paste history capture、dedupe、limit 和 focus-safe 约束已有纯模型表达。
- `T-097-hotkey-window-failure-state-model` 已推进，hotkey window permission/platform/bridge 失败已有可见状态模型。
- `T-105-local-terminal-notification-dispatcher` 已推进，notification rule 到 badge/toast/system notification intent 的纯决策层已建立。
- `T-106-local-terminal-paste-decision` 已推进，read-only、large/multiline confirmation 和 history capture 已有统一 paste decision。
- `T-111-local-terminal-policy-action-reducer` 已推进，policy action id 到 paste decision、notification intent、hotkey state 的纯 reducer 已建立。
- `T-129-paste-runtime-controller-integration` 已推进，paste action 已可通过 runtime controller 记录 send/confirm/block decision 和原始文本。
- `T-130-notification-runtime-controller-integration` 已推进，notification action 已可通过 runtime controller 记录 notification intent。
- `T-133-paste-history-runtime-controller-hook` 已推进，paste action 已可通过注入式 hook 记录 paste history。

## Work Plan

1. Clipboard policy
   - copy-on-select：off / clipboard。
   - right click：context menu / paste / copy selection。
   - middle click：disabled / paste。
   - OSC 52 copy/paste policy。
   - selection copy 不破坏 terminal focus。

2. Paste policy
   - bracketed paste：auto / force / plain。
   - large paste confirmation。
   - multiline paste confirmation。
   - paste history size。
   - read-only 下禁止 paste。
   - 正在进行的 paste 不被热重载中断。

3. Notification rules
   - bell。
   - command finished。
   - long-running command finished。
   - silence。
   - activity。
   - prompt ready。
   - 每条规则支持 enabled、threshold、target、focus policy。

4. Monitor UX
   - target 支持 badge、in-app toast、system notification。
   - focus policy 支持 always、unfocused、never。
   - inactive pane activity 默认 badge only。

5. Hotkey window
   - toggle hotkey window。
   - window width/height。
   - screen position。
   - animation。
   - autohide。
   - default profile / last active workspace。
   - macOS permission or platform failure state。

## Task Breakdown

1. `T-090`: clipboard policy schema model
2. `T-090` / `T-106` / `T-129`: paste policy guard for multiline/large/read-only and runtime controller decision
3. `T-093` / `T-133`: paste history policy, focus-safe contract model, and runtime hook
4. `T-090` / `T-105` / `T-130`: notification rules, monitor dispatch decision model, and runtime controller intent
5. `T-097`: hotkey window config and failure state model

## Acceptance Criteria

- large/multiline paste 受策略保护。
- read-only 禁止 paste 和 send text。
- selection copy 不破坏 terminal focus。
- OSC 52 行为受 emulation/profile/config 边界控制。
- 通知只在配置允许时出现。
- hotkey window 调用失败有可见状态。

## Verification

- Unit tests
  - large paste、multiline paste、read-only paste guard
  - bracketed paste policy
  - monitor rule threshold/focus policy matching
  - hotkey window config parsing

- Widget tests
  - paste confirmation UI 不破坏 focus
  - paste history UI 不破坏 focus
  - hotkey window action 失败时显示可见状态

- Manual smoke
  - 粘贴单行、多行、大段文本
  - 切换 read-only 后尝试 paste
  - unfocused window 下触发 command finished/bell
  - 触发 hotkey window 成功和失败路径

## Exit Criteria

- P5 可以专注于 visual/theme/advanced features，不再补输入安全和通知基础设施。

## Risks

- 风险：paste policy 太细导致配置难懂。
- 缓解：默认策略必须安全且简单，高级选项后置隐藏。

- 风险：system notification 受平台权限影响。
- 缓解：所有权限或平台失败都必须进入 visible failure state，不静默失败。

## Added foundation slice: T-157 Local terminal policy production callbacks

Status: FOUNDATION / WIRED / UNVERIFIED. Added a typed production callback and
wiring contract for clipboard, paste, notification, and hotkey-window
operations. Current `ShellScreen` wiring covers advanced paste, paste history,
read-only enforcement, notification toggles, and persisted notification
preferences for the required baseline. Remaining work: verify paste policy
cannot be bypassed, large/multiline confirmation behavior, notification focus
policy, hotkey-window visible failure behavior, and preference persistence before
closing P4 production wiring.
