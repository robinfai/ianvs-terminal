#[path = "fixtures/recording/create.rs"]
mod fixture;
use ianvs_core::recording::file_service::request_json;
use serde_json::{Value, json};
use std::ffi::{CStr, CString};

fn request(op: &str, id: Option<&str>, payload: Value) -> Value {
    // Exercise the exported entrypoint and its allocator pairing as well.
    let input = CString::new(
        json!({"schema_version":2,"job_id":id,"operation":op,"payload":payload}).to_string(),
    )
    .unwrap();
    let output = unsafe { ianvs_core::ffi::ianvs_recording_file_request_v2_json(input.as_ptr()) };
    assert!(!output.is_null());
    let response = unsafe { CStr::from_ptr(output) }
        .to_str()
        .unwrap()
        .to_owned();
    unsafe { ianvs_core::ffi::ianvs_string_free(output) };
    let value: Value = serde_json::from_str(&response).unwrap();
    assert_eq!(value["operation"], op);
    value
}
fn run(op: &str, payload: Value) -> Value {
    let ticket = request("reserve", None, json!({}));
    assert_eq!(ticket["ok"], true, "{ticket}");
    let id = ticket["job_id"].as_str().unwrap();
    let result = request(op, Some(id), payload);
    assert_eq!(request("release", Some(id), json!({}))["ok"], true);
    result
}

#[test]
fn ffi_reads_structured_frames_images_and_bounded_command_pages_without_sessions() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("fixture.trailrec");
    fixture::create(&path, 11);
    let original = std::fs::read(path.join("records.bin")).unwrap();
    let info = run("inspect", json!({"bundle_path":path}));
    assert_eq!(info["ok"], true, "{info}");
    assert_eq!(info["result"]["summary"]["visual_count"], 11);
    assert_eq!(info["result"]["completion"], "finished");
    let id = info["result"]["metadata"]["recording_id"].as_str().unwrap();
    let screen = run(
        "seek",
        json!({"bundle_path":path,"recording_id":id,"offset_micros":6_500_000}),
    );
    assert_eq!(screen["ok"], true, "{screen}");
    assert_eq!(screen["result"]["screen"]["offset_micros"], 6_000_000);
    let binding = &screen["result"]["screen"]["assets"][0];
    let image = run(
        "asset",
        json!({"bundle_path":path,"recording_id":id,"binding":binding}),
    );
    assert_eq!(image["ok"], true, "{image}");
    assert_eq!(image["result"]["rgba_base64"], "/wAA/wD/AP8=");
    let mut cursor = json!(0);
    let mut events = Vec::new();
    loop {
        let page = run(
            "timeline",
            json!({"bundle_path":path,"recording_id":id,"cursor":cursor,"limit":3}),
        );
        assert_eq!(page["ok"], true, "{page}");
        let chunk = page["result"]["events"].as_array().unwrap();
        assert!(chunk.len() <= 3);
        events.extend(chunk.iter().cloned());
        cursor = page["result"]["next_cursor"].clone();
        if cursor.is_null() {
            break;
        }
    }
    assert_eq!(events.len(), 22);
    assert_eq!(
        events.last().unwrap()["command"],
        "printf '%s' 'quoted 雪-10'"
    );
    assert_eq!(std::fs::read(path.join("records.bin")).unwrap(), original);
}

#[test]
fn cancelled_reserved_work_does_not_open_or_create_any_files_and_releases_capacity() {
    for _ in 0..20 {
        let ticket = request("reserve", None, json!({}));
        let id = ticket["job_id"].as_str().unwrap();
        assert_eq!(request("cancel", Some(id), json!({}))["ok"], true);
        let result = request(
            "inspect",
            Some(id),
            json!({"bundle_path":"/definitely/not/opened.trailrec"}),
        );
        assert_eq!(result["ok"], false);
        assert!(result["error"].as_str().unwrap().contains("cancelled"));
        assert_eq!(request("release", Some(id), json!({}))["ok"], true);
        assert_eq!(request("cancel", Some(id), json!({}))["ok"], false);
    }
}

#[test]
fn wrong_identity_stale_timeline_corruption_and_legacy_are_rejected() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("fixture.trailrec");
    fixture::create(&path, 2);
    let info = run("inspect", json!({"bundle_path":path}));
    let id = info["result"]["metadata"]["recording_id"].as_str().unwrap();
    assert_eq!(
        run(
            "seek",
            json!({"bundle_path":path,"recording_id":"wrong","offset_micros":0})
        )["ok"],
        false
    );
    let index_path = path.join("commands.index");
    let mut bytes = std::fs::read(&index_path).unwrap();
    bytes[116] ^= 1;
    std::fs::write(&index_path, bytes).unwrap();
    assert_eq!(
        run(
            "timeline",
            json!({"bundle_path":path,"recording_id":id,"cursor":0,"limit":10})
        )["ok"],
        false
    );
    let legacy = root.path().join("old.ndjson");
    std::fs::write(&legacy, b"preserve").unwrap();
    assert_eq!(run("inspect", json!({"bundle_path":legacy}))["ok"], false);
    assert_eq!(std::fs::read(&legacy).unwrap(), b"preserve");
    assert!(serde_json::from_str::<Value>(&request_json("{}")).unwrap()["ok"] == false);
}
