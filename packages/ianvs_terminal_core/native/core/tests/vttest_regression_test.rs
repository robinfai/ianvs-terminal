use par_term_emu_core_rust::terminal::Terminal;

fn visible_row(term: &Terminal, row: usize) -> String {
    term.active_grid().row_text(row).trim_end().to_string()
}

fn response_text(term: &mut Terminal) -> String {
    String::from_utf8(term.drain_responses()).expect("terminal response should be utf8")
}

#[test]
fn vttest_screen_features_repaint_consecutive_full_width_autowrapped_rows() {
    let mut term = Terminal::new(5, 4);

    term.process(b"\x1b[2J\x1b[H*****\r\n***\r\n*****");
    assert_eq!(visible_row(&term, 0), "*****");
    assert_eq!(visible_row(&term, 1), "***");
    assert_eq!(visible_row(&term, 2), "*****");

    term.process(b"\x1b[H***************");

    assert_eq!(visible_row(&term, 0), "*****");
    assert_eq!(visible_row(&term, 1), "*****");
    assert_eq!(visible_row(&term, 2), "*****");
    assert!(term.active_grid().is_line_wrapped(0));
    assert!(term.active_grid().is_line_wrapped(1));
    assert!(!term.active_grid().is_line_wrapped(2));
}

#[test]
fn vttest_screen_features_deca_wm_toggle_controls_last_column_wrap() {
    let mut term = Terminal::new(5, 3);

    term.process(b"\x1b[?7l\x1b[HABCDEZ");
    assert_eq!(visible_row(&term, 0), "ABCDZ");
    assert_eq!(visible_row(&term, 1), "");
    assert!(!term.active_grid().is_line_wrapped(0));

    term.process(b"\x1b[2J\x1b[H\x1b[?7hABCDEZ");
    assert_eq!(visible_row(&term, 0), "ABCDE");
    assert_eq!(visible_row(&term, 1), "Z");
    assert!(term.active_grid().is_line_wrapped(0));
}

#[test]
fn vttest_terminal_reports_are_machine_checkable() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b[5n");
    assert_eq!(response_text(&mut term), "\x1b[0n");

    term.process(b"\x1b[3;4H\x1b[6n");
    assert_eq!(response_text(&mut term), "\x1b[3;4R");
}
