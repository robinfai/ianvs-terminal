use crate::color::{Color, NamedColor};
use crate::cursor::CursorStyle;
use crate::mouse::{MouseEncoding, MouseMode};
use crate::terminal::{Terminal, TerminalEvent};

fn emit_test_sixel_graphic(term: &mut Terminal) {
    term.process(b"\x1bPq????\x1b\\");
}

// ========== Cursor Movement Tests ==========

#[test]
fn test_cursor_up() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[10;10H"); // Move to (10,10)

    term.process(b"\x1b[5A"); // Move up 5
    assert_eq!(term.cursor.row, 4); // 10-1-5 = 4 (0-indexed)

    term.process(b"\x1b[A"); // Default (1)
    assert_eq!(term.cursor.row, 3);

    term.process(b"\x1b[0A"); // 0 treated as 1
    assert_eq!(term.cursor.row, 2);
}

#[test]
fn test_cursor_down() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[5;10H"); // Move to (10,5)

    term.process(b"\x1b[3B"); // Move down 3
    assert_eq!(term.cursor.row, 7); // 5-1+3 = 7 (0-indexed)

    // Test bounds
    term.process(b"\x1b[100B");
    assert_eq!(term.cursor.row, 23); // Last row (0-indexed)
}

#[test]
fn test_cursor_forward() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[10;10H");

    term.process(b"\x1b[5C"); // Move right 5
    assert_eq!(term.cursor.col, 14); // 10-1+5 = 14 (0-indexed)

    // Test bounds
    term.process(b"\x1b[100C");
    assert_eq!(term.cursor.col, 79); // Last column
}

#[test]
fn test_cursor_back() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[10;20H");

    term.process(b"\x1b[10D"); // Move left 10
    assert_eq!(term.cursor.col, 9); // 20-1-10 = 9 (0-indexed)

    // Test bounds
    term.process(b"\x1b[100D");
    assert_eq!(term.cursor.col, 0); // First column
}

#[test]
fn test_cursor_position() {
    let mut term = Terminal::new(80, 24);

    // CUP - Cursor Position (1-indexed)
    term.process(b"\x1b[10;20H");
    assert_eq!(term.cursor.row, 9); // 0-indexed
    assert_eq!(term.cursor.col, 19);

    // Default position (1,1)
    term.process(b"\x1b[H");
    assert_eq!(term.cursor.row, 0);
    assert_eq!(term.cursor.col, 0);

    // HVP (same as CUP)
    term.process(b"\x1b[5;10f");
    assert_eq!(term.cursor.row, 4);
    assert_eq!(term.cursor.col, 9);
}

#[test]
fn test_cursor_horizontal_absolute() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[10;10H");

    // CHA - Move to column 30 (1-indexed)
    term.process(b"\x1b[30G");
    assert_eq!(term.cursor.col, 29); // 0-indexed
    assert_eq!(term.cursor.row, 9); // Row unchanged
}

#[test]
fn test_cursor_vertical_absolute() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[10;10H");

    // VPA - Move to row 15 (1-indexed)
    term.process(b"\x1b[15d");
    assert_eq!(term.cursor.row, 14); // 0-indexed
    assert_eq!(term.cursor.col, 9); // Column unchanged
}

#[test]
fn test_cursor_next_prev_line() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[10;20H");

    // CNL - Cursor next line (move down and to column 0)
    term.process(b"\x1b[3E");
    assert_eq!(term.cursor.row, 12); // 10-1+3 = 12
    assert_eq!(term.cursor.col, 0);

    // CPL - Cursor previous line (move up and to column 0)
    term.process(b"\x1b[5F");
    assert_eq!(term.cursor.row, 7); // 12-5 = 7
    assert_eq!(term.cursor.col, 0);
}

// ========== SGR Attribute Tests ==========

#[test]
fn test_sgr_reset() {
    let mut term = Terminal::new(80, 24);

    // Set some attributes
    term.process(b"\x1b[1;31;42m"); // Bold, red fg, green bg

    // Reset all
    term.process(b"\x1b[0m");
    assert!(!term.flags.bold());
}

#[test]
fn test_sgr_bold_dim_italic() {
    let mut term = Terminal::new(80, 24);

    // Bold
    term.process(b"\x1b[1m");
    assert!(term.flags.bold());

    // Dim
    term.process(b"\x1b[2m");
    assert!(term.flags.dim());

    // Italic
    term.process(b"\x1b[3m");
    assert!(term.flags.italic());

    // Reset bold/dim
    term.process(b"\x1b[22m");
    assert!(!term.flags.bold());
    assert!(!term.flags.dim());

    // Reset italic
    term.process(b"\x1b[23m");
    assert!(!term.flags.italic());
}

#[test]
fn test_sgr_underline() {
    let mut term = Terminal::new(80, 24);

    // Underline
    term.process(b"\x1b[4m");
    assert!(term.flags.underline());

    // No underline
    term.process(b"\x1b[24m");
    assert!(!term.flags.underline());
}

