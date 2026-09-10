use ianvs_core::session;
use par_term_emu_core_rust::terminal::Terminal;
use serde_json::Value;
use std::thread;
use std::time::Duration;

const HISTORY: &str = "请把这些字符串拼接起来";

struct Replay(u64);

impl Replay {
    fn new() -> Self {
        let corpus: Value = serde_json::from_str(include_str!(
            "fixtures/session_config/session_config_v1_shape_corpus.json"
        ))
        .unwrap();
        let id = session::create_replay_session_v1(&corpus["valid_local"].to_string()).unwrap();
        session::resize_session(id, 93, 22, 0, 0).unwrap();
        let replay = Self(id);
        replay.feed(b"\x1b[4;1HOLD\x1b[7;1H");
        assert!(replay.frame().is_some());
        replay
    }

    fn feed(&self, bytes: &[u8]) {
        session::replay_session_output(self.0, bytes).unwrap();
    }

    fn frame(&self) -> Option<Value> {
        session::take_frame_diff(self.0)
            .unwrap()
            .map(|json| serde_json::from_str(&json).unwrap())
    }
}

impl Drop for Replay {
    fn drop(&mut self) {
        session::close_session(self.0).unwrap();
    }
}

fn assert_row(frame: &Value, index: usize, expected: &str) {
    let row = frame["rows"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["index"].as_u64() == Some(index as u64))
        .unwrap_or_else(|| panic!("missing changed row {index}: {frame}"));
    assert_eq!(row["text"].as_str().unwrap().trim_end(), expected);
}

#[test]
fn synchronized_unicode_history_emits_input_row_without_another_output() {
    let replay = Replay::new();
    // Like Claude Code, write the input line then park the real cursor below
    // it. Cursor-only damage must not conceal the text row.
    replay.feed(format!("\x1b[?2026h\x1b[4;1H{HISTORY}\x1b[K\x1b[7;1H\x1b[?2026l").as_bytes());
    let frame = replay
        .frame()
        .expect("completed Unicode batch must publish");
    assert_row(&frame, 3, HISTORY);
    assert_eq!(frame["cursor"]["row"], 6);
    assert_eq!(frame["modes"]["synchronized_output"], false);
    assert!(replay.frame().is_none());
}

#[test]
fn synchronized_unicode_preserves_c1_valued_continuations_at_every_split() {
    // These scalars contain each C1 byte recognized by the boundary scanner,
    // including OSC/DCS openers and ST, plus the reported Chinese character.
    let text = "АИЛМНОП来◐🙂";
    let update = format!("{text}\x1b[?2026l");
    for split in 0..=update.len() {
        let mut terminal = Terminal::new(93, 22);
        terminal.process(b"\x1b[?2026h");
        terminal.process(&update.as_bytes()[..split]);
        if split < update.len() {
            assert!(
                terminal.synchronized_updates(),
                "premature flush at {split}"
            );
        }
        terminal.process(&update.as_bytes()[split..]);
        assert!(!terminal.synchronized_updates(), "stuck at split {split}");
        assert_eq!(terminal.active_grid().row_text(0).trim_end(), text);
    }

    let mut terminal = Terminal::new(93, 22);
    for byte in format!("\x1b[?2026h{text}\x1b[?2026l").as_bytes() {
        terminal.process(&[*byte]);
    }
    assert!(!terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), text);
}

#[test]
fn unicode_before_sync_enable_does_not_hide_the_batch_boundary() {
    let mut terminal = Terminal::new(93, 22);
    terminal.process("来\x1b[?2026hhidden".as_bytes());
    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "来");
    terminal.process(b"\x1b[?2026l");
    assert!(!terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "来hidden");
}

#[test]
fn unicode_in_control_strings_does_not_expose_fake_sync_end_or_reset() {
    for fake in [b"\x1b[?2026l".as_slice(), b"\x1bc"] {
        let mut terminal = Terminal::new(93, 22);
        terminal.process(b"before\x1b[?2026hhidden\x1bP");
        // U+041C includes 0x9c, which must not terminate the DCS string.
        terminal.process(&[0xd0]);
        terminal.process(&[0x9c]);
        terminal.process(fake);
        terminal.process(b"\x1b\\");
        assert!(terminal.synchronized_updates());
        assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");
        terminal.process(b"-shown\x1b[?2026l");
        assert!(!terminal.synchronized_updates());
        assert!(terminal.active_grid().row_text(0).contains("-shown"));
    }
}

#[test]
fn unicode_does_not_hide_real_c1_sync_boundaries_or_hard_reset() {
    let mut terminal = Terminal::new(93, 22);
    terminal.process(b"\x9b?2026h");
    terminal.process(HISTORY.as_bytes());
    terminal.process(b"\x9b?2026l");
    assert!(!terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), HISTORY);

    terminal.process("\x1b[?2026h来\x1bcafter".as_bytes());
    assert!(!terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "after");
}

#[test]
fn synchronized_unicode_survives_snapshot_between_input_chunks() {
    let update = format!("{HISTORY}\x1b[?2026l");
    for split in 0..update.len() {
        let mut terminal = Terminal::new(93, 22);
        terminal.process(b"\x1b[?2026h");
        terminal.process(&update.as_bytes()[..split]);
        let mut restored = Terminal::new(1, 1);
        restored.restore_from_snapshot(terminal.capture_snapshot());
        restored.process(&update.as_bytes()[split..]);
        assert!(!restored.synchronized_updates(), "stuck at split {split}");
        assert_eq!(restored.active_grid().row_text(0).trim_end(), HISTORY);
    }
}

#[test]
fn synchronized_timeout_publishes_non_cursor_rows_without_new_output() {
    let replay = Replay::new();
    replay.feed(b"\x1b[?2026h\x1b[4;1Htimeout-history\x1b[K\x1b[7;1H");
    assert!(replay.frame().is_none());
    thread::sleep(Duration::from_millis(1100));
    let frame = replay.frame().expect("timeout must publish changed rows");
    assert_row(&frame, 3, "timeout-history");
    assert_eq!(frame["cursor"]["row"], 6);
    assert_eq!(frame["modes"]["synchronized_output"], false);
    assert!(replay.frame().is_none());
}

#[test]
fn synchronized_timeout_publishes_full_repaint_and_scroll_damage() {
    for update in [
        b"\x1b[?2026h\x1b[2J\x1b[4;1HCLEARED\x1b[7;1H".as_slice(),
        b"\x1b[?2026h\x1b[4;1HCLEARED\x1b[1;22r\x1b[22;1H\n\x1b[7;1H",
    ] {
        let replay = Replay::new();
        replay.feed(update);
        assert!(replay.frame().is_none());
        thread::sleep(Duration::from_millis(1100));
        let frame = replay.frame().expect("timeout must publish screen damage");
        let expected_row = if update.windows(4).any(|part| part == b"\x1b[2J") {
            assert_row(&frame, 0, "");
            3
        } else {
            2
        };
        assert_row(&frame, expected_row, "CLEARED");
        assert!(
            !frame["rows"]
                .as_array()
                .unwrap()
                .iter()
                .any(|row| { row["text"].as_str().unwrap().contains("OLD") })
        );
        assert!(replay.frame().is_none());
    }
}
