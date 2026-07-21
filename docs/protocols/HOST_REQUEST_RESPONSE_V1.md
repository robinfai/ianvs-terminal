# Host Request/Response V1

Host Request/Response v1 is the correlated native-to-product contract for child-process requests
that need host policy or data before the terminal can reply. It is distinct from synchronous
Dart-to-native Session Request/Response v1 and from one-way Runtime Events.

T-322 introduces the contract through one bounded operation: OSC 52 text clipboard reads. The
v1 Runtime Event path emits `message_name: "host_request"`; its payload is a complete Host
Request v1 object:

```json
{
  "schema_version": 1,
  "contract": "ianvs-runtime-envelope-v1",
  "message_class": "event",
  "message_name": "host_request",
  "session_id": "7",
  "sequence": 3,
  "timestamp_micros": 1784610000000000,
  "payload": {
    "schema_version": 1,
    "contract": "ianvs-host-request-v1",
    "request_id": "host:7:3",
    "session_id": "7",
    "operation": "clipboard.read_text",
    "sequence": 3,
    "timestamp_micros": 1784610000000000,
    "payload": {"selection": "c"}
  }
}
```

Dart validates the inner session, sequence and timestamp against the outer Runtime Event before
exposing the request. `request_id` is derived from the native session and event sequence. Unknown
additive fields are ignored, but a wrong schema, contract, identity or response state is rejected.

An authorized response contains canonical Base64 UTF-8 clipboard data:

```json
{
  "schema_version": 1,
  "contract": "ianvs-host-response-v1",
  "request_id": "host:7:3",
  "session_id": "7",
  "operation": "clipboard.read_text",
  "ok": true,
  "timestamp_micros": 1784610000000100,
  "payload": {"data_base64": "aGVsbG8="}
}
```

A denial or host failure contains no payload and uses a bounded structured error:

```json
{
  "schema_version": 1,
  "contract": "ianvs-host-response-v1",
  "request_id": "host:7:3",
  "session_id": "7",
  "operation": "clipboard.read_text",
  "ok": false,
  "timestamp_micros": 1784610000000101,
  "error": {
    "code": "permission_denied",
    "message": "clipboard access was denied"
  }
}
```

The optional `ianvs_session_host_response_v1_json` symbol consumes a matching response. Native
keeps at most 64 pending requests, validates a response before removal and consumes accepted
success, denial or error exactly once. Duplicate, stale, cross-session or wrong-operation
responses fail. A successful clipboard response decodes to at most 4 MiB of UTF-8 and the whole
Host Response document is limited to 6 MiB; Host Request documents are limited to 64 KiB.
Runtime Capabilities advertises this paired event/response surface as
`host-request-response.json.v1`.

Compatibility remains dual-stack:

- new Dart/new native uses Runtime Event `host_request` plus Host Response v1;
- new Dart/old native receives `clipboard_paste_request` and writes the existing OSC 52 reply;
- old Dart/new native polls `ianvs_session_poll_events_json`, receives the unchanged legacy event
  and uses its existing direct reply;
- ordinary Runtime Events retain their existing message names and payloads.

This first slice deliberately does not classify URL opening, attention feedback, notification
display, shell metadata, file downloads or other one-way host actions as response-bearing
requests. OSC 5522 MIME clipboard, OSC 1337 ReportVariable and notification activation also
remain on their existing separately governed paths until their own compatibility tasks.
