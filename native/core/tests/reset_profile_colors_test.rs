use par_term_emu_core_rust::{color::Color, terminal::Terminal};

#[test]
fn ris_initializes_every_cell_with_profile_colors_on_both_screens() {
    for background in [Color::Rgb(245, 245, 247), Color::Rgb(30, 35, 40)] {
        let foreground = Color::Rgb(61, 62, 63);
        let mut terminal = Terminal::new(40, 8);
        terminal.set_default_fg(foreground);
        terminal.set_default_bg(background);
        terminal.process(b"old output\x1b[41mexplicit red\x1b[?1049hother screen");
        // Runtime OSC overrides must reset to the profile, including cells
        // that the subsequent shell prompt does not overwrite.
        terminal.process(b"\x1b]11;#123456\x07\x1b");
        terminal.process(b"c");
        assert_eq!(terminal.default_bg(), background);
        assert_eq!(terminal.default_fg(), foreground);
        assert!(!terminal.is_alt_screen_active());
        for alternate in [false, true] {
            if alternate {
                terminal.process(b"\x1b[?47h");
            }
            terminal.process(b"\x1b[32mhost\x1b[0m$ ");
            for row in 0..8 {
                for col in 0..40 {
                    let cell = terminal.active_grid().get(col, row).unwrap();
                    assert_eq!(
                        cell.bg, background,
                        "screen={alternate}, cell=({col},{row})"
                    );
                    if row > 0 || col >= 6 {
                        assert_eq!(cell.fg, foreground);
                    }
                }
            }
        }
    }
}
