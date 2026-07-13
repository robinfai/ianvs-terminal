# iTerm2 OSC 1337 ClearScrollback contract

Ianvs supports iTerm2's terminal-local Clear Buffer command:

```text
OSC 1337 ; ClearScrollback ST
```

BEL and ST terminators are accepted. The command name is exact; parameters,
suffixes, and near-matches are ignored. Despite its historical name, iTerm2
maps this OSC to its Clear Buffer action rather than the narrower CSI 3 J
operation.

## Buffer behavior

- Retained primary-screen scrollback is discarded, including a request sent
  while the alternate screen is active.
- The active visible grid and its screen-local graphics are cleared. Retained
  scrollback graphics are also discarded.
- The current wrapped logical line is moved to the top. When an OSC 133 prompt
  mark is available, visible rows from that prompt through the cursor are
  retained, matching iTerm2's prompt-preserving clear behavior.
- The cursor keeps its column and moves to the final retained row. Saved cursor
  state, vertical and horizontal margins, and origin mode are reset.
- Semantic zones whose absolute row coordinates became invalid are evicted;
  eviction events remain ordered before the full-clear event.
- Later bytes in the same PTY stream continue parsing normally. The clear
  emits no reply and does not reset unrelated title, color, mode, or session
  metadata.

## Native/session consistency

The parser emits a typed full-clear event. Native sessions reset their viewport
offset, row/frame caches, and bounded resize transcript when that event comes
from either this OSC or CSI 3 J. This prevents cleared text from remaining in
diagnostic/replay storage or reappearing after resize. Product frames report
zero scrollback offset and zero maximum offset immediately after the clear.

## Policy and safety

`ClearScrollback` is classified as bounded shell-integration metadata with a
16 KiB ingress ceiling shared by OSC 1337 shell metadata. It changes only the
emulated terminal buffer: it cannot read or write files or clipboard data,
open URLs, focus windows, change profiles, execute commands, or acquire host
authority. Denied metadata policy and VT220 profiles consume it without state
mutation.

The behavior is derived from iTerm2 source commit
`2c6c17162f5fc979e0933714803f1a4a7f1fffa3`: `VT100Terminal.m` dispatches
`ClearScrollback` to `terminalClearBuffer`, and
`VT100ScreenMutableState.m` implements the prompt-preserving buffer clear.
