//! Character writing and text output
//!
//! Handles character output including:
//! - Special character handling (CR, LF, TAB, BS)
//! - Wide character support (emoji, CJK)
//! - Auto-wrap mode (DECAWM)
//! - Scrolling behavior
//! - Insert mode
//! - Character attributes and hyperlinks
//! - Grapheme clusters (variation selectors, ZWJ, skin tone modifiers, regional indicators)

use crate::cell::Cell;
use crate::debug;
use crate::grapheme;
use crate::terminal::Terminal;

impl Terminal {
    /// Fast path for chunks known to contain only printable ASCII plus simple C0 controls.
    pub(super) fn write_plain_ascii_fast_path(&mut self, data: &[u8]) {
        let mut index = 0;
        while index < data.len() {
            match data[index] {
                b'\n' | b'\r' | b'\t' | b'\x08' => {
                    self.record_execute_debug_stats(data[index]);
                    self.write_char(data[index] as char);
                    index += 1;
                }
                0x20..=0x7e => {
                    let start = index;
                    while index < data.len() && matches!(data[index], 0x20..=0x7e) {
                        index += 1;
                    }
                    self.write_plain_ascii_printable_run(&data[start..index]);
                }
                _ => {
                    index += 1;
                }
            }
        }
    }

    fn write_plain_ascii_printable_run(&mut self, bytes: &[u8]) {
        if self.active_grid().has_multicells() {
            for byte in bytes {
                self.write_char(*byte as char);
            }
            return;
        }
        self.commit_deferred_kitty_deletes_for_visual_output();
        let mut index = 0;
        while index < bytes.len() {
            if self.pending_wrap {
                self.advance_pending_wrap_for_plain_ascii();
            }

            let (cols, _rows) = self.size();
            if cols == 0 {
                return;
            }

            let cursor_col = self.cursor.col.min(cols - 1);
            let cursor_row = self.cursor.row;
            let writable = (cols - cursor_col).min(bytes.len() - index);
            if writable == 0 {
                return;
            }

            self.clear_wide_fragments_for_write(cursor_col, cursor_row, writable);

            let mut cell_flags = self.flags;
            cell_flags.hyperlink_id = self.current_hyperlink_id;
            cell_flags.set_guarded(self.char_protected);
            let fg = self.fg;
            let bg = self.bg;
            let underline_color = self.underline_color;

            if let Some(row_cells) = self.active_grid_mut().row_mut(cursor_row) {
                for offset in 0..writable {
                    row_cells[cursor_col + offset] = Cell {
                        c: bytes[index + offset] as char,
                        combining: Vec::new(),
                        fg,
                        bg,
                        underline_color,
                        flags: cell_flags,
                        width: 1,
                        multicell: None,
                    };
                }
            }
            self.mark_row_dirty(cursor_row);
            self.record_print_debug_count(writable);

            self.cursor.col = cursor_col + writable;
            index += writable;
            if self.cursor.col >= cols {
                self.cursor.col = cols - 1;
                self.pending_wrap = true;
            }
        }
    }

    fn advance_pending_wrap_for_plain_ascii(&mut self) {
        let (cols, rows) = self.size();
        let current_row = self.cursor.row;
        self.active_grid_mut().set_line_wrapped(current_row, true);
        self.mark_row_dirty(current_row);
        self.cursor.col = 0;
        if self.cursor.row == self.scroll_region_bottom {
            let scroll_top = self.scroll_region_top;
            let scroll_bottom = self.scroll_region_bottom;
            debug::log_scroll("plain-ascii-wrap-advance", scroll_top, scroll_bottom, 1);
            self.active_grid_mut()
                .scroll_region_up(1, scroll_top, scroll_bottom);
            self.adjust_graphics_for_scroll_up(1, scroll_top, scroll_bottom);
        } else {
            self.cursor.row += 1;
            if self.cursor.row >= rows {
                self.cursor.row = rows.saturating_sub(1);
            }
        }
        if cols == 0 {
            self.cursor.col = 0;
        }
        self.pending_wrap = false;
    }

