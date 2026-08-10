use ianvs_core::session;
use ianvs_core::session_config::{
    SESSION_CONFIG_CONTRACT, SESSION_CONFIG_SCHEMA_VERSION, SessionConfigV1,
};
use std::ffi::CString;

#[test]
fn session_config_v1_crosses_live_and_replay_ffi_with_legacy_compatibility() {
    let config = serde_json::json!({
        "schema_version": SESSION_CONFIG_SCHEMA_VERSION,
        "contract": SESSION_CONFIG_CONTRACT,
        "session_id": "runtime-v1-test",
        "display_name": "V1 Test",
        "config": {
            "launch": {
                "program": "/bin/sh",
                "args": ["-c", "sleep 60"],
                "env": {"LANG": "C.UTF-8"},
                "cwd": null
            },
            "terminal": {
                "emulation": "vt220",
                "scrollbackLines": 1234,
                "graphics": {
                    "enabled": false,
                    "advertise": "none",
                    "maxImageBytes": 1024,
                    "maxTotalBytes": 2048
                },
                "dragDropEnabled": false
            },
            "shellIntegration": {"enabled": false},
            "appearance": {
                "font": {
                    "family": "Menlo",
                    "fallback": ["Monaco"],
                    "size": 13.0,
                    "lineHeight": 1.4
                },
                "colors": {},
                "cursor": {"shape": "beam", "blink": false}
            },
            "interaction": {
                "copyOnSelect": true,
                "optionDragMode": "normal_selection"
            },
            "future_config_field": true
        },
        "future_top_level": {"value": 1}
    });
    let decoded = SessionConfigV1::decode_json(&config.to_string()).unwrap();
    assert_eq!(decoded.session_id, "runtime-v1-test");
    assert_eq!(decoded.config.launch.program, "/bin/sh");

    let raw = CString::new(config.to_string()).unwrap();
    let live_id = unsafe { ianvs_core::ffi::ianvs_session_create_v1(raw.as_ptr()) };
    assert_ne!(live_id, 0);
    session::close_session(live_id).unwrap();

    let replay_id = unsafe { ianvs_core::ffi::ianvs_replay_session_create_v1(raw.as_ptr()) };
    assert_ne!(replay_id, 0);
    session::close_session(replay_id).unwrap();

    let invalid = CString::new(
        serde_json::json!({
            "schema_version": 2,
            "contract": SESSION_CONFIG_CONTRACT,
            "session_id": "bad",
            "display_name": "Bad",
            "config": {"launch": {"program": "/bin/sh"}}
        })
        .to_string(),
    )
    .unwrap();
    assert_eq!(
        unsafe { ianvs_core::ffi::ianvs_replay_session_create_v1(invalid.as_ptr()) },
        0
    );

    let legacy = serde_json::json!({
        "id": "legacy-profile-wire",
        "name": "Legacy Profile Wire",
        "launch": {"program": "/definitely/not/a/child"}
    });
    let legacy_id = session::create_replay_session(&legacy.to_string()).unwrap();
    session::close_session(legacy_id).unwrap();
}
