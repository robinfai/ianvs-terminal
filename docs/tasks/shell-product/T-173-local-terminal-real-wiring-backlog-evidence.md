# T-173 Local terminal real wiring backlog evidence

## Milestone

P0-P5 cross-milestone execution control

## Intent

Provide a stable evidence builder for the T-164 through T-169 real wiring
backlog so final completion reporting does not rely on ad-hoc task-status lists.

## Scope

- Represent each real wiring backlog task as explicit evidence.
- Default every task to pending.
- Convert backlog evidence into completion backlog items.
- Build a completion evidence report from a production wiring bundle and backlog
  evidence.

## Deliverables

- `example/lib/features/shell/local_terminal_real_wiring_backlog_evidence.dart`
- `example/test/shell/local_terminal_real_wiring_backlog_evidence_test.dart`

## Acceptance criteria

- T-164 through T-169 default to pending.
- Verified task evidence can close the completion evidence report only when the
  production wiring bundle can also close.
- Completion evidence remains explicit and does not infer verification from
  foundation artifacts.

## Status

Foundation implemented. Not verified in this session.
