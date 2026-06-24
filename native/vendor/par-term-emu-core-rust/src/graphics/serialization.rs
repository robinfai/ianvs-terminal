//! Image metadata serialization for session persistence
//!
//! Provides serializable representations of image metadata that can be persisted
//! and restored with terminal sessions. Supports both embedded image data (base64)
//! and external file references for compact on-disk storage.
//!
//! # Design
//!
//! The serialization layer introduces `SerializableGraphic` as a serde-compatible
//! mirror of `TerminalGraphic`. Raw pixel data is handled via `ImageDataRef` which
//! supports either inline base64 or a file path reference. Animation frame data
//! uses the same approach.
//!
//! A `GraphicsSnapshot` captures the full graphics state (active placements,
//! scrollback, and animations) for round-trip persistence.

use std::collections::HashMap;
use std::sync::Arc;

use base64::Engine;
use serde::{Deserialize, Serialize};

use super::animation::{AnimationFrame, AnimationState, CompositionMode};
use super::{
    graphic_content_version, GraphicProtocol, GraphicsStore, ImagePlacement, TerminalGraphic,
};

/// Reference to image data - either inline base64 or an external file path
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "value")]
pub enum ImageDataRef {
    /// Base64-encoded RGBA pixel data (portable but larger)
    Inline(String),
    /// Path to external file containing raw RGBA pixel data
    File(String),
}

/// Serializable animation frame metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerializableAnimationFrame {
    pub frame_number: u32,
    pub width: usize,
    pub height: usize,
    pub delay_ms: u32,
    pub x_offset: u32,
    pub y_offset: u32,
    pub composition: CompositionMode,
    pub data: ImageDataRef,
}

/// Serializable animation metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerializableAnimation {
    pub image_id: u32,
    pub frames: Vec<SerializableAnimationFrame>,
    pub default_delay_ms: u32,
    pub state: AnimationState,
    pub current_frame: u32,
    pub loop_count: u32,
    pub loops_completed: u32,
}

/// Serializable representation of a terminal graphic
///
/// This captures all metadata needed to restore an image placement,
/// including protocol-specific fields and pixel data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerializableGraphic {
    /// Unique placement ID
    pub id: u64,
    /// Graphics protocol used
    pub protocol: GraphicProtocol,
    /// Position in terminal (col, row)
    pub position: (usize, usize),
    /// Width in pixels
    pub width: usize,
    /// Height in pixels
    pub height: usize,
    /// Original width in pixels as decoded from source image
    pub original_width: usize,
    /// Original height in pixels as decoded from source image
    pub original_height: usize,
    /// Cell dimensions (cell_width, cell_height) for rendering
    pub cell_dimensions: Option<(u32, u32)>,
    /// Resolved display span in terminal cells
    #[serde(default)]
    pub display_cell_span: Option<(usize, usize)>,
    /// Rows scrolled off visible area
    pub scroll_offset_rows: usize,
    /// Row in scrollback buffer
    pub scrollback_row: Option<usize>,

    // Kitty-specific fields
    pub kitty_image_id: Option<u32>,
    pub kitty_placement_id: Option<u32>,
    pub is_virtual: bool,
    pub parent_image_id: Option<u32>,
    pub parent_placement_id: Option<u32>,
    pub relative_x_offset: i32,
    pub relative_y_offset: i32,
    pub was_compressed: bool,

    /// Unified placement metadata
    pub placement: ImagePlacement,

    /// Image pixel data reference
    pub data: ImageDataRef,
}

/// Complete snapshot of graphics state for session persistence
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphicsSnapshot {
    /// Schema version for forward compatibility
    pub version: u32,
    /// Active placements (visible area)
    pub placements: Vec<SerializableGraphic>,
    /// Graphics in scrollback
    pub scrollback: Vec<SerializableGraphic>,
    /// Animations indexed by image ID
    pub animations: Vec<SerializableAnimation>,
}