#[test]
fn test_sgr_other_attributes() {
    let mut term = Terminal::new(80, 24);

    // Blink
    term.process(b"\x1b[5m");
    assert!(term.flags.blink());
    term.process(b"\x1b[25m");
    assert!(!term.flags.blink());

    // Reverse
    term.process(b"\x1b[7m");
    assert!(term.flags.reverse());
    term.process(b"\x1b[27m");
    assert!(!term.flags.reverse());

    // Hidden
    term.process(b"\x1b[8m");
    assert!(term.flags.hidden());
    term.process(b"\x1b[28m");
    assert!(!term.flags.hidden());

    // Strikethrough
    term.process(b"\x1b[9m");
    assert!(term.flags.strikethrough());
    term.process(b"\x1b[29m");
    assert!(!term.flags.strikethrough());
}

#[test]
fn test_sgr_basic_colors() {
    let mut term = Terminal::new(80, 24);

    // Foreground colors (30-37)
    term.process(b"\x1b[31m"); // Red
    assert_eq!(term.fg, Color::Named(NamedColor::Red));

    term.process(b"\x1b[34m"); // Blue
    assert_eq!(term.fg, Color::Named(NamedColor::Blue));

    // Background colors (40-47)
    term.process(b"\x1b[42m"); // Green
    assert_eq!(term.bg, Color::Named(NamedColor::Green));

    // Bright colors (90-97)
    term.process(b"\x1b[91m"); // Bright red
    assert_eq!(term.fg, Color::Named(NamedColor::BrightRed));

    // Reset to defaults
    term.process(b"\x1b[39m");
    assert_eq!(term.fg, term.default_fg);
    term.process(b"\x1b[49m");
    assert_eq!(term.bg, term.default_bg);
}

#[test]
fn test_sgr_rgb_colors() {
    let mut term = Terminal::new(80, 24);

    // Foreground RGB (38;2;r;g;b)
    term.process(b"\x1b[38;2;255;128;64m");
    assert_eq!(term.fg, Color::Rgb(255, 128, 64));

    // Background RGB (48;2;r;g;b)
    term.process(b"\x1b[48;2;10;20;30m");
    assert_eq!(term.bg, Color::Rgb(10, 20, 30));
}

#[test]
fn test_sgr_256_colors() {
    let mut term = Terminal::new(80, 24);

    // Foreground 256 color (38;5;idx)
    term.process(b"\x1b[38;5;123m");
    assert_eq!(term.fg, Color::from_ansi_code(123));

    // Background 256 color (48;5;idx)
    term.process(b"\x1b[48;5;200m");
    assert_eq!(term.bg, Color::from_ansi_code(200));
}

#[test]
fn test_el_uses_current_background_color() {
    let mut term = Terminal::new(10, 1);

    term.process(b"\x1b[48;2;30;30;30mabc\x1b[K");

    for col in 3..10 {
        let cell = term.active_grid().get(col, 0).expect("expected cell");
        assert_eq!(cell.c, ' ');
        assert_eq!(cell.bg, Color::Rgb(30, 30, 30));
    }
}

#[test]
fn test_el_removes_intersecting_graphics() {
    let mut term = Terminal::new(12, 10);

    term.process(b"\x1b[2;2H");
    emit_test_sixel_graphic(&mut term);
    term.process(b"\x1b[6;2H");
    emit_test_sixel_graphic(&mut term);
    assert_eq!(term.graphics_count(), 2);

    term.process(b"\x1b[2;3H\x1b[K");

    assert_eq!(term.graphics_count(), 1);
    assert_eq!(
        term.all_graphics()[0].position.1,
        5,
        "EL should remove the graphic intersecting the erased row without touching another row"
    );
}

#[test]
fn test_ed0_removes_graphics_below_cursor_only() {
    let mut term = Terminal::new(12, 10);

    term.process(b"\x1b[2;2H");
    emit_test_sixel_graphic(&mut term);
    term.process(b"\x1b[6;2H");
    emit_test_sixel_graphic(&mut term);
    assert_eq!(term.graphics_count(), 2);

    term.process(b"\x1b[5;1H\x1b[J");

    assert_eq!(term.graphics_count(), 1);
    assert_eq!(
        term.all_graphics()[0].position.1,
        1,
        "ED 0 should keep graphics entirely above the cursor"
    );
}

#[test]
fn test_ech_removes_graphics_only_when_erased_cells_intersect() {
    let mut term = Terminal::new(12, 10);

    term.process(b"\x1b[3;4H");
    emit_test_sixel_graphic(&mut term);
    assert_eq!(term.graphics_count(), 1);

    term.process(b"\x1b[3;1H\x1b[2X");
    assert_eq!(
        term.graphics_count(),
        1,
        "ECH should keep graphics outside the erased cell range"
    );

    term.process(b"\x1b[3;3H\x1b[2X");
    assert_eq!(
        term.graphics_count(),
        0,
        "ECH should remove graphics intersecting the erased cell range"
    );
}

// ========== Mode Tests ==========

#[test]
fn test_private_mode_cursor_visibility() {
    let mut term = Terminal::new(80, 24);

    // Show cursor
    term.process(b"\x1b[?25h");
    assert!(term.cursor.visible);

    // Hide cursor
    term.process(b"\x1b[?25l");
    assert!(!term.cursor.visible);
}

