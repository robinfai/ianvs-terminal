//! Owned-volume durability acceptance helper. It never mounts a volume or crashes an OS.
//! Use only new test bundles; stream mode is bounded to 120 actual seconds.

use ianvs_core::model::TERMINAL_FRAME_SCHEMA_VERSION;
use ianvs_core::proto::frame_diff as pb;
use ianvs_core::recording::{
    AdaptiveSampler, BackgroundWriter, ContainerReader, RecordedAsset, RecordingCompletion,
    RecordingMetadata, SamplingPolicy, SemanticEvent, SemanticKind, StoredRecord, WriterPhase,
};
use std::io::{self, Write};
use std::path::Path;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

fn event(offset: u64, large: bool) -> SemanticEvent {
    SemanticEvent {
        offset_micros: offset,
        kind: SemanticKind::CommandStarted,
        context_id: "owned-filesystem-fixture".into(),
        command_id: Some(format!("command-{offset}")),
        command: Some(if large {
            "x".repeat(32 * 1024)
        } else {
            "echo committed-marker".into()
        }),
        cwd: Some("/owned-fixture".into()),
        hostname: Some("filesystem-probe".into()),
        exit_code: None,
    }
}

fn until(mut check: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(10);
    while !check() {
        assert!(
            Instant::now() < deadline,
            "writer did not progress within deadline"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn scan(path: &Path) {
    let report = ContainerReader::open(path)
        .unwrap()
        .scan(|| false, |_| Ok(()))
        .unwrap();
    assert_ne!(report.completion, RecordingCompletion::Finished);
    assert!(report.summary.visual_count >= 1 && report.summary.semantic_count >= 1);
    let mut reader = ContainerReader::open(path).unwrap();
    let first = reader.next_record().unwrap().unwrap();
    if let StoredRecord::Visual { sample, assets } = first.record {
        assert_eq!(sample.frame.rows[0].text, "committed screen 雪");
        assert_eq!(assets.len(), 1);
        let asset = reader.load_asset(&assets[0]).unwrap();
        assert_eq!(asset.rgba, vec![255, 0, 0, 255, 0, 255, 0, 255]);
    } else {
        panic!("committed visual missing");
    }
    println!("recovered_records={}", report.summary.record_count);
    println!(
        "recovered_duration_micros={}",
        report.summary.duration_micros
    );
    println!("completion={:?}", report.completion);
    println!("verified_bytes={}", report.verified_bytes);
    println!("screen_and_asset_verified=true");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mode = args.get(1).expect("write|scan mode");
    let path = Path::new(args.get(2).expect("new owned bundle path"));
    if mode == "scan" {
        scan(path);
        return;
    }
    assert!(mode == "write" || mode == "stream");
    let capture_clock = Instant::now();
    let metadata = RecordingMetadata {
        recording_id: "filesystem-probe".into(),
        started_at_unix_millis: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64,
        title: "Owned filesystem failure fixture".into(),
        hostname: Some("filesystem-probe".into()),
    };
    let frame = pb::TerminalFrameDiff {
        frame_schema_version: TERMINAL_FRAME_SCHEMA_VERSION.into(),
        frame_kind: pb::TerminalFrameKind::Snapshot as i32,
        viewport_rows: 1,
        viewport_cols: 80,
        cursor: Some(pb::TerminalCursor::default()),
        modes: Some(pb::TerminalFrameModes::default()),
        rows: vec![pb::TerminalRow {
            text: "committed screen 雪".into(),
            ..Default::default()
        }],
        graphics: vec![pb::TerminalGraphicPlacement {
            asset_key: Some(pb::TerminalGraphicAssetKey {
                asset_id: 3,
                asset_version: 1,
            }),
            ..Default::default()
        }],
        ..Default::default()
    };
    let sample = AdaptiveSampler::new(SamplingPolicy::default())
        .unwrap()
        .observe_frame(0, frame)
        .unwrap()
        .unwrap();
    let mut writer = BackgroundWriter::start(path, &metadata).unwrap();
    writer
        .enqueue_visual(
            sample,
            vec![RecordedAsset {
                asset_id: 3,
                asset_version: 1,
                width: 2,
                height: 1,
                rgba: vec![255, 0, 0, 255, 0, 255, 0, 255],
            }],
        )
        .unwrap();
    writer.enqueue_semantic(&event(1, false)).unwrap();
    until(|| writer.status().committed.record_count >= 2);
    println!(
        "READY committed_records={}",
        writer.status().committed.record_count
    );
    io::stdout().flush().unwrap();
    if mode == "stream" {
        while capture_clock.elapsed() < Duration::from_secs(120) {
            let now = capture_clock.elapsed().as_micros() as u64;
            writer.enqueue_semantic(&event(now, true)).unwrap();
            let status = writer.status();
            assert_eq!(status.phase, WriterPhase::Capturing);
            println!(
                "PROGRESS elapsed_micros={} committed_records={} committed_duration_micros={} written_records={} written_duration_micros={}",
                now,
                status.committed.record_count,
                status.committed.duration_micros,
                status.written.record_count,
                status.written.duration_micros
            );
            io::stdout().flush().unwrap();
            std::thread::sleep(Duration::from_millis(100));
        }
        panic!("system-crash injection did not arrive within 120 seconds");
    }
    let mut line = String::new();
    io::stdin().read_line(&mut line).unwrap();
    assert_eq!(line.trim(), "stress");
    let started = Instant::now();
    for count in 0..4096 {
        let before = writer.status().written.record_count;
        if writer.enqueue_semantic(&event(10 + count, true)).is_err() {
            break;
        }
        until(|| {
            writer.status().phase == WriterPhase::Failed
                || writer.status().written.record_count > before
        });
        if writer.status().phase == WriterPhase::Failed {
            break;
        }
    }
    until(|| writer.status().settled);
    let status = writer.status();
    assert_eq!(status.phase, WriterPhase::Failed);
    assert!(status.committed.record_count >= 2);
    assert!(writer.request_finish(10_000).is_err());
    println!("writer_phase={:?}", status.phase);
    println!("writer_error={:?}", status.error);
    println!("committed_records={}", status.committed.record_count);
    println!("failure_observed_micros={}", started.elapsed().as_micros());
    println!("settled={}", status.settled);
    println!("finish_rejected=true");
}
