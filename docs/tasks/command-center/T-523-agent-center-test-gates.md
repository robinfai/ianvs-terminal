# T-523 Agent Center Test Gates and Regression Suite

## Goal

沉淀 Agent Center lane 的自动化回归门、人工验收矩阵和 stop conditions，确保 `T-500`
到 `T-522` 的输入归属、上下文隐私、provider boundary 和命令 proposal 安全不会在后续
迭代中回退。

## Scope

- 固化 Agent Center focused regression gate，覆盖 `test/agent_center`、command mode
  router、`Ctrl-R` Agent actions 和 shell command block proposal/review flows。
- 要求测试使用 mock Agent adapters，不依赖 provider credentials，不发起真实 provider
  network calls。
- 记录 Agent 专属人工 QA，验证 dedicated Agent conversation、context chips、provider
  secret boundary、proposal review/insert/run 和 command search Agent actions。
- 把本 gate 接入 `T-322`，作为 Command Center verification gates 的 Agent lane 最小命令。

## Non-goals

- 不实现 `T-524` feature flags 或 staged rollout。
- 不替代 `docs/TESTING.md` 的 full example regression。
- 不接入真实 Agent provider。
- 不放宽 read-only、paste confirmation、shortcut isolation、terminal input policy 或风险确认策略。

## Files In Scope

- `tools/agent_center_verification_gate.sh`
- `docs/tasks/command-center/T-523-agent-center-test-gates.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- `docs/tasks/command-center/README.md`

## Functional Acceptance

- 一条脚本能从 repo 根目录运行 Agent Center focused regression gate。
- gate 先跑 `flutter analyze`，再跑 Agent lane 相关 widget/unit tests。
- gate 清空常见 provider secret 环境变量；测试必须继续通过。
- T-322 能直接引用该脚本作为 Agent Center lane 最小命令。
- Manual QA 明确要求只通过真实 UI 操作验收，不能用测试替代功能验收。

## Automated Gate

从 repo 根目录运行：

```bash
bash tools/agent_center_verification_gate.sh
```

该脚本展开为：

```bash
cd example
flutter analyze
DEEPSEEK_API_KEY= OPENAI_API_KEY= ANTHROPIC_API_KEY= GOOGLE_API_KEY= GROQ_API_KEY= MISTRAL_API_KEY= flutter test \
  test/config/local_terminal_config_models_test.dart \
  test/config/local_terminal_config_repository_test.dart \
  test/config/local_terminal_config_bootstrap_test.dart \
  test/command_center/command_center_feature_flags_test.dart \
  test/agent_center \
  test/command_center/command_center_mode_router_test.dart \
  test/command_center/command_search_overlay_controller_test.dart \
  test/command_center/command_search_overlay_test.dart \
  test/shell/shell_screen_command_blocks_test.dart
```

## Coverage Map

| Area | Regression coverage |
| --- | --- |
| Mode taxonomy and input ownership | `agent_mode_test.dart`, `input_ownership_router_test.dart`, `command_center_mode_router_test.dart` |
| Conversation and mock runtime | `agent_conversation_models_test.dart`, `agent_runtime_adapter_test.dart`, `agent_conversation_pane_test.dart`, `shell_screen_command_blocks_test.dart` |
| Context snapshots, chips, privacy, budget | `agent_context_builder_test.dart`, `agent_context_attachment_test.dart`, `agent_context_chips_test.dart`, `agent_context_privacy_filter_test.dart`, `shell_screen_command_blocks_test.dart` |
| NL routing and visible route UI | `agent_intent_router_test.dart`, `agent_detection_policy_test.dart`, `route_decision_chip_test.dart` |
| Command proposal safety and terminal bridge | `agent_command_safety_pipeline_test.dart`, `shell_screen_command_blocks_test.dart` |
| Command search Agent actions | `command_search_overlay_controller_test.dart`, `command_search_overlay_test.dart`, `shell_screen_command_blocks_test.dart` |
| Session memory and block context | `shell_screen_command_blocks_test.dart` |
| Provider config and secret boundary | `agent_provider_config_test.dart`, `shell_screen_command_blocks_test.dart` |
| Feature flags and staged rollout | `local_terminal_config_models_test.dart`, `local_terminal_config_repository_test.dart`, `local_terminal_config_bootstrap_test.dart`, `command_center_feature_flags_test.dart`, `shell_screen_command_blocks_test.dart` |

## Manual QA Gate

Run these checks in a live app after the automated gate passes. For this thread, functional
acceptance must use `@电脑` only.

| Area | Manual check | Pass condition |
| --- | --- | --- |
| Agent mode ownership | Switch to Agent mode, type a question, and submit. | The message appears in the Agent conversation; terminal prompt receives no text and no command executes. |
| Dedicated conversation | Ask for a safe command suggestion. | Mock response streams into the Agent pane, not terminal scrollback; proposal is visible as reviewable UI. |
| Proposal insert | Open proposal review and choose insert. | Command is inserted as a terminal draft only; execution does not happen during insert. |
| Proposal run | Run only a low-risk eligible proposal from review. | Execution requires explicit review action and still respects read-only, paste, and risk gates. |
| Provider boundary | Select or view the Agent draft provider. | UI shows the provider boundary label, not any raw secret value. |
| Context privacy | Use a secret-shaped cwd or context value. | Agent request/context/memory prompt shows `[REDACTED]` and stays within the context budget. |
| Command search Agent actions | Open `Ctrl-R`, choose explain/debug Agent action for a command. | Agent receives the action prompt and command metadata; PTY receives no hidden write. |

## Stop Conditions

Stop implementation or release verification immediately and fix before continuing if any of these happen:

- Any Agent or natural-language route silently writes to the PTY.
- Agent tests require provider credentials, real provider network calls, or machine-specific secrets.
- Raw secret values appear in Agent request payloads, context snapshots, memory prompts, provider config, UI labels, logs, or snapshots.
- Agent context leaves process without redaction and size-budget filtering.
- Proposal insert executes a command instead of creating an editable draft.
- Proposal run bypasses review, read-only, paste confirmation, shortcut isolation, terminal input policy, risk confirmation, or direct-run eligibility.
- Command search Agent actions write prompt text to the shell instead of the Agent conversation.
- Stale selected-block, last-failed-block, cwd, or session summary context is attached after the visible source changed.
- Manual functional acceptance uses any UI automation path other than `@电脑` in this thread.

## Verification Commands

```bash
bash tools/agent_center_verification_gate.sh
rg -n "Agent Center lane|agent_center_verification_gate|provider credentials|context privacy|@电脑" \
  docs/tasks/command-center/T-322-command-center-verification-gates.md \
  docs/tasks/command-center/T-523-agent-center-test-gates.md \
  docs/tasks/command-center/README.md
```

## Done When

- Agent Center lane has a single focused gate that future tasks can run before rollout.
- The gate passes with provider secret variables empty.
- T-322 includes the Agent Center lane command and Agent stop conditions.
- Manual QA is explicit enough to catch input ownership, privacy, proposal execution, provider boundary, and command search regressions.