impl GraphicsSnapshot {
    /// Current schema version
    pub const CURRENT_VERSION: u32 = 1;
}

// --- Conversion: TerminalGraphic -> SerializableGraphic ---

impl From<&TerminalGraphic> for SerializableGraphic {
    fn from(g: &TerminalGraphic) -> Self {
        let encoded = base64::engine::general_purpose::STANDARD.encode(g.pixels.as_ref());
        Self {
            id: g.id,
            protocol: g.protocol,
            position: g.position,
            width: g.width,
            height: g.height,
            original_width: g.original_width,
            original_height: g.original_height,
            cell_dimensions: g.cell_dimensions,
            display_cell_span: g.display_cell_span,
            scroll_offset_rows: g.scroll_offset_rows,
            scrollback_row: g.scrollback_row,
            kitty_image_id: g.kitty_image_id,
            kitty_placement_id: g.kitty_placement_id,
            is_virtual: g.is_virtual,
            parent_image_id: g.parent_image_id,
            parent_placement_id: g.parent_placement_id,
            relative_x_offset: g.relative_x_offset,
            relative_y_offset: g.relative_y_offset,
            was_compressed: g.was_compressed,
            placement: g.placement.clone(),
            data: ImageDataRef::Inline(encoded),
        }
    }
}

impl SerializableGraphic {
    /// Convert back to a TerminalGraphic by resolving the image data reference
    ///
    /// For `ImageDataRef::Inline`, decodes the base64 data directly.
    /// For `ImageDataRef::File`, reads the file contents.
    ///
    /// Returns an error if the data cannot be resolved.
    pub fn to_terminal_graphic(&self) -> Result<TerminalGraphic, GraphicsSerializationError> {
        let pixels = self.resolve_data()?;
        let asset_version = graphic_content_version(self.width, self.height, &pixels);
        Ok(TerminalGraphic {
            id: self.id,
            protocol: self.protocol,
            position: self.position,
            width: self.width,
            height: self.height,
            original_width: self.original_width,
            original_height: self.original_height,
            asset_version,
            pixels: Arc::new(pixels),
            cell_dimensions: self.cell_dimensions,
            display_cell_span: self.display_cell_span,
            scroll_offset_rows: self.scroll_offset_rows,
            scrollback_row: self.scrollback_row,
            kitty_image_id: self.kitty_image_id,
            kitty_placement_id: self.kitty_placement_id,
            is_virtual: self.is_virtual,
            parent_image_id: self.parent_image_id,
            parent_placement_id: self.parent_placement_id,
            relative_x_offset: self.relative_x_offset,
            relative_y_offset: self.relative_y_offset,
            was_compressed: self.was_compressed,
            placement: self.placement.clone(),
        })
    }

    /// Resolve the image data reference to raw RGBA bytes
    fn resolve_data(&self) -> Result<Vec<u8>, GraphicsSerializationError> {
        match &self.data {
            ImageDataRef::Inline(b64) => base64::engine::general_purpose::STANDARD
                .decode(b64)
                .map_err(|e| GraphicsSerializationError::Base64Decode(e.to_string())),
            ImageDataRef::File(path) => std::fs::read(path)
                .map_err(|e| GraphicsSerializationError::FileRead(path.clone(), e.to_string())),
        }
    }

    /// Create a SerializableGraphic with a file reference instead of inline data.
    ///
    /// This writes the pixel data to the given path and stores a reference.
    pub fn with_file_ref(
        graphic: &TerminalGraphic,
        path: &str,
    ) -> Result<Self, GraphicsSerializationError> {
        std::fs::write(path, graphic.pixels.as_ref())
            .map_err(|e| GraphicsSerializationError::FileWrite(path.to_string(), e.to_string()))?;

        let mut sg = SerializableGraphic::from(graphic);
        sg.data = ImageDataRef::File(path.to_string());
        Ok(sg)
    }
}

// --- Conversion: AnimationFrame -> SerializableAnimationFrame ---

