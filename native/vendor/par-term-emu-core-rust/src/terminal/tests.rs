use super::Terminal;

#[test]
fn resize_drains_full_repaint_damage() {
    let mut term = Terminal::new(8, 4);

    term.resize(12, 6);

    let damage = term.drain_active_screen_damage();
    assert!(damage.full_repaint);
    assert_eq!(damage.snapshot_fallback_reason.as_deref(), Some("resize"));
}

#[test]
fn restore_from_snapshot_drains_full_repaint_damage() {
    let mut term = Terminal::new(8, 4);
    let snapshot = term.capture_snapshot();

    term.process(b"hello");
    let _ = term.drain_active_screen_damage();
    term.restore_from_snapshot(snapshot);

    let damage = term.drain_active_screen_damage();
    assert!(damage.full_repaint);
    assert_eq!(
        damage.snapshot_fallback_reason.as_deref(),
        Some("restore_from_snapshot")
    );
}

#[test]
fn alternate_screen_switches_drain_full_repaint_damage() {
    let mut term = Terminal::new(8, 4);

    term.use_alt_screen();
    let entered = term.drain_active_screen_damage();
    assert!(entered.full_repaint);
    assert_eq!(
        entered.snapshot_fallback_reason.as_deref(),
        Some("alternate_screen_switch")
    );

    term.use_primary_screen();
    let exited = term.drain_active_screen_damage();
    assert!(exited.full_repaint);
    assert_eq!(
        exited.snapshot_fallback_reason.as_deref(),
        Some("alternate_screen_switch")
    );
}

#[test]
fn process_debug_stats_track_plain_text_and_scroll_costs() {
    let mut term = Terminal::with_scrollback(8, 2, 16);

    term.process(b"line-001\nline-002\nline-003\n");
    let stats = term.take_process_debug_stats();

    assert_eq!(stats.process_calls, 1);
    assert_eq!(stats.process_bytes, 27);
    assert_eq!(stats.plain_ascii_bytes, 24);
    assert_eq!(stats.escape_or_control_bytes, 3);
    assert_eq!(stats.print_calls, 24);
    assert_eq!(stats.execute_calls, 3);
    assert_eq!(stats.newline_calls, 3);
    assert!(stats.scroll_region_up_calls > 0);
    assert!(stats.scroll_rows > 0);
    assert!(stats.scrollback_push_lines > 0);
    assert_eq!(stats.plain_ascii_fast_path_calls, 1);
    assert!(stats.plain_ascii_fast_path_micros > 0);
    assert!(stats.scroll_micros > 0);
}

#[test]
fn process_debug_stats_track_escape_or_control_bytes() {
    let mut term = Terminal::new(8, 2);

    term.process(b"abc\x1b[31mdef\x1b[0m");
    let stats = term.take_process_debug_stats();

    assert_eq!(stats.process_calls, 1);
    assert_eq!(stats.print_calls, 6);
    assert_eq!(stats.escape_or_control_bytes, 2);
    assert!(stats.plain_ascii_bytes < stats.process_bytes);
}

#[test]
fn plain_ascii_fast_path_handles_safe_chunks() {
    let mut term = Terminal::with_scrollback(8, 2, 16);

    term.process(b"abc\r\nxyz");
    let stats = term.take_process_debug_stats();

    assert_eq!(stats.plain_ascii_fast_path_calls, 1);
    assert_eq!(stats.plain_ascii_fast_path_bytes, 8);
    assert_eq!(stats.print_calls, 6);
    assert_eq!(stats.execute_calls, 2);
    assert_eq!(term.active_grid().row_text(0).trim_end(), "abc");
    assert_eq!(term.active_grid().row_text(1).trim_end(), "xyz");
}

#[test]
fn plain_ascii_fast_path_does_not_consume_split_osc_payload() {
    let mut term = Terminal::new(20, 2);

    term.process(b"\x1b]2;hel");
    term.process(b"lo\x07visible");
    let stats = term.take_process_debug_stats();

    assert_eq!(term.title(), "hello");
    assert_eq!(term.active_grid().row_text(0).trim_end(), "visible");
    assert_eq!(stats.plain_ascii_fast_path_calls, 0);
}
