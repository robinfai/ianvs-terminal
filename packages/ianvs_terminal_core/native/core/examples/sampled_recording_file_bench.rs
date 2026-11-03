//! Real container/file-service measurements with accelerated logical time.
//! OS file caches are warm; this is not Flutter, PTY or wall-clock endurance QA.
use ianvs_core::model::TERMINAL_FRAME_SCHEMA_VERSION;
use ianvs_core::proto::frame_diff as pb;
use ianvs_core::recording::file_service::request_json;
use ianvs_core::recording::{
    AdaptiveSampler, ContainerWriter, RecordingMetadata, SamplingPolicy, SemanticEvent,
    SemanticKind,
};
use serde_json::{Value, json};
use std::error::Error;
use std::path::Path;
use std::time::Instant;

fn request(operation: &str, job_id: Option<&str>, payload: Value) -> Result<Value, Box<dyn Error>> {
    let reply: Value = serde_json::from_str(&request_json(
        &json!({"schema_version":2,"operation":operation,"job_id":job_id,"payload":payload})
            .to_string(),
    ))?;
    if reply["ok"] != true {
        return Err(reply.to_string().into());
    }
    Ok(reply)
}

fn run(operation: &str, payload: Value) -> Result<Value, Box<dyn Error>> {
    let ticket = request("reserve", None, json!({}))?;
    let id = ticket["job_id"].as_str().ok_or("missing job")?;
    let result = request(operation, Some(id), payload);
    request("release", Some(id), json!({}))?;
    Ok(result?["result"].clone())
}

fn percentiles(mut times: Vec<u128>) -> Value {
    times.sort_unstable();
    json!({"p50_micros":times[times.len()/2],"p95_micros":times[(times.len()-1)*95/100],"max_micros":times.last()})
}

