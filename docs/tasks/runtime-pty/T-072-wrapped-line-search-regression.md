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
- `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- `Session::search` now groups consecutive wrapped visual rows into logical rows before searching, then maps each match start back to the visual row, start column, logical end column, text, and scrollback offset.
- `cargo test --manifest-path native/core/Cargo.toml --test session_test wrapped_line_search` passes and covers a query spanning a soft-wrap boundary.
- `cargo test --manifest-path native/core/Cargo.toml --test session_test session_search` passes the existing scrollback, empty-query, substring-mode, and regex-mode search coverage.

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

- Wrapped-line search has a named regression. Done:
  `session_wrapped_line_search_matches_across_visual_rows`.
- Empty search remains covered. Done: `session_search_empty_query_returns_no_matches`.
- The audit links this task or marks the row `Covered` with evidence. Done:
  `TERMINAL_XTERM_RECENT_FIX_AUDIT.md` records the focused commands.

## Risks / Follow-ups

- Search match coordinates keep the existing JSON shape. A match that spans
  multiple visual rows reports the start visual row and start column, with
  `end_col` extending by the logical match width from that start column.
