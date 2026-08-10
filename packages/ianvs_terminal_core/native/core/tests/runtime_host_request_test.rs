use ianvs_core::host_request::{
    HOST_REQUEST_CONTRACT, HOST_REQUEST_SCHEMA_VERSION, HOST_RESPONSE_CONTRACT, HostResponseError,
    HostResponseV1, host_request_v1_from_event,
};

#[test]
fn osc52_clipboard_read_maps_to_a_correlated_host_request_v1() {
    let request = host_request_v1_from_event(
        7,
        3,
        1_200,
        "clipboard_paste_request",
        Some(serde_json::json!({"selection": "c"})),
    )
    .expect("OSC 52 reads must become Host Request v1 on the envelope path");

    assert_eq!(request.schema_version, HOST_REQUEST_SCHEMA_VERSION);
    assert_eq!(request.contract, HOST_REQUEST_CONTRACT);
    assert_eq!(request.request_id, "host:7:3");
    assert_eq!(request.session_id, "7");
    assert_eq!(request.operation, "clipboard.read_text");
    assert_eq!(request.sequence, 3);
    assert_eq!(request.timestamp_micros, 1_200);
    assert_eq!(request.payload, serde_json::json!({"selection": "c"}));

    assert!(
        host_request_v1_from_event(7, 4, 1_201, "bell", None).is_none(),
        "ordinary events must keep their existing Runtime Event shape"
    );
}

#[test]
fn host_response_v1_validates_schema_identity_and_response_state() {
    let raw = serde_json::json!({
        "schema_version": 1,
        "contract": HOST_RESPONSE_CONTRACT,
        "request_id": "host:7:3",
        "session_id": "7",
        "operation": "clipboard.read_text",
        "ok": true,
        "timestamp_micros": 1_300,
        "payload": {"data_base64": "aGVsbG8="},
        "future": true
    })
    .to_string();
    let response = HostResponseV1::decode_json(&raw, 7).expect("valid Host Response v1");
    assert!(response.ok);

    let wrong_contract = raw.replace(HOST_RESPONSE_CONTRACT, "future-host-response");
    assert_eq!(
        HostResponseV1::decode_json(&wrong_contract, 7).unwrap_err(),
        HostResponseError::UnsupportedContract
    );

    let invalid_state = serde_json::json!({
        "schema_version": 1,
        "contract": HOST_RESPONSE_CONTRACT,
        "request_id": "host:7:3",
        "session_id": "7",
        "operation": "clipboard.read_text",
        "ok": false,
        "timestamp_micros": 1_300,
        "payload": {},
        "error": {"code": "permission_denied", "message": "denied"}
    })
    .to_string();
    assert_eq!(
        HostResponseV1::decode_json(&invalid_state, 7).unwrap_err(),
        HostResponseError::InvalidResponseState
    );
}