impl From<&AnimationFrame> for SerializableAnimationFrame {
    fn from(f: &AnimationFrame) -> Self {
        let encoded = base64::engine::general_purpose::STANDARD.encode(f.pixels.as_ref());
        Self {
            frame_number: f.frame_number,
            width: f.width,
            height: f.height,
            delay_ms: f.delay_ms,
            x_offset: f.x_offset,
            y_offset: f.y_offset,
            composition: f.composition,
            data: ImageDataRef::Inline(encoded),
        }
    }
}

impl SerializableAnimationFrame {
    /// Convert back to an AnimationFrame
    pub fn to_animation_frame(&self) -> Result<AnimationFrame, GraphicsSerializationError> {
        let pixels = match &self.data {
            ImageDataRef::Inline(b64) => base64::engine::general_purpose::STANDARD
                .decode(b64)
                .map_err(|e| GraphicsSerializationError::Base64Decode(e.to_string()))?,
            ImageDataRef::File(path) => std::fs::read(path)
                .map_err(|e| GraphicsSerializationError::FileRead(path.clone(), e.to_string()))?,
        };
        Ok(AnimationFrame {
            frame_number: self.frame_number,
            pixels: Arc::new(pixels),
            width: self.width,
            height: self.height,
            delay_ms: self.delay_ms,
            x_offset: self.x_offset,
            y_offset: self.y_offset,
            composition: self.composition,
        })
    }
}

// --- GraphicsStore export/import ---

impl GraphicsStore {
    /// Export all graphics state as a serializable snapshot
    ///
    /// This captures active placements, scrollback graphics, and animation
    /// state. Pixel data is encoded as base64 inline.
    pub fn export_snapshot(&self) -> GraphicsSnapshot {
        let placements = self
            .all_graphics()
            .iter()
            .map(SerializableGraphic::from)
            .collect();

        let scrollback = self
            .all_scrollback_graphics()
            .iter()
            .map(SerializableGraphic::from)
            .collect();

        let animations = self
            .all_animations()
            .values()
            .map(|anim| SerializableAnimation {
                image_id: anim.image_id,
                frames: anim
                    .frames
                    .values()
                    .map(SerializableAnimationFrame::from)
                    .collect(),
                default_delay_ms: anim.default_delay_ms,
                state: anim.state,
                current_frame: anim.current_frame,
                loop_count: anim.loop_count,
                loops_completed: anim.loops_completed,
            })
            .collect();

        GraphicsSnapshot {
            version: GraphicsSnapshot::CURRENT_VERSION,
            placements,
            scrollback,
            animations,
        }
    }

    /// Import graphics state from a serialized snapshot
    ///
    /// This clears existing graphics and restores from the snapshot.
    /// Returns the number of graphics restored, or an error if data is invalid.
    pub fn import_snapshot(
        &mut self,
        snapshot: &GraphicsSnapshot,
    ) -> Result<usize, GraphicsSerializationError> {
        if snapshot.version > GraphicsSnapshot::CURRENT_VERSION {
            return Err(GraphicsSerializationError::UnsupportedVersion(
                snapshot.version,
                GraphicsSnapshot::CURRENT_VERSION,
            ));
        }

        self.clear_snapshot_import_state();

        // Restore active placements
        for sg in &snapshot.placements {
            let graphic = sg.to_terminal_graphic()?;
            self.add_graphic(graphic);
        }

        // Restore scrollback
        for sg in &snapshot.scrollback {
            let graphic = sg.to_terminal_graphic()?;
            // Add directly to scrollback via the internal method
            self.add_scrollback_graphic(graphic);
        }

        // Restore animations
        for sa in &snapshot.animations {
            let mut frames = HashMap::new();
            for sf in &sa.frames {
                let frame = sf.to_animation_frame()?;
                frames.insert(frame.frame_number, frame);
            }
            self.restore_animation(sa, frames);
        }

        Ok(self.graphics_count() + self.scrollback_count())
    }

