//! Erase-related CSI sequence handling

use crate::debug;
use crate::terminal::Terminal;
use vte::Params;

impl Terminal {
    pub(crate) fn handle_csi_erase(
        &mut self,
        action: char,
        params: &Params,
        _intermediates: &[u8],
    ) {
        match action {
            'J' => {
                // Erase in display (ED)
                let n = params
                    .iter()
                    .next()
                    .and_then(|p| p.first())
                    .copied()
                    .unwrap_or(0);
                let cursor_col = self.cursor.col;
                let cursor_row = self.cursor.row;
                let erase_bg = self.bg;
                let erase_bg_is_default = self.flags.bg_is_default();
                match n {
                    0 => {
                        self.active_grid_mut().clear_screen_below_with_bg_source(
                            cursor_col,
                            cursor_row,
                            erase_bg,
                            erase_bg_is_default,
                        );
                        self.delete_graphics_below_cursor(cursor_col, cursor_row);
                    }
                    1 => {
                        self.active_grid_mut().clear_screen_above_with_bg_source(
                            cursor_col,
                            cursor_row,
                            erase_bg,
                            erase_bg_is_default,
                        );
                        self.delete_graphics_above_cursor(cursor_col, cursor_row);
                    }
                    2 => {
                        self.active_grid_mut().clear();
                        self.clear_graphics();
                        self.terminal_events
                            .push(crate::terminal::TerminalEvent::ScreenCleared {
                                include_scrollback: false,
                            });
                        debug::log(
                            debug::DebugLevel::Debug,
                            "CLEAR",
                            "Cleared screen and graphics (ED 2)",
                        );
                    }
                    3 => {
                        self.active_grid_mut().clear_scrollback();
                        if !self.alt_screen_active {
                            self.graphics_store.clear_scrollback_graphics();
                            self.clear_iterm_blocks();
                        }
                        self.terminal_events
                            .push(crate::terminal::TerminalEvent::ScreenCleared {
                                include_scrollback: true,
                            });
                        debug::log(
                            debug::DebugLevel::Debug,
                            "CLEAR",
                            "Cleared scrollback and scrollback graphics (ED 3)",
                        );
                    }
                    _ => {}
                }
            }
            'K' => {
                // Erase in line (EL)
                let n = params
                    .iter()
                    .next()
                    .and_then(|p| p.first())
                    .copied()
                    .unwrap_or(0);
                let cursor_col = self.cursor.col;
                let cursor_row = self.cursor.row;
                let erase_bg = self.bg;
                let erase_bg_is_default = self.flags.bg_is_default();
                match n {
                    0 => {
                        self.active_grid_mut().clear_line_right_with_bg_source(
                            cursor_col,
                            cursor_row,
                            erase_bg,
                            erase_bg_is_default,
                        );
                        self.delete_graphics_in_rect(
                            cursor_col,
                            cursor_row,
                            self.active_grid().cols(),
                            cursor_row.saturating_add(1),
                        );
                    }
                    1 => {
                        self.active_grid_mut().clear_line_left_with_bg_source(
                            cursor_col,
                            cursor_row,
                            erase_bg,
                            erase_bg_is_default,
                        );
                        self.delete_graphics_in_rect(
                            0,
                            cursor_row,
                            cursor_col.saturating_add(1),
                            cursor_row.saturating_add(1),
                        );
                    }
                    2 => {
                        self.active_grid_mut().clear_row_with_bg_source(
                            cursor_row,
                            erase_bg,
                            erase_bg_is_default,
                        );
                        self.delete_graphics_in_rect(
                            0,
                            cursor_row,
                            self.active_grid().cols(),
                            cursor_row.saturating_add(1),
                        );
                    }
                    _ => {}
                }
            }
            'X' => {
                // Erase characters (ECH)
                let n = params
                    .iter()
                    .next()
                    .and_then(|p| p.first())
                    .copied()
                    .unwrap_or(1) as usize;
                let n = if n == 0 { 1 } else { n };
                let cursor_col = self.cursor.col;
                let cursor_row = self.cursor.row;
                let erase_bg = self.bg;
                let erase_bg_is_default = self.flags.bg_is_default();
                self.active_grid_mut().erase_characters_with_bg_source(
                    cursor_col,
                    cursor_row,
                    n,
                    erase_bg,
                    erase_bg_is_default,
                );
                self.delete_graphics_in_rect(
                    cursor_col,
                    cursor_row,
                    cursor_col.saturating_add(n),
                    cursor_row.saturating_add(1),
                );
            }
            _ => {}
        }
    }

