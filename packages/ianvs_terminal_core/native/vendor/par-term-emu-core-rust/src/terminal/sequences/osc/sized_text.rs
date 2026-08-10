//! Kitty OSC 66 sized-text handling.

use crate::cell::MultiCell;
use crate::terminal::Terminal;
use crate::unicode_width_config::str_width;
use unicode_segmentation::UnicodeSegmentation;

const MAX_OSC66_TEXT_BYTES: usize = 4 * 1024;
const MAX_OSC66_METADATA_BYTES: usize = 128;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct SizedTextMetadata {
    width: u8,
    scale: u8,
    subscale_n: u8,
    subscale_d: u8,
    vertical_align: u8,
    horizontal_align: u8,
}

impl Default for SizedTextMetadata {
    fn default() -> Self {
        Self {
            width: 0,
            scale: 1,
            subscale_n: 0,
            subscale_d: 0,
            vertical_align: 0,
            horizontal_align: 0,
        }
    }
}

impl SizedTextMetadata {
    fn parse(value: &[u8]) -> Option<Self> {
        if value.len() > MAX_OSC66_METADATA_BYTES {
            return None;
        }
        let value = std::str::from_utf8(value).ok()?;
        let mut metadata = Self::default();
        if !value.is_empty() {
            for field in value.split(':') {
                let (key, raw_value) = field.split_once('=')?;
                if key.len() != 1 || raw_value.is_empty() || raw_value.len() > 2 {
                    return None;
                }
                let parsed = raw_value.parse::<u8>().ok()?;
                match key.as_bytes()[0] {
                    b'w' if parsed <= 7 => metadata.width = parsed,
                    b's' if (1..=7).contains(&parsed) => metadata.scale = parsed,
                    b'n' if parsed <= 15 => metadata.subscale_n = parsed,
                    b'd' if parsed <= 15 => metadata.subscale_d = parsed,
                    b'v' if parsed <= 2 => metadata.vertical_align = parsed,
                    b'h' if parsed <= 2 => metadata.horizontal_align = parsed,
                    _ => return None,
                }
            }
        }
        if metadata.subscale_d == 0 {
            metadata.subscale_n = 0;
        } else if metadata.subscale_n >= metadata.subscale_d {
            return None;
        }
        Some(metadata)
    }

    fn cell_metadata(self, width: u8, natural_width: bool) -> MultiCell {
        MultiCell {
            width,
            scale: self.scale,
            subscale_n: self.subscale_n,
            subscale_d: self.subscale_d,
            vertical_align: self.vertical_align,
            horizontal_align: self.horizontal_align,
            x: 0,
            y: 0,
            natural_width,
        }
    }
}

fn is_unicode_noncharacter(value: char) -> bool {
    let value = value as u32;
    (0xfdd0..=0xfdef).contains(&value) || value & 0xffff >= 0xfffe
}

fn decode_escape_safe_utf8(value: &[u8]) -> String {
    String::from_utf8_lossy(value)
        .chars()
        .filter(|character| !character.is_control() && !is_unicode_noncharacter(*character))
        .collect()
}