    /// Serialize the graphics snapshot to JSON
    pub fn export_json(&self) -> Result<String, GraphicsSerializationError> {
        let snapshot = self.export_snapshot();
        serde_json::to_string(&snapshot)
            .map_err(|e| GraphicsSerializationError::SerdeError(e.to_string()))
    }

    /// Serialize the graphics snapshot to pretty-printed JSON
    pub fn export_json_pretty(&self) -> Result<String, GraphicsSerializationError> {
        let snapshot = self.export_snapshot();
        serde_json::to_string_pretty(&snapshot)
            .map_err(|e| GraphicsSerializationError::SerdeError(e.to_string()))
    }

    /// Import graphics state from JSON
    pub fn import_json(&mut self, json: &str) -> Result<usize, GraphicsSerializationError> {
        let snapshot: GraphicsSnapshot = serde_json::from_str(json)
            .map_err(|e| GraphicsSerializationError::SerdeError(e.to_string()))?;
        self.import_snapshot(&snapshot)
    }

    /// Add a graphic directly to scrollback storage
    fn add_scrollback_graphic(&mut self, graphic: TerminalGraphic) -> bool {
        if !self.image_fits_limits(graphic.width, graphic.height, graphic.pixels.len())
            || !self.evict_until_fits(graphic.pixels.len())
        {
            self.dropped_count += 1;
            return false;
        }
        let max = self.limits().max_scrollback_graphics;
        if max == 0 {
            self.dropped_count += 1;
            return false;
        }
        if self.scrollback.len() >= max {
            self.scrollback.remove(0);
            self.dropped_count += 1;
        }
        self.scrollback.push(graphic);
        true
    }

    fn clear_snapshot_import_state(&mut self) {
        self.placements.clear();
        self.cleared_kitty_placements.clear();
        self.deleted_kitty_placements.clear();
        self.deferred_kitty_deletes.clear();
        self.shared_images.clear();
        self.virtual_placements.clear();
        self.animations.clear();
        self.scrollback.clear();
        self.scrollback_position = 0;
    }

    /// Restore a complete animation from serialized state
    fn restore_animation(
        &mut self,
        sa: &SerializableAnimation,
        frames: HashMap<u32, AnimationFrame>,
    ) {
        for (_, frame) in frames {
            self.add_animation_frame(sa.image_id, frame);
        }

        if let Some(anim) = self.animations.get_mut(&sa.image_id) {
            anim.default_delay_ms = sa.default_delay_ms;
            anim.state = sa.state;
            anim.current_frame = if anim.frames.contains_key(&sa.current_frame) {
                sa.current_frame
            } else {
                anim.frames.keys().min().copied().unwrap_or(1)
            };
            anim.loop_count = sa.loop_count;
            anim.loops_completed = sa.loops_completed;
        }
    }
}

/// Errors that can occur during graphics serialization/deserialization
#[derive(Debug, Clone)]
pub enum GraphicsSerializationError {
    /// Base64 decoding failed
    Base64Decode(String),
    /// Failed to read external image file
    FileRead(String, String),
    /// Failed to write external image file
    FileWrite(String, String),
    /// JSON serialization/deserialization error
    SerdeError(String),
    /// Unsupported snapshot version
    UnsupportedVersion(u32, u32),
}

impl std::fmt::Display for GraphicsSerializationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Base64Decode(msg) => write!(f, "Base64 decode error: {}", msg),
            Self::FileRead(path, msg) => {
                write!(f, "Failed to read image file '{}': {}", path, msg)
            }
            Self::FileWrite(path, msg) => {
                write!(f, "Failed to write image file '{}': {}", path, msg)
            }
            Self::SerdeError(msg) => write!(f, "Serialization error: {}", msg),
            Self::UnsupportedVersion(got, max) => {
                write!(
                    f,
                    "Unsupported snapshot version {} (max supported: {})",
                    got, max
                )
            }
        }
    }
}

