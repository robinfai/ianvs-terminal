use ianvs_core::model::TERMINAL_FRAME_SCHEMA_VERSION;
use ianvs_core::proto::frame_diff as pb;
use ianvs_core::recording::{
    AdaptiveSampler, RecordingError, SampleRecord, SamplingPolicy, ScreenReplay, ScreenState,
    SemanticEvent, SemanticKind, VisualSample,
};
use ianvs_core::{frame_diff_proto, session};
use prost::Message;

fn snapshot(lines: &[&str]) -> pb::TerminalFrameDiff {
    pb::TerminalFrameDiff {
        frame_schema_version: TERMINAL_FRAME_SCHEMA_VERSION.to_owned(),
        frame_kind: pb::TerminalFrameKind::Snapshot as i32,
        viewport_rows: lines.len() as u32,
        viewport_cols: 80,
        cursor: Some(pb::TerminalCursor::default()),
        modes: Some(pb::TerminalFrameModes::default()),
        rows: lines
            .iter()
            .enumerate()
            .map(|(index, text)| pb::TerminalRow {
                index: index as u32,
                text: text.to_string(),
                ..Default::default()
            })
            .collect(),
        ..Default::default()
    }
}

fn delta(index: u32, text: &str) -> pb::TerminalFrameDiff {
    let mut frame = snapshot(&["", "", ""]);
    frame.frame_kind = pb::TerminalFrameKind::Delta as i32;
    frame.rows = vec![pb::TerminalRow {
        index,
        text: text.to_owned(),
        ..Default::default()
    }];
    frame
}

fn sampler() -> AdaptiveSampler {
    AdaptiveSampler::new(SamplingPolicy::default()).unwrap()
}

#[test]
fn unsampled_deltas_are_included_in_the_next_stored_frame() {
    let mut sampler = sampler();
    let first = sampler
        .observe_frame(0, snapshot(&["first", "second", "third"]))
        .unwrap()
        .unwrap();
    assert!(
        sampler
            .observe_frame(1_000, delta(0, "updated first"))
            .unwrap()
            .is_none()
    );
    assert!(
        sampler
            .observe_frame(2_000, delta(2, "updated third"))
            .unwrap()
            .is_none()
    );
    let second = sampler.tick(1_000_000).unwrap().unwrap();
    assert_eq!(second.base_sequence, Some(first.sequence));
    assert_eq!(second.frame.rows.len(), 2);
    let mut restored = ScreenState::default();
    restored.apply(first.frame).unwrap();
    restored.apply(second.frame).unwrap();
    assert_eq!(restored.snapshot(), sampler.current_screen());
    assert_eq!(restored.snapshot().unwrap().rows[1].text, "second");
}

#[test]
fn hyperlink_only_changes_and_removals_survive_storage_deltas() {
    let mut sampler = sampler();
    let mut initial = snapshot(&["link", "plain", ""]);
    initial.hyperlinks.push(pb::TerminalHyperlinkRange {
        row: 0,
        start_col: 0,
        end_col: 4,
        uri: "https://first.example".to_owned(),
        protocol_id: "first".to_owned(),
    });
    let first = sampler.observe_frame(0, initial).unwrap().unwrap();
    let mut changed = delta(0, "link");
    changed.hyperlinks.push(pb::TerminalHyperlinkRange {
        row: 0,
        start_col: 0,
        end_col: 4,
        uri: "https://second.example".to_owned(),
        protocol_id: "second".to_owned(),
    });
    let second = sampler.observe_frame(1_000_000, changed).unwrap().unwrap();
    let third = sampler
        .observe_frame(2_000_000, delta(0, "link"))
        .unwrap()
        .unwrap();
    let mut restored = ScreenState::default();
    restored.apply(first.frame).unwrap();
    restored.apply(second.frame).unwrap();
    assert_eq!(
        restored.snapshot().unwrap().hyperlinks[0].uri,
        "https://second.example"
    );
    restored.apply(third.frame).unwrap();
    assert!(restored.snapshot().unwrap().hyperlinks.is_empty());
    assert_eq!(restored.snapshot(), sampler.current_screen());
}

