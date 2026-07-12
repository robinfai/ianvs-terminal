# Kitty OSC 5522 MIME clipboard contract

Ianvs implements a security-bounded core subset of Kitty's arbitrary MIME
clipboard protocol. OSC 5522 is separate from xterm OSC 52: OSC 52 remains the
portable text-selection protocol, while OSC 5522 carries binary data and
multiple MIME representations.

The authoritative wire format is documented by
[Kitty's clipboard protocol](https://sw.kovidgoyal.net/kitty/clipboard/).

## Supported wire operations

- `type=write` starts a transaction. Its payload must be empty.
- `type=wdata:mime=<base64 MIME>` appends one Base64 data chunk. A final empty
  `type=wdata` commits the transaction.
- `type=walias:mime=<base64 target>` associates one or more space-separated
  MIME aliases with data already supplied for the target.
- `type=read` accepts a Base64-encoded, space-separated MIME pattern list.
  Exact MIME types, `type/*`, and `*/*` are supported.
- Paste-event follow-up reads may instead place one Base64 MIME value in the
  `mime` metadata field and leave the payload empty.
- A read payload of `.` lists available MIME types without reading clipboard
  contents and therefore without showing a read-permission prompt.
- Replies use `OK`, `DATA`, `DONE`, `EINVAL`, `ENOSYS`, `EPERM`, `EBUSY`, or
  `EIO` status values and preserve a sanitized correlation `id`.

Both BEL and ST input framing are accepted by the streaming parser. Ianvs
emits ST-terminated responses. Decoded `DATA` chunks are at most 4096 bytes.

## Bounds and failure behavior

| Resource | Limit |
|---|---:|
| One decoded `wdata` chunk | 4096 bytes |
| One transaction / read result | 4 MiB |
| MIME representations or read patterns | 64 |
| MIME value | 255 bytes |
| Aliases for one representation | 16 |
| Echoed `id` | 128 allowed ASCII bytes |
| Decoded `pw` or application `name` | 256 bytes each |

MIME data is assembled as bytes, never decoded as text. Invalid Base64,
invalid MIME syntax, a non-empty start payload, out-of-order MIME chunks,
aliases for absent data, and any bound violation produce one `EINVAL`. The
failed transaction ignores subsequent data packets until a fresh `type=write`
starts. RIS clears an unfinished transaction.

## Host authorization and platform behavior

- MIME writes reuse the product clipboard-copy policy. Denial returns `EPERM`
  before the system clipboard is touched.
- MIME content reads reuse the clipboard-paste/read policy. Denial returns
  `EPERM` before platform data is requested.
- Base64 UTF-8 `pw` and application `name` metadata are accepted on reads and
  writes. “Always allow” is offered only when both are present, remembers the
  exact pair for at most the current terminal session, and authorizes matching
  future reads and writes on that session. Password-only requests remain
  ordinary one-shot authorization requests.
- Type listing is metadata-only and bypasses content-read authorization.
- macOS maps common text and image types to `NSPasteboard` types, canonicalizes
  system aliases, and filters non-MIME pasteboard identifiers. Arbitrary MIME
  names are reversibly hex-encoded under the valid private UTI prefix
  `dev.ianvs.terminal.mime.` because `NSPasteboard` rejects `/` inside a raw
  UTI; reads and type listing decode the original MIME name.
- The default clipboard location is supported. `loc=primary` returns `ENOSYS`
  on macOS because the platform has no X11-style primary selection.
- Diagnostics expose only protocol metadata, MIME names, counts, status, and
  byte totals; binary clipboard contents are not logged.

## Paste-event mode

- `CSI ? 5522 h` enables OSC 5522 paste events, `CSI ? 5522 l` disables them,
  and DECRQM reports `CSI ? 5522 ; 1 $ y` or `CSI ? 5522 ; 2 $ y`.
- While enabled, a user paste emits an unsolicited `OK`, one metadata-only
  `DATA` packet per available MIME type, and `DONE`. This takes precedence over
  bracketed-paste mode and never reads or injects clipboard text directly.
- The `OK` packet carries a cryptographically random one-time `pw`. A matching
  clipboard-location read consumes that token without a second prompt. Tokens
  expire after 10 seconds, are single-use, are bounded per session, and are
  cleared when the session closes.
- The UI exposes `MIME PASTE` instead of the bracketed `PASTE` indicator while
  both modes are active.

Non-macOS primary-selection integration and reference-terminal comparison
remain outside this contract.
