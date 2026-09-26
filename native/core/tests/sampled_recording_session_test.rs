use ianvs_core::proto::frame_diff::TerminalFrameDiff;
use ianvs_core::recording::{
    ContainerReader, RecordingCompletion, RecordingIndex, RecordingMetadata, SemanticKind,
    StoredRecord, WriterPhase,
};
use ianvs_core::session;
use prost::Message;
use serde_json::json;
use std::path::Path;
use std::time::{Duration, Instant};

struct Engine(u64);
impl Engine {
    fn replay() -> Self {
        let profile = json!({"id":"recording-test","name":"recording","launch":{"program":"/not/executed"},"terminal":{"scrollbackLines":8000}});
        let engine = Self(session::create_replay_session(&profile.to_string()).unwrap());
        session::resize_session(engine.0, 80, 24, 640, 480).unwrap();
        engine
    }
    fn output(&self, bytes: &[u8]) {
        session::replay_session_output(self.0, bytes).unwrap();
    }
    fn start(&self, path: &Path) {
        session::start_sampled_recording(
            self.0,
            path,
            &RecordingMetadata {
                recording_id: "native-capture".into(),
                started_at_unix_millis: 42,
                title: "capture".into(),
                hostname: Some("host".into()),
            },
        )
        .unwrap();
    }
    fn finish(&self) {
        session::stop_sampled_recording(self.0).unwrap();
        wait_until(|| {
            let status = session::sampled_recording_status(self.0).unwrap().unwrap();
            assert_ne!(status.phase, WriterPhase::Failed, "{status:?}");
            status.phase == WriterPhase::Finished
        });
    }
}
impl Drop for Engine {
    fn drop(&mut self) {
        let _ = session::close_session(self.0);
    }
}
fn wait_until(mut predicate: impl FnMut() -> bool) {
    let started = Instant::now();
    while !predicate() {
        assert!(
            started.elapsed() < Duration::from_secs(8),
            "recording condition timed out"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn hidden_session_keeps_recording_without_consuming_ui_damage() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("hidden.trailrec");
    let engine = Engine::replay();
    engine.output("existing 界面\r\n".as_bytes());
    session::take_frame_diff_protobuf(engine.0)
        .unwrap()
        .unwrap();
    engine.start(&path);
    assert!(
        session::take_frame_diff_protobuf(engine.0)
            .unwrap()
            .is_none(),
        "starting capture dirtied the UI"
    );
    wait_until(|| {
        session::sampled_recording_status(engine.0)
            .unwrap()
            .unwrap()
            .written
            .visual_count
            >= 3
    });
    let before = session::sampled_recording_status(engine.0)
        .unwrap()
        .unwrap()
        .written
        .visual_count;
    engine.output(b"unpolled background output");
    wait_until(|| {
        session::sampled_recording_status(engine.0)
            .unwrap()
            .unwrap()
            .written
            .visual_count
            > before
    });
    let bytes = session::take_frame_diff_protobuf(engine.0)
        .unwrap()
        .expect("recorder consumed UI damage");
    let frame = TerminalFrameDiff::decode(bytes.as_slice()).unwrap();
    assert!(
        frame
            .rows
            .iter()
            .any(|row| row.text.contains("unpolled background output"))
    );
    engine.finish();
    RecordingIndex::rebuild(&path, || false).unwrap();
    let mut index = RecordingIndex::open(&path).unwrap();
    assert!(
        index
            .seek(0, || false)
            .unwrap()
            .unwrap()
            .frame
            .rows
            .iter()
            .any(|row| row.text.contains("existing 界面"))
    );
    assert!(
        index
            .seek(u64::MAX, || false)
            .unwrap()
            .unwrap()
            .frame
            .rows
            .iter()
            .any(|row| row.text.contains("unpolled background output"))
    );
}

#[test]
fn native_capture_preserves_pixels_after_graphics_are_removed_and_session_closes() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("graphics.trailrec");
    let engine = Engine::replay();
    engine.output(b"\x1b_Ga=T,f=32,s=1,v=1,i=7;/wAA/w==\x1b\\");
    engine.start(&path);
    engine.output(b"\x1b_Ga=d,d=A;\x1b\\");
    engine.finish();
    drop(engine);
    let mut reader = ContainerReader::open(&path).unwrap();
    let StoredRecord::Visual { assets, sample } = reader.next_record().unwrap().unwrap().record
    else {
        panic!()
    };
    assert_eq!(sample.frame.graphics.len(), 1);
    assert_eq!(assets.len(), 1);
    assert_eq!(
        reader.load_asset(&assets[0]).unwrap().rgba,
        [255, 0, 0, 255]
    );
    let mut last_graphics = usize::MAX;
    while let Some(record) = reader.next_record().unwrap() {
        if let StoredRecord::Visual { sample, .. } = record.record {
            last_graphics = sample.frame.graphics.len();
        }
    }
    assert_eq!(last_graphics, 0);
}

#[test]
fn closing_session_finishes_recording_without_frontend_polling() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("closed.trailrec");
    let engine = Engine::replay();
    engine.start(&path);
    engine.output(b"last output before close");
    drop(engine);
    wait_until(|| {
        ContainerReader::open(&path)
            .unwrap()
            .scan(|| false, |_| Ok(()))
            .unwrap()
            .completion
            == RecordingCompletion::Finished
    });
    let mut reader = ContainerReader::open(&path).unwrap();
    while reader.next_record().unwrap().is_some() {}
    assert!(
        reader
            .screen()
            .unwrap()
            .rows
            .iter()
            .any(|row| row.text.contains("last output before close"))
    );
}

