# Diagnostic Event V1

Diagnostic Event v1 is the correlated runtime contract for native diagnostic snapshots. It is a
specialization of Runtime Envelope v1 rather than a second top-level envelope:

```json
{
  "schema_version": 1,
  "contract": "ianvs-runtime-envelope-v1",
  "message_class": "diagnostic",
  "message_name": "frame_stats",
  "session_id": "7",
  "sequence": 3,
  "timestamp_micros": 1784610000000000,
  "payload": {
    "rows_scanned": 40,
    "rows_emitted": 8,
    "frame_build_micros": 321
  }
}
```

The contract defines two names:

- `frame_stats` returns and consumes the latest Frame diagnostic snapshot;
- `session_stats` returns a current Session diagnostic snapshot without consuming accumulated
  counters.

Every materialized v1 diagnostic carries the native numeric session id as a decimal string, a
per-session monotonically increasing diagnostic sequence and a Unix timestamp in microseconds.
The sequence advances only when a diagnostic payload exists. Unsupported names and an absent
Frame snapshot return null and do not consume a sequence.

The required FFI symbol is:

```text
ianvs_session_take_diagnostic_event_v1_json(session_id, diagnostic_name)
```

The returned UTF-8 string is native-owned and is released with `ianvs_string_free`. Dart bounds
the encoded event at 1 MiB, requires a diagnostic Runtime Envelope with session/sequence and an
object payload, validates requested session/name correlation, and ignores additive unknown
fields. A wrong schema, contract, message class, correlation or payload type is rejected before
the product consumes native metrics.

`NativePtyBackend` uses this required v1 symbol and typed `PtyDiagnosticEventV1`. Malformed
diagnostics are observational failures and cannot interrupt Frame refresh. Runtime Capabilities
advertises `diagnostic-event.json.v1`; the predecessor debug-stat symbols and
`diagnostics.json.v1` feature are removed. There is no diagnostic downgrade path.

This contract does not change `terminal-diagnostics-session-v1`, the privacy-preserving evidence
package returned by `terminal.export_diagnostics`. It also does not turn the internal sanitized
diagnostic history into a streaming API, version Frame payloads again, or migrate asset transfer.