#[test]
fn test_private_mode_application_cursor() {
    let mut term = Terminal::new(80, 24);

    // Enable application cursor
    term.process(b"\x1b[?1h");
    assert!(term.application_cursor);

    // Disable
    term.process(b"\x1b[?1l");
    assert!(!term.application_cursor);
}

#[test]
fn test_private_mode_autowrap() {
    let mut term = Terminal::new(80, 24);

    // Disable autowrap
    term.process(b"\x1b[?7l");
    assert!(!term.auto_wrap);

    // Enable autowrap
    term.process(b"\x1b[?7h");
    assert!(term.auto_wrap);
}

#[test]
fn test_private_mode_alt_screen() {
    let mut term = Terminal::new(80, 24);

    // Switch to alternate screen
    term.process(b"\x1b[?1049h");
    assert!(term.alt_screen_active);

    // Switch back to primary
    term.process(b"\x1b[?1049l");
    assert!(!term.alt_screen_active);
}

#[test]
fn test_private_mode_alt_screen_47_and_1047() {
    for (enter, exit) in [
        (b"\x1b[?47h".as_slice(), b"\x1b[?47l".as_slice()),
        (b"\x1b[?1047h".as_slice(), b"\x1b[?1047l".as_slice()),
    ] {
        let mut term = Terminal::new(80, 24);
        term.process(b"PRIMARY");
        assert_eq!(term.active_grid().row_text(0).trim_end(), "PRIMARY");

        term.process(enter);
        assert!(term.alt_screen_active);
        assert_eq!(term.active_grid().row_text(0).trim_end(), "");

        term.process(b"ALT");
        assert_eq!(term.active_grid().row_text(0).trim_end(), "ALT");

        term.process(exit);
        assert!(!term.alt_screen_active);
        assert_eq!(term.active_grid().row_text(0).trim_end(), "PRIMARY");
    }
}

