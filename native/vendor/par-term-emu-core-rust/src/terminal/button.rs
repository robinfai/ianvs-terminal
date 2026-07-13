//! iTerm2 OSC 1337 inline button state.

use std::collections::VecDeque;

use super::Terminal;

pub const MAX_ITERM_BUTTONS: usize = 512;
pub const MAX_ITERM_BUTTON_ICON_CHARS: usize = 128;
pub const ITERM_BUTTON_WIDTH_CELLS: usize = 4;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ItermButtonKind {
    Copy { block_id: String },
    Custom { code: i32, icon: String },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ItermButton {
    pub id: u64,
    pub kind: ItermButtonKind,
    /// Primary-screen buttons use a global absolute row. Alternate-screen
    /// buttons use a transient grid row.
    pub row: usize,
    pub col: usize,
    pub alternate_screen: bool,
    pub valid: bool,
}

#[derive(Clone, Debug)]
pub(crate) struct ItermButtonState {
    buttons: VecDeque<ItermButton>,
    next_id: u64,
}

impl Default for ItermButtonState {
    fn default() -> Self {
        Self {
            buttons: VecDeque::new(),
            next_id: 1,
        }
    }
}

impl ItermButtonState {
    pub(crate) fn buttons(&self) -> &VecDeque<ItermButton> {
        &self.buttons
    }

    fn insert(
        &mut self,
        kind: ItermButtonKind,
        row: usize,
        col: usize,
        alternate_screen: bool,
        first_retained_abs_row: usize,
    ) {
        self.buttons
            .retain(|button| button.alternate_screen || button.row >= first_retained_abs_row);
        while self.buttons.len() >= MAX_ITERM_BUTTONS {
            self.buttons.pop_front();
        }
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1).max(1);
        self.buttons.push_back(ItermButton {
            id,
            kind,
            row,
            col,
            alternate_screen,
            valid: true,
        });
    }

    fn invalidate_custom(&mut self) -> bool {
        let mut changed = false;
        for button in &mut self.buttons {
            if matches!(button.kind, ItermButtonKind::Custom { .. }) && button.valid {
                button.valid = false;
                changed = true;
            }
        }
        changed
    }

    fn clear_screen(&mut self, alternate_screen: bool) {
        self.buttons
            .retain(|button| button.alternate_screen != alternate_screen);
    }

    fn clear(&mut self) {
        self.buttons.clear();
    }

    pub(crate) fn next_id(&self) -> u64 {
        self.next_id
    }

    pub(crate) fn preserve_next_id(&mut self, next_id: u64) {
        self.next_id = self.next_id.max(next_id).max(1);
    }

    pub(crate) fn adjust_scroll_up(
        &mut self,
        n: usize,
        top: usize,
        bottom: usize,
        alternate_screen: bool,
        primary_visible_base: usize,
    ) {
        if n == 0 {
            return;
        }
        self.buttons.retain_mut(|button| {
            if button.alternate_screen != alternate_screen {
                return true;
            }
            if !alternate_screen && top == 0 {
                // Primary marks use absolute rows and therefore stay attached
                // when the grid advances into scrollback.
                return true;
            }
            let visible_row = if alternate_screen {
                button.row
            } else {
                button.row.saturating_sub(primary_visible_base)
            };
            if visible_row < top || visible_row > bottom {
                return true;
            }
            if visible_row < top.saturating_add(n) {
                return false;
            }
            let next_row = visible_row.saturating_sub(n);
            button.row = if alternate_screen {
                next_row
            } else {
                primary_visible_base.saturating_add(next_row)
            };
            true
        });
    }

    pub(crate) fn adjust_scroll_down(
        &mut self,
        n: usize,
        top: usize,
        bottom: usize,
        alternate_screen: bool,
        primary_visible_base: usize,
    ) {
        if n == 0 {
            return;
        }
        self.buttons.retain_mut(|button| {
            if button.alternate_screen != alternate_screen {
                return true;
            }
            let visible_row = if alternate_screen {
                button.row
            } else {
                button.row.saturating_sub(primary_visible_base)
            };
            if visible_row < top || visible_row > bottom {
                return true;
            }
            if visible_row > bottom.saturating_sub(n) {
                return false;
            }
            let next_row = visible_row.saturating_add(n);
            button.row = if alternate_screen {
                next_row
            } else {
                primary_visible_base.saturating_add(next_row)
            };
            true
        });
    }
}

