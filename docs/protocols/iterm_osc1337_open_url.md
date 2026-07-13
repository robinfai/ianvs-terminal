# iTerm2 OSC 1337 OpenURL

Ianvs supports the bounded request form:

```text
OSC 1337 ; OpenURL=: BASE64_URL ST
```

The URL is decoded with strict standard Base64 and strict UTF-8. Parsing a
valid sequence creates an untrusted request event only; it never opens a URL,
raises a window, steals focus, or grants generic host-action authority.

## Accepted subset

- decoded URL size: 1–4,096 UTF-8 bytes;
- no leading/trailing whitespace or control characters;
- `http` and `https` require a non-empty host;
- `file` requires an empty host and a non-root local path;
- all other schemes, malformed Base64/UTF-8, empty targets and malformed URLs
  are ignored;
- Xterm256 sessions only; VT220 sessions reject the sequence.

The streaming ingress gate classifies the sequence as a bounded hyperlink
request. The independent host-action capability remains disabled. The parser,
native session bridge, Dart runtime, product policy, and macOS platform bridge
each validate the target before the final side effect.

## Product authorization

The persistent global policy defaults to **Ask every time** and can be changed
to **Deny** in Defaults & appearance. A request can show a dialog only when its
source session is the active pane. The dialog shows the scheme/host or local
file class and the complete URL. It has explicit **Deny** and **Open** actions.

There is at most one active prompt, with a five-second burst cooldown. Requests
from inactive panes, requests received while a prompt is active, and requests
during the cooldown are dropped. After approval, the product rechecks that the
source session is still active. A `file:` target uses this same approval as its
file-link permission, avoiding a misleading second confirmation.

The platform bridge independently accepts only hosted `http`/`https` targets
and hostless, non-root local `file` targets. No terminal sequence can call it
directly.

## Privacy, replay, and compatibility

Runtime event payloads contain the validated URL so the confirmation dialog can
show the exact destination. Diagnostics retain only source, scheme, character
count, and a keyed hash; they never record the URL or host. The native event
queue remains count/byte bounded, and transcript resize replay drains historical
requests without re-emitting them.

No frame or protobuf schema changes are required. The local-config addition is
optional and defaults to Ask; the legacy `deny` spelling maps to Disabled.
Reverting Phase 29 returns OpenURL to a bounded unsupported OSC 1337 no-op.

The behavior follows the official
[iTerm2 proprietary escape-code documentation](https://iterm2.com/documentation-escape-codes.html),
with a deliberately explicit active-pane authorization boundary because PTY
output is untrusted.
