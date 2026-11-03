use ianvs_core::model::TERMINAL_FRAME_SCHEMA_VERSION;
use ianvs_core::proto::frame_diff as pb;
use ianvs_core::recording::{
    AdaptiveSampler, ContainerWriter, RecordedAsset, RecordingMetadata, SamplingPolicy,
    SemanticEvent, SemanticKind,
};
use std::path::Path;

pub fn create(path: &Path, frames: u64) {
    let metadata = RecordingMetadata {
        recording_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
        started_at_unix_millis: 1_790_438_400_000,
        title: "采样回放 fixture".into(),
        hostname: Some("fixture.local".into()),
    };
    let mut writer = ContainerWriter::create(path, &metadata).unwrap();
    let mut sampler = AdaptiveSampler::new(SamplingPolicy::default()).unwrap();
    let asset = RecordedAsset {
        asset_id: 3,
        asset_version: 1,
        width: 2,
        height: 1,
        rgba: vec![255, 0, 0, 255, 0, 255, 0, 255],
    };
    for n in 0..frames {
        let frame = pb::TerminalFrameDiff {
            frame_schema_version: TERMINAL_FRAME_SCHEMA_VERSION.into(),
            frame_kind: pb::TerminalFrameKind::Snapshot as i32,
            viewport_rows: 2,
            viewport_cols: 80,
            cursor: Some(pb::TerminalCursor::default()),
            modes: Some(pb::TerminalFrameModes::default()),
            rows: vec![
                pb::TerminalRow {
                    text: format!("frame {n} 雪"),
                    ..Default::default()
                },
                pb::TerminalRow {
                    index: 1,
                    text: "copiable structured screen".into(),
                    ..Default::default()
                },
            ],
            graphics: vec![pb::TerminalGraphicPlacement {
                placement_id: 1,
                render_id: 1,
                asset_key: Some(pb::TerminalGraphicAssetKey {
                    asset_id: 3,
                    asset_version: 1,
                }),
                protocol: "kitty".into(),
                row: 1,
                col: 40,
                width_px: 2,
                height_px: 1,
                width_cells: 2,
                height_cells: 1,
                visible_width_px: 2,
                visible_height_px: 1,
                ..Default::default()
            }],
            ..Default::default()
        };
        let sample = sampler
            .observe_frame(n * 1_000_000, frame)
            .unwrap()
            .unwrap();
        writer
            .append_visual(sample, std::slice::from_ref(&asset))
            .unwrap();
        for (offset, kind, code) in [
            (100, SemanticKind::CommandStarted, None),
            (500, SemanticKind::CommandFinished, Some(7)),
        ] {
            writer
                .append_semantic(&SemanticEvent {
                    offset_micros: n * 1_000_000 + offset,
                    kind,
                    context_id: "root".into(),
                    command_id: Some(format!("c{n}")),
                    command: Some(format!("printf '%s' 'quoted 雪-{n}'")),
                    cwd: Some("/tmp/fixture".into()),
                    hostname: Some("fixture.local".into()),
                    exit_code: code,
                })
                .unwrap();
        }
    }
    writer
        .finish(frames.saturating_sub(1) * 1_000_000 + 1000)
        .unwrap();
}
