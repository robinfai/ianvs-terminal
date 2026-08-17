use super::{
    sanitize_bracketed_paste_content, Terminal, TerminalEvent, MAX_PENDING_TERMINAL_EVENTS,
    MAX_PENDING_TERMINAL_EVENT_BYTES, MAX_PENDING_TMUX_NOTIFICATIONS,
};
use crate::color::Color;
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
fn resize_height_shrink_keeps_inline_graphic_near_cursor_visible() {
    let mut term = Terminal::with_scrollback(80, 24, 100);
    term.set_cell_dimensions(10, 20);
    let mut graphic = TerminalGraphic::new(
        1,
        GraphicProtocol::ITermInline,
        (0, 19),
        100,
        80,
        vec![255; 100 * 80 * 4],
    );
    graphic.set_cell_dimensions(10, 20);
    graphic.set_display_cell_span(10, 4);
    assert!(term.graphics_store.add_graphic(graphic));
    term.process(b"\x1b[24;1H");

    term.resize(80, 10);

    assert_eq!(term.cursor().row, 9);
    assert_eq!(term.all_graphics().len(), 1);
    let graphic = &term.all_graphics()[0];
    assert_eq!(graphic.position.1, 5);
    assert_eq!(graphic.display_cell_span, Some((10, 4)));
    assert_eq!(graphic.scroll_offset_rows, 0);
    assert!(graphic.position.1 + graphic.display_cell_span.unwrap().1 <= 10);
}

