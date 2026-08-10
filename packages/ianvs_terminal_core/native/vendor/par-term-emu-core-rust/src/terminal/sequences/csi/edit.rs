//! Edit-related CSI sequence handling (insertion/deletion)

use crate::terminal::Terminal;
use vte::Params;

impl Terminal {
    pub(crate) fn handle_csi_edit(&mut self, action: char, params: &Params, _intermediates: &[u8]) {
        let (cols, _rows) = self.size();
        let cursor_row = self.cursor.row;
        let scroll_top = self.scroll_region_top;
        let scroll_bottom = self.scroll_region_bottom;

        match action {
            'L' => {
                // Insert line (IL)
                let n = params
                    .iter()
                    .next()
                    .and_then(|p| p.first())
                    .copied()
                    .unwrap_or(1) as usize;
                let n = if n == 0 { 1 } else { n };
                // Insert lines within current scroll region if cursor is inside it
                if cursor_row >= scroll_top && cursor_row <= scroll_bottom {
                    let effective_n = n.min(scroll_bottom - cursor_row + 1);
                    self.active_grid_mut()
                        .insert_lines(n, cursor_row, scroll_bottom);
                    self.graphics_store.adjust_for_insert_lines_for_screen(
                        effective_n,
                        cursor_row,
                        scroll_bottom,
                        self.alt_screen_active,
                    );
                }
            }
            'M' => {
                // Delete line (DL)
                let n = params
                    .iter()
                    .next()
                    .and_then(|p| p.first())
                    .copied()
                    .unwrap_or(1) as usize;
                let n = if n == 0 { 1 } else { n };
                // Delete lines within current scroll region if cursor is inside it
                if cursor_row >= scroll_top && cursor_row <= scroll_bottom {
                    let effective_n = n.min(scroll_bottom - cursor_row + 1);
                    self.active_grid_mut()
                        .delete_lines(n, cursor_row, scroll_bottom);
                    self.graphics_store.adjust_for_delete_lines_for_screen(
                        effective_n,
                        cursor_row,
                        scroll_bottom,
                        self.alt_screen_active,
                    );
                }
            }
            '@' => {
                // Insert characters (ICH)
                let n = params
                    .iter()
                    .next()
                    .and_then(|p| p.first())
                    .copied()
                    .unwrap_or(1) as usize;
                let n = if n == 0 { 1 } else { n };
                let cursor_col = self.cursor.col;
                self.active_grid_mut()
                    .insert_characters(cursor_col, cursor_row, n);
                self.graphics_store.adjust_for_insert_characters_for_screen(
                    n,
                    cursor_col,
                    cursor_row,
                    cols,
                    self.alt_screen_active,
                );
            }
            'P' => {
                // Delete characters (DCH)
                let n = params
                    .iter()
                    .next()
                    .and_then(|p| p.first())
                    .copied()
                    .unwrap_or(1) as usize;
                let n = if n == 0 { 1 } else { n };
                let cursor_col = self.cursor.col;
                self.active_grid_mut()
                    .delete_characters(cursor_col, cursor_row, n);
                self.graphics_store.adjust_for_delete_characters_for_screen(
                    n,
                    cursor_col,
                    cursor_row,
                    cols,
                    self.alt_screen_active,
                );
            }
            _ => {}
        }
    }
}
