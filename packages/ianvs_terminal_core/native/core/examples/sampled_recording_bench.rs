//! Deterministic measurement using the real VT engine and an independent
//! snapshot oracle. Logical duration is not wall-clock endurance evidence.
use ianvs_core::frame_diff_proto;
use ianvs_core::proto::frame_diff as pb;
use ianvs_core::recording::{
    AdaptiveSampler, SampleRecord, SamplingPolicy, ScreenReplay, SemanticEvent, SemanticKind,
    VisualSample,
};
use ianvs_core::session;
use prost::Message;
use serde::Serialize;
use std::error::Error;
use std::time::Instant;

struct Engine(u64);

impl Engine {
    fn new() -> Result<Self, Box<dyn Error>> {
        let profile = serde_json::json!({"id":"sampled-benchmark","name":"sampling",
            "launch":{"program":"/not/a/live/process"},"terminal":{"scrollbackLines":8000}});
        let engine = Self(session::create_replay_session(&profile.to_string())?);
        engine.resize(120, 40)?;
        Ok(engine)
    }
    fn resize(&self, cols: u16, rows: u16) -> Result<(), Box<dyn Error>> {
        session::resize_session(self.0, cols, rows, cols * 8, rows * 16)?;
        Ok(())
    }
    fn output(&self, output: &[u8]) -> Result<(), Box<dyn Error>> {
        if !output.is_empty() {
            session::replay_session_output(self.0, output)?;
        }
        Ok(())
    }
    fn frame(&self) -> Result<Option<pb::TerminalFrameDiff>, Box<dyn Error>> {
        session::take_frame_diff_protobuf(self.0)?
            .map(|bytes| pb::TerminalFrameDiff::decode(bytes.as_slice()).map_err(Into::into))
            .transpose()
    }
    fn snapshot(&self) -> Result<pb::TerminalFrameDiff, Box<dyn Error>> {
        let packet = session::take_frame_packet_v1_protobuf(self.0, Some(u64::MAX))?
            .ok_or("missing snapshot")?;
        frame_diff_proto::decode_frame_packet_v1_for_test(&packet)?
            .frame
            .ok_or_else(|| "missing snapshot payload".into())
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        let _ = session::close_session(self.0);
    }
}

fn normalized(mut frame: pb::TerminalFrameDiff) -> pb::TerminalFrameDiff {
    frame.frame_kind = pb::TerminalFrameKind::Snapshot as i32;
    frame.viewport_row_shift = 0;
    frame.dirty_ranges.clear();
    for row in &mut frame.rows {
        row.source_row = None;
        row.source_end_row = None;
        row.modified_at_micros = 0;
    }
    frame
}

#[derive(Default, Serialize)]
struct Metrics {
    workload: String,
    logical_duration_micros: u64,
    output_bytes_fed: u64,
    live_frames_applied: u64,
    visual_samples: u64,
    keyframes: u64,
    semantic_records: u64,
    semantic_json_bytes: u64,
    sampled_delta_protobuf_bytes: u64,
    equivalent_sampled_snapshot_protobuf_bytes: u64,
    max_retained_screen_protobuf_bytes: usize,
    sampler_p50_micros: u64,
    sampler_p95_micros: u64,
    sampler_max_micros: u64,
    wall_elapsed_micros: u128,
    snapshot_comparisons: u64,
}

fn accept(
    sample: VisualSample,
    replay: &mut ScreenReplay,
    oracle: &Engine,
    metrics: &mut Metrics,
) -> Result<(), Box<dyn Error>> {
    metrics.visual_samples += 1;
    metrics.keyframes += u64::from(sample.base_sequence.is_none());
    metrics.sampled_delta_protobuf_bytes += sample.frame.encoded_len() as u64;
    replay.apply(sample)?;
    let expected = normalized(oracle.snapshot()?);
    let actual = normalized(replay.screen().ok_or("missing restored screen")?.clone());
    if actual != expected {
        return Err(format!("{}: sampled state diverges from snapshot", metrics.workload).into());
    }
    metrics.equivalent_sampled_snapshot_protobuf_bytes += actual.encoded_len() as u64;
    metrics.snapshot_comparisons += 1;
    Ok(())
}

fn output(workload: &str, tick: u64) -> String {
    match workload {
        "idle" => String::new(),
        "shell" if tick % 100 == 1 => format!("$ echo task-{tick}\r\ntask-{tick}\r\n"),
        "logs" => (0..10)
            .map(|line| {
                format!(
                    "INFO id={} route=/items/{} status=200 latency={}ms\r\n",
                    tick * 10 + line,
                    tick % 83,
                    tick % 97
                )
            })
            .collect(),
        "scrollback_eviction" => (0..10)
            .map(|line| format!("line-{:05}\r\n", tick * 10 + line))
            .collect(),
        "tui" if tick == 1 => "\x1b[?1049h\x1b[2J\x1b[?25l".to_owned(),
        "tui" => format!(
            "\x1b[?2026h\x1b[4;1H\x1b[32mprogress={tick:08}\x1b[0m\x1b[5;1H你好 👩‍💻\x1b[?2026l"
        ),
        "metadata" => format!("\x1b]2;title-{tick}\x07"),
        "resize" => format!("tick={tick}\r\n"),
        _ => String::new(),
    }
}

