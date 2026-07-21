use super::{CachedRowState, DisplayProjection};
use crate::model::{TerminalDirtyRange, TerminalEmulation, TerminalHyperlinkRange, TerminalRow};
use par_term_emu_core_rust::terminal::Terminal;

/// Immutable terminal and viewport inputs shared by frame builders.
///
/// Builder-specific damage, cache, and fallback state deliberately stays out
/// of this context so snapshot, delta, display, and graphics extraction can
/// add only the mutable inputs they own.
pub(in crate::session) struct FrameBuildContext<'a> {
    pub(in crate::session) terminal: &'a Terminal,
    pub(in crate::session) emulation: TerminalEmulation,
    pub(in crate::session) display_projection: &'a DisplayProjection,
    pub(in crate::session) viewport_start_row: usize,
    pub(in crate::session) viewport_display_start_row: usize,
    pub(in crate::session) viewport_rows: usize,
    pub(in crate::session) viewport_cols: usize,
    pub(in crate::session) scrollback_len: usize,
    pub(in crate::session) alt_screen_active: bool,
}

pub(in crate::session) type BuiltFrameRows = (
    Vec<TerminalRow>,
    Vec<TerminalHyperlinkRange>,
    Vec<CachedRowState>,
    Vec<TerminalDirtyRange>,
    usize,
    usize,
);
