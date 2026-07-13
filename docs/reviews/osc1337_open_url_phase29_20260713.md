# Phase 29 review — OSC 1337 OpenURL — 2026-07-13

## Result

Phase 29 promotes iTerm2 `OSC 1337;OpenURL=:` from a bounded no-op to a typed,
strictly validated request behind persistent deny/ask policy, active-pane
routing, an explicit destination dialog, burst suppression, and independent
native platform validation. Terminal output never opens a URL automatically.

## Baseline and scope

- Start SHA: `1cb1ca2c2a3303b25873d85a666e3ebf14f5aae2`.
- Branch: `codex/osc1337-open-url-phase29-20260713`.
- Supported schemes: hosted `http`/`https` and hostless non-root local `file`
  URLs.
- Decoded limit: 4,096 UTF-8 bytes.
- Persistent policy: Ask every time (default) or Deny.
- Deferred: StealFocus, SetProfile, RequestAttention, background-image changes,
  custom controls, and other unrelated OSC 1337 host actions.

## Official comparison and security decision

The official iTerm2 escape-code documentation defines
`OSC 1337 ; OpenURL=: [url] ST`, with a Base64 URL, user permission, and a
feature-disable option. Ianvs implements those permission and disable semantics
without granting the parser generic host authority.

Malformed Base64/UTF-8, controls, outer whitespace, unsupported schemes,
missing HTTP hosts, remote/root-only file URLs and oversized values are
rejected.
Diagnostics contain no raw target. Only the active pane can prompt; approval is
rechecked after the dialog; concurrent/burst requests cannot stack dialogs;
resize replay cannot repeat a historical request; VT220 remains fail-closed.

## Automated evidence

- Vendored parser: valid HTTPS/file requests, malformed/unsafe/oversized
  rejection, every-byte split, Hyperlink capability denial, and no HostAction.
- Shared corpus: fragmented ST Base64 OpenURL mirrored byte-for-byte in native
  and Dart fixtures.
- Native: typed privacy-safe callback, real PTY delivery, VT220 denial, bounded
  queue behavior inherited from the common event queue, and resize non-replay.
- Dart: immediate router mapping, typed independent validation, and exhaustive
  consumers.
- Product: config defaults/roundtrip/deny alias, Defaults UI persistence,
  confirmation-before-open, explicit deny, persistent deny, inactive/unsafe
  rejection, and burst suppression.
- macOS application integration: a real child process emits OpenURL, the URL
  opener remains untouched before confirmation, and one exact call occurs only
  after the Open action while the shell remains live.

The complete verifier and cold-launch Computer Use evidence are recorded after
the final-tree gates in the completion section below.

## Compatibility and rollback

The terminal event, native callback and Dart event kinds are additive. No frame,
protobuf, or FFI schema changes are needed. Missing config defaults to Ask.
Reverting the Phase 29 implementation restores bounded no-op behavior without
affecting OSC 8 hyperlinks or Phase 28 file downloads.

## Completion evidence

- Final-tree verifier:
  `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 tools/verify_flutter_terminal.sh`
  exited 0. Its audited totals included 34 shared-corpus cases / 49 required
  edge classes / 27 semantic intents, 1,680 vendored Rust tests with one
  ignored, 11 vendored doc tests with one ignored, 98 native core unit tests,
  488 native session tests, 3 VTT tests, 475 terminal-package tests with one
  existing skip, 939 grouped example tests, 128 example widget tests, 4 macOS
  smoke tests, 33 application real-PTY tests, and 14 RunnerTests. Analysis,
  formatting, Clippy, builds, protobuf checks, and documentation contracts also
  passed in the same run.
- Cold-launch Computer Use acceptance used the verifier-built macOS debug app.
  A child `base64 -D` process emitted the exact ST-terminated OpenURL bytes for
  `https://example.test/computer-gate`. The app stayed foregrounded and showed
  the full target, destination host, and untrusted-output warning without
  opening an external application. Choosing **Deny** produced
  `OSC 1337 Open URL blocked`; the same shell then printed
  `CUAOSC29AFTERDENY` and remained interactive.
