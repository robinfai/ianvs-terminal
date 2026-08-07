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

A valid batch with `dropped_count > 0` or an observable sequence gap preserves
the historical `NativePtyBackend` default: `pollEvents` throws
`PtyRuntimeContractException(code: event_sequence_gap)`. A consumer that can
reconcile survivors must opt in with
`emitRuntimeEventGapDiagnostics: true`; only then does the backend insert a
synthetic typed `PtyRuntimeEventGapDiagnostic` before the surviving events.
The example product opts in because its controller handles that diagnostic
before a survivor can start or advance a transfer. Structurally malformed,
cross-session or reordered envelopes remain contract errors in both modes.

`TerminalRuntimeController` routes the synthetic diagnostic onto its public
typed `runtimeEventGaps` stream as a
`TerminalSessionRuntimeEventGapDiagnostic`. Before processing survivors it
sends `terminal.zmodem.cancel_active` when the backend advertises either
ZMODEM capability or Dart already holds a known ZMODEM transfer. The command
does not depend on Dart's possibly stale transfer id. A backend with no ZMODEM
capability only receives the normal frame refresh and gap diagnostic; a
generic event gap cannot create an unknown ZMODEM input lock. If native
reconciliation returns `cancelled` or `draining`, Dart retains the input lock
under synthetic authority; non-terminal ZMODEM survivors from that batch are
suppressed because native may just have cancelled them. An `idle` result is
also authoritative when the already-polled batch has no matching terminal
survivor: Dart clears a stale known lock, or avoids creating an unknown lock
when there was no known transfer. `draining` retains a synthetic unknown input
lock. A matching terminal completion/failure in the lossy batch
is still delivered, but it only releases the remembered transfer when the
post-poll reconciliation reports `idle`. A `cancelled`, `draining`, missing,
or malformed response proves no such idle boundary: native may have advanced
to authority whose detection was inside the gap, so Dart replaces the
remembered id with the synthetic unknown lock. A later terminal event from a
gap-free batch, or a later reconciliation that reports `idle`, releases it. A failed
reconciliation with no previously remembered transfer preserves the first
valid non-terminal ZMODEM survivor (and only that survivor's transfer
identity), so a first-batch gap still establishes the input lock and transfer
UI instead of silently exposing protocol bytes to ordinary input. A
`publish_failed` survivor carrying a valid owner-bound recovery token is also
always delivered, even when the earlier transfer UI events were among the
dropped messages. If native reconciliation fails without either survivor,
Dart creates a local-only `zmodem_reconciliation_required` identity, retains
its input lock, and publishes a visible generic transfer banner rather than
claiming that opaque protocol routing is safe. A later native event replaces
that unknown identity, and the product Cancel action retries the synthetic
id-bound operation and then the id-free reconciliation. A successful id-free
response also distinguishes `cancelled`, `draining`, and `idle`, so a
completion present in the same batch remains visible instead of being
relabelled as a cancellation while the independent unknown authority stays
locked. The typed diagnostic
reports whether state was cleared, whether reconciliation was accepted, and
whether a frame refresh was requested. A batch containing a surviving session
exit still publishes the gap but requests no refresh because the exit will
release the session state.

If the id-bound cancel already succeeded and native is in its bounded Draining
state, `cancel_active` is idempotent: it does not tear down the PTY, and any
ordinary input deferred behind the transfer flushes at the drain boundary.
Every direct transport-termination path that cannot deliver such queued input
first emits `zmodem_deferred_write_failed`; reconciliation cannot silently
discard user input.

The new poll symbol is optional. `NativePtyBackend` uses it when present and otherwise calls the
legacy event-array symbol. Presence is advertised by `event-envelope.json.v1` in Runtime
Capabilities v1. The legacy symbol is not removed in T-319.
