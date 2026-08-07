# Runtime Capabilities V1

Runtime Capabilities v1 is a read-only compatibility query for the native core. It inventories
the wire surfaces compiled into the loaded library; it does not replace those surfaces or prove
that a product or host enables them.

The JSON object has this shape:

```json
{
  "schema_version": 1,
  "runtime_contract": "ianvs-runtime-contract-v1",
  "frame_schema_versions": ["terminal-frame-diff-v1"],
  "recording_schema_versions": [1],
  "features": [
    "diagnostic-event.json.v1",
    "diagnostics.json.v1",
    "event-envelope.json.v1",
    "file-download.v1",
    "frame-packet.protobuf.v1",
    "frame.json.v1",
    "frame.protobuf.v1",
    "graphic-asset-packet.protobuf.v1",
    "graphic-asset.rgba.v1",
    "host-request-response.json.v1",
    "refresh-hint.v1",
    "replay-checkpoint.v1",
    "replay-session.v1",
    "session-config.json.v1",
    "session-recording.v1",
    "session-request-envelope.json.v1",
    "session-request.json.v1",
    "zmodem.receive.v1",
    "zmodem.send.v1"
  ]
}
```

The example above is the manifest emitted on macOS and Linux. `zmodem.receive.v1` is
advertised only when the core can anchor receive operations to a stable Unix
directory file descriptor; the supported native-core targets are currently
macOS and Linux. The repository's example product has a macOS runner and file
dialogs; it does not currently provide a Linux product runner. Other native
builds omit both ZMODEM feature ids and fail file
authorization closed as `unsupported_platform`; they do not advertise send
until they have an atomic, no-follow file-open implementation.
The Session Response v1 error preserves `unsupported_platform` as its public
structured error code; other internal ZMODEM/runtime failures remain collapsed
to the bounded `runtime_error` contract.

The native producer emits feature ids in sorted order without duplicates. Dart accepts additive
unknown object fields and retains unknown feature ids so a v1 consumer can inspect a newer v1
producer. It rejects malformed fields, unsupported schema versions, the wrong contract id,
duplicate entries and values outside the documented bounds.

`ianvs_runtime_capabilities_json` returns a library-owned UTF-8 JSON string. Callers release a
non-null result with `ianvs_string_free`. The symbol is optional on the Dart side: a library built
before T-318 reports no manifest and continues through the existing symbol-probing paths.

T-318 introduced this query without changing existing payloads. T-319 later added
`event-envelope.json.v1` as the first independently scoped migration while retaining the legacy
event array. Later command, frame, diagnostic or asset migrations still require their own
versioned task and compatibility tests.

T-320 adds `session-config.json.v1`. It means the optional live and replay SessionConfig v1
entrypoints are compiled into the library; callers still probe the symbols and retain the legacy
Profile-shaped create path during the explicit compatibility window.

T-321 adds `session-request-envelope.json.v1` for the optional correlated Session
Request/Response v1 entrypoint. The older `session-request.json.v1` feature continues to identify
the legacy discriminated request channel; callers keep that fallback until a separately approved
compatibility-window removal.

T-322 adds `host-request-response.json.v1` for the optional native-to-product Host Request v1
event mapping and `ianvs_session_host_response_v1_json` response symbol. The initial operation is
the OSC 52 text clipboard read; legacy event polling and direct PTY response remain supported.

T-323 adds `diagnostic-event.json.v1` for the typed Frame/Session diagnostic envelope while
retaining `diagnostics.json.v1` and both legacy debug-stat symbols.

T-324 adds `frame-packet.protobuf.v1` for the correlated, sequenced Protobuf packet around the
unchanged `terminal-frame-diff-v1` payload. Callers still probe the optional symbol and retain the
legacy Protobuf and JSON Frame paths during the compatibility window.

T-330 adds `graphic-asset-packet.protobuf.v1` for an atomic identity, dimensions and decoded-RGBA
asset transfer. Callers still probe the optional symbol and retain `graphic-asset.rgba.v1` plus the
legacy metadata/copy symbols when loading an older library.

ZMODEM v1 adds the independently scoped `zmodem.receive.v1` and
`zmodem.send.v1` ids. Receive is present only on builds with the supported
stable-dirfd implementation (currently macOS and Linux); other builds omit that id and reject
receive authorization. Send is likewise advertised only on macOS and Linux,
where opening the selected regular file with `O_NOFOLLOW` makes the authority
check atomic.
The `zmodem-unsupported-platform` Windows CI job executes the public request
surface on a real unsupported target and asserts both capability omission and
structured `unsupported_platform` errors for receive and send authorization.
These ids describe the session request/event surface and native byte-stream
engine; the product still owns per-transfer file selection and authorization.
See [ZMODEM_V1.md](ZMODEM_V1.md).