    /// Write a character to the terminal at the current cursor position
    pub(super) fn write_char(&mut self, c: char) {
        // Apply ACS (Alternate Character Set) translation when the active charset
        // is DEC Special / Line Drawing.  Only printable ASCII chars are mapped;
        // control characters pass through unchanged so CR/LF/etc. still work.
        let c = if c.is_ascii_graphic() {
            self.active_charset().translate(c)
        } else {
            c
        };

        if !c.is_control() {
            self.commit_deferred_kitty_deletes_for_visual_output();
        }

        let (cols, _rows) = self.size();

        // Handle regional indicator pairs (flag emoji like 🇺🇸)
        // When the second regional indicator arrives, combine it with the first
        if grapheme::is_regional_indicator(c) {
            let Some((target_col, target_row)) = self.previous_grapheme_cell_position(cols) else {
                // At position (0, 0), this is the first regional indicator
                // Continue to write it as a normal character below
                return self.write_regional_indicator_first(c, cols);
            };

            // Check if previous cell is a regional indicator without a pair yet
            let should_combine = if let Some(target_cell) =
                self.active_grid().get(target_col, target_row)
            {
                grapheme::is_regional_indicator(target_cell.c) && target_cell.combining.is_empty()
            } else {
                false
            };

            if should_combine {
                // Extract cursor position before mutable borrow
                let cursor_row = self.cursor.row;

                let can_wrap_widened = self.auto_wrap && cols >= 2;
                let mut wrapped_wide_cell = None;
                let mut grown_wide_cell = None;

                // Previous cell is a lone regional indicator - combine them
                if let Some(target_cell) = self.active_grid_mut().get_mut(target_col, target_row) {
                    target_cell.combining.push(c);
                    target_cell.width = 2;
                    target_cell.flags.set_wide_char(true);
                    if target_col + 1 >= cols && can_wrap_widened {
                        wrapped_wide_cell = Some(target_cell.clone());
                    } else if target_col + 1 < cols {
                        grown_wide_cell = Some(target_cell.clone());
                    }
                }

                if let Some(cell) = wrapped_wide_cell {
                    self.wrap_widened_grapheme_from_right_edge(target_col, target_row, cell);
                    return;
                }

                if let Some(cell) = grown_wide_cell {
                    self.write_wide_spacer_for_grown_cell(target_col, target_row, &cell);
                }

                // Advance cursor past the spacer
                self.cursor.col += 1;
                if self.cursor.col >= cols {
                    if self.auto_wrap {
                        self.cursor.col = cols - 1;
                        self.pending_wrap = true;
                    } else {
                        self.cursor.col = cols - 1;
                    }
                }

                self.mark_row_dirty(target_row);
                if cursor_row != target_row {
                    self.mark_row_dirty(cursor_row);
                }
                return;
            }
            // Previous cell is not a lone regional indicator
            // Continue to write this as the first of a new pair
            return self.write_regional_indicator_first(c, cols);
        }

        // Handle combining characters and zero-width grapheme modifiers
        // (variation selectors, ZWJ, skin tone modifiers, emoji tags).
        // These should be added to the previous cell instead of creating a new cell
        if grapheme::is_variation_selector(c)
            || grapheme::is_zwj(c)
            || grapheme::is_zero_width_format(c)
            || grapheme::is_skin_tone_modifier(c)
            || grapheme::is_emoji_tag(c)
            || grapheme::is_combining_mark(c)
        {
            let Some((target_col, target_row)) = self.previous_grapheme_cell_position(cols) else {
                return;
            };

            if self
                .active_grid()
                .get(target_col, target_row)
                .is_some_and(|cell| cell.multicell.is_some())
            {
                self.append_combining_to_multicell(target_col, target_row, c);
                return;
            }

            // Copy normalization form before mutable borrow
            let norm_form = self.normalization_form;
            let width_config = self.width_config;
            let cursor_should_advance_after_width_growth =
                self.cursor.row == target_row && self.cursor.col == target_col + 1;
            let mut advanced_width = false;
            let can_wrap_widened = self.auto_wrap && cols >= 2;
            let mut wrapped_wide_cell = None;
            let mut grown_wide_cell = None;

            // Add combining character to the target cell
            if let Some(target_cell) = self.active_grid_mut().get_mut(target_col, target_row) {
                target_cell.combining.push(c);

                // Apply Unicode normalization if NFC or NFKC (composition forms)
                // This composes base + combining into precomposed form when possible
                if matches!(
                    norm_form,
                    crate::unicode_normalization_config::NormalizationForm::NFC
                        | crate::unicode_normalization_config::NormalizationForm::NFKC
                ) {
                    let grapheme = target_cell.get_grapheme();
                    let normalized = norm_form.normalize(&grapheme);
                    let mut chars = normalized.chars();
                    if let Some(base) = chars.next() {
                        target_cell.c = base;
                        target_cell.combining = chars.collect();
                    }
                }

                // Recalculate width if needed (e.g., emoji with variation selector)
                let grapheme = target_cell.get_grapheme();
                let new_width = grapheme::is_wide_grapheme_with_config(&grapheme, &width_config);
                if new_width && target_cell.width() == 1 {
                    target_cell.width = 2;
                    target_cell.flags.set_wide_char(true);
                    advanced_width = cursor_should_advance_after_width_growth;

                    if target_col + 1 < cols {
                        grown_wide_cell = Some(target_cell.clone());
                    } else if can_wrap_widened {
                        wrapped_wide_cell = Some(target_cell.clone());
                    }
                }

                self.mark_row_dirty(target_row);
            }
            if let Some(cell) = wrapped_wide_cell {
                self.wrap_widened_grapheme_from_right_edge(target_col, target_row, cell);
                return;
            }
            if let Some(cell) = grown_wide_cell {
                self.write_wide_spacer_for_grown_cell(target_col, target_row, &cell);
            }
            if advanced_width {
                self.cursor.col += 1;
                if self.cursor.col >= cols {
                    self.cursor.col = cols.saturating_sub(1);
                    if self.auto_wrap {
                        self.pending_wrap = true;
                    }
                }
            }
            return;
        }

        // Check if previous cell has ZWJ - if so, this char is part of ZWJ sequence
        // and should be added as combining character (e.g., 👨 + ZWJ + 💻 = 👨‍💻)
        // OPTIMIZATION: Only check for emoji characters (most text won't trigger this)
        let char_code = c as u32;
        let is_potential_emoji = matches!(char_code,
            0x2600..=0x27BF  // Misc Symbols (❤️, ☀️, etc.)
            | 0x1F000..=0x1FFFF // Emoji blocks
        );

        if is_potential_emoji && (self.cursor.col > 0 || self.cursor.row > 0) {
            let Some((target_col, target_row)) = self.previous_grapheme_cell_position(cols) else {
                return;
            };

            if let Some(rect) = self
                .active_grid()
                .multicell_rect_at(target_col, target_row as isize)
            {
                let continues_multicell = self
                    .active_grid()
                    .relative_row(rect.anchor_row)
                    .and_then(|row_cells| row_cells.get(rect.anchor_col))
                    .is_some_and(|anchor| anchor.get_grapheme().ends_with('\u{200D}'));
                if continues_multicell {
                    self.append_combining_to_multicell(target_col, target_row, c);
                    return;
                }
            }

            // Check if target cell has ZWJ in combining chars
            if let Some(target_cell) = self.active_grid().get(target_col, target_row) {
                if target_cell.combining.contains(&'\u{200D}') {
                    let width_config = self.width_config;
                    let cursor_should_advance_after_width_growth =
                        self.cursor.row == target_row && self.cursor.col == target_col + 1;
                    let mut advanced_width = false;
                    let can_wrap_widened = self.auto_wrap && cols >= 2;
                    let mut wrapped_wide_cell = None;
                    let mut grown_wide_cell = None;
                    // Previous cell has ZWJ, add current char as combining
                    if let Some(target_cell_mut) =
                        self.active_grid_mut().get_mut(target_col, target_row)
                    {
                        target_cell_mut.combining.push(c);

                        // Recalculate width if needed
                        let grapheme = target_cell_mut.get_grapheme();
                        let new_width =
                            grapheme::is_wide_grapheme_with_config(&grapheme, &width_config);
                        if new_width && target_cell_mut.width() == 1 {
                            target_cell_mut.width = 2;
                            target_cell_mut.flags.set_wide_char(true);
                            advanced_width = cursor_should_advance_after_width_growth;

                            if target_col + 1 < cols {
                                grown_wide_cell = Some(target_cell_mut.clone());
                            } else if can_wrap_widened {
                                wrapped_wide_cell = Some(target_cell_mut.clone());
                            }
                        }

                        self.mark_row_dirty(target_row);
                    }
                    if let Some(cell) = wrapped_wide_cell {
                        self.wrap_widened_grapheme_from_right_edge(target_col, target_row, cell);
                        return;
                    }
                    if let Some(cell) = grown_wide_cell {
                        self.write_wide_spacer_for_grown_cell(target_col, target_row, &cell);
                    }
                    if advanced_width {
                        self.cursor.col += 1;
                        if self.cursor.col >= cols {
                            self.cursor.col = cols.saturating_sub(1);
                            if self.auto_wrap {
                                self.pending_wrap = true;
                            }
                        }
                    }
                    return;
                }
            }
        }

        // Handle special characters
        match c {
            '\r' => {
                // Carriage return moves to left margin when DECLRMM is enabled
                if self.use_lr_margins {
                    self.cursor.col = self.left_margin.min(cols.saturating_sub(1));
                } else {
                    self.cursor.move_to_line_start();
                }
                // CR clears pending wrap
                self.pending_wrap = false;
                return;
            }
            '\n' => {
                // LNM (Line Feed/New Line Mode): when enabled, LF does CR+LF
                if self.line_feed_new_line_mode {
                    // Do carriage return first
                    if self.use_lr_margins {
                        self.cursor.col = self.left_margin.min(cols.saturating_sub(1));
                    } else {
                        self.cursor.move_to_line_start();
                    }
                }
                // VT spec behavior: Line feed moves cursor down. If at bottom of scroll region, scroll the region.
                // Per VT220 manual: "Index (IND) moves the cursor down one line in the same column.
                // If the cursor is at the bottom margin, the screen performs a scroll up."
                let (_, rows) = self.size();
                let in_scroll_region = self.cursor.row >= self.scroll_region_top
                    && self.cursor.row <= self.scroll_region_bottom;
                // If DECLRMM is enabled and the cursor is outside left/right margins,
                // ignore the scroll (match iTerm2 behavior) to avoid corrupting panes/status bars.
                let outside_lr_margin = self.use_lr_margins
                    && (self.cursor.col < self.left_margin || self.cursor.col > self.right_margin);

                if in_scroll_region
                    && self.cursor.row == self.scroll_region_bottom
                    && !outside_lr_margin
                {
                    // At bottom of scroll region - scroll the region per VT spec
                    // The scroll is confined to the region boundaries, preserving content outside it
                    let top = self.scroll_region_top;
                    let bottom = self.scroll_region_bottom;
                    debug::log_scroll("newline-at-scroll-bottom", top, bottom, 1);
                    self.active_grid_mut().scroll_region_up(1, top, bottom);
                    // Adjust graphics to scroll with content
                    self.adjust_graphics_for_scroll_up(1, top, bottom);
                    // Mark all rows in scroll region as dirty
                    for row in top..=bottom {
                        self.mark_row_dirty(row);
                    }
                    // Cursor stays at scroll_region_bottom per VT spec
                } else {
                    // Not at scroll region bottom, or outside region - just move cursor down
                    self.cursor.row += 1;
                    if self.cursor.row >= rows {
                        self.cursor.row = rows - 1;
                    }
                }
                // LF/IND semantics clear pending wrap
                self.pending_wrap = false;
                return;
            }
            '\t' => {
                // Tab to next tab stop
                let mut next_col = self.cursor.col + 1;
                while next_col < cols {
                    if self.tab_stops.get(next_col).copied().unwrap_or(false) {
                        break;
                    }
                    next_col += 1;
                }
                self.cursor.col = next_col.min(cols - 1);
                // Horizontal cursor movement clears pending wrap
                self.pending_wrap = false;
                return;
            }
            '\x08' => {
                // Backspace
                if self.cursor.col > 0 {
                    self.cursor.col -= 1;
                }
                // Horizontal movement clears pending wrap
                self.pending_wrap = false;
                return;
            }
            c if c.is_control() => {
                // Ignore other control characters
                return;
            }
            _ => {}
        }

        // Handle wide characters (emoji, CJK, etc.)
        let char_width = crate::unicode_width_config::char_width(c, &self.width_config);

        // If a wrap is pending from a prior write at the right margin, perform the wrap now
        if self.pending_wrap {
            let (cols, rows) = self.size();
            let was_outside_lr = self.use_lr_margins
                && (self.cursor.col < self.left_margin || self.cursor.col > self.right_margin);

            // Mark the current row as wrapped (line continues to next row)
            let current_row = self.cursor.row;
            self.active_grid_mut().set_line_wrapped(current_row, true);
            self.mark_row_dirty(current_row);

            // Move to left margin or column 0
            self.cursor.col = if self.use_lr_margins {
                self.left_margin.min(cols.saturating_sub(1))
            } else {
                0
            };
            if self.cursor.row == self.scroll_region_bottom && !was_outside_lr {
                let scroll_top = self.scroll_region_top;
                let scroll_bottom = self.scroll_region_bottom;
                debug::log_scroll("wrap-pending-advance", scroll_top, scroll_bottom, 1);
                self.active_grid_mut()
                    .scroll_region_up(1, scroll_top, scroll_bottom);
                // Adjust graphics to scroll with content
                self.adjust_graphics_for_scroll_up(1, scroll_top, scroll_bottom);
                // Cursor remains at bottom of region
            } else {
                self.cursor.row += 1;
                if self.cursor.row >= rows {
                    self.cursor.row = rows - 1;
                }
            }
            self.pending_wrap = false;
        }

        self.prepare_normal_write_position(char_width.max(1));

        // If wide character won't fit on current line, wrap first
        if char_width == 2 && self.cursor.col >= cols - 1 && self.auto_wrap {
            // Mark the current row as wrapped (line continues to next row)
            let current_row = self.cursor.row;
            self.active_grid_mut().set_line_wrapped(current_row, true);
            self.mark_row_dirty(current_row);

            // Wrap to left margin if DECLRMM is enabled
            self.cursor.col = if self.use_lr_margins {
                self.left_margin.min(cols.saturating_sub(1))
            } else {
                0
            };
            // VT spec behavior: scroll if at scroll region bottom
            let (_, rows) = self.size();
            let outside_lr_margin = self.use_lr_margins
                && (self.cursor.col < self.left_margin || self.cursor.col > self.right_margin);
            if self.cursor.row == self.scroll_region_bottom && !outside_lr_margin {
                let scroll_top = self.scroll_region_top;
                let scroll_bottom = self.scroll_region_bottom;
                self.active_grid_mut()
                    .scroll_region_up(1, scroll_top, scroll_bottom);
                // Adjust graphics to scroll with content
                self.adjust_graphics_for_scroll_up(1, scroll_top, scroll_bottom);
                // Cursor stays at scroll_region_bottom
            } else {
                self.cursor.row += 1;
                if self.cursor.row >= rows {
                    self.cursor.row = rows - 1;
                }
            }
        }

        // Write the character with appropriate wide_char flag
        let mut cell_flags = self.flags;
        if char_width == 2 {
            cell_flags.set_wide_char(true);
        }
        // Apply current hyperlink ID
        cell_flags.hyperlink_id = self.current_hyperlink_id;
        // Apply character protection (DECSCA)
        cell_flags.set_guarded(self.char_protected);

        let cell = Cell {
            c,
            combining: Vec::new(),
            fg: self.fg,
            bg: self.bg,
            underline_color: self.underline_color,
            flags: cell_flags,
            width: char_width as u8,
            multicell: None,
        };

        let cursor_col = self.cursor.col;
        let cursor_row = self.cursor.row;

        // If insert mode (IRM) is enabled, insert space by shifting chars right
        if self.insert_mode {
            self.active_grid_mut()
                .insert_chars(cursor_col, cursor_row, char_width);
            self.graphics_store.adjust_for_insert_characters_for_screen(
                char_width,
                cursor_col,
                cursor_row,
                cols,
                self.alt_screen_active,
            );
        } else {
            self.clear_wide_fragments_for_write(cursor_col, cursor_row, char_width.max(1));
        }

        self.active_grid_mut().set(cursor_col, cursor_row, cell);
        // Mark row as dirty for rendering
        self.mark_row_dirty(cursor_row);

        // Advance cursor by character width
        self.cursor.col += char_width;

        // If it's a wide character, fill the next cell with a spacer
        if char_width == 2 && self.cursor.col - 1 < cols {
            let mut spacer_flags = self.flags;
            spacer_flags.set_wide_char_spacer(true);
            // Apply hyperlink ID to spacer as well
            spacer_flags.hyperlink_id = self.current_hyperlink_id;

            let spacer = Cell {
                c: ' ', // Spacer character
                combining: Vec::new(),
                fg: self.fg,
                bg: self.bg,
                underline_color: self.underline_color,
                flags: spacer_flags,
                width: 1, // Spacers always have width 1
                multicell: None,
            };
            let spacer_col = self.cursor.col - 1;
            let spacer_row = self.cursor.row;
            self.active_grid_mut().set(spacer_col, spacer_row, spacer);
            // Spacer is on same row, already marked dirty above
        }

        // Handle delayed autowrap when the glyph reaches the right margin.
        if self.cursor.col >= cols {
            if self.auto_wrap {
                self.pending_wrap = true;
            }
            // Fallback: if auto-wrap is disabled or some edge case, clamp to last column
            self.cursor.col = cols - 1;
        }
    }

