# Phase 25 review — OSC 1337 annotations — 2026-07-13

## Result

Phase 25 implements iTerm2 `AddAnnotation` and `AddHiddenAnnotation`, including
legacy note aliases, through Ianvs's existing bounded per-session annotation UI.
Targeted parser, policy, corpus, native real-PTY, Dart, widget, application
real-PTY, and static-analysis checks are green. The repository-wide verifier and
final cold-launch Computer Use acceptance are also green.

## Baseline and scope

- Start SHA: `15eedb8b0406a3bfc2739a7a43aa96e7f1724ddb`.
- Branch: `codex/osc1337-block-folding-20260713`.
- Supported commands: `AddAnnotation`, `AddHiddenAnnotation`, and the legacy
  `AddNote` / `AddHiddenNote` aliases.
- Supported grammar: official message-only, `length|message`, and
  `message|length|x|y` forms.
- No clipboard, file, URL, process, profile, notification, focus, or other host
  authority is added.

## Review decisions and fixes

- Compared the official iTerm2 documentation and source commit
  `2c6c17162f5fc979e0933714803f1a4a7f1fffa3`. Default length, coordinate clamp,
  validation, legacy aliases, and visible-versus-hidden behavior follow the
  upstream implementation.
- Reused the product's existing annotation sheet, session badge, removal and
  cleanup paths. Visible notes open only for the active pane; hidden and
  inactive-pane notes cannot steal focus.
- The parser records absolute rows. Native mapping converts them to retained
  rows and resolves selected text after processing the whole PTY read. Product
  frame refresh retries text extraction when a command precedes its target
  bytes.
- Bounds are 16 KiB per OSC, 1,024 Unicode scalar values per message, 4,096
  cells per range, 80 product entries, and the existing bounded native event
  queue. Text extraction retries are capped at 16 subsequent frames. Review
  fixes changed the Dart message check from UTF-16 code units to Unicode scalar
  values and added annotation-specific ingress overflow recovery.
- Final diff review fixed alternate-screen coordinates after discarded-row
  scrolling, bounded empty-range refresh work, and made an already-open sheet
  update when later visible annotations arrive. The widget test now sends its
  second note after the sheet is open instead of batching both beforehand.
- Annotation diagnostics retain only source, visibility, counts, and range
  coordinates. Notes and selected terminal text are redacted.
- Initial concurrent Flutter analysis commands raced over generated ephemeral
  files. Serial execution passed and is the authoritative product result; this
  was a test-tool concurrency issue, not a product defect.

## Block folding scope decision

Official iTerm2 source confirms that `Block` / `UpdateBlock` fold and unfold
visual rows in the text-view virtualization layer. Ianvs currently models every
frame as contiguous `viewportStartRow + relativeRow`. Correct support therefore
requires non-contiguous row mapping synchronized across rendering, scrolling,
selection, search, graphics, resize, and replay. Metadata-only events or blank
painted rows would leave layout and interaction semantics wrong, so block
folding remains a dedicated future foundation phase and is not claimed here.

## Targeted evidence

- Shared corpus: 32 cases / 46 required edge classes; semantic probes: 27.
- Vendor: official and legacy forms, default/explicit/coordinate ranges,
  malformed and every-byte splits, alternate-screen scroll coordinates, policy
  denial, overflow recovery, and no host-action capability.
- Native: selected-text resolution, absolute/retained coordinate mapping,
  privacy-safe diagnostics, real PTY visible/hidden events, and VT220 denial.
- Dart: immediate typed event routing and exhaustive compatibility handling.
- Flutter product: hidden badge without modal; visible active-pane sheet opens
  once and live-updates for later notes; application real PTY verifies note
  text, selected text, badge count, and continued terminal output.

## Release gates

- `VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1
  tools/verify_flutter_terminal.sh` exited 0. Its major suites include vendor
  Rust (1,672 passed / 1 ignored), native unit (89), native real-PTY (482),
  vttest (3), Dart PTY (21), package Flutter (464 passed / 1 skipped), docs
  contracts (7), example tests (930), standalone widget acceptance (128),
  macOS smoke (4), application real-PTY (30), and RunnerTests (14).
- The verifier rebuilt
  `example/build/macos/Build/Products/Debug/Ianvs Terminal Dev.app`; final
  Computer Use quit the previous process and cold-launched that exact bundle.
- A real zsh command emitted hidden `away` and visible `visible` annotations in
  one burst, followed by `CUA-OSC1337-ANNOTATION-PASS`. After one stable render
  cycle, the visible command automatically opened the sheet, whose accessibility
  tree showed both notes, both target texts, and `2 annotations`.
- Closing the sheet exposed the `2 annotations` badge and preserved the PASS
  marker. A subsequent shell command printed `CUA-ANNOTATION-INTERACTIVE`,
  proving focus/input/output remained healthy after the modal lifecycle.

## Security, compatibility, and rollback

The new event is additive JSON only and does not change frame/protobuf schemas.
Metadata denial and VT220 gating fail closed; printable target text continues to
render. Reverting the Phase 25 commit returns these commands to bounded no-ops
without data migration. Blocks/UpdateBlock and OSC 1337 host actions remain
separate deferred scopes.