#[test]
fn test_private_mode_1048_saves_and_restores_cursor() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b[3;5H\x1b[1m\x1b[?1048h");
    term.process(b"\x1b[10;20H\x1b[22m");
    assert_eq!(term.cursor.row, 9);
    assert_eq!(term.cursor.col, 19);
    assert!(!term.flags.bold());

    term.process(b"\x1b[?1048l");
    assert_eq!(term.cursor.row, 2);
    assert_eq!(term.cursor.col, 4);
    assert!(term.flags.bold());
}

#[test]
fn test_private_mode_1049_restores_saved_cursor_attributes() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b[4;6H\x1b[1m\x1b[?1049h");
    assert!(term.alt_screen_active);
    term.process(b"\x1b[12;30H\x1b[22mALT");
    assert_eq!(term.cursor.row, 11);
    assert!(!term.flags.bold());

    term.process(b"\x1b[?1049l");
    assert!(!term.alt_screen_active);
    assert_eq!(term.cursor.row, 3);
    assert_eq!(term.cursor.col, 5);
    assert!(term.flags.bold());
}

#[test]
fn test_private_mode_mouse() {
    let mut term = Terminal::new(80, 24);

    // Normal mouse tracking
    term.process(b"\x1b[?1000h");
    assert!(matches!(term.mouse_mode, MouseMode::Normal));

    // Button event mode
    term.process(b"\x1b[?1002h");
    assert!(matches!(term.mouse_mode, MouseMode::ButtonEvent));

    // Any event mode
    term.process(b"\x1b[?1003h");
    assert!(matches!(term.mouse_mode, MouseMode::AnyEvent));

    // Disable
    term.process(b"\x1b[?1000l");
    assert!(matches!(term.mouse_mode, MouseMode::Off));
}

#[test]
fn test_private_mode_mouse_encoding() {
    let mut term = Terminal::new(80, 24);

    // SGR mouse
    term.process(b"\x1b[?1006h");
    assert!(matches!(term.mouse_encoding, MouseEncoding::Sgr));

    // UTF-8 mouse
    term.process(b"\x1b[?1005h");
    assert!(matches!(term.mouse_encoding, MouseEncoding::Utf8));

    // URXVT mouse
    term.process(b"\x1b[?1015h");
    assert!(matches!(term.mouse_encoding, MouseEncoding::Urxvt));

    // SGR pixel mouse
    term.process(b"\x1b[?1016h");
    assert!(matches!(term.mouse_encoding, MouseEncoding::SgrPixels));

    // Reset to default
    term.process(b"\x1b[?1016l");
    assert!(matches!(term.mouse_encoding, MouseEncoding::Default));
}

#[test]
fn test_private_mode_bracketed_paste() {
    let mut term = Terminal::new(80, 24);

    // Enable bracketed paste
    term.process(b"\x1b[?2004h");
    assert!(term.bracketed_paste);

    // Disable
    term.process(b"\x1b[?2004l");
    assert!(!term.bracketed_paste);
}

// ========== Device Response Tests ==========

#[test]
fn test_device_status_report() {
    let mut term = Terminal::new(80, 24);

    // DSR 5 - Operating status
    term.process(b"\x1b[5n");
    let response = term.drain_responses();
    assert_eq!(response, b"\x1b[0n");

    // DSR 6 - Cursor position report
    term.process(b"\x1b[10;20H");
    term.process(b"\x1b[6n");
    let response = term.drain_responses();
    assert_eq!(response, b"\x1b[10;20R"); // 1-indexed
}

#[test]
fn test_device_attributes() {
    let mut term = Terminal::new(80, 24);

    // Primary DA - should include parameter 52 for OSC 52 clipboard
    term.process(b"\x1b[c");
    let response = term.drain_responses();
    let response_str = std::str::from_utf8(&response).unwrap();
    assert!(response_str.starts_with("\x1b[?"));
    assert!(
        response_str.contains(";52"),
        "DA1 should advertise OSC 52 clipboard (param 52)"
    );

    // Secondary DA
    term.process(b"\x1b[>c");
    let response = term.drain_responses();
    assert_eq!(response, b"\x1b[>82;10000;0c");
}

#[test]
fn test_xtversion() {
    let mut term = Terminal::new(80, 24);

    // XTVERSION: CSI > q
    term.process(b"\x1b[>q");
    let response = term.drain_responses();
    let response_str = std::str::from_utf8(&response).unwrap();
    assert!(
        response_str.starts_with("\x1bP>|par-term("),
        "XTVERSION should respond with par-term version"
    );
    assert!(
        response_str.ends_with(")\x1b\\"),
        "XTVERSION should end with ST"
    );
}

// ========== Scroll Region and Tab Tests ==========

#[test]
fn test_scroll_region() {
    let mut term = Terminal::new(80, 24);

    // Set scroll region rows 6-16 (1-indexed)
    term.process(b"\x1b[6;16r");
    assert_eq!(term.scroll_region_top, 5); // 0-indexed
    assert_eq!(term.scroll_region_bottom, 15);

    // Reset to full screen
    term.process(b"\x1b[r");
    assert_eq!(term.scroll_region_top, 0);
    assert_eq!(term.scroll_region_bottom, 23);
}

#[test]
fn test_tab_stops() {
    let mut term = Terminal::new(80, 24);

    // Set a tab stop
    term.process(b"\x1b[1;20H");
    term.process(b"\x1bH"); // HTS (ESC H)
    assert!(term.tab_stops[19]); // 0-indexed

    // Clear tab at current position
    term.process(b"\x1b[g"); // or \x1b[0g
    assert!(!term.tab_stops[19]);

    // Clear all tabs
    term.process(b"\x1b[3g");
    assert!(!term.tab_stops.iter().any(|&x| x));
}

// ========== Cursor Style Tests ==========

#[test]
fn test_cursor_style() {
    let mut term = Terminal::new(80, 24);

    // Blinking block
    term.process(b"\x1b[1 q");
    assert_eq!(term.cursor.style, CursorStyle::BlinkingBlock);

    // Steady block
    term.process(b"\x1b[2 q");
    assert_eq!(term.cursor.style, CursorStyle::SteadyBlock);

    // Blinking underline
    term.process(b"\x1b[3 q");
    assert_eq!(term.cursor.style, CursorStyle::BlinkingUnderline);

    // Steady underline
    term.process(b"\x1b[4 q");
    assert_eq!(term.cursor.style, CursorStyle::SteadyUnderline);

    // Blinking bar
    term.process(b"\x1b[5 q");
    assert_eq!(term.cursor.style, CursorStyle::BlinkingBar);

    // Steady bar
    term.process(b"\x1b[6 q");
    assert_eq!(term.cursor.style, CursorStyle::SteadyBar);
}

// ========== Save/Restore Cursor Tests ==========

#[test]
fn test_save_restore_cursor_ansi() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b[10;15H");
    term.process(b"\x1b[31m"); // Red fg

    // Save cursor (ANSI.SYS style)
    term.process(b"\x1b[s");

    // Move and change
    term.process(b"\x1b[20;5H");
    term.process(b"\x1b[32m");

    // Restore cursor
    term.process(b"\x1b[u");
    assert_eq!(term.cursor.col, 14); // 0-indexed
    assert_eq!(term.cursor.row, 9);
}

// ========== XTWINOPS Tests ==========

#[test]
fn test_xtwinops_report_size() {
    let mut term = Terminal::new(80, 24);

    // Report text area size (CSI 18 t)
    term.process(b"\x1b[18t");
    let response = term.drain_responses();
    assert_eq!(response, b"\x1b[8;24;80t");
}

#[test]
fn test_xtwinops_title_stack() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b]0;Original\x1b\\");

    // Save title (CSI 22 t)
    term.process(b"\x1b[22t");

    term.process(b"\x1b]0;New\x1b\\");

    // Restore title (CSI 23 t)
    term.process(b"\x1b[23t");
    assert_eq!(term.title(), "Original");
}

// ========== Insert Mode Tests ==========

#[test]
fn test_insert_mode() {
    let mut term = Terminal::new(80, 24);

    // Enable insert mode (IRM)
    term.process(b"\x1b[4h");
    assert!(term.insert_mode);

    // Disable insert mode
    term.process(b"\x1b[4l");
    assert!(!term.insert_mode);
}

// ========== Mode Changed Event Tests ==========

/// Helper: drain events and find ModeChanged events matching a mode name
fn find_mode_events(term: &mut Terminal, mode: &str) -> Vec<(String, bool)> {
    term.poll_events()
        .into_iter()
        .filter_map(|e| match e {
            TerminalEvent::ModeChanged(m, enabled) if m == mode => Some((m, enabled)),
            _ => None,
        })
        .collect()
}

#[test]
fn test_mode_changed_event_mouse_normal() {
    let mut term = Terminal::new(80, 24);
    term.poll_events(); // Clear any initial events

    // Enable normal mouse tracking
    term.process(b"\x1b[?1000h");
    let events = find_mode_events(&mut term, "mouse_normal");
    assert_eq!(events.len(), 1);
    assert!(events[0].1); // enabled = true

    // Disable mouse tracking
    term.process(b"\x1b[?1000l");
    let events = find_mode_events(&mut term, "mouse_normal");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1); // enabled = false
}

#[test]
fn test_mode_changed_event_mouse_button_event() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    term.process(b"\x1b[?1002h");
    let events = find_mode_events(&mut term, "mouse_button_event");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    term.process(b"\x1b[?1002l");
    let events = find_mode_events(&mut term, "mouse_button_event");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);
}

