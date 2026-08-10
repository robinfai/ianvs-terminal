//! Kitty OSC 66 multicell text placement.

use crate::cell::{Cell, MultiCell};
use crate::debug;
use crate::terminal::Terminal;

impl Terminal {
    fn advance_multicell_line(&mut self) {
        let (cols, rows) = self.size();
        if rows == 0 {
            return;
        }
        let current_row = self.cursor.row;
        self.active_grid_mut().set_line_wrapped(current_row, true);
        self.mark_row_dirty(current_row);
        self.cursor.col = if self.use_lr_margins {
            self.left_margin.min(cols.saturating_sub(1))
        } else {
            0
        };
        if self.cursor.row == self.scroll_region_bottom {
            let top = self.scroll_region_top;
            let bottom = self.scroll_region_bottom;
            debug::log_scroll("osc66-wrap", top, bottom, 1);
            self.active_grid_mut().scroll_region_up(1, top, bottom);
            self.adjust_graphics_for_scroll_up(1, top, bottom);
        } else {
            self.cursor.row = self.cursor.row.saturating_add(1).min(rows - 1);
        }
        self.pending_wrap = false;
    }

    fn prepare_multicell_write_position(&mut self, required_width: usize) -> bool {
        let (cols, rows) = self.size();
        if cols == 0 || rows == 0 || required_width == 0 || required_width > cols {
            return false;
        }

        for _ in 0..cols.saturating_mul(rows).saturating_add(1) {
            if self.pending_wrap {
                self.advance_multicell_line();
            }

            if self.cursor.col.saturating_add(required_width) > cols {
                let trailing_start = cols.saturating_sub(required_width);
                let lower_row_blocked =
                    self.active_grid()
                        .row(self.cursor.row)
                        .is_some_and(|row_cells| {
                            row_cells[trailing_start..cols]
                                .iter()
                                .any(|cell| cell.multicell.is_some_and(|metadata| metadata.y > 0))
                        });
                if self.auto_wrap || lower_row_blocked {
                    self.advance_multicell_line();
                    continue;
                }
                self.cursor.col = trailing_start;
            }

            let start = self.cursor.col;
            let end = start + required_width;
            let blocking_end = self
                .active_grid()
                .row(self.cursor.row)
                .and_then(|row_cells| {
                    row_cells[start..end]
                        .iter()
                        .enumerate()
                        .filter_map(|(offset, cell)| {
                            let metadata = cell.multicell?;
                            (metadata.y > 0).then(|| {
                                start
                                    .saturating_add(offset)
                                    .saturating_sub(metadata.x as usize)
                                    .saturating_add(metadata.block_width())
                            })
                        })
                        .max()
                });
            if let Some(blocking_end) = blocking_end {
                self.cursor.col = blocking_end.min(cols);
                if self.cursor.col.saturating_add(required_width) > cols {
                    self.advance_multicell_line();
                }
                continue;
            }

            if self
                .active_grid()
                .get(self.cursor.col, self.cursor.row)
                .is_some_and(|cell| cell.multicell.is_some())
            {
                let cursor_col = self.cursor.col;
                let cursor_row = self.cursor.row as isize;
                self.active_grid_mut()
                    .clear_multicell_at(cursor_col, cursor_row);
            }
            return true;
        }
        false
    }

