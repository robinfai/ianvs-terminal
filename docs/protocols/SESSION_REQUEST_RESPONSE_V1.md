# Session Request/Response V1

Session Request/Response v1 is the synchronous Dart-to-native command contract used by the
generic session request channel. It is not the native-to-product Host Request/Event direction.

Request example:

```json
{
  "schema_version": 1,
  "contract": "ianvs-session-request-v1",
  "request_id": "dart-1",
  "session_id": "7",
  "operation": "terminal.search_text",
  "payload": {
    "query": "error",
    "mode": "smart_case_substring"
  }
}
```

Successful response example:

```json
{
  "schema_version": 1,
  "contract": "ianvs-session-response-v1",
  "request_id": "dart-1",
  "session_id": "7",
  "operation": "terminal.search_text",
  "ok": true,
  "timestamp_micros": 1784610000000000,
  "payload": {"matches": [], "error_text": null}
}
```

Protocol failure example:

```json
{
  "schema_version": 1,
  "contract": "ianvs-session-response-v1",
  "request_id": "dart-2",
  "session_id": "7",
  "operation": "terminal.future_operation",
  "ok": false,
  "timestamp_micros": 1784610000000001,
  "error": {
    "code": "unsupported_operation",
    "message": "the requested operation is not supported"
  }
}
```

The UTF-8 request document is limited to 1 MiB. The response ceiling is 16 MiB because the
existing bounded Recording stop operation returns current recording schema NDJSON through this channel.
Identifiers and operation names are individually bounded. Consumers ignore additive unknown v1
object fields, but reject a wrong schema/contract, malformed required fields, oversized input and
request/response correlation mismatch.

The required `ianvs_session_request_v1_json` symbol consumes Request v1 and always attempts to
return Response v1, including structured protocol/runtime errors. Runtime Capabilities advertises
`session-request-envelope.json.v1`. The predecessor `ianvs_session_request_json` symbol and
`session-request.json.v1` feature are removed; there is no unversioned request fallback.

Operation-specific clients supply an operation name and its payload separately. Native dispatches
the validated operation and payload directly; no `{kind, ...payload}` compatibility object crosses
this contract. No application Profile fields or undeclared native internals cross it either.
