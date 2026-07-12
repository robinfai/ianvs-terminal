# xterm special and dynamic colors

Status: supported appearance subset with complete wire state for OSC 5/6,
105/106 and 10–19/110–119.

Normative references:

- [XTerm Control Sequences](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html)
- [xterm resource manual](https://invisible-island.net/xterm/manpage/xterm.html)

## Special attribute colors

Ianvs accepts any number of pairs in `OSC 5;c;spec;c;spec`. `spec=?` returns
one `OSC 5;c;rgb:rrrr/gggg/bbbb ST` response. The same five resources are also
available through OSC 4 indices 256–260 in the 256-color personality.

| `c` | Resource | Attribute |
|---:|---|---|
| 0 | `colorBD` | bold |
| 1 | `colorUL` | underline |
| 2 | `colorBL` | blink |
| 3 | `colorRV` | reverse |
| 4 | `colorIT` | italic |

`OSC 105;c...` restores named resources to immutable profile/session
baselines; no parameters restores all five. Explicit OSC 104 indices 256–260
restore the same slots. Invalid and odd trailing parameters are ignored
independently.

`OSC 6;c;f` and its exact alias `OSC 106;c;f` enable a mode when `f` is nonzero
and disable it when `f` is zero:

| `c` | Mode |
|---:|---|
| 0–4 | enable the corresponding resource above |
| 5 | `colorAttrMode`: allow attribute colors to override explicit ANSI/truecolor foregrounds |

With mode 5 disabled, the xterm default, attribute colors affect only cells
whose foreground came from the terminal default. With it enabled, existing
explicit-color cells are repainted too. The renderer follows xterm's default
`veryBoldColors=0` behavior: a matched special color replaces the corresponding
bold/underline/blink/reverse/italic visual attribute instead of combining with
it. Reverse cells are flattened once into final foreground/background colors,
so Flutter does not invert them a second time. OSC 6/106 without complete pairs
has no effect; RIS restores the configured mode baselines.

## Dynamic resources

OSC 10–19 parameters are sequential. For example, `OSC 17;A;B;C ST` addresses
17, 18 and 19. Each parameter may set a color or contain `?`, in which case one
response for that resource is emitted. Parameters after resource 19 are
ignored.

| OSC | Resource | Product effect |
|---:|---|---|
| 10 | text foreground | rendered and exported |
| 11 | text background | rendered and exported |
| 12 | text cursor | rendered and exported |
| 13 | pointer foreground | retained/queryable; no host-pointer recoloring |
| 14 | pointer background | retained/queryable; no host-pointer recoloring |
| 15 | Tektronix foreground | retained/queryable; no Tektronix widget |
| 16 | Tektronix background | retained/queryable; no Tektronix widget |
| 17 | highlight background | rendered selection background |
| 18 | Tektronix cursor | retained/queryable; no Tektronix widget |
| 19 | highlight foreground | rendered selected-text foreground |

OSC 110–119 restore the corresponding 10–19 profile/session baseline.
Selection foreground activation is also baseline-aware: OSC 19 enables the
selected-text override, OSC 119 restores the profile's configured activation,
and legacy frames without the new field retain the existing theme behavior.

## Frame and renderer contract

`selection_background` and `selection_foreground` are additive optional JSON
fields and protobuf tags 25/26. Delta application inherits omitted values from
the previous frame. The viewport paints the selected background first, draws
the normal cached row, then clips and repaints selected glyphs in the dynamic
foreground. Custom box/powerline geometry follows the same clipped override.

Attribute resources are resolved while native style runs are built. A resource
or mode mutation marks a full repaint so existing screen and scrollback cells
are re-resolved without changing their stored SGR provenance.

## Safety, bounds and compatibility

These commands are appearance-only and cannot authorize a host action. The
OSC ingress gate classifies both short and long aliases as `Appearance`; VT220
or an explicitly denied appearance capability consumes them without mutation
or reply. Existing VTE field-count and ingress-byte limits bound pair batches,
and malformed UTF-8, indices, flags and color specifications are isolated.

Snapshots retain all visible and non-visual resources. RIS restores immutable
profile colors and mode baselines. JSON/protobuf changes are additive and old
consumers can ignore the two new tags.

## Evidence

Automated coverage includes special set/query/reset, OSC 4 aliases, OSC 6/106
mode equivalence including `colorAttrMode`, sequential 13–19 set/query,
110–119 reset, malformed inputs, BEL/ST and every-byte splits, snapshot/RIS,
shared corpus, native real PTY, VT220 denial, JSON/protobuf parity, Dart merge
compatibility and Flutter pixel assertions for selection background and text.
