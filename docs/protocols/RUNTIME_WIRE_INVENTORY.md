# Runtime Wire Inventory

This is the current inventory of the Dart/Rust FFI boundary. Classification describes the
payload's responsibility; it does not claim that every row already uses Runtime Envelope v1.

| FFI symbol | Class | Payload / ownership | Current version state |
|---|---|---|---|
| `ianvs_ping` | control | integer health result | unversioned |
| `ianvs_runtime_capabilities_json` | control | owned Runtime Capabilities JSON | v1 |
| `ianvs_session_create` | command/config | borrowed legacy Profile-shaped JSON | unversioned compatibility debt |
| `ianvs_replay_session_create` | command/config | borrowed legacy Profile-shaped JSON | unversioned compatibility debt |
| `ianvs_session_create_v1` | command/config | borrowed product-neutral SessionConfig JSON | optional v1 primary path |
| `ianvs_replay_session_create_v1` | command/config | borrowed product-neutral SessionConfig JSON | optional v1 primary path |
| `ianvs_replay_session_output` | command | borrowed PTY bytes | explicit length, unversioned |
| `ianvs_replay_session_exit` | command | session id and optional exit code | unversioned |
| `ianvs_session_close` | command | session id | unversioned |
| `ianvs_session_refresh_hint` | control | session id to bit flags | unversioned |
| `ianvs_session_resize` | command | rows/columns/pixel geometry | unversioned |
| `ianvs_session_resize_with_cell_size` | command | rows/columns/pixel/cell geometry | unversioned |
| `ianvs_session_write` | command | borrowed input bytes | explicit length, unversioned |
| `ianvs_session_scroll` | command | relative line delta | unversioned |
| `ianvs_session_scroll_to` | command | absolute scrollback offset | unversioned |
| `ianvs_session_search_json` | command/response | borrowed request JSON, owned result JSON | request-specific, unversioned envelope |
| `ianvs_session_selection_text` | command/response | borrowed request JSON, owned UTF-8 text | request-specific, unversioned envelope |
| `ianvs_session_request_json` | command/response | borrowed discriminated request JSON, owned result JSON | unversioned compatibility path |
| `ianvs_session_request_v1_json` | command/response | borrowed correlated Session Request v1, owned Session Response v1 | optional v1 primary path |
| `ianvs_session_host_response_v1_json` | host response | borrowed correlated Host Response v1 | optional v1 response path for v1 Host Requests |
| `ianvs_session_take_frame_diff_json` | frame | owned `terminal-frame-diff-v1` JSON | versioned payload |
| `ianvs_session_take_frame_diff_protobuf` | frame | owned Protobuf bytes plus length | mirrors versioned Frame payload |
| `ianvs_session_take_frame_packet_v1_protobuf` | frame | owned correlated Frame Packet v1 Protobuf plus length | optional v1 primary path |
| `ianvs_session_take_frame_debug_stats_json` | diagnostic | owned frame metrics JSON | unversioned |
| `ianvs_session_take_session_debug_stats_json` | diagnostic | owned session metrics JSON | unversioned |
| `ianvs_session_take_diagnostic_event_v1_json` | diagnostic | owned Diagnostic Event v1 Runtime Envelope | optional v1 primary path |
| `ianvs_session_poll_events_json` | event | owned legacy event JSON array | unversioned legacy path |
| `ianvs_session_graphic_asset_packet_v1_protobuf` | asset transfer | owned correlated Graphic Asset Packet v1 Protobuf plus length | optional v1 primary path |
| `ianvs_session_graphic_asset_meta` | asset transfer | caller-owned metadata destination | explicit fields, unversioned |
| `ianvs_session_graphic_asset_rgba_copy` | asset transfer | caller-owned RGBA destination | identity/version plus explicit length |
| `ianvs_session_file_download_take` | asset transfer | caller-owned byte destination | one-shot identity plus explicit length |
| `ianvs_session_file_download_discard` | asset transfer | session/download identity | unversioned |
| `ianvs_string_free` | ownership | releases native owned UTF-8 strings | allocator contract |
| `ianvs_bytes_free` | ownership | releases native owned bytes with matching length | allocator contract |

T-319 adds `ianvs_session_poll_event_envelopes_json` as the v1 Event path. The legacy poll symbol
remains for old Dart/native combinations. Frames and asset bytes deliberately keep their current
specialized transports; “Envelope” is a semantic governance model, not a requirement to Base64 or
JSON-wrap every high-volume payload.

T-320 adds the two SessionConfig v1 entrypoints and advertises `session-config.json.v1`.
`TerminalRuntimeController` prefers the versioned path when the loaded backend exposes it. The
legacy create symbols and Profile-shaped encoder remain quarantined compatibility surfaces in
both upgrade directions; their removal requires a separate compatibility-window decision.

T-321 adds `ianvs_session_request_v1_json` and advertises
`session-request-envelope.json.v1`. Generic terminal command clients prefer the correlated,
bounded v1 Request/Response envelopes, while the exact legacy `{kind, ...payload}` object and
`ianvs_session_request_json` remain tested in both upgrade directions. This is the synchronous
Dart-to-native command direction.

T-322 adds `ianvs_session_host_response_v1_json`, advertises
`host-request-response.json.v1`, and maps only OSC 52 text clipboard reads to
`message_name: "host_request"` on the v1 Runtime Event path. The legacy event-array symbol still
returns `clipboard_paste_request`, and new Dart keeps its direct PTY reply fallback for older
native libraries. One-way URL, attention, notification and asset-transfer events are not
misclassified as response-bearing requests.

T-323 adds `ianvs_session_take_diagnostic_event_v1_json`, advertises
`diagnostic-event.json.v1`, and migrates the Frame/Session metrics consumers to typed,
correlated Runtime Envelope v1 diagnostics. Both legacy debug-stat symbols retain their exact
payloads and one-shot/snapshot semantics. The separate `terminal.export_diagnostics` evidence
package is not this wire and remains unchanged.

T-324 adds `ianvs_session_take_frame_packet_v1_protobuf`, advertises
`frame-packet.protobuf.v1`, and wraps the unchanged `terminal-frame-diff-v1` Protobuf with exact
session identity, per-session sequence and timestamp. The caller acknowledges only its last
accepted packet; a stale acknowledgement forces the next native extraction to a Snapshot. Both
legacy Frame symbols remain available, and graphic/file bytes remain on their specialized asset
channels.

T-330 adds `ianvs_session_graphic_asset_packet_v1_protobuf`, advertises
`graphic-asset-packet.protobuf.v1`, and transfers exact session/asset/version identity,
dimensions and decoded RGBA atomically under one session-state lock. New Dart falls back to the
unchanged metadata/copy pair only when the optional packet symbol is absent; a null or malformed
packet does not downgrade in the same call. Both legacy symbols remain for old Dart/new native.
