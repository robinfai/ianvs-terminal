use serde_json::Value;
use std::collections::BTreeSet;
use std::path::PathBuf;

const CURRENT_ABI: &[&str] = &[
    "ianvs_bytes_free",
    "ianvs_ping",
    "ianvs_replay_session_checkpoint_capture",
    "ianvs_replay_session_checkpoint_restore",
    "ianvs_replay_session_create_v1",
    "ianvs_replay_session_exit",
    "ianvs_replay_session_output",
    "ianvs_runtime_capabilities_json",
    "ianvs_session_close",
    "ianvs_session_create_v1",
    "ianvs_session_file_download_discard",
    "ianvs_session_file_download_take",
    "ianvs_session_graphic_asset_packet_v1_protobuf",
    "ianvs_session_host_response_v1_json",
    "ianvs_session_poll_event_envelopes_json",
    "ianvs_session_refresh_hint",
    "ianvs_session_request_v1_json",
    "ianvs_session_resize_with_cell_size",
    "ianvs_session_scroll",
    "ianvs_session_scroll_to",
    "ianvs_session_take_diagnostic_event_v1_json",
    "ianvs_session_take_frame_packet_v1_protobuf",
    "ianvs_session_write",
    "ianvs_session_write_protocol_reply",
    "ianvs_ssh_import_profiles_json",
    "ianvs_string_free",
];

const PREDECESSOR_ABI: &[&str] = &[
    "ianvs_replay_session_create",
    "ianvs_session_create",
    "ianvs_session_graphic_asset_meta",
    "ianvs_session_graphic_asset_rgba_copy",
    "ianvs_session_poll_events_json",
    "ianvs_session_request_json",
    "ianvs_session_resize",
    "ianvs_session_search_json",
    "ianvs_session_selection_text",
    "ianvs_session_take_frame_debug_stats_json",
    "ianvs_session_take_frame_diff_json",
    "ianvs_session_take_frame_diff_protobuf",
    "ianvs_session_take_session_debug_stats_json",
];

#[test]
fn checked_in_abi_manifest_is_exactly_current_only() {
    let manifest_path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("ianvs_core_abi_v1.json");
    let manifest: Value = serde_json::from_slice(
        &std::fs::read(&manifest_path)
            .unwrap_or_else(|error| panic!("read {}: {error}", manifest_path.display())),
    )
    .expect("parse ABI manifest");
    let functions = manifest["functions"]
        .as_object()
        .expect("ABI functions object");
    let actual = functions
        .keys()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();
    let expected = CURRENT_ABI.iter().copied().collect::<BTreeSet<_>>();

    assert_eq!(actual, expected);
    for symbol in PREDECESSOR_ABI {
        assert!(
            !functions.contains_key(*symbol),
            "predecessor export {symbol}"
        );
    }
    assert!(manifest.get("dart_unbound_legacy_exports").is_none());
    assert!(manifest.get("structs").is_none());
    assert!(manifest.get("host_layout").is_none());
}
