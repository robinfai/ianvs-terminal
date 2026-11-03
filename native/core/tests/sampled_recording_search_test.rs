#[path = "fixtures/recording/create.rs"]
mod fixture;
use ianvs_core::model::TERMINAL_FRAME_SCHEMA_VERSION;
use ianvs_core::proto::frame_diff as pb;
use ianvs_core::recording::file_service::request_json;
use ianvs_core::recording::{
    AdaptiveSampler, ContainerWriter, RecordingMetadata, SamplingPolicy, SemanticEvent,
    SemanticKind,
};
use serde_json::{Value, json};
use std::fs;
use std::path::Path;

fn request(op: &str, id: Option<&str>, payload: Value) -> Value {
    serde_json::from_str(&request_json(
        &json!({"schema_version":2,"operation":op,"job_id":id,"payload":payload}).to_string(),
    ))
    .unwrap()
}
fn run(payload: Value) -> Value {
    let reserved = request("reserve", None, json!({}));
    let id = reserved["job_id"].as_str().unwrap();
    let result = request("search", Some(id), payload);
    assert_eq!(request("release", Some(id), json!({}))["ok"], true);
    result
}
fn query(path: &Path, text: &str, kind: &str) -> Value {
    json!({"bundle_path":path,"recording_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","query":text,"hostname":null,"kind":kind,"cursor":0,"limit":100})
}
fn all(mut payload: Value) -> Vec<Value> {
    let mut hits = Vec::new();
    loop {
        let page = run(payload.clone());
        assert_eq!(page["ok"], true, "{page}");
        let chunk = page["result"]["hits"].as_array().unwrap();
        assert!(chunk.len() <= payload["limit"].as_u64().unwrap() as usize);
        hits.extend(chunk.iter().cloned());
        let next = &page["result"]["next_cursor"];
        if next.is_null() {
            break;
        }
        assert!(next.as_u64().unwrap() > payload["cursor"].as_u64().unwrap());
        payload["cursor"] = next.clone();
    }
    hits
}

#[test]
fn indexes_retained_screens_and_exact_commands_with_bounded_pages_and_reusable_cache() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("sample.trailrec");
    fixture::create(&path, 11);
    let original = fs::read(path.join("records.bin")).unwrap();
    let mut input = query(&path, "quoted 雪", "command");
    input["limit"] = json!(2);
    let commands = all(input.clone());
    assert_eq!(
        commands.len(),
        11,
        "normal finishes must not duplicate starts"
    );
    assert_eq!(commands[10]["preview"], "printf '%s' 'quoted 雪-10'");
    assert_eq!(commands[10]["kind"], "command");
    assert!(commands[10]["row"].is_null());
    let cache = fs::read(path.join("search.info")).unwrap();
    assert_eq!(all(input), commands);
    assert_eq!(fs::read(path.join("search.info")).unwrap(), cache);
    let frames = all(query(&path, "FRAME", "screen"));
    assert_eq!(frames.len(), 11);
    assert_eq!(frames.last().unwrap()["offset_micros"], 10_000_000);
    assert_eq!(
        all(query(&path, "copiable structured screen", "screen")).len(),
        1,
        "unchanged rows are indexed once"
    );
    assert!(all(query(&path, "quoted", "screen")).is_empty());
    assert_eq!(fs::read(path.join("records.bin")).unwrap(), original);
}

fn special(path: &Path) {
    let mut writer = ContainerWriter::create(
        path,
        &RecordingMetadata {
            recording_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
            title: "context fixture".into(),
            started_at_unix_millis: 0,
            hostname: Some("local.test".into()),
        },
    )
    .unwrap();
    let mut sampler = AdaptiveSampler::new(SamplingPolicy::default()).unwrap();
    let mut frame = pb::TerminalFrameDiff {
        frame_schema_version: TERMINAL_FRAME_SCHEMA_VERSION.into(),
        frame_kind: pb::TerminalFrameKind::Snapshot as i32,
        viewport_rows: 3,
        viewport_cols: 80,
        cursor: Some(pb::TerminalCursor::default()),
        modes: Some(pb::TerminalFrameModes::default()),
        rows: vec![
            pb::TerminalRow {
                index: 0,
                text: "İstanbul --very-".into(),
                wrapped: true,
                ..Default::default()
            },
            pb::TerminalRow {
                index: 1,
                text: "long-option 雪".into(),
                ..Default::default()
            },
            pb::TerminalRow {
                index: 2,
                text: "first retained output".into(),
                ..Default::default()
            },
        ],
        sized_text: vec![pb::TerminalSizedTextPlacement {
            text: "Large DISPLAY".into(),
            row: 2,
            width_cells: 10,
            height_cells: 1,
            ..Default::default()
        }],
        ..Default::default()
    };
    writer
        .append_visual(
            sampler.observe_frame(0, frame.clone()).unwrap().unwrap(),
            &[],
        )
        .unwrap();
    writer
        .append_semantic(&SemanticEvent {
            offset_micros: 500_000,
            kind: SemanticKind::ContextChanged,
            context_id: "nested".into(),
            command_id: None,
            command: None,
            cwd: Some("/remote".into()),
            hostname: Some("remote.test".into()),
            exit_code: None,
        })
        .unwrap();
    frame.rows[2].text = "second retained output".into();
    writer
        .append_visual(
            sampler.observe_frame(1_000_000, frame).unwrap().unwrap(),
            &[],
        )
        .unwrap();
    writer
        .append_semantic(&SemanticEvent {
            offset_micros: 1_100_000,
            kind: SemanticKind::CommandFinished,
            context_id: "nested".into(),
            command_id: Some("started-before-recording".into()),
            command: Some("printf 'orphan 雪'".into()),
            cwd: Some("/remote".into()),
            hostname: Some("remote.test".into()),
            exit_code: Some(0),
        })
        .unwrap();
    writer.finish(2_000_000).unwrap();
}

