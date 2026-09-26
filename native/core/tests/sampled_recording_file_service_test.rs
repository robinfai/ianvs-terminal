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
    let summary_cache = std::fs::read(path.join("summary.index")).unwrap();
    // The writer publishes usable caches before the first inspect/rebuild.
    assert_eq!(
        run(
            "seek",
            json!({"bundle_path":path,"recording_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","offset_micros":6_500_000})
        )["ok"],
        true
    );
    let info = run("inspect", json!({"bundle_path":path}));
    assert_eq!(info["ok"], true, "{info}");
    assert_eq!(info["result"]["summary"]["visual_count"], 11);
    assert_eq!(info["result"]["completion"], "finished");
    assert_eq!(
        std::fs::read(path.join("summary.index")).unwrap(),
        summary_cache,
        "first open must reuse writer-published caches"
    );
    assert_eq!(
        run("inspect", json!({"bundle_path":path}))["result"],
        info["result"]
    );
    assert_eq!(
        std::fs::read(path.join("summary.index")).unwrap(),
        summary_cache
    );
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

#[test]
fn damaged_missing_and_oversized_caches_rebuild_without_modifying_primary_data() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("fixture.trailrec");
    fixture::create(&path, 3);
    let original = std::fs::read(path.join("records.bin")).unwrap();
    for name in ["summary.index", "commands.index", "seek.index"] {
        let cache = path.join(name);
        let mut bytes = std::fs::read(&cache).unwrap();
        let last = bytes.len() - 1;
        bytes[last] ^= 1;
        std::fs::write(&cache, bytes).unwrap();
        let info = run("inspect", json!({"bundle_path":path}));
        assert_eq!(info["result"]["completion"], "finished", "{info}");
        assert_eq!(info["result"]["summary"]["record_count"], 9);
        assert_eq!(run("timeline", json!({"bundle_path":path,"recording_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","cursor":0,"limit":128}))["result"]["events"].as_array().unwrap().len(), 6);
        assert_eq!(std::fs::read(path.join("records.bin")).unwrap(), original);
    }
    std::fs::OpenOptions::new()
        .write(true)
        .open(path.join("summary.index"))
        .unwrap()
        .set_len(1024 * 1024 * 1024)
        .unwrap();
    assert_eq!(
        run("inspect", json!({"bundle_path":path}))["result"]["completion"],
        "finished"
    );
    std::fs::remove_file(path.join("commands.index")).unwrap();
    assert_eq!(
        run("inspect", json!({"bundle_path":path}))["result"]["completion"],
        "finished"
    );
    assert_eq!(std::fs::read(path.join("records.bin")).unwrap(), original);
}

#[test]
fn committed_interrupted_prefix_opens_fast_and_later_growth_forces_recovery() {
    use ianvs_core::recording::{ContainerWriter, RecordingMetadata, SemanticEvent, SemanticKind};
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("interrupted.trailrec");
    let metadata = RecordingMetadata {
        recording_id: "interrupted".into(),
        title: "committed prefix".into(),
        started_at_unix_millis: 0,
        hostname: None,
    };
    let mut writer = ContainerWriter::create(&path, &metadata).unwrap();
    let mut event = SemanticEvent {
        offset_micros: 1,
        kind: SemanticKind::CommandStarted,
        context_id: "local".into(),
        command_id: Some("1".into()),
        command: Some("echo one".into()),
        cwd: None,
        hostname: None,
        exit_code: None,
    };
    writer.append_semantic(&event).unwrap();
    writer.commit().unwrap();
    let committed = std::fs::read(path.join("summary.index")).unwrap();
    let info = run("inspect", json!({"bundle_path":path}));
    assert_eq!(info["result"]["completion"], "interrupted");
    assert_eq!(info["result"]["summary"]["record_count"], 1);
    assert_eq!(
        std::fs::read(path.join("summary.index")).unwrap(),
        committed
    );
    event.offset_micros = 2;
    event.command_id = Some("2".into());
    writer.append_semantic(&event).unwrap();
    drop(writer);
    let recovered = run("inspect", json!({"bundle_path":path}));
    assert_eq!(recovered["result"]["completion"], "interrupted");
    assert_eq!(recovered["result"]["summary"]["record_count"], 2);
    assert_ne!(
        std::fs::read(path.join("summary.index")).unwrap(),
        committed
    );
}

