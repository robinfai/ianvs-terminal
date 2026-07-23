# Actual Replay Timeline Audit

## Audit scope

- Surface: Instant Replay timeline and shared Replay dock.
- User goal: scan command history, understand SSH boundaries, and jump to a
  command without ambiguous or overlapping cards.
- Actual evidence: `01-actual-replay.png`.
- Selected-design comparison: `02-source-actual-comparison.png`.
- Fixed deterministic reproduction: `03-fixed-replay.png`.
- Before/after comparison: `04-before-after-comparison.png`.

## Step 1 — Inspect the actual Replay timeline

Health before fix: failing.

Strengths:

- Replay controls, path, elapsed time, session metadata, and event track remain
  visible.
- Local and remote semantic states use distinct color families.

Findings:

1. P1 · Behavior/layout: shell-hook and OSC events created separate cards for
   the same command. `Command 10` overlapped `top`, and an anonymous local
   command overlapped the `ssh cloud` remote session.
2. P1 · Readability: overlapping SSH title, icon, status, and time text made
   the remote segment unreadable.
3. P2 · Content: anonymous numbering reflected raw semantic-event order, so
   visible cards began at `Command 4`, `Command 7`, and `Command 10`.
4. P2 · Density: near-zero anonymous segments rendered as slivers at the start
   of the lane.
5. Accessibility risk: overlapping labels break visual reading order and make
   the seek targets ambiguous. Screenshot evidence cannot verify keyboard or
   screen-reader behavior.

## Step 2 — Verify the corrected semantic model

Health after fix: passed in deterministic Flutter rendering.

- One open command is retained per local or remote lane.
- Anonymous hook events are enriched by later named OSC events instead of
  becoming another card.
- An anonymous local command is promoted into the SSH parent when the remote
  command becomes known.
- Duplicate finish events are ignored after the matching segment closes.
- Sub-100 ms anonymous noise is omitted from cards while the event track
  remains available.
- Remaining anonymous cards are renumbered from 1 in visible order.
- SSH title and `Remote activity · time range` are rendered on separate lines.
- Small horizontal card gaps preserve visual boundaries.

## Evidence limits

The post-fix image is a deterministic widget-test reproduction, not a second
capture of the user's live SSH session. The shared timeline model is used by
both Instant Replay and saved Recording Replay, and the regression fixture
includes the duplicate hook/OSC and anonymous-to-SSH transitions visible in
the supplied screenshot.