impl Terminal {
    pub fn iterm_buttons(&self) -> &VecDeque<ItermButton> {
        self.iterm_buttons.buttons()
    }

    pub fn iterm_button(&self, id: u64) -> Option<&ItermButton> {
        self.iterm_buttons
            .buttons()
            .iter()
            .find(|button| button.id == id)
    }

    pub fn iterm_button_copy_text(&self, id: u64) -> Option<String> {
        let button = self.iterm_button(id)?;
        if !button.valid {
            return None;
        }
        let ItermButtonKind::Copy { block_id } = &button.kind else {
            return None;
        };
        let block = self
            .iterm_blocks()
            .iter()
            .rev()
            .find(|block| block.complete && block.id == *block_id)?;
        let first_retained_abs_row = self
            .grid
            .total_lines_scrolled()
            .saturating_sub(self.grid.scrollback_len());
        let last_retained_abs_row = self
            .grid
            .total_lines_scrolled()
            .saturating_add(self.grid.rows().saturating_sub(1));
        if block.start_abs_row < first_retained_abs_row || block.end_abs_row > last_retained_abs_row
        {
            return None;
        }
        self.extract_text_from_row_range(block.start_abs_row, block.end_abs_row)
    }

    pub(crate) fn handle_iterm_copy_button(&mut self, block_id: String) {
        let alternate_screen = self.alt_screen_active;
        let row = if alternate_screen {
            self.cursor.row
        } else {
            self.grid
                .total_lines_scrolled()
                .saturating_add(self.cursor.row)
        };
        let first_retained_abs_row = self
            .grid
            .total_lines_scrolled()
            .saturating_sub(self.grid.scrollback_len());
        self.iterm_buttons.insert(
            ItermButtonKind::Copy { block_id },
            row,
            self.cursor.col,
            alternate_screen,
            first_retained_abs_row,
        );
        self.advance_after_iterm_button();
        self.mark_full_repaint("iterm_copy_button");
    }

    pub(crate) fn handle_iterm_custom_button(&mut self, code: i32, icon: String) {
        let alternate_screen = self.alt_screen_active;
        let row = if alternate_screen {
            self.cursor.row
        } else {
            self.grid
                .total_lines_scrolled()
                .saturating_add(self.cursor.row)
        };
        let first_retained_abs_row = self
            .grid
            .total_lines_scrolled()
            .saturating_sub(self.grid.scrollback_len());
        self.iterm_buttons.insert(
            ItermButtonKind::Custom { code, icon },
            row,
            self.cursor.col,
            alternate_screen,
            first_retained_abs_row,
        );
        self.advance_after_iterm_button();
        self.mark_full_repaint("iterm_custom_button");
    }

    pub(crate) fn invalidate_iterm_custom_buttons(&mut self) {
        if self.iterm_buttons.invalidate_custom() {
            self.mark_full_repaint("iterm_custom_button_invalidation");
        }
    }

    fn advance_after_iterm_button(&mut self) {
        for _ in 0..ITERM_BUTTON_WIDTH_CELLS {
            self.write_char(' ');
        }
    }

    pub(crate) fn clear_iterm_buttons(&mut self) {
        self.iterm_buttons.clear();
    }

    pub(crate) fn clear_iterm_buttons_for_screen(&mut self, alternate_screen: bool) {
        self.iterm_buttons.clear_screen(alternate_screen);
    }
}

pub(crate) fn bounded_iterm_button_icon(value: &str) -> Option<String> {
    if value.is_empty()
        || value.chars().count() > MAX_ITERM_BUTTON_ICON_CHARS
        || value.chars().any(char::is_control)
    {
        return None;
    }
    Some(value.to_string())
}