    fn blank_cell_for_current_write(&self) -> Cell {
        let mut flags = self.flags;
        flags.hyperlink_id = self.current_hyperlink_id;
        flags.set_guarded(self.char_protected);
        flags.set_wide_char(false);
        flags.set_wide_char_spacer(false);
        Cell {
            c: ' ',
            combining: Vec::new(),
            fg: self.fg,
            bg: self.bg,
            underline_color: self.underline_color,
            flags,
            width: 1,
            multicell: None,
        }
    }

    fn clear_wide_fragments_for_write(&mut self, col: usize, row: usize, width: usize) {
        if width == 0 {
            return;
        }
        let cols = self.active_grid().cols();
        let output_end = col.saturating_add(width).min(cols);
        let Some(range) = self.active_grid().wide_safe_range(col, row, width) else {
            return;
        };
        if range.start == col && range.end == output_end {
            return;
        }

        let blank = self.blank_cell_for_current_write();
        if let Some(row_cells) = self.active_grid_mut().row_mut(row) {
            for clear_col in range {
                if clear_col < col || clear_col >= output_end {
                    row_cells[clear_col] = blank.clone();
                }
            }
        }
    }

    fn previous_grapheme_cell_position(&self, cols: usize) -> Option<(usize, usize)> {
        if cols == 0 {
            return None;
        }

        let (candidate_col, candidate_row) = if self.pending_wrap {
            (self.cursor.col.min(cols.saturating_sub(1)), self.cursor.row)
        } else if self.cursor.col > 0 {
            (self.cursor.col - 1, self.cursor.row)
        } else if self.cursor.row > 0 {
            (cols - 1, self.cursor.row - 1)
        } else {
            return None;
        };

        let cell = self.active_grid().get(candidate_col, candidate_row)?;
        if !cell.flags.wide_char_spacer() {
            return Some((candidate_col, candidate_row));
        }

        if candidate_col > 0 {
            Some((candidate_col - 1, candidate_row))
        } else if candidate_row > 0 {
            Some((cols - 1, candidate_row - 1))
        } else {
            None
        }
    }