#[test]
fn test_mode_changed_event_mouse_any_event() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    term.process(b"\x1b[?1003h");
    let events = find_mode_events(&mut term, "mouse_any_event");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    term.process(b"\x1b[?1003l");
    let events = find_mode_events(&mut term, "mouse_any_event");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);
}

#[test]
fn test_mode_changed_event_mouse_encoding() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    // Enable SGR encoding
    term.process(b"\x1b[?1006h");
    let events = find_mode_events(&mut term, "mouse_sgr");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    // Disable SGR encoding
    term.process(b"\x1b[?1006l");
    let events = find_mode_events(&mut term, "mouse_sgr");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);

    // Enable SGR pixel encoding
    term.process(b"\x1b[?1016h");
    let events = find_mode_events(&mut term, "mouse_sgr_pixels");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    // Disable SGR pixel encoding
    term.process(b"\x1b[?1016l");
    let events = find_mode_events(&mut term, "mouse_sgr_pixels");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);
}

#[test]
fn test_mode_changed_event_alt_screen_1047() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    term.process(b"\x1b[?1047h");
    let events = find_mode_events(&mut term, "alternate_screen");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    term.process(b"\x1b[?1047l");
    let events = find_mode_events(&mut term, "alternate_screen");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);
}

#[test]
fn test_mode_changed_event_bracketed_paste() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    term.process(b"\x1b[?2004h");
    let events = find_mode_events(&mut term, "bracketed_paste");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    term.process(b"\x1b[?2004l");
    let events = find_mode_events(&mut term, "bracketed_paste");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);
}

#[test]
fn test_mode_changed_event_application_cursor() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    term.process(b"\x1b[?1h");
    let events = find_mode_events(&mut term, "application_cursor");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    term.process(b"\x1b[?1l");
    let events = find_mode_events(&mut term, "application_cursor");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);
}

#[test]
fn test_mode_changed_event_focus_tracking() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    term.process(b"\x1b[?1004h");
    let events = find_mode_events(&mut term, "focus_tracking");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    term.process(b"\x1b[?1004l");
    let events = find_mode_events(&mut term, "focus_tracking");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);
}

#[test]
fn test_mode_changed_event_cursor_visible() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    // Hide cursor
    term.process(b"\x1b[?25l");
    let events = find_mode_events(&mut term, "cursor_visible");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);

    // Show cursor
    term.process(b"\x1b[?25h");
    let events = find_mode_events(&mut term, "cursor_visible");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);
}

#[test]
fn test_mode_changed_event_alternate_screen() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    // Enter alt screen
    term.process(b"\x1b[?1049h");
    let events = find_mode_events(&mut term, "alternate_screen");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    // Leave alt screen
    term.process(b"\x1b[?1049l");
    let events = find_mode_events(&mut term, "alternate_screen");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);
}

#[test]
fn test_mode_changed_event_origin_mode() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    term.process(b"\x1b[?6h");
    let events = find_mode_events(&mut term, "origin_mode");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    term.process(b"\x1b[?6l");
    let events = find_mode_events(&mut term, "origin_mode");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);
}

#[test]
fn test_mode_changed_event_auto_wrap() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    // Disable auto-wrap (default is on)
    term.process(b"\x1b[?7l");
    let events = find_mode_events(&mut term, "auto_wrap");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);

    // Re-enable auto-wrap
    term.process(b"\x1b[?7h");
    let events = find_mode_events(&mut term, "auto_wrap");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);
}

#[test]
fn test_mode_changed_event_insert_mode() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    term.process(b"\x1b[4h");
    let events = find_mode_events(&mut term, "insert_mode");
    assert_eq!(events.len(), 1);
    assert!(events[0].1);

    term.process(b"\x1b[4l");
    let events = find_mode_events(&mut term, "insert_mode");
    assert_eq!(events.len(), 1);
    assert!(!events[0].1);
}