    fn delete_graphics_below_cursor(&mut self, cursor_col: usize, cursor_row: usize) {
        let cols = self.active_grid().cols();
        let rows = self.active_grid().rows();
        self.delete_graphics_in_rect(cursor_col, cursor_row, cols, cursor_row.saturating_add(1));
        self.delete_graphics_in_rect(0, cursor_row.saturating_add(1), cols, rows);
    }

    fn delete_graphics_above_cursor(&mut self, cursor_col: usize, cursor_row: usize) {
        let cols = self.active_grid().cols();
        self.delete_graphics_in_rect(0, 0, cols, cursor_row);
        self.delete_graphics_in_rect(
            0,
            cursor_row,
            cursor_col.saturating_add(1),
            cursor_row.saturating_add(1),
        );
    }

    pub(crate) fn delete_graphics_in_rect(
        &mut self,
        start_col: usize,
        start_row: usize,
        end_col: usize,
        end_row: usize,
    ) {
        let cols = self.active_grid().cols();
        let rows = self.active_grid().rows();
        let start_col = start_col.min(cols);
        let start_row = start_row.min(rows);
        let end_col = end_col.min(cols);
        let end_row = end_row.min(rows);
        self.graphics_store
            .delete_graphics_intersecting_rect_for_screen(
                start_col,
                start_row,
                end_col,
                end_row,
                self.alt_screen_active,
            );
    }

    /// DECSCA - Select Character Protection Attribute
    /// CSI Ps " q
    /// Ps = 0 or 2: disable protection, Ps = 1: enable protection
    pub(crate) fn handle_decsca(&mut self, params: &Params) {
        let ps = params
            .iter()
            .next()
            .and_then(|p| p.first())
            .copied()
            .unwrap_or(0);
        match ps {
            1 => {
                self.char_protected = true;
                debug::log(debug::DebugLevel::Debug, "DECSCA", "Protection enabled");
            }
            0 | 2 => {
                self.char_protected = false;
                debug::log(debug::DebugLevel::Debug, "DECSCA", "Protection disabled");
            }
            _ => {}
        }
    }

    /// DECSERA - Selective Erase Rectangular Area
    /// CSI Pt ; Pl ; Pb ; Pr $ {
    /// Erases characters in the specified rectangle that are NOT protected (guarded)
    pub(crate) fn handle_decsera(&mut self, params: &Params) {
        let params_vec: Vec<u16> = params
            .iter()
            .flat_map(|subparams| subparams.iter().copied())
            .collect();

        // Parameters: top, left, bottom, right (1-indexed, default to full screen)
        let top = params_vec.first().copied().unwrap_or(1).max(1) as usize - 1;
        let left = params_vec.get(1).copied().unwrap_or(1).max(1) as usize - 1;
        let bottom = params_vec
            .get(2)
            .copied()
            .map(|v| {
                if v == 0 {
                    self.active_grid().rows() as u16
                } else {
                    v
                }
            })
            .unwrap_or(self.active_grid().rows() as u16) as usize
            - 1;
        let right = params_vec
            .get(3)
            .copied()
            .map(|v| {
                if v == 0 {
                    self.active_grid().cols() as u16
                } else {
                    v
                }
            })
            .unwrap_or(self.active_grid().cols() as u16) as usize
            - 1;

        let rows = self.active_grid().rows();
        let cols = self.active_grid().cols();
        let bottom = bottom.min(rows - 1);
        let right = right.min(cols - 1);

        // First pass: collect which cells to erase (unprotected only)
        let mut to_erase: Vec<(usize, usize)> = Vec::new();
        for row in top..=bottom {
            if let Some(cells) = self.active_grid().row(row) {
                for (col, cell) in cells.iter().enumerate().take(right + 1).skip(left) {
                    if !cell.flags.guarded() {
                        to_erase.push((col, row));
                    }
                }
            }
        }
        // Second pass: erase the collected cells
        let blank_cell = self.active_grid().blank_cell();
        for &(col, row) in &to_erase {
            if let Some(cells) = self.active_grid_mut().row_mut(row) {
                cells[col] = blank_cell.clone();
            }
        }
        for &(col, row) in &to_erase {
            self.delete_graphics_in_rect(col, row, col.saturating_add(1), row.saturating_add(1));
        }

        debug::log(
            debug::DebugLevel::Debug,
            "DECSERA",
            &format!(
                "Selective erase rect ({},{}) to ({},{})",
                left, top, right, bottom
            ),
        );
    }
}