fn measure(workload: &str, ticks: u64) -> Result<Metrics, Box<dyn Error>> {
    let start = Instant::now();
    let source = Engine::new()?;
    let oracle = Engine::new()?;
    let mut sampler = AdaptiveSampler::new(SamplingPolicy::default())?;
    let mut replay = ScreenReplay::default();
    let mut metrics = Metrics {
        workload: workload.to_owned(),
        logical_duration_micros: ticks * 20_000,
        ..Default::default()
    };
    let mut timings = Vec::new();
    let initial = sampler
        .observe_frame(0, source.frame()?.ok_or("missing initial screen")?)?
        .ok_or("missing first sample")?;
    accept(initial, &mut replay, &oracle, &mut metrics)?;
    for tick in 1..=ticks {
        if workload == "resize" && tick % 200 == 0 {
            let (cols, rows) = if tick % 400 == 0 { (120, 40) } else { (80, 24) };
            source.resize(cols, rows)?;
            oracle.resize(cols, rows)?;
        }
        let bytes = output(workload, tick);
        source.output(bytes.as_bytes())?;
        oracle.output(bytes.as_bytes())?;
        metrics.output_bytes_fed += bytes.len() as u64;
        let frame = source.frame()?;
        let now = tick * 20_000;
        let timed = Instant::now();
        let sample = if let Some(frame) = frame {
            metrics.live_frames_applied += 1;
            sampler.observe_frame(now, frame)?
        } else {
            sampler.tick(now)?
        };
        timings.push(timed.elapsed().as_micros() as u64);
        if let Some(sample) = sample {
            accept(sample, &mut replay, &oracle, &mut metrics)?;
        }
        if workload == "shell" && tick % 100 == 1 {
            let event = SemanticEvent {
                offset_micros: now,
                kind: SemanticKind::CommandStarted,
                context_id: "root".to_owned(),
                command_id: Some(tick.to_string()),
                command: Some(format!("echo task-{tick}")),
                cwd: Some("/benchmark".to_owned()),
                hostname: Some("synthetic".to_owned()),
                exit_code: None,
            };
            for record in sampler.observe_semantic(event)? {
                match record {
                    SampleRecord::Visual(sample) => {
                        accept(*sample, &mut replay, &oracle, &mut metrics)?
                    }
                    SampleRecord::Semantic(event) => {
                        metrics.semantic_records += 1;
                        metrics.semantic_json_bytes += serde_json::to_vec(&event)?.len() as u64;
                    }
                }
            }
        }
        metrics.max_retained_screen_protobuf_bytes = metrics
            .max_retained_screen_protobuf_bytes
            .max(sampler.retained_screen_protobuf_bytes());
    }
    if let Some(sample) = sampler.finish(ticks * 20_000 + 1)? {
        accept(sample, &mut replay, &oracle, &mut metrics)?;
    }
    timings.sort_unstable();
    metrics.sampler_p50_micros = timings[timings.len() / 2];
    metrics.sampler_p95_micros = timings[(timings.len() - 1) * 95 / 100];
    metrics.sampler_max_micros = *timings.last().ok_or("no timings")?;
    metrics.wall_elapsed_micros = start.elapsed().as_micros();
    Ok(metrics)
}

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.len() > 1 {
        return Err("usage: sampled_recording_bench [output.json]".into());
    }
    let mut results = Vec::new();
    for workload in [
        "idle",
        "shell",
        "logs",
        "tui",
        "scrollback_eviction",
        "resize",
        "metadata",
    ] {
        results.push(measure(workload, 3000)?);
    }
    let report = serde_json::json!({
        "schema_version":1, "os":std::env::consts::OS, "arch":std::env::consts::ARCH,
        "fidelity":"adaptive_structured_screens", "duration_mode":"accelerated_logical_time",
        "limitations":["frame payload bytes exclude container, compression, indexes and image blobs",
            "synthetic semantic events do not prove hook delivery", "encoded retained bytes are not heap/RSS",
            "does not launch Flutter or establish 24-hour endurance"],
        "policy":{"minimum_interval_micros":100_000,"maximum_interval_micros":1_000_000,"keyframe_interval_micros":5_000_000},
        "results":results });
    let json = serde_json::to_string_pretty(&report)?;
    if let Some(path) = args.first() {
        if let Some(parent) = std::path::Path::new(path).parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(path, &json)?;
    }
    println!("{json}");
    Ok(())
}