#[test]
fn test_mode_changed_no_event_when_mouse_already_off() {
    let mut term = Terminal::new(80, 24);
    term.poll_events();

    // Mouse is already off, resetting should not emit an event
    term.process(b"\x1b[?1000l");
    let all_events: Vec<_> = term
        .poll_events()
        .into_iter()
        .filter(|e| matches!(e, TerminalEvent::ModeChanged(..)))
        .collect();
    assert!(all_events.is_empty());
}

// ─── DECRQM (Request Mode) ─────────────────────────────────────────────────

#[test]
fn test_decrqm_application_cursor_off_by_default() {
    let mut term = Terminal::new(80, 24);
    // Query DEC private mode 1 (application cursor) — should be reset (status=2)
    term.process(b"\x1b[?1$p");
    let response = term.drain_responses();
    let response_str = std::str::from_utf8(&response).unwrap();
    assert!(
        response_str.contains("$y"),
        "DECRQM response should contain $y, got: {:?}",
        response_str
    );
    assert!(
        response_str.contains(";2"),
        "application cursor should be reset by default, got: {:?}",
        response_str
    );
}

#[test]
fn test_decrqm_application_cursor_after_setting() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[?1h"); // enable application cursor
    term.process(b"\x1b[?1$p"); // query
    let response = term.drain_responses();
    let response_str = std::str::from_utf8(&response).unwrap();
    assert!(
        response_str.contains(";1"),
        "application cursor should be set (status=1), got: {:?}",
        response_str
    );
}

#[test]
fn test_decrqm_auto_wrap_on_by_default() {
    let mut term = Terminal::new(80, 24);
    // Auto-wrap (mode 7) is on by default
    term.process(b"\x1b[?7$p");
    let response = term.drain_responses();
    let response_str = std::str::from_utf8(&response).unwrap();
    assert!(
        response_str.contains(";1"),
        "auto-wrap should be set by default (status=1), got: {:?}",
        response_str
    );
}

#[test]
fn test_decrqm_unrecognized_mode_returns_zero() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[?9999$p");
    let response = term.drain_responses();
    let response_str = std::str::from_utf8(&response).unwrap();
    assert!(
        response_str.contains(";0"),
        "unrecognized mode should return status 0, got: {:?}",
        response_str
    );
}

#[test]
fn test_decrqm_mouse_encoding_modes_report_set_and_reset() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b[?1016$p");
    let response = term.drain_responses();
    let response = std::str::from_utf8(&response).unwrap();
    assert!(
        response.contains("\x1b[?1016;2$y"),
        "SGR pixel mouse encoding should be reset by default, got: {response:?}"
    );

    term.process(b"\x1b[?1016h\x1b[?1006$p\x1b[?1016$p");
    let response = term.drain_responses();
    let response = std::str::from_utf8(&response).unwrap();
    assert!(
        response.contains("\x1b[?1006;2$y"),
        "SGR cell mouse encoding should report reset while SGR pixel mode is active: {response:?}"
    );
    assert!(
        response.contains("\x1b[?1016;1$y"),
        "SGR pixel mouse encoding should report set after DECSET 1016: {response:?}"
    );

    term.process(b"\x1b[?1016l\x1b[?1016$p");
    let response = term.drain_responses();
    let response = std::str::from_utf8(&response).unwrap();
    assert!(
        response.contains("\x1b[?1016;2$y"),
        "SGR pixel mouse encoding should report reset after DECRST 1016: {response:?}"
    );
}

#[test]
fn test_decrqm_alt_screen_variants_report_set_and_reset() {
    let mut term = Terminal::new(80, 24);

    term.process(b"\x1b[?47$p\x1b[?1047$p\x1b[?1049$p");
    let response = term.drain_responses();
    let response = std::str::from_utf8(&response).unwrap();
    assert!(
        response.contains("\x1b[?47;2$y")
            && response.contains("\x1b[?1047;2$y")
            && response.contains("\x1b[?1049;2$y"),
        "alternate screen variants should report reset by default: {response:?}"
    );

    term.process(b"\x1b[?1047h\x1b[?47$p\x1b[?1047$p\x1b[?1049$p");
    let response = term.drain_responses();
    let response = std::str::from_utf8(&response).unwrap();
    assert!(
        response.contains("\x1b[?47;1$y")
            && response.contains("\x1b[?1047;1$y")
            && response.contains("\x1b[?1049;1$y"),
        "alternate screen variants should report set while alt screen is active: {response:?}"
    );

    term.process(b"\x1b[?1047l\x1b[?1047$p");
    let response = term.drain_responses();
    let response = std::str::from_utf8(&response).unwrap();
    assert!(
        response.contains("\x1b[?1047;2$y"),
        "alternate screen should report reset after DECRST 1047: {response:?}"
    );
}

#[test]
fn test_decrqm_ansi_insert_mode_off_by_default() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[4$p");
    let response = term.drain_responses();
    let response_str = std::str::from_utf8(&response).unwrap();
    assert!(
        response_str.contains("$y"),
        "DECRQM ANSI response should contain $y, got: {:?}",
        response_str
    );
    assert!(
        response_str.contains(";2"),
        "insert mode should be reset by default, got: {:?}",
        response_str
    );
}

