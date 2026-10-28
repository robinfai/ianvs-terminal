# Shared conversation and native terminal timeline

## Ownership and composition

`UnifiedTerminalTimeline` remains the outer list. The host retains task IDs,
reading anchors and source-session identities. Conversation rows use
`ianvs_agent_chat` (`ChatMessageFrame`, `ChatMessageBody`, `ChatToolCard`,
`ChatPlanCard`, `ChatDecisionCard`, `ChatCodePreview`, `PromptInput.hosted`).
Native command blocks remain `TerminalCommandBlocksView` records. They are never
converted to Markdown or cloned into a tool's output details.

The visible order is user request, streamed explanation, tool/plan update,
command proposal, native command block, and follow-up explanation. A tool update
revises its existing row instead of moving it to the tail. The first live block
also follows existing conversation when the initial terminal history is empty.
When the host receipt supplies the block ID, the canonical action row occupies
that same timeline position and the previously observed native row is deduplicated.

## Identity and state boundaries

`toolCallId` is scoped by task and prompt turn. An explicit bridge `rawInput`
with `server=trail_terminal`, a supported write tool, `arguments.operation_id`
and matching operation arguments can resolve to the host's action. The action's
receipt establishes `sessionId + blockId`. Command text similarity, call order
and ACP `completed` status cannot establish a link or successful execution.

Host approval still validates the proposal revision, target and ownership.
`ChatDecisionCard` receives the existing host widgets; it has no approval logic.
ACP permission requests remain controlled by the ACP runtime and its scoped
bridge policy. Neither display path can authorize the other.

All terminal bridge tool cards suppress default raw output/content details.
Linked cards provide navigation to the original proposal or command block.
Unlinked cards retain only protocol activity; they do not invent a terminal
receipt. A native block's running state and exit code remain authoritative.

## Input, mobile and interactive programs

`PromptInput.hosted` supplies the shared surface while Terminal keeps its single
editor, focus node, IME handling, Shell history, completion, context chips and
send guards. The mobile editor stack remains mounted when its chrome changes.
Phone typography remains fixed per repository policy. Shared frames use the
same content inset for user and assistant rows, bounded reading widths, and
vertical role placement on narrow surfaces.

Stopping generation cancels inference, not an accepted command. The native
block continues updating and interruption remains a separate host action.
Full-screen programs continue in the real terminal using the existing takeover
and read-only observation controls. No conversation card creates a PTY or
acquires independent input ownership.

## Retention and recovery

The existing session-local task store retains transcript row IDs, tool/plan
projections, operation associations, tool expansion, native block references,
reading anchors and draft state across task switches. Late events from a retired
turn cannot mutate a replacement task. Existing receipt reconciliation and
retained source controllers handle reconnects without resubmitting commands.

History also survives quitting and reopening Trail. Atomic JSON files in the
application support directory's `ai-history` folder store content, draft, reading
position, expansions and native cell snapshots. Changes are debounced; native
output is sampled every two seconds. Backgrounding, closing a session and normal
quit flush the latest snapshots. Shutdown captures before native teardown and
waits for writes, including saves from recently closed sessions. A failed normal
exit save cancels that exit; storage errors are shown in the AI status.

Recovered tasks are read-only history. Pending approvals become revoked,
submitted commands with no verified outcome become unknown, and a previously
running native block is not declared successful. Archived sources have a unique
`saved-` identity, never reuse a new PTY with the same session ID, and cannot send
input. Starting a new task explicitly returns to live work. Credentials, runtime
handles and executable approvals are not persisted.

Snapshots are bounded: up to 128 blocks per source and the last 2,048 native rows
per block, with original source coordinates and an evicted-prefix indicator.
Each task document is limited to 16 MiB; startup loads at most 64 documents and
64 MiB, ordered by last modification time. Older files remain on disk.
Multiple Shell sessions in the same process can view a recovered task: untouched
views do not write, changed fields are merged through a shared write queue, and
fold/expansion changes use set additions/removals. Each document saves only its
own sources' native view. Concurrent edits of the same scalar field use the last
save; separate processes are not coordinated by this store. Corrupt or unknown-schema files are preserved
and skipped. This is bounded local history, not an unlimited terminal recording;
forced termination can lose changes since the last completed save.

## Dependency release

Development currently resolves the sibling packages locally. Formal consumers
must use published versions containing these APIs. Existing pub.dev chat 0.2.0
and runtime 0.1.0 predate the split core contracts; they are not compatible
substitutes. Publish core first, then chat/runtime, and only then switch Terminal
constraints and lockfile after a clean hosted dependency resolution. Publication
and its final consumer switch must not be simulated with an unavailable version.

## Validation

Regression coverage includes tool delta deduplication, preserved prose order,
completed-tool versus pending-command separation, explicit operation receipt
association, stale-event rejection, task retention, empty-history live ordering,
mobile/desktop reading layout, literal code display, input/history/IME ownership,
independent cancellation and canonical native output. Restart tests cover real
atomic files, native source ID reuse, invalid documents, stale approvals,
reading anchors, delayed Shell restoration, closed-session pending writes,
failed-save retry, multi-session field/fold merging, newest-valid selection and
pre-teardown capture.

Verified locally on 2026-10-28 with Flutter 3.44.8: application suite 3,866
passed / 2 skipped, changed production and test files passed static analysis,
and mobile dark / desktop wide conversation captures were visually inspected.
The suite used the local ACP native library and sibling development packages.
Hosted-package consumption and remote CI for this iteration remain release gates;
these local results do not claim physical-device restart testing.
