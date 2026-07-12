# Phase 19 review — Kitty OSC 5522 MIME clipboard — 2026-07-13

## Result

The phase is accepted. Ianvs now implements a safe core of Kitty OSC 5522
through the streaming gate, native transaction assembler, typed Dart policy
boundary, product UI, and macOS pasteboard bridge. Existing xterm OSC 52 text
behavior remains compatible and independently policy-gated.

## Review and fixes

- Added bounded multi-packet `write`, `wdata`, and `walias` assembly for binary
  MIME representations, plus `read` patterns and metadata-only `.` listing.
- Added explicit `OK`, `DATA`, `DONE`, `EINVAL`, `ENOSYS`, `EPERM`, and `EIO`
  responses with sanitized correlation IDs and 4096-byte decoded DATA chunks.
- Reused clipboard write/read authorization. MIME listing never reads content
  and bypasses the read prompt; `loc=primary` fails closed with `ENOSYS` on
  macOS.
- Added 4 MiB transaction bounds, 64 MIME limits, sequential MIME ordering,
  every-byte split coverage, failed-transaction quarantine, RIS cleanup, and
  diagnostics that do not expose binary content.
- Initial macOS review canonicalized synthesized legacy PNG/TIFF/string
  pasteboard aliases instead of returning them as invalid MIME names.
- Computer Use found that raw custom MIME strings such as
  `application/octet-stream` are invalid macOS UTIs and caused an actual `EIO`.
  Custom MIME is now reversibly encoded below `dev.ianvs.terminal.mime.`, with a
  unique-pasteboard write/read regression.
- Full Widget review found that generalized prompt text changed established
  OSC 52 copy/paste wording. The original OSC 52 labels were restored while
  OSC 5522 retains protocol-specific read/write wording.

## Evidence

- Shared corpus: 27 cases and 38 required edge classes; semantic probes: 22
  intents.
- Vendor: 1,652 passed, 1 existing ignored; doc tests: 11 passed, 1 existing
  ignored.
- Native: 82 unit tests, shared-corpus execution, 471 real-PTY/session tests,
  and 3 doc tests passed.
- Dart/Flutter: static analysis clean; 21 PTY package tests, 457 terminal
  package tests with 1 existing skip, 926 grouped example tests, and 126 Widget
  tests passed.
- macOS: 4 smoke tests, 26 real-PTY acceptance tests, and all 13 RunnerTests
  passed. The Runner suite writes arbitrary MIME to a unique real pasteboard.
- Repository gate:
  `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 tools/verify_flutter_terminal.sh`
  completed successfully.
- Computer Use final gate cold-launched the verifier-built app. The real PTY
  write returned `type=write:status=DONE:id=cua-write`, UI reported
  `OSC5522 MIME WRITE OK`, and pasteboard metadata held both private encoded
  UTIs. A following no-prompt list returned `OK/DATA/DONE` and decoded exactly
  `application/octet-stream application/x-ianvs-cua`.

## Deferred scope

Password/application-name caching and `CSI ? 5522 h/l` paste-event mode remain
unsupported and cannot bypass Ianvs authorization. Kitty reference-terminal
comparison and non-macOS primary-selection integration remain separate work.
