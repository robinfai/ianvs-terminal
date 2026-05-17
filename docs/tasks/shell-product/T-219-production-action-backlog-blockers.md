# T-219 Production action backlog blockers

## Milestone

P1 action runtime production wiring

## Intent

Record the remaining action-runtime gaps that should stay out of the current
required production baseline until real product behavior exists.

## Current blockers

No action-level implementation blocker is currently listed. Remaining work is
verification and any defects found by verification.

## Scope

- Keep these actions out of the current required production action baseline.
- Treat them as real follow-up implementation tasks, not verification-only
  cleanup.
- Preserve optional tracking where the action ID exists and can be resolved.

## Non-goals

- Do not implement placeholder callbacks that only return success.
- Do not mark P1 action runtime wiring complete.
- Do not remove the action IDs or planning coverage.

## Acceptance criteria

- Remaining action gaps are visible as implementation blockers.
- Current required production baseline remains limited to actions with real
  `ShellScreen` dispatch behavior.
- Future tasks can pick one blocker at a time without rediscovering why it was
  not previously promoted.

## Status

Updated after native `clearScrollback`, `reopenClosedTab`, `toggleReadOnly`,
`resizePane`, `swapPane`, `zoomPane`, `openThemePicker`,
`applyLayoutTemplate`, historical `exportScrollback`, and notification
preference persistence received concrete production coverage. No action-level
implementation blocker is currently listed.

`T-239` records the completion-backlog evidence correction: T-164 through T-168
should now appear as implemented but blocked by verification, instead of generic
pending placeholders.

Verification is pending. No analyze, tests, formatting, or manual UI checks have
been run for this record.
