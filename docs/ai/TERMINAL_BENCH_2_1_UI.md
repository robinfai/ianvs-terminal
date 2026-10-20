# Trail / Terminal-Bench 2.1 UI acceptance

The product acceptance scope was fixed on 2026-10-01, before any TB2.1 model
attempt. The official repository is `harbor-framework/terminal-bench-2-1`, commit
`7131e4375048a0e408a8fb404b5f499d726b695b`. The machine-readable selection in
`tools/terminal_bench/tb21-selection.json` records task tree IDs, instruction
hashes, official resources and deadlines. Failures never cause substitutions.
No official hidden tests or solutions were reviewed during selection.

| Coverage | Fixed tasks |
|---|---|
| Files and data | large-scale-text-editing; log-summary-date-ranges; multi-source-data-merger |
| Debugging and recovery | fix-git; merge-diff-arc-agi-task; sqlite-db-truncate |
| Build | build-pmars; compile-compcert; sqlite-with-gcov |
| Operations | nginx-request-logging; openssl-selfsigned-cert; configure-git-webserver |

All selected tasks require no GPU, 1–2 CPUs, 2–4 GiB RAM and 10 GiB storage.
They fit the approved 10-CPU/28-GiB/80-GiB Colima VM when run sequentially.
Published image digests and actual architecture/emulation must be recorded for
each attempt. Network/package drift and emulation can still cause environment
failures. This selected-set product evaluation is not a leaderboard submission.

## Fixed coverage

- macOS: Luna first runs `log-summary-date-ranges`, `build-pmars` and
  `nginx-request-logging`; Sol and Astra each run all 12 tasks independently.
- macOS Command Block: the user cancelled phone testing on 2026-10-01 and
  substituted Block mode for that coverage. Run the same three representative
  tasks with Luna, Sol and Astra; keep Normal and Block results separate.
- Each platform/model/task starts in a fresh official environment. Preserve the
  official instruction verbatim and the official verifier. Never put solutions,
  hidden tests, their failure details or parent-agent suggestions in the prompt.

## UI boundary

Start the actual production Trail UI. Select the connection, model and terminal
through the UI, enter the official instruction in the AI input, click Send,
review and click each approval in the UI, and observe completion. Automation may
tap, enter text, scroll, capture screenshots and record visible state. It must
not invoke controllers, send task commands out of band, solve tasks or silently
approve proposals. Task-environment setup and the official verifier may run
outside the UI. Transport attachment is setup, not a solver command.

`example/lib/ui_acceptance_main.dart` enables only standard Flutter driver UI
commands and invokes production startup. It has no custom command handler,
configuration override or task injection. The earlier controller benchmark and
the integration test with direct setup calls are supplemental engineering
checks only; they do not count toward this UI coverage.

Capture configuration/model selection, the submitted prompt, first approval,
important execution states, final UI and official verifier result. Keep raw
credentials out of screenshots and records. Audit actual returned model IDs,
elapsed wall time, input/output/cache tokens, HTTP failures and rejected tool
proposals. A model's success statement is never a verifier result.

## Failure and reference policy

Record model task failure, product defect, evaluation-program defect and
environment failure separately. Preserve first attempts and all later attempts.
When a product defect is fixed, repeat the same UI scenario with the same model.
For key unresolved task failures, run an established reference agent with the
same exact model ID, original prompt, official deadline and clean environment;
this is a separate comparison, never a replacement Trail result. Runs after
viewing hidden tests or task-specific changes are diagnostic and excluded from
the initial acceptance aggregate.

## Separate product regression scenarios

Track local and SSH connections; Block/Normal selection and negotiation fallback;
long-output scrolling and expansion; waiting and interruption; vim/top full-screen
entry and return; rejected-proposal recovery; network/error recovery. Use short
disposable fixtures, UI controls and evidence. Report these independently from
Terminal-Bench scores.

## Current state

All 36 fixed UI coverage cells are complete. The latest recorded attempt for
each cell has 27 official rewards of 1, eight rewards of 0, and one unscored
verifier timeout. All 45 original attempts remain available, including setup
errors, interruptions and repeats after product fixes. This is selected-set
product acceptance, not a leaderboard score.