    fn wide_spacer_for_cell(cell: &Cell) -> Cell {
        let mut spacer_flags = cell.flags;
        spacer_flags.set_wide_char(false);
        spacer_flags.set_wide_char_spacer(true);
        Cell {
            c: ' ',
            combining: Vec::new(),
            fg: cell.fg,
            bg: cell.bg,
            underline_color: cell.underline_color,
            flags: spacer_flags,
            width: 1,
            multicell: None,
        }
    }

    fn write_wide_spacer_for_grown_cell(
        &mut self,
        target_col: usize,
        target_row: usize,
        cell: &Cell,
    ) {
        let cols = self.active_grid().cols();
        if target_col + 1 >= cols {
            return;
        }

        self.clear_wide_fragments_for_write(target_col, target_row, 2);
        let spacer = Self::wide_spacer_for_cell(cell);
        self.active_grid_mut()
            .set(target_col + 1, target_row, spacer);
        self.mark_row_dirty(target_row);
    }

    fn wrap_widened_grapheme_from_right_edge(
        &mut self,
        target_col: usize,
        target_row: usize,
        cell: Cell,
    ) {
        let (cols, rows) = self.size();
        if cols < 2 || rows == 0 {
            return;
        }

        self.active_grid_mut()
            .set(target_col, target_row, Cell::default());
        self.active_grid_mut().set_line_wrapped(target_row, true);
        self.mark_row_dirty(target_row);

        let in_scroll_region =
            target_row >= self.scroll_region_top && target_row <= self.scroll_region_bottom;
        let destination_row = if in_scroll_region && target_row == self.scroll_region_bottom {
            let scroll_top = self.scroll_region_top;
            let scroll_bottom = self.scroll_region_bottom;
            debug::log_scroll("wrap-widened-grapheme", scroll_top, scroll_bottom, 1);
            self.active_grid_mut()
                .scroll_region_up(1, scroll_top, scroll_bottom);
            self.adjust_graphics_for_scroll_up(1, scroll_top, scroll_bottom);
            scroll_bottom
        } else {
            target_row.saturating_add(1).min(rows - 1)
        };
        let destination_col = if self.use_lr_margins {
            self.left_margin.min(cols.saturating_sub(2))
        } else {
            0
        };

        let spacer = Self::wide_spacer_for_cell(&cell);
        self.active_grid_mut()
            .set(destination_col, destination_row, cell);
        self.active_grid_mut()
            .set(destination_col + 1, destination_row, spacer);
        self.mark_row_dirty(destination_row);

        let next_col = destination_col + 2;
        self.cursor.row = destination_row;
        self.cursor.col = next_col.min(cols - 1);
        self.pending_wrap = self.auto_wrap && next_col >= cols;
    }

