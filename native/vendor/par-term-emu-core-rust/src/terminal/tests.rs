use super::{sanitize_bracketed_paste_content, Terminal};
use crate::graphics::{GraphicProtocol, TerminalGraphic};

#[test]
fn sanitize_bracketed_paste_content_removes_embedded_markers() {
    let content = "safe\x1b[201~echo unsafe\x1b[200~tail\u{009B}0200~end\u{009B}0201~";

    assert_eq!(
        sanitize_bracketed_paste_content(content),
        "safeecho unsafetailend"
    );
}

#[test]
fn sanitize_bracketed_paste_content_preserves_non_marker_csi_and_unicode() {
    let content = "UTF-8 🌟 keep\x1b[1;201~literal\u{009B}202~";

    assert_eq!(
        sanitize_bracketed_paste_content(content),
        "UTF-8 🌟 keep\x1b[1;201~literal\u{009B}202~"
    );
}

#[test]
fn paste_input_bytes_wraps_sanitized_bracketed_paste_content() {
    let mut term = Terminal::new(8, 4);
    term.set_bracketed_paste(true);

    let bytes = term.paste_input_bytes("safe\x1b[201~echo\x1b[200~tail");

    assert_eq!(
        String::from_utf8(bytes).unwrap(),
        "\x1b[200~safeechotail\x1b[201~"
    );
}

#[test]
fn paste_input_bytes_treats_marker_only_bracketed_paste_as_noop() {
    let mut term = Terminal::new(8, 4);
    term.set_bracketed_paste(true);

    let bytes = term.paste_input_bytes("\x1b[200~\x1b[201~\u{009B}200~\u{009B}201~");

    assert!(bytes.is_empty());
}

#[test]
fn paste_input_bytes_preserves_content_when_bracketed_paste_is_disabled() {
    let term = Terminal::new(8, 4);
    let content = "safe\x1b[201~echo";

    assert_eq!(term.paste_input_bytes(content), content.as_bytes());
}

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

fn screenshot_test_graphic(row: usize, height_rows: usize) -> TerminalGraphic {
    let height_rows = height_rows.max(1);
    let mut graphic = TerminalGraphic::new(
        1,
        GraphicProtocol::Sixel,
        (0, row),
        1,
        height_rows,
        vec![255; height_rows * 4],
    );
    graphic.set_cell_dimensions(1, 1);
    graphic.set_display_cell_span(1, height_rows);
    graphic
}

#[test]
fn screenshot_view_keeps_active_graphic_scroll_crop() {
    let mut term = Terminal::new(4, 4);
    let mut graphic = screenshot_test_graphic(0, 3);
    graphic.scroll_offset_rows = 1;
    assert!(term.graphics_store.add_graphic(graphic));

    let graphics = term.graphics_for_screenshot_view(0);

    assert_eq!(graphics.len(), 1);
    assert_eq!(graphics[0].position, (0, 0));
    assert_eq!(
        graphics[0].scroll_offset_rows, 1,
        "screenshot rendering must preserve active graphic top crop"
    );
}

#[test]
fn screenshot_view_includes_scrollback_graphics_at_requested_offset() {
    let mut term = Terminal::with_scrollback(4, 2, 16);
    term.process(b"one\ntwo\nthree\n");
    let scrollback_len = term.active_grid().scrollback_len();
    assert!(
        scrollback_len > 0,
        "test setup should create text scrollback"
    );

    assert!(term
        .graphics_store
        .add_graphic(screenshot_test_graphic(0, 1)));
    term.graphics_store.adjust_for_scroll_up_with_scrollback(
        1,
        0,
        1,
        scrollback_len.saturating_sub(1),
    );
    assert_eq!(term.graphics_store.scrollback_count(), 1);

    let graphics = term.graphics_for_screenshot_view(1);

    assert_eq!(graphics.len(), 1);
    assert_eq!(graphics[0].position, (0, 0));
    assert_eq!(graphics[0].scroll_offset_rows, 0);
    assert_eq!(
        graphics[0].scrollback_row, None,
        "screenshot renderer receives viewport-relative graphics"
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
