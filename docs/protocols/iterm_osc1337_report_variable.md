# iTerm2 OSC 1337 ReportVariable

Ianvs supports a permission-gated subset of iTerm2's variable-report request:

```text
OSC 1337 ; ReportVariable=<Base64 UTF-8 variable name> ST
```

The corresponding reply always uses iTerm2's exact BEL-terminated form:

```text
OSC 1337;ReportVariable=<Base64 UTF-8 value> BEL
```

An empty value means denied, undefined, unsupported, or invalid at a later trust
boundary. The terminal never substitutes a host environment variable, file,
command result, or other ambient process data.

## Supported variables

The surface is deliberately closed to values Ianvs already owns and can
represent accurately:

- `session.name`: the current pane title;
- `session.terminalIconName` and `session.terminalWindowName`: the current
  terminal frame titles;
- `session.columns` and `session.rows`: the current product frame dimensions;
- `session.hostname`, `session.username`, and `session.path`: the current
  bounded shell-integration state;
- `session.shell` and `session.lastCommand`: bounded shell-integration state;
- `session.badge` and `session.profileName`: current pane/profile state;
- `user.*`: a bounded value previously supplied to the terminal with iTerm2
  `SetUserVar`.

Names outside this set receive an empty reply and do not create a permission
prompt. A valid name is at most 256 UTF-8 bytes and contains no control
characters. Input Base64 and UTF-8 decoding are strict. The OSC streaming
payload remains under the 4 KiB metadata limit.

## Permission and response lifecycle

Permission is remembered independently for each exact variable name as
**Always Allow** or **Always Deny**, with at most 64 retained decisions. The
first request for a supported variable always receives an immediate empty
reply. If its session is the active pane, Ianvs then offers a future decision;
the safe focused action is **Always Deny**, while **Not Now** leaves no stored
decision. Terminal output therefore cannot delay the shell while waiting for a
dialog or obtain the value that caused the first prompt.

On a later allowed request, the product re-resolves `session.*` from current
product-owned state instead of trusting a stale parser payload. The native
bridge may attach a bounded candidate for terminal-owned title, dimensions,
shell context, and `user.*`, but the Dart runtime moves it into a private token.
The public event exposes only `source` and `name`; explicit product permission
is required to use the candidate in a reply. Denied, undefined, inactive,
unsupported, malformed, or overflowed requests fail closed with an empty reply
whenever the parser can safely issue a reply token.

Every native event receives a one-shot opaque request token bound to its
session identity and session epoch. Duplicate, stale, closed-session and
cross-session responses are rejected. Runtime queues retain at most 128 pending
tokens, response values are limited to 16 KiB of UTF-8, and queue overflow is
answered empty. The xterm-compatible facade has no permission store and always
answers empty. Automatic replies preserve the user's retained-scrollback
position instead of forcing the viewport back to the live cursor.

Defaults & appearance shows the number of remembered decisions and their
allow/deny totals, and can forget decisions individually or together. Clearing
decisions does not retroactively authorize a pending request. Only one prompt
may be visible, with a 30-second global prompt cooldown to bound modal spam.

## Privacy and compatibility

Diagnostics record only the source, a sanitized name, name/value character
counts, and whether a value was defined; they never record the value. Resize
replay does not redeliver requests, and VT220 sessions reject the OSC sequence.
No frame or Protobuf schema change is required because the request travels
through the existing typed session-event channel.

The wire grammar and empty-denial behavior were compared with the official
[iTerm2 escape-code documentation](https://iterm2.com/documentation-escape-codes.html),
[scripting fundamentals](https://iterm2.com/documentation-scripting-fundamentals.html),
[variable reference](https://iterm2.com/documentation-variables.html), and the
iTerm2 implementation paths `VT100Terminal.m`, `VT100Output.m`, and
`iTermNaggingController.m`. Ianvs intentionally exposes a smaller variable
surface and keeps all host environment and file authority outside this
protocol.
