use ianvs_core::session;
use ianvs_core::session_request::{
    SESSION_REQUEST_CONTRACT, SESSION_REQUEST_SCHEMA_VERSION, SESSION_RESPONSE_CONTRACT,
    SessionResponseV1,
};
use std::ffi::{CStr, CString};

fn call_v1(session_id: u64, request: serde_json::Value) -> SessionResponseV1 {
    let raw = CString::new(request.to_string()).unwrap();
    let pointer =
        unsafe { ianvs_core::ffi::ianvs_session_request_v1_json(session_id, raw.as_ptr()) };
    assert!(!pointer.is_null());
    let response = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { ianvs_core::ffi::ianvs_string_free(pointer) };
    serde_json::from_str(&response).unwrap()
}

#[test]
fn session_request_response_v1_crosses_ffi_with_structured_errors_and_legacy_compatibility() {
    let legacy_profile = serde_json::json!({
        "id": "request-v1-replay",
        "name": "Request V1 Replay",
        "launch": {"program": "/definitely/not/a/child"}
    });
    let session_id = session::create_replay_session(&legacy_profile.to_string()).unwrap();
    session::replay_session_output(session_id, b"alpha error omega\r\n").unwrap();

    let request = serde_json::json!({
        "schema_version": SESSION_REQUEST_SCHEMA_VERSION,
        "contract": SESSION_REQUEST_CONTRACT,
        "request_id": "rust-1",
        "session_id": session_id.to_string(),
        "operation": "terminal.search_text",
        "payload": {
            "query": "error",
            "mode": "case_sensitive_substring",
            "future": true
        },
        "future": true
    });
    let response = call_v1(session_id, request);
    assert_eq!(response.schema_version, SESSION_REQUEST_SCHEMA_VERSION);
    assert_eq!(response.contract, SESSION_RESPONSE_CONTRACT);
    assert_eq!(response.request_id, "rust-1");
    assert_eq!(response.session_id, session_id.to_string());
    assert_eq!(response.operation, "terminal.search_text");
    assert!(response.ok);
    assert_eq!(
        response.payload.as_ref().unwrap()["matches"][0]["text"],
        "error"
    );

    let unsupported = call_v1(
        session_id,
        serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_REQUEST_CONTRACT,
            "request_id": "rust-2",
            "session_id": session_id.to_string(),
            "operation": "terminal.future_operation",
            "payload": {}
        }),
    );
    assert!(!unsupported.ok);
    assert_eq!(
        unsupported.error.as_ref().unwrap().code,
        "unsupported_operation"
    );

    let invalid = call_v1(
        session_id,
        serde_json::json!({
            "schema_version": 2,
            "contract": SESSION_REQUEST_CONTRACT,
            "request_id": "rust-3",
            "session_id": session_id.to_string(),
            "operation": "terminal.search_text",
            "payload": {}
        }),
    );
    assert!(!invalid.ok);
    assert_eq!(invalid.error.as_ref().unwrap().code, "unsupported_schema");

    let invalid_contract = call_v1(
        session_id,
        serde_json::json!({
            "schema_version": 1,
            "contract": "ianvs-session-request-v2",
            "request_id": "rust-4",
            "session_id": session_id.to_string(),
            "operation": "terminal.search_text",
            "payload": {}
        }),
    );
    assert!(!invalid_contract.ok);
    assert_eq!(
        invalid_contract.error.as_ref().unwrap().code,
        "unsupported_contract"
    );

    let identity_mismatch = call_v1(
        session_id,
        serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_REQUEST_CONTRACT,
            "request_id": "rust-5",
            "session_id": (session_id + 1).to_string(),
            "operation": "terminal.search_text",
            "payload": {}
        }),
    );
    assert!(!identity_mismatch.ok);
    assert_eq!(identity_mismatch.session_id, session_id.to_string());
    assert_eq!(
        identity_mismatch.error.as_ref().unwrap().code,
        "invalid_session_id"
    );

    let missing_session_id = session_id + 1_000_000;
    let runtime_failure = call_v1(
        missing_session_id,
        serde_json::json!({
            "schema_version": 1,
            "contract": SESSION_REQUEST_CONTRACT,
            "request_id": "rust-6",
            "session_id": missing_session_id.to_string(),
            "operation": "terminal.search_text",
            "payload": {"query": "error", "mode": "case_sensitive_substring"}
        }),
    );
    assert!(!runtime_failure.ok);
    assert_eq!(
        runtime_failure.error.as_ref().unwrap().code,
        "runtime_error"
    );

    let legacy = session::request_session_json(
        session_id,
        &serde_json::json!({
            "kind": "terminal.search_text",
            "query": "alpha",
            "mode": "case_sensitive_substring"
        })
        .to_string(),
    )
    .unwrap()
    .unwrap();
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&legacy).unwrap()["matches"][0]["text"],
        "alpha"
    );

    session::close_session(session_id).unwrap();
}
