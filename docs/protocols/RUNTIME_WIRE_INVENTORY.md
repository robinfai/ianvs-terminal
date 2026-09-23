# Runtime Wire Inventory

This is the current Dart/Rust FFI boundary, aligned with the exact exported function set in
[`ianvs_core_abi_v1.json`](../../native/core/ianvs_core_abi_v1.json). Native Dart bindings require
the current ABI at load time. There is no predecessor-library negotiation or downgrade chain.
Classification describes responsibility; high-volume bytes use specialized Protobuf/byte paths
rather than JSON Runtime Envelopes.

| FFI symbol | Class | Payload / ownership | Current contract |
|---|---|---|---|
| `ianvs_ping` | control | integer health result | ABI v1 |
| `ianvs_runtime_capabilities_json` | control | owned Runtime Capabilities JSON | Runtime Capabilities v1 |
| `ianvs_ssh_import_profiles_json` | import | borrowed OpenSSH config path, owned import JSON | bounded SSH profile import |
| `ianvs_session_create_v1` | command/config | borrowed product-neutral SessionConfig JSON | SessionConfig v1 |
| `ianvs_replay_session_create_v1` | command/config | borrowed product-neutral SessionConfig JSON | SessionConfig v1 |
| `ianvs_replay_session_output` | command | borrowed PTY bytes | explicit length |
| `ianvs_replay_session_exit` | command | session id and optional exit code | ABI v1 |
| `ianvs_replay_session_checkpoint_capture` | command | session id to checkpoint id | replay checkpoint |
| `ianvs_replay_session_checkpoint_restore` | command | session and checkpoint identity | replay checkpoint |
| `ianvs_session_close` | command | session id | ABI v1 |
| `ianvs_session_refresh_hint` | control | session id to bit flags | refresh hint v1 |
| `ianvs_session_resize_with_cell_size` | command | rows/columns/pixel/cell geometry | ABI v1 |
| `ianvs_session_write` | command | borrowed input bytes | explicit length |
| `ianvs_session_write_protocol_reply` | host response | borrowed terminal reply bytes ordered or deferred behind native ZMODEM state | explicit length |
| `ianvs_session_scroll` | command | relative line delta | ABI v1 |
| `ianvs_session_scroll_to` | command | absolute scrollback offset | ABI v1 |
| `ianvs_session_request_v1_json` | command/response | borrowed correlated request, owned response JSON | Session Request/Response v1 |
| `ianvs_session_host_response_v1_json` | host response | borrowed correlated response JSON | Host Response v1 |
| `ianvs_session_take_frame_packet_v1_protobuf` | frame | owned correlated Protobuf packet plus length | Frame Packet v1 |
| `ianvs_session_take_diagnostic_event_v1_json` | diagnostic | owned Runtime Envelope JSON | Diagnostic Event v1 |
| `ianvs_session_poll_event_envelopes_json` | event | owned correlated Runtime Event batch JSON | Runtime Event Envelope v1 |
| `ianvs_session_graphic_asset_packet_v1_protobuf` | asset transfer | owned correlated Protobuf packet plus length | Graphic Asset Packet v1 |
| `ianvs_session_file_download_take` | asset transfer | caller-owned byte destination | one-shot identity plus explicit length |
| `ianvs_session_file_download_discard` | asset transfer | session/download identity | file download v1 |
| `ianvs_string_free` | ownership | releases native-owned UTF-8 strings | matching native allocator |
| `ianvs_bytes_free` | ownership | releases native-owned bytes with matching length | matching native allocator |

## Current boundaries

- Live/replay creation accepts only the closed SessionConfig v1 shape. App Profile persistence
  remains outside this wire.
- Search, selection, recording and other generic commands use Session Request/Response v1;
  operation-specific clients own payload semantics.
- OSC 52 text clipboard reads use Runtime Event `host_request` and correlated Host Response v1.
  One-way URL, attention, notification and asset-transfer events remain separate. Other terminal
  protocol replies use the explicit byte channel so ZMODEM ordering remains authoritative.
- Frame/Session metrics use Diagnostic Event v1. The `terminal.export_diagnostics` evidence
  package is a separate privacy-preserving operation payload.
- Frame Packet v1 carries session identity, sequence and timestamp around `terminal-frame-diff-v1`.
  Dart acknowledges only accepted packets; stale acknowledgement requests a native Snapshot.
- Graphic Asset Packet v1 atomically transfers session/asset/version identity, dimensions and
  bounded decoded RGBA. File downloads retain their dedicated one-shot byte channel.

Predecessor Profile-shaped create, unversioned request/event, Frame JSON/Protobuf, debug-stat,
resize-without-cell-size, search/selection and graphic metadata/copy exports are removed.
Internal JSON codecs, standard terminal escape-sequence aliases and optional capabilities on
custom Dart backends do not reintroduce those native ABI paths.

The standalone `ianvs_terminal_core` package mirrors these canonical sources and the same ABI
manifest. `make terminal-core-check` rejects source drift; the binary-contract gate also checks
actual dynamic-library exports against the manifest.
