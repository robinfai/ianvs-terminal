# iTerm2 OSC 6 incremental tab color

Ianvs supports iTerm2's session-local incremental tab-color controls:

```text
OSC 6 ; 1 ; bg ; red   ; brightness ; N ST
OSC 6 ; 1 ; bg ; green ; brightness ; N ST
OSC 6 ; 1 ; bg ; blue  ; brightness ; N ST
OSC 6 ; 1 ; bg ; * ; default ST
```

`N` is an exact decimal integer from 0 through 255. `ST` may be BEL or
`ESC \\`. Each component request preserves the other two components from the
current session tab color. If no profile or prior runtime color exists, the
composition starts from black. The exact default request restores the profile's
configured tab color, or removes the runtime tab-color affordance when the
profile has none. There is no protocol reply.

## Product contract

The composed color crosses the existing optional `tab_color` frame field and
uses Ianvs's existing live tab-color affordance. Incremental red, green and blue
frames rebuild the owning shell chrome without requiring unrelated title
metadata. Reset returns to the profile baseline instead of hard-coding an
application color.

Runtime color survives normal frame deltas, snapshots and transcript-backed
resize replay. RIS restores the profile baseline. The separate iTerm2 OSC 1337
`SetColors=tab=...` path shares the same current color and reset baseline.

iTerm2's form is recognized only after the exact `6;1;bg` prefix. Other OSC 6
payloads continue through Ianvs's pre-existing xterm special-color attribute
mode implementation. Once the iTerm2 prefix matches, wrong field counts,
component/action casing, non-decimal values and values outside 0-255 are
consumed as bounded no-ops rather than being reinterpreted as xterm modes.

## Policy and lifecycle

OSC 6 remains classified as Appearance by the streaming gate. Disabling that
capability consumes the sequence without changing the profile baseline or
runtime color; VT220 profiles likewise deny it. The state is session-local and
cannot read or write files, use the clipboard or network, change profiles,
activate the app, send notifications, disclose data, or authorize host actions.

## Evidence

Automated coverage includes mixed BEL/ST termination, every-byte input,
fragmented ST, strict malformed values, RGB component composition, profile
reset, snapshot/RIS, Appearance denial, coexistence with xterm OSC 6, mirrored
shared corpus, semantic probes, native real-PTY frames, JSON/protobuf parity,
resize replay, VT220 denial, Flutter widget pixels, macOS application real-PTY
rendering and continued input.

The contract was compared with the current
[iTerm2 escape-code documentation](https://iterm2.com/documentation-escape-codes.html)
and iTerm2 source revision `7c0361f5afe234bfa255ce486065eb964c7ca01a`.
`sources/VT100/VT100Terminal.m` defines the exact grammar and component range;
`sources/VT100Screen/VT100ScreenMutableState+TerminalDelegate.m` routes each
component to the owning session; and `sources/PTYSession/PTYSession.m` composes
against the current tab color (black when absent) and restores saved profile
settings for the default action.
