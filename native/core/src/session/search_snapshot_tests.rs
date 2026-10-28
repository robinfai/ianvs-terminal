use super::*;
use crate::model::{
    TerminalProfileAppearance, TerminalProfileInteraction, TerminalProfileLaunch,
    TerminalProfileTerminal, TerminalShellIntegration,
};

fn session_with_screen(cols: usize, rows: usize) -> Arc<TerminalSession> {
    let profile = TerminalProfile {
        id: "search-snapshot".into(),
        name: "Search snapshot".into(),
        launch: TerminalProfileLaunch {
            program: "/bin/sh".into(),
            args: vec![],
            env: Default::default(),
            cwd: None,
        },
        connection: TerminalProfileConnection::default(),
        terminal: TerminalProfileTerminal::default(),
        shell_integration: TerminalShellIntegration {
            enabled: false,
            ..Default::default()
        },
        appearance: TerminalProfileAppearance::default(),
        interaction: TerminalProfileInteraction::default(),
    };
    let session = TerminalSession::spawn_replay(1, profile).unwrap();
    session.state.lock().terminal = Terminal::with_scrollback(cols, rows, 32);
    session
}

fn matches(rows: Vec<TerminalSearchRow>, query: &str) -> Vec<TerminalSearchMatch> {
    let pattern =
        TerminalSearchPattern::new(query, TerminalSearchMode::CaseSensitiveSubstring).unwrap();
    let mut result = Vec::new();
    collect_search_matches(&mut result, rows, &pattern);
    result
}

#[test]
fn search_snapshot_retains_wrapped_unicode_while_other_thread_ingests() {
    let session = session_with_screen(5, 4);
    session.replay_output("ab界cdef".as_bytes()).unwrap();
    let snapshot = session.capture_search_snapshot();

    // A snapshot must not retain the session lock. Check before spawning so a
    // regression fails directly rather than leaving a blocked worker behind.
    assert!(session.state.try_lock().is_some());
    let writer = Arc::clone(&session);
    thread::spawn(move || writer.replay_output(b"\x1b[2J\x1b[Hreplacement").unwrap())
        .join()
        .unwrap();

    let old = matches(snapshot, "界cd");
    assert_eq!(old.len(), 1);
    assert_eq!(old[0].text, "界cd");
    assert_eq!((old[0].row, old[0].start_col, old[0].end_col), (0, 2, 6));
    assert!(
        session
            .search("界cd", TerminalSearchMode::CaseSensitiveSubstring)
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        session
            .search("replacement", TerminalSearchMode::CaseSensitiveSubstring)
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn search_snapshot_keeps_alternate_screen_after_return_to_primary() {
    let session = session_with_screen(20, 4);
    session
        .replay_output(b"primary\x1b[?1049halternate")
        .unwrap();
    let snapshot = session.capture_search_snapshot();
    session.replay_output(b"\x1b[?1049l").unwrap();
    let old = matches(snapshot, "alternate");
    assert_eq!(old.len(), 1);
    assert_eq!(old[0].scrollback_offset, 0);
    assert!(
        session
            .search("alternate", TerminalSearchMode::CaseSensitiveSubstring)
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        session
            .search("primary", TerminalSearchMode::CaseSensitiveSubstring)
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn search_snapshot_preserves_folded_source_rows_and_projected_offsets() {
    let session = session_with_screen(20, 4);
    session.replay_output(b"\x1b]1337;Block=id=fold;attr=start\x07first\r\nsecret\r\nlast\x1b]1337;Block=id=fold;attr=end\x07\x1b]1337;UpdateBlock=id=fold;action=fold\x07").unwrap();
    let snapshot = session.capture_search_snapshot();
    session
        .replay_output(b"\r\nnew\r\nnew\r\nnew\r\nnew\r\nnew")
        .unwrap();
    let old = matches(snapshot, "secret");
    assert_eq!(old.len(), 1);
    assert_eq!(old[0].row, 1);
    assert_eq!(old[0].scrollback_offset, 0);
    let current = session
        .search("secret", TerminalSearchMode::CaseSensitiveSubstring)
        .unwrap();
    assert_eq!(current.len(), 1);
    assert!(current[0].scrollback_offset > old[0].scrollback_offset);
}
