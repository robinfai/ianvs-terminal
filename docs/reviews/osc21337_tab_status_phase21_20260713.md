# Phase 21 review — OSC 21337 tab status — 2026-07-13

## Result

The phase is accepted. Automated verification and the final Computer Use gate
are green.

## Review and fixes

- Added the public iTerm2 OSC 21337 fields `indicator`, `status`, and
  `status-color` as typed incremental updates. Omitted fields retain state,
  empty values clear, and invalid colors do not overwrite valid state.
- Added escaped semicolon/backslash parsing, xterm color normalization, a 4 KiB
  appearance ingress limit, a 256-scalar status limit, control filtering, and
  BEL/ST/split-input coverage.
- Routed presence/value pairs through native and Dart without logging raw
  status text. RIS, pane close, and session close clear product state.
- Added active-pane tab UI with an indicator dot, compact status label,
  readable color fallback, text-scaling bounds, tooltip, and accessibility
  semantics. Split tabs follow the active pane.
- Review found two implementation defects and fixed both before acceptance:
  the sealed-event compatibility switches initially omitted the new event, and
  the native pending queue initially treated incremental updates as safely
  coalescible. The latter could have lost a prior set when a partial clear
  followed quickly, so OSC 21337 updates now preserve order.
- Corrected the OSC 5522 matrix row left stale after Phase 20; password/name
  caching and paste-event mode are implemented and verified, not deferred.

## Evidence

- Shared corpus: 28 cases and 39 required edge classes; semantic probes: 23
  intents.
- Vendor: 1,658 passed, 1 existing ignored; doc tests: 11 passed, 1 existing
  ignored.
- Native: 84 unit tests, shared-corpus execution, 474 real-PTY/session tests,
  and 3 vttest regressions passed.
- Dart/Flutter: static analysis clean; 21 PTY package tests, 460 terminal
  package tests with 1 existing skip, 928 grouped example tests, 126 Widget
  tests, and 7 documentation contract tests passed.
- macOS: 4 smoke tests, 26 real-PTY acceptance tests, and all 13 RunnerTests
  passed.
- Repository gate:
  `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 tools/verify_flutter_terminal.sh`
  completed successfully.
- Computer Use cold-launched the verifier-built app. A real shell emitted the
  set probe and printed `OSC21337_CUA_SET`; the tab showed an orange dot and
  `Working`, while its accessibility label reported `status Working, status
  indicator active`. A `status-color=` partial clear printed
  `OSC21337_CUA_PARTIAL` and retained both dot and text. A final empty
  `indicator=;status=;status-color=` sequence printed `OSC21337_CUA_CLEAR` and
  removed both visual and semantic status.

## Deferred scope

Later unpublished extension keys and additional reference-terminal comparison
remain separate work. OSC 21337 remains appearance-only and grants no host
authority.