| Model | Normal reward 1 / planned | Block reward 1 / planned |
|---|---:|---:|
| gpt-6-luna | 2 / 3 | 2 / 3 |
| gpt-6-sol | 9 / 12 | 2 / 3 |
| gpt-6-astra | 9 / 12 | 3 / 3 |

Sol Normal data merger has no score because its official verifier timed out.
Astra Normal pMARS has reward 1 with a retained adapter timeout caused by
completion-recording delay. Every selected attempt's returned model ID was
verified by the passive response audit. Per-attempt timing, token accounting,
failure attribution and reference results are in the generated local
`tmp/terminal-bench/ui-2-1/report.md`, `report.json` and `attempts.csv`.

Selection is frozen. The first macOS Normal/Luna task (`log-summary-date-ranges`)
completed through UI entry and one explicit UI approval. All three responses
reported `gpt-6-luna`; token accounting was 7,420 input, 676 output and 1,536 cached.
Official verifier reward was 0.0. A fresh same-model Terminus 2 comparison passed
with reward 1.0 (80.9 seconds; 30,871 input / 1,153 output / 13,824 cache tokens).
That difference alone does not establish a Trail defect. The later Sol UI run
passed the same task with reward 1.0: its proposal parsed the event severity
field, whereas Luna's Normal and Block proposals scanned severity words across
the complete message. Luna's output overcounted ERROR while INFO and WARNING
matched. The evidence therefore supports model task failure, with severity
overcounting as the inferred cause; no hidden tests were reviewed. The original
attempt records remain intact and separate assessment files retain this
attribution. An earlier setup attempt is retained
as an evaluation-program error: asynchronous settings loading overwrote the audit
endpoint, and its unaudited proposal was rejected before any terminal action.
The first pMARS UI attempt reached the official 900-second deadline and received
reward 0.0. The UI driver had a long interruption before a generic continuation;
record this as an evaluation-program failure, rather than solely model failure.
Eight actions were approved in the UI. A fresh Normal/Luna pMARS repeat passed
the official verifier after nine approvals and one generic continuation, with
19 responses all reporting `gpt-6-luna` (474,945 input / 1,887 output / 406,528
cached tokens). Nginx Normal/Luna passed the official
verifier (reward 1.0) after seven UI approvals.

The first three Luna Block attempts are retained. Log summary received reward
0.0. pMARS and Nginx received reward 1.0, but both unexpectedly fell back to
Normal during execution, so they do not establish full Block coverage. No
hidden tests were reviewed. A same-model Terminus 2 pMARS reference also passed.

The fallback was reproduced in a separate SSH fixture with three AI commands,
each printing 180 lines. The 80 ms output check could observe new output while
the 150 ms ownership poll still held the previous ready lease. Refreshing
ownership alone was insufficient: a decoded render frame can also lag behind
the native ready receipt. Attribution now pairs current native ownership with
the native live screen and starts comparison only after Block is active.
Genuine output outside a command still falls back to Normal. Both races failed
before their fixes and are covered by the six passing mode tests; static
analysis passed. A fresh real UI fixture kept all three completed Blocks,
loaded output back to line 1, and preserved scroll position during native
wheel movement (visible range moved from line 17 to 91 and back to 54).
Evidence and source hashes are under `product-regression/` in the local report
directory. The Nginx Block repeat passed the official verifier with reward 1.0,
six responses all reporting `gpt-6-luna`, two UI approvals, and 30,306 input /
860 output / 13,312 cache tokens. Both commands completed in Blocks without
fallback. The pMARS Block repeat also passed (reward 1.0), with 21 responses all
reporting `gpt-6-luna`, 360,256 input / 1,417 output / 312,832 cache tokens, and
11 UI approval clicks (one stale proposal was rejected; ten commands were
sent). Execution stayed in Blocks through dependency failures, recovery,
compilation and final verification. These repeats used the same original
prompts and fresh environments after the generic product fix.

Vim and top both reached the full terminal renderer in the separate local
regression. While checking top exit, changing Flutter Driver text emulation
with an attached text client caused an engine crash in
`FlutterTextInputPlugin setEditingState:`. This is retained as an evaluation
program issue pending native-keyboard reproduction, not evidence of a product
exit defect. The UI entry point now accepts
`--dart-define=TRAIL_UI_NATIVE_KEYBOARD=true` to select native keyboard input
before any client attaches. This changes only the standard driver's input
backend; production startup remains unchanged. Native-keyboard runs use real
OS key/paste events and do not call Driver `enter_text`.

