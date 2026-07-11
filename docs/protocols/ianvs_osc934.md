# Ianvs OSC 934 named progress protocol

## Status and scope

OSC 934 is an Ianvs/par-term private protocol for session-scoped named progress
presentation. It is not an ECMA-48, xterm, iTerm2, Kitty, WezTerm, or VS Code
protocol. The stable version token for the wire shape in this document is
`ianvs-osc934/1`.

Progress state is presentation metadata only. Receiving this protocol must not
start or stop a process, change command lifecycle state, execute a command,
open a link, read or write the clipboard, access a file, or grant any host
permission.

Applications must discover support with the query below. `$TERM`, terminal
brand detection, and the presence of another OSC protocol are not claims of
OSC 934 support.

## Framing and grammar

The canonical introducer is `ESC ]` and the canonical emitted terminator is ST
(`ESC \`). The parser accepts either ST or BEL (`0x07`) on input. Parameters
are UTF-8 byte strings separated by the literal semicolon byte.

```text
OSC       = ESC "]" payload (ST / BEL)
payload   = set / remove / remove-all / query

set       = "934;set;" id *(";" property)
remove    = "934;remove;" id
remove-all= "934;remove_all"
query     = "934;query"

property  = "percent=" uint
          / "label=" label
          / "state=" state
          / extension-property

state     = "normal" / "indeterminate" / "warning" / "error" / "hidden"
uint      = 1*DIGIT
ST        = ESC "\\"
```

There is no quoting or escaping layer in version 1. Consequently, an ID,
label, key, or value cannot contain a semicolon or an OSC terminator. Senders
that need those values must choose a safe display representation before
encoding the command.

## Fields and limits

Lengths are measured after framing is removed and in UTF-8 bytes, not Unicode
scalar values.

| Item | Version 1 limit | Receiver behavior when invalid or over the limit |
|---|---:|---|
| complete `934;...` payload | at most 8,192 bytes | discard the command above 8,192 bytes |
| ID | 1–128 bytes | discard the command if empty, oversized, invalid UTF-8, or contains a control character |
| label | 1–1,024 bytes | ignore that property if empty, oversized, invalid UTF-8, or contains a control character |
| percent | decimal integer in `0..=65535` | clamp valid integers above 100 to 100; ignore invalid integers |
| active IDs per terminal session | 64 | reject a new ID; continue to allow updates/removals for retained IDs |

The streaming OSC boundary must apply the 8 KiB limit while bytes arrive, so
an unterminated or oversized command cannot first grow an unbounded parser
buffer. The command parser repeats the limit check as defense in depth.

Leading and trailing Unicode whitespace is removed from the action, ID, key,
and value. IDs and labels remain untrusted presentation text even after these
checks.

## Command semantics and lifecycle

### `set`

`set` creates an ID or replaces the complete record for an existing ID.
Version 1 is replacement, not patch, semantics: omitted fields return to the
defaults `state=normal`, `percent=0`, and no label. A valid duplicate recognized
property replaces the previous valid value in the same command. Unknown
properties and malformed recognized properties are ignored.

`hidden` retains the record but marks it inactive. It is not equivalent to
`remove`; a later `set` may make the same ID visible again.

### `remove`

`remove` deletes one retained ID. Removing an unknown ID is an idempotent no-op
and does not emit a progress-change event.

### `remove_all`

`remove_all` deletes every retained ID in the current terminal session. It is
an idempotent no-op when the map is already empty. A receiver may ignore
trailing fields on `remove` and `remove_all` for compatibility, but senders
must not emit them in version 1.

Named progress survives ordinary primary/alternate screen transitions because
it belongs to the terminal session, not a screen buffer. Closing the session
destroys all retained progress state. Progress does not imply that a command is
running or that a process has completed.

## Capability discovery

A client requests the version 1 static descriptor with:

```text
ESC ] 934;query ESC \
```

A supporting receiver writes this exact canonical response to the terminal
device response channel:

```text
ESC ] 934;capability;ianvs-osc934/1;actions=set,remove,remove_all;states=normal,indeterminate,warning,error,hidden ESC \
```

The response contains static constants only. It must not expose active IDs,
labels, percentages, session identifiers, environment values, or terminal
contents. `query` with extra fields is malformed and gets no response.
`capability` is not an input command; receiving a capability response as normal
terminal output is an unknown action and must not trigger another response.
This prevents response loops.

No response means “not proven supported.” It may also mean an intermediary
filtered the private OSC. Callers must time out and fall back without retrying
in a tight loop.

## Events and stable source identity

Accepted state changes are bridged as typed `session_progress` events. Their
stable source string is:

```text
ianvs_osc934
```

The event payload uses `named=true`, an action (`set`, `remove`, or
`remove_all`), ID, optional state, optional percent, and optional label as
appropriate. The legacy development value `osc934` is not the canonical source
name. Consumers may temporarily accept it while upgrading persisted fixtures,
but producers must emit one event with `ianvs_osc934`, not duplicate old and new
events.

A successful `set`, removal of an existing ID, and non-empty `remove_all` each
emit one state-change event. Invalid commands and idempotent removals emit no
state-change event. A capability query emits only the device response and does
not mutate state or emit a progress event.

## Unknown and malformed input

- Unknown actions are consumed as a no-op and receive no response.
- A missing action or required ID is a no-op.
- An invalid action or ID invalidates the whole command.
- An invalid or unknown property affects only that property.
- Unknown properties are ignored so an older version 1 receiver can safely
  process commands from a sender that adds optional properties.
- A valid recognized duplicate property uses the last valid value.
- Invalid UTF-8 or controls in the action/ID, payload overflow, and incomplete
  framing must not mutate state. An invalid optional property is ignored while
  other valid fields in the command retain their defined effect.
- An unsupported terminal profile or a denied presentation policy consumes the
  command without allowing it to become visible text or a host action.

Receivers should count rejected commands by bounded reason code for diagnostics
but must not include raw payloads in diagnostic events.

## Security, privacy, and redaction

IDs and labels are attacker-controlled terminal output. Renderers must treat
them as text, apply normal escaping, and avoid interpreting markup, URLs, ANSI
sequences, or commands. UI code may truncate further than the wire limits.

Logs, crash annotations, metrics, and protocol diagnostics must not record raw
IDs, labels, unknown properties, or complete OSC payloads. Safe diagnostics are
limited to the protocol/version, action class, accepted/rejected result,
bounded reason code, payload byte count, and active-bar count. Capability
responses are public constants and contain no secret or session-derived data.

Rate limiting and UI coalescing are allowed, but the retained final state must
follow the ordered accepted commands. Presentation policy may suppress display;
it does not authorize another capability.

## Compatibility and versioning

- Version 1 receivers accept BEL or ST input; senders and query responses use
  ST canonically.
- Unknown properties are the only additive extension point inside the version 1
  `set` command.
- A future implementation may add static comma-separated items to a capability
  response only if version 1 readers can ignore them safely.
- Any incompatible grammar, lifecycle, default, or security semantic requires a
  new capability token such as `ianvs-osc934/2`.
- A receiver must never silently reinterpret a version 1 command with version 2
  semantics.
- The private protocol must remain independently policy-gated and must not be
  advertised as another terminal vendor's protocol.

## Examples

```text
ESC ] 934;set;download-1;percent=50;label=Downloading;state=normal ESC \
ESC ] 934;set;build;state=indeterminate;label=Compiling BEL
ESC ] 934;set;build;state=error;label=Build failed ESC \
ESC ] 934;remove;download-1 ESC \
ESC ] 934;remove_all ESC \
```

Automated protocol evidence lives in the OSC 934 parser tests and the Phase 7
review record. Cross-terminal observations are supplemental for this private
protocol and must be recorded only after the referenced terminal was actually
run.
