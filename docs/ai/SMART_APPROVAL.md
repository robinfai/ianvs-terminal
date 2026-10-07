# Smart command approval

Implemented 2026-10-03. In **AI connection → Command approval**, choose
**Smart review** or **Confirm every command**. New configuration forms suggest
Smart review; legacy/unknown saved values preserve manual confirmation. Merely
changing the selection does not run a task; Save persists it on this device.

The user-authorized scope is low-risk operations and recoverable edits within
the requested task. A request to investigate and propose a remedy without
applying it permits necessary low-risk read-only diagnostics, but no changes.
An explicit ban on running commands/tools or acting before confirmation still
requires confirmation, even for read-only commands. Ambiguous scope is escalated.
Direct human command entry is unchanged.

## Decision and execution

1. Explicit terminal observation tools remain read-only and need no approval.
2. Every proposed shell command passes the common gate for API and ACP.
   Interactive keys, obvious deletion/privilege/credential operations, dynamic
   shell evaluation and selected external mutations require human confirmation.
   Known shell aliases with unavailable behavior also require confirmation.
   A leading noninteractive `sudo -n` / `sudo --non-interactive` wrapper
   (also `/usr/bin/sudo`) reaches independent model review. It grants no
   automatic permission: the reviewer receives the original full command,
   evaluates downstream effects and scope, and may still require confirmation.
   Destructive/permission-changing commands inside that wrapper remain subject
   to the mandatory rules. Other sudo forms remain manual.
3. Other commands receive an independent review using the selected model. The
   reviewer receives the exact input, current target, human task requests and
   bounded terminal evidence. Evidence/input are untrusted data. The acting
   agent's reasoning and its assertion that an action is safe grant no authority.
4. Only a structured `allow` result for this action ID, with low risk, matching
   scope, no confirmation requirement and read-only/reversible effects can pass.
   Invalid output, a tool attempt, missing context, error or a 30-second timeout
   becomes ordinary manual confirmation. There is no automatic retry or default
   allow and no cached command-prefix permission.
5. Before execution the controller rechecks the task, exact command revision,
   connection and terminal guard. Edits, pause, manual input, configuration
   changes and SSH/terminal changes revoke old decisions. Submission retains
   the existing lease, target checks, operation ID and native receipt. Unknown
   receipt outcomes cannot trigger automatic re-execution.

