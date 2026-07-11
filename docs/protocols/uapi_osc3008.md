# UAPI OSC 3008 terminal contexts

Status: supported as bounded, typed, untrusted metadata on
`codex/osc3008-context-prototype-20260711`.

Normative upstream syntax: [UAPI Terminal Context OSC](https://uapi-group.org/specifications/specs/osc_context/).

## Wire grammar

Ianvs accepts the version 1.0 start and end forms:

```text
ESC ] 3008 ; start=<context-id> ; field=value ... ESC \
ESC ] 3008 ; end=<context-id> ; field=value ... ESC \
```

ST is the normative terminator; BEL is also accepted by the shared OSC parser.
Literal semicolon and backslash bytes are decoded from `\x3b` and `\x5c`.
Context IDs must decode to 1–64 printable ASCII bytes. Metadata values must be
valid UTF-8 without control characters.

## Lifecycle

- A new `start=` pushes a child of the active context.
- Starting an existing ID returns to that context, discards its descendants,
  and replaces rather than merges its metadata.
- Ending a known ID ends it and all descendants, then reactivates its parent.
- An unknown or malformed `end=` is ignored without damaging the existing
  hierarchy.
- RIS (`ESC c`) does not clear the hierarchy. Snapshot capture and restore
  preserve it. Closing the terminal session destroys the session-owned stack.
- A 33rd nested context is rejected while all 32 retained contexts remain
  intact.

Each accepted transition emits one `TerminalContextChanged` parser event and
one native `terminal_context` event. Implicit descendant closures are reported
as a count on the explicit transition; they do not create attacker-amplified
per-descendant events.

## Metadata

Common start fields are `type`, `user`, `hostname`, `machineid`, `bootid`,
`pid`, `pidfdid`, and `comm`. Ianvs recognizes every version 1.0 context type:
`boot`, `container`, `vm`, `elevate`, `chpriv`, `subcontext`, `remote`, `shell`,
`command`, `app`, `service`, and `session`.

Type-specific fields are accepted only for their specified context types:

- `cwd`: shell and command;
- `cmdline`: command;
- `vm`: VM;
- `container`: container;
- `targetuser`: elevate, privilege change, VM, container, remote, and session;
- `targethost`: remote;
- `sessionid`: session.

End metadata supports `exit=success|failure|crash|interrupt`, status 0–255, and
a bounded symbolic `SIG...` signal. Field order is arbitrary. An unknown or
invalid individual field is ignored while valid sibling fields remain usable.

## Typed event contract

The additive JSON/Dart event uses `source=osc3008` and exposes action, exact
context identity, resulting depth, active state, context type, bounded common
and type-specific metadata, exit metadata, and `implicitClosedCount`. Dart
surfaces this as `TerminalSessionContextEvent`.

The example product deliberately consumes the event without creating visual
state or taking an action. This keeps protocol metadata available to future
trusted consumers without treating child-process claims about user, host,
privilege, PID, command, or session identity as authority.

## Bounds, policy, and privacy

- OSC ingress class: metadata / shell integration, 16 KiB per sequence;
- hierarchy depth: 32;
- decoded context ID: 64 bytes;
- each decoded text field: 255 UTF-8 bytes;
- numeric PID fields: unsigned 64-bit; exit status: 0–255;
- native and vendor event queues retain their existing independent count and
  byte ceilings.

VT220 and a denied metadata capability consume OSC 3008 without exposing
context state. The protocol cannot authorize execution, privilege changes,
navigation, profile switching, notification delivery, clipboard access, or any
other host action. Diagnostic records preserve only stable action/type/numeric
fields plus text lengths and hashes; they never record raw IDs, paths, commands,
users, hosts, machine IDs, session IDs, or signals.

## Evidence boundary

Automated coverage includes BEL/ST and every byte split, UTF-8 and textual
escapes, all lifecycle recovery rules, metadata replacement, invalid-field
isolation, depth and field limits, snapshot/RIS preservation, diagnostics,
native real PTY, VT220 gating, Dart typed routing, the shared byte corpus, and a
macOS real-PTY integration test. A UAPI reference implementation or another
terminal has not yet been used for interoperability comparison.