#[cfg(unix)]
#[test]
fn same_size_source_corruption_with_restored_mtime_invalidates_local_cache() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("fixture.trailrec");
    fixture::create(&path, 3);
    let file = path.join("records.bin");
    let modified = std::fs::metadata(&file).unwrap().modified().unwrap();
    let mut bytes = std::fs::read(&file).unwrap();
    let first_record = 44 + u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize;
    bytes[first_record + 60] ^= 1;
    std::fs::write(&file, &bytes).unwrap();
    std::fs::OpenOptions::new()
        .write(true)
        .open(&file)
        .unwrap()
        .set_times(std::fs::FileTimes::new().set_modified(modified))
        .unwrap();
    let info = run("inspect", json!({"bundle_path":path}));
    assert_eq!(info["result"]["completion"], "damaged_tail", "{info}");
    assert_eq!(info["result"]["summary"]["visual_count"], 0);
    assert_eq!(std::fs::read(&file).unwrap(), bytes);
}

#[test]
fn optional_summary_publication_failure_does_not_lose_a_finished_recording() {
    use ianvs_core::recording::{
        ContainerReader, ContainerWriter, RecordingCompletion, RecordingMetadata,
    };
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("fixture.trailrec");
    let writer = ContainerWriter::create(
        &path,
        &RecordingMetadata {
            recording_id: "cache-failure".into(),
            title: "".into(),
            started_at_unix_millis: 0,
            hostname: None,
        },
    )
    .unwrap();
    // A destination directory makes atomic summary publication fail.
    std::fs::create_dir(path.join("summary.index")).unwrap();
    writer.finish(42).unwrap();
    let report = ContainerReader::open(&path)
        .unwrap()
        .scan(|| false, |_| Ok(()))
        .unwrap();
    assert_eq!(report.completion, RecordingCompletion::Finished);
    let info = run("inspect", json!({"bundle_path":path}));
    assert_eq!(info["result"]["completion"], "finished", "{info}");
    assert_eq!(info["result"]["summary"]["duration_micros"], 42);
}

#[cfg(unix)]
#[test]
fn library_directory_sync_is_strict_and_never_treats_other_file_types_as_durable() {
    let temporary = tempfile::tempdir().unwrap();
    let directory = temporary.path().join("library");
    std::fs::create_dir(&directory).unwrap();
    let metadata = directory.join("retention.json");
    std::fs::write(&metadata, b"preserve metadata").unwrap();
    let original = std::fs::read(&metadata).unwrap();
    let result = run("sync_directory", json!({"directory_path":directory}));
    assert_eq!(result["ok"], true, "{result}");
    assert_eq!(result["result"], json!({}));
    assert_eq!(std::fs::read(&metadata).unwrap(), original);

    let alias = temporary.path().join("alias");
    std::os::unix::fs::symlink(&directory, &alias).unwrap();
    let missing = temporary.path().join("missing");
    for input in [
        json!({"directory_path":metadata}),
        json!({"directory_path":alias}),
        json!({"directory_path":missing}),
        json!({"directory_path":"relative"}),
        json!({"directory_path":directory,"unknown":true}),
        json!({"directory_path":null}),
        json!({}),
    ] {
        assert_eq!(run("sync_directory", input)["ok"], false);
    }
    assert!(!missing.exists());
    assert_eq!(std::fs::read(&metadata).unwrap(), original);
    let ticket = request("reserve", None, json!({}));
    let id = ticket["job_id"].as_str().unwrap();
    assert_eq!(request("cancel", Some(id), json!({}))["ok"], true);
    let cancelled = request(
        "sync_directory",
        Some(id),
        json!({"directory_path":directory}),
    );
    assert_eq!(cancelled["ok"], false);
    assert!(cancelled["error"].as_str().unwrap().contains("cancelled"));
    assert_eq!(request("release", Some(id), json!({}))["ok"], true);
}