#[test]
fn semantic_events_bypass_visual_sampling_and_writer_pressure() {
    let mut sampler = sampler();
    sampler.observe_frame(0, snapshot(&["$", "", ""])).unwrap();
    sampler.set_writer_pressure(100);
    for index in 0..100 {
        let event = SemanticEvent {
            offset_micros: index + 1,
            kind: SemanticKind::CommandStarted,
            context_id: "nested-host".to_owned(),
            command_id: Some(index.to_string()),
            command: Some(format!("echo '{index}'")),
            cwd: Some("/srv".to_owned()),
            hostname: Some("server".to_owned()),
            exit_code: None,
        };
        let records = sampler.observe_semantic(event.clone()).unwrap();
        assert_eq!(records.last(), Some(&SampleRecord::Semantic(event)));
        let SampleRecord::Visual(frame) = &records[0] else {
            panic!("boundary frame missing")
        };
        assert_eq!(frame.offset_micros, index + 1);
    }
}

#[test]
fn activity_raises_sampling_frequency_and_pressure_reduces_it() {
    let mut sampler = sampler();
    sampler
        .observe_frame(0, snapshot(&["0", "0", "0"]))
        .unwrap();
    let quiet_interval = sampler.current_interval_micros();
    for index in 1..30 {
        let text = index.to_string();
        sampler
            .observe_frame(index, snapshot(&[&text, &text, &text]))
            .unwrap();
    }
    let active_interval = sampler.current_interval_micros();
    assert!(active_interval < quiet_interval);
    sampler.set_writer_pressure(100);
    assert!(sampler.current_interval_micros() > active_interval);
    for time in 1..100 {
        sampler.tick(time * 1_000_000).unwrap();
    }
    assert!(sampler.current_interval_micros() >= quiet_interval);
}

#[test]
fn idle_time_does_not_create_duplicate_keyframes_and_stop_flushes_pending_changes() {
    let mut sampler = sampler();
    sampler
        .observe_frame(0, snapshot(&["start", "", ""]))
        .unwrap();
    // Logical time proves timestamp range/idle policy, not wall-clock endurance.
    for hour in 1..=25 {
        assert!(sampler.tick(hour * 3_600_000_000).unwrap().is_none());
    }
    sampler
        .observe_frame(25 * 3_600_000_000 + 1, delta(1, "end"))
        .unwrap();
    let stopped = sampler.finish(25 * 3_600_000_000 + 2).unwrap().unwrap();
    let mut state = ScreenState::default();
    state
        .apply(sampler.current_screen().unwrap().clone())
        .unwrap();
    state.apply(stopped.frame).unwrap();
    assert_eq!(state.snapshot(), sampler.current_screen());
}

#[test]
fn geometry_changes_force_keyframes_and_invalid_updates_preserve_state() {
    let mut sampler = sampler();
    sampler
        .observe_frame(0, snapshot(&["a", "b", "c"]))
        .unwrap();
    let resized = sampler
        .observe_frame(1, snapshot(&["a", "b"]))
        .unwrap()
        .unwrap();
    assert_eq!(resized.base_sequence, None);
    let before = sampler.current_screen().unwrap().clone();
    let mut invalid = before.clone();
    invalid.rows[0].index = 100;
    assert!(sampler.observe_frame(2, invalid).is_err());
    assert_eq!(sampler.current_screen(), Some(&before));
    assert_eq!(sampler.tick(0), Err(RecordingError::NonMonotonicTime));
    assert_eq!(sampler.current_screen(), Some(&before));
}