fn measure(frames: u64) -> Result<Value, Box<dyn Error>> {
    let root = tempfile::tempdir()?;
    let path = root.path().join("file-benchmark.trailrec");
    let metadata = RecordingMetadata {
        recording_id: "file-benchmark".into(),
        started_at_unix_millis: 0,
        title: "Synthetic file benchmark".into(),
        hostname: Some("fixture.local".into()),
    };
    let started = Instant::now();
    let mut writer = ContainerWriter::create(&path, &metadata)?;
    let mut sampler = AdaptiveSampler::new(SamplingPolicy::default())?;
    let mut command_count = 0;
    for n in 0..frames {
        let frame = pb::TerminalFrameDiff {
            frame_schema_version: TERMINAL_FRAME_SCHEMA_VERSION.into(),
            frame_kind: pb::TerminalFrameKind::Snapshot as i32,
            viewport_cols: 120,
            viewport_rows: 40,
            cursor: Some(pb::TerminalCursor::default()),
            modes: Some(pb::TerminalFrameModes::default()),
            rows: (0..40)
                .map(|row| pb::TerminalRow {
                    index: row,
                    text: if row == 0 {
                        format!("sample {n} 雪")
                    } else {
                        format!("fixed row {row} {}", "x".repeat(96))
                    },
                    ..Default::default()
                })
                .collect(),
            ..Default::default()
        };
        writer.append_visual(
            sampler
                .observe_frame(n * 1_000_000, frame)?
                .ok_or("missing sample")?,
            &[],
        )?;
        if n.is_multiple_of(10) {
            writer.append_semantic(&SemanticEvent {
                offset_micros: n * 1_000_000,
                kind: SemanticKind::CommandStarted,
                context_id: "fixture".into(),
                command_id: Some(n.to_string()),
                command: Some(format!("echo sample-{n} '雪'")),
                cwd: Some("/fixture".into()),
                hostname: Some("fixture.local".into()),
                exit_code: None,
            })?;
            command_count += 1;
        }
        if n % 5000 == 4999 {
            writer.commit()?;
        }
    }
    let finish_start = Instant::now();
    let summary = writer.finish(frames * 1_000_000)?;
    let finish_micros = finish_start.elapsed().as_micros();
    let creation_micros = started.elapsed().as_micros();
    let cache_before = std::fs::read(path.join("summary.index"))?;
    let mut open_times = Vec::new();
    for _ in 0..25 {
        let start = Instant::now();
        let info = run("inspect", json!({"bundle_path":path}))?;
        open_times.push(start.elapsed().as_micros());
        if info["summary"]["visual_count"] != frames
            || info["summary"]["semantic_count"] != command_count
        {
            return Err("open summary mismatch".into());
        }
    }
    if cache_before != std::fs::read(path.join("summary.index"))? {
        return Err("cached opens unexpectedly rebuilt indexes".into());
    }
    let mut seek_times = Vec::new();
    for n in 0..100 {
        let target = (n * 7919) % frames;
        let start = Instant::now();
        let screen = run(
            "seek",
            json!({"bundle_path":path,"recording_id":metadata.recording_id,"offset_micros":target * 1_000_000}),
        )?;
        seek_times.push(start.elapsed().as_micros());
        if screen["screen"]["offset_micros"] != target * 1_000_000 {
            return Err("random seek mismatch".into());
        }
    }
    let search_payload = |query: &str, cursor: u64| {
        json!({
            "bundle_path":path,"recording_id":metadata.recording_id,
            "query":query,"hostname":"fixture.local","kind":"all",
            "cursor":cursor,"limit":100,
        })
    };
    let start = Instant::now();
    let first_search = run("search", search_payload("sample", 0))?;
    let search_build_and_first_page_micros = start.elapsed().as_micros();
    if first_search["hits"]
        .as_array()
        .ok_or("missing search hits")?
        .len()
        != 100
    {
        return Err("dense search page mismatch".into());
    }
    let search_cache_before = std::fs::read(path.join("search.info"))?;
    let mut search_page_times = Vec::new();
    for _ in 0..25 {
        let start = Instant::now();
        run("search", search_payload("sample", 0))?;
        search_page_times.push(start.elapsed().as_micros());
    }
    let rare_query = format!("sample {} 雪", frames - 1);
    let mut full_scans = Vec::new();
    for query in [rare_query.as_str(), "not-present-in-any-document"] {
        let start = Instant::now();
        let mut cursor = 0;
        let mut hits = 0;
        let mut pages = Vec::new();
        let mut scanned_bytes = 0;
        loop {
            let page_start = Instant::now();
            let result = run("search", search_payload(query, cursor))?;
            pages.push(page_start.elapsed().as_micros());
            hits += result["hits"]
                .as_array()
                .ok_or("missing search hits")?
                .len();
            scanned_bytes += result["scanned_bytes"]
                .as_u64()
                .ok_or("missing scan bytes")?;
            let Some(next) = result["next_cursor"].as_u64() else {
                break;
            };
            if next <= cursor {
                return Err("nonadvancing search page".into());
            }
            cursor = next;
        }
        let expected = usize::from(query == rare_query);
        if hits != expected {
            return Err("full search result mismatch".into());
        }
        full_scans.push(json!({"query":query,"hits":hits,"pages":pages.len(),
            "scanned_bytes":scanned_bytes,"total_micros":start.elapsed().as_micros(),
            "page_latency":percentiles(pages)}));
    }
    if search_cache_before != std::fs::read(path.join("search.info"))? {
        return Err("cached searches unexpectedly rebuilt indexes".into());
    }
    std::fs::remove_file(path.join("summary.index"))?;
    let start = Instant::now();
    let rebuilt = run("inspect", json!({"bundle_path":path}))?;
    let recovery_scan_micros = start.elapsed().as_micros();
    if rebuilt["summary"] != serde_json::to_value(&summary)? {
        return Err("rebuilt summary mismatch".into());
    }
    let bytes = |name: &str| -> Result<u64, Box<dyn Error>> {
        Ok(std::fs::metadata(path.join(name))?.len())
    };
    Ok(
        json!({"visual_samples":frames,"commands":command_count,"logical_duration_seconds":frames,"creation_micros":creation_micros,"finish_micros":finish_micros,"records_bytes":bytes("records.bin")?,"seek_index_bytes":bytes("seek.index")?,"commands_index_bytes":bytes("commands.index")?,"summary_index_bytes":bytes("summary.index")?,"search_index_bytes":bytes("search.index")?,"search_info_bytes":bytes("search.info")?,"search_build_and_first_page_micros":search_build_and_first_page_micros,"cached_dense_search_page":percentiles(search_page_times),"full_search_scans":full_scans,"cached_open":percentiles(open_times),"random_seek":percentiles(seek_times),"recovery_scan_micros":recovery_scan_micros}),
    )
}

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.len() > 1 {
        return Err("usage: sampled_recording_file_bench [output.json]".into());
    }
    let results = [measure(10_000)?, measure(100_000)?];
    let report = json!({"schema_version":1,"os":std::env::consts::OS,"arch":std::env::consts::ARCH,"duration_mode":"accelerated_logical_time","filesystem_cache":"warm","limitations":["synthetic structured frames, no live PTY or Flutter","no image assets, Flutter cross-file search, input latency, or power failure measurement","logical duration does not establish real 24-hour endurance"],"results":results});
    let output = serde_json::to_string_pretty(&report)?;
    if let Some(path) = args.first() {
        if let Some(parent) = Path::new(path).parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(path, &output)?;
    }
    println!("{output}");
    Ok(())
}
