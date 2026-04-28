use crate::grid::{GridDamage, ScrollRegionDamage};

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct TerminalDamage {
    pub full_repaint: bool,
    pub dirty_rows: Vec<usize>,
    pub scroll_region: Option<ScrollRegionDamage>,
    pub snapshot_fallback_reason: Option<String>,
}

impl From<GridDamage> for TerminalDamage {
    fn from(value: GridDamage) -> Self {
        Self {
            full_repaint: value.full_repaint,
            dirty_rows: value.dirty_rows.into_iter().collect(),
            scroll_region: value.scroll_region,
            snapshot_fallback_reason: value.snapshot_fallback_reason,
        }
    }
}
