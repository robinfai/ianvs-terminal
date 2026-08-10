//! Erase and clear operations for the terminal grid

use crate::color::Color;
use crate::grid::Grid;

impl Grid {
    fn blank_cell_with_bg_source(&self, bg: Color, bg_is_default: bool) -> crate::cell::Cell {
        let mut blank = self.blank_cell();
        blank.bg = bg;
        blank.flags.set_bg_is_default(bg_is_default);
        blank
    }

    /// Clear the entire grid
    pub fn clear(&mut self) {
        self.clear_multicells_intersecting(0, self.cols, 0, self.rows);
        let blank_cell = self.blank_cell();
        self.cells.fill(blank_cell);
        self.screen_has_multicells = false;
        self.multicells_may_exist = self
            .scrollback_cells
            .iter()
            .any(|cell| cell.multicell.is_some());
        self.screen_row_start = 0;
        self.wrapped.fill(false);
        self.zones.clear();
        self.damage.mark_full_repaint("clear_screen");
    }

    /// Clear a specific row
    pub fn clear_row(&mut self, row: usize) {
        self.clear_multicells_intersecting(0, self.cols, row, row.saturating_add(1));
        let blank_cell = self.blank_cell();
        if let Some(row_cells) = self.row_mut(row) {
            row_cells.fill(blank_cell);
        }
    }

    /// Clear a specific row using the active background color.
    pub fn clear_row_with_bg(&mut self, row: usize, bg: Color) {
        self.clear_row_with_bg_source(row, bg, false);
    }

    pub(crate) fn clear_row_with_bg_source(&mut self, row: usize, bg: Color, bg_is_default: bool) {
        self.clear_multicells_intersecting(0, self.cols, row, row.saturating_add(1));
        let blank = self.blank_cell_with_bg_source(bg, bg_is_default);
        if let Some(row_cells) = self.row_mut(row) {
            for cell in row_cells {
                *cell = blank.clone();
            }
        }
    }

    /// Clear from cursor to end of line
    pub fn clear_line_right(&mut self, col: usize, row: usize) {
        self.clear_multicells_intersecting(col, self.cols, row, row.saturating_add(1));
        let blank_cell = self.blank_cell();
        if let Some(range) = self.wide_safe_range(col, row, self.cols.saturating_sub(col)) {
            for c in range {
                if let Some(cell) = self.get_mut(c, row) {
                    *cell = blank_cell.clone();
                }
            }
        }
    }

    /// Clear from cursor to end of line using the active background color.
    pub fn clear_line_right_with_bg(&mut self, col: usize, row: usize, bg: Color) {
        self.clear_line_right_with_bg_source(col, row, bg, false);
    }

    pub(crate) fn clear_line_right_with_bg_source(
        &mut self,
        col: usize,
        row: usize,
        bg: Color,
        bg_is_default: bool,
    ) {
        self.clear_multicells_intersecting(col, self.cols, row, row.saturating_add(1));
        let blank = self.blank_cell_with_bg_source(bg, bg_is_default);
        if let Some(range) = self.wide_safe_range(col, row, self.cols.saturating_sub(col)) {
            for c in range {
                if let Some(cell) = self.get_mut(c, row) {
                    *cell = blank.clone();
                }
            }
        }
    }

    /// Clear from beginning of line to cursor
    pub fn clear_line_left(&mut self, col: usize, row: usize) {
        self.clear_multicells_intersecting(0, col.saturating_add(1), row, row.saturating_add(1));
        let blank_cell = self.blank_cell();
        if let Some(range) = self.wide_safe_range(0, row, col.saturating_add(1)) {
            for c in range {
                if let Some(cell) = self.get_mut(c, row) {
                    *cell = blank_cell.clone();
                }
            }
        }
    }

    /// Clear from beginning of line to cursor using the active background color.
    pub fn clear_line_left_with_bg(&mut self, col: usize, row: usize, bg: Color) {
        self.clear_line_left_with_bg_source(col, row, bg, false);
    }