The native-keyboard repeat on macOS 27.0.1 passed top and Vim entry/exit from Block, followed by manual Block recovery (exit 0). The active IME held physical letters as preedit; committing them delivered top `q` and Vim `ZQ`. A separate 3-second wait completed, Ctrl-C interrupted `sleep 30` at 4.3 seconds with exit 130, and a loopback connection refusal was followed by a successful command. Evidence 22–30 is retained separately from benchmark scores. The development Keychain startup blocker was also fixed and validated with zero platform credential calls across two real app startup cycles.

The first six Sol Normal tasks have completed UI execution. Log summary,
million-row Vim editing, Git recovery, bundle/ARC merge and truncated SQLite
recovery all passed the official verifier (reward 1.0). Multi-source data merge
completed in the UI, but its official verifier exceeded the unchanged
900-second deadline and produced no reward. A read-only process snapshot found
`uv` still running with low resource usage; the underlying verification timeout
cause is unconfirmed. It is recorded separately from model failures and passes.
That attempt also exercised request-timeout recovery: an upstream response took
477.932 seconds, outliving the client's 45-second deadline. One generic UI
continuation recovered without replaying terminal actions. The late response
did not execute an action. Report generation now reconciles late inference
usage by request start time, preserving the original UI completion records.

Sol pMARS exposed a separate history-compaction defect: after a long turn,
a generic continuation lost the original user goal. Two regression tests failed
before the fix. Compaction now preserves every human request and explicitly
selected block, removes obsolete automatic screen snapshots and complete old
tool exchanges, and keeps the latest observation. If the human constraints alone
exceed the bound, it reports a conversation limit instead of silently deleting
them. All 30 AI controller/client tests pass, including request/size limits,
selected context, protocol pairing and recovery through a new conversation.
The fresh same-model, same-prompt UI repeat reached its 24-step turn limit;
a generic continuation retained the goal and resumed Debian/pMARS work without
re-entering the original prompt. The official build result is tracked separately.
The earlier pMARS
attempt also suffered slow Debian package downloads and stale-index 404s, so its
unchanged-deadline failure is recorded with both product and environment factors.

The later Sol Normal OpenSSL certificate task passed the official verifier
(reward 1.0) after four individually reviewed native UI approvals and no
follow-ups. Six responses reported `gpt-6-sol`, using 30,694 input / 1,609 output /
17,664 cached tokens. Its verifier spent several minutes in APT setup before
finishing; no hidden test contents were inspected. The fresh Sol pMARS repeat
finished with reward 0.0 and an agent timeout despite the successful goal-retention
regression. The same-model Terminus 2 reference also timed out with reward 0.0
(915.36 seconds total; 138,359 input / 2,213 output / 104,448 cached tokens).
That result alone does not isolate the cause. That
reference overlaps later verification and Nginx setup on the shared VM/network;
these are not controlled bandwidth comparisons.

Sol Normal Nginx also passed the official verifier (reward 1.0), with six
individually reviewed UI approvals and one generic continuation after a step
limit. All 29 responses reported `gpt-6-sol`, using 522,554 input / 2,439 output /
476,032 cached tokens. The original goal remained available after continuation.

The independent recovery scenarios are complete. AI settings displayed a
connection error for an unavailable loopback endpoint and succeeded after the
original endpoint was restored; the failing draft was never saved. SSH with an
explicit `/bin/sh` automatically fell from Block to Normal and disabled Block
with an incomplete-negotiation explanation. In a clean repeat, exiting SSH kept
Normal active and the tab announced that Block was available for manual
restoration. Manual selection restored Block and a new command exited 0.
Native menu screenshots and command output are retained in regression evidence
33–43. An earlier Driver interaction with the native menu timed out and failed
to deliver dependent input; those observations are preserved as an evaluation
tool issue and are not used to claim successful recovery.