#[test]
fn matches_soft_wrap_unicode_sized_text_remote_contexts_and_orphan_command_finishes() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("special.trailrec");
    special(&path);
    let mut input = query(&path, "İSTANBUL --VERY-LONG-OPTION 雪", "screen");
    let hits = all(input.clone());
    assert_eq!(hits.len(), 2);
    assert_eq!(hits[0]["preview"], "İstanbul --very-long-option 雪");
    assert_eq!(hits[0]["hostname"], "local.test");
    assert_eq!(hits[1]["hostname"], "remote.test");
    assert_eq!(hits[1]["offset_micros"], 500_000);
    input["hostname"] = json!("REMOTE");
    assert_eq!(all(input).len(), 1);
    assert_eq!(all(query(&path, "large display", "screen")).len(), 2);
    let commands = all(query(&path, "orphan", "command"));
    assert_eq!(commands.len(), 1);
    assert_eq!(commands[0]["hostname"], "remote.test");
    assert!(all(query(&path, "unsampled output", "all")).is_empty());
}

#[test]
fn damaged_cache_rebuilds_and_source_growth_indexes_only_the_verified_prefix() {
    use std::io::Write;
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("sample.trailrec");
    fixture::create(&path, 4);
    let input = query(&path, "frame", "screen");
    let expected = all(input.clone());
    for name in ["search.index", "search.info"] {
        let target = path.join(name);
        let mut bytes = fs::read(&target).unwrap();
        bytes[0] ^= 1;
        fs::write(&target, bytes).unwrap();
        assert_eq!(all(input.clone()), expected);
    }
    fs::OpenOptions::new()
        .append(true)
        .open(path.join("records.bin"))
        .unwrap()
        .write_all(b"damaged tail")
        .unwrap();
    let original = fs::read(path.join("records.bin")).unwrap();
    assert_eq!(all(input), expected);
    assert_eq!(fs::read(path.join("records.bin")).unwrap(), original);
}

#[test]
fn invalid_queries_are_rejected_before_index_creation() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("sample.trailrec");
    fixture::create(&path, 1);
    for (key, value) in [
        ("limit", json!(0)),
        ("limit", json!(101)),
        ("query", json!("x".repeat(1025))),
        ("query", json!("a\0b")),
        ("kind", json!("input")),
        ("recording_id", json!("wrong")),
    ] {
        let mut input = query(&path, "frame", "all");
        input[key] = value;
        assert_eq!(run(input)["ok"], false);
        assert!(!path.join("search.info").exists());
    }
}

#[test]
fn cancellation_during_index_build_publishes_no_partial_index() {
    use std::time::{Duration, Instant};
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("long.trailrec");
    fixture::create(&path, 10_000);
    let before: Vec<_> = fs::read_dir(&path)
        .unwrap()
        .map(|x| x.unwrap().path())
        .collect();
    let reserved = request("reserve", None, json!({}));
    let id = reserved["job_id"].as_str().unwrap().to_owned();
    let worker_id = id.clone();
    let input = query(&path, "missing", "all");
    let worker = std::thread::spawn(move || request("search", Some(&worker_id), input));
    let started = Instant::now();
    loop {
        let writing = fs::read_dir(&path).unwrap().any(|item| {
            let item = item.unwrap();
            !before.contains(&item.path()) && item.metadata().unwrap().len() > 1024
        });
        if writing {
            break;
        }
        assert!(
            !worker.is_finished(),
            "search finished before the cancellation checkpoint"
        );
        assert!(started.elapsed() < Duration::from_secs(10));
        std::thread::yield_now();
    }
    assert_eq!(request("cancel", Some(&id), json!({}))["ok"], true);
    let response = worker.join().unwrap();
    assert_eq!(response["ok"], false, "{response}");
    assert!(response["error"].as_str().unwrap().contains("cancelled"));
    assert_eq!(request("release", Some(&id), json!({}))["ok"], true);
    assert!(!path.join("search.info").exists());
    assert!(!path.join("search.index").exists());
}

#[test]
fn no_match_pages_have_forward_progress_and_bounded_scan_work() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("long.trailrec");
    fixture::create(&path, 3000);
    let input = query(&path, "absent needle", "all");
    let first = run(input.clone());
    assert_eq!(first["ok"], true, "{first}");
    assert!(first["result"]["hits"].as_array().unwrap().is_empty());
    assert!(
        first["result"]["next_cursor"]
            .as_u64()
            .is_some_and(|offset| offset > 8)
    );
    assert!(first["result"]["scanned_bytes"].as_u64().unwrap() < 4 * 1024 * 1024 + 1024);
    assert!(all(input).is_empty());
}
