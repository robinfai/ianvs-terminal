# Trail × Terminal-Bench 4.0

> Historical high-difficulty reference only. On 2026-10-01 the user moved the
> acceptance scope to a fixed Terminal-Bench 2.1 subset, initiated entirely from
> the real Trail UI. No further TB4 expansion is authorized. These controller
> harness results do not count as UI product acceptance. Running trials are
> draining and the existing records are retained, including failures.

## Purpose and pinned inputs

Evaluate Trail's terminal AI end to end: understanding a task, inspecting an
existing terminal, editing files, diagnosing failures, operating interactive
programs, and checking results. Inference comes from the requested models;
the solver remains Trail's `TerminalAiController`, `TerminalAiRuntime`, native
terminal emulator and PTY, rather than a different coding agent.

- Dataset: `harbor-framework/terminal-bench`, tag `v4.0.0`, commit
  `452bf305c6daa62fc59061d22133a7cbc7c1572e`.
- Official task directory: `tasks/`, 66 tasks. `archive/` and framework test
  fixtures are excluded.
- Evaluator: Harbor 0.23.0, isolated Python 3.12 environment.
- Local OAuth gateway: CLIProxyAPI source commit
  `fd48ea6840f5572deb53aeb5657740937ac9daaa` (v8 configuration).
- Requested model IDs: `gpt-6-luna`, `gpt-6-sol`, `gpt-6-astra`. No aliases or
  fallback model pools. Every response must report the requested model ID.
- Host validated: macOS 27.0.1 (26A434), Apple Silicon. Dedicated Colima profile
  `trail-tbench`: 10 CPU, 28 GiB RAM, sparse disk capped at 80 GiB. Docker context
  `colima-trail-tbench`; the user's global Docker context stays unchanged.

## Scenario coverage

| Category | Tasks | Representative demands on a terminal agent |
|---|---:|---|
| Software | 18 | Debug event-time/session semantics, repair database recovery, optimize frontend and algorithm performance, preserve protected source files |
| Science | 14 | Read scientific inputs, implement numerical methods, run analyses and proofs, produce validated artifacts |
| ML | 11 | Diagnose checkpoint/shard/inference problems, preserve evaluation parity, implement GPU kernels and training |
| Operations | 9 | Reconcile structured evidence, scheduling and business constraints, generate required output files |
| Hardware | 5 | Work with CAD/FreeCAD and RTL tools, generate artifacts meeting geometric or logical constraints |
| Security | 5 | Analyze task-local forensic or cryptographic material in disposable environments |
| Media | 4 | Produce design/music artifacts from supplied materials |

The benchmark primarily measures task completion, not UI aesthetics. Its tasks
do not guarantee coverage of vi/vim/k9s, manual takeover, session-hop rejection,
or mobile interaction. Existing real-PTY UI acceptance and controller tests
remain separate gates; a benchmark score cannot replace those checks.

## Execution boundary

1. Harbor builds the unmodified official task environment with its resource
   configuration. The adapter resolves and pins its container ID and task user.
2. A host-side Flutter test process loads the actual native Trail library and
   starts `docker exec -it <pinned-container> /bin/bash` as its PTY transport.
3. Trail reads the actual active terminal grid (160 columns × 48 rows) and uses
   its existing model client and tool schema. There are no direct file-edit,
   command-execution or model-solving shortcuts in the adapter.
4. The Docker shell is currently unintegrated. Trail's supported `send_keys`
   fallback handles commands and interactive tools; the prompt includes the
   previous exit code. Negotiated `run_command` and full command-block history
   are covered by the separate product acceptance suite, not this adapter.
5. The harness calls the ordinary `approve()` method for each writing action,
   scoped to this disposable container. Automatic approval exists only in the
   explicit test entry point, never the shipping application.
6. Harbor terminates agent execution at the official 28,800-second deadline and
   runs the official verifier in its declared separate environment. Only the
   original task instruction is passed to Trail. Oracle solutions, grader
   code, author explanations and host workspace files are not provided.

No OAuth tokens, local proxy key, Docker socket or host workspace are mounted
inside the task container. The model sees its task instruction and terminal
output. The host-side inference client connects to `127.0.0.1:8317/v1`.

## Model and context policy

Luna first validates a full task/environment/agent/verifier cycle. Sol and Astra
then each receive a fresh environment for every locally runnable task. Initial
results are retained; retries have separate attempt IDs and are not folded into
pass@1. A repaired harness requires a new run identifier.

The benchmark raises the configurable turn budget from the product default of
24 to 2,048 inference steps, retaining approval and stale-context checks. Model
requests have a ten-minute timeout within the overall eight-hour task limit.
History is capped at 64 messages/192,000 characters by removing complete old
exchanges while retaining the current task request. Full untrimmed events remain
in the trajectory log. Reasoning effort is recorded per run (Luna smoke: medium;
Sol/Astra batch: high).

## Resource limits and score interpretation

Four tasks exceed the approved local resources:

| Task | Official requirement | Local status |
|---|---|---|
| fp8-rmsnorm-gemm | 1 × H100 | GPU unavailable |
| jax-speedrun-gpu | 1 × H100, 16 CPU, 32 GiB RAM, 1,000 GiB storage | GPU and host resources unavailable |
| math-eval-grader | 1 × H100 | GPU unavailable |
| live-database-cutover | 16 CPU | CPU allocation unavailable |

They remain in the result matrix as `resource_unavailable`, not model failures
or successes. No cloud machines are purchased automatically. Native ARM images
and amd64 emulation on this Mac may differ from the official reference platform;
Docker does not enforce every task's storage quota. Results are a local product
evaluation, not a claimed leaderboard-comparable score.