    pub(super) fn prepare_normal_write_position(&mut self, required_width: usize) {
        let (cols, rows) = self.size();
        if cols == 0 || rows == 0 || required_width == 0 {
            return;
        }
        for _ in 0..cols.saturating_mul(rows).saturating_add(1) {
            let start = self.cursor.col.min(cols - 1);
            let end = start.saturating_add(required_width).min(cols);
            let lower_block_end = self
                .active_grid()
                .row(self.cursor.row)
                .and_then(|row_cells| {
                    row_cells[start..end]
                        .iter()
                        .enumerate()
                        .filter_map(|(offset, cell)| {
                            let metadata = cell.multicell?;
                            (metadata.y > 0).then(|| {
                                start
                                    .saturating_add(offset)
                                    .saturating_sub(metadata.x as usize)
                                    .saturating_add(metadata.block_width())
                            })
                        })
                        .max()
                });
            if let Some(lower_block_end) = lower_block_end {
                self.cursor.col = lower_block_end.min(cols);
                if self.cursor.col.saturating_add(required_width) > cols {
                    self.advance_multicell_line();
                }
                continue;
            }

            let mut top_row_cells = Vec::new();
            if let Some(row_cells) = self.active_grid().row(self.cursor.row) {
                for (col, cell) in row_cells.iter().enumerate().take(end).skip(start) {
                    if cell.multicell.is_some_and(|metadata| metadata.y == 0) {
                        top_row_cells.push(col);
                    }
                }
            }
            for col in top_row_cells {
                let row = self.cursor.row as isize;
                self.active_grid_mut().clear_multicell_at(col, row);
            }
            return;
        }
    }

    pub(super) fn append_combining_to_multicell(
        &mut self,
        col: usize,
        row: usize,
        character: char,
    ) -> bool {
        self.active_grid_mut()
            .append_multicell_text_at(col, row as isize, character)
    }

    pub(crate) fn write_multicell_block(&mut self, text: &str, metadata: MultiCell) {
        if text.is_empty() || !metadata.is_anchor() {
            return;
        }
        let (cols, rows) = self.size();
        let width = metadata.block_width();
        let height = metadata.block_height();
        if width == 0 || height == 0 || width > cols || height > rows {
            return;
        }
        if !self.prepare_multicell_write_position(width) {
            return;
        }

        if self.cursor.row.saturating_add(height) > rows {
            let extra = self.cursor.row.saturating_add(height) - rows;
            let top = self.scroll_region_top;
            let bottom = self.scroll_region_bottom;
            if extra > bottom.saturating_sub(top).saturating_add(1) {
                return;
            }
            self.active_grid_mut().scroll_region_up(extra, top, bottom);
            self.adjust_graphics_for_scroll_up(extra, top, bottom);
            self.cursor.row = self.cursor.row.saturating_sub(extra);
        }

        self.commit_deferred_kitty_deletes_for_visual_output();
        let anchor_col = self.cursor.col;
        let anchor_row = self.cursor.row;
        self.active_grid_mut().clear_multicells_intersecting(
            anchor_col,
            anchor_col + width,
            anchor_row,
            anchor_row + height,
        );

        if self.insert_mode {
            for row in anchor_row..anchor_row + height {
                self.active_grid_mut().insert_chars(anchor_col, row, width);
                self.graphics_store.adjust_for_insert_characters_for_screen(
                    width,
                    anchor_col,
                    row,
                    cols,
                    self.alt_screen_active,
                );
            }
        }

        let mut flags = self.flags;
        flags.hyperlink_id = self.current_hyperlink_id;
        flags.set_guarded(self.char_protected);
        flags.set_wide_char(false);
        flags.set_wide_char_spacer(false);
        let mut chars = text.chars();
        let base = chars.next().unwrap_or(' ');
        let rest = chars.collect::<Vec<_>>();
        let fg = self.fg;
        let bg = self.bg;
        let underline_color = self.underline_color;

        for block_y in 0..height {
            for block_x in 0..width {
                let is_anchor = block_x == 0 && block_y == 0;
                let mut cell_metadata = metadata;
                cell_metadata.x = block_x as u8;
                cell_metadata.y = block_y as u8;
                let cell = Cell {
                    c: if is_anchor { base } else { ' ' },
                    combining: if is_anchor { rest.clone() } else { Vec::new() },
                    fg,
                    bg,
                    underline_color,
                    flags,
                    width: if is_anchor { width as u8 } else { 1 },
                    multicell: Some(cell_metadata),
                };
                self.active_grid_mut()
                    .set(anchor_col + block_x, anchor_row + block_y, cell);
            }
            self.mark_row_dirty(anchor_row + block_y);
        }

        self.cursor.col = self.cursor.col.saturating_add(width);
        if self.cursor.col >= cols {
            self.cursor.col = cols - 1;
            self.pending_wrap = self.auto_wrap;
        }
    }
}
