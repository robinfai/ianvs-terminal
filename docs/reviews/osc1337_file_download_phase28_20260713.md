# Phase 28 review — OSC 1337 incoming file download — 2026-07-13

## Result

Phase 28 closes the incoming non-inline OSC 1337 file gap behind an explicit,
active-pane Save decision. Transfer bytes remain bounded and native-owned until
one exact, one-shot read; no automatic host write or local upload authority is
added.

## Baseline and scope

- Start SHA: `1893fba4b96b767770b139e6c99b04c3091f498e`.
- Branch: `codex/osc1337-download-phase28-20260713`.
- Supported: single `File` downloads with absent/false `inline`, and
  `MultipartFile` / `FilePart` / `FileEnd` downloads.
- Retained limits: 16 MiB total decoded bytes and at most eight pending choices
  per session.
- User boundary: active-pane metadata prompt followed by native Save panel;
  cancel, close, timeout and background delivery discard the bytes.
- Deferred: outgoing upload and unrelated OSC 1337 host actions.

## Official comparison and product decision

The implementation was compared with the official
[iTerm2 images protocol](https://iterm2.com/documentation-images.html): missing
or zero `inline` denotes download; single and multipart forms share the same
arguments; file data is Base64 and the filename is Base64-encoded metadata.
iTerm2 may download directly, while Ianvs deliberately requires an explicit
Save destination because PTY output is untrusted host input.

`RequestUpload` would cross the opposite trust boundary by revealing local
data. This phase keeps it unsupported, cancels the protocol request and emits
only visible blocked feedback. It does not open a picker or read a file.

## Architecture and review findings

- Native drains completed parser transfers immediately, validates download
  direction/status/decoded size, sanitizes the basename, and moves bytes into a
  session-scoped queue. Event JSON contains no payload bytes.
- The FFI copy requires the exact expected size and consumes the item only
  after a successful copy. A separate discard operation releases abandoned
  choices. No public C header exists in this repository; Dart resolves both
  additive exports from the bundled dynamic library.
- Dart validates source, positive opaque ID, size, basename length, controls,
  separators and dot path components before allowing take/discard. Bytes are
  requested only after the native save panel returns a destination.
- The product presents only active-pane events. Snackbar action ownership is
  claimed synchronously so replacing the prompt with completion feedback cannot
  run its close callback and discard the same transfer a second time.
- Transcript resize replay drains transfer records, notifications and protocol
  responses without re-emitting historical host effects.
- Writer injection makes the final byte write testable without granting tests
  filesystem authority. AppKit independently reduces the suggested name to a
  bounded basename before assigning `NSSavePanel.nameFieldStringValue`.

## Automated evidence

Targeted Rust, Dart and Flutter checks cover:

- single-file handoff, exact bytes, size mismatch, filename sanitization,
  aggregate/count bounds, one-shot consume and explicit discard;
- real interactive PTY delivery plus transcript resize non-replay;
- FFI argument bounds and optional-backend behavior;
- immediate typed event routing with metadata-only payloads and invalid-path
  rejection;
- active-pane prompt, Save-before-copy ordering, exact write bytes,
  native-panel cancel and inactive-pane cleanup;
- explicit `RequestUpload` denial and parser cancellation response.

The complete final-tree command passed with exit code 0:

```bash
VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 \
  tools/verify_flutter_terminal.sh
```

It covered 33 corpus cases / 49 required edge classes, 27 semantic intents,
vendored Rust 1,678 passed / 1 ignored plus 11 passed / 1 ignored doc tests,
native core 97/97, native real-PTY/session 485/485, VTT 3/3, terminal package
474 passed / 1 existing skip, example grouped tests 933/933, complete example
Widget tests 128/128, macOS smoke 4/4, application real PTY 32/32, Debug app
rebuild and RunnerTests 14/14. Formatting, strict Clippy, generated protobuf,
mirrored corpus, docs contracts, analysis and benchmark smoke are included in
the same gate.

Cold-launch `@电脑` acceptance used the verifier-built standalone
`Ianvs Terminal Dev.app` with a real zsh child. A byte-exact 14-byte download
visibly produced `Received osc-phase28.txt (14 B)` and the accessible **Save**
action. Save opened the native panel with `osc-phase28.txt` as the suggested
basename. Cancel returned to the terminal with `Received file discarded`, and
`CUAOSC28AFTERCANCEL` executed afterward in the same pane with `SHELL ACTIVE`.
A separate `RequestUpload=format=tgz` probe visibly produced
`File upload request blocked`, opened no picker, and left a live prompt.

The first probe command was a harmless miss because the Computer Use text
injector removed underscores from a temporary path. A retry using an
alphanumeric path reached the same cold-launched app and supplied the evidence
above; the failed command never emitted OSC bytes.

## Security, compatibility and rollback

The PTY controls neither the destination nor an automatic write. Raw bytes are
absent from event serialization and diagnostics, filenames cannot supply a
path, local upload is denied, pending memory is capped, and replay cannot repeat
the action. The change is additive at callback/FFI/runtime layers and leaves
frame/protobuf and inline-image behavior unchanged. Reverting Phase 28 returns
non-inline downloads to bounded parser-internal no-op behavior.
