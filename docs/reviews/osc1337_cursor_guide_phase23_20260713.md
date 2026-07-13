# Phase 23 review — OSC 1337 HighlightCursorLine — 2026-07-13

## Result

Phase 23 implements the iTerm2 cursor guide across parser, snapshot, native
frame transport, Dart runtime, Flutter rendering, and a real macOS PTY flow.
Targeted verification, the repository-wide gate, and final cold-launch Computer
Use acceptance are green.

## Baseline and scope

- Start SHA: `ecae85019d22381ea4c82bf21106070412e3fcff`.
- Branch: `codex/osc1337-cursor-guide-20260713`.
- Scope: terminal-local `OSC 1337;HighlightCursorLine=yes|no`; no clipboard,
  file, URL, focus, profile, process, or other host authority.

## Review decisions and fixes

- Re-audited the original handoff and current support matrix. The original
  P0/P1 compatibility gaps are closed. Blocks/UpdateBlock remains a larger
  line-mapping phase because iTerm2 folding removes and restores visual rows;
  emitting metadata without that behavior would be false product support.
- Compared current official iTerm2 documentation and source commit
  `2c6c17162f5fc979e0933714803f1a4a7f1fffa3`. Canonical values are `yes/no`,
  an empty value enables in the source, the guide follows the cursor row, and
  the state is session-local rather than a cell mutation.
- Reused the existing dormant `cursor_guide_color/use_cursor_guide` terminal
  state. Visibility and color changes now create bounded repaint damage, and
  snapshot/restore retains the state.
- Added JSON/protobuf fields instead of inferring the command from row data.
  Cursor-only deltas can clear the boolean; legacy frames default to disabled.
- The renderer paints inside the existing RenderObject. It uses the frame theme
  token, stays stable across cursor blink phases, respects DECTCEM, and keeps
  selection/search emphasis above the guide.
- Review caught and corrected a Python f-string escaping error in the
  project-local Flutter UI guideline search helper, then reran its color and
  performance queries. The implementation follows the returned no-hardcoded-
  color rule by carrying the existing terminal theme token through the frame.

## Targeted evidence

- Vendor parser: documented values, bare enable, invalid near-matches, BEL/ST,
  every-byte split, RIS persistence, snapshot restoration, appearance policy,
  payload bound, and no host-action authority.
- Native: real PTY JSON/protobuf guide state and color parity plus VT220 denial.
- Shared corpus: 30 cases and 41 required edge classes; semantic probes: 25
  intents.
- Dart: JSON/protobuf legacy and enabled parity, cursor-only enable/clear delta,
  guide-color retention, and mirrored corpus validation.
- Flutter: exact full-row geometry, frame token color/alpha, blink independence,
  and terminal cursor visibility behavior.
- Application: macOS real PTY used file signals to enable the guide, observed a
  non-empty RenderObject guide paint, then disabled it without fixed-sleep state
  inference.

## Release gates

- `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 tools/verify_flutter_terminal.sh`
  exited 0. The gate covered 30 shared OSC
  cases / 41 edge classes, 25 semantic probes, 1,668 vendor tests (1 existing
  ignored), 11 vendor doc tests (1 existing ignored), 84 native unit tests, 1
  native corpus test, 478 native session/PTY tests, 3 vttest regressions, 21
  Dart PTY-backend tests, 928 Flutter/Dart package and example tests, 126 example
  widget tests, 4 macOS smoke tests, 28 macOS real-PTY tests, and 13 RunnerTests.
- The root documentation contract suite passed all 7 tests.
- Computer Use cold-launched the verifier-built `Ianvs Terminal Dev.app`.
  `HighlightCursorLine=yes` painted a theme-token full-width guide on the live
  cursor row; the guide followed the next prompt row; `no` removed it; a final
  `CUA-GUIDE-PASS` command confirmed the real shell remained interactive.

## Security, compatibility, and rollback

The command remains an appearance-only parser capability with a 4 KiB ceiling.
Diagnostics contain counters, not payload text. Protobuf tags 6 and 30 are new;
JSON fields are optional and old payloads decode safely. Reverting the Phase 23
implementation commit returns this command to a bounded generic OSC 1337 no-op
without a data migration.

Blocks/UpdateBlock folding, annotations, legacy streaming clipboard capture,
ReportVariable, host attention, unsafe buttons, profile mutation, and file
upload/download remain separate scopes.
