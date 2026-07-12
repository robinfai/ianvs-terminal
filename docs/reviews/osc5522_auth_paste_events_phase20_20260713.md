# Phase 20 review — OSC 5522 authorization and paste events — 2026-07-13

## Result

The phase is accepted. Automated verification and the final Computer Use gate
are green.

## Review and fixes

- Added bounded Base64 UTF-8 `pw` and application `name` parsing across the
  native host boundary without exposing passwords in diagnostic events.
- Added exact application-name/password authorization caching scoped to one
  terminal session. Password-only requests cannot be remembered.
- Added `CSI ? 5522 h/l` mode state, DECRQM replies, JSON/protobuf frame
  transport, product status indicators, and reset/snapshot coverage.
- Added unsolicited paste-event MIME advertisement with a random, location-
  scoped, single-use 10-second token. MIME paste takes precedence over both
  plain and bracketed paste and does not read clipboard text.
- Added widget coverage for the explicit “Always allow” consent wording and
  the no-text-read/no-bracketed-paste precedence contract.
- Review found that VT220 sessions could receive a misleading supported DECRQM
  reply even though the product masks xterm-only paste mode. VT220 now reports
  `CSI ? 5522 ; 0 $ y` while xterm256 retains set/reset replies.

## Evidence

- Shared corpus: 27 cases and 38 required edge classes; semantic probes: 22
  intents.
- Vendor: 1,653 passed, 1 existing ignored; doc tests: 11 passed, 1 existing
  ignored.
- Native: 83 unit tests, shared-corpus execution, 472 real-PTY/session tests,
  and 3 vttest regressions passed.
- Dart/Flutter: static analysis clean; 21 PTY package tests, 460 terminal
  package tests with 1 existing skip, 928 grouped example tests, 126 Widget
  tests, and 7 documentation contract tests passed.
- macOS: 4 smoke tests, 26 real-PTY acceptance tests, and all 13 RunnerTests
  passed.
- Repository gate:
  `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 tools/verify_flutter_terminal.sh`
  completed successfully.
- Computer Use cold-launched the verifier-built app and ran a real-PTY probe.
  DECRQM reported reset, then set; the UI switched from `PASTE` to
  `MIME PASTE`. Command-V emitted a MIME advertisement instead of clipboard
  text, the one-time password authorized exactly one `text/plain` read, and the
  terminal printed
  `OSC5522_CUA_PASS types=text/plain payload=osc5522-cua-payload`. Product UI
  independently reported `OSC5522 MIME READ OK` and 19 bytes.

## Deferred scope

Reference-terminal comparison and non-macOS primary-selection integration
remain separate work.
