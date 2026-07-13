//! iTerm2 OSC 1337 block lifecycle and fold state.

use std::collections::VecDeque;

use super::Terminal;

pub const MAX_ITERM_BLOCKS: usize = 512;
pub const MAX_ITERM_BLOCK_ID_CHARS: usize = 256;
pub const MAX_ITERM_BLOCK_TYPE_CHARS: usize = 256;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ItermBlock {
    pub id: String,
    pub block_type: Option<String>,
    pub start_abs_row: usize,
    pub end_abs_row: usize,
    pub complete: bool,
    pub folded: bool,
    pub render: bool,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct ItermBlockState {
    blocks: VecDeque<ItermBlock>,
    active_ids: Vec<String>,
}

impl ItermBlockState {
    pub(crate) fn blocks(&self) -> &VecDeque<ItermBlock> {
        &self.blocks
    }

    fn prune_before(&mut self, first_retained_abs_row: usize) {
        self.blocks
            .retain(|block| !block.complete || block.end_abs_row >= first_retained_abs_row);
        self.active_ids.retain(|id| {
            self.blocks
                .iter()
                .any(|block| !block.complete && block.id == *id)
        });
    }

    fn start(
        &mut self,
        id: String,
        block_type: Option<String>,
        abs_row: usize,
        first_retained_abs_row: usize,
    ) -> bool {
        self.prune_before(first_retained_abs_row);
        if self.active_ids.iter().any(|active| active == &id) {
            return false;
        }

        self.blocks.retain(|block| block.id != id);
        while self.blocks.len() >= MAX_ITERM_BLOCKS {
            let removable = self
                .blocks
                .iter()
                .position(|block| block.complete)
                .unwrap_or(0);
            if let Some(removed) = self.blocks.remove(removable) {
                self.active_ids.retain(|active| active != &removed.id);
            }
        }
        self.blocks.push_back(ItermBlock {
            id: id.clone(),
            block_type,
            start_abs_row: abs_row,
            end_abs_row: abs_row,
            complete: false,
            folded: false,
            render: false,
        });
        self.active_ids.insert(0, id);
        true
    }

    fn end(&mut self, id: &str, abs_row: usize, render: bool) -> bool {
        if !self.active_ids.iter().any(|active| active == id) {
            return false;
        }
        let Some(block) = self
            .blocks
            .iter_mut()
            .rev()
            .find(|block| !block.complete && block.id == id)
        else {
            return false;
        };
        block.end_abs_row = abs_row.max(block.start_abs_row);
        block.complete = true;
        block.render = render;
        self.active_ids.retain(|active| active != id);
        true
    }

    fn set_folded(&mut self, id: &str, folded: bool) -> bool {
        let Some(block) = self.blocks.iter_mut().rev().find(|block| {
            block.complete && block.id == id && block.end_abs_row > block.start_abs_row
        }) else {
            return false;
        };
        if block.folded == folded {
            return false;
        }
        block.folded = folded;
        true
    }
}

impl Terminal {
    pub fn iterm_blocks(&self) -> &VecDeque<ItermBlock> {
        self.iterm_blocks.blocks()
    }

    pub fn set_iterm_block_folded(&mut self, id: &str, folded: bool) -> bool {
        let changed = self.iterm_blocks.set_folded(id, folded);
        if changed {
            self.mark_full_repaint(if folded {
                "iterm_block_fold"
            } else {
                "iterm_block_unfold"
            });
        }
        changed
    }

    pub(crate) fn handle_iterm_block_start(&mut self, id: String, block_type: Option<String>) {
        if self.alt_screen_active {
            return;
        }
        let abs_row = self
            .grid
            .total_lines_scrolled()
            .saturating_add(self.cursor.row);
        let first_retained_abs_row = self
            .grid
            .total_lines_scrolled()
            .saturating_sub(self.grid.scrollback_len());
        if self
            .iterm_blocks
            .start(id, block_type, abs_row, first_retained_abs_row)
        {
            self.mark_full_repaint("iterm_block_start");
        }
    }

    pub(crate) fn handle_iterm_block_end(&mut self, id: &str, render: bool) {
        if self.alt_screen_active {
            return;
        }
        let abs_row = self
            .grid
            .total_lines_scrolled()
            .saturating_add(self.cursor.row);
        if self.iterm_blocks.end(id, abs_row, render) {
            self.mark_full_repaint("iterm_block_end");
        }
    }

    pub(crate) fn clear_iterm_blocks(&mut self) {
        self.iterm_blocks = ItermBlockState::default();
    }
}

pub(crate) fn bounded_iterm_block_value(value: &str, max_chars: usize) -> Option<String> {
    if value.is_empty() || value.chars().count() > max_chars || value.chars().any(char::is_control)
    {
        return None;
    }
    Some(value.to_string())
}