#[test]
fn screen_state_rejects_unbased_deltas_and_incomplete_shift_updates() {
    let mut state = ScreenState::default();
    assert_eq!(
        state.apply(delta(0, "x")),
        Err(RecordingError::MissingSnapshot)
    );
    state.apply(snapshot(&["a", "b", "c"])).unwrap();
    let before = state.snapshot().cloned();
    let mut bad_shift = delta(1, "changed");
    bad_shift.viewport_row_shift = -1;
    assert!(state.apply(bad_shift).is_err());
    assert_eq!(state.snapshot().cloned(), before);
    let mut valid_shift = delta(2, "new");
    valid_shift.viewport_row_shift = -1;
    state.apply(valid_shift).unwrap();
    let text: Vec<_> = state
        .snapshot()
        .unwrap()
        .rows
        .iter()
        .map(|row| row.text.as_str())
        .collect();
    assert_eq!(text, ["b", "c", "new"]);
}

#[test]
fn invalid_semantics_do_not_consume_the_clock_or_emit_a_boundary() {
    let mut sampler = sampler();
    sampler
        .observe_frame(0, snapshot(&["a", "b", "c"]))
        .unwrap();
    let event = SemanticEvent {
        offset_micros: 10_000,
        kind: SemanticKind::CommandStarted,
        context_id: "root".to_owned(),
        command_id: None,
        command: None,
        cwd: None,
        hostname: None,
        exit_code: None,
    };
    assert_eq!(
        sampler.observe_semantic(event),
        Err(RecordingError::InvalidSemanticEvent)
    );
    assert!(sampler.tick(1).is_ok());
}

struct Engine(u64);

impl Engine {
    fn new() -> Self {
        let profile = serde_json::json!({"id":"sampled-recording-test", "name":"sampling",
            "launch":{"program":"/not/a/live/process"}, "terminal":{"scrollbackLines":8000}});
        let id = session::create_replay_session(&profile.to_string()).unwrap();
        session::resize_session(id, 80, 24, 640, 480).unwrap();
        Self(id)
    }
    fn output(&self, bytes: &[u8]) {
        session::replay_session_output(self.0, bytes).unwrap();
    }
    fn frame(&self) -> Option<pb::TerminalFrameDiff> {
        session::take_frame_diff_protobuf(self.0)
            .unwrap()
            .map(|bytes| pb::TerminalFrameDiff::decode(bytes.as_slice()).unwrap())
    }
    fn forced_snapshot(&self) -> pb::TerminalFrameDiff {
        let bytes = session::take_frame_packet_v1_protobuf(self.0, Some(u64::MAX))
            .unwrap()
            .unwrap();
        frame_diff_proto::decode_frame_packet_v1_for_test(&bytes)
            .unwrap()
            .frame
            .unwrap()
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        session::close_session(self.0).unwrap();
    }
}

fn normalized(mut frame: pb::TerminalFrameDiff) -> pb::TerminalFrameDiff {
    frame.frame_kind = pb::TerminalFrameKind::Snapshot as i32;
    frame.viewport_row_shift = 0;
    frame.dirty_ranges.clear();
    for row in &mut frame.rows {
        // Native retained-row indexes are bookkeeping, not rendered pixels.
        row.source_row = None;
        row.source_end_row = None;
        row.modified_at_micros = 0;
    }
    frame
}

fn restore_sample(state: &mut ScreenState, sample: VisualSample, engine: &Engine) {
    state.apply(sample.frame).unwrap();
    assert_eq!(
        normalized(state.snapshot().unwrap().clone()),
        normalized(engine.forced_snapshot())
    );
}

