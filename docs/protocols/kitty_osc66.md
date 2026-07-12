# Kitty OSC 66 sized text

Status: supported.

Normative upstream syntax: [Kitty text sizing protocol](https://sw.kovidgoyal.net/kitty/text-sizing-protocol/).

## Wire grammar

Ianvs accepts BEL- or ST-terminated sized text in the published form:

```text
OSC 66 ; metadata ; text ST
```

`text` is escape-code-safe UTF-8 and is limited to 4,096 bytes. Semicolons
after the metadata separator belong to the text. The metadata field is a
colon-separated list of these keys:

| Key | Accepted values | Default | Meaning |
|---|---:|---:|---|
| `s` | 1–7 | 1 | Integral scale; block height is `s` cells |
| `w` | 0–7 | 0 | Unscaled width; block width is `s × w` cells |
| `n` | 0–15 | 0 | Fractional numerator |
| `d` | 0–15 | 0 | Fractional denominator; when nonzero, `d > n` |
| `v` | 0–2 | 0 | Fractional vertical alignment: top, bottom, center |
| `h` | 0–2 | 0 | Fractional horizontal alignment: left, right, center |

Unknown keys, malformed values and invalid fractions reject the complete
sequence without changing terminal state. Control characters and Unicode
noncharacters are excluded from rendered text.

## Cell and rendering model

For nonzero `w`, all text in one sequence occupies one `s × w` by `s` block.
For `w=0`, Ianvs segments text into Unicode grapheme clusters, calculates each
cluster's normal terminal width and creates one scaled block per cluster. Every
occupied cell stores bounded block metadata; only the top-left anchor stores
the text.

The native frame exports additive `sized_text` placements in JSON and protobuf
tag 24. Placements include the text, cell rectangle, viewport clipping offset,
integral/fractional scale, alignment, natural-width flag and terminal style.
Dart validates the same bounds for JSON and protobuf, including the 4 KiB UTF-8
limit. Flutter reserves the block in ordinary row text and paints the scaled
glyph once, clipped to the visible portion. If the requested text cannot fit,
the renderer downsizes it to the block, which the protocol explicitly permits.

Fractional scale is applied on top of `s`. For example,
`s=2:n=1:d=2:v=2` occupies a 2×2 block but renders at the base font size,
vertically centered. Block, beam and underline cursors cover the corresponding
multicell geometry when the cursor lies anywhere inside it.

## Grid behavior

Ianvs implements the specified grid interactions:

- DECAWM wraps a block before drawing when it does not fit; with wrapping off,
  the cursor moves left far enough to fit it;
- a block larger than the screen in either dimension is discarded;
- combining characters extend a block only from its top row;
- writing at the top-left erases the block, writing elsewhere on its top row
  replaces the block with spaces, and writing on a lower row skips to its right;
- ICH, DCH, ECH, ED, EL, IL and DL erase blocks that would be split or intersect
  an erased region, while complete single-line blocks can shift intact;
- scrolling may retain complete blocks across the screen/scrollback boundary;
  ED 2, ED 3, history eviction and fragment cleanup cannot leave orphan cells;
- width reflow preserves complete blocks that still fit and removes blocks that
  become too large; snapshots preserve blocks and RIS clears them.

Plain and styled text export, search and selection expose anchor text once and
omit structural continuation cells.

## Bounds, policy and compatibility

OSC 66 is appearance-only and cannot request a host action. The streaming gate
applies the 4 KiB limit to the text body before dispatch, metadata is capped at
128 bytes by the command parser, and malformed or oversized sequences are
discarded through their terminator before normal parsing resumes. VT220 policy
consumes OSC 66 without moving the cursor, changing cells or exporting a
placement.

JSON `sized_text` is additive and absent data decodes as an empty list.
Protobuf tag 24 is additive. Older consumers continue to receive blank cell
geometry where sized text is reserved; newer consumers render the placement.

Automated evidence covers metadata and UTF-8 bounds, fixed/natural width,
fractional alignment, BEL/ST and every byte split, policy denial, capability
detection via CPR, overwrite/edit/erase rules, screen/scrollback boundaries,
resize/reflow, snapshot/RIS, shared corpus, semantic probe, JSON/protobuf parity,
viewport clipping, Flutter painting/cursors, VT220 isolation and macOS real PTY.
