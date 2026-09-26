use ianvs_core::model::TERMINAL_FRAME_SCHEMA_VERSION;
use ianvs_core::proto::frame_diff as pb;
use ianvs_core::recording::{
    AdaptiveSampler, BackgroundWriter, ContainerReader, ContainerWriter, QueueBudget,
    RecordedAsset, RecordingCompletion, RecordingIndex, RecordingMetadata, SampleRecord,
    SamplingPolicy, SemanticEvent, SemanticKind, StorageError, StoredRecord, VisualSample,
    WriterPhase,
};
use std::fs;
use std::path::Path;
use std::time::{Duration, Instant};

fn metadata() -> RecordingMetadata {
    RecordingMetadata {
        recording_id: "test-session".into(),
        started_at_unix_millis: 42,
        title: "部署复盘".into(),
        hostname: Some("host-a".into()),
    }
}
fn frame(text: &str) -> pb::TerminalFrameDiff {
    pb::TerminalFrameDiff {
        frame_schema_version: TERMINAL_FRAME_SCHEMA_VERSION.into(),
        frame_kind: pb::TerminalFrameKind::Snapshot as i32,
        viewport_rows: 1,
        viewport_cols: 80,
        cursor: Some(pb::TerminalCursor::default()),
        modes: Some(pb::TerminalFrameModes::default()),
        rows: vec![pb::TerminalRow {
            text: text.into(),
            ..Default::default()
        }],
        ..Default::default()
    }
}
fn sample(text: &str) -> VisualSample {
    AdaptiveSampler::new(SamplingPolicy::default())
        .unwrap()
        .observe_frame(0, frame(text))
        .unwrap()
        .unwrap()
}
fn event(offset_micros: u64) -> SemanticEvent {
    SemanticEvent {
        offset_micros,
        kind: SemanticKind::CommandStarted,
        context_id: "host-a-shell".into(),
        command_id: Some(format!("command-{offset_micros}")),
        command: Some("echo '雪 ❄' && printf '\\033]52;c;anything\\007'".into()),
        cwd: Some("/srv/app".into()),
        hostname: Some("host-a".into()),
        exit_code: None,
    }
}
fn wait_until(mut condition: impl FnMut() -> bool) {
    let start = Instant::now();
    while !condition() {
        assert!(
            start.elapsed() < Duration::from_secs(8),
            "condition timed out"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn round_trip_streams_visuals_commands_and_footer_without_a_terminal() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("session.trailrec");
    let mut writer = ContainerWriter::create(&path, &metadata()).unwrap();
    let first = sample("already on screen");
    writer.append_visual(first.clone(), &[]).unwrap();
    writer.append_semantic(&event(100)).unwrap();
    let summary = writer.finish(2_000_000).unwrap();
    assert_eq!(summary.record_count, 2);
    let mut reader = ContainerReader::open(&path).unwrap();
    assert_eq!(reader.metadata, metadata());
    assert!(matches!(reader.next_record().unwrap().unwrap().record,
        StoredRecord::Visual { sample, .. } if *sample == first));
    assert_eq!(reader.screen().unwrap().rows[0].text, "already on screen");
    assert_eq!(
        reader.next_record().unwrap().unwrap().record,
        StoredRecord::Semantic(event(100))
    );
    assert_eq!(
        reader.next_record().unwrap().unwrap().record,
        StoredRecord::Finished(summary.clone())
    );
    assert!(reader.next_record().unwrap().is_none());
    let report = ContainerReader::open(&path)
        .unwrap()
        .scan(|| false, |_| Ok(()))
        .unwrap();
    assert_eq!(report.completion, RecordingCompletion::Finished);
    assert_eq!(report.summary, summary);
    assert_eq!(
        report.verified_bytes,
        fs::metadata(path.join("records.bin")).unwrap().len()
    );
}

#[test]
fn assets_survive_reopen_deduplicate_by_content_and_detect_corruption() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("images.trailrec");
    let mut writer = ContainerWriter::create(&path, &metadata()).unwrap();
    let mut first = sample("image");
    first.frame.graphics.push(pb::TerminalGraphicPlacement {
        asset_key: Some(pb::TerminalGraphicAssetKey {
            asset_id: 3,
            asset_version: 1,
        }),
        ..Default::default()
    });
    let mut asset = RecordedAsset {
        asset_id: 3,
        asset_version: 1,
        width: 2,
        height: 1,
        rgba: vec![255, 0, 0, 255, 0, 255, 0, 255],
    };
    writer
        .append_visual(first.clone(), &[asset.clone()])
        .unwrap();
    first.sequence = 1;
    first.offset_micros = 1_000_000;
    first.frame.graphics[0]
        .asset_key
        .as_mut()
        .unwrap()
        .asset_version = 2;
    asset.asset_version = 2;
    writer.append_visual(first, &[asset.clone()]).unwrap();
    writer.finish(1_000_000).unwrap();
    assert_eq!(fs::read_dir(path.join("assets")).unwrap().count(), 1);
    let mut reader = ContainerReader::open(&path).unwrap();
    reader.next_record().unwrap();
    let StoredRecord::Visual { assets, .. } = reader.next_record().unwrap().unwrap().record else {
        panic!()
    };
    assert_eq!(reader.load_asset(&assets[0]).unwrap(), asset);
    let blob = fs::read_dir(path.join("assets"))
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let mut bytes = fs::read(&blob).unwrap();
    bytes[16] ^= 1;
    fs::write(&blob, bytes).unwrap();
    assert!(reader.load_asset(&assets[0]).is_err());
}

#[test]
fn missing_assets_and_oversized_dimensions_cannot_publish_a_visual() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("invalid.trailrec");
    let mut writer = ContainerWriter::create(&path, &metadata()).unwrap();
    let mut first = sample("image");
    first.frame.graphics.push(pb::TerminalGraphicPlacement {
        asset_key: Some(pb::TerminalGraphicAssetKey {
            asset_id: 1,
            asset_version: 1,
        }),
        ..Default::default()
    });
    assert!(writer.append_visual(first.clone(), &[]).is_err());
    let huge = RecordedAsset {
        asset_id: 1,
        asset_version: 1,
        width: u32::MAX,
        height: u32::MAX,
        rgba: vec![],
    };
    assert!(writer.append_visual(first, &[huge]).is_err());
    writer
        .append_visual(sample("valid after rejected input"), &[])
        .unwrap();
    writer.finish(0).unwrap();
    assert_eq!(
        ContainerReader::open(&path)
            .unwrap()
            .scan(|| false, |_| Ok(()))
            .unwrap()
            .summary
            .visual_count,
        1
    );
}

