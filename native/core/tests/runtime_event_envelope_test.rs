use ianvs_core::runtime_contract::{
    RUNTIME_ENVELOPE_SCHEMA_VERSION, RUNTIME_EVENT_BATCH_CONTRACT, RuntimeEventBatchV1,
    RuntimeMessageClass,
};
use ianvs_core::session;
use std::ffi::CStr;

#[test]
fn runtime_event_envelope_v1_crosses_ffi_and_empty_poll_returns_null() {
    let profile = serde_json::json!({
        "id": "event-envelope",
        "name": "Event Envelope",
        "launch": {"program": "/definitely/not/a/child"}
    });
    let session_id = session::create_replay_session(&profile.to_string()).unwrap();

    let pointer = ianvs_core::ffi::ianvs_session_poll_event_envelopes_json(session_id);
    assert!(!pointer.is_null());
    let raw = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("event batch must be UTF-8")
        .to_owned();
    unsafe { ianvs_core::ffi::ianvs_string_free(pointer) };

    let batch: RuntimeEventBatchV1 =
        serde_json::from_str(&raw).expect("event batch must match v1 schema");
    assert_eq!(batch.schema_version, RUNTIME_ENVELOPE_SCHEMA_VERSION);
    assert_eq!(batch.contract, RUNTIME_EVENT_BATCH_CONTRACT);
    assert_eq!(batch.message_class, RuntimeMessageClass::Event);
    assert_eq!(batch.session_id, session_id.to_string());
    assert_eq!(batch.next_sequence, 1);
    assert_eq!(batch.dropped_count, 0);
    assert_eq!(batch.messages.len(), 1);
    assert_eq!(batch.messages[0].message_name, "started");
    assert_eq!(batch.messages[0].sequence, Some(0));
    assert!(batch.messages[0].timestamp_micros > 0);

    let empty = ianvs_core::ffi::ianvs_session_poll_event_envelopes_json(session_id);
    assert!(empty.is_null());
    session::close_session(session_id).unwrap();
}
