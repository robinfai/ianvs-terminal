# Runtime Capabilities V1

Runtime Capabilities v1 is a read-only contract query for the native core. It inventories
the wire surfaces compiled into the loaded library; it does not replace those surfaces or prove
that a product or host enables them.

The JSON object has this shape:

```json
{
  "schema_version": 1,
  "runtime_contract": "ianvs-runtime-contract-v1",
  "frame_schema_versions": [
    "terminal-frame-diff-v1"
  ],
  "recording_schema_versions": [
    1
  ],
  "features": [
    "diagnostic-event.json.v1",
    "event-envelope.json.v1",
    "file-download.v1",
    "frame-packet.protobuf.v1",
    "graphic-asset-packet.protobuf.v1",
    "host-request-response.json.v1",
    "refresh-hint.v1",
    "replay-checkpoint.v1",
    "replay-session.v1",
    "session-config.json.v1",
    "session-recording.v1",
    "session-request-envelope.json.v1",
    "ssh-session.v1",
    "ssh-sftp-directory-listing.v1",
    "ssh-sftp-file-operations.v1",
    "zmodem.receive.v1",
    "zmodem.send.v1"
  ]
}
```

The example above is the manifest emitted on macOS and Linux. `zmodem.receive.v1` is
advertised only when the core can anchor receive operations to a stable Unix
directory file descriptor; the supported ZMODEM targets are currently
macOS and Linux. The repository's example product has macOS and iOS runners;
it does not currently provide a Linux product runner. Other native builds,
including iOS, omit both ZMODEM feature ids and fail file
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
non-null result with `ianvs_string_free`. `NativePtyBindings` requires this symbol and the
current ABI when loading the library; missing entrypoints fail loading instead of activating a
predecessor transport. The exact exported surface is maintained in
[`ianvs_core_abi_v1.json`](../../native/core/ianvs_core_abi_v1.json).

The current contract uses SessionConfig v1 for creation, Session Request/Response v1 for
synchronous commands, Runtime Event Envelope v1 for events, Host Request/Response v1 for OSC 52
text reads, Diagnostic Event v1 for metrics, Frame Packet v1 for frames and Graphic Asset Packet
v1 for decoded RGBA. The predecessor Profile-shaped create, unversioned request/event,
Frame JSON/Protobuf, debug-stat and graphic metadata/copy ABI paths are removed. Frame JSON
codecs still serve fixtures and internal models; they are not a native transport capability.

`ssh-session.v1`, `ssh-sftp-directory-listing.v1` and `ssh-sftp-file-operations.v1` describe
native SSH sessions and their request-driven file operations. Host configuration, credentials and
per-operation policy still determine whether a particular session can use them.

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