    /// Write the first regional indicator of a potential flag pair.
    /// This is written as a width-1 character initially. If followed by another
    /// regional indicator, they will be combined into a width-2 flag emoji.
    fn write_regional_indicator_first(&mut self, c: char, cols: usize) {
        // If a wrap is pending from a prior write at the right margin, perform the wrap now
        if self.pending_wrap {
            let (_cols, rows) = self.size();
            let was_outside_lr = self.use_lr_margins
                && (self.cursor.col < self.left_margin || self.cursor.col > self.right_margin);

            // Mark the current row as wrapped (line continues to next row)
            let current_row = self.cursor.row;
            self.active_grid_mut().set_line_wrapped(current_row, true);
            self.mark_row_dirty(current_row);

            // Move to left margin or column 0
            self.cursor.col = if self.use_lr_margins {
                self.left_margin.min(cols.saturating_sub(1))
            } else {
                0
            };
            if self.cursor.row == self.scroll_region_bottom && !was_outside_lr {
                let scroll_top = self.scroll_region_top;
                let scroll_bottom = self.scroll_region_bottom;
                debug::log_scroll("wrap-pending-regional", scroll_top, scroll_bottom, 1);
                self.active_grid_mut()
                    .scroll_region_up(1, scroll_top, scroll_bottom);
                // Adjust graphics to scroll with content
                self.adjust_graphics_for_scroll_up(1, scroll_top, scroll_bottom);
                // Cursor remains at bottom of region
            } else {
                self.cursor.row += 1;
                if self.cursor.row >= rows {
                    self.cursor.row = rows - 1;
                }
            }
            self.pending_wrap = false;
        }

        // Write the regional indicator as width 1 initially
        // (It will become width 2 if followed by another regional indicator)
        let mut cell_flags = self.flags;
        cell_flags.hyperlink_id = self.current_hyperlink_id;
        cell_flags.set_guarded(self.char_protected);

        let cell = Cell {
            c,
            combining: Vec::new(),
            fg: self.fg,
            bg: self.bg,
            underline_color: self.underline_color,
            flags: cell_flags,
            width: 1, // Initially width 1, will become 2 when paired
            multicell: None,
        };

        let cursor_col = self.cursor.col;
        let cursor_row = self.cursor.row;

        // If insert mode (IRM) is enabled, insert space by shifting chars right
        if self.insert_mode {
            self.active_grid_mut()
                .insert_chars(cursor_col, cursor_row, 1);
            self.graphics_store.adjust_for_insert_characters_for_screen(
                1,
                cursor_col,
                cursor_row,
                cols,
                self.alt_screen_active,
            );
        } else {
            self.clear_wide_fragments_for_write(cursor_col, cursor_row, 1);
        }

        self.active_grid_mut().set(cursor_col, cursor_row, cell);
        self.mark_row_dirty(cursor_row);

        // Advance cursor by 1
        self.cursor.col += 1;

        // Handle delayed autowrap
        if self.auto_wrap && self.cursor.col >= cols {
            self.cursor.col = cols - 1;
            self.pending_wrap = true;
        } else if self.cursor.col >= cols {
            self.cursor.col = cols - 1;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::color::Color;

    fn create_test_terminal() -> Terminal {
        Terminal::new(80, 24)
    }

    #[test]
    fn test_write_char_basic() {
        let mut term = create_test_terminal();
        term.write_char('A');

        let cell = term.active_grid().get(0, 0).unwrap();
        assert_eq!(cell.c, 'A');
        assert_eq!(term.cursor.col, 1);
        assert_eq!(term.cursor.row, 0);
    }

    #[test]
    fn test_write_char_carriage_return() {
        let mut term = create_test_terminal();
        term.write_char('A');
        term.write_char('B');
        term.write_char('C');
        assert_eq!(term.cursor.col, 3);

        term.write_char('\r');
        assert_eq!(term.cursor.col, 0);
        assert_eq!(term.cursor.row, 0);
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_carriage_return_with_lr_margins() {
        let mut term = create_test_terminal();
        term.use_lr_margins = true;
        term.left_margin = 5;
        term.right_margin = 75;

        term.cursor.col = 10;
        term.write_char('\r');

        assert_eq!(term.cursor.col, 5); // Should move to left margin
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_line_feed() {
        let mut term = create_test_terminal();
        term.cursor.col = 5;
        term.write_char('\n');

        assert_eq!(term.cursor.col, 5); // Column unchanged
        assert_eq!(term.cursor.row, 1); // Row advanced
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_line_feed_new_line_mode() {
        let mut term = create_test_terminal();
        term.line_feed_new_line_mode = true;
        term.cursor.col = 5;
        term.write_char('\n');

        assert_eq!(term.cursor.col, 0); // CR+LF behavior
        assert_eq!(term.cursor.row, 1);
    }

    #[test]
    fn test_write_char_line_feed_at_scroll_bottom() {
        let mut term = create_test_terminal();
        term.scroll_region_top = 0;
        term.scroll_region_bottom = 23;
        term.cursor.row = 23;

        // Write some content in first row
        term.cursor.row = 0;
        term.write_char('X');

        // Go to bottom and trigger scroll
        term.cursor.row = 23;
        term.write_char('\n');

        // Should stay at row 23 after scrolling
        assert_eq!(term.cursor.row, 23);

        // First row should be blank after scroll
        let cell = term.active_grid().get(0, 0).unwrap();
        assert_eq!(cell.c, ' ');
    }

    #[test]
    fn test_write_char_tab() {
        let mut term = create_test_terminal();
        term.cursor.col = 0;

        // Default tab stops at every 8 columns
        term.write_char('\t');
        assert_eq!(term.cursor.col, 8);
        assert!(!term.pending_wrap);

        term.write_char('\t');
        assert_eq!(term.cursor.col, 16);
    }

    #[test]
    fn test_write_char_tab_at_end() {
        let mut term = create_test_terminal();
        term.cursor.col = 78;

        term.write_char('\t');
        assert_eq!(term.cursor.col, 79); // Clamped to last column
    }

    #[test]
    fn test_write_char_backspace() {
        let mut term = create_test_terminal();
        term.cursor.col = 5;

        term.write_char('\x08');
        assert_eq!(term.cursor.col, 4);
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_backspace_at_start() {
        let mut term = create_test_terminal();
        term.cursor.col = 0;

        term.write_char('\x08');
        assert_eq!(term.cursor.col, 0); // Stays at 0
    }

    #[test]
    fn test_write_char_control_chars_ignored() {
        let mut term = create_test_terminal();
        term.cursor.col = 5;

        // Test various control characters (except CR, LF, TAB, BS)
        term.write_char('\x01'); // SOH
        term.write_char('\x02'); // STX
        term.write_char('\x1B'); // ESC

        assert_eq!(term.cursor.col, 5); // Cursor unchanged

        let cell = term.active_grid().get(5, 0).unwrap();
        assert_eq!(cell.c, ' '); // No character written
    }

    #[test]
    fn test_write_char_wide_character() {
        let mut term = create_test_terminal();

        term.write_char('😀'); // Emoji (wide char)

        let cell = term.active_grid().get(0, 0).unwrap();
        assert_eq!(cell.c, '😀');
        assert_eq!(cell.width, 2);
        assert!(cell.flags.wide_char());

        // Check spacer cell
        let spacer = term.active_grid().get(1, 0).unwrap();
        assert_eq!(spacer.c, ' ');
        assert!(spacer.flags.wide_char_spacer());

        assert_eq!(term.cursor.col, 2); // Cursor advanced by 2
    }

    #[test]
    fn test_write_char_wide_character_wrap() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.cursor.col = 79; // Last column

        term.write_char('😀'); // Wide char won't fit

        // Should wrap to next line
        assert_eq!(term.cursor.col, 2);
        assert_eq!(term.cursor.row, 1);

        // Character should be on second row
        let cell = term.active_grid().get(0, 1).unwrap();
        assert_eq!(cell.c, '😀');

        // First row should be marked as wrapped
        assert!(term.active_grid().is_line_wrapped(0));
    }

    #[test]
    fn test_write_char_wide_character_ending_at_right_edge_wraps_next() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.cursor.col = 78;

        term.write_char('😀');
        term.write_char('X');

        let emoji = term.active_grid().get(78, 0).unwrap();
        assert_eq!(emoji.c, '😀');
        assert_eq!(emoji.width(), 2);
        assert!(emoji.flags.wide_char());
        assert!(term
            .active_grid()
            .get(79, 0)
            .unwrap()
            .flags
            .wide_char_spacer());
        assert!(term.active_grid().is_line_wrapped(0));
        assert_eq!(term.active_grid().get(0, 1).unwrap().c, 'X');
        assert_eq!(term.cursor.row, 1);
        assert_eq!(term.cursor.col, 1);
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_variation_selector_width_growth_advances_cursor() {
        let mut term = create_test_terminal();

        term.write_char('✈');
        term.write_char('\u{FE0F}');
        term.write_char('X');

        let emoji = term.active_grid().get(0, 0).unwrap();
        assert_eq!(emoji.get_grapheme(), "✈️");
        assert_eq!(emoji.width(), 2);
        assert!(emoji.flags.wide_char());
        assert!(term
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer());
        assert_eq!(term.active_grid().get(2, 0).unwrap().c, 'X');
        assert_eq!(term.cursor.col, 3);
    }

    #[test]
    fn test_write_char_keycap_cluster_advances_cursor_once() {
        let mut term = create_test_terminal();

        term.write_char('1');
        term.write_char('\u{FE0F}');
        term.write_char('\u{20E3}');
        term.write_char('X');

        let keycap = term.active_grid().get(0, 0).unwrap();
        assert_eq!(keycap.get_grapheme(), "1️⃣");
        assert_eq!(keycap.width(), 2);
        assert!(keycap.flags.wide_char());
        assert!(term
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer());
        assert_eq!(term.active_grid().get(2, 0).unwrap().c, 'X');
        assert_eq!(term.cursor.col, 3);
    }

    #[test]
    fn test_write_char_text_presentation_selector_keeps_narrow_cursor() {
        let mut term = create_test_terminal();

        term.write_char('✈');
        term.write_char('\u{FE0E}');
        term.write_char('X');

        let text = term.active_grid().get(0, 0).unwrap();
        assert_eq!(text.get_grapheme(), "✈︎");
        assert_eq!(text.width(), 1);
        assert!(!text.flags.wide_char());
        assert_eq!(term.active_grid().get(1, 0).unwrap().c, 'X');
        assert_eq!(term.cursor.col, 2);
    }

    #[test]
    fn test_write_char_plain_text_zwj_stays_narrow() {
        let mut term = create_test_terminal();

        term.write_char('a');
        term.write_char('\u{200D}');
        term.write_char('b');
        term.write_char('X');

        let joined = term.active_grid().get(0, 0).unwrap();
        assert_eq!(joined.get_grapheme(), "a\u{200D}");
        assert_eq!(joined.width(), 1);
        assert!(!joined.flags.wide_char());
        assert!(!term
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer());
        assert_eq!(term.active_grid().get(1, 0).unwrap().c, 'b');
        assert_eq!(term.active_grid().get(2, 0).unwrap().c, 'X');
        assert_eq!(term.cursor.col, 3);
    }

    #[test]
    fn test_write_char_variation_selector_supplement_attaches_to_base() {
        let mut term = create_test_terminal();

        term.write_char('字');
        term.write_char('\u{E0100}');
        term.write_char('X');

        let ideograph = term.active_grid().get(0, 0).unwrap();
        assert_eq!(ideograph.get_grapheme(), "字\u{E0100}");
        assert_eq!(ideograph.width(), 2);
        assert!(ideograph.flags.wide_char());
        assert!(term
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer());
        assert_eq!(term.active_grid().get(2, 0).unwrap().c, 'X');
        assert_eq!(term.cursor.col, 3);
    }

    #[test]
    fn test_write_char_emoji_tag_sequence_stays_one_wide_cell() {
        let mut term = create_test_terminal();

        let scotland_flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}";
        for c in scotland_flag.chars() {
            term.write_char(c);
        }
        term.write_char('X');

        let flag = term.active_grid().get(0, 0).unwrap();
        assert_eq!(flag.get_grapheme(), scotland_flag);
        assert_eq!(flag.width(), 2);
        assert!(flag.flags.wide_char());
        assert!(term
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer());
        assert_eq!(term.active_grid().get(2, 0).unwrap().c, 'X');
        assert_eq!(term.cursor.col, 3);
    }

    #[test]
    fn test_write_char_variation_selector_width_growth_at_right_edge_wraps_next() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.cursor.col = 78;

        term.write_char('✈');
        term.write_char('\u{FE0F}');
        term.write_char('X');

        let emoji = term.active_grid().get(78, 0).unwrap();
        assert_eq!(emoji.get_grapheme(), "✈️");
        assert_eq!(emoji.width(), 2);
        assert!(emoji.flags.wide_char());
        assert!(term
            .active_grid()
            .get(79, 0)
            .unwrap()
            .flags
            .wide_char_spacer());
        assert!(term.active_grid().is_line_wrapped(0));
        assert_eq!(term.active_grid().get(0, 1).unwrap().c, 'X');
        assert_eq!(term.cursor.row, 1);
        assert_eq!(term.cursor.col, 1);
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_variation_selector_uses_pending_wrap_cell() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.cursor.col = 78;
        term.write_char('Q');

        term.write_char('✈');
        term.write_char('\u{FE0F}');
        term.write_char('X');

        assert_eq!(term.active_grid().get(78, 0).unwrap().c, 'Q');
        assert_eq!(term.active_grid().get(79, 0).unwrap().c, ' ');
        let emoji = term.active_grid().get(0, 1).unwrap();
        assert_eq!(emoji.get_grapheme(), "✈️");
        assert_eq!(emoji.width(), 2);
        assert!(emoji.flags.wide_char());
        assert!(term.active_grid().is_line_wrapped(0));
        assert_eq!(term.active_grid().get(2, 1).unwrap().c, 'X');
        assert_eq!(term.cursor.row, 1);
        assert_eq!(term.cursor.col, 3);
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_combining_mark_uses_pending_wrap_cell() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.cursor.col = 78;
        term.write_char('Q');

        term.write_char('e');
        term.write_char('\u{0301}');
        term.write_char('X');

        assert_eq!(term.active_grid().get(78, 0).unwrap().c, 'Q');
        let accented = term.active_grid().get(79, 0).unwrap();
        assert_eq!(accented.get_grapheme(), "é");
        assert_eq!(accented.width(), 1);
        assert!(!accented.flags.wide_char());
        assert!(term.active_grid().is_line_wrapped(0));
        assert_eq!(term.active_grid().get(0, 1).unwrap().c, 'X');
        assert_eq!(term.cursor.row, 1);
        assert_eq!(term.cursor.col, 1);
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_regional_indicator_pair_uses_pending_wrap_cell() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.cursor.col = 78;
        term.write_char('Q');

        term.write_char('\u{1F1FA}');
        term.write_char('\u{1F1F8}');
        term.write_char('X');

        assert_eq!(term.active_grid().get(78, 0).unwrap().c, 'Q');
        assert_eq!(term.active_grid().get(79, 0).unwrap().c, ' ');
        let flag = term.active_grid().get(0, 1).unwrap();
        assert_eq!(flag.get_grapheme(), "🇺🇸");
        assert_eq!(flag.width(), 2);
        assert!(flag.flags.wide_char());
        assert!(term.active_grid().is_line_wrapped(0));
        assert_eq!(term.active_grid().get(2, 1).unwrap().c, 'X');
        assert_eq!(term.cursor.row, 1);
        assert_eq!(term.cursor.col, 3);
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_zwj_sequence_uses_pending_wrap_cell() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.cursor.col = 78;

        term.write_char('👨');
        term.write_char('\u{200D}');
        term.write_char('💻');
        term.write_char('X');

        let emoji = term.active_grid().get(78, 0).unwrap();
        assert_eq!(emoji.get_grapheme(), "👨‍💻");
        assert_eq!(emoji.width(), 2);
        assert!(emoji.flags.wide_char());
        assert!(term
            .active_grid()
            .get(79, 0)
            .unwrap()
            .flags
            .wide_char_spacer());
        assert!(term.active_grid().is_line_wrapped(0));
        assert_eq!(term.active_grid().get(0, 1).unwrap().c, 'X');
        assert_eq!(term.cursor.row, 1);
        assert_eq!(term.cursor.col, 1);
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_pending_wrap() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;

        // Fill line to last column
        for _ in 0..80 {
            term.write_char('A');
        }

        assert_eq!(term.cursor.col, 79);
        assert!(term.pending_wrap);

        // Next character should trigger wrap
        term.write_char('B');
        assert_eq!(term.cursor.col, 1);
        assert_eq!(term.cursor.row, 1);
        assert!(!term.pending_wrap);

        let cell = term.active_grid().get(0, 1).unwrap();
        assert_eq!(cell.c, 'B');
    }

    #[test]
    fn test_write_char_no_auto_wrap() {
        let mut term = create_test_terminal();
        term.auto_wrap = false;

        // Fill line to last column
        for _ in 0..80 {
            term.write_char('A');
        }

        assert_eq!(term.cursor.col, 79); // Stays at last column
        assert!(!term.pending_wrap);

        // Next character overwrites last cell
        term.write_char('B');
        assert_eq!(term.cursor.col, 79);
        assert_eq!(term.cursor.row, 0);

        let cell = term.active_grid().get(79, 0).unwrap();
        assert_eq!(cell.c, 'B');
    }

    #[test]
    fn test_write_char_insert_mode() {
        let mut term = create_test_terminal();
        term.insert_mode = true;

        // Write some characters
        term.write_char('A');
        term.write_char('B');
        term.write_char('C');

        // Move back and insert
        term.cursor.col = 1;
        term.write_char('X');

        // Should have: A X B C (C shifted right)
        assert_eq!(term.active_grid().get(0, 0).unwrap().c, 'A');
        assert_eq!(term.active_grid().get(1, 0).unwrap().c, 'X');
        assert_eq!(term.active_grid().get(2, 0).unwrap().c, 'B');
        assert_eq!(term.active_grid().get(3, 0).unwrap().c, 'C');
    }

    #[test]
    fn test_write_char_with_attributes() {
        let mut term = create_test_terminal();

        // Set some attributes
        term.fg = Color::Rgb(255, 0, 0);
        term.bg = Color::Rgb(0, 255, 0);
        term.flags.set_bold(true);
        term.flags.set_italic(true);

        term.write_char('A');

        let cell = term.active_grid().get(0, 0).unwrap();
        assert_eq!(cell.c, 'A');
        assert_eq!(cell.fg, Color::Rgb(255, 0, 0));
        assert_eq!(cell.bg, Color::Rgb(0, 255, 0));
        assert!(cell.flags.bold());
        assert!(cell.flags.italic());
    }

    #[test]
    fn test_write_char_with_hyperlink() {
        let mut term = create_test_terminal();
        term.current_hyperlink_id = Some(42);

        term.write_char('A');

        let cell = term.active_grid().get(0, 0).unwrap();
        assert_eq!(cell.flags.hyperlink_id, Some(42));
    }

    #[test]
    fn test_write_char_guarded() {
        let mut term = create_test_terminal();
        term.char_protected = true;

        term.write_char('A');

        let cell = term.active_grid().get(0, 0).unwrap();
        assert!(cell.flags.guarded());
    }

    #[test]
    fn test_write_char_pending_wrap_clears_on_cr() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.pending_wrap = true;

        term.write_char('\r');
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_pending_wrap_clears_on_lf() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.pending_wrap = true;

        term.write_char('\n');
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_pending_wrap_clears_on_tab() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.pending_wrap = true;

        term.write_char('\t');
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_pending_wrap_clears_on_backspace() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.pending_wrap = true;

        term.write_char('\x08');
        assert!(!term.pending_wrap);
    }

    #[test]
    fn test_write_char_line_wrapping_marks() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;

        // Fill first line
        for _ in 0..80 {
            term.write_char('A');
        }

        assert!(term.pending_wrap);

        // Next char triggers wrap and marks line
        term.write_char('B');

        assert!(term.active_grid().is_line_wrapped(0));
        assert!(!term.active_grid().is_line_wrapped(1));
    }

    #[test]
    fn test_write_char_wide_at_scroll_bottom() {
        let mut term = create_test_terminal();
        term.scroll_region_top = 0;
        term.scroll_region_bottom = 23;
        term.cursor.row = 23;
        term.cursor.col = 79;
        term.auto_wrap = true;

        // Write wide char that triggers wrap and scroll
        term.write_char('😀');

        // Should be on row 23 after scroll
        assert_eq!(term.cursor.row, 23);
        assert_eq!(term.cursor.col, 2);
    }

    #[test]
    fn test_write_char_cjk_characters() {
        let mut term = create_test_terminal();

        // Test various CJK characters (all wide)
        term.write_char('中'); // Chinese
        assert_eq!(term.cursor.col, 2);

        term.write_char('日'); // Japanese
        assert_eq!(term.cursor.col, 4);

        term.write_char('한'); // Korean
        assert_eq!(term.cursor.col, 6);

        // Verify all are marked as wide
        assert!(term.active_grid().get(0, 0).unwrap().flags.wide_char());
        assert!(term.active_grid().get(2, 0).unwrap().flags.wide_char());
        assert!(term.active_grid().get(4, 0).unwrap().flags.wide_char());
    }

    #[test]
    fn test_write_char_insert_mode_wide_char() {
        let mut term = create_test_terminal();
        term.insert_mode = true;

        term.write_char('A');
        term.write_char('B');

        term.cursor.col = 1;
        term.write_char('😀');

        // Should insert wide char (shifts by 2)
        assert_eq!(term.active_grid().get(0, 0).unwrap().c, 'A');
        assert_eq!(term.active_grid().get(1, 0).unwrap().c, '😀');
        assert!(term
            .active_grid()
            .get(2, 0)
            .unwrap()
            .flags
            .wide_char_spacer());
        assert_eq!(term.active_grid().get(3, 0).unwrap().c, 'B');
    }

    #[test]
    fn test_write_char_lf_with_lr_margins_outside() {
        let mut term = create_test_terminal();
        term.use_lr_margins = true;
        term.left_margin = 10;
        term.right_margin = 70;
        term.scroll_region_top = 0;
        term.scroll_region_bottom = 23;

        // Position cursor outside left/right margins but in scroll region
        term.cursor.col = 5;
        term.cursor.row = 23;

        term.write_char('\n');

        // Should not scroll when outside LR margins (iTerm2 behavior)
        assert_eq!(term.cursor.row, 23); // Clamped to bottom
    }

    #[test]
    fn test_write_char_pending_wrap_with_lr_margins() {
        let mut term = create_test_terminal();
        term.auto_wrap = true;
        term.use_lr_margins = true;
        term.left_margin = 10;
        term.right_margin = 70;

        term.cursor.col = 79;
        term.pending_wrap = true;

        term.write_char('A');

        // Should wrap to left margin
        assert_eq!(term.cursor.col, 11);
        assert_eq!(term.cursor.row, 1);
    }
}
