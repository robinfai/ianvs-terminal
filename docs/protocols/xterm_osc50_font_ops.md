# xterm OSC 50 font-operation contract

Ianvs supports xterm OSC 50 as a session-local TrueType font-family operation
in Xterm256 sessions:

```text
OSC 50 ; family ST
OSC 50 ; #index family ST
OSC 50 ; ? ST
OSC 50 ; ?index ST
```

BEL termination is accepted as well. A query reply mirrors the request's
terminator and uses `OSC 50 ; family` for an unindexed query or
`OSC 50 ; #index family` for an explicitly indexed query.

## Supported semantics

- A plain non-empty payload sets the current session's font family.
- `#` accepts xterm's absolute or relative font-menu index expression before
  the family. Ianvs validates the official index order but, like xterm's
  `renderFont` path, applies the supplied TrueType family rather than
  fabricating a bitmap-font menu.
- `?` returns the current family. Absolute and relative query expressions use
  xterm's default `1,2,3,0,4,5,6,7` face-size ordering and an index-zero
  anchor. Ianvs has no X resource overrides that can reorder those sizes.
- Family names may contain spaces, Unicode and semicolons. Leading/trailing
  whitespace is removed. Empty names, controls, invalid UTF-8 and names over
  256 UTF-8 bytes are ignored.
- An invalid query index returns bare `OSC 50` with the matching terminator,
  consistent with xterm's failed query response.

OSC 50 changes only the current font family. It does not change the configured
profile, fallback families, point size or line height. The Flutter viewport
combines the frame's current family with those profile-owned values, measures
the resulting glyph cells and drives the existing PTY resize/reflow path when
metrics change.

## Policy, lifecycle and compatibility

- OSC 50 uses the existing 4 KiB Appearance ingress class and bounded terminal
  response buffer. Appearance denial and VT220 mode consume the request without
  changing state or replying.
- The profile family seeds each new terminal and resize reconstruction. A
  successful OSC 50 set survives RIS, terminal snapshots and transcript replay.
- A changed family forces a snapshot frame so cached glyph metrics and row
  visuals cannot be reused across different fonts.
- JSON adds optional `font_family`; protobuf adds optional tag 33. Legacy
  producers leave the field absent, and Dart then continues using the profile
  family. Invalid wire values fail closed to that legacy behavior.
- OSC 60 now includes `allowFontOps` while Appearance is enabled. OSC 61 keeps
  xterm's `SetFont,GetFont` fallback deny-list for the case where that parent
  category is disabled, and OSC 62 continues to report the official table.

## Reference comparison

The contract was compared with the
[official xterm Patch #410 control-sequence reference](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html)
and the matching 2026-04-19 source archive. `QueryFontRequest` and
`ChangeFontRequest` in `misc.c` define the query/set behavior;
`ParseShiftedFont` and `setFaceName` implement the menu expression and TrueType
family path.

Ianvs intentionally does not expose xterm's X resource bitmap font menu or a
profile-persistent font mutation. Those would require product-owned font-menu
and settings contracts rather than terminal output alone.