#[test]
fn every_partial_tail_returns_only_the_verified_prefix_and_never_rewrites_it() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("partial.trailrec");
    let mut writer = ContainerWriter::create(&path, &metadata()).unwrap();
    writer.append_visual(sample("verified"), &[]).unwrap();
    writer.commit().unwrap();
    let prefix = fs::read(path.join("records.bin")).unwrap();
    writer.append_semantic(&event(1)).unwrap();
    writer.finish(1).unwrap();
    let whole = fs::read(path.join("records.bin")).unwrap();
    for length in prefix.len()..whole.len() {
        fs::write(path.join("records.bin"), &whole[..length]).unwrap();
        let report = ContainerReader::open(&path)
            .unwrap()
            .scan(|| false, |_| Ok(()))
            .unwrap();
        assert_ne!(report.completion, RecordingCompletion::Finished);
        assert!(
            report.verified_bytes >= prefix.len() as u64 && report.verified_bytes <= length as u64
        );
        assert_eq!(report.summary.visual_count, 1);
        assert_eq!(fs::read(path.join("records.bin")).unwrap(), whole[..length]);
    }
}

#[test]
fn corrupt_payload_huge_length_and_extra_footer_bytes_are_rejected() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("corrupt.trailrec");
    let mut writer = ContainerWriter::create(&path, &metadata()).unwrap();
    writer.append_visual(sample("intact"), &[]).unwrap();
    writer.commit().unwrap();
    let prefix_len = fs::metadata(path.join("records.bin")).unwrap().len() as usize;
    writer.append_semantic(&event(1)).unwrap();
    writer.finish(1).unwrap();
    let original = fs::read(path.join("records.bin")).unwrap();
    let mut corrupt = original.clone();
    corrupt[prefix_len + 60] ^= 1;
    fs::write(path.join("records.bin"), corrupt).unwrap();
    let report = ContainerReader::open(&path)
        .unwrap()
        .scan(|| false, |_| Ok(()))
        .unwrap();
    assert_eq!(report.verified_bytes, prefix_len as u64);
    assert!(matches!(
        report.completion,
        RecordingCompletion::DamagedTail(_)
    ));
    let mut huge = original.clone();
    huge[prefix_len + 8..prefix_len + 12].copy_from_slice(&u32::MAX.to_le_bytes());
    fs::write(path.join("records.bin"), huge).unwrap();
    let report = ContainerReader::open(&path)
        .unwrap()
        .scan(|| false, |_| Ok(()))
        .unwrap();
    assert_eq!(report.verified_bytes, prefix_len as u64);
    let mut extra = original;
    extra.push(0);
    fs::write(path.join("records.bin"), extra).unwrap();
    assert!(matches!(
        ContainerReader::open(&path)
            .unwrap()
            .scan(|| false, |_| Ok(()))
            .unwrap()
            .completion,
        RecordingCompletion::DamagedTail(_)
    ));
}