Sol Normal Git-to-web deployment passed the official verifier (reward 1.0),
with nine approved actions, 29 responses reporting `gpt-6-sol`, and 1,306,542
input / 3,410 output / 559,488 cached tokens. A step-limit continuation retained
the task. A later proposed exit from the container to inspect host ports was
rejected; the follow-up only restated the existing isolation boundary. Both
follow-ups and the rejection are retained in the attempt evidence. No host
configuration was changed and no solving hints were supplied.

Sol Normal SQLite/gcov passed the official verifier (reward 1.0) after thirteen
approved actions and one generic step-limit continuation. All 46 responses
reported `gpt-6-sol`, using 2,164,782 input / 2,777 output / 595,072 cached tokens.
The real UI showed compilation from the vendored source, installation into PATH,
the SQLite version, and generated coverage files before official verification.

Sol Normal CompCert received official reward 0.0, with no Harbor exception. The
model ended with an explicit incomplete final before the unchanged 40-minute
deadline; the UI record was written at 14:50:58 UTC. The run had 29 approved actions with
three generic continuations. All 85 responses reported `gpt-6-sol`, using
4,080,512 input / 5,864 output / 803,072 cached tokens. A transient DNS failure
prevented initial package installation, then recovered without parent changes.
CompCert failed with the installed Coq version; the attempted compatible Coq
source build also exited 2, and its incremental retry was still running at the
final response. The model reported a linker segmentation fault, but that raw
diagnostic was not independently inspected. Record this as task failure with
environment delay; the relative contributions remain unconfirmed. A separate
same-model Terminus 2 reference was started afterward and overlaps later Block
tasks on the shared VM/network, so it is not a controlled timing comparison.

The Sol CompCert Terminus 2 reference subsequently passed (official reward 1.0,
no exception): 35 episodes, 594,586 input / 5,231 output / 537,984 cached tokens.
Agent wall time was 14:51:52–15:31:36 UTC. A shared unobserved wall-clock gap
affected the surrounding evaluation period, and the run overlapped other tasks
on the VM/network; treat this as a result comparison, not a controlled timing
or causal comparison. No reference solution or hidden test contents were read.

Sol Block log summary passed the official verifier (reward 1.0). Both task
commands completed in Blocks without fallback; no follow-up was needed. Three
responses reported `gpt-6-sol`, using 9,760 input / 737 output / 4,608 cached
tokens. The initial SSH transport block is retained separately from the two
completed task commands. Native sidebar tabs were used after the top tab bar
overflowed, allowing direct access to the active session's mode menu.

Sol Block pMARS attempt 01 was interrupted during evaluation: the UI showed an
AI request timeout while package installation remained active, followed by an
approximately 20-minute unobserved wall-clock gap. Preserve its three approvals
and one generic continuation, but exclude it from model capability conclusions.
A clean attempt 02 began through the same actual SSH Block UI at 15:25:17 UTC.

Sol Block pMARS attempt 02 received official reward 0.0 and reached the original
900-second agent timeout.
The UI retained Block throughout twelve approvals and two generic continuations;
no action was approved after the deadline. It downloaded and checked Debian
source archive hashes but did not finish installing build tools. Stale package
indexes produced 404s; the final 9.7 MB index update took 3 min 41 sec at
43.8 kB/s. All 59 audited responses reported `gpt-6-sol`, using 2,293,906 input /
3,332 output / 641,920 cached tokens. Classify as task failure with environment
delay; environment and strategy contributions are not isolated.

Sol Block Nginx completed its UI flow with seven approved actions and no
follow-up. The real UI showed valid syntax, successful home and custom 404
responses, and detailed access logs after recovery from an empty PID-file
reload error. All eleven responses reported `gpt-6-sol`, using 101,263 input /
1,812 output / 72,704 cached tokens. The official verifier passed with reward
1.0 and no exception.

Astra Normal text editing completed the actual UI flow: Vim and byte comparison
both exited 0 after about 2 min 13 sec. Two actions were approved. A premature
incomplete final and one stale Ctrl-Z proposal required two generic continuations;
the stale pause was rejected after completion became visible, and no signal was
sent. All 21 responses reported `gpt-6-astra`, using 366,196 input / 2,019 output /
329,856 cached tokens. Official verification passed with reward 1.0 and no
exception.

