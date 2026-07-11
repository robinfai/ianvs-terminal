# Kitty OSC 99 safe notification subset

Status: supported safe subset on `codex/osc99-safe-subset-20260711`.

Normative upstream syntax: [Kitty desktop notifications](https://sw.kovidgoyal.net/kitty/desktop-notifications/).

## Wire grammar

Ianvs accepts the Kitty form:

```text
ESC ] 99 ; metadata ; payload ESC \
```

BEL termination is accepted for compatibility. Metadata is a colon-separated
list of one-character keys. Unknown keys are consumed without granting a host
capability.

The supported payload types are:

- `p=title` (default) and `p=body`;
- `p=close` for a known `i=` identifier;
- `p=?` for a static capability query.

The supported metadata is:

- `i=`: notification identity for chunking, update and close;
- `d=0|1`: incomplete/complete chunk lifecycle;
- `e=0|1`: plain UTF-8 or Base64 UTF-8 payload;
- `f=`: Base64 UTF-8 application name;
- repeated `t=`: Base64 UTF-8 notification type;
- `w=-1..4294967295`: platform expiry, never-expire, or positive milliseconds;
- `o=always`: the only advertised occasion.

A new completed notification with a still-active identifier is emitted as an
`update`. `p=close` is a no-op for a missing or unknown identifier. A body-only
notification promotes its body to the visible title, matching Kitty fallback
semantics. Notifications without an identifier are never correlated.

## Capability query

For:

```text
ESC ] 99 ; i=<id>:p=? ; ESC \
```

Ianvs replies:

```text
ESC ] 99 ; i=<id>:p=? ; o=always:p=title,body,close:w=1 ESC \
```

The response deliberately omits actions, close reports, buttons, icons, sound,
urgency and activation callbacks.

## Bounds and recovery

- one OSC notification sequence: 8 KiB streaming admission ceiling;
- metadata: 1,024 bytes;
- plain/decoded chunk: 2,048 bytes;
- encoded chunk: 4,096 bytes;
- identifier: 128 bytes;
- assembled title/body: 160/512 Unicode scalars;
- application/type: 160/64 Unicode scalars;
- types per notification: 8;
- pending and active identifiers: 64 each;
- expiry: unsigned 32-bit milliseconds after the protocol `-1` sentinel.

Malformed metadata, UTF-8, Base64, unsupported payload types and oversized
chunks fail closed. Split OSC input, split terminators and in-flight assemblies
survive the terminal snapshot/restore path. Diagnostics record only action,
counts, lengths, hashes and expiry metadata, never identifiers or text.

## Product and security behavior

OSC 99 maps into the existing typed notification path with
`source=osc99`, `action=show|update|close`, and optional identity, application,
types and expiry. The Flutter product correlates by session plus protocol ID,
removes closed/expired state, and uses a stable macOS notification identifier so
updates replace prior delivery.

Parsing never authorizes host execution. Buttons, arbitrary activation/focus
callbacks, close-event reports, sound selection, icon transfer, commands and
other shell-provided actions are not implemented. System delivery still obeys
the existing Ianvs notification preference, inactive-session and rate-limit
policy. VT220 and a denied notification capability do not expose OSC 99.