#[test]
fn invalid_order_is_rejected_before_append_and_legacy_files_remain_intact() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("ordered.trailrec");
    let mut writer = ContainerWriter::create(&path, &metadata()).unwrap();
    writer.append_visual(sample("first"), &[]).unwrap();
    writer.append_semantic(&event(100)).unwrap();
    assert!(writer.append_semantic(&event(99)).is_err());
    assert!(
        writer
            .append_visual(sample("duplicate sequence"), &[])
            .is_err()
    );
    let summary = writer.finish(100).unwrap();
    assert_eq!(summary.record_count, 2);
    let legacy = dir.path().join("old.ndjson");
    let bytes = b"{\"schema\":1}\n";
    fs::write(&legacy, bytes).unwrap();
    assert!(matches!(
        ContainerReader::open(&legacy),
        Err(StorageError::UnsupportedFormat)
    ));
    assert!(ContainerWriter::create(&legacy, &metadata()).is_err());
    assert_eq!(fs::read(&legacy).unwrap(), bytes);
    assert!(ContainerWriter::create(&path, &metadata()).is_err());
}

#[test]
fn scan_cancellation_leaves_recording_unchanged() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("cancel.trailrec");
    let mut writer = ContainerWriter::create(&path, &metadata()).unwrap();
    writer.append_visual(sample("first"), &[]).unwrap();
    writer.finish(0).unwrap();
    let before = fs::read(path.join("records.bin")).unwrap();
    assert!(matches!(
        ContainerReader::open(&path)
            .unwrap()
            .scan(|| true, |_| Ok(())),
        Err(StorageError::Cancelled)
    ));
    assert_eq!(fs::read(path.join("records.bin")).unwrap(), before);
}

#[test]
fn background_finish_drains_records_and_releases_shared_budget() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("background.trailrec");
    let budget = QueueBudget::new(1024 * 1024);
    let mut writer = BackgroundWriter::with_budget(&path, &metadata(), budget.clone()).unwrap();
    writer.enqueue_visual(sample("start"), vec![]).unwrap();
    for time in 1..20 {
        writer.enqueue_semantic(&event(time)).unwrap();
    }
    writer.request_finish(100).unwrap();
    wait_until(|| {
        matches!(
            writer.status().phase,
            WriterPhase::Finished | WriterPhase::Failed
        )
    });
    let status = writer.status();
    assert_eq!(status.phase, WriterPhase::Finished, "{status:?}");
    assert_eq!(status.committed.semantic_count, 19);
    assert_eq!(budget.used_bytes(), 0);
    let report = ContainerReader::open(&path)
        .unwrap()
        .scan(|| false, |_| Ok(()))
        .unwrap();
    assert_eq!(report.completion, RecordingCompletion::Finished);
    assert_eq!(report.summary, status.committed);
}