Astra Normal log summary completed with two approved actions and no follow-up.
The real terminal reported 164 files processed, printed the CSV, and exited 0.
All three responses reported `gpt-6-astra`, using 19,406 input / 787 output /
8,064 cached tokens. Official verification passed with reward 1.0 and no
exception.

Astra Normal data merger completed with two native approved actions and no
follow-up. The UI showed four unique users, three field conflicts, and successful
read-back validation of both output files. All three responses reported
`gpt-6-astra`, using 12,301 input / 1,727 output / 4,736 cached tokens. Official
verification passed with reward 1.0 and no exception.

Astra Normal Git recovery completed with four approved actions and no follow-up.
The real UI showed the detached commit preserved on a branch, a merge into
master, one conflict resolved, a clean working tree and tree comparison exit 0.
All five responses reported `gpt-6-astra`, using 30,447 input / 751 output /
16,000 cached tokens. No push was performed. Official verification returned
reward 0.0 with no exception. Actual terminal actions matched approvals; the
exact acceptance mismatch remains unknown. Record as model task failure without
claiming a Trail defect. A fresh same-model Terminus 2 reference was started;
no hidden test or reference solution content was inspected. The first reference
attempt failed before inference: tmux installation timed out after 120 seconds.
It produced no model reward. An unchanged fresh-environment retry also failed
at the same 120-second tmux installation timeout, before any inference. Both
original results remain intact. A separately labelled setup diagnostic extends
only the dependency-install command timeout from 120 to 300 seconds and its
overall install budget from 240 to 330 seconds; Harbor's 360-second setup limit,
the original task, solver, model and 900-second task limit are unchanged.
This diagnostic passed official verification with reward 1.0 and no exception.
Setup took 202.75 seconds and agent execution 58.77 seconds. All six audited
responses reported `gpt-6-astra`; usage was 16,661 input / 862 output / 3,840
cached tokens. Preserve its diagnostic label. The Trail UI failure's exact
acceptance mismatch remains unknown; reference success alone does not establish
a product defect or a causal explanation.

Astra Normal merge-diff attempt 01 was interrupted by macOS screen lock after
the original prompt was submitted. The initial proposal was never approved;
zero task commands executed. The official result is reward 0 with
`AgentTimeoutError` at the unchanged 900-second deadline. Classify this as an
evaluation interruption, exclude it from model ability conclusions, and retry
in a fresh environment after native UI access is restored.

