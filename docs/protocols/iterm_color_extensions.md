# iTerm2 color extensions

Ianvs supports the session-local color subset of iTerm2 OSC 4 and OSC 1337
`SetColors`. The contract follows the published iTerm2 escape-code reference
and the open-source iTerm2 `VT100Terminal` implementation:

- <https://iterm2.com/documentation-escape-codes.html>
- <https://gitlab.com/gnachman/iterm2/-/blob/master/sources/VT100Terminal.m>

## Wire contract

OSC 4 accepts the iTerm2 default-color query aliases in addition to the xterm
palette contract:

- `OSC 4 ; -2 ; ? ST` replies with the current default background.
- `OSC 4 ; -1 ; ? ST` replies with the current default foreground.
- Negative indices are query-only. Mutations and unrecognized negative indices
  are ignored.

`OSC 1337 ; SetColors=key=value[,key=value...] ST` accepts at most 32 pairs.
Keys are ASCII and exact; malformed or unknown pairs are ignored without
rolling back valid siblings.

| Key | Ianvs session effect |
|---|---|
| `fg`, `bg` | Default foreground/background |
| `bold` | Default-sourced bold glyph foreground; bold font weight remains active |
| `underline` | Underline decoration color; SGR 58 remains cell-authoritative |
| `link` | OSC 8 hyperlink underline color |
| `selbg`, `selfg` | Selection background/foreground |
| `curbg`, `curfg` | Cursor fill/glyph color |
| `tab` | Active tab chrome color; `tab=default` removes the override |
| `black`…`white`, `br_black`…`br_white` | ANSI palette indices 0–15 |

Values accept three- or six-digit hexadecimal RGB, optionally prefixed by
`rgb:` or `srgb:`. `p3:` values are decoded as Display-P3, converted through
linear light into sRGB, clipped, and quantized to the existing 8-bit frame
color representation.

## Product transport and reset behavior

The native frame exports optional `link_color`, `cursor_text_color`, and
`tab_color` fields, plus optional `underline_color` on normal and sized-text
style runs. They use additive protobuf tags 27–29, style-run tag 11, and
sized-text tag 22. Missing fields preserve legacy/profile behavior in both JSON
and protobuf decoders.

Color-resource changes force a snapshot instead of a sparse delta so removed
overrides cannot survive in Dart state. Terminal snapshots retain active
session overrides. RIS clears them and restores profile/default behavior.

## Authority boundary

This subset is appearance-only. `preset` is deliberately ignored because it
would select or mutate host profile configuration. Unknown keys, malformed
colors, oversized batches, VT220 sessions, and sequences denied by the
appearance policy have no effect. No supported key grants file, process,
clipboard, network, notification, or command authority.

## Evidence

Coverage includes parser state and exact queries, malformed/P3/profile-denial
cases, snapshot/RIS behavior, appearance-policy classification, shared mirrored
corpus and semantic probes, native JSON/protobuf frame parity, Dart codec and
delta normalization, pixel-level underline/cursor rendering, tab UI fallback,
and macOS real-PTY acceptance.
