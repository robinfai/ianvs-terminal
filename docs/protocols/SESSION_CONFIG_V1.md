# SessionConfig V1

SessionConfig v1 is the product-neutral contract used to create live or headless replay sessions.
It is the only live/replay creation wire. App Profile storage remains a separate contract.

```json
{
  "schema_version": 1,
  "contract": "ianvs-session-config-v1",
  "session_id": "runtime-1",
  "display_name": "zsh",
  "client_capabilities": {
    "zmodem": true
  },
  "config": {
    "launch": {
      "program": "/bin/zsh",
      "args": ["-l"],
      "env": {"TERM_PROGRAM": "ianvs-terminal"},
      "cwd": "/tmp"
    },
    "connection": {"type": "local"},
    "terminal": {
      "emulation": "xterm256",
      "scrollbackLines": 8000,
      "graphics": {
        "enabled": true,
        "advertise": "kitty",
        "maxImageBytes": 104857600,
        "maxTotalBytes": 268435456
      },
      "dragDropEnabled": false
    },
    "shellIntegration": {"enabled": true},
    "appearance": {
      "font": {
        "family": "JetBrainsMono Nerd Font Mono",
        "fallback": ["Menlo"],
        "size": 14.0,
        "lineHeight": 1.6
      },
      "colors": {
        "special": {"foreground": null, "background": null, "cursor": null, "selection": null, "tab": null},
        "normal": {"black": null, "red": null, "green": null, "yellow": null, "blue": null, "magenta": null, "cyan": null, "white": null},
        "bright": {"black": null, "red": null, "green": null, "yellow": null, "blue": null, "magenta": null, "cyan": null, "white": null}
      },
      "cursor": {"shape": "block", "blink": true}
    },
    "interaction": {
      "copyOnSelect": false,
      "optionDragMode": "block_selection"
    }
  }
}
```

The encoded UTF-8 document is limited to 1 MiB. `session_id` and `display_name` are runtime
identity only; they are not application Profile identifiers. The `config` object is the declared
wire form of `TerminalSessionConfig`, and does not accept the legacy top-level `shell`, `args`,
`env`, `cwd` or `terminalEmulation` aliases.

SessionConfig v1 uses closed objects and exact, case-sensitive field names and enum values.
Missing required fields, unknown fields, aliases, unsupported schema/contract, invalid identity
and values outside collection/string/finite-number bounds are rejected by both Dart and Rust.
Nullable fields such as `launch.cwd` and color entries must still be present; null selects the
corresponding default rather than making the key optional. Schema evolution requires an explicit
contract change. Optional SSH shell-integration fields are described below.

`client_capabilities` and its boolean `zmodem` field are required. Sending `false` leaves live
ZMODEM bytes raw; sending `true` opts into native detection, authorization and transfer handling.
This is a client feature choice, not negotiation with an older native library. Replay sessions
ignore this live-transport capability.

`ianvs_session_create_v1` and `ianvs_replay_session_create_v1` are required native symbols.
Runtime Capabilities advertises `session-config.json.v1`. The predecessor Profile-shaped create
symbols and Dart encoder have been removed; a mismatched library cannot trigger a downgrade.

### SSH shell integration options

`config.shellIntegration` requires `enabled` and additionally accepts optional boolean
`sshWrapper` and `sshAutoInject`. Omitted `sshWrapper` defaults to false in the core.
Omitted `sshAutoInject` preserves host-level inheritance; explicit false disables
automatic SSH bootstrap. Explicit null and non-boolean values are rejected at the
v1 runtime boundary. Existing `{ "enabled": true }` documents remain valid.

SFTP directory/file start payloads accept optional `contextId`; omission retains
the root endpoint API. A context is resolved once at request acceptance. Stale or
inactive contexts fail, and transfers and atomic rename keep the captured route.