#[test]
fn admission_failure_is_visible_and_does_not_forge_a_complete_recording() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("budget.trailrec");
    let budget = QueueBudget::new(1);
    let mut writer = BackgroundWriter::with_budget(&path, &metadata(), budget.clone()).unwrap();
    assert!(matches!(
        writer.enqueue_semantic(&event(1)),
        Err(StorageError::QueueExhausted)
    ));
    assert_eq!(writer.status().phase, WriterPhase::Failed);
    assert!(writer.request_finish(1).is_err());
    assert_eq!(budget.used_bytes(), 0);
    assert_eq!(
        ContainerReader::open(&path)
            .unwrap()
            .scan(|| false, |_| Ok(()))
            .unwrap()
            .completion,
        RecordingCompletion::Interrupted
    );
}

#[test]
fn idle_wall_clock_deadline_commits_without_more_frames() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("idle.trailrec");
    let mut writer = BackgroundWriter::start(&path, &metadata()).unwrap();
    writer.enqueue_visual(sample("idle"), vec![]).unwrap();
    let started = Instant::now();
    wait_until(|| writer.status().committed.visual_count == 1);
    assert!(started.elapsed() < Duration::from_secs(8));
    writer.request_finish(5_000_000).unwrap();
    wait_until(|| writer.status().phase == WriterPhase::Finished);
}

#[test]
fn abrupt_process_kill_preserves_synced_records_as_interrupted() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("killed.trailrec");
    let marker = dir.path().join("ready");
    let mut child = std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "recording_crash_child_helper", "--nocapture"])
        .env("TRAIL_RECORDING_CRASH_CHILD", &path)
        .env("TRAIL_RECORDING_CRASH_MARKER", &marker)
        .stdout(std::process::Stdio::null())
        .spawn()
        .unwrap();
    let start = Instant::now();
    while !marker.exists() && start.elapsed() < Duration::from_secs(8) {
        assert!(
            child.try_wait().unwrap().is_none(),
            "child exited before commit"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
    child.kill().unwrap();
    child.wait().unwrap();
    assert!(marker.exists(), "child never reported commit");
    let report = ContainerReader::open(&path)
        .unwrap()
        .scan(|| false, |_| Ok(()))
        .unwrap();
    assert_eq!(report.completion, RecordingCompletion::Interrupted);
    assert_eq!(report.summary.visual_count, 1);
    assert_eq!(report.summary.semantic_count, 1);
}

#[test]
fn recording_crash_child_helper() {
    let Some(path) = std::env::var_os("TRAIL_RECORDING_CRASH_CHILD") else {
        return;
    };
    let mut writer = ContainerWriter::create(Path::new(&path), &metadata()).unwrap();
    writer
        .append_visual(sample("survives process kill"), &[])
        .unwrap();
    writer.append_semantic(&event(10)).unwrap();
    writer.commit().unwrap();
    fs::write(
        std::env::var_os("TRAIL_RECORDING_CRASH_MARKER").unwrap(),
        b"committed",
    )
    .unwrap();
    loop {
        std::thread::park();
    }
}

#[test]
fn disk_index_cold_seek_matches_sequential_replay_during_dense_hook_bursts() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("seek.trailrec");
    let mut writer = ContainerWriter::create(&path, &metadata()).unwrap();
    let mut sampler = AdaptiveSampler::new(SamplingPolicy::default()).unwrap();
    let mut screen = frame("initial");
    screen.viewport_rows = 3;
    screen.rows.push(pb::TerminalRow {
        index: 1,
        text: "unchanged second row".into(),
        ..Default::default()
    });
    screen.rows.push(pb::TerminalRow {
        index: 2,
        text: "unchanged third row".into(),
        ..Default::default()
    });
    let first = sampler.observe_frame(0, screen.clone()).unwrap().unwrap();
    writer.append_visual(first, &[]).unwrap();
    for index in 1..=400 {
        screen.rows[0].text = format!("command {index}: 雪 ❄");
        if let Some(sample) = sampler.observe_frame(index * 100, screen.clone()).unwrap() {
            writer.append_visual(sample, &[]).unwrap();
        }
        for record in sampler.observe_semantic(event(index * 100)).unwrap() {
            match record {
                SampleRecord::Visual(sample) => writer.append_visual(*sample, &[]).unwrap(),
                SampleRecord::Semantic(event) => writer.append_semantic(&event).unwrap(),
            }
        }
    }
    writer.finish(50_000).unwrap();
    let report = RecordingIndex::rebuild(&path, || false).unwrap();
    assert_eq!(report.completion, RecordingCompletion::Finished);
    assert_eq!(report.summary.visual_count, 401);
    // Four keyframe entries; no full-history index array is required at open.
    assert_eq!(
        fs::metadata(path.join("seek.index")).unwrap().len(),
        104 + 4 * 64
    );
    let mut reader = ContainerReader::open(&path).unwrap();
    let mut sequential = Vec::new();
    while let Some(record) = reader.next_record().unwrap() {
        if let StoredRecord::Visual { sample, .. } = record.record {
            sequential.push((sample.offset_micros, reader.screen().unwrap().clone()));
        }
    }
    let mut index = RecordingIndex::open(&path).unwrap();
    for time in [
        0,
        99,
        100,
        200,
        12_799,
        12_800,
        12_801,
        25_600,
        39_999,
        40_000,
        u64::MAX,
    ] {
        let expected = sequential
            .iter()
            .rev()
            .find(|(offset, _)| *offset <= time)
            .unwrap();
        let actual = index.seek(time, || false).unwrap().unwrap();
        assert_eq!(actual.offset_micros, expected.0);
        assert_eq!(&actual.frame, &expected.1, "seek mismatch at {time}");
    }
    assert!(matches!(
        index.seek(100, || true),
        Err(StorageError::Cancelled)
    ));
}

