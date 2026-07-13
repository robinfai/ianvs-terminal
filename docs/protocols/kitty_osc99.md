# Kitty OSC 99 safe interactive notification subset

Status: supported through Phase 31 on
`codex/osc99-interactive-reporting-phase31-20260713`.

Normative upstream syntax: [Kitty desktop notifications](https://sw.kovidgoyal.net/kitty/desktop-notifications/).

## Wire grammar

Ianvs accepts the Kitty form:

```text
ESC ] 99 ; metadata ; payload ESC \
```

BEL termination is accepted for compatibility. Metadata is a colon-separated
list of one-character keys. Unknown non-action keys are consumed without
granting host authority; malformed or unknown action values fail closed.

The supported payload types are:

- `p=title` (default), `p=body`, and `p=buttons`;
- `p=close` for an active identifier;
- `p=?` for a static capability query;
- `p=alive` for the bounded active-identifier query.

The supported metadata is:

- `i=`: notification identity for chunking, update, close, and reports, limited
  to the Kitty identifier alphabet `[A-Za-z0-9_+.-]`;
- `d=0|1`: incomplete/complete chunk lifecycle;
- `e=0|1`: plain UTF-8 or Base64 UTF-8 payload;
- `f=`: Base64 UTF-8 application name;
- repeated `t=`: Base64 UTF-8 notification type;
- `w=-1..4294967295`: platform expiry, never-expire, or positive milliseconds;
- `o=always`: the only advertised occasion;
- `a=report|-report`: enable or disable explicit user-action reports;
- `c=0|1`: enable or disable tracked close reports.

`a=focus` and `a=-focus` are parsed only so a Kitty-compatible action list is
well formed. They never focus, activate, raise, or reorder the Ianvs window.
Sound, icon, urgency, arbitrary commands, and other occasions remain inert.

Button payloads are presentation-only UTF-8 labels separated by U+2028. They
never contain callback text or commands. Empty slots retain their original
one-based ordinal and receive a local `Button N` display label, so sanitization
cannot shift the number reported to the child. A completed notification with a
still-active identifier is emitted as an `update`. The omitted `i=` value uses
Ianvs' bounded canonical identifier `0`, including chunking, update, close, and
alive semantics. A body-only notification promotes its body to the visible
title.

## Queries and reports

For:

```text
ESC ] 99 ; i=<id>:p=? ; ESC \
```

Ianvs replies:

```text
ESC ] 99 ; i=<id>:p=? ; a=report:c=1:o=always:p=title,body,close,alive,buttons:w=1 ESC \
```

For `i=<query-id>:p=alive`, Ianvs first expires native lifecycle state and then
returns active identifiers in deterministic lexical order:

```text
ESC ] 99 ; i=<query-id>:p=alive ; id1,id2 ESC \
```

Ianvs emits action reports only after an explicit gesture in its in-window
notification menu:

```text
# Notification body activation
ESC ] 99 ; i=<id> ; ESC \

# One-based button number
ESC ] 99 ; i=<id> ; <button-number> ESC \

# Explicit dismissal or tracked positive expiry when c=1
ESC ] 99 ; i=<id>:p=close ; ESC \
```

Opening the menu may focus the pane because the user clicked Ianvs UI, but an
OSC action never focuses it by itself. A child-issued `p=close` removes state
without echoing a close report, preventing command/report cycles. macOS system
notifications remain a secondary policy-gated delivery surface; interaction
reports are owned by the attributable in-window menu, not inferred from an
untrackable Notification Center close.

## Bounds and recovery

- one OSC notification sequence: 8 KiB streaming admission ceiling;
- metadata: 1,024 bytes;
- plain/decoded chunk: 2,048 bytes;
- encoded chunk: 4,096 bytes;
- identifier: 128 bytes from `[A-Za-z0-9_+.-]`;
- assembled title/body: 160/512 Unicode scalars;
- application/type: 160/64 Unicode scalars;
- types per notification: 8;
- buttons: 5 labels, 64 Unicode scalars each, 324 assembled scalars including
  separators;
- pending and active identifiers: 64 each;
- expiry: unsigned 32-bit milliseconds after the protocol `-1` sentinel.

Malformed metadata, UTF-8, Base64, action values, close-report values,
unsupported payload types, and oversized chunks fail closed. Split OSC input,
split terminators, action metadata, and in-flight button assemblies survive the
terminal snapshot/restore path. Diagnostics retain only action flags, counts,
lengths, hashes, and expiry metadata—never identifiers, text, or button labels.

## Product and security behavior

OSC 99 maps into the typed notification path with `source=osc99`,
`action=show|update|close`, identity, application, types, expiry, report flags,
and bounded button labels. Flutter correlates by session plus protocol ID,
removes closed/expired state, and uses a stable macOS notification identifier so
updates replace prior delivery.

Before reporting an interaction, the product re-resolves the live pane and
notification, validates the identifier grammar and current button count, and
writes only the fixed report shape to that notification's session. Stale menu
entries, removed sessions, wrong identifiers, and out-of-range buttons are
no-ops. Explicit and timed product dismissal also closes the same bounded ID in
the native lifecycle before any report is written, so a later `p=alive` cannot
resurrect or return dismissed UI state. The shell never supplies the bytes sent
after a click.

System delivery continues to obey the existing notification preference,
inactive-session, and rate-limit policy. OSC 99 cannot execute shell commands,
open links, read files or clipboard data, select sounds or icons, or steal
focus. VT220 and a denied notification capability do not expose OSC 99.

## Acceptance

The repository verifier covers the vendored parser, native typed events and
real PTY, Dart runtime, product lifecycle, widget interaction, macOS build and
RunnerTests. The final cold-launch Computer Use gate exercised a real child and
observed the exact button, activation and close reports, status removal,
continued input, and Finder retaining foreground focus after `a=focus`. The
recorded evidence and remaining Kitty reference-terminal boundary are in the
[Phase 31 review](../reviews/osc99_interactive_reports_phase31_20260713.md).
