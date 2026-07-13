# Phase 24 review — OSC 1337 clipboard write — 2026-07-13

## Result

Phase 24 implements iTerm2's direct Base64 text-copy command and legacy
streaming `CopyToClipboard` / `EndCopy` flow through Ianvs's existing bounded,
policy-gated clipboard product path. Targeted parser, real-PTY, Dart, widget,
macOS bridge, corpus, and static-analysis checks are green. The repository-wide
gate and final cold-launch Computer Use round trip are also green.

## Baseline and scope

- Start SHA: `a4edaf58ff22cf304f243b3ece8bfd292958d057`.
- Branch: `codex/osc1337-clipboard-capture-20260713`.
- Supported commands: `CopyToClipboard`, `EndCopy`, and direct `Copy=:`.
- Supported text targets: general clipboard everywhere the existing text
  bridge is available, plus macOS find and font pasteboards.
- No clipboard read, file transfer, URL, focus, process, profile, or arbitrary
  host-action authority is added.

## Review decisions and fixes

- Compared the current official iTerm2 documentation and source commit
  `2c6c17162f5fc979e0933714803f1a4a7f1fffa3`. The legacy form captures received
  bytes while still rendering them; the direct form carries Base64 data inside
  one OSC.
- Raw streaming ownership lives in the native filtered host observer because
  the VTE cell model cannot reconstruct exact received bytes. Both command
  boundaries still pass through the shared OSC capability/size gate first.
- Reused the existing OSC 52 clipboard-write policy, authorization prompt,
  preview, stale-session checks, status UI, and system bridge. Parser acceptance
  alone cannot touch a pasteboard.
- Capped streaming data at 4 MiB and aborts unfinished capture on RIS/session
  teardown. A new start replaces an unfinished capture; stray end is ignored.
- A real PTY test initially expected `LF`, but the PTY's enabled `ONLCR`
  processing correctly delivered `CRLF`. The assertion now verifies the bytes
  received by the terminal, which is the protocol's actual copy source.
- A direct RunnerTests invocation inherited a deleted temporary Flutter test
  listener path from the preceding integration run. Rebuilding the normal
  macOS target refreshed generated configuration; RunnerTests then passed.

## Targeted evidence

- Vendor ingress: clipboard-write classification, deny behavior that preserves
  visible stream text, 4 MiB direct wire bound, and no host-action grant.
- Native observer: BEL/ST and 1-byte split capture, direct Base64, general/find/
  font target mapping, nested replacement, overflow, RIS, invalid/stray end,
  diagnostic redaction, and VT220 denial.
- Native real PTY: two protocol-tagged clipboard events plus visible captured
  output; PTY `CRLF` byte fidelity is asserted.
- Dart runtime: protocol and named target survive authorization and reach the
  target-aware writer; legacy OSC 52 payloads keep their existing defaults.
- Flutter product: ask-policy dialog identifies iTerm2 OSC 1337, shows target,
  size and preview, then publishes protocol-specific success feedback.
- macOS: the method channel maps `c`, `find`, and `font` to the corresponding
  `NSPasteboard.Name`; 14 RunnerTests pass.
- Shared corpus: 31 cases / 43 required edge classes; semantic probes: 26.
- Package and example Flutter analysis report no issues.

## Release gates

- `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
  tools/verify_flutter_terminal.sh` exited 0. Its major suites include vendor
  Rust (1,669 passed / 1 ignored), native unit (88), native real-PTY (480),
  vttest (3), Dart PTY (21), package Flutter (464 passed / 1 skipped), docs
  contracts (7), example tests (930), standalone widget acceptance (126),
  macOS smoke (4), application real-PTY (29), and RunnerTests (14).
- The verifier rebuilt
  `example/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app`; the final
  Computer Use pass quit the prior process and cold-launched that exact bundle.
- In the live shell, streaming `CopyToClipboard=find` displayed the captured
  `CUA-STREAM-COPY` text, exposed `ITERM1337 COPY OK` with `Selection: find`,
  and an AppKit `NSPasteboard.find` read returned `CUA-STREAM-COPY`.
- Direct `Copy=:Q1VBLURJUkVDVC1DT1BZ` exposed `ITERM1337 COPY OK` with
  `Selection: c`, and an AppKit general-pasteboard read returned
  `CUA-DIRECT-COPY`. The same shell then printed
  `CUA-OSC1337-CLIPBOARD-PASS`.
- The macOS `pbpaste -pboard find` command returned no text in this environment,
  so named and general targets were verified through the corresponding AppKit
  APIs used by the product bridge instead of treating that tool behavior as a
  product failure.

## Security, compatibility, and rollback

No protobuf or frame schema changes are required. The new native event reuses
the additive `clipboard_copy` JSON envelope with `protocol=iterm1337`; old
events without a protocol continue to decode as OSC 52. Clipboard text remains
absent from diagnostics. Named-pasteboard bridge failure is reported as invalid
payload rather than silently targeting the general clipboard.

Reverting the Phase 24 commit returns these commands to bounded no-ops without
data migration. Clipboard reads, non-text MIME content, file transfer, profile
mutation, attention requests, and other OSC 1337 host actions remain separate
scopes.
