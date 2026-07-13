# Phase 22 review — OSC 1337 ClearScrollback — 2026-07-13

## Result

The phase is accepted. Automated verification and the final cold-launch
Computer Use gate are green.

## Baseline and scope

- Start SHA: `f59d204dcaee98f5f2c366c63a583d0dbca6893c`.
- Branch: `codex/osc1337-clear-buffer-20260713`.
- Scope: exact iTerm2 OSC 1337 `ClearScrollback` / Clear Buffer behavior;
  no file, clipboard, URL, profile, process, or other host authority.

## Review and fixes

- Audited the current support matrix and the original handoff. All original
  P0/P1 gaps are closed; this was the next fully closable terminal-local OSC
  compatibility gap.
- Compared iTerm2 source commit
  `2c6c17162f5fc979e0933714803f1a4a7f1fffa3`. The public command dispatches to
  Clear Buffer, not the narrower CSI 3 J history-only operation.
- Added exact BEL/ST parsing, every-byte split recovery, a 16 KiB metadata
  ingress boundary, independent metadata policy denial, and VT220 denial.
- Clear Buffer now discards primary history, visible active-buffer content,
  screen/scrollback graphics, stale zones, saved cursor state, margins and
  origin mode. It preserves the current wrapped line and, when available, the
  visible range from the latest prompt mark through the cursor.
- Review caught and corrected the initial all-empty-screen implementation:
  iTerm2's `clearBufferSavingPrompt:YES` retains the active prompt/logical line.
  Ianvs now moves those rows to the top instead of swallowing an asynchronously
  displayed prompt.
- Native sessions now treat terminal-originated full clears like the host clear
  API: scrollback offset, frame caches and bounded transcript/replay state are
  invalidated, so cleared content cannot remain in replay storage or reappear
  after resize.
- No Dart event, JSON field or protobuf tag was added. Existing snapshot/delta
  scrollback fields carry the complete product result.

## Evidence

- Shared corpus: 29 cases and 40 required edge classes; semantic probes: 24
  intents.
- Vendor: 1,664 passed, 1 existing ignored; doc tests: 11 passed, 1 existing
  ignored.
- Native: 84 unit tests, shared-corpus execution, 476 session/real-PTY tests,
  and 3 vttest regressions passed.
- Dart/Flutter: static analysis clean; 21 PTY package tests, 460 terminal
  package tests with 1 existing skip, 928 grouped example tests, 126 Widget
  tests, and 7 documentation contract tests passed.
- macOS: 4 smoke tests, 27 real-PTY acceptance tests, and all 13 RunnerTests
  passed.
- Repository gate:
  `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 tools/verify_flutter_terminal.sh`
  completed successfully.
- Computer Use cold-launched the verifier-built app. A real zsh session emitted
  60 `CUA-OLD-*` rows and exposed a scrollbar. After the exact OSC, the screen
  contained only `CUA-AFTER-CLEAR` and a fresh prompt, the scrollbar was gone,
  upward navigation restored no old row, and `CUA-INTERACTIVE-PASS` executed
  normally with `SHELL ACTIVE`.

## Security, compatibility, and rollback

The command is terminal-local metadata and receives no host-action capability.
Near-matches are no-ops, blocked/oversized diagnostics retain counters only,
and unrelated title/color/mode/session metadata remains intact. Revert the
Phase 22 implementation commit to return this command to the bounded generic
OSC 1337 no-op; no schema migration is required.

Semantic Blocks/UpdateBlock, unsafe OSC 1337 host actions, file download/upload,
profile mutation and arbitrary custom buttons remain separate deferred work.
