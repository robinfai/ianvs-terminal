use ianvs_core::runtime_contract::{
    RUNTIME_CAPABILITIES_SCHEMA_VERSION, RUNTIME_CONTRACT, RuntimeCapabilities,
};
use ianvs_core::{ianvs_runtime_capabilities_json, ianvs_string_free};
use std::ffi::CStr;

#[test]
fn runtime_capabilities_v1_is_deterministic_and_matches_the_ffi_export() {
    let expected = RuntimeCapabilities::current();

    assert_eq!(expected.schema_version, RUNTIME_CAPABILITIES_SCHEMA_VERSION);
    assert_eq!(expected.runtime_contract, RUNTIME_CONTRACT);
    assert_eq!(expected.frame_schema_versions, ["terminal-frame-diff-v1"]);
    assert_eq!(expected.recording_schema_versions, [1]);
    assert!(!expected.features.is_empty());
    assert!(expected.features.windows(2).all(|pair| pair[0] < pair[1]));
    assert!(
        expected
            .features
            .contains(&"diagnostic-event.json.v1".to_owned())
    );
    assert!(
        expected
            .features
            .contains(&"frame-packet.protobuf.v1".to_owned())
    );
    assert!(
        expected
            .features
            .contains(&"graphic-asset-packet.protobuf.v1".to_owned())
    );
    assert!(
        expected
            .features
            .contains(&"replay-checkpoint.v1".to_owned())
    );

    let pointer = ianvs_runtime_capabilities_json();
    assert!(!pointer.is_null());
    let raw = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .expect("capability JSON must be UTF-8")
        .to_owned();
    unsafe { ianvs_string_free(pointer) };

    let decoded: RuntimeCapabilities =
        serde_json::from_str(&raw).expect("capability JSON must match its public schema");
    assert_eq!(decoded, expected);
    assert_eq!(raw, serde_json::to_string(&expected).unwrap());
}
