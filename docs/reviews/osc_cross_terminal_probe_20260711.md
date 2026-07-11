# Cross-terminal OSC semantic probe — 2026-07-11

## Probe inventory

`python3 tools/osc_semantic_probe.py --self-test` passed with 10 deterministic
semantic intents: title, cwd, hyperlink with ID, clipboard copy/query,
prompt/command/output, notification, progress, badge and user variable.
`python3 tools/validate_osc_protocol_corpus.py` passed all 15 required framing
and malformed-input classes, including tmux and screen passthrough fixtures.

Detected reference/intermediary versions:

- iTerm2 3.6.11;
- Ghostty 1.2.3;
- tmux 3.6a;
- GNU Screen 4.00.03.

## Reference-terminal attempt

Computer Use was initialized through its required Node/Sky wrapper. Both actual
reference-terminal targets were then attempted:

| Terminal | Result | Reason |
|---|---|---|
| iTerm2 3.6.11 | not executed | Computer Use returned: terminal app `com.googlecode.iterm2` is not allowed for safety reasons |
| Ghostty 1.2.3 | not executed | Computer Use returned: terminal app `com.mitchellh.ghostty` is not allowed for safety reasons |

No AppleScript, accessibility bypass, screen scraping or alternate UI automation
was used. Therefore the required consumed/raw-echo/host-action/reply/ID/security
observations are **unproven**, not failed and not passed. In particular, this
record makes no clipboard, notification or OSC 934 interoperability claim.

## Automated evidence that remains valid

The shared byte corpus proves Ianvs handling of BEL/ST, split ESC/ST/UTF-8,
missing/empty/duplicate parameters, oversized payload, malformed Base64 and
percent encoding, unknown keys, mixed supported/unsupported sequences and
tmux/screen wrappers. This is Ianvs compatibility evidence only; it does not
substitute for a real reference-terminal observation.

## Manual completion command

In a disposable shell inside one reference terminal, inspect escaped probes
before opting into raw host-action cases:

```bash
python3 tools/osc_semantic_probe.py --intent all --format escaped
python3 tools/osc_semantic_probe.py --intent title --format raw
python3 tools/osc_semantic_probe.py --intent hyperlink_with_id --format raw
```

Clipboard and notification raw probes require explicit operator consent. Record
for each intent: consumed, raw bytes echoed, host action, reply bytes,
ID/metadata retention and security default.