A read-only check of the previously used `ssh cloud` host found 2 CPU, 3,944 MiB
RAM and no detected NVIDIA GPU. It cannot supply the missing 16-CPU/H100 capacity;
no benchmark workload or software was installed there.

Record separately: verifier reward, model failure, harness failure, environment
build failure, timeout, unavailable resources, request count, input/output/cache
tokens, wall time, requested/reported model IDs, reasoning effort, source revision
and dataset revision. Never treat a zero process exit alone as a verifier pass.

## Local gateway and reproducibility

Runtime state lives in ignored `tmp/terminal-bench/`. The gateway configuration,
client key and OAuth files have private permissions. OAuth uses its own login
session, separate from the desktop Codex process. The gateway binds localhost,
disables management and discovery, and uses no paid third-party relay.

The attributed Tibo approach is CLIProxyAPI with Codex OAuth and a local
OpenAI-compatible endpoint. The original post was inaccessible to the web
reader; the attribution is not a claim that the entire post was verified.
OpenAI's `codex-responses-api-proxy` is a different API-key proxy and is not what
this setup runs.

The helper `tools/terminal_bench/proxy.py` exposes `init`, `login`, `start`, and
`preflight`. Build the pinned CLIProxyAPI checkout with Go into
`tmp/terminal-bench/bin/cliproxyapi` before using it. `init` preserves an existing
client key; `login` opens a separate OpenAI login; `start` runs the foreground
gateway. Stop that process to stop the gateway. OAuth tokens are never printed
by the helper or included in benchmark configuration files.

Reproduction (from repository root after the private proxy setup):

```sh
DOCKER_CONTEXT=colima-trail-tbench \
TRAIL_FLUTTER=/Users/robinfai/development/flutter/bin/flutter \
PYTHONPATH="$PWD" \
tmp/terminal-bench/venv/bin/harbor run \
  -p /private/tmp/trail-terminal-bench/dataset/tasks/session-window-debug \
  -a tools.terminal_bench.trail_agent:TrailAgent -m gpt-6-luna \
  --ak reasoning_effort=medium -n 1 \
  -o tmp/terminal-bench/jobs --job-name luna-smoke-01
```

The complete local matrix is resumable, retains all 66 rows per model, and uses
fresh environments for each model:

```sh
tmp/terminal-bench/venv/bin/python tools/terminal_bench/run_matrix.py \
  --dataset /private/tmp/trail-terminal-bench/dataset --run sol-astra-v1
```

Use the same run ID to resume an interrupted queue. A changed agent source or
configuration requires a new run ID. Scheduler v2 admits at most two trials,
with declared resources totaling at most 10 CPU, 24 GiB RAM and 50 GiB task disk
(leaving space for build cache and the VM). It adopts confirmed live Harbor
processes when resuming, uses a process lock to prevent duplicate schedulers,
prioritizes warm task images and software tasks, and defers environment retries.
The schedule is recorded separately in `scheduler.json`; agent source remains
frozen for the run. Images and volumes belonging to completed trials are removed afterwards if
unused, and unused build cache is kept near 20 GiB. Only the dedicated VM is
affected. Interrupted indexing is recovered from Harbor's finished trial result;
environment failures get at most one further attempt. Provider authentication/quota failures stop the
queue with the remaining entries marked pending.

## Observed results

2026-10-01: all three exact model IDs completed a real function-call preflight.
Luna completed the `session-window-debug` end-to-end smoke run in 5m 1s with
22 model requests. Official reward: **0.0**; verifier subtests: **3/7 passed**.
No harness exception occurred. This proves that inference, terminal actions,
artifact transfer and the official verifier are connected; it does not claim
that Luna solved the task. Runtime evidence is under
`tmp/terminal-bench/jobs/luna-smoke-01/`.

Sol subsequently completed the same task with high reasoning effort in 23 model
requests. Official reward remains **0.0**, with **6/7 verifier subtests passed**.
Its four self-authored regression tests passing did not imply full correctness;
the report keeps the official failure. Evidence is under
`tmp/terminal-bench/matrix/sol-astra-v1/session-window-debug-gpt-6-sol-1/`.

Sol/Astra outcomes are recorded as they complete in
`tmp/terminal-bench/matrix/sol-astra-v1/results.json`. The initial matrix contains
124 runnable entries and 8 resource-unavailable entries, covering all 66 tasks
for each model. The scope changed before completion; pending entries will remain
unattempted. No full-matrix score is claimed.

The first Astra `session-window-debug` attempt stopped on `invalid_action`
before its proposed input was sent. Its raw rejected reply was not recorded,
so the exact invalid argument is unknown. The tool schema omitted length limits
that the client enforced. A general product repair now declares those limits,
records rejected proposal diagnostics in the optional harness, and permits at
most two corrected proposals, each still subject to approval. Execution failures
are never retried this way. Unit tests cover approval, cancellation and bounds.
The two in-flight `data-anonymization` trials overlapped source editing and are
diagnostic only; their source identity is not claimed to match the original run.

## Sources

- [Terminal-Bench 4.0 announcement](https://www.tbench.ai/news/terminal-bench-4-0)
- [Pinned official release](https://github.com/harbor-framework/terminal-bench/releases/tag/v4.0.0)
- [Harbor agent documentation](https://docs.harborframework.com/core-concepts/agents/pre-integrated-agents)
- [CLIProxyAPI source](https://github.com/router-for-me/CLIProxyAPI)
- [Attributed Tibo post](https://x.com/thsottiaux/status/2076119366647894371)
- [OpenAI OAuth token sharing](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)
- [OpenAI model guidance](https://developers.openai.com/api/docs/guides/latest-model)
