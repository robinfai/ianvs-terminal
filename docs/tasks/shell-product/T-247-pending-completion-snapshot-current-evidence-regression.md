# T-247 Pending completion snapshot current evidence regression

## Goal

Add regression coverage for `LocalTerminalPendingCompletionSnapshotFactory` so UI diagnostics snapshots expose the current implemented-but-unverified backlog evidence.

## Scope

- Update `example/test/shell/local_terminal_pending_completion_snapshot_factory_test.dart`.
- Assert the pending snapshot exposes T-164 as blocked with current production wiring evidence.
- Assert the pending snapshot keeps T-169 blocked by verification blockers.

## Non-goals

- Do not mark verification gates as passed.
- Do not run tests in this task.
- Do not change production runtime behavior.

## Acceptance

- The snapshot factory preserves current backlog evidence through the facade layer.
- The snapshot remains non-closeable while verification is pending.

## Verification Commands

- `flutter test example/test/shell/local_terminal_pending_completion_snapshot_factory_test.dart`

## Result

Added focused regression coverage for current completion evidence at the pending snapshot factory layer.

## Verification

Not run. The test was added but not executed in this session.

## Remaining Risks

- The new test may require formatting.
- Full objective closure still requires the complete verification plan.