#[test]
fn test_decrqm_alt_screen_after_enable() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[?1049h"); // enable alt screen
    term.process(b"\x1b[?1049$p"); // query
    let response = term.drain_responses();
    let response_str = std::str::from_utf8(&response).unwrap();
    assert!(
        response_str.contains(";1"),
        "alt screen should be set after enable, got: {:?}",
        response_str
    );
}

// ─── DECSLRM (Set Left-Right Margins) ─────────────────────────────────────

#[test]
fn test_decslrm_sets_margins_when_declrmm_enabled() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[?69h"); // enable DECLRMM
    term.process(b"\x1b[10;70s"); // set left=10, right=70 (1-indexed)
    assert_eq!(term.left_margin, 9, "left margin should be 9 (0-indexed)");
    assert_eq!(
        term.right_margin, 69,
        "right margin should be 69 (0-indexed)"
    );
}

#[test]
fn test_decslrm_ignored_when_declrmm_disabled() {
    let mut term = Terminal::new(80, 24);
    // DECLRMM is off by default; CSI s without params or without DECLRMM = cursor save
    term.process(b"\x1b[5;10H");
    term.process(b"\x1b[s"); // save cursor (not DECSLRM since DECLRMM is off and no params)
    assert_eq!(
        term.left_margin, 0,
        "left margin should remain 0 without DECLRMM"
    );
    assert_eq!(
        term.right_margin, 79,
        "right margin should remain 79 without DECLRMM"
    );
}

// ─── DECCRA (Copy Rectangular Area) ────────────────────────────────────────

#[test]
fn test_deccra_copies_content() {
    use crate::terminal::cells_to_text;
    let mut term = Terminal::new(80, 24);
    // Write "ABCDE" on row 1 col 1
    term.process(b"\x1b[1;1H");
    term.process(b"ABCDE");
    // DECCRA: copy rows 1-1, cols 1-5, page 1 → dest row 5, col 1, page 1
    // Format: CSI Pt;Pl;Pb;Pr;Pp;Dt;Dl;Dp $v
    term.process(b"\x1b[1;1;1;5;1;5;1;1$v");
    let rows = term.get_row_range(4, 5); // 0-indexed row 4 = 1-indexed row 5
    let row4_text = cells_to_text(&rows[0]);
    assert!(
        row4_text.starts_with("ABCDE"),
        "DECCRA should copy 'ABCDE' to row 5, got: {:?}",
        &row4_text[..row4_text.len().min(10)]
    );
}

// ─── DECSERA (Selective Erase Rectangular Area) ────────────────────────────

#[test]
fn test_decsera_erases_unprotected_cells() {
    use crate::terminal::cells_to_text;
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[1;1H");
    term.process(b"hello");
    // DECSERA: erase rows 1-1, cols 1-5
    // Format: CSI Pt;Pl;Pb;Pr ${
    term.process(b"\x1b[1;1;1;5${");
    let rows = term.get_row_range(0, 1);
    let row0_text = cells_to_text(&rows[0]);
    let region: String = row0_text.chars().take(5).collect();
    assert!(
        region.chars().all(|c| c == ' '),
        "DECSERA should erase unprotected cells to spaces, got: {:?}",
        region
    );
}

// ─── Synchronized Updates ──────────────────────────────────────────────────

#[test]
fn test_synchronized_updates_mode_toggle() {
    let mut term = Terminal::new(80, 24);
    term.process(b"\x1b[?2026h"); // enable
    assert!(
        term.synchronized_updates,
        "synchronized_updates should be true after enable"
    );
    term.process(b"\x1b[?2026l"); // disable
    assert!(
        !term.synchronized_updates,
        "synchronized_updates should be false after disable"
    );
}

#[test]
fn test_synchronized_updates_timeout_keeps_buffer_before_deadline() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden");

    assert!(!term.flush_synchronized_updates_if_timed_out());
    assert!(term.synchronized_updates);
    assert_eq!(term.update_buffer, b"hidden");
    assert_eq!(term.active_grid().row_text(0).trim_end(), "before");
}

#[test]
fn test_synchronized_updates_timeout_flushes_buffer_and_disables_mode() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden");
    term.sync_update_started_at =
        Some(std::time::Instant::now() - std::time::Duration::from_secs(2));

    assert!(term.flush_synchronized_updates_if_timed_out());
    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(term.active_grid().row_text(0).trim_end(), "beforehidden");
}

#[test]
fn test_synchronized_updates_timeout_ignores_nested_enable_in_stale_buffer() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden\x1b[?2026hnested");
    term.sync_update_started_at =
        Some(std::time::Instant::now() - std::time::Duration::from_secs(2));

    assert!(term.flush_synchronized_updates_if_timed_out());
    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(
        term.active_grid().row_text(0).trim_end(),
        "beforehiddennested"
    );
}

#[test]
fn test_synchronized_updates_timeout_ignores_nested_enable_after_reset() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden\x1bcafter\x1b[?2026hnested");
    term.sync_update_started_at =
        Some(std::time::Instant::now() - std::time::Duration::from_secs(2));

    assert!(term.flush_synchronized_updates_if_timed_out());
    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(term.active_grid().row_text(0).trim_end(), "afternested");
}