The model API reviewer advertises no tools. ACP uses a fresh disposable session
with no MCP server registration or host capabilities; permission requests are
denied. Reviewers cannot execute the command or approve subsequent commands.
The acting ACP tool call is resumed only after the host has the execution result.
If the agent finishes its prompt while its MCP call is waiting, the host retains
the pending review/approval or execution state. Approval remains available; after
execution, a new ACP turn receives the original receipt instead of resubmitting
the command or waiting forever for the finished turn. Pending submission queries
explicitly report that no input was sent. The agent is instructed to stop polling
when approval is pending and never infer execution from a tool timeout.
This follows ACP's provision for client-side permission policies:
[ACP tool calls and permission requests](https://agentclientprotocol.com/protocol/v1/tool-calls).

The UI shows review in progress and a short decision reason. Manual mode also
explains that “Confirm every command” is selected and where to enable smart review.
The reason follows
the original receipt into the native block timeline, including when an initially
unknown receipt is later reconciled. These records currently live with the
in-memory task, like the rest of the AI conversation.

## Limits and cost

Review adds a separate inference and its cost/latency. The real `gpt-5.6-sol` ACP
probe on this host took approximately 13 seconds per model-reviewed example;
mandatory-confirmation rules did not invoke the model. This is an observation,
not a latency guarantee. There is no extra model provider or API key setting.

The local rules are conservative tripwires, not a full shell interpreter or a
complete high-risk-command detector. AI judgment is fallible, particularly for
unknown scripts, aliases, functions, plugins and incomplete environment evidence.
Smart review is not an execution sandbox or a guarantee that every side effect
can be predicted. Keep manual mode for environments requiring deterministic
human approval. A single low-risk result does not grant blanket session access.

## Validation

On macOS 27.0.1, static analysis, 291 AI tests, both native UI scenarios and all
three real ACP review cases passed. Logs, screenshots and source hashes are in
[the acceptance evidence](evidence/smart-approval-20261003/manifest.json).

`example/test/ai/ai_approval_test.dart` covers schema validation, risk/scope,
explicit-confirmation results, mandatory confirmation, tool denial, timeouts,
late replies, exact revision binding, task/node/config changes, unknown receipts,
and ACP continuous execution with deduplicated operations. HTTP tests verify
the review request has no tool schema. Settings/widget tests cover saved mode,
review progress/reasons, light/dark and fixed-font phone layouts.

`example/tool/approval_probe.dart` runs real tool-free ACP review with
`gpt-5.6-sol`: scoped `ls -la` passed, an explicit “do not execute” request was
escalated, and a deletion example was escalated without model inference. None
of the probe's example commands execute.

`example/integration_test/input_intent_acceptance_test.dart` also exercises the
macOS app and native PTY using a controlled loopback model/reviewer: review sends
no input, the approved marker runs exactly once, the native timeline retains its
approval reason, and a deletion proposal remains unexecuted pending confirmation.
This fixture verifies wiring, not the real model's classification accuracy.

No physical iPhone or Terminal-Bench rerun is implied. The Development app is
built for validation; the installed daily app is not replaced by these tests.

### 2026-10-04 pending-approval regression

The reported development configuration omitted `approvalMode`, so the existing
legacy fallback selected manual confirmation without a reason on the card. ACP
then finished its prompt after waiting for the tool, overwriting the host's
pending-approval phase with idle and hiding the approval controls. This was a
host lifecycle bug, not evidence that the diagnostic command had executed.

The fix preserves host review/approval/execution state across prompt completion,
resumes a finished agent with the approved input and original receipt, and shows
the manual-mode reason. Three controlled ACP races cover prompt completion during
manual approval, independent review and execution, with exactly one terminal write.
English/Chinese widget tests cover the manual-mode explanation and usable controls.
302 AI tests passed on macOS 27.0.1; the final receipt changes passed the 53 focused
ACP/review tests. Scoped static analysis and `git diff --check` passed.

Real tool-free `gpt-5.6-sol` review allowed disk diagnostics under an investigate /
propose-without-cleanup request and repository inspection under a no-edits request.
It escalated an explicit no-commands request, an out-of-scope directory creation,
and deletion. The screenshot's `bash -lc` wrapper was separately escalated because
unknown login scripts can run; the same diagnostic commands without that wrapper
passed. This is an intentional uncertainty boundary. Command generation now asks
for ordinary commands/pipelines in the existing shell and avoids unnecessary login
shells. No probe command was executed. Run selected cases with
`dart run tool/approval_probe.dart diagnostic-login-shell` or omit case names to
run all cases. These observations do not guarantee every future model decision.

### 2026-10-04 citation and noninteractive sudo regression

The live development app was configured for Smart review, but its local rule
unconditionally escalated the user's `sudo -n docker ps -a --size ...` diagnostic.
Noninteractive privilege use now reaches the same independent review as other
proposals, without removing the wrapper from the actual review or execution.
This is a general wrapper rule, not a Docker command allowlist. The reviewer
distinguishes read-only use of existing permissions from privileged changes,
credential access or unknown behavior. Real tool-free `gpt-5.6-sol` probes allow
the scoped Docker diagnostic and reject an explicit no-commands request and an
out-of-scope privileged file modification. No probe command executes.

Repeated model citations also exposed a UI crash: citation keys used only the
block ID and starting line. References now deduplicate identical full ranges;
different ending lines retain separate stable keys and navigation targets.
The original provenance/ambiguous-source checks remain intact. Streaming tests
cover repeated citations, overlapping ranges, text selection, scrolling and
task removal on desktop/phone layouts. AI role text is restored to the original
sparkle icon at the user's request. The 328-test AI suite and scoped static
analysis pass; existing corrupted widget trees may require an application restart.
