# xterm legacy title and icon-label contract

Ianvs supports the numeric xterm title operations and the retained Sun/CDE
non-numeric aliases in Xterm256 sessions:

```text
OSC 0 ; text ST   set window title and icon label
OSC 1 ; text ST   set icon label
OSC 2 ; text ST   set window title
OSC l text ST     set window title
OSC L text ST     set icon label
```

BEL termination is accepted as well. The lowercase `l` and uppercase `L` are
the command bytes themselves: there is no protocol separator after them. A
semicolon following either alias is therefore part of the title or label.
None of these set operations emits a PTY reply.

## State and product behavior

- OSC 0 updates both channels from the same text. OSC 2 and lowercase `l`
  update only the window title. OSC 1 and uppercase `L` update only the icon
  label.
- The vendored terminal owns the window-title state and emits the existing
  `TitleChanged` event. The native filtered host observer owns the icon label.
  Existing optional `window_title` and `window_icon_name` JSON/protobuf fields
  carry both values; no schema or authority was added.
- The product uses a non-empty window title first, then a non-empty icon label,
  then the profile name for its pane/tab title. Independent icon-label updates
  therefore do not unexpectedly replace an active window title.
- Title and icon text must be UTF-8. Control characters are removed and each
  resulting value is limited to 1,024 Unicode scalars. Empty accepted aliases
  clear their owned channel; invalid UTF-8 leaves the prior value unchanged.
- Numeric and legacy title payloads preserve semicolons. This also repairs the
  prior numeric OSC 0/2 truncation at the first semicolon introduced by VTE's
  parameter splitting.

## Ingress, lifecycle, and compatibility

- All five operations use the existing Appearance capability and its 4 KiB
  streaming payload limit. The non-numeric aliases are classified from their
  first byte, so a long alias cannot fall into the 64-byte custom-command path
  or bypass Appearance denial.
- Appearance denial and VT220 emulation consume the complete sequence without
  changing either channel. Oversized input is discarded through BEL/ST and
  parsing resumes with following terminal text.
- RIS clears both current channels. Terminal snapshots and resize transcript
  replay preserve the existing title behavior without replaying a host action.
- The aliases are additive wire compatibility. Existing OSC 0/1/2 producers,
  frame fields and pane-title precedence keep their prior APIs.

CSI 20/21 `t` title-report requests and independent icon/title stack semantics
are window-operation contracts, not OSC set-operation parsing, and are not
promoted by this phase.

## Reference comparison

The contract was compared with the
[official xterm Patch #410 control-sequence reference](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html)
and its matching 2026-04-19 `misc.c`. The reference dispatches an initial
lowercase `l` to its window-title operation and uppercase `L` to its icon-name
operation without requiring a semicolon; it also defines OSC 0 as the combined
window-and-icon title operation.