impl std::error::Error for GraphicsSerializationError {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graphics::{
        animation::AnimationFrame, next_graphic_id, GraphicProtocol, GraphicsLimits, ImagePlacement,
    };

    fn create_test_graphic() -> TerminalGraphic {
        // 2x2 RGBA image
        let pixels = vec![
            255, 0, 0, 255, // red
            0, 255, 0, 255, // green
            0, 0, 255, 255, // blue
            255, 255, 0, 255, // yellow
        ];
        let mut g = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Kitty,
            (5, 10),
            2,
            2,
            pixels,
        );
        g.kitty_image_id = Some(42);
        g.kitty_placement_id = Some(1);
        g.was_compressed = true;
        g.placement = ImagePlacement {
            z_index: 3,
            preserve_aspect_ratio: true,
            ..Default::default()
        };
        g
    }

    #[test]
    fn test_serializable_graphic_round_trip() {
        let original = create_test_graphic();
        let serializable = SerializableGraphic::from(&original);

        // Check metadata preserved
        assert_eq!(serializable.id, original.id);
        assert_eq!(serializable.protocol, GraphicProtocol::Kitty);
        assert_eq!(serializable.position, (5, 10));
        assert_eq!(serializable.width, 2);
        assert_eq!(serializable.height, 2);
        assert_eq!(serializable.kitty_image_id, Some(42));
        assert!(serializable.was_compressed);
        assert_eq!(serializable.placement.z_index, 3);

        // Convert back
        let restored = serializable.to_terminal_graphic().unwrap();
        assert_eq!(restored.id, original.id);
        assert_eq!(restored.protocol, original.protocol);
        assert_eq!(restored.position, original.position);
        assert_eq!(restored.width, original.width);
        assert_eq!(restored.height, original.height);
        assert_eq!(restored.original_width, original.original_width);
        assert_eq!(restored.original_height, original.original_height);
        assert_eq!(restored.pixels.as_ref(), original.pixels.as_ref());
        assert_eq!(restored.kitty_image_id, original.kitty_image_id);
        assert_eq!(restored.kitty_placement_id, original.kitty_placement_id);
        assert_eq!(restored.was_compressed, original.was_compressed);
        assert_eq!(restored.placement, original.placement);
    }

    #[test]
    fn test_serializable_graphic_json_round_trip() {
        let original = create_test_graphic();
        let serializable = SerializableGraphic::from(&original);

        let json = serde_json::to_string(&serializable).unwrap();
        let deserialized: SerializableGraphic = serde_json::from_str(&json).unwrap();
        let restored = deserialized.to_terminal_graphic().unwrap();

        assert_eq!(restored.id, original.id);
        assert_eq!(restored.pixels.as_ref(), original.pixels.as_ref());
        assert_eq!(restored.placement.z_index, 3);
    }

    #[test]
    fn test_graphics_store_snapshot_round_trip() {
        let mut store = GraphicsStore::new();

        // Add some graphics
        let g1 = create_test_graphic();
        let g2 = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Sixel,
            (0, 0),
            4,
            1,
            vec![128u8; 16],
        );
        store.add_graphic(g1.clone());
        store.add_graphic(g2.clone());

        // Export
        let snapshot = store.export_snapshot();
        assert_eq!(snapshot.version, GraphicsSnapshot::CURRENT_VERSION);
        assert_eq!(snapshot.placements.len(), 2);
        assert_eq!(snapshot.scrollback.len(), 0);

        // Import into a new store
        let mut store2 = GraphicsStore::new();
        let count = store2.import_snapshot(&snapshot).unwrap();
        assert_eq!(count, 2);
        assert_eq!(store2.graphics_count(), 2);

        // Verify first graphic
        let restored = &store2.all_graphics()[0];
        assert_eq!(restored.protocol, GraphicProtocol::Kitty);
        assert_eq!(restored.position, (5, 10));
        assert_eq!(restored.pixels.as_ref(), g1.pixels.as_ref());
    }

    #[test]
    fn test_graphics_store_json_round_trip() {
        let mut store = GraphicsStore::new();
        store.add_graphic(create_test_graphic());

        let json = store.export_json().unwrap();
        assert!(!json.is_empty());

        let mut store2 = GraphicsStore::new();
        let count = store2.import_json(&json).unwrap();
        assert_eq!(count, 1);
        assert_eq!(store2.graphics_count(), 1);
    }

    #[test]
    fn test_graphics_store_export_with_scrollback() {
        let mut store = GraphicsStore::new();

        // Add active graphic
        store.add_graphic(create_test_graphic());

        // Simulate scrollback: add graphic, scroll it off
        let mut g = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Sixel,
            (0, 0),
            10,
            4,
            vec![0u8; 160],
        );
        g.set_cell_dimensions(8, 2);
        store.add_graphic(g);

        // Scroll up enough to push it to scrollback
        store.adjust_for_scroll_up_with_scrollback(10, 0, 23, 0);

        let snapshot = store.export_snapshot();
        // One active graphic remains, the other went to scrollback
        assert_eq!(snapshot.placements.len(), 1);
        assert_eq!(snapshot.scrollback.len(), 1);

        // Round trip
        let mut store2 = GraphicsStore::new();
        let count = store2.import_snapshot(&snapshot).unwrap();
        assert_eq!(count, 2);
        assert_eq!(store2.graphics_count(), 1);
        assert_eq!(store2.scrollback_count(), 1);
    }

    #[test]
    fn test_import_snapshot_counts_only_restored_limited_graphics() {
        let small_active = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Sixel,
            (0, 0),
            1,
            1,
            vec![1; 4],
        );
        let large_active = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Sixel,
            (1, 0),
            2,
            1,
            vec![2; 8],
        );
        let mut small_scrollback = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Sixel,
            (0, 0),
            1,
            1,
            vec![3; 4],
        );
        small_scrollback.scrollback_row = Some(0);
        let mut large_scrollback = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Sixel,
            (1, 0),
            2,
            1,
            vec![4; 8],
        );
        large_scrollback.scrollback_row = Some(1);
        let snapshot = GraphicsSnapshot {
            version: GraphicsSnapshot::CURRENT_VERSION,
            placements: vec![
                SerializableGraphic::from(&small_active),
                SerializableGraphic::from(&large_active),
            ],
            scrollback: vec![
                SerializableGraphic::from(&small_scrollback),
                SerializableGraphic::from(&large_scrollback),
            ],
            animations: vec![],
        };
        let mut store = GraphicsStore::with_limits(GraphicsLimits {
            max_total_memory: 4,
            max_image_bytes: 1024,
            ..GraphicsLimits::default()
        });

        let count = store.import_snapshot(&snapshot).unwrap();

        assert_eq!(count, 1);
        assert_eq!(store.graphics_count(), 0);
        assert_eq!(store.scrollback_count(), 1);
        assert_eq!(store.dropped_count(), 3);
    }

    #[test]
    fn test_graphics_store_export_with_animations() {
        use crate::graphics::animation::AnimationFrame;

        let mut store = GraphicsStore::new();

        // Add animated graphic
        let g = create_test_graphic();
        let image_id = g.kitty_image_id.unwrap();
        store.add_graphic(g);

        // Add animation frames
        let frame1 = AnimationFrame::new(1, vec![255u8; 16], 2, 2).with_delay(100);
        let frame2 = AnimationFrame::new(2, vec![128u8; 16], 2, 2).with_delay(200);
        store.add_animation_frame(image_id, frame1);
        store.add_animation_frame(image_id, frame2);

        let snapshot = store.export_snapshot();
        assert_eq!(snapshot.animations.len(), 1);
        assert_eq!(snapshot.animations[0].image_id, image_id);
        assert_eq!(snapshot.animations[0].frames.len(), 2);

        // Round trip
        let mut store2 = GraphicsStore::new();
        store2.import_snapshot(&snapshot).unwrap();
        let anim = store2.get_animation(image_id).unwrap();
        assert_eq!(anim.frame_count(), 2);
        assert_eq!(anim.default_delay_ms, 100);
    }

    #[test]
    fn test_unsupported_version() {
        let snapshot = GraphicsSnapshot {
            version: 999,
            placements: vec![],
            scrollback: vec![],
            animations: vec![],
        };

        let mut store = GraphicsStore::new();
        let result = store.import_snapshot(&snapshot);
        assert!(result.is_err());
        match result.unwrap_err() {
            GraphicsSerializationError::UnsupportedVersion(got, max) => {
                assert_eq!(got, 999);
                assert_eq!(max, GraphicsSnapshot::CURRENT_VERSION);
            }
            _ => panic!("Expected UnsupportedVersion error"),
        }
    }

    #[test]
    fn test_empty_snapshot() {
        let mut store = GraphicsStore::new();
        let mut virtual_graphic = create_test_graphic();
        virtual_graphic.kitty_image_id = Some(77);
        virtual_graphic.kitty_placement_id = Some(2);

        store.add_graphic(create_test_graphic());
        store.store_kitty_image(77, 1, 1, vec![7; 4]);
        store.add_virtual_placement(virtual_graphic);
        store.add_animation_frame(77, AnimationFrame::new(1, vec![8; 4], 1, 1));
        store.clear();
        store.add_graphic(TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Sixel,
            (0, 0),
            1,
            1,
            vec![9; 4],
        ));

        assert_eq!(store.graphics_count(), 1);
        assert_eq!(store.pending_cleared_kitty_graphics_count(), 1);
        assert!(store.get_kitty_image(77).is_some());
        assert!(!store.all_virtual_placements().is_empty());
        assert!(store.get_animation(77).is_some());

        // Import empty snapshot should clear existing
        let empty = GraphicsSnapshot {
            version: 1,
            placements: vec![],
            scrollback: vec![],
            animations: vec![],
        };
        let count = store.import_snapshot(&empty).unwrap();
        assert_eq!(count, 0);
        assert_eq!(store.graphics_count(), 0);
        assert_eq!(store.pending_cleared_kitty_graphics_count(), 0);
        assert!(store.get_kitty_image(77).is_none());
        assert!(store.all_virtual_placements().is_empty());
        assert!(store.get_animation(77).is_none());
    }

    #[test]
    fn test_import_snapshot_limits_animation_frames() {
        let frame1 = AnimationFrame::new(1, vec![1; 4], 1, 1);
        let frame2 = AnimationFrame::new(2, vec![2; 4], 1, 1);
        let snapshot = GraphicsSnapshot {
            version: GraphicsSnapshot::CURRENT_VERSION,
            placements: vec![],
            scrollback: vec![],
            animations: vec![SerializableAnimation {
                image_id: 99,
                frames: vec![
                    SerializableAnimationFrame::from(&frame1),
                    SerializableAnimationFrame::from(&frame2),
                ],
                default_delay_ms: 100,
                state: crate::graphics::AnimationState::Playing,
                current_frame: 2,
                loop_count: 3,
                loops_completed: 1,
            }],
        };
        let mut store = GraphicsStore::with_limits(GraphicsLimits {
            max_total_memory: 4,
            max_image_bytes: 1024,
            ..GraphicsLimits::default()
        });

        let count = store.import_snapshot(&snapshot).unwrap();

        assert_eq!(count, 0);
        let animation = store.get_animation(99).unwrap();
        assert_eq!(animation.frame_count(), 1);
        assert!(animation.current_frame().is_some());
        assert_eq!(animation.loop_count, 3);
        assert_eq!(animation.loops_completed, 1);
        assert_eq!(store.dropped_count(), 1);
    }

    #[test]
    fn test_file_ref_round_trip() {
        let graphic = create_test_graphic();
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test_image.rgba");
        let path_str = path.to_str().unwrap();

        let sg = SerializableGraphic::with_file_ref(&graphic, path_str).unwrap();
        assert!(matches!(sg.data, ImageDataRef::File(_)));

        // Verify file was written
        let file_data = std::fs::read(&path).unwrap();
        assert_eq!(file_data, graphic.pixels.as_ref().as_slice());

        // Restore from file ref
        let restored = sg.to_terminal_graphic().unwrap();
        assert_eq!(restored.pixels.as_ref(), graphic.pixels.as_ref());
    }

    #[test]
    fn test_image_data_ref_serialization() {
        let inline = ImageDataRef::Inline("dGVzdA==".to_string());
        let json = serde_json::to_string(&inline).unwrap();
        let deserialized: ImageDataRef = serde_json::from_str(&json).unwrap();
        match deserialized {
            ImageDataRef::Inline(data) => assert_eq!(data, "dGVzdA=="),
            _ => panic!("Expected Inline variant"),
        }

        let file_ref = ImageDataRef::File("/tmp/test.rgba".to_string());
        let json = serde_json::to_string(&file_ref).unwrap();
        let deserialized: ImageDataRef = serde_json::from_str(&json).unwrap();
        match deserialized {
            ImageDataRef::File(path) => assert_eq!(path, "/tmp/test.rgba"),
            _ => panic!("Expected File variant"),
        }
    }

    #[test]
    fn test_all_protocols_serialize() {
        for protocol in [
            GraphicProtocol::Sixel,
            GraphicProtocol::ITermInline,
            GraphicProtocol::Kitty,
        ] {
            let g = TerminalGraphic::new(
                next_graphic_id(),
                protocol,
                (0, 0),
                1,
                1,
                vec![255, 0, 0, 255],
            );
            let sg = SerializableGraphic::from(&g);
            let json = serde_json::to_string(&sg).unwrap();
            let deserialized: SerializableGraphic = serde_json::from_str(&json).unwrap();
            let restored = deserialized.to_terminal_graphic().unwrap();
            assert_eq!(restored.protocol, protocol);
        }
    }

    #[test]
    fn test_placement_metadata_preserved() {
        let mut g = create_test_graphic();
        g.placement = ImagePlacement {
            display_mode: crate::graphics::ImageDisplayMode::Download,
            requested_width: crate::graphics::ImageDimension::pixels(100.0),
            requested_height: crate::graphics::ImageDimension::cells(5.0),
            preserve_aspect_ratio: false,
            columns: Some(10),
            rows: Some(5),
            z_index: -1,
            x_offset: 2,
            y_offset: 3,
        };

        let sg = SerializableGraphic::from(&g);
        let json = serde_json::to_string(&sg).unwrap();
        let deserialized: SerializableGraphic = serde_json::from_str(&json).unwrap();
        let restored = deserialized.to_terminal_graphic().unwrap();

        assert_eq!(
            restored.placement.display_mode,
            crate::graphics::ImageDisplayMode::Download
        );
        assert_eq!(restored.placement.requested_width.value, 100.0);
        assert_eq!(
            restored.placement.requested_width.unit,
            crate::graphics::ImageSizeUnit::Pixels
        );
        assert_eq!(restored.placement.requested_height.value, 5.0);
        assert_eq!(
            restored.placement.requested_height.unit,
            crate::graphics::ImageSizeUnit::Cells
        );
        assert!(!restored.placement.preserve_aspect_ratio);
        assert_eq!(restored.placement.columns, Some(10));
        assert_eq!(restored.placement.rows, Some(5));
        assert_eq!(restored.placement.z_index, -1);
        assert_eq!(restored.placement.x_offset, 2);
        assert_eq!(restored.placement.y_offset, 3);
    }
}