Native UI access resumed on 2026-10-02 (Asia/Shanghai). During new-tab setup,
the long-running development app crashed in Flutter's
`AccessibilityBridge::CreateRemoveReparentedNodesUpdate` after repeated AXTree
update errors. The system crash report confirms `EXC_BAD_ACCESS`; this is a new
unresolved finding, not a successful regression check. The app was relaunched
and the still-live merge-diff attempt 02 container was retained. Original-prompt
submission occurred after relaunch, at 17:31:12 UTC, under the original deadline.
Related upstream reports cover [macOS OverlayPortal semantics](https://github.com/flutter/flutter/issues/187198)
and [ListView/Tooltip AXTree errors](https://github.com/flutter/flutter/issues/182444),
but their relationship to this crash is not proven. No accessibility feature or
SDK version was changed to avoid the failure. Evidence is retained in
`product-regression/44-accessibility-crash.json`.

The resumed Astra Normal merge-diff UI attempt completed with ten native
approvals and one generic continuation. The model installed missing Git/Python,
handled timezone prompts, merged both bundle branches, resolved the implementation
conflict, and passed all three public examples plus clean-tree checks. Its 21
responses all reported `gpt-6-astra`, using 620,314 input / 2,364 output / 479,488
cached tokens. Official verification returned reward 0.0 with no exception;
record model task failure with the exact acceptance mismatch unknown. A fresh
default-configuration same-model Terminus 2 reference passed with reward 1.0
and no exception. Its 15 responses all reported `gpt-6-astra`; usage was 81,040
input / 1,422 output / 52,736 cached tokens, with 181.76 seconds of agent
execution. No reference solution or hidden test content was inspected; the
exact reason for the different UI result remains unknown.

Astra Normal SQLite truncation recovery completed in the real UI with three
approved actions and no follow-up. It decoded ten surviving records from the
remaining database page, wrote the required JSON and validated readback. All
four responses reported `gpt-6-astra`, using 19,726 input / 1,205 output / 8,448
cached tokens. Official verification passed with reward 1.0 and no exception.

Astra Normal pMARS completed its real UI task with nine approvals and two generic
continuations after 24-step limits during package downloads. It built Debian
0.9.4-1 without X11, retained the source tree, installed the binary, produced
`Results: 12 30 8`, and demonstrated an actual cdb single step. All 58 responses
reported `gpt-6-astra`, using 3,122,630 input / 3,098 output / 638,464 cached tokens.
Official reward was 1.0 with `AgentTimeoutError`: final completion was captured
at 18:01:31.064 UTC, before the 18:01:38.611 deadline, but supplemental screenshot
and recording latency delayed the adapter's completion file until 18:01:47.486.
Keep the raw exception and classify this as passed with evaluation recording
delay; do not attribute this adapter timeout to model failure. The original
record is unchanged, with timing evidence in `evaluation-note.json`. Future UI
completion is recorded before supplemental screenshots.

Astra Normal OpenSSL completed with one approved action and no follow-up. The
real terminal confirmed successful Python verification, the requested subject
and validity, and mode 600 on both private-key-bearing files. Both responses
reported `gpt-6-astra`, using 7,226 input / 1,346 output / 1,408 cached tokens.
Official verification passed with reward 1.0 and no exception.

Astra Normal Nginx completed with two approved actions and no follow-up. The
real terminal confirmed configuration syntax, HTTP 200 and custom 404 responses,
and access logs containing timestamps, statuses and quoted user agents. All 13
responses reported `gpt-6-astra`, using 204,481 input / 1,674 output / 160,768
cached tokens. Official verification passed with reward 1.0 and no exception.

Astra Normal Git-to-web deployment completed with four approved actions and no
follow-up. The terminal showed a non-root clone, commit, push and HTTP readback
returning `hello world`, with exit 0. All nine responses reported `gpt-6-astra`,
using 102,364 input / 1,422 output / 69,248 cached tokens. Official verification
passed with reward 1.0 and no exception.

Astra Normal SQLite/gcov completed with five approved actions and one generic
continuation after the step limit. The terminal showed compilation from the
vendored snapshot, a PATH symlink, an SQL query returning 42, and `.gcno`/`.gcda`
files for both the shell and SQLite core. All 25 responses reported
`gpt-6-astra`, using 990,213 input / 1,773 output / 406,016 cached tokens.
Official verification passed with reward 1.0 and no exception.

Astra Normal CompCert attempt 01 was interrupted by macOS screen lock while
approval for compatible Coq setup was pending. Four actions were approved and
one generic continuation was sent; the unsupported system Coq was correctly
rejected by configure. The pending install proposal never executed. All 27
responses reported `gpt-6-astra`, using 1,270,022 input / 1,576 output / 465,408
cached tokens. Official verification returned reward 0 with `AgentTimeoutError`
at the unchanged 40-minute deadline. Exclude this interruption from model-ability
conclusions. After unlock the stale proposal was rejected in native UI before
preparing a fresh repeat. Rebinding the native app restored its accessibility
tree; no new runtime or engine error was observed during this recovery.

Astra Normal CompCert attempt 02 reached the unchanged 40-minute deadline with
official reward 0 and `AgentTimeoutError`. Fifteen actions were individually
approved and four generic continuations retained the original task. All 61
responses reported `gpt-6-astra`, using 3,333,930 input / 4,672 output / 790,400
cached tokens. Real UI diagnostics confirmed that the default nine-job Coq
build exceeded the official 4 GiB container limit (`oom_kill=1`, opam exit 31).
The model retried with one job and reused build files, but the chained CompCert
build was still waiting at the deadline. No completed compiler or successful
source test was observed. Record task failure with environment delay; the
memory limit and compilation strategy both contributed. A default same-model
Terminus 2 reference was started during the recovery and shares the VM/network;
it is a result comparison, not a controlled timing comparison.

Astra Block log summary passed the official verifier (reward 1.0, no exception).
Both task commands completed in Blocks with exit 0 and no fallback; the initial
SSH transport is retained separately. Two native approvals were needed and no
follow-up was sent. All three responses reported `gpt-6-astra`, using 8,663
input / 965 output / 4,096 cached tokens.

Astra Block pMARS passed the official verifier (reward 1.0, no exception).
Eight native approvals and no follow-ups built Debian 0.9.4-1, preserved the
source, installed the requested binary without X11, produced `Results: 12 30 8`,
and exercised an actual cdb single step followed by explicit quit (status 4).
All task actions stayed in Blocks. All 20 responses reported `gpt-6-astra`,
using 767,586 input / 1,397 output / 700,416 cached tokens.

Astra Block Nginx passed the official verifier (reward 1.0, no exception).
Two native approvals and no follow-ups produced valid configuration, HTTP 200
and custom 404 responses, and access logs with timestamps, methods, statuses
and quoted user agents. The first inspection encountered a missing `ps` command;
the model completed setup without depending on it. All task actions remained
in Blocks. All ten responses reported `gpt-6-astra`, using 146,147 input /
1,779 output / 112,384 cached tokens.

The default Astra CompCert Terminus 2 reference also received reward 0.0, with
no Harbor exception. Total wall time was 39 minutes 37 seconds; usage was
802,828 input / 3,344 output / 747,136 cached tokens. All 51 audited responses
reported `gpt-6-astra`. Its execution overlapped
the UI recovery and later Block tasks on the shared VM/network. This comparison
does not isolate strategy, infrastructure or product effects. Only result and
passive audit metadata were inspected; no reference trajectory or hidden test
contents were read.

Native tab activation exposed a separate accessibility defect: the outer
semantic buttons excluded their child button semantics without supplying tap
actions. A regression reproduced failure to change the active tab through
`SemanticsAction.tap`. Activation and close now explicitly forward the semantic
action to their existing handlers. All 28 tab/mode tests passed and static
analysis was clean. The shared fake backend now answers composer ownership
polls with an explicit unknown state, avoiding unrelated missing-response
errors and perpetual rebuilds in UI tests. After hot reload, native accessibility
clicks switched from tab 11 to 9 and closed the completed tab 11 while retaining
tab 9. Evidence 45–46 is separate from benchmark scoring. This fix does not
establish a cause or resolution for the earlier native Flutter engine crash.

Broader shell regression exposed an incorrect Material surface around the AI
settings entry. Its ListTile now has an explicit transparent Material ancestor,
resolving the Flutter paint assertion. All 27 related shell/sidebar tests passed,
in addition to the 28 tab/mode tests above; static analysis passed. Real native
UI opened Defaults and AI settings after hot reload with no runtime errors.
Evidence 47–48 also shows the development file-storage explanation; no settings
were changed during this check.

A metadata-only evidence integrity audit covered the 45 completed attempt
records: every retained original instruction matched the frozen manifest hash
and every attempt had UI screenshots. Forty-four also retained exact original
prompt text in UI diagnostics, including the older nested Luna log format. The
initial Luna log setup error lacks machine-readable UI prompt evidence and
remains excluded. Results are saved in `evidence-integrity.json`; this audit did
not read hidden tests, reference solutions or credentials. Reproduce it with
`python3 tools/terminal_bench/ui_evidence_audit.py`. PNG header validation checks
that an image with positive dimensions is retained; visual correctness still
depends on the recorded UI inspection. The original completion's model-identity
field is reported separately from the reconciled passive audit in `ui_report.py`.

Phone testing was cancelled by the user after installation; no phone task result
is counted or required. Its planned coverage is now macOS Block mode. The local OAuth gateway is
already running on `127.0.0.1:8317`; all three requested exact model IDs previously
returned real tool calls. The earlier Luna command/vim integration test passed,
but is not counted as one of the selected tasks or new UI regression scenarios.

TB4 stopped expanding when the scope changed. Preserve its raw records as
high-difficulty reference, including controller/harness limitations and failures.

## Official sources

- [Terminal-Bench 2.1 announcement](https://www.tbench.ai/news/terminal-bench-2-1)
- [Pinned dataset](https://github.com/harbor-framework/terminal-bench-2-1/tree/7131e4375048a0e408a8fb404b5f499d726b695b)
- [Official run instructions](https://github.com/harbor-framework/terminal-bench-2-1/blob/7131e4375048a0e408a8fb404b5f499d726b695b/tasks/README.md)
