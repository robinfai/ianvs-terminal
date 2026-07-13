# iTerm2 OSC 1337 incoming file download

## Support contract

Ianvs supports the incoming, non-inline subset of iTerm2's OSC 1337 file
protocol:

```text
OSC 1337 ; File=[arguments] : base64-data ST-or-BEL
OSC 1337 ; MultipartFile=[arguments] ST-or-BEL
OSC 1337 ; FilePart=base64-data ST-or-BEL
OSC 1337 ; FileEnd ST-or-BEL
```

`inline` absent or `inline=0` is a download. `inline=1` continues through the
separate bounded inline-graphics path. The optional `name` argument is Base64;
the optional `size` must agree with the decoded byte length when present.

The wire behavior was compared with the official
[iTerm2 images protocol](https://iterm2.com/documentation-images.html). Ianvs
intentionally differs at the host boundary: it never writes an incoming file
automatically. The active pane shows a bounded metadata prompt and the user must
choose **Save**, then choose a destination in the native macOS save panel.

## Trust and resource boundary

- The parser admits at most 16 MiB for a transfer. Native session storage also
  caps all pending download bytes at 16 MiB and retains at most eight items.
- Callback JSON contains only `source`, an opaque decimal `transferId`, a
  sanitized basename and decoded byte size. File bytes never enter event JSON,
  logs, Flutter state or diagnostics.
- A file can be copied from native storage exactly once and only when the
  caller supplies the exact advertised size. Cancel, snackbar timeout, invalid
  metadata, inactive/background pane delivery and session close discard it.
- Filenames are reduced to a control-free basename of at most 160 Unicode
  scalar values. Native, Dart and AppKit validate this independently; the final
  path comes only from `NSSavePanel`.
- Completed or failed transfers created while transcript resize replay rebuilds
  the parser are discarded, so historical terminal bytes cannot repeat a host
  action.
- `RequestUpload` remains unsupported. Ianvs returns the parser's cancellation
  response and shows blocked feedback without opening a file panel, reading a
  local file or placing local bytes on the PTY.
- OSC 1337 `OpenURL` is governed by its separate active-pane permission
  contract; `StealFocus`, `SetProfile` and other host actions remain
  unsupported and unauthorized.

## Product lifecycle

1. A completed real-PTY transfer moves decoded bytes from parser ownership into
   one-shot session storage and emits a metadata-only `file_download` event.
2. Only the active pane presents `Received <name> (<size>)` with **Save** and a
   close control. A background event is discarded silently.
3. Save opens `NSSavePanel`. Cancel discards. Confirm consumes the exact bytes
   once, writes them to the selected path and reports success or failure.
4. Closing or timing out the prompt without Save discards the native bytes.

## Verification contract

Regression coverage includes single-transfer parser handoff, exact-byte
one-shot copy, size mismatch, pending-count and aggregate-memory bounds,
filename sanitization, transcript-resize non-replay, real interactive PTY
delivery, FFI/backend validation, typed event routing, active-pane gating,
native save-panel argument handling, cancel/discard and upload denial. Final
acceptance requires a verifier-built cold-launched macOS app and real zsh OSC
probes.