#[test]
fn sampled_shell_and_tui_match_independent_native_snapshots() {
    let source = Engine::new();
    let oracle = Engine::new();
    let mut sampler = sampler();
    let mut replay = ScreenState::default();
    let first = sampler
        .observe_frame(0, source.frame().unwrap())
        .unwrap()
        .unwrap();
    restore_sample(&mut replay, first, &oracle);
    let output = [
        "$ printf hello\r\nhello\r\n",
        "\u{1b}[?1049h\u{1b}[2J",
        "\u{1b}[3;4H\u{1b}[31m你好 e\u{301} 👩‍💻\u{1b}[0m",
        "\u{1b}]8;;https://example.com\u{7}link\u{1b}]8;;\u{7}",
        "\u{1b}]2;updated title\u{7}",
        "\u{1b}[?1049l",
    ];
    for (index, bytes) in output.iter().enumerate() {
        source.output(bytes.as_bytes());
        oracle.output(bytes.as_bytes());
        let time = (index as u64 + 1) * 200_000;
        if let Some(frame) = source.frame()
            && let Some(sample) = sampler.observe_frame(time, frame).unwrap()
        {
            restore_sample(&mut replay, sample, &oracle);
        }
    }
    restore_sample(
        &mut replay,
        sampler.finish(2_000_000).unwrap().unwrap(),
        &oracle,
    );
}

#[test]
fn sampled_scrolling_matches_snapshots_after_eight_thousand_line_eviction() {
    let source = Engine::new();
    let oracle = Engine::new();
    let mut sampler = sampler();
    let mut replay = ScreenState::default();
    restore_sample(
        &mut replay,
        sampler
            .observe_frame(0, source.frame().unwrap())
            .unwrap()
            .unwrap(),
        &oracle,
    );
    for batch in 0..900 {
        let output: String = (0..10)
            .map(|line| format!("line-{:05}\r\n", batch * 10 + line))
            .collect();
        source.output(output.as_bytes());
        oracle.output(output.as_bytes());
        let time = (batch + 1) * 20_000;
        if let Some(frame) = source.frame()
            && let Some(sample) = sampler.observe_frame(time, frame).unwrap()
        {
            restore_sample(&mut replay, sample, &oracle);
        }
    }
    restore_sample(
        &mut replay,
        sampler.finish(20_000_000).unwrap().unwrap(),
        &oracle,
    );
}

#[test]
fn cold_seek_from_keyframes_equals_sequential_replay_and_rejects_missing_bases() {
    let mut sampler = sampler();
    let mut samples = Vec::new();
    samples.push(
        sampler
            .observe_frame(0, snapshot(&["0", "", ""]))
            .unwrap()
            .unwrap(),
    );
    for second in 1..=20 {
        samples.push(
            sampler
                .observe_frame(second * 1_000_000, delta(0, &second.to_string()))
                .unwrap()
                .unwrap(),
        );
    }
    let mut sequential = ScreenReplay::default();
    for sample in &samples {
        sequential.apply(sample.clone()).unwrap();
    }
    for (index, sample) in samples
        .iter()
        .enumerate()
        .filter(|(_, sample)| sample.base_sequence.is_none())
    {
        let mut random = ScreenReplay::default();
        random.seek_keyframe(sample.clone()).unwrap();
        for following in &samples[index + 1..] {
            random.apply(following.clone()).unwrap();
        }
        assert_eq!(random.screen(), sequential.screen());
    }
    let mut ordered = ScreenReplay::default();
    ordered.apply(samples[0].clone()).unwrap();
    let before = ordered.screen().cloned();
    assert_eq!(
        ordered.apply(samples[2].clone()),
        Err(RecordingError::InvalidSequence)
    );
    assert_eq!(ordered.screen().cloned(), before);
    let mut wrong_base = samples[1].clone();
    wrong_base.base_sequence = Some(999);
    assert_eq!(
        ordered.apply(wrong_base),
        Err(RecordingError::InvalidSequence)
    );
    ordered.apply(samples[1].clone()).unwrap();
}