#[test]
fn real_pty_hook_bytes_reach_timeline_without_ui_event_polling() {
    fn hex(value: serde_json::Value) -> String {
        value
            .to_string()
            .bytes()
            .map(|byte| format!("{byte:02x}"))
            .collect()
    }
    let command = format!("printf '%s' '{}'", "argument-雪".repeat(200));
    let started = hex(json!({"hook":"preexec","command":command,"context_id":"root"}));
    let finished =
        hex(json!({"hook":"command_finished","command":command,"context_id":"root","exit_code":7}));
    // Controlled synthetic hooks emitted through a real PTY/parser. Installed
    // interactive-shell and SSH coverage are separate acceptance tests.
    let script = format!(
        "read gate; printf '\\033Phook;{started}\\033\\\\'; printf 'native captured output'; printf '\\033Phook;{finished}\\033\\\\'; read finish_gate"
    );
    let profile = json!({"id":"hook-pty","name":"hook-pty","launch":{"program":"/bin/sh","args":["-c",script]}});
    let engine = Engine(session::create_session(&profile.to_string()).unwrap());
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("pty.trailrec");
    engine.start(&path);
    session::write_session(engine.0, b"go\n").unwrap();
    wait_until(|| {
        let status = session::sampled_recording_status(engine.0)
            .unwrap()
            .unwrap();
        assert_ne!(status.phase, WriterPhase::Failed, "{status:?}");
        status.written.semantic_count >= 5
    });
    engine.finish();
    let mut starts = Vec::new();
    let mut finishes = Vec::new();
    ContainerReader::open(&path)
        .unwrap()
        .scan(
            || false,
            |record| {
                if let StoredRecord::Semantic(event) = &record.record {
                    if event.kind == SemanticKind::CommandStarted {
                        starts.push(event.clone());
                    }
                    if event.kind == SemanticKind::CommandFinished {
                        finishes.push(event.clone());
                    }
                }
                Ok(())
            },
        )
        .unwrap();
    assert_eq!(starts.len(), 1);
    assert_eq!(finishes.len(), 1);
    assert_eq!(starts[0].command.as_deref(), Some(command.as_str()));
    assert_eq!(starts[0].command_id, finishes[0].command_id);
    assert_eq!(finishes[0].exit_code, Some(7));
}

#[test]
fn capture_started_mid_command_keeps_remote_identity_and_finishes_on_child_exit() {
    fn wire(value: serde_json::Value) -> String {
        let hex: String = value
            .to_string()
            .bytes()
            .map(|byte| format!("{byte:02x}"))
            .collect();
        format!("printf '\\033Phook;{hex}\\033\\\\'; ")
    }
    let script = wire(
        json!({"hook":"bootstrap.ready","context_id":"remote-before-start","host":"database-server","registered":true}),
    ) + &wire(
        json!({"hook":"precmd.pwd","context_id":"remote-before-start","pwd":"/srv/database"}),
    ) + &wire(
        json!({"hook":"preexec","context_id":"remote-before-start","command":"long-running task"}),
    ) + "printf 'ready-before-capture\\n'; read gate; "
        + &wire(
            json!({"hook":"command_finished","context_id":"remote-before-start","command":"long-running task","exit_code":0}),
        )
        + "printf 'final child output\\n'; exit 0";
    let profile = json!({"id":"mid-command","name":"mid-command","launch":{"program":"/bin/sh","args":["-c",script]}});
    let engine = Engine(session::create_session(&profile.to_string()).unwrap());
    // Establish the context before recording; no frontend polling occurs after start.
    wait_until(|| {
        session::poll_events(engine.0)
            .unwrap()
            .contains("long-running task")
    });
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("mid-command.trailrec");
    engine.start(&path);
    session::write_session(engine.0, b"go\n").unwrap();
    wait_until(|| {
        let status = session::sampled_recording_status(engine.0)
            .unwrap()
            .unwrap();
        assert_ne!(status.phase, WriterPhase::Failed, "{status:?}");
        status.phase == WriterPhase::Finished
    });
    let mut finish = None;
    let mut starts = 0;
    let report = ContainerReader::open(&path)
        .unwrap()
        .scan(
            || false,
            |record| {
                if let StoredRecord::Semantic(event) = &record.record {
                    if event.kind == SemanticKind::CommandFinished {
                        finish = Some(event.clone());
                    }
                    if event.kind == SemanticKind::CommandStarted {
                        starts += 1;
                    }
                }
                Ok(())
            },
        )
        .unwrap();
    assert_eq!(report.completion, RecordingCompletion::Finished);
    assert_eq!(
        starts, 0,
        "must not fabricate a start time before recording began"
    );
    let finish = finish.unwrap();
    assert_eq!(finish.hostname.as_deref(), Some("database-server"));
    assert_eq!(finish.cwd.as_deref(), Some("/srv/database"));
    RecordingIndex::rebuild(&path, || false).unwrap();
    assert!(
        RecordingIndex::open(&path)
            .unwrap()
            .seek(u64::MAX, || false)
            .unwrap()
            .unwrap()
            .frame
            .rows
            .iter()
            .any(|row| row.text.contains("final child output"))
    );
}
