# Kitty OSC 21 color-control subset

Status: supported bounded subset.

Normative upstream syntax: [Kitty color control](https://sw.kovidgoyal.net/kitty/color-stack/).

## Wire grammar and ordering

Ianvs accepts:

```text
ESC ] 21 ; key=value ; key=value ... ST
```

BEL and ST termination are accepted. Fields execute from left to right, so a
set followed by a query in the same sequence reports the new value. A bare key
resets it to the session/profile baseline, `key=` selects the field's dynamic
state, and `key=?` queries it. Unknown query keys reply as `key=?`; unknown set
or reset fields are ignored independently.

The existing VTE dispatcher retains at most 15 fields after the command. Ianvs
tests and documents that ceiling and clean recovery in the next OSC sequence.
The streaming appearance-policy limit remains 4 KiB, and query replies are also
capped at 4 KiB.

## Supported keys

The following affect the rendered terminal and exported JSON/Protobuf frame:

- ANSI palette indices `0` through `255`;
- `foreground` and `background`;
- `cursor`.

The following are retained, reset and queried in the terminal snapshot/state:

- `selection_background` and `selection_foreground`;
- `cursor_text` and `visual_bell`;
- `transparent_background_color1` through
  `transparent_background_color7`.

Selection text recoloring, visual-bell tint, cursor-text color, and transparent
background compositing are not yet consumed by the Flutter renderer. The
protocol does not invent a visual effect for those fields; they remain typed
color state for query and future renderer work.

## Color values

Ianvs accepts the normative `#RGB`, `#RRGGBB`, 9/12-digit hash forms,
`rgb:h/h/h`, and `rgbi:f/f/f` encodings. Components scale or clamp according to
the Kitty rules. A practical bounded set of common X11 names and numbered
red/green/blue variants is accepted. Alpha suffixes are retained and returned;
negative alpha is retained only for transparent-background slots. Current
frame colors are opaque, so alpha is not advertised as rendered support.

An empty palette value is ignored because ANSI table entries cannot be dynamic.
An empty special value is stored as dynamic and queries as an empty value. For
the visible cursor, the dynamic fallback is current foreground.

## Baselines, reset and compatibility

Profile setters establish immutable reset baselines for foreground, background,
cursor, selection colors and all 256 palette entries. OSC 21 changes only
runtime state. Bare-key reset, OSC 104/110/111/112, RIS, and profile/session
reconstruction restore the correct baselines. Snapshot capture/restore retains
runtime special colors and alpha metadata.

OSC 4/10/11/12 remain interoperable and update the same runtime values. OSC 23
is deliberately unrelated: the prior internal OSC 23 title-stack pop was a bug.
Title-stack push/pop remains the standard `CSI 22 t` / `CSI 23 t` path, while
OSC 23 is a bounded unsupported no-op.

## Security and evidence

OSC 21 is appearance-only and cannot authorize a host action. VT220 or a denied
appearance capability consumes the sequence without applying values or replying.
Invalid UTF-8, keys, indices, colors and alpha components are ignored at field
granularity. No color text reaches privacy diagnostics.

Automated evidence covers ordering, combined replies, unknown queries, dynamic
and alpha state, profile reset, malformed fields, every byte split, BEL/ST,
15-field admission, snapshot/RIS, shared corpus, native real PTY, VT220,
JSON/Protobuf parity, Flutter frame decoding/render paths, and macOS real PTY.
