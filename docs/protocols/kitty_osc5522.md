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

## Deliberately deferred Kitty features

This phase does not cache `pw` passwords or application `name` metadata, and it
does not implement the `CSI ? 5522 h/l` paste-event notification mode. Supplying
`pw` therefore never bypasses the normal Ianvs authorization decision. These
features require separate lifecycle, trust, and UI contracts before they can be
advertised as supported.
