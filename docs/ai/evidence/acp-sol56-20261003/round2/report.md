# Trail ACP / Terminal-Bench 2.1

Model: gpt-5.6-sol; reasoning: high; adapter: codex-acp@2.1.1.
Fixed 12-task selection, one attempt each, original instructions and official verifiers.
Production controller + ACP + authenticated MCP + native SSH/Command Blocks.
Harness approvals are confined to disposable containers. This is not real-UI acceptance or a full-dataset leaderboard score.

| Task | State | Reward | Approvals | Linked blocks |
|---|---|---:|---:|---:|
| large-scale-text-editing | passed | 1.0 | 5 | 5 |
| log-summary-date-ranges | passed | 1.0 | 2 | 2 |
| multi-source-data-merger | passed | 1.0 | 3 | 3 |
| fix-git | passed | 1.0 | 10 | 9 |
| merge-diff-arc-agi-task | passed | 1.0 | 20 | 19 |
| sqlite-db-truncate | passed | 1.0 | 4 | 4 |
| build-pmars | passed | 1.0 | 10 | 10 |
| compile-compcert | failed | 0.0 | 11 | — |
| sqlite-with-gcov | failed | 0.0 | 5 | 5 |
| nginx-request-logging | passed | 1.0 | 1 | 1 |
| openssl-selfsigned-cert | passed | 1.0 | 2 | 2 |
| configure-git-webserver | failed | 0.0 | 5 | 5 |

Passed: 9/12. Failed: 3. Unscored or pending: 0.

Model provenance: exact model requested and confirmed by ACP config; adapter model metadata is derived from that session selection, not an independent provider response-model echo.
Token accounting: adapter 2.1.1 returns its last inference usage, not task totals. Total task tokens remain unavailable; no misleading sum is published.
Historical API/UI results use different models and execution boundaries; they are not a controlled causal comparison.
