# Runtime Event Envelope V1

Runtime Event Envelope v1 is the first migrated message class under the Runtime Contract. One
poll returns a batch object:

```json
{
  "schema_version": 1,
  "contract": "ianvs-runtime-event-batch-v1",
  "message_class": "event",
  "session_id": "7",
  "next_sequence": 2,
  "dropped_count": 0,
  "messages": [
    {
      "schema_version": 1,
      "contract": "ianvs-runtime-envelope-v1",
      "message_class": "event",
      "message_name": "started",
      "session_id": "7",
      "sequence": 0,
      "timestamp_micros": 1784600000000000,
      "payload": null
    }
  ]
}
```

`sequence` is assigned per session before queue admission. Eviction therefore leaves an observable
gap. `next_sequence` is the exclusive sequence cursor after all attempted events in the batch, and
`dropped_count` counts bounded-queue losses since the previous poll. A batch may have no retained
messages when an oversized event was rejected, but still reports the advanced cursor and drop.

The Dart decoder accepts additive unknown object fields and unknown `message_name` values. It
requires the known v1 contracts and `event` class, bounded positive session identity, safe integer
sequence/timestamp fields, at most 1,024 messages, one session per batch and strictly increasing
message order. Contract failures use stable structured error codes.

The new poll symbol is optional. `NativePtyBackend` uses it when present and otherwise calls the
legacy event-array symbol. Presence is advertised by `event-envelope.json.v1` in Runtime
Capabilities v1. The legacy symbol is not removed in T-319.