#[test]
fn cancelled_index_rebuild_preserves_cache_and_stale_or_corrupt_indexes_fail() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("index-integrity.trailrec");
    let mut writer = ContainerWriter::create(&path, &metadata()).unwrap();
    writer.append_visual(sample("first"), &[]).unwrap();
    writer.finish(0).unwrap();
    RecordingIndex::rebuild(&path, || false).unwrap();
    let original_index = fs::read(path.join("seek.index")).unwrap();
    assert!(matches!(
        RecordingIndex::rebuild(&path, || true),
        Err(StorageError::Cancelled)
    ));
    assert_eq!(fs::read(path.join("seek.index")).unwrap(), original_index);
    let mut broken = original_index.clone();
    broken[104] ^= 1;
    fs::write(path.join("seek.index"), &broken).unwrap();
    assert!(
        RecordingIndex::open(&path)
            .unwrap()
            .seek(100, || false)
            .is_err()
    );
    broken = original_index;
    broken[8] ^= 1;
    fs::write(path.join("seek.index"), broken).unwrap();
    assert!(RecordingIndex::open(&path).is_err());
    RecordingIndex::rebuild(&path, || false).unwrap();
    let mut index = RecordingIndex::open(&path).unwrap();
    use std::io::Write;
    fs::OpenOptions::new()
        .append(true)
        .open(path.join("records.bin"))
        .unwrap()
        .write_all(b"bad tail")
        .unwrap();
    assert!(index.seek(0, || false).is_err());
    assert!(RecordingIndex::open(&path).is_err());
    let report = RecordingIndex::rebuild(&path, || false).unwrap();
    assert!(matches!(
        report.completion,
        RecordingCompletion::DamagedTail(_)
    ));
    assert_eq!(
        RecordingIndex::open(&path)
            .unwrap()
            .seek(0, || false)
            .unwrap()
            .unwrap()
            .frame
            .rows[0]
            .text,
        "first"
    );
}

#[test]
fn indexed_seek_on_interrupted_prefix_ignores_an_uncommitted_tail() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("interrupted-index.trailrec");
    let mut writer = ContainerWriter::create(&path, &metadata()).unwrap();
    writer.append_visual(sample("preserved"), &[]).unwrap();
    writer.commit().unwrap();
    drop(writer);
    let report = RecordingIndex::rebuild(&path, || false).unwrap();
    assert_eq!(report.completion, RecordingCompletion::Interrupted);
    assert_eq!(
        RecordingIndex::open(&path)
            .unwrap()
            .seek(u64::MAX, || false)
            .unwrap()
            .unwrap()
            .frame
            .rows[0]
            .text,
        "preserved"
    );
}
