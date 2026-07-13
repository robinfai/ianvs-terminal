# iTerm2 OSC 1337 cursor-guide contract

Ianvs supports iTerm2's session-local cursor guide:

```text
OSC 1337 ; HighlightCursorLine=yes ST
OSC 1337 ; HighlightCursorLine=no ST
```

BEL and ST terminators are accepted. `yes` and `no` are the canonical values
from the [iTerm2 escape-code documentation](https://iterm2.com/documentation-escape-codes.html).
For source compatibility, an exact command with an empty value enables the
guide; `true`/`false`, `1`/`0`, and `on`/`off` are bounded aliases. Unknown
values, parameters, suffixes, and near-matching command names are ignored.

## Presentation behavior

- The guide covers the full current cursor row and follows cursor movement.
- It uses the terminal's cursor-guide color token with a low-opacity fill and
  device-pixel-aligned top and bottom edges. No color is hard-coded in the
  Flutter widget.
- Cell backgrounds render below the guide. Search and selection emphasis render
  above it, so the guide cannot obscure stronger interaction states.
- DECTCEM cursor visibility controls the guide. Cursor blink animation does not
  make the full row flash.
- The state is session-local across primary and alternate screens. It survives
  RIS and terminal snapshots until an explicit `no` command changes it.

The behavior follows iTerm2 source commit
`2c6c17162f5fc979e0933714803f1a4a7f1fffa3`:
`VT100Terminal.m` parses the command, the screen delegate stores the session
setting, and `iTermTextDrawingHelper.m` paints the guide behind text only while
the terminal cursor is visible.

## Frame compatibility

Native JSON frames add `cursor.highlight_line`, defaulting to `false`, plus the
optional `cursor_guide_color`. Protobuf adds `TerminalCursor.highlight_line` at
tag 6 and `TerminalFrameDiff.cursor_guide_color` at tag 30. Both additions are
backward compatible: old payloads decode to a disabled guide, old consumers may
ignore the fields, and existing tags are not reused.

Cursor-only delta frames can enable or disable the guide without rebuilding row
text. Guide-color changes request a full repaint, while the renderer stays in
the existing terminal RenderObject and adds no overlay layer.

## Policy and safety

The command is classified as appearance state with the existing 4 KiB ingress
limit. Appearance-policy denial and VT220 profiles consume it without state
mutation. It cannot read or write the clipboard or filesystem, open URLs,
focus windows, change profiles, execute commands, or request any host action.