    pub(crate) fn clear_line_left_with_bg_source(
        &mut self,
        col: usize,
        row: usize,
        bg: Color,
        bg_is_default: bool,
    ) {
        self.clear_multicells_intersecting(0, col.saturating_add(1), row, row.saturating_add(1));
        let blank = self.blank_cell_with_bg_source(bg, bg_is_default);
        if let Some(range) = self.wide_safe_range(0, row, col.saturating_add(1)) {
            for c in range {
                if let Some(cell) = self.get_mut(c, row) {
                    *cell = blank.clone();
                }
            }
        }
    }

    /// Clear from cursor to end of screen
    pub fn clear_screen_below(&mut self, col: usize, row: usize) {
        self.clear_line_right(col, row);
        for r in (row + 1)..self.rows {
            self.clear_row(r);
        }
    }

    /// Clear from cursor to end of screen using the active background color.
    pub fn clear_screen_below_with_bg(&mut self, col: usize, row: usize, bg: Color) {
        self.clear_screen_below_with_bg_source(col, row, bg, false);
    }

    pub(crate) fn clear_screen_below_with_bg_source(
        &mut self,
        col: usize,
        row: usize,
        bg: Color,
        bg_is_default: bool,
    ) {
        self.clear_line_right_with_bg_source(col, row, bg, bg_is_default);
        for r in (row + 1)..self.rows {
            self.clear_row_with_bg_source(r, bg, bg_is_default);
        }
    }

    /// Clear from beginning of screen to cursor
    pub fn clear_screen_above(&mut self, col: usize, row: usize) {
        for r in 0..row {
            self.clear_row(r);
        }
        self.clear_line_left(col, row);
    }

    /// Clear from beginning of screen to cursor using the active background color.
    pub fn clear_screen_above_with_bg(&mut self, col: usize, row: usize, bg: Color) {
        self.clear_screen_above_with_bg_source(col, row, bg, false);
    }

    pub(crate) fn clear_screen_above_with_bg_source(
        &mut self,
        col: usize,
        row: usize,
        bg: Color,
        bg_is_default: bool,
    ) {
        for r in 0..row {
            self.clear_row_with_bg_source(r, bg, bg_is_default);
        }
        self.clear_line_left_with_bg_source(col, row, bg, bg_is_default);
    }

    /// Erase characters at (col, row)
    pub fn erase_characters(&mut self, col: usize, row: usize, n: usize) {
        self.clear_multicells_intersecting(col, col.saturating_add(n), row, row.saturating_add(1));
        let blank_cell = self.blank_cell();
        if let Some(range) = self.wide_safe_range(col, row, n) {
            for c in range {
                if let Some(cell) = self.get_mut(c, row) {
                    *cell = blank_cell.clone();
                }
            }
        }
    }

    /// Erase characters at (col, row) using the active background color.
    pub fn erase_characters_with_bg(&mut self, col: usize, row: usize, n: usize, bg: Color) {
        self.erase_characters_with_bg_source(col, row, n, bg, false);
    }

    pub(crate) fn erase_characters_with_bg_source(
        &mut self,
        col: usize,
        row: usize,
        n: usize,
        bg: Color,
        bg_is_default: bool,
    ) {
        self.clear_multicells_intersecting(col, col.saturating_add(n), row, row.saturating_add(1));
        let blank = self.blank_cell_with_bg_source(bg, bg_is_default);
        if let Some(range) = self.wide_safe_range(col, row, n) {
            for c in range {
                if let Some(cell) = self.get_mut(c, row) {
                    *cell = blank.clone();
                }
            }
        }
    }

    /// Alias for erase_characters
    pub fn erase_chars(&mut self, col: usize, row: usize, n: usize) {
        self.erase_characters(col, row, n);
    }

    /// Clear the scrollback buffer
    pub fn clear_scrollback(&mut self) {
        // Absolute row mappings are invalid once the retained history and its
        // origin are discarded. Queue every zone for a typed eviction event
        // rather than leaving stale marks pointing into the new row epoch.
        self.invalidate_zones();
        self.scrollback_cells.clear();
        self.scrollback_start = 0;
        self.scrollback_lines = 0;
        self.scrollback_wrapped.clear();
        self.total_lines_scrolled = 0;
        self.sanitize_multicell_fragments();
        self.damage.mark_full_repaint("clear_scrollback");
    }
}
