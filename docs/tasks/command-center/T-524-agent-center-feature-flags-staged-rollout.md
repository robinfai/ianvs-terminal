# T-524 Agent Center Feature Flags and Staged Rollout

## Goal

为 Agent Center lane 增加独立 feature flags 和 staged rollout 门控，让 `T-500` 到
`T-523` 的 Agent conversation、context、proposal、provider draft 和 command search
Agent actions 可以显式灰度，而不是默认和 Command Center 其他能力绑定在一起。

## Scope

- 扩展 `LocalTerminalCommandCenterConfig`，增加 Agent Center 子能力开关。
- 扩展 `CommandCenterFeatureFlags`，计算 Agent rollout stage 和 router enabled modes。
- runtime defaults 继续开启当前开发预览，显式本地配置可以关闭 Agent 子能力。
- ShellScreen 根据 flag 隐藏 Agent mode、Agent draft provider 和 command search Agent actions。
- 远程 command draft 请求只有在 `agentProviderDraft` 启用且选择 `Agent draft` 时才允许 prefer remote。
- 将 config / feature flag tests 纳入 Agent Center focused verification gate。

## Non-goals

- 不新增真实 provider 网络调用。
- 不新增远程配置、云灰度、账号实验或 telemetry。
- 不把 feature flag 类型下沉到 `packages/ianvs_terminal`。
- 不改变 proposal review、read-only、paste confirmation、shortcut isolation 或 risk confirmation 策略。

## Files In Scope

- `example/lib/features/config/local_terminal_config_models.dart`
- `example/lib/features/config/local_terminal_config_repository.dart`
- `example/lib/features/command_center/command_center_feature_flags.dart`
- `example/lib/features/shell/shell_screen*.dart`
- `example/test/config/*local_terminal_config*_test.dart`
- `example/test/command_center/command_center_feature_flags_test.dart`
- `example/test/shell/shell_screen_command_blocks_test.dart`
- `tools/agent_center_verification_gate.sh`
- `docs/tasks/command-center/T-524-agent-center-feature-flags-staged-rollout.md`

## Rollout Stages

| Stage | Required flags | Enabled surface |
| --- | --- | --- |
| `off` | `enabled=false`, `agentCenter=false`, or `agentConversation=false` | Agent mode, Agent prompt actions, and Agent provider draft are unavailable. |
| `conversationPreview` | `enabled`, `agentCenter`, `agentConversation` | Dedicated Agent composer and conversation can be shown. |
| `contextPreview` | conversation flags plus `agentContext` | Agent context chips, inline ask, and context attachments can be shown. |
| `proposalPreview` | conversation flags plus `agentCommandProposals` or `agentCommandSearchActions` | Proposal review and command search Agent actions can be shown. |
| `providerPreview` | conversation flags plus `agentProviderDraft` | `Agent draft` provider option can be selected; secret values still stay outside requests. |

All Agent sub-capabilities are gated by `enabled`, `agentCenter`, and `agentConversation`.

## Functional Acceptance

- Config defaults keep Agent sub-capabilities false.
- Runtime defaults enable the current local development preview.
- Old local `commandCenter` configs that predate Agent rollout keys receive runtime defaults for missing Agent subkeys.
- Explicit local config can keep every Agent sub-capability false.
- `CommandCenterFeatureFlags` reports the correct rollout stage.
- Router enabled modes include Agent modes only when the corresponding Agent flags are enabled.
- Shell command input hides Agent mode and `Agent draft` when rollout excludes them.
- Command search Agent actions are not wired when `agentCommandSearchActions` is false.
- Remote command draft requests pass `allowRemote=false` unless `agentProviderDraft` is enabled.

## Automated Gate

From repo root:

```bash
bash tools/agent_center_verification_gate.sh
```

The gate includes config/schema tests, feature flag tests, Agent Center tests, command search Agent action tests, and shell command block proposal tests.

## Manual QA Gate

For this thread, functional acceptance must use `@电脑` only.

| Area | Manual check | Pass condition |
| --- | --- | --- |
| Runtime preview | Launch the app with runtime defaults and inspect the universal input controls. | Agent mode is visible because runtime preview defaults are enabled. |
| Provider stage | Open the model picker. | `Agent draft` appears with boundary text only; no raw secret value appears. |
| Proposal stage | Ask Agent for a safe command and open review. | Proposal review shows explicit Insert/Run actions; insert creates a draft and does not auto-execute. |
| Search action stage | Open Command Center then Command search. | Search opens as an isolated surface and does not write hidden text to shell. Agent actions appear only when results and the rollout flag permit them. |

## Stop Conditions

Stop implementation or release verification immediately and fix before continuing if any of these happen:

- Agent mode is reachable when `agentConversation` is false.
- `Agent draft` is selectable when `agentProviderDraft` is false.
- Command search Agent actions dispatch prompts when `agentCommandSearchActions` is false.
- Remote draft requests are allowed or preferred when `agentProviderDraft` is false.
- Any Agent sub-capability ignores the Command Center total `enabled` gate.
- Runtime defaults silently disable the current documented development preview.
- Explicit local config cannot turn off Agent sub-capabilities.

## Verification Commands

```bash
bash tools/agent_center_verification_gate.sh
rg -n "agentCenter|agentConversation|agentProviderDraft|agentCommandSearchActions|Rollout Stages" \
  example/lib/features/config/local_terminal_config_models.dart \
  example/lib/features/command_center/command_center_feature_flags.dart \
  docs/tasks/command-center/T-524-agent-center-feature-flags-staged-rollout.md
```

## Done When

- Agent Center has independent config flags and computed rollout stages.
- Runtime UI respects disabled Agent modes, provider draft, and command search Agent actions.
- Config, flag, widget, and Agent focused tests pass through the shared gate.
- The rollout behavior is documented for future staged release work.
