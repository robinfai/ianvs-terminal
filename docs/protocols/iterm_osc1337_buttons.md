# iTerm2 OSC 1337 inline buttons

Ianvs supports iTerm2's documented inline copy and custom buttons:

```text
OSC 1337 ; Button=type=copy ; block=<block-id> ST
OSC 1337 ; Button=type=custom ; code=<positive-int32> ; icon=<SF-symbol> ST
OSC 1337 ; Button=type=custom ST
```

BEL and ST terminators are accepted. A valid button is anchored at the current
cursor and consumes exactly four terminal cells. The parameter-only custom
form invalidates every retained custom button without advancing the cursor;
copy buttons remain valid. Consistent with iTerm2, a malformed custom form also
follows the invalidation branch; invalid copy and unknown types are bounded
no-ops.

## User actions and replies

Buttons are presentation state until an explicit user click or keyboard
activation. The UI calls the native session with the opaque button ID; native
code re-resolves that ID against the current session, active screen, visible
viewport, fold projection and validity before doing anything.

- Custom activation writes exactly `CSI ? 1337 ; <code> ~` to the originating
  PTY. The OSC payload cannot choose another response grammar or executable
  action.
- Copy activation returns the exact retained text of the referenced completed
  OSC 1337 block. The example product writes that text to the system clipboard
  only after the explicit gesture. Native parsing never touches the clipboard.
- Disabled custom buttons remain visible at reduced opacity and expose a
  disabled accessibility state. They cannot be activated.
- Missing, hidden, off-viewport, evicted, invalidated, wrong-screen,
  cross-session and stale IDs fail closed.

Copy extraction requires the complete referenced block range to remain in the
bounded terminal history. It does not return a truncated prefix after history
eviction.

## Frame and rendering contract

`TerminalFrameDiff.inline_buttons` is an additive full-state collection.
Protobuf frame tag `32` carries `TerminalInlineButton`; no existing tag is
reused. Each item contains its opaque ID, kind, viewport row/column, fixed
four-cell width, validity and either a block ID or custom code/icon.

Folded block interiors do not export buttons. Primary marks use absolute
history rows; alternate-screen marks use transient grid rows and are cleared
when that screen is cleared or exited. Width reflow is reconstructed from the
bounded session transcript; direct unsafe reflow invalidates button marks.

Flutter overlays the reserved cells with compact Material controls using
terminal theme colors. Copy uses the platform-neutral copy glyph. Common SF
Symbol names map to equivalent Material icons; other bounded names use a
generic button glyph while remaining presentation-only. Tooltip, semantic
label, mouse, Tab traversal, Enter and Space activation are supported.

## Bounds and trust boundary

- OSC ingress class: terminal `Appearance`, 4 KiB payload limit.
- Retained buttons: 512.
- Icon: 128 Unicode scalar values, non-empty, no controls.
- Copy block ID: the existing 256-scalar block bound.
- Custom code: `1..=2147483647`.
- Reserved width: exactly four cells.
- Button IDs are monotonic for a session across clear, alternate-screen exit
  and RIS, so an old frame cannot collide with a newly created button.

The protocol cannot execute icon or label text, launch processes, open URLs,
read files, focus applications, choose arbitrary PTY bytes, or access the
clipboard without an explicit product gesture.

## Reference behavior

The implementation was compared with the official iTerm2 escape-code
documentation and iTerm2 source commit
`2c6c17162f5fc979e0933714803f1a4a7f1fffa3`, including `VT100Terminal.m`,
`VT100ScreenMutableState+TerminalDelegate.m`, `PTYSession.m`,
`Marks/ButtonMark.swift`, and `TerminalView/TerminalButton.swift`. iTerm2 3.6.9+
documents the same copy/custom forms, four-space advance, global custom
invalidation and fixed `CSI ? 1337 ; code ~` reply.
