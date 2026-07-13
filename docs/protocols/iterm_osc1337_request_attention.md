# iTerm2 OSC 1337 RequestAttention

Ianvs supports the four documented iTerm2 attention actions through a closed,
policy-gated contract:

```text
OSC 1337 ; RequestAttention=yes ST
OSC 1337 ; RequestAttention=once ST
OSC 1337 ; RequestAttention=no ST
OSC 1337 ; RequestAttention=fireworks ST
```

BEL and ST terminators are accepted. The key and value are exact and
case-sensitive; empty values, whitespace variants, unknown actions, and near
matches are ignored.

## Product behavior

| Action | Allowed behavior |
| --- | --- |
| `yes` | Request critical AppKit user attention. |
| `once` | Request informational AppKit user attention. |
| `no` | Cancel the outstanding AppKit request owned by that terminal session. |
| `fireworks` | Show a short, cursor-local, theme-derived visual effect. |

The persistent default is **Deny**. Users may choose **Allow with limits** in
Defaults & appearance. `no` remains effective while Deny is selected so a
terminal can always retract an earlier request.

Ianvs never activates the app, steals focus, posts Notification Center content,
opens a URL, reads host data, or executes a command for this protocol. Dock
attention may be requested by a background session because its purpose is to
signal that the user may want to return to the app.

## Bounds and lifecycle

- The parser classifies RequestAttention as Notification ingress under the
  existing 8 KiB OSC payload ceiling. Parsing grants no host authority.
- Native events contain only `source=iterm1337` and the closed `action` value.
- AppKit request IDs are retained per terminal session and only Ianvs-owned IDs
  may be cancelled.
- At most eight AppKit requests may be outstanding across the app. Requests are
  limited by a two-second per-session cooldown and a 750 ms global cooldown.
- Fireworks use an 800 ms per-session cooldown, a 400 ms animation, and a 420 ms
  total lifetime.
- A repeated allowed request replaces the session's prior owned request after
  the cooldown. Burst requests inside a cooldown are dropped.
- Session exit, close, reset, policy disable, and widget disposal cancel owned
  AppKit requests and clear visual effects. Epoch validation cancels a platform
  request that completes after its session or permission has gone away.
- VT220 profiles deny the event. Native resize replay consumes parser state
  without re-delivering the host request.

## Fireworks accessibility and rendering

The visual effect is placed from the current live frame's cursor and measured
cell geometry, clamped to the pane viewport. It is not shown while the user is
viewing retained scrollback. Colors come from the app theme's accent, warning,
and success tokens. The overlay ignores pointer input, is isolated by a
`RepaintBoundary`, and exposes a live-region semantic label: `Terminal requested
attention`.

When Reduce Motion is enabled, Ianvs renders a static burst for the same bounded
lifetime instead of animating it.

## Wire-to-product path

The vendored parser emits a payload-free closed enum. Native session code
independently validates it and sends:

```json
{
  "kind": "attention_request",
  "payload": {"source": "iterm1337", "action": "once"}
}
```

The Dart runtime validates the source and action again before ShellScreen
applies the persistent policy, rate limits, session ownership, and AppKit or
cursor-local product effect. Diagnostics retain only the source and action;
terminal content is not copied into logs.

## Evidence

Coverage includes exact and invalid parser inputs, BEL/ST and every-byte splits,
Notification-capability denial, shared corpus recovery, native privacy-safe
mapping, real-PTY four-action ordering, VT220 denial, resize non-redelivery,
strict Dart routing, persistent configuration, default Deny, burst suppression,
owned cancellation, Reduce Motion semantics, cursor-local rendering, AppKit
mapping/ownership, and application real-PTY delivery. Final cold-launch Computer
Use acceptance visibly covered the cursor-local effect, all four actions,
background no-focus behavior, cancellation, and continued shell input.

Official references:

- [iTerm2 proprietary escape codes](https://iterm2.com/documentation-escape-codes.html)
- [NSApplication requestUserAttention](https://developer.apple.com/documentation/appkit/nsapplication/requestuserattention(_:))
- [NSApplication cancelUserAttentionRequest](https://developer.apple.com/documentation/appkit/nsapplication/canceluserattentionrequest(_:))
