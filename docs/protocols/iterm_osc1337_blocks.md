# iTerm2 OSC 1337 Block and UpdateBlock

Ianvs supports iTerm2's terminal-local block folding and text-document
presentation commands:

```text
OSC 1337 ; Block=id=<id>;attr=start[;type=<type>] ST
OSC 1337 ; Block=id=<id>;attr=end[;render=1] ST
OSC 1337 ; UpdateBlock=id=<id>;action=fold|unfold ST
```

BEL and ST termination are accepted through the existing bounded OSC parser.
Parameter order is not significant; the last bounded value for a duplicate key
wins. Unknown attributes, actions and IDs are no-ops.

## Semantics

- Marks apply only to the primary screen. Alternate-screen block commands are
  ignored, and VT220 sessions keep OSC 1337 gated off.
- A start mark captures the current absolute primary-buffer row. An end mark
  closes the matching active ID at the current row. Nested IDs are supported.
- Only completed ranges spanning more than one physical row can fold.
- A folded range becomes one dim/italic display row containing bounded prefixes
  of the first and last rows around `…N line(s)…`, where `N` is the number of
  interior physical rows. The source grid is not destructively rewritten.
- Overlapping folded ranges collapse to the outermost stable summary. Unfolding
  restores the original grid immediately.
- `render=1` changes the completed, unfolded region into a theme-derived text
  document presentation. `type` selects Markdown, JSON, plain text or generic
  code styling; missing types use bounded visible-text heuristics.
- Rendering is a reversible presentation projection. The original terminal
  rows remain authoritative for selection, search, copy, replay and resize.
  Closing the document restores the rows' original terminal styling.
- Folding a rendered block hides its document presentation; unfolding restores
  it. User document-close and fold choices are preserved across
  transcript-backed width replay.
- RIS, CSI `3 J`, and OSC 1337 `ClearScrollback` discard stale block marks.

Ianvs deliberately implements both folding and text documents as reversible
display projections. This matches iTerm2's observable fold controls,
syntax-aware document presentation, selection/search behavior and close-to-
restore action while preserving the terminal grid as the authoritative source.
iTerm2 replaces rows with a variable-height AppKit Porthole; Ianvs keeps the
same terminal-cell row geometry so scrollback, graphics and frame coordinates
remain deterministic across Flutter platforms.

## Cross-layer mapping

Folded frames may be non-contiguous. Each display row therefore carries an
optional retained `source_row` / inclusive `source_end_row`, and each visible
block carries its display range plus retained source range. A summary maps the
entire hidden interval; projection padding maps to no source row.

- Virtual scrollback counts projected display rows rather than hidden physical
  rows.
- Search continues over original content and routes a hidden match to its fold
  summary.
- Selection highlights use source ranges; product-triggered fold changes clear
  the current selection before layout changes.
- Graphics and OSC 66 placements intersecting a collapsed range are omitted;
  placements outside the fold are remapped to display rows.
- A complete native transcript reconstructs block coordinates during width
  reflow. If replay is unavailable, direct reflow invalidates physical marks
  instead of exposing stale coordinates.

Frame transport is additive: protobuf frame tag `31` carries blocks, block tag
`9` carries the `rendered` state, and row tags `6` and `7` carry source bounds.
Document content is not duplicated into frame metadata; it remains in the
existing bounded viewport rows. Older consumers ignore the new tag and legacy
frames default `rendered` to false.

## Bounds and safety

- Existing OSC ingress limit: 16 KiB.
- Parsed block parameters: at most 16.
- Block IDs and types: at most 256 Unicode scalar values, non-empty and without
  control characters.
- Retained blocks: at most 512; completed entries are evicted first.
- Frame blocks: at most 512 with viewport and source-range validation.

Document styling examines only already-rendered viewport strings. The protocol
changes only terminal-local layout and cannot read files, access the clipboard,
open URLs, focus windows, switch profiles, launch processes or perform another
host action.

## Reference behavior

The implementation was compared with iTerm2 commit
`2c6c17162f5fc979e0933714803f1a4a7f1fffa3`, including its
`tests/test_block_folding.sh`, `VT100Terminal.m`, the screen/session delegates,
`PTYTextView.swift`, `PortholeFactory.swift`, `TextViewPortholeRenderer.swift`
and the Markdown/JSON renderer specializations. iTerm2 extracts the original
range, builds a selectable/searchable text Porthole, applies a `type` hint or
auto-detection, and restores saved lines when the Porthole closes. Ianvs uses
reversible cross-platform row projection rather than destructive AppKit buffer
replacement while preserving those protocol-level behaviors.
