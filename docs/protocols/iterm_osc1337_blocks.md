# iTerm2 OSC 1337 Block and UpdateBlock

Ianvs supports the terminal-local layout subset of iTerm2 block folding:

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
- `render=1` is retained as bounded parser metadata, but iTerm2's associated
  text/JSON document transformation is not implemented in this folding phase.
  It remains a safe deferred action and grants no host authority.
- RIS, CSI `3 J`, and OSC 1337 `ClearScrollback` discard stale block marks.

Ianvs deliberately implements folding as a reversible display projection. This
matches iTerm2's observable first/last-line summary and fold controls while
preserving the terminal grid as the authoritative source for copy, search and
replay.

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

Frame transport is additive: protobuf frame tag `31` carries blocks, while row
tags `6` and `7` carry source bounds. Older consumers ignore the new tags and
legacy frames retain contiguous-row fallback behavior.

## Bounds and safety

- Existing OSC ingress limit: 16 KiB.
- Parsed block parameters: at most 16.
- Block IDs and types: at most 256 Unicode scalar values, non-empty and without
  control characters.
- Retained blocks: at most 512; completed entries are evicted first.
- Frame blocks: at most 512 with viewport and source-range validation.

The protocol changes only terminal-local layout. It cannot read files, access
the clipboard, open URLs, focus windows, switch profiles, launch processes or
perform another host action.

## Reference behavior

The implementation was compared with iTerm2 commit
`2c6c17162f5fc979e0933714803f1a4a7f1fffa3`, including its
`tests/test_block_folding.sh`, OSC parser, screen delegate, fold summary and
fold-button paths. Ianvs uses reversible row virtualization rather than
iTerm2's internal destructive buffer fold, while preserving the protocol's
observable fold/unfold behavior.

The comparison also confirmed that iTerm2 routes `attr=end;render=1` through
its text-document renderer. Ianvs does not claim that separate transformation
as part of the folding subset.
