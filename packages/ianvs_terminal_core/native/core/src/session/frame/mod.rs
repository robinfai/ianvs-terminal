mod context;
mod damage;
mod delta;
mod graphics;
mod projection;
mod snapshot;

pub(in crate::session) use context::{BuiltFrameRows, FrameBuildContext};
pub(in crate::session) use damage::{
    CachedFrameMeta, CachedRowState, PendingFrameWork, resolve_viewport_row_shift,
    snapshot_fallback_reason,
};
#[cfg(test)]
pub(in crate::session) use damage::{PendingScrollRegion, delta_candidate_row_indexes};
pub(in crate::session) use delta::{DeltaFrameContext, build_delta_frame};
pub(in crate::session) use graphics::{
    GraphicAssetSnapshot, build_projected_graphic_placements, graphic_asset_snapshots,
};
#[cfg(test)]
pub(in crate::session) use graphics::{build_graphic_placements, graphic_placement_for_viewport};
pub(in crate::session) use projection::{
    CollapsedBlockRange, DisplayProjection, DisplayProjectionRow, display_projection_for_terminal,
    projection_source_span,
};
pub(in crate::session) use snapshot::build_snapshot_frame;