impl Terminal {
    pub(crate) fn handle_osc_sized_text(&mut self, params: &[&[u8]]) {
        if params.len() < 3 {
            return;
        }
        let Some(metadata) = SizedTextMetadata::parse(params[1]) else {
            return;
        };
        let text_bytes = params[2..].join(&b';');
        if text_bytes.is_empty() || text_bytes.len() > MAX_OSC66_TEXT_BYTES {
            return;
        }
        let text = decode_escape_safe_utf8(&text_bytes);
        if text.is_empty() {
            return;
        }

        if metadata.width > 0 {
            self.write_multicell_block(&text, metadata.cell_metadata(metadata.width, false));
            return;
        }

        for grapheme in UnicodeSegmentation::graphemes(text.as_str(), true) {
            let width = str_width(grapheme, &self.width_config).min(7) as u8;
            if width == 0 {
                continue;
            }
            self.write_multicell_block(grapheme, metadata.cell_metadata(width, true));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal::OscCapability;

    #[test]
    fn osc66_fixed_width_preserves_metadata_text_and_cell_offsets() {
        let mut terminal = Terminal::new(12, 6);
        terminal.process(b"\x1b]66;s=2:w=2:n=1:d=2:v=2:h=1;A;B\x07");

        let anchor = terminal.grid().get(0, 0).expect("anchor");
        assert_eq!(anchor.get_grapheme(), "A;B");
        let metadata = anchor.multicell.expect("multicell metadata");
        assert_eq!(metadata.width, 2);
        assert_eq!(metadata.scale, 2);
        assert_eq!(metadata.subscale_n, 1);
        assert_eq!(metadata.subscale_d, 2);
        assert_eq!(metadata.vertical_align, 2);
        assert_eq!(metadata.horizontal_align, 1);
        assert!(!metadata.natural_width);
        for y in 0..2 {
            for x in 0..4 {
                let cell = terminal.grid().get(x, y).expect("occupied cell");
                let cell_metadata = cell.multicell.expect("occupied metadata");
                assert_eq!((cell_metadata.x, cell_metadata.y), (x as u8, y as u8));
                if x + y > 0 {
                    assert_eq!(cell.get_grapheme(), " ");
                }
            }
        }
        assert_eq!((terminal.cursor().col, terminal.cursor().row), (4, 0));
    }

    #[test]
    fn osc66_natural_width_segments_ascii_and_wide_graphemes() {
        let mut terminal = Terminal::new(20, 6);
        terminal.process("\x1b]66;s=2;a莊\x1b\\".as_bytes());

        let ascii = terminal.grid().get(0, 0).unwrap();
        let wide = terminal.grid().get(2, 0).unwrap();
        assert_eq!(ascii.get_grapheme(), "a");
        assert_eq!(ascii.multicell.unwrap().width, 1);
        assert!(ascii.multicell.unwrap().natural_width);
        assert_eq!(wide.get_grapheme(), "莊");
        assert_eq!(wide.multicell.unwrap().width, 2);
        assert_eq!((terminal.cursor().col, terminal.cursor().row), (6, 0));
    }

    #[test]
    fn osc66_rejects_malformed_metadata_and_filters_unsafe_text_controls() {
        let mut terminal = Terminal::new(20, 6);
        terminal.process(b"\x1b]66;q=1;bad\x07\x1b]66;n=2:d=2;bad\x07");
        assert!(terminal.grid().get(0, 0).unwrap().multicell.is_none());

        terminal.process(b"\x1b]66;w=2;A\x01B\x07");
        assert_eq!(terminal.grid().get(0, 0).unwrap().get_grapheme(), "AB");
    }

    #[test]
    fn osc66_wraps_before_a_block_and_discards_blocks_larger_than_screen() {
        let mut terminal = Terminal::new(6, 6);
        terminal.process(b"12345\x1b]66;s=2;A\x07");
        assert_eq!(terminal.grid().get(0, 1).unwrap().get_grapheme(), "A");
        assert_eq!((terminal.cursor().col, terminal.cursor().row), (2, 1));

        terminal.process(b"\x1b]66;s=7:w=7;too-large\x07");
        assert_eq!((terminal.cursor().col, terminal.cursor().row), (2, 1));
    }

    #[test]
    fn osc66_snapshot_restores_blocks_and_ris_clears_them() {
        let mut terminal = Terminal::new(12, 6);
        terminal.process(b"\x1b]66;s=2;A\x07");
        let snapshot = terminal.capture_snapshot();
        terminal.process(b"\rX");
        terminal.restore_from_snapshot(snapshot);
        assert_eq!(terminal.grid().get(0, 0).unwrap().get_grapheme(), "A");
        assert!(terminal.grid().get(0, 0).unwrap().multicell.is_some());

        terminal.reset();
        assert!(terminal.grid().get(0, 0).unwrap().multicell.is_none());
    }

    #[test]
    fn osc66_normal_writes_follow_top_and_lower_row_overwrite_rules() {
        let mut terminal = Terminal::new(12, 6);
        terminal.process(b"\x1b]66;s=2;AB\x07");

        terminal.process(b"\x1b[1;2Hx");
        assert!(terminal.grid().get(0, 0).unwrap().multicell.is_none());
        assert_eq!(terminal.grid().get(1, 0).unwrap().get_grapheme(), "x");
        assert_eq!(terminal.grid().get(2, 0).unwrap().get_grapheme(), "B");

        terminal.process(b"\x1b[2;3Hy");
        assert_eq!(terminal.grid().get(2, 0).unwrap().get_grapheme(), "B");
        assert_eq!(terminal.grid().get(4, 1).unwrap().get_grapheme(), "y");
        assert_eq!((terminal.cursor().col, terminal.cursor().row), (5, 1));
    }

    #[test]
    fn osc66_combining_text_updates_only_from_the_top_row() {
        let mut terminal = Terminal::new(12, 6);
        terminal.process(b"\x1b]66;s=2;A\x07");
        terminal.process("\u{301}".as_bytes());
        assert_eq!(
            terminal.grid().get(0, 0).unwrap().get_grapheme(),
            "A\u{301}"
        );

        terminal.process(b"\x1b[2;2H");
        terminal.process("\u{300}".as_bytes());
        assert_eq!(
            terminal.grid().get(0, 0).unwrap().get_grapheme(),
            "A\u{301}"
        );
    }

    #[test]
    fn osc66_edit_controls_clear_splits_and_shift_complete_single_line_blocks() {
        let mut terminal = Terminal::new(12, 6);
        terminal.process(b"a\x1b]66;w=2;B\x07c");
        terminal.process(b"\x1b[1;1H\x1b[@");
        assert_eq!(terminal.grid().get(2, 0).unwrap().get_grapheme(), "B");
        assert!(terminal.grid().get(2, 0).unwrap().multicell.is_some());

        terminal.process(b"\x1b[1;3H\x1b[X");
        assert!(terminal.grid().get(2, 0).unwrap().multicell.is_none());
        assert!(terminal.grid().get(3, 0).unwrap().multicell.is_none());

        terminal.process(b"\x1b[2;1H\x1b]66;s=2;M\x07\x1b[2;1H\x1b[P");
        assert!(terminal.grid().get(0, 1).unwrap().multicell.is_none());
        assert!(terminal.grid().get(0, 2).unwrap().multicell.is_none());
    }

    #[test]
    fn osc66_line_edits_and_resize_do_not_leave_fragments() {
        let mut terminal = Terminal::new(12, 6);
        terminal.process(b"\x1b[2;1H\x1b]66;s=3;A\x07");
        terminal.process(b"\x1b[3;1H\x1b[L");
        for row in 0..6 {
            for col in 0..12 {
                assert!(
                    terminal.grid().get(col, row).unwrap().multicell.is_none(),
                    "line-edit fragment at ({col}, {row})"
                );
            }
        }

        terminal.process(b"\x1b[1;1H\x1b]66;s=2:w=2;B\x07");
        terminal.resize(3, 6);
        for row in 0..6 {
            for col in 0..3 {
                assert!(
                    terminal.grid().get(col, row).unwrap().multicell.is_none(),
                    "resize fragment at ({col}, {row})"
                );
            }
        }
    }

    #[test]
    fn osc66_resize_preserves_complete_blocks_that_still_fit() {
        let mut terminal = Terminal::new(12, 6);
        terminal.process(b"x\x1b]66;s=2:w=2;A\x07");

        terminal.resize(20, 8);
        let expanded = terminal.grid().get(1, 0).expect("expanded anchor");
        assert_eq!(expanded.get_grapheme(), "A");
        assert!(expanded.multicell.is_some_and(MultiCell::is_anchor));
        for y in 0..2 {
            for x in 1..5 {
                assert!(
                    terminal.grid().get(x, y).unwrap().multicell.is_some(),
                    "expanded block fragment at ({x}, {y})"
                );
            }
        }

        terminal.resize(8, 6);
        let narrowed = terminal.grid().get(1, 0).expect("narrowed anchor");
        assert_eq!(narrowed.get_grapheme(), "A");
        assert!(narrowed.multicell.is_some_and(MultiCell::is_anchor));
        for y in 0..2 {
            for x in 1..5 {
                assert!(
                    terminal.grid().get(x, y).unwrap().multicell.is_some(),
                    "narrowed block fragment at ({x}, {y})"
                );
            }
        }
    }

    #[test]
    fn osc66_scrollback_preserves_complete_blocks_and_removes_history_fragments() {
        let mut terminal = Terminal::with_scrollback(8, 4, 12);
        terminal.process(b"\x1b]66;s=2:w=2;history\x07");
        terminal.active_grid_mut().scroll_up(2);

        assert_eq!(terminal.grid().scrollback_len(), 2);
        let anchor = &terminal.grid().scrollback_line(0).unwrap()[0];
        assert_eq!(anchor.get_grapheme(), "history");
        assert!(anchor.multicell.is_some_and(MultiCell::is_anchor));
        assert!(terminal.grid().scrollback_line(1).unwrap()[3]
            .multicell
            .is_some());

        terminal.resize(12, 4);
        let expanded = &terminal.grid().scrollback_line(0).unwrap()[0];
        assert_eq!(expanded.get_grapheme(), "history");
        assert!(expanded.multicell.is_some_and(MultiCell::is_anchor));

        terminal.resize(3, 4);
        for line in 0..terminal.grid().scrollback_len() {
            assert!(
                terminal
                    .grid()
                    .scrollback_line(line)
                    .unwrap()
                    .iter()
                    .all(|cell| cell.multicell.is_none()),
                "oversized OSC 66 fragment survived in scrollback line {line}"
            );
        }
    }

    #[test]
    fn osc66_screen_and_scrollback_erases_remove_cross_boundary_blocks() {
        let mut terminal = Terminal::with_scrollback(8, 4, 12);
        terminal.process(b"\x1b]66;s=2;A\x07");
        terminal.active_grid_mut().scroll_up(1);
        assert!(terminal.grid().scrollback_line(0).unwrap()[0]
            .multicell
            .is_some());
        assert!(terminal.grid().get(0, 0).unwrap().multicell.is_some());

        terminal.process(b"\x1b[2J");
        assert!(terminal.grid().scrollback_line(0).unwrap()[0]
            .multicell
            .is_none());
        assert!(terminal.grid().get(0, 0).unwrap().multicell.is_none());

        terminal.process(b"\x1b[1;1H\x1b]66;s=2;B\x07");
        terminal.active_grid_mut().scroll_up(1);
        assert!(terminal.grid().scrollback_line(1).unwrap()[0]
            .multicell
            .is_some());
        assert!(terminal.grid().get(0, 0).unwrap().multicell.is_some());

        terminal.process(b"\x1b[3J");
        assert_eq!(terminal.grid().scrollback_len(), 0);
        assert!(terminal.grid().get(0, 0).unwrap().multicell.is_none());
    }

    #[test]
    fn osc66_survives_every_byte_split_with_bel_or_st() {
        for terminator in [b"\x07".as_slice(), b"\x1b\\".as_slice()] {
            let mut sequence = b"\x1b]66;s=2:w=2;split".to_vec();
            sequence.extend_from_slice(terminator);
            for split in 1..sequence.len() {
                let mut terminal = Terminal::new(12, 6);
                terminal.process(&sequence[..split]);
                terminal.process(&sequence[split..]);
                assert_eq!(
                    terminal.grid().get(0, 0).unwrap().get_grapheme(),
                    "split",
                    "split={split}, terminator={terminator:?}"
                );
            }
        }
    }

    #[test]
    fn osc66_appearance_policy_denial_blocks_cells() {
        let mut terminal = Terminal::new(12, 6);
        terminal.set_osc_capability_allowed(OscCapability::Appearance, false);
        terminal.process(b"\x1b]66;s=2;blocked\x07");
        assert!(terminal.grid().get(0, 0).unwrap().multicell.is_none());
    }

    #[test]
    fn osc66_capability_detection_reports_width_and_scale_cursor_advances() {
        let mut terminal = Terminal::new(12, 6);
        terminal.process(b"\r\x1b[6n\x1b]66;w=2; \x07\x1b[6n\x1b]66;s=2; \x07\x1b[6n");

        assert_eq!(terminal.drain_responses(), b"\x1b[1;1R\x1b[1;3R\x1b[1;5R");
    }
}