#[test]
fn font_cell_height_change_reflows_iterm_rows_without_resizing_pixels() {
    let mut term = Terminal::with_scrollback(80, 24, 100);
    term.set_cell_dimensions(10, 20);
    let mut graphic = TerminalGraphic::new(
        1,
        GraphicProtocol::ITermInline,
        (0, 2),
        100,
        80,
        vec![255; 100 * 80 * 4],
    );
    graphic.set_cell_dimensions(10, 20);
    graphic.set_display_cell_span(10, 4);
    graphic.reserves_rows = true;
    assert!(term.graphics_store.add_graphic(graphic));
    term.process(b"\x1b[7;1HAFTER");
    assert_eq!(term.cursor().row, 6);

    term.set_cell_dimensions(10, 10);

    let graphic = &term.all_graphics()[0];
    assert_eq!(graphic.cell_dimensions, Some((10, 10)));
    assert_eq!(graphic.display_cell_span, Some((10, 8)));
    assert_eq!(term.cursor().row, 10);
    assert_eq!(term.active_grid().row(10).unwrap()[0].get_grapheme(), "A");

    term.set_cell_dimensions(10, 20);
    let graphic = &term.all_graphics()[0];
    assert_eq!(graphic.display_cell_span, Some((10, 4)));
    assert_eq!(term.cursor().row, 6);
    assert_eq!(term.active_grid().row(6).unwrap()[0].get_grapheme(), "A");
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

#[test]
fn enq_answerback_uses_the_atomic_response_budget() {
    const ANSWERBACK: &str = "configured";
    let mut term = Terminal::new(20, 2);
    term.set_answerback_string(Some(ANSWERBACK.to_string()));
    let filler = vec![b'x'; crate::terminal::MAX_RESPONSE_BUFFER_BYTES - ANSWERBACK.len() + 1];
    term.push_response(&filler);
    drop(filler);

    term.process(b"\x05");
    assert_eq!(
        term.response_buffer.len(),
        crate::terminal::MAX_RESPONSE_BUFFER_BYTES - ANSWERBACK.len() + 1
    );
    assert_eq!(term.response_buffer_overflow_count(), 1);
    let buffered = term.drain_responses();
    assert!(buffered.iter().all(|byte| *byte == b'x'));
    drop(buffered);

    term.process(b"\x05");
    assert_eq!(term.drain_responses(), ANSWERBACK.as_bytes());
}

#[test]
fn ris_preserves_host_policy_profile_and_resource_configuration() {
    let mut term = Terminal::new(20, 4);
    term.set_default_fg(Color::Rgb(1, 2, 3));
    term.set_graphics_memory_limits(7, 11);
    term.set_max_sixel_graphics(3);
    term.set_sixel_limits(4, 5, 6);
    term.set_cell_dimensions(7, 9);
    term.set_pixel_size(700, 900);
    term.set_max_transfer_size(1_234);
    term.set_max_inline_images(4);
    term.set_max_clipboard_sync_events(5);
    term.set_max_clipboard_event_bytes(6);
    term.set_max_clipboard_sync_history(7);
    term.set_max_command_history(8);
    term.set_max_cwd_history(9);
    term.set_max_notifications(10);
    term.set_allow_clipboard_read(true);
    term.set_accept_osc7(false);
    term.set_answerback_string(Some("configured".to_string()));
    term.set_width_config(crate::unicode_width_config::WidthConfig::cjk());
    term.set_normalization_form(crate::unicode_normalization_config::NormalizationForm::NFD);
    term.set_remote_session_id(Some("remote-session".to_string()));

    // Mutate protocol-owned semantic state, then reset through RIS.
    term.process(b"\x1b]10;#aabbcc\x07\x1b]1337;SetBadgeFormat=RGVwbG95\x07\x1bc");

    let graphics_limits = term.graphics_store.limits();
    assert_eq!(graphics_limits.max_image_bytes, 7);
    assert_eq!(graphics_limits.max_total_memory, 11);
    assert_eq!(graphics_limits.max_graphics_count, 3);
    assert_eq!(term.sixel_limits().max_width, 4);
    assert_eq!(term.sixel_limits().max_height, 5);
    assert_eq!(term.sixel_limits().max_repeat, 6);
    assert_eq!(term.cell_dimensions(), (7, 9));
    assert_eq!((term.pixel_width, term.pixel_height), (700, 900));
    assert_eq!(term.get_max_transfer_size(), 1_234);
    assert_eq!(term.max_inline_images, 4);
    assert_eq!(term.max_clipboard_sync_events(), 5);
    assert_eq!(term.max_clipboard_event_bytes(), 6);
    assert_eq!(term.max_clipboard_sync_history, 7);
    assert_eq!(term.max_command_history, 8);
    assert_eq!(term.max_cwd_history, 9);
    assert_eq!(term.max_notifications(), 10);
    assert!(term.allow_clipboard_read());
    assert!(!term.accept_osc7());
    assert_eq!(term.answerback_string(), Some("configured"));
    assert_eq!(
        term.width_config(),
        &crate::unicode_width_config::WidthConfig::cjk()
    );
    assert_eq!(
        term.normalization_form(),
        crate::unicode_normalization_config::NormalizationForm::NFD
    );
    assert_eq!(term.remote_session_id(), Some("remote-session"));
    assert_eq!(term.default_fg(), Color::Rgb(1, 2, 3));
    assert!(term.badge_format().is_none());
}

#[test]
fn ris_restores_default_tab_stops_instead_of_session_customization() {
    let mut term = Terminal::new(20, 4);
    term.clear_all_tab_stops();
    term.set_tab_stop(3);
    assert_eq!(term.get_tab_stops(), vec![3]);

    term.process(b"\x1bc");

    assert_eq!(term.get_tab_stops(), vec![0, 8, 16]);
}

#[test]
fn pending_terminal_event_count_is_bounded_without_polling() {
    let mut term = Terminal::new(20, 4);

    for _ in 0..(MAX_PENDING_TERMINAL_EVENTS + 176) {
        term.process(b"\x07");
    }

    let (pending_count, pending_bytes, dropped_count) = term.terminal_event_queue_diagnostics();
    assert_eq!(pending_count, MAX_PENDING_TERMINAL_EVENTS);
    assert!(pending_bytes <= MAX_PENDING_TERMINAL_EVENT_BYTES);
    assert_eq!(dropped_count, 176);
    assert_eq!(term.poll_events().len(), MAX_PENDING_TERMINAL_EVENTS);
    assert_eq!(term.terminal_event_queue_diagnostics(), (0, 0, 176));
}

#[test]
fn pending_terminal_event_payload_bytes_are_bounded_without_logging_content() {
    let mut term = Terminal::new(20, 4);
    let canary = "terminal-event-secret-canary".repeat(40_000);

    for _ in 0..24 {
        term.terminal_events
            .push(TerminalEvent::TitleChanged(canary.clone()));
    }
    term.enforce_terminal_event_queue_limits();

    let (pending_count, pending_bytes, dropped_count) = term.terminal_event_queue_diagnostics();
    assert!(pending_count < 24);
    assert!(pending_bytes <= MAX_PENDING_TERMINAL_EVENT_BYTES);
    assert!(dropped_count > 0);
}

#[test]
fn pending_tmux_notifications_are_bounded_without_a_consumer() {
    let mut term = Terminal::new(20, 4);
    term.set_tmux_control_mode(true);
    let input = "%sessions-changed\n".repeat(MAX_PENDING_TMUX_NOTIFICATIONS + 44);

    term.process(input.as_bytes());

    assert_eq!(
        term.tmux_notification_queue_diagnostics(),
        (MAX_PENDING_TMUX_NOTIFICATIONS, 44)
    );
    assert_eq!(
        term.drain_tmux_notifications().len(),
        MAX_PENDING_TMUX_NOTIFICATIONS
    );
    assert_eq!(term.tmux_notification_queue_diagnostics(), (0, 44));
}