#[test]
fn metadata_styles_and_graphics_versions_survive_sampling_and_removal() {
    let mut sampler = sampler();
    let mut first = snapshot(&["color", "image", ""]);
    first.rows[0].style_runs.push(pb::TerminalStyleRun {
        start: 0,
        end: 5,
        bold: true,
        foreground: Some(pb::ColorRgb {
            present: true,
            rgb: 0x123456,
        }),
        ..Default::default()
    });
    first.graphics.push(pb::TerminalGraphicPlacement {
        render_id: 1,
        placement_id: 2,
        asset_key: Some(pb::TerminalGraphicAssetKey {
            asset_id: 3,
            asset_version: 1,
        }),
        row: 1,
        width_cells: 4,
        height_cells: 1,
        ..Default::default()
    });
    let mut replay = ScreenReplay::default();
    replay
        .apply(sampler.observe_frame(0, first.clone()).unwrap().unwrap())
        .unwrap();
    let mut metadata = first.clone();
    metadata.frame_kind = pb::TerminalFrameKind::Delta as i32;
    metadata.rows.clear();
    metadata.graphics[0]
        .asset_key
        .as_mut()
        .unwrap()
        .asset_version = 2;
    metadata.window_title = "recorded title".to_owned();
    replay
        .apply(
            sampler
                .observe_frame(1_000_000, metadata.clone())
                .unwrap()
                .unwrap(),
        )
        .unwrap();
    assert_eq!(replay.screen(), sampler.current_screen());
    assert_eq!(
        replay.screen().unwrap().rows[0].style_runs,
        first.rows[0].style_runs
    );
    assert_eq!(
        replay.screen().unwrap().graphics[0]
            .asset_key
            .unwrap()
            .asset_version,
        2
    );
    metadata.graphics.clear();
    replay
        .apply(sampler.observe_frame(2_000_000, metadata).unwrap().unwrap())
        .unwrap();
    assert!(replay.screen().unwrap().graphics.is_empty());
}

#[test]
fn oversized_geometry_is_rejected_before_row_allocation() {
    let mut state = ScreenState::default();
    let mut frame = snapshot(&["small"]);
    frame.viewport_rows = 1_048_576;
    frame.viewport_cols = 1;
    assert!(state.apply(frame).is_err());
    assert!(state.snapshot().is_none());
}

#[test]
fn extreme_sampling_intervals_do_not_overflow_or_increase_rate_under_pressure() {
    let mut sampler = AdaptiveSampler::new(SamplingPolicy {
        minimum_interval_micros: 1,
        maximum_interval_micros: u64::MAX,
        keyframe_interval_micros: u64::MAX,
    })
    .unwrap();
    sampler
        .observe_frame(0, snapshot(&["a", "b", "c"]))
        .unwrap();
    let normal = sampler.current_interval_micros();
    sampler.set_writer_pressure(100);
    assert!(sampler.current_interval_micros() >= normal);
}

#[test]
fn equal_damage_at_higher_update_frequency_increases_sampling_frequency() {
    let mut fast = sampler();
    let mut slow = sampler();
    fast.observe_frame(0, snapshot(&["a", "b", "c"])).unwrap();
    slow.observe_frame(0, snapshot(&["a", "b", "c"])).unwrap();
    for index in 1..30 {
        let frame = delta(0, &index.to_string());
        fast.observe_frame(index * 10_000, frame.clone()).unwrap();
        slow.observe_frame(index * 1_000_000, frame).unwrap();
    }
    assert!(fast.current_interval_micros() < slow.current_interval_micros());
}

#[test]
fn full_repaints_use_independent_keyframes_when_a_delta_saves_no_bytes() {
    let mut sampler = sampler();
    sampler
        .observe_frame(0, snapshot(&["a", "b", "c"]))
        .unwrap();
    let repainted = sampler
        .observe_frame(1_000_000, snapshot(&["x", "y", "z"]))
        .unwrap()
        .unwrap();
    assert_eq!(repainted.base_sequence, None);
    let mut replay = ScreenReplay::default();
    replay.seek_keyframe(repainted).unwrap();
    assert_eq!(replay.screen(), sampler.current_screen());
}