#[test]
fn test_synchronized_updates_manual_flush_resets_timeout_window() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden");
    term.sync_update_started_at =
        Some(std::time::Instant::now() - std::time::Duration::from_secs(2));
    term.flush_synchronized_updates();

    assert!(term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(term.active_grid().row_text(0).trim_end(), "beforehidden");
    assert!(
        !term.flush_synchronized_updates_if_timed_out(),
        "manual flush should start a fresh synchronized update timeout window"
    );
}

#[test]
fn test_synchronized_updates_buffers_remainder_after_enable_in_same_chunk() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden");

    assert!(term.synchronized_updates);
    assert_eq!(term.update_buffer, b"hidden");
    assert_eq!(term.active_grid().get(0, 0).unwrap().c, 'b');
    assert_eq!(term.active_grid().get(5, 0).unwrap().c, 'e');
    assert_eq!(term.active_grid().get(6, 0).unwrap().c, ' ');

    term.process(b"-shown\x1b[?2026l");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(
        term.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn test_synchronized_updates_buffers_remainder_after_split_enable() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2");
    term.process(b"026hhidden");

    assert!(term.synchronized_updates);
    assert_eq!(term.update_buffer, b"hidden");
    assert_eq!(term.active_grid().row_text(0).trim_end(), "before");

    term.process(b"-shown\x1b[?2026l");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(
        term.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn test_synchronized_updates_buffers_remainder_after_multi_split_enable() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b");
    term.process(b"[?202");
    term.process(b"6hhidden");

    assert!(term.synchronized_updates);
    assert_eq!(term.update_buffer, b"hidden");
    assert_eq!(term.active_grid().row_text(0).trim_end(), "before");

    term.process(b"-shown\x1b[?2026l");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(
        term.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn test_synchronized_updates_buffers_remainder_when_2026_is_not_first_mode() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?25;2026hhidden");

    assert!(term.synchronized_updates);
    assert_eq!(term.update_buffer, b"hidden");
    assert_eq!(term.active_grid().row_text(0).trim_end(), "before");

    term.process(b"-shown\x1b[?2026l");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(
        term.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn test_synchronized_updates_buffers_remainder_after_c1_csi_enable() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x9b?2026hhidden");

    assert!(term.synchronized_updates);
    assert_eq!(term.update_buffer, b"hidden");
    assert_eq!(term.active_grid().row_text(0).trim_end(), "before");

    term.process(b"-shown\x9b?2026l");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(
        term.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn test_synchronized_updates_flushes_start_and_end_in_same_chunk() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden\x1b[?2026l-after");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(
        term.active_grid().row_text(0).trim_end(),
        "beforehidden-after"
    );
}

#[test]
fn test_synchronized_updates_flushes_when_2026_is_not_first_reset_mode() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden");
    term.process(b"-shown\x1b[?25;2026l-after");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(
        term.active_grid().row_text(0).trim_end(),
        "beforehidden-shown-after"
    );
}

#[test]
fn test_synchronized_updates_flushes_after_split_multi_mode_disable() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden\x1b[?25;20");
    assert!(term.synchronized_updates);
    assert_eq!(term.active_grid().row_text(0).trim_end(), "before");

    term.process(b"26l-after");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(
        term.active_grid().row_text(0).trim_end(),
        "beforehidden-after"
    );
}

#[test]
fn test_synchronized_updates_flushes_disable_with_long_trailing_remainder() {
    let mut term = Terminal::new(80, 24);
    let trailing = "x".repeat(64);
    let update = format!("hidden\x1b[?2026l{trailing}");

    term.process(b"before\x1b[?2026h");
    term.process(update.as_bytes());

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(
        term.active_grid().row_text(0).trim_end(),
        format!("beforehidden{trailing}")
    );
}

#[test]
fn test_synchronized_updates_does_not_flush_for_osc_embedded_hard_reset() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden\x1b]0;not-a-reset-\x1bctitle\x07");

    assert!(term.synchronized_updates);
    assert_eq!(term.active_grid().row_text(0).trim_end(), "before");

    term.process(b"-shown\x1b[?2026l");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(term.active_grid().row_text(0).trim_end(), "title-shown");
}

#[test]
fn test_synchronized_updates_does_not_flush_for_split_osc_embedded_hard_reset() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2026hhidden\x1b]0;not-a-reset-\x1b");

    assert!(term.synchronized_updates);
    assert_eq!(term.active_grid().row_text(0).trim_end(), "before");

    term.process(b"ctitle\x07-shown");

    assert!(term.synchronized_updates);
    assert_eq!(term.active_grid().row_text(0).trim_end(), "before");

    term.process(b"\x1b[?2026l");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(term.active_grid().row_text(0).trim_end(), "title-shown");
}

#[test]
fn test_synchronized_updates_does_not_buffer_split_non_sync_private_mode() {
    let mut term = Terminal::new(80, 24);

    term.process(b"before\x1b[?2");
    term.process(b"5hshown");

    assert!(!term.synchronized_updates);
    assert!(term.update_buffer.is_empty());
    assert_eq!(term.active_grid().row_text(0).trim_end(), "beforeshown");
}
