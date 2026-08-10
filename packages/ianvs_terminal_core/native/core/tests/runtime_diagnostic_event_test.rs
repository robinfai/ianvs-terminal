use ianvs_core::runtime_contract::{
    RUNTIME_ENVELOPE_CONTRACT, RUNTIME_ENVELOPE_SCHEMA_VERSION, RuntimeEnvelopeV1,
    RuntimeMessageClass,
};
use ianvs_core::session;
use std::ffi::{CStr, CString};

fn take_diagnostic(session_id: u64, name: &str) -> Option<RuntimeEnvelopeV1> {
    let name = CString::new(name).unwrap();
    let pointer = unsafe {
        ianvs_core::ffi::ianvs_session_take_diagnostic_event_v1_json(session_id, name.as_ptr())
    };
    if pointer.is_null() {
        return None;
    }
    let raw = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("diagnostic event must be UTF-8")
        .to_owned();
    unsafe { ianvs_core::ffi::ianvs_string_free(pointer) };
    Some(serde_json::from_str(&raw).expect("diagnostic event must match Runtime Envelope v1"))
}

#[test]
fn diagnostic_event_v1_crosses_ffi_with_identity_sequence_and_timestamp() {
    let profile = serde_json::json!({
        "id": "diagnostic-event",
        "name": "Diagnostic Event",
        "launch": {"program": "/definitely/not/a/child"}
    });
    let session_id = session::create_replay_session(&profile.to_string()).unwrap();

    let session_stats = take_diagnostic(session_id, "session_stats").unwrap();
    assert_eq!(
        session_stats.schema_version,
        RUNTIME_ENVELOPE_SCHEMA_VERSION
    );
    assert_eq!(session_stats.contract, RUNTIME_ENVELOPE_CONTRACT);
    assert_eq!(session_stats.message_class, RuntimeMessageClass::Diagnostic);
    assert_eq!(session_stats.message_name, "session_stats");
    let expected_session_id = session_id.to_string();
    assert_eq!(
        session_stats.session_id.as_deref(),
        Some(expected_session_id.as_str())
    );
    assert_eq!(session_stats.sequence, Some(0));
    assert!(session_stats.timestamp_micros > 0);
    assert!(session_stats.payload.unwrap().is_object());

    let next_session_stats = take_diagnostic(session_id, "session_stats").unwrap();
    assert_eq!(next_session_stats.sequence, Some(1));

    assert!(take_diagnostic(session_id, "unknown_stats").is_none());

    let legacy = ianvs_core::ffi::ianvs_session_take_session_debug_stats_json(session_id);
    assert!(
        !legacy.is_null(),
        "legacy diagnostic FFI must remain available"
    );
    unsafe { ianvs_core::ffi::ianvs_string_free(legacy) };
    session::close_session(session_id).unwrap();
}

#[test]
fn frame_diagnostic_v1_preserves_take_semantics() {
    let profile = serde_json::json!({
        "id": "diagnostic-frame",
        "name": "Diagnostic Frame",
        "launch": {"program": "/definitely/not/a/child"}
    });
    let session_id = session::create_replay_session(&profile.to_string()).unwrap();

    let frame = ianvs_core::ffi::ianvs_session_take_frame_diff_json(session_id);
    assert!(!frame.is_null());
    unsafe { ianvs_core::ffi::ianvs_string_free(frame) };

    let diagnostic = take_diagnostic(session_id, "frame_stats").unwrap();
    assert_eq!(diagnostic.message_name, "frame_stats");
    assert!(diagnostic.payload.unwrap()["frame_build_micros"].is_number());
    assert!(take_diagnostic(session_id, "frame_stats").is_none());

    session::close_session(session_id).unwrap();
}
