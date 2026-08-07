# SessionConfig V1

SessionConfig v1 is the product-neutral contract used to create live or headless replay sessions.
It replaces the primary Profile-shaped Dart/native payload without changing app Profile storage.

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
        "special": {},
        "normal": {},
        "bright": {}
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

Schema v1 consumers ignore additive unknown object fields. They reject the wrong schema or
contract, missing/invalid identity, a missing config/launch object, an empty launch program and
values outside documented collection/string/finite-number bounds.

`client_capabilities.zmodem` is an explicit, fail-closed opt-in to native ZMODEM interception.
It defaults to `false` when absent. This protects independently upgraded components:

| Dart client | Native core | Result |
| --- | --- | --- |
| old | old | Legacy raw PTY behavior |
| new | old | SessionConfig v1 is unavailable, so the existing compatibility fallback remains raw |
| old | new | Legacy create omits the opt-in; ZMODEM bytes remain raw and close keeps legacy semantics |
| new | new | SessionConfig v1 sends `zmodem: true`; native detection, authorization and transfer UI are enabled |

Replay sessions ignore this live-transport capability.

The optional `ianvs_session_create_v1` and `ianvs_replay_session_create_v1` symbols consume this
contract. Runtime Capabilities advertises `session-config.json.v1`. During the compatibility
window, the old symbols continue consuming the Profile-shaped wire: new Dart falls back when v1
is unavailable, and old Dart remains usable with a new native core.
