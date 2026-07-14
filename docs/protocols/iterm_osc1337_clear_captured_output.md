# iTerm2 OSC 1337 ClearCapturedOutput

Ianvs supports iTerm2's session-local captured-output clear command:

```text
OSC 1337 ; ClearCapturedOutput ST
```

`ST` may be BEL or `ESC \\`. The command has no reply. It clears the
product-owned Captured Output collection for only the originating session.
Terminal cells, scrollback, shell history, annotations, clipboard state,
graphics, and captured output belonging to other sessions are unchanged.

## Product contract

Ianvs Captured Output contains bounded rows recorded by profile triggers and
coprocess patterns. An exact `ClearCapturedOutput` request removes those entries
for the emitting session. If its Captured Output sheet is open, it immediately
updates to the normal guided empty state instead of retaining a stale copy.

The event follows the session epoch from the native reader to Flutter. Closing
or replacing a session invalidates queued events, and product code filters by
the event's session ID. The xterm-compatible facade consumes the typed event
without inventing a captured-output store.

`ClearCapturedOutput=...`, extra parameters, case variants, and other near
matches are bounded no-ops. The exact request does not clear the terminal grid
or emit visible protocol bytes.

## Policy and lifecycle

The streaming gate classifies the command as shell-integration metadata. It is
accepted by xterm-compatible profiles, consumed without a product event when
Metadata is denied, and denied by the VT220 profile. It is an immediate event,
not snapshot state, so terminal resize replay never redelivers a historical
clear.

No filesystem, clipboard, network, profile, focus, notification, or host-action
authority is involved. There is no persistence or disclosure boundary.

## Evidence

Automated coverage includes exact BEL/ST handling, every-byte and fragmented ST
input, malformed suffixes, policy classification, terminal text/title
preservation, mirrored shared corpus, native event mapping, real-PTY delivery,
VT220 denial, resize non-replay, strict Dart routing, invalid-source rejection,
open-sheet refresh, and continued real-PTY input.

The contract was compared with the current
[iTerm2 escape-code documentation](https://iterm2.com/documentation-escape-codes.html)
and iTerm2 source paths `VT100Terminal.m`,
`VT100ScreenMutableState+TerminalDelegate.m`, and `PTYSession.m`. iTerm2 names
the operation `ClearCapturedOutput` and routes it as a product-owned captured
output change rather than a terminal-buffer clear.
