# T-072 Wrapped-Line Search Regression

## Goal

Add a native/runtime search regression for matches that span wrapped terminal rows.

## Scope

- Native `Session::search` behavior across wrapped rows.
- Runtime/facade expectations for search matches that begin on one wrapped row and continue on the next.
- Audit update for xterm.js #3671.

## Non-goals

- Do not add xterm.js SearchAddon or decorations.
- Do not change prompt-marker behavior.
- Do not optimize search performance; that belongs to T-076.

## Files In Scope

- `native/core/src/session.rs`
- `native/core/tests/session_test.rs`
- `packages/flutterm_terminal/test/terminal_runtime_controller_test.dart`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- `Session::search` currently extracts each row independently and calls `collect_text_matches` per row; the `wrapped` flag is not used to join logical wrapped lines.
- `cargo test --test session_test session_searches` passes only single-row scrollback search.
- `cargo test --test session_test session_search_empty_query_returns_no_matches` passes after the audit probe, proving empty search is covered separately.

## Functional Acceptance

- A failing-first native test demonstrates a query spanning a soft-wrapped row boundary.
- The fixed implementation returns a match with correct row, start/end columns, text, and scrollback offset.
- Empty-query behavior remains covered and does not regress.
- The audit row for wrapped-line search is updated with the final passing command.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd native/core
cargo test --test session_test wrapped_line_search
cargo test --test session_test session_search_empty_query_returns_no_matches
```

## Manual QA

1. Print a long line that wraps naturally in the example app.
2. Search for a substring that crosses the visual wrap boundary.
3. Confirm the search result scrolls to and highlights the logical match.

## Done When

- Wrapped-line search has a named regression.
- Empty search remains covered.
- The audit links this task or marks the row `Covered` with evidence.

## Risks / Follow-ups

- Search match coordinates may need a compatibility decision if a logical match spans more than one visual row.
