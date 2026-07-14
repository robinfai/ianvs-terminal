# xterm OSC 60/61/62 capability-query contract

Ianvs supports xterm's three read-only optional-runtime-feature queries in
Xterm256 sessions:

```text
OSC 60 ST
OSC 61 ; category ST
OSC 62 ; category ST
```

BEL termination is accepted as well. Replies use the request's terminator:

```text
OSC 60 [ ; category-list ] ST
OSC 61 [ ; operation-list ] ST
OSC 62 [ ; operation-list ] ST
```

- OSC 60 reports top-level categories that are wholly enabled now.
- OSC 61 reports the fallback subcategories that remain disabled when the
  named top-level category is disabled.
- OSC 62 reports every recognized subcategory in the named xterm table.

Category matching for OSC 61/62 is ASCII case-insensitive. The documented
`allowWindowOps` name and xterm's `allowWinOps` compatibility alias are both
accepted. A recognized category with an empty table replies without the
semicolon. Missing, unknown, extra or reply-shaped payloads are consumed
without a reply. This keeps the normative query grammar exact and prevents a
PTY line-discipline echo from turning a terminal reply into a response loop.

## Ianvs capability mapping

| Category | OSC 60 | OSC 61 fallback deny-list | OSC 62 allowable table |
|---|---|---|---|
| `allowColorOps` | present while the OSC Appearance capability is enabled | `SetColor,GetColor,GetAnsiColor` | the same three official items |
| `allowFontOps` | absent; OSC 50 font control is not implemented | `SetFont,GetFont` | the same two official items |
| `allowMouseOps` | absent because the whole category is not enabled | `Locator,VT200Hilite` | all 11 official mouse items |
| `allowPasteControls` | absent; Ianvs does not expose an xterm paste-control permission switch | every canonical C0 item plus `C0,DEL,STTY` | the official table, including the `NL` alias |
| `allowTcapOps` | absent; xterm termcap set/get is not implemented | `SetTcap,GetTcap` | the same two official items |
| `allowTitleOps` | present while the OSC Metadata capability is enabled | empty | empty, matching xterm's lack of a title subcategory table |
| `allowWindowOps` | absent because host-window operations are not enabled wholesale | every unsupported/denied operation | all 27 current official items |

Ianvs implements these window-operation exceptions while the parent category
remains disabled, so OSC 61 omits them from its deny-list:

- `GetWinSizePixels`
- `GetWinSizeChars`
- `PushTitle`
- `PopTitle`
- `GetChecksum`

`SetSelection` and `GetSelection` are also omitted only while their independent
OSC ClipboardWrite and ClipboardRead capabilities are enabled. This makes
OSC 61 reflect the effective legacy insecure-sequence switch as well as the
fine-grained parser policy. Omission means that the request can reach the
product policy layer; it does not grant clipboard authority. The application
can still deny or prompt for the operation.

## Safety and lifecycle

- The queries use the existing 4 KiB bounded custom-protocol ingress class.
  Oversized input is discarded through its terminator and later OSC parsing
  recovers.
- Parser acceptance grants no permission, mutates no terminal/product state,
  and cannot change any capability. OSC 60/61/62 have no setter form.
- Replies are assembled only from fixed protocol names and terminal-owned
  booleans. They disclose no environment, filesystem, clipboard data, title or
  user content.
- Response-buffer insertion remains atomic and bounded by the terminal's
  existing response budget.
- Xterm256 real PTY replies flow directly back to the child. They do not add a
  frame, Dart event or product UI schema. Resize transcript replay cannot
  re-send a historical reply.
- VT220 sessions consume the xterm-specific queries without replying.

## Reference comparison

The contract was compared against the official xterm Patch #410 control-
sequence document (2026-04-19) and its corresponding source archive. The
reference implementation is in `misc.c` (`report_allowed_ops`,
`report_disallowed_ops`, and `report_allowable_ops`); the canonical tables are
in `charproc.c` (`tblColorOps`, `tblFontOps`, `tblMouseOps`, `tblPasteOps`,
`tblTcapOps`, and `tblWindowOps`).

Ianvs intentionally maps xterm's X resource booleans and fallback lists onto
its actual parser/product capabilities. It does not claim unimplemented font,
termcap, DEC locator, highlight-tracking or host-window operations merely
because xterm defines their names.
