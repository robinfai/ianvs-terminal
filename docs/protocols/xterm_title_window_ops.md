# xterm title query, mode and stack contract

Ianvs implements xterm's title-related window operations for Xterm256 sessions.
The contract complements the OSC 0/1/2/l/L setters documented in
[xterm legacy title aliases](xterm_legacy_title_aliases.md).

```text
CSI 20 t                 report icon label as OSC L label ST
CSI 21 t                 report window title as OSC l title ST
CSI 22 ; Ps ; Pi t       save title state
CSI 23 ; Ps ; Pi t       restore title state
CSI > Pm [; Pm ...] t    set title modes (XTSMTITLE)
CSI > Pm [; Pm ...] T    reset title modes (XTRMTITLE)
```

`Ps` selects both channels (`0`, the default), icon label only (`1`) or window
title only (`2`). `Pi=0` uses the implicit LIFO. `Pi=1..10` addresses a direct
slot and does not push or pop the implicit stack. Other selectors and positions
are bounded no-ops.

## Reports and modes

- CSI 20/21 reports always use the two-byte ST terminator, matching xterm's
  `report_win_label` behavior. The reply contains no semicolon between the
  non-numeric `L/l` command byte and its text.
- Mode 0 decodes later OSC 0/1/2/l/L setter text as strict hexadecimal bytes.
  Odd-length input, a non-hexadecimal nibble or decoded invalid UTF-8 leaves
  the prior channel unchanged.
- Mode 1 encodes CSI 20/21 report bytes as uppercase hexadecimal.
- Modes 2 and 3 explicitly select UTF-8 setter/query operation. Ianvs already
  requires valid UTF-8 for title state and replies, so these bits preserve the
  native UTF-8 path without a second legacy character-set conversion.
- Multiple explicit `Pm` values are applied in order. XTRMTITLE clears only
  the named bits. Setting both a hexadecimal and UTF-8 bit keeps the
  hexadecimal bit authoritative for the corresponding set/query transform.
- Mode state is terminal-local. It is retained in terminal snapshots and reset
  by RIS; it is never persisted to a profile.

## Independent stack behavior

The terminal owns a fixed ten-entry stack whose entries hold independent
optional icon and window values.

- Implicit saves advance through the ten slots and retain the newest ten
  entries. Implicit restores pop newest first.
- Selector 1 saves only the icon value; selector 2 saves only the window value.
  When a restored entry lacks the other component, the implementation follows
  xterm and scans older slots for that component. Only the requested selector
  is applied to live state.
- Direct positions 1–10 overwrite and retrieve their corresponding slot
  without changing implicit depth. A direct restore is reusable.
- Each channel is already limited to 1,024 Unicode scalars and the OSC ingress
  payload is limited to 4 KiB, bounding retained stack memory and report size.

Terminal snapshots retain the two live channels, mode bits and all ten stack
entries. Resize transcript reconstruction therefore restores the same query
and pop results without duplicating replies. RIS clears both channels, all
mode bits and every stack entry.

## Policy and product behavior

All operations use the existing Appearance capability. Appearance denial and
VT220 emulation consume the complete request without changing state or writing
a PTY reply. No title operation reads host data, persists configuration,
changes a profile name, invokes a host API or grants authority.

The existing optional `window_title` and `window_icon_name` JSON/protobuf fields
export live state. Product pane/tab naming continues to prefer a non-empty
window title, then a non-empty icon label, then the profile name. No frame,
protobuf, FFI or configuration schema was added.

## Reference and evidence

The grammar and behavior were compared against the
[official xterm Patch #410 control-sequence reference](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html)
and its matching 2026-04-19 `charproc.c`/`misc.c`: `report_win_label`,
`CASE_XTERM_SM_TITLE`, `CASE_XTERM_RM_TITLE`, `xtermPushTitle` and
`xtermPopTitle`.

Repository evidence covers raw and hexadecimal exact replies, fragmentation,
selectors, partial fallback, implicit bounds, all direct positions, invalid
input, policy denial, VT220 silence, RIS, snapshots, shared corpus, native real
PTY and macOS product real PTY behavior. Final acceptance evidence is recorded
in [Phase 40 review](../reviews/xterm_title_window_ops_phase40_20260714.md).
