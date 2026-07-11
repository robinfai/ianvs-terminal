//! Unified graphics protocol support
//!
//! Multi-protocol graphics support for Sixel, iTerm2 inline images, and Kitty graphics protocol.
//!
//! # Supported Protocols
//! - **Sixel**: DEC VT340 compatible bitmap graphics
//! - **iTerm2**: OSC 1337 inline images (PNG, JPEG, GIF)
//! - **Kitty**: APC-based graphics protocol with image reuse
//!
//! # Architecture
//! All protocols are normalized to a unified `TerminalGraphic` representation with RGBA pixel data.
//! The `GraphicsStore` handles storage, scrolling, and Kitty image ID reuse.

pub mod animation;
pub mod iterm;
pub mod kitty;
pub mod placeholder;
pub mod serialization;

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;

use serde::{Deserialize, Serialize};

// Re-export for convenience
pub use animation::{Animation, AnimationControl, AnimationFrame, AnimationState, CompositionMode};
pub use iterm::ITermParser;
pub use placeholder::{
    create_placeholder_with_diacritics, number_to_diacritic, PlaceholderInfo, PLACEHOLDER_CHAR,
};
pub use serialization::{GraphicsSnapshot, ImageDataRef, SerializableGraphic};

/// Image display mode for rendering
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum ImageDisplayMode {
    /// Render inline within the terminal grid (default)
    #[default]
    Inline,
    /// Download/save rather than display (iTerm2 inline=0)
    Download,
}

impl ImageDisplayMode {
    /// Get display mode name as string
    pub fn as_str(&self) -> &'static str {
        match self {
            ImageDisplayMode::Inline => "inline",
            ImageDisplayMode::Download => "download",
        }
    }
}

/// Unit for image dimension sizing
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum ImageSizeUnit {
    /// Automatic sizing based on image dimensions (default)
    #[default]
    Auto,
    /// Size in terminal cells
    Cells,
    /// Size in pixels
    Pixels,
    /// Size as percentage of terminal
    Percent,
}

impl ImageSizeUnit {
    /// Get unit name as string
    pub fn as_str(&self) -> &'static str {
        match self {
            ImageSizeUnit::Auto => "auto",
            ImageSizeUnit::Cells => "cells",
            ImageSizeUnit::Pixels => "pixels",
            ImageSizeUnit::Percent => "percent",
        }
    }
}

/// Image dimension with unit
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct ImageDimension {
    /// Numeric value (non-positive values mean auto)
    pub value: f64,
    /// Unit for the value
    pub unit: ImageSizeUnit,
}

impl Default for ImageDimension {
    fn default() -> Self {
        Self {
            value: 0.0,
            unit: ImageSizeUnit::Auto,
        }
    }
}

impl ImageDimension {
    /// Create an auto dimension
    pub fn auto() -> Self {
        Self::default()
    }

    /// Create a dimension with cells unit
    pub fn cells(value: f64) -> Self {
        Self {
            value,
            unit: ImageSizeUnit::Cells,
        }
    }

    /// Create a dimension with pixels unit
    pub fn pixels(value: f64) -> Self {
        Self {
            value,
            unit: ImageSizeUnit::Pixels,
        }
    }

    /// Create a dimension with percent unit
    pub fn percent(value: f64) -> Self {
        Self {
            value,
            unit: ImageSizeUnit::Percent,
        }
    }

    /// Check if this is an auto dimension
    pub fn is_auto(&self) -> bool {
        self.unit == ImageSizeUnit::Auto || !self.value.is_finite() || self.value <= 0.0
    }
}

/// Unified image placement metadata across protocols
///
/// Abstracts placement info from Kitty and iTerm2 so the frontend can implement
/// inline/cover/contain rendering without protocol-specific logic.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct ImagePlacement {
    /// Display mode (inline vs download)
    pub display_mode: ImageDisplayMode,
    /// Requested width for sizing
    pub requested_width: ImageDimension,
    /// Requested height for sizing
    pub requested_height: ImageDimension,
    /// Whether to preserve aspect ratio when scaling
    pub preserve_aspect_ratio: bool,
    /// Number of columns to display (Kitty c= parameter)
    pub columns: Option<u32>,
    /// Number of rows to display (Kitty r= parameter)
    pub rows: Option<u32>,
    /// Z-index for layering (Kitty z= parameter, 0 = default)
    pub z_index: i32,
    /// X offset within the cell in pixels (Kitty X= parameter)
    pub x_offset: u32,
    /// Y offset within the cell in pixels (Kitty Y= parameter)
    pub y_offset: u32,
    /// X offset of the source image rectangle in pixels (Kitty x= parameter)
    #[serde(default)]
    pub source_x_offset: u32,
    /// Y offset of the source image rectangle in pixels (Kitty y= parameter)
    #[serde(default)]
    pub source_y_offset: u32,
    /// Width of the source image rectangle in pixels (Kitty w= parameter)
    #[serde(default)]
    pub source_width: Option<u32>,
    /// Height of the source image rectangle in pixels (Kitty h= parameter)
    #[serde(default)]
    pub source_height: Option<u32>,
}

impl ImagePlacement {
    /// Create a default inline placement
    pub fn inline() -> Self {
        Self {
            display_mode: ImageDisplayMode::Inline,
            preserve_aspect_ratio: true,
            ..Default::default()
        }
    }

    /// Create a download-only placement (iTerm2 inline=0)
    pub fn download() -> Self {
        Self {
            display_mode: ImageDisplayMode::Download,
            ..Default::default()
        }
    }
}

/// Graphics protocol identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GraphicProtocol {
    Sixel,
    ITermInline, // OSC 1337
    Kitty,       // APC graphics protocol
}

impl GraphicProtocol {
    /// Get protocol name as string
    pub fn as_str(&self) -> &'static str {
        match self {
            GraphicProtocol::Sixel => "sixel",
            GraphicProtocol::ITermInline => "iterm",
            GraphicProtocol::Kitty => "kitty",
        }
    }
}

/// Limits for graphics to prevent resource exhaustion
#[derive(Debug, Clone, Copy)]
pub struct GraphicsLimits {
    pub max_width: u32,
    pub max_height: u32,
    pub max_pixels: usize,
    pub max_image_bytes: usize,
    pub max_total_memory: usize,
    pub max_graphics_count: usize,
    pub max_scrollback_graphics: usize,
}

impl Default for GraphicsLimits {
    fn default() -> Self {
        Self {
            max_width: 10000,
            max_height: 10000,
            max_pixels: 25_000_000,              // 25MP
            max_image_bytes: 100 * 1024 * 1024,  // 100MB
            max_total_memory: 256 * 1024 * 1024, // 256MB
            max_graphics_count: 1000,
            max_scrollback_graphics: 500,
        }
    }
}

/// Protocol-agnostic graphic representation
#[derive(Debug, Clone)]
pub struct TerminalGraphic {
    /// Unique placement ID
    pub id: u64,
    /// Graphics protocol used
    pub protocol: GraphicProtocol,
    /// Position in terminal (col, row)
    pub position: (usize, usize),
    /// Width in pixels (may change during animation)
    pub width: usize,
    /// Height in pixels (may change during animation)
    pub height: usize,
    /// Original width in pixels as decoded from source image
    pub original_width: usize,
    /// Original height in pixels as decoded from source image
    pub original_height: usize,
    /// RGBA pixel data (Arc for Kitty sharing)
    pub pixels: Arc<Vec<u8>>,
    /// Stable content version derived from dimensions and RGBA data
    pub asset_version: u64,
    /// Cell dimensions (cell_width, cell_height) for rendering
    pub cell_dimensions: Option<(u32, u32)>,
    /// Resolved display span in terminal cells for hit testing
    pub display_cell_span: Option<(usize, usize)>,
    /// Rows scrolled off visible area (for partial rendering)
    pub scroll_offset_rows: usize,
    /// Row in scrollback buffer (only set when in scrollback)
    pub scrollback_row: Option<usize>,
    /// Whether this placement belongs to the alternate screen buffer
    pub alternate_screen: bool,

    // Kitty-specific (None for other protocols)
    /// Kitty image ID for image reuse
    pub kitty_image_id: Option<u32>,
    /// Protocol-neutral animation ID used to connect animated placements to
    /// frames in the animation store.
    pub animation_id: Option<u32>,
    /// Kitty placement ID
    pub kitty_placement_id: Option<u32>,
    /// Virtual placement (U=1) - used as prototype for Unicode placeholders
    pub is_virtual: bool,
    /// Parent placement for relative positioning (P= key)
    pub parent_image_id: Option<u32>,
    /// Parent placement ID for relative positioning (Q= key)
    pub parent_placement_id: Option<u32>,
    /// X offset relative to parent placement (in pixels)
    pub relative_x_offset: i32,
    /// Y offset relative to parent placement (in pixels)
    pub relative_y_offset: i32,
    /// Whether the original data was compressed (for diagnostics)
    pub was_compressed: bool,
    /// Unified placement metadata (display mode, sizing, z-index, offsets)
    pub placement: ImagePlacement,
}

impl TerminalGraphic {
    /// Create a new terminal graphic
    pub fn new(
        id: u64,
        protocol: GraphicProtocol,
        position: (usize, usize),
        width: usize,
        height: usize,
        pixels: Vec<u8>,
    ) -> Self {
        Self {
            id,
            protocol,
            position,
            width,
            height,
            original_width: width,
            original_height: height,
            asset_version: graphic_content_version(width, height, &pixels),
            pixels: Arc::new(pixels),
            cell_dimensions: None,
            display_cell_span: None,
            scroll_offset_rows: 0,
            scrollback_row: None,
            alternate_screen: false,
            kitty_image_id: None,
            animation_id: None,
            kitty_placement_id: None,
            is_virtual: false,
            parent_image_id: None,
            parent_placement_id: None,
            relative_x_offset: 0,
            relative_y_offset: 0,
            was_compressed: false,
            placement: ImagePlacement::inline(),
        }
    }

    /// Create with shared pixel data (for Kitty image reuse)
    pub fn with_shared_pixels(
        id: u64,
        protocol: GraphicProtocol,
        position: (usize, usize),
        width: usize,
        height: usize,
        pixels: Arc<Vec<u8>>,
    ) -> Self {
        Self {
            id,
            protocol,
            position,
            width,
            height,
            original_width: width,
            original_height: height,
            asset_version: graphic_content_version(width, height, pixels.as_ref()),
            pixels,
            cell_dimensions: None,
            display_cell_span: None,
            scroll_offset_rows: 0,
            scrollback_row: None,
            alternate_screen: false,
            kitty_image_id: None,
            animation_id: None,
            kitty_placement_id: None,
            is_virtual: false,
            parent_image_id: None,
            parent_placement_id: None,
            relative_x_offset: 0,
            relative_y_offset: 0,
            was_compressed: false,
            placement: ImagePlacement::inline(),
        }
    }

    /// Set cell dimensions used when creating this graphic
    pub fn set_cell_dimensions(&mut self, cell_width: u32, cell_height: u32) {
        self.cell_dimensions = Some((cell_width, cell_height));
    }

    /// Set the resolved display span used by scoped Kitty deletes.
    pub fn set_display_cell_span(&mut self, columns: usize, rows: usize) {
        self.display_cell_span = Some((columns.max(1), rows.max(1)));
    }

    /// Mark which screen buffer owns this placement.
    pub fn set_alternate_screen(&mut self, alternate_screen: bool) {
        self.alternate_screen = alternate_screen;
    }

    /// Calculate display cell span using placement sizing and optional terminal size.
    pub fn resolved_cell_span(
        &self,
        viewport_cols: Option<usize>,
        viewport_rows: Option<usize>,
    ) -> (usize, usize) {
        let cell_width = self.cell_dimensions.map(|(w, _)| w as usize).unwrap_or(1);
        let cell_height = self.cell_dimensions.map(|(_, h)| h as usize).unwrap_or(2);
        let cell_width = cell_width.max(1);
        let cell_height = cell_height.max(1);
        let (_, _, source_width, source_height) =
            self.source_rect_pixels()
                .unwrap_or((0, 0, self.width.max(1), self.height.max(1)));
        let requested_width = graphic_dimension_px_for_cell_span(
            self.placement.requested_width,
            source_width,
            cell_width,
            viewport_cols.map(|cols| cols.saturating_mul(cell_width).max(cell_width)),
        );
        let requested_height = graphic_dimension_px_for_cell_span(
            self.placement.requested_height,
            source_height,
            cell_height,
            viewport_rows.map(|rows| rows.saturating_mul(cell_height).max(cell_height)),
        );

        let (width_px, height_px) = match (requested_width, requested_height) {
            (Some(width), Some(height)) => (width, height),
            (Some(width), None) if self.placement.preserve_aspect_ratio && source_width > 0 => {
                let height = ((width as f64 * source_height as f64) / source_width as f64)
                    .round()
                    .max(1.0) as usize;
                (width, height)
            }
            (None, Some(height)) if self.placement.preserve_aspect_ratio && source_height > 0 => {
                let width = ((height as f64 * source_width as f64) / source_height as f64)
                    .round()
                    .max(1.0) as usize;
                (width, height)
            }
            (Some(width), None) => (width, source_height.max(1)),
            (None, Some(height)) => (source_width.max(1), height),
            _ => (source_width.max(1), source_height.max(1)),
        };

        let width_span_px = (self.placement.x_offset as usize).saturating_add(width_px);
        let height_span_px = (self.placement.y_offset as usize).saturating_add(height_px);

        (
            width_span_px.div_ceil(cell_width).max(1),
            height_span_px.div_ceil(cell_height).max(1),
        )
    }

    /// Source image rectangle requested by Kitty placement metadata.
    pub fn source_rect_pixels(&self) -> Option<(usize, usize, usize, usize)> {
        let source_x = (self.placement.source_x_offset as usize).min(self.width);
        let source_y = (self.placement.source_y_offset as usize).min(self.height);
        let available_width = self.width.saturating_sub(source_x);
        let available_height = self.height.saturating_sub(source_y);
        if available_width == 0 || available_height == 0 {
            return None;
        }
        let requested_width = self.placement.source_width.unwrap_or(0) as usize;
        let requested_height = self.placement.source_height.unwrap_or(0) as usize;
        let source_width = if requested_width == 0 {
            available_width
        } else {
            requested_width.min(available_width)
        };
        let source_height = if requested_height == 0 {
            available_height
        } else {
            requested_height.min(available_height)
        };
        if source_width == 0 || source_height == 0 {
            return None;
        }
        Some((source_x, source_y, source_width, source_height))
    }

    /// Calculate how many terminal cells this graphic spans
    pub fn cell_span(&self, fallback_cell_width: u32, fallback_cell_height: u32) -> (usize, usize) {
        let (cell_w, cell_h) = self
            .cell_dimensions
            .unwrap_or((fallback_cell_width, fallback_cell_height));
        let cols = (self.width as u32).div_ceil(cell_w) as usize;
        let rows = (self.height as u32).div_ceil(cell_h) as usize;
        (cols, rows)
    }

    /// Get RGBA color at pixel coordinates
    pub fn pixel_at(&self, x: usize, y: usize) -> Option<(u8, u8, u8, u8)> {
        if x >= self.width || y >= self.height {
            return None;
        }
        let offset = (y * self.width + x) * 4;
        if offset + 3 >= self.pixels.len() {
            return None;
        }
        Some((
            self.pixels[offset],
            self.pixels[offset + 1],
            self.pixels[offset + 2],
            self.pixels[offset + 3],
        ))
    }

    /// Alias for pixel_at (compatibility with SixelGraphic API)
    pub fn get_pixel(&self, x: usize, y: usize) -> Option<(u8, u8, u8, u8)> {
        self.pixel_at(x, y)
    }

    /// Sample color for half-block cell rendering
    /// Returns (top_half_rgba, bottom_half_rgba) for the cell at (col, row)
    #[allow(clippy::type_complexity)]
    pub fn sample_half_block(
        &self,
        cell_col: usize,
        cell_row: usize,
        cell_width: u32,
        cell_height: u32,
    ) -> Option<((u8, u8, u8, u8), (u8, u8, u8, u8))> {
        // Calculate pixel coordinates relative to graphic position
        let rel_col = cell_col.checked_sub(self.position.0)?;
        let rel_row = cell_row.checked_sub(self.position.1)?;

        let px_x = rel_col * cell_width as usize;
        let px_y = rel_row * cell_height as usize;

        // Sample center of top and bottom halves
        let top_y = px_y + cell_height as usize / 4;
        let bottom_y = px_y + (cell_height as usize * 3) / 4;
        let center_x = px_x + cell_width as usize / 2;

        let top = self.pixel_at(center_x, top_y)?;
        let bottom = self.pixel_at(center_x, bottom_y)?;

        Some((top, bottom))
    }

    /// Get dimensions in terminal cells
    pub fn cell_size(&self, cell_width: u32, cell_height: u32) -> (usize, usize) {
        let cols = self.width.div_ceil(cell_width as usize);
        let rows = self.height.div_ceil(cell_height as usize);
        (cols, rows)
    }

    /// Calculate height in terminal rows
    pub fn height_in_rows(&self, cell_height: u32) -> usize {
        let cell_h = self.cell_dimensions.map(|(_, h)| h).unwrap_or(cell_height);
        (self.height as u32).div_ceil(cell_h) as usize
    }
}

/// Global counter for unique graphic IDs
static GRAPHIC_ID_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
static LOCAL_KITTY_IMAGE_ID_COUNTER: AtomicU32 = AtomicU32::new(0x4000_0000);
static LOCAL_ANIMATION_ID_COUNTER: AtomicU32 = AtomicU32::new(0x8000_0000);

/// Generate a unique graphic placement ID
pub fn next_graphic_id() -> u64 {
    GRAPHIC_ID_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}

const FNV_OFFSET_BASIS: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x00000100000001b3;
const GRAPHIC_CONTENT_VERSION_MASK: u64 = (1_u64 << 53) - 1;

fn fnv_mix_bytes(mut hash: u64, bytes: &[u8]) -> u64 {
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

fn fnv_mix_u64(hash: u64, value: u64) -> u64 {
    fnv_mix_bytes(hash, &value.to_le_bytes())
}

/// Stable non-zero content version for decoded image data.
pub fn graphic_content_version(width: usize, height: usize, pixels: &[u8]) -> u64 {
    let hash = fnv_mix_bytes(
        fnv_mix_u64(fnv_mix_u64(FNV_OFFSET_BASIS, width as u64), height as u64),
        pixels,
    );
    (hash & GRAPHIC_CONTENT_VERSION_MASK).max(1)
}

fn graphic_dimension_px_for_cell_span(
    dimension: ImageDimension,
    fallback_px: usize,
    cell_px: usize,
    terminal_px: Option<usize>,
) -> Option<usize> {
    if dimension.is_auto() {
        return None;
    }
    let value = dimension.value.max(0.0);
    let px = match dimension.unit {
        ImageSizeUnit::Auto => fallback_px,
        ImageSizeUnit::Cells => (value * cell_px as f64).round() as usize,
        ImageSizeUnit::Pixels => value.round() as usize,
        ImageSizeUnit::Percent => {
            let terminal_px = terminal_px?;
            ((value / 100.0) * terminal_px as f64).round() as usize
        }
    };
    Some(px.max(1))
}

fn graphic_cell_span(graphic: &TerminalGraphic) -> (usize, usize) {
    graphic
        .display_cell_span
        .unwrap_or_else(|| graphic.resolved_cell_span(None, None))
}

fn graphic_intersects_column(graphic: &TerminalGraphic, col: usize) -> bool {
    let (width_cells, _) = graphic_cell_span(graphic);
    let start_col = graphic.position.0;
    let end_col = start_col.saturating_add(width_cells);
    col >= start_col && col < end_col
}

fn graphic_intersects_row(graphic: &TerminalGraphic, row: usize) -> bool {
    let (_, height_cells) = graphic_cell_span(graphic);
    let start_row = graphic.position.1;
    let end_row = start_row.saturating_add(height_cells);
    row >= start_row && row < end_row
}

fn graphic_intersects_cell(graphic: &TerminalGraphic, col: usize, row: usize) -> bool {
    graphic_intersects_column(graphic, col) && graphic_intersects_row(graphic, row)
}

fn graphic_intersects_rect(
    graphic: &TerminalGraphic,
    start_col: usize,
    start_row: usize,
    end_col: usize,
    end_row: usize,
) -> bool {
    if start_col >= end_col || start_row >= end_row {
        return false;
    }

    let (width_cells, height_cells) = graphic_cell_span(graphic);
    let graphic_start_col = graphic.position.0;
    let graphic_end_col = graphic_start_col.saturating_add(width_cells);
    let graphic_start_row = graphic.position.1;
    let graphic_end_row = graphic_start_row.saturating_add(height_cells);

    graphic_start_col < end_col
        && graphic_end_col > start_col
        && graphic_start_row < end_row
        && graphic_end_row > start_row
}

fn screen_filter_excludes(graphic: &TerminalGraphic, alternate_screen: Option<bool>) -> bool {
    alternate_screen
        .map(|screen| graphic.alternate_screen != screen)
        .unwrap_or(false)
}

fn kitty_delete_criteria_matches(
    graphic: &TerminalGraphic,
    image_id: Option<u32>,
    placement_id: Option<u32>,
    alternate_screen: Option<bool>,
) -> bool {
    if graphic.protocol != GraphicProtocol::Kitty
        || screen_filter_excludes(graphic, alternate_screen)
    {
        return false;
    }
    if let Some(image_id) = image_id {
        if graphic.kitty_image_id != Some(image_id) {
            return false;
        }
    }
    if let Some(placement_id) = placement_id {
        if graphic.kitty_placement_id != Some(placement_id) {
            return false;
        }
    }
    true
}

fn add_signed_saturating(value: usize, delta: i32) -> usize {
    if delta >= 0 {
        value.saturating_add(delta as usize)
    } else {
        value.saturating_sub(delta.unsigned_abs() as usize)
    }
}

fn relative_kitty_position(
    parent_position: (usize, usize),
    child: &TerminalGraphic,
) -> (usize, usize) {
    (
        add_signed_saturating(parent_position.0, child.relative_x_offset),
        add_signed_saturating(parent_position.1, child.relative_y_offset),
    )
}

#[allow(clippy::too_many_arguments)]
fn compose_frame_pixels(
    source: &AnimationFrame,
    destination: &mut AnimationFrame,
    source_x: usize,
    source_y: usize,
    source_width: Option<usize>,
    source_height: Option<usize>,
    destination_x: usize,
    destination_y: usize,
    composition: CompositionMode,
) -> bool {
    if source.pixels.len() != source.width.saturating_mul(source.height).saturating_mul(4)
        || destination.pixels.len()
            != destination
                .width
                .saturating_mul(destination.height)
                .saturating_mul(4)
    {
        return false;
    }
    if source_x >= source.width
        || source_y >= source.height
        || destination_x >= destination.width
        || destination_y >= destination.height
    {
        return false;
    }

    let available_source_width = source.width.saturating_sub(source_x);
    let available_source_height = source.height.saturating_sub(source_y);
    let requested_width = source_width.unwrap_or(available_source_width);
    let requested_height = source_height.unwrap_or(available_source_height);
    let width = requested_width
        .min(available_source_width)
        .min(destination.width.saturating_sub(destination_x));
    let height = requested_height
        .min(available_source_height)
        .min(destination.height.saturating_sub(destination_y));
    if width == 0 || height == 0 {
        return false;
    }

    let mut destination_pixels = destination.pixels.as_ref().clone();
    for row in 0..height {
        for col in 0..width {
            let source_index = ((source_y + row) * source.width + source_x + col).saturating_mul(4);
            let destination_index =
                ((destination_y + row) * destination.width + destination_x + col).saturating_mul(4);
            let source_pixel = &source.pixels[source_index..source_index + 4];
            let destination_pixel =
                &mut destination_pixels[destination_index..destination_index + 4];
            match composition {
                CompositionMode::Overwrite => destination_pixel.copy_from_slice(source_pixel),
                CompositionMode::AlphaBlend => {
                    alpha_blend_pixel_over(source_pixel, destination_pixel)
                }
            }
        }
    }
    destination.pixels = Arc::new(destination_pixels);
    true
}

fn alpha_blend_pixel_over(source: &[u8], destination: &mut [u8]) {
    let source_alpha = source[3] as f32 / 255.0;
    let destination_alpha = destination[3] as f32 / 255.0;
    let output_alpha = source_alpha + destination_alpha * (1.0 - source_alpha);
    if output_alpha <= f32::EPSILON {
        destination.copy_from_slice(&[0, 0, 0, 0]);
        return;
    }

    for channel in 0..3 {
        let source_channel = source[channel] as f32 / 255.0;
        let destination_channel = destination[channel] as f32 / 255.0;
        let output_channel = (source_channel * source_alpha
            + destination_channel * destination_alpha * (1.0 - source_alpha))
            / output_alpha;
        destination[channel] = (output_channel * 255.0).round().clamp(0.0, 255.0) as u8;
    }
    destination[3] = (output_alpha * 255.0).round().clamp(0.0, 255.0) as u8;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct KittyDeferredDelete {
    image_id: Option<u32>,
    placement_id: Option<u32>,
    alternate_screen: Option<bool>,
}

impl KittyDeferredDelete {
    fn matches(&self, graphic: &TerminalGraphic) -> bool {
        if graphic.protocol != GraphicProtocol::Kitty {
            return false;
        }
        if let Some(alternate_screen) = self.alternate_screen {
            if graphic.alternate_screen != alternate_screen {
                return false;
            }
        }
        if let Some(image_id) = self.image_id {
            if graphic.kitty_image_id != Some(image_id) {
                return false;
            }
        }
        if let Some(placement_id) = self.placement_id {
            if graphic.kitty_placement_id != Some(placement_id) {
                return false;
            }
        }
        true
    }

    fn matches_criteria(
        &self,
        image_id: Option<u32>,
        placement_id: Option<u32>,
        alternate_screen: Option<bool>,
    ) -> bool {
        if let Some(alternate_screen) = alternate_screen {
            if self.alternate_screen != Some(alternate_screen) {
                return false;
            }
        }
        if let Some(image_id) = image_id {
            if self.image_id != Some(image_id) {
                return false;
            }
        }
        if let Some(placement_id) = placement_id {
            if self.placement_id != Some(placement_id) {
                return false;
            }
        }
        true
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct KittyPlacementKey {
    alternate_screen: bool,
    image_id: u32,
    placement_id: u32,
}

impl KittyPlacementKey {
    fn for_graphic(graphic: &TerminalGraphic) -> Option<Self> {
        if graphic.protocol != GraphicProtocol::Kitty {
            return None;
        }
        Some(Self {
            alternate_screen: graphic.alternate_screen,
            image_id: graphic.kitty_image_id?,
            placement_id: graphic.kitty_placement_id?,
        })
    }
}

fn kitty_relative_parent_matches_key(graphic: &TerminalGraphic, key: KittyPlacementKey) -> bool {
    graphic.protocol == GraphicProtocol::Kitty
        && graphic.alternate_screen == key.alternate_screen
        && graphic.parent_image_id == Some(key.image_id)
        && graphic
            .parent_placement_id
            .map(|placement_id| placement_id == key.placement_id)
            .unwrap_or(true)
}

/// Centralized graphics storage supporting image reuse
#[derive(Debug, Default)]
pub struct GraphicsStore {
    /// Kitty shared images: image_id -> (width, height, pixel_data)
    shared_images: HashMap<u32, (usize, usize, Arc<Vec<u8>>)>,

    /// Kitty image-number history: image_number -> newest-to-oldest image ids.
    ///
    /// The protocol allows clients to create images with non-unique I= numbers
    /// and then refer to only the newest image carrying that number.
    kitty_image_numbers: HashMap<u32, Vec<u32>>,

    /// All active placements (visible area)
    placements: Vec<TerminalGraphic>,

    /// Recently cleared Kitty placements. These are no longer visible, but a
    /// redraw that immediately follows ED 2/3 can reuse their render identity
    /// so frontends keep double-buffered image state across clear/redraw cycles.
    cleared_kitty_placements: Vec<TerminalGraphic>,

    /// Virtual placements - prototypes for Unicode placeholder images
    /// Key is (image_id, placement_id)
    virtual_placements: HashMap<(u32, u32), TerminalGraphic>,

    /// Animations indexed by image ID
    animations: HashMap<u32, Animation>,

    /// Graphics in scrollback (keyed by scrollback row)
    scrollback: Vec<TerminalGraphic>,

    /// Text scrollback length observed by the last synchronized terminal scroll.
    tracked_text_scrollback_len: usize,

    /// Current scrollback row counter (incremented when lines scroll off)
    scrollback_position: usize,

    /// Resource limits
    limits: GraphicsLimits,

    /// Count of graphics dropped due to limits
    dropped_count: usize,

    /// Kitty deletes waiting for a replacement transfer to settle.
    deferred_kitty_deletes: Vec<KittyDeferredDelete>,

    /// Kitty placements removed from active protocol state but retained briefly
    /// so an immediate replacement can reuse the same render identity.
    deleted_kitty_placements: Vec<TerminalGraphic>,
}

impl GraphicsStore {
    /// Create a new graphics store with default limits
    pub fn new() -> Self {
        Self::default()
    }

    /// Create with custom limits
    pub fn with_limits(limits: GraphicsLimits) -> Self {
        Self {
            limits,
            ..Default::default()
        }
    }

    /// Allocate a protocol-neutral animation ID for images that do not carry
    /// a protocol-native image identifier.
    pub fn allocate_local_animation_id(&self) -> u32 {
        for _ in 0..u32::MAX {
            let id = LOCAL_ANIMATION_ID_COUNTER.fetch_add(1, Ordering::Relaxed);
            let id = if id == 0 { 0x8000_0000 } else { id };
            if self.animations.contains_key(&id) || self.shared_images.contains_key(&id) {
                continue;
            }
            let used_by_kitty_placement = self
                .placements
                .iter()
                .chain(self.scrollback.iter())
                .chain(self.virtual_placements.values())
                .any(|graphic| graphic.kitty_image_id == Some(id));
            if !used_by_kitty_placement {
                return id;
            }
        }
        LOCAL_ANIMATION_ID_COUNTER.fetch_add(1, Ordering::Relaxed)
    }

    /// Resolve Kitty relative placement metadata into an absolute terminal cell
    /// position that the existing renderer and frame protocol can consume.
    pub fn resolve_relative_kitty_placement(
        &self,
        graphic: &mut TerminalGraphic,
    ) -> Result<(), GraphicsError> {
        if graphic.protocol != GraphicProtocol::Kitty
            || (graphic.parent_image_id.is_none() && graphic.parent_placement_id.is_none())
        {
            return Ok(());
        }
        let parent_image_id = graphic.parent_image_id.ok_or_else(|| {
            GraphicsError::KittyError("Relative placement requires parent image ID".to_string())
        })?;
        let parent_position = self
            .relative_kitty_parent_position(
                graphic.alternate_screen,
                parent_image_id,
                graphic.parent_placement_id,
            )
            .ok_or_else(|| {
                GraphicsError::KittyError("Parent image placement not found".to_string())
            })?;

        graphic.position = relative_kitty_position(parent_position, graphic);
        Ok(())
    }

    fn relative_kitty_parent_position(
        &self,
        alternate_screen: bool,
        parent_image_id: u32,
        parent_placement_id: Option<u32>,
    ) -> Option<(usize, usize)> {
        self.placements
            .iter()
            .chain(self.virtual_placements.values())
            .find(|candidate| {
                candidate.protocol == GraphicProtocol::Kitty
                    && candidate.alternate_screen == alternate_screen
                    && candidate.kitty_image_id == Some(parent_image_id)
                    && parent_placement_id
                        .map(|placement_id| candidate.kitty_placement_id == Some(placement_id))
                        .unwrap_or(true)
            })
            .map(|candidate| candidate.position)
    }

    /// Add a graphic placement
    pub fn add_graphic(&mut self, mut graphic: TerminalGraphic) -> bool {
        let placement_key = KittyPlacementKey::for_graphic(&graphic);
        if !self.image_fits_limits(graphic.width, graphic.height, graphic.pixels.len())
            || !self.evict_until_fits(graphic.pixels.len())
        {
            self.dropped_count += 1;
            return false;
        }

        if graphic.protocol == GraphicProtocol::Kitty {
            let existing_placement_id = self.matching_kitty_graphic_id(&graphic);
            let deferred_placement_id = self.resolve_deferred_kitty_deletes_for_graphic(&graphic);
            let cleared_placement_id = self.matching_cleared_kitty_graphic_id(&graphic);
            if let Some(placement_id) = existing_placement_id
                .or(deferred_placement_id)
                .or(cleared_placement_id)
            {
                graphic.id = placement_id;
                self.clear_deleted_kitty_placement_id(placement_id);
                self.clear_cleared_kitty_placement_id(placement_id);
            }
        }

        if let (GraphicProtocol::Kitty, Some(image_id), Some(placement_id)) = (
            graphic.protocol,
            graphic.kitty_image_id,
            graphic.kitty_placement_id,
        ) {
            self.placements.retain(|existing| {
                existing.protocol != GraphicProtocol::Kitty
                    || existing.alternate_screen != graphic.alternate_screen
                    || existing.kitty_image_id != Some(image_id)
                    || existing.kitty_placement_id != Some(placement_id)
            });
        }

        self.deferred_kitty_deletes
            .retain(|pending| !pending.matches(&graphic));
        self.deleted_kitty_placements
            .retain(|deleted| deleted.id != graphic.id);

        // Enforce placement limit
        if self.placements.len() >= self.limits.max_graphics_count {
            // Remove oldest placement
            self.placements.remove(0);
            self.dropped_count += 1;
        }
        self.placements.push(graphic);
        if let Some(placement_key) = placement_key {
            self.update_relative_kitty_descendants(placement_key);
        }
        true
    }

    fn update_relative_kitty_descendants(&mut self, parent_key: KittyPlacementKey) {
        let mut pending = vec![parent_key];
        let mut visited = HashSet::new();

        while let Some(key) = pending.pop() {
            if !visited.insert(key) {
                continue;
            }
            let Some(parent_position) = self
                .placements
                .iter()
                .chain(self.virtual_placements.values())
                .find(|graphic| KittyPlacementKey::for_graphic(graphic) == Some(key))
                .map(|graphic| graphic.position)
            else {
                continue;
            };

            for graphic in &mut self.placements {
                if !kitty_relative_parent_matches_key(graphic, key) {
                    continue;
                }
                let next_position = relative_kitty_position(parent_position, graphic);
                if graphic.position != next_position {
                    graphic.position = next_position;
                }
                if let Some(child_key) = KittyPlacementKey::for_graphic(graphic) {
                    pending.push(child_key);
                }
            }

            for graphic in self.virtual_placements.values_mut() {
                if !kitty_relative_parent_matches_key(graphic, key) {
                    continue;
                }
                let next_position = relative_kitty_position(parent_position, graphic);
                if graphic.position != next_position {
                    graphic.position = next_position;
                }
                if let Some(child_key) = KittyPlacementKey::for_graphic(graphic) {
                    pending.push(child_key);
                }
            }
        }
    }

    fn expand_with_relative_descendants(
        &self,
        mut keys: HashSet<KittyPlacementKey>,
    ) -> HashSet<KittyPlacementKey> {
        let mut pending = keys.iter().copied().collect::<Vec<_>>();
        while let Some(key) = pending.pop() {
            for graphic in self
                .placements
                .iter()
                .chain(self.cleared_kitty_placements.iter())
                .chain(self.deleted_kitty_placements.iter())
                .chain(self.virtual_placements.values())
            {
                if !kitty_relative_parent_matches_key(graphic, key) {
                    continue;
                }
                let Some(child_key) = KittyPlacementKey::for_graphic(graphic) else {
                    continue;
                };
                if keys.insert(child_key) {
                    pending.push(child_key);
                }
            }
        }
        keys
    }

    /// Remove a graphic by ID
    pub fn remove_graphic(&mut self, id: u64) {
        self.placements.retain(|g| g.id != id);
        self.clear_deleted_kitty_placement_id(id);
        self.clear_cleared_kitty_placement_id(id);
    }

    /// Get graphics at a specific row
    pub fn graphics_at_row(&self, row: usize) -> Vec<&TerminalGraphic> {
        self.placements
            .iter()
            .filter(|g| {
                let start_row = g.position.1;
                let (_, height_cells) = graphic_cell_span(g);
                let end_row = start_row.saturating_add(height_cells);
                row >= start_row && row < end_row
            })
            .collect()
    }

    /// Get all active graphics
    pub fn all_graphics(&self) -> &[TerminalGraphic] {
        &self.placements
    }

    /// Get Kitty placements that were cleared by ED 2/3 but may be redrawn shortly.
    pub fn pending_cleared_kitty_graphics(&self) -> &[TerminalGraphic] {
        &self.cleared_kitty_placements
    }

    /// Get mutable access to all graphics
    pub fn all_graphics_mut(&mut self) -> &mut Vec<TerminalGraphic> {
        &mut self.placements
    }

    /// Refresh cell metrics for every stored placement.
    pub fn refresh_cell_dimensions(
        &mut self,
        cell_width: u32,
        cell_height: u32,
        cols: usize,
        rows: usize,
    ) {
        let cell_width = cell_width.max(1);
        let cell_height = cell_height.max(1);
        for graphic in &mut self.placements {
            refresh_graphic_cell_dimensions(graphic, cell_width, cell_height, cols, rows);
        }
        for graphic in &mut self.cleared_kitty_placements {
            refresh_graphic_cell_dimensions(graphic, cell_width, cell_height, cols, rows);
        }
        for graphic in self.virtual_placements.values_mut() {
            refresh_graphic_cell_dimensions(graphic, cell_width, cell_height, cols, rows);
        }
        for graphic in &mut self.scrollback {
            refresh_graphic_cell_dimensions(graphic, cell_width, cell_height, cols, rows);
        }
        for graphic in &mut self.deleted_kitty_placements {
            refresh_graphic_cell_dimensions(graphic, cell_width, cell_height, cols, rows);
        }
    }

    /// Get total graphics count
    pub fn graphics_count(&self) -> usize {
        self.placements.len()
    }

    /// Get pending cleared Kitty placement count for diagnostics and frame coalescing.
    pub fn pending_cleared_kitty_graphics_count(&self) -> usize {
        self.cleared_kitty_placements.len()
    }

    /// Get count of graphics dropped due to limits
    pub fn dropped_count(&self) -> usize {
        self.dropped_count
    }

    /// Get current limits
    pub fn limits(&self) -> &GraphicsLimits {
        &self.limits
    }

    /// Maximum decoded image payload bytes accepted by parsers before storage.
    pub fn max_decoded_image_bytes(&self) -> usize {
        self.limits
            .max_image_bytes
            .min(self.limits.max_total_memory)
    }

    /// Set maximum graphics count
    pub fn set_max_graphics(&mut self, max: usize) {
        self.limits.max_graphics_count = max;
        // Enforce new limit
        while self.placements.len() > max {
            self.placements.remove(0);
        }
    }

    /// Replace graphics limits and evict existing data until the store fits.
    pub fn set_limits(&mut self, limits: GraphicsLimits) {
        self.limits = limits;
        self.enforce_limits();
    }

    /// Clear all graphics
    pub fn clear(&mut self) {
        let cleared_kitty_placements = self
            .placements
            .iter()
            .filter(|graphic| graphic.protocol == GraphicProtocol::Kitty)
            .cloned()
            .collect::<Vec<_>>();
        if !cleared_kitty_placements.is_empty() {
            self.cleared_kitty_placements = cleared_kitty_placements;
        }
        self.placements.clear();
        self.deferred_kitty_deletes.clear();
        self.deleted_kitty_placements.clear();
    }

    /// Clear graphics for one screen buffer.
    pub fn clear_screen(&mut self, alternate_screen: bool) {
        let cleared_kitty_placements = self
            .placements
            .iter()
            .filter(|graphic| {
                graphic.protocol == GraphicProtocol::Kitty
                    && graphic.alternate_screen == alternate_screen
            })
            .cloned()
            .collect::<Vec<_>>();
        if !cleared_kitty_placements.is_empty() {
            self.cleared_kitty_placements
                .retain(|graphic| graphic.alternate_screen != alternate_screen);
            self.cleared_kitty_placements
                .extend(cleared_kitty_placements);
        }
        self.placements
            .retain(|graphic| graphic.alternate_screen != alternate_screen);
        self.deferred_kitty_deletes
            .retain(|delete| delete.alternate_screen != Some(alternate_screen));
        self.deleted_kitty_placements
            .retain(|graphic| graphic.alternate_screen != alternate_screen);
        self.virtual_placements
            .retain(|_, graphic| graphic.alternate_screen != alternate_screen);
    }

    /// Remove all graphics owned by the alternate screen buffer.
    pub fn clear_alternate_screen_graphics(&mut self) {
        self.clear_screen(true);
        self.cleared_kitty_placements
            .retain(|graphic| !graphic.alternate_screen);
    }

    /// Delete active graphics that intersect a terminal cell rectangle on one screen buffer.
    pub fn delete_graphics_intersecting_rect_for_screen(
        &mut self,
        start_col: usize,
        start_row: usize,
        end_col: usize,
        end_row: usize,
        alternate_screen: bool,
    ) {
        if start_col >= end_col || start_row >= end_row {
            return;
        }
        let mut deleted_kitty_placements = Vec::new();
        self.placements.retain(|graphic| {
            let should_delete = graphic.alternate_screen == alternate_screen
                && graphic_intersects_rect(graphic, start_col, start_row, end_col, end_row);
            if should_delete && graphic.protocol == GraphicProtocol::Kitty {
                deleted_kitty_placements.push(graphic.clone());
            }
            !should_delete
        });
        self.remember_deleted_kitty_placements(deleted_kitty_placements);
    }

    fn remember_deleted_kitty_placements(
        &mut self,
        deleted_kitty_placements: Vec<TerminalGraphic>,
    ) {
        for graphic in deleted_kitty_placements {
            let image_id = graphic.kitty_image_id;
            let placement_id = graphic.kitty_placement_id;
            let alternate_screen = graphic.alternate_screen;
            self.deleted_kitty_placements
                .retain(|deleted| deleted.id != graphic.id);
            self.deleted_kitty_placements.push(graphic);
            self.defer_kitty_delete_for_screen(image_id, placement_id, Some(alternate_screen));
        }
        while self.deleted_kitty_placements.len() > self.limits.max_graphics_count {
            self.deleted_kitty_placements.remove(0);
        }
    }

    // --- Kitty image management ---

    /// Allocate a new image id for a Kitty image number and mark it as newest.
    pub fn allocate_kitty_image_id_for_number(&mut self, image_number: u32) -> u32 {
        for _ in 0..u32::MAX {
            let id = LOCAL_KITTY_IMAGE_ID_COUNTER.fetch_add(1, Ordering::Relaxed);
            let id = if id == 0 { 0x4000_0000 } else { id };
            if self.kitty_image_id_exists(id) || self.kitty_image_number_mentions(id) {
                continue;
            }
            self.record_kitty_image_number(image_number, id);
            return id;
        }
        let id = LOCAL_KITTY_IMAGE_ID_COUNTER.fetch_add(1, Ordering::Relaxed);
        self.record_kitty_image_number(image_number, id);
        id
    }

    /// Record that image_id is the newest image for image_number.
    pub fn record_kitty_image_number(&mut self, image_number: u32, image_id: u32) {
        let stack = self.kitty_image_numbers.entry(image_number).or_default();
        stack.retain(|existing_id| *existing_id != image_id);
        stack.push(image_id);
    }

    /// Resolve a Kitty image number to the newest known live image id.
    pub fn kitty_image_id_for_number(&self, image_number: u32) -> Option<u32> {
        self.kitty_image_numbers.get(&image_number).and_then(|ids| {
            ids.iter()
                .rev()
                .copied()
                .find(|image_id| self.kitty_image_id_exists(*image_id))
        })
    }

    fn kitty_image_number_mentions(&self, image_id: u32) -> bool {
        self.kitty_image_numbers
            .values()
            .any(|ids| ids.contains(&image_id))
    }

    fn forget_kitty_image_number_id(&mut self, image_id: u32) {
        self.kitty_image_numbers.retain(|_, ids| {
            ids.retain(|existing_id| *existing_id != image_id);
            !ids.is_empty()
        });
    }

    fn kitty_image_id_exists(&self, image_id: u32) -> bool {
        self.shared_images.contains_key(&image_id)
            || self.animations.contains_key(&image_id)
            || self
                .placements
                .iter()
                .chain(self.cleared_kitty_placements.iter())
                .chain(self.deleted_kitty_placements.iter())
                .chain(self.scrollback.iter())
                .chain(self.virtual_placements.values())
                .any(|graphic| graphic.kitty_image_id == Some(image_id))
    }

    /// Store a Kitty image for later reuse
    pub fn store_kitty_image(
        &mut self,
        image_id: u32,
        width: usize,
        height: usize,
        pixels: Vec<u8>,
    ) {
        if !self.image_fits_limits(width, height, pixels.len())
            || !self.evict_until_fits(pixels.len())
        {
            self.dropped_count += 1;
            return;
        }

        self.shared_images
            .insert(image_id, (width, height, Arc::new(pixels)));
    }

    /// Get a stored Kitty image
    pub fn get_kitty_image(&self, image_id: u32) -> Option<(usize, usize, Arc<Vec<u8>>)> {
        self.shared_images.get(&image_id).cloned()
    }

    /// Get Kitty image IDs that have retained pixel data or animation state.
    pub fn kitty_image_data_ids(&self) -> HashSet<u32> {
        self.shared_images
            .keys()
            .chain(self.animations.keys())
            .copied()
            .collect()
    }

    /// Remove a Kitty image
    pub fn remove_kitty_image(&mut self, image_id: u32) {
        self.shared_images.remove(&image_id);
        self.animations.remove(&image_id);
        self.cleared_kitty_placements
            .retain(|graphic| graphic.kitty_image_id != Some(image_id));
        self.forget_kitty_image_number_id(image_id);
    }

    /// Remove Kitty image data for IDs that no active placement, virtual
    /// placement, or scrollback graphic still references.
    pub fn remove_unreferenced_kitty_images(&mut self, image_ids: impl IntoIterator<Item = u32>) {
        for image_id in image_ids {
            if !self.kitty_image_id_is_referenced(image_id) {
                self.remove_kitty_image(image_id);
            }
        }
    }

    fn kitty_image_id_is_referenced(&self, image_id: u32) -> bool {
        self.placements
            .iter()
            .chain(self.scrollback.iter())
            .any(|graphic| graphic.kitty_image_id == Some(image_id))
            || self
                .virtual_placements
                .values()
                .any(|graphic| graphic.kitty_image_id == Some(image_id))
    }

    /// Delete Kitty graphics that intersect a terminal cell.
    pub fn delete_kitty_graphics_intersecting_cell(
        &mut self,
        col: usize,
        row: usize,
        z_index: Option<i32>,
    ) -> HashSet<u32> {
        self.delete_kitty_graphics_intersecting_cell_for_screen(col, row, z_index, None)
    }

    pub fn delete_kitty_graphics_intersecting_cell_for_screen(
        &mut self,
        col: usize,
        row: usize,
        z_index: Option<i32>,
        alternate_screen: Option<bool>,
    ) -> HashSet<u32> {
        self.delete_kitty_graphics_where(alternate_screen, |graphic| {
            if let Some(z) = z_index {
                if graphic.placement.z_index != z {
                    return false;
                }
            }
            graphic_intersects_cell(graphic, col, row)
        })
    }

    /// Delete all currently visible Kitty graphics while preserving other protocols.
    pub fn delete_all_kitty_graphics(&mut self) -> HashSet<u32> {
        self.delete_all_kitty_graphics_for_screen(None)
    }

    pub fn delete_all_kitty_graphics_for_screen(
        &mut self,
        alternate_screen: Option<bool>,
    ) -> HashSet<u32> {
        let image_ids = self.delete_kitty_graphics_where(alternate_screen, |_| true);
        self.deferred_kitty_deletes
            .retain(|delete| !delete.matches_criteria(None, None, alternate_screen));
        image_ids
    }

    /// Delete Kitty graphics at an exact terminal position.
    pub fn delete_kitty_graphics_at_position(&mut self, position: (usize, usize)) -> HashSet<u32> {
        self.delete_kitty_graphics_at_position_for_screen(position, None)
    }

    pub fn delete_kitty_graphics_at_position_for_screen(
        &mut self,
        position: (usize, usize),
        alternate_screen: Option<bool>,
    ) -> HashSet<u32> {
        self.delete_kitty_graphics_where(alternate_screen, |graphic| graphic.position == position)
    }

    /// Delete Kitty graphics intersecting a terminal column.
    pub fn delete_kitty_graphics_in_column(&mut self, col: usize) -> HashSet<u32> {
        self.delete_kitty_graphics_in_column_for_screen(col, None)
    }

    pub fn delete_kitty_graphics_in_column_for_screen(
        &mut self,
        col: usize,
        alternate_screen: Option<bool>,
    ) -> HashSet<u32> {
        self.delete_kitty_graphics_where(alternate_screen, |graphic| {
            graphic_intersects_column(graphic, col)
        })
    }

    /// Delete Kitty graphics intersecting a terminal row.
    pub fn delete_kitty_graphics_in_row(&mut self, row: usize) -> HashSet<u32> {
        self.delete_kitty_graphics_in_row_for_screen(row, None)
    }

    pub fn delete_kitty_graphics_in_row_for_screen(
        &mut self,
        row: usize,
        alternate_screen: Option<bool>,
    ) -> HashSet<u32> {
        self.delete_kitty_graphics_where(alternate_screen, |graphic| {
            graphic_intersects_row(graphic, row)
        })
    }

    /// Delete Kitty graphics with a matching z-index.
    pub fn delete_kitty_graphics_by_z_index(&mut self, z_index: i32) -> HashSet<u32> {
        self.delete_kitty_graphics_by_z_index_for_screen(z_index, None)
    }

    pub fn delete_kitty_graphics_by_z_index_for_screen(
        &mut self,
        z_index: i32,
        alternate_screen: Option<bool>,
    ) -> HashSet<u32> {
        self.delete_kitty_graphics_where(alternate_screen, |graphic| {
            graphic.placement.z_index == z_index
        })
    }

    fn delete_kitty_graphics_where(
        &mut self,
        alternate_screen: Option<bool>,
        mut should_delete: impl FnMut(&TerminalGraphic) -> bool,
    ) -> HashSet<u32> {
        let mut delete_keys = HashSet::new();
        for graphic in self
            .placements
            .iter()
            .chain(self.cleared_kitty_placements.iter())
            .chain(self.deleted_kitty_placements.iter())
            .chain(self.scrollback.iter())
            .chain(self.virtual_placements.values())
        {
            if graphic.protocol == GraphicProtocol::Kitty
                && !screen_filter_excludes(graphic, alternate_screen)
                && should_delete(graphic)
            {
                if let Some(key) = KittyPlacementKey::for_graphic(graphic) {
                    delete_keys.insert(key);
                }
            }
        }
        let delete_keys = self.expand_with_relative_descendants(delete_keys);

        let mut deleted_image_ids = HashSet::new();
        let mut deleted_kitty_placements = Vec::new();
        self.placements.retain(|graphic| {
            let key_matches = KittyPlacementKey::for_graphic(graphic)
                .map(|key| delete_keys.contains(&key))
                .unwrap_or(false);
            let keep = graphic.protocol != GraphicProtocol::Kitty
                || screen_filter_excludes(graphic, alternate_screen)
                || (!should_delete(graphic) && !key_matches);
            if !keep {
                if let Some(image_id) = graphic.kitty_image_id {
                    deleted_image_ids.insert(image_id);
                }
                deleted_kitty_placements.push(graphic.clone());
            }
            keep
        });
        self.cleared_kitty_placements.retain(|graphic| {
            let key_matches = KittyPlacementKey::for_graphic(graphic)
                .map(|key| delete_keys.contains(&key))
                .unwrap_or(false);
            let keep = graphic.protocol != GraphicProtocol::Kitty
                || screen_filter_excludes(graphic, alternate_screen)
                || (!should_delete(graphic) && !key_matches);
            if !keep {
                if let Some(image_id) = graphic.kitty_image_id {
                    deleted_image_ids.insert(image_id);
                }
                deleted_kitty_placements.push(graphic.clone());
            }
            keep
        });
        self.deleted_kitty_placements.retain(|graphic| {
            let key_matches = KittyPlacementKey::for_graphic(graphic)
                .map(|key| delete_keys.contains(&key))
                .unwrap_or(false);
            let keep = graphic.protocol != GraphicProtocol::Kitty
                || screen_filter_excludes(graphic, alternate_screen)
                || (!should_delete(graphic) && !key_matches);
            if !keep {
                if let Some(image_id) = graphic.kitty_image_id {
                    deleted_image_ids.insert(image_id);
                }
                deleted_kitty_placements.push(graphic.clone());
            }
            keep
        });
        self.virtual_placements.retain(|_, graphic| {
            let key_matches = KittyPlacementKey::for_graphic(graphic)
                .map(|key| delete_keys.contains(&key))
                .unwrap_or(false);
            let keep = graphic.protocol != GraphicProtocol::Kitty
                || screen_filter_excludes(graphic, alternate_screen)
                || (!should_delete(graphic) && !key_matches);
            if !keep {
                if let Some(image_id) = graphic.kitty_image_id {
                    deleted_image_ids.insert(image_id);
                }
            }
            keep
        });
        self.scrollback.retain(|graphic| {
            let key_matches = KittyPlacementKey::for_graphic(graphic)
                .map(|key| delete_keys.contains(&key))
                .unwrap_or(false);
            let keep = graphic.protocol != GraphicProtocol::Kitty
                || screen_filter_excludes(graphic, alternate_screen)
                || (!should_delete(graphic) && !key_matches);
            if !keep {
                if let Some(image_id) = graphic.kitty_image_id {
                    deleted_image_ids.insert(image_id);
                }
            }
            keep
        });
        self.remember_deleted_kitty_placements(deleted_kitty_placements);
        self.prune_deferred_kitty_deletes_without_tombstones();
        deleted_image_ids
    }

    /// Delete graphics by Kitty criteria
    pub fn delete_kitty_graphics(
        &mut self,
        image_id: Option<u32>,
        placement_id: Option<u32>,
    ) -> HashSet<u32> {
        self.delete_kitty_graphics_for_screen(image_id, placement_id, None)
    }

    pub fn delete_kitty_graphics_for_screen(
        &mut self,
        image_id: Option<u32>,
        placement_id: Option<u32>,
        alternate_screen: Option<bool>,
    ) -> HashSet<u32> {
        let mut deleted_image_ids =
            self.kitty_image_ids_matching(image_id, placement_id, alternate_screen);
        let retained_count =
            self.retain_deleted_kitty_placements(image_id, placement_id, alternate_screen);
        if retained_count > 0 {
            self.defer_kitty_delete_for_screen(image_id, placement_id, alternate_screen);
        } else {
            self.deferred_kitty_deletes.retain(|delete| {
                !delete.matches_criteria(image_id, placement_id, alternate_screen)
            });
            self.clear_deleted_kitty_graphics_matching(image_id, placement_id, alternate_screen);
        }
        self.cleared_kitty_placements.retain(|graphic| {
            if graphic.protocol != GraphicProtocol::Kitty {
                return true;
            }
            if let Some(alternate_screen) = alternate_screen {
                if graphic.alternate_screen != alternate_screen {
                    return true;
                }
            }
            if let Some(image_id) = image_id {
                if graphic.kitty_image_id != Some(image_id) {
                    return true;
                }
            }
            if let Some(placement_id) = placement_id {
                if graphic.kitty_placement_id != Some(placement_id) {
                    return true;
                }
            }
            false
        });
        deleted_image_ids.extend(self.delete_kitty_graphics_now(
            image_id,
            placement_id,
            alternate_screen,
        ));
        deleted_image_ids
    }

    pub fn delete_kitty_graphics_by_image_id_range_for_screen(
        &mut self,
        start_image_id: u32,
        end_image_id: u32,
        alternate_screen: Option<bool>,
    ) -> HashSet<u32> {
        if start_image_id > end_image_id {
            return HashSet::new();
        }
        let matching_image_ids = self
            .kitty_image_data_ids()
            .into_iter()
            .chain(
                self.placements
                    .iter()
                    .chain(self.cleared_kitty_placements.iter())
                    .chain(self.deleted_kitty_placements.iter())
                    .chain(self.scrollback.iter())
                    .chain(self.virtual_placements.values())
                    .filter(|graphic| {
                        graphic.protocol == GraphicProtocol::Kitty
                            && !screen_filter_excludes(graphic, alternate_screen)
                    })
                    .filter_map(|graphic| graphic.kitty_image_id),
            )
            .filter(|image_id| *image_id >= start_image_id && *image_id <= end_image_id)
            .collect::<HashSet<_>>();

        let mut deleted_image_ids = HashSet::new();
        for image_id in matching_image_ids {
            deleted_image_ids.extend(self.delete_kitty_graphics_for_screen(
                Some(image_id),
                None,
                alternate_screen,
            ));
            deleted_image_ids.insert(image_id);
        }
        deleted_image_ids
    }

    /// Defer a Kitty image/placement delete until no replacement transfer is active.
    pub fn defer_kitty_delete(&mut self, image_id: Option<u32>, placement_id: Option<u32>) {
        self.defer_kitty_delete_for_screen(image_id, placement_id, None);
    }

    pub fn defer_kitty_delete_for_screen(
        &mut self,
        image_id: Option<u32>,
        placement_id: Option<u32>,
        alternate_screen: Option<bool>,
    ) {
        if !self.deferred_kitty_deletes.iter().any(|delete| {
            delete.image_id == image_id
                && delete.placement_id == placement_id
                && delete.alternate_screen == alternate_screen
        }) {
            self.deferred_kitty_deletes.push(KittyDeferredDelete {
                image_id,
                placement_id,
                alternate_screen,
            });
        }
    }

    /// Commit deferred Kitty deletes.
    pub fn commit_deferred_kitty_deletes(&mut self) {
        let pending = std::mem::take(&mut self.deferred_kitty_deletes);
        for delete in pending {
            self.clear_deleted_kitty_graphics_matching(
                delete.image_id,
                delete.placement_id,
                delete.alternate_screen,
            );
            self.delete_kitty_graphics_now(
                delete.image_id,
                delete.placement_id,
                delete.alternate_screen,
            );
        }
    }

    /// Commit deferred Kitty deletes that are not part of the in-flight replacement.
    pub fn commit_deferred_kitty_deletes_preserving_replacement(
        &mut self,
        replacement_image_id: Option<u32>,
        replacement_placement_id: u32,
        replacement_position: (usize, usize),
        replacement_alternate_screen: bool,
    ) {
        let pending = std::mem::take(&mut self.deferred_kitty_deletes);
        for delete in pending {
            if self.delete_waits_for_replacement(
                &delete,
                replacement_image_id,
                replacement_placement_id,
                replacement_position,
                replacement_alternate_screen,
            ) {
                self.deferred_kitty_deletes.push(delete);
            } else {
                self.clear_deleted_kitty_graphics_matching(
                    delete.image_id,
                    delete.placement_id,
                    delete.alternate_screen,
                );
                self.delete_kitty_graphics_now(
                    delete.image_id,
                    delete.placement_id,
                    delete.alternate_screen,
                );
            }
        }
    }

    fn resolve_deferred_kitty_deletes_for_graphic(
        &mut self,
        graphic: &TerminalGraphic,
    ) -> Option<u64> {
        let pending = std::mem::take(&mut self.deferred_kitty_deletes);
        let replacement_placement_id =
            self.replacement_kitty_graphic_id_for_pending_deletes(&pending, graphic);
        for delete in pending {
            if delete.matches(graphic)
                || self.delete_waits_for_replacement_graphic(&delete, graphic)
            {
                continue;
            }
            self.clear_deleted_kitty_graphics_matching(
                delete.image_id,
                delete.placement_id,
                delete.alternate_screen,
            );
            self.delete_kitty_graphics_now(
                delete.image_id,
                delete.placement_id,
                delete.alternate_screen,
            );
        }
        replacement_placement_id
    }

    fn matching_kitty_graphic_id(&self, graphic: &TerminalGraphic) -> Option<u64> {
        if graphic.protocol != GraphicProtocol::Kitty {
            return None;
        }
        let image_id = graphic.kitty_image_id?;
        let placement_id = graphic.kitty_placement_id?;
        self.placements
            .iter()
            .find(|existing| {
                existing.protocol == GraphicProtocol::Kitty
                    && existing.alternate_screen == graphic.alternate_screen
                    && existing.kitty_image_id == Some(image_id)
                    && existing.kitty_placement_id == Some(placement_id)
            })
            .map(|existing| existing.id)
    }

    fn matching_cleared_kitty_graphic_id(&self, graphic: &TerminalGraphic) -> Option<u64> {
        if graphic.protocol != GraphicProtocol::Kitty {
            return None;
        }
        let placement_id = graphic.kitty_placement_id?;
        let mut single_candidate = None;
        let mut candidate_count = 0usize;
        let mut same_image_candidate = None;
        let mut same_image_count = 0usize;

        for cleared in &self.cleared_kitty_placements {
            if cleared.protocol != GraphicProtocol::Kitty
                || cleared.alternate_screen != graphic.alternate_screen
                || cleared.kitty_placement_id != Some(placement_id)
            {
                continue;
            }
            if cleared.position == graphic.position {
                return Some(cleared.id);
            }

            candidate_count += 1;
            single_candidate = Some(cleared.id);

            if cleared.kitty_image_id == graphic.kitty_image_id {
                same_image_count += 1;
                same_image_candidate = Some(cleared.id);
            }
        }

        if same_image_count == 1 {
            same_image_candidate
        } else if candidate_count == 1 {
            single_candidate
        } else {
            None
        }
    }

    fn clear_cleared_kitty_placement_id(&mut self, id: u64) {
        self.cleared_kitty_placements
            .retain(|cleared| cleared.id != id);
    }

    fn clear_deleted_kitty_placement_id(&mut self, id: u64) {
        self.deleted_kitty_placements
            .retain(|deleted| deleted.id != id);
    }

    fn replacement_kitty_graphic_id_for_pending_deletes(
        &self,
        pending: &[KittyDeferredDelete],
        replacement: &TerminalGraphic,
    ) -> Option<u64> {
        let replacement_placement_id = replacement.kitty_placement_id?;
        let mut single_candidate = None;
        let mut candidate_count = 0usize;

        for graphic in &self.deleted_kitty_placements {
            if graphic.protocol != GraphicProtocol::Kitty
                || graphic.alternate_screen != replacement.alternate_screen
                || graphic.kitty_placement_id != Some(replacement_placement_id)
            {
                continue;
            }
            if !pending.iter().any(|delete| delete.matches(graphic)) {
                continue;
            }
            if graphic.position == replacement.position {
                return Some(graphic.id);
            }
            candidate_count += 1;
            single_candidate = Some(graphic.id);
        }

        if candidate_count == 1 {
            single_candidate
        } else {
            None
        }
    }

    fn delete_waits_for_replacement(
        &self,
        delete: &KittyDeferredDelete,
        replacement_image_id: Option<u32>,
        replacement_placement_id: u32,
        replacement_position: (usize, usize),
        replacement_alternate_screen: bool,
    ) -> bool {
        if delete
            .alternate_screen
            .map(|alternate_screen| alternate_screen != replacement_alternate_screen)
            .unwrap_or(false)
        {
            return false;
        }
        if delete.image_id == replacement_image_id
            && delete
                .placement_id
                .map(|placement_id| placement_id == replacement_placement_id)
                .unwrap_or(true)
        {
            return true;
        }

        self.deleted_kitty_placements.iter().any(|graphic| {
            delete.matches(graphic)
                && graphic.kitty_placement_id == Some(replacement_placement_id)
                && graphic.alternate_screen == replacement_alternate_screen
                && graphic.position == replacement_position
        })
    }

    fn delete_waits_for_replacement_graphic(
        &self,
        delete: &KittyDeferredDelete,
        replacement: &TerminalGraphic,
    ) -> bool {
        if delete.matches(replacement) {
            return true;
        }
        let Some(replacement_placement_id) = replacement.kitty_placement_id else {
            return false;
        };
        self.deleted_kitty_placements.iter().any(|deleted| {
            delete.matches(deleted)
                && deleted.kitty_placement_id == Some(replacement_placement_id)
                && deleted.alternate_screen == replacement.alternate_screen
                && deleted.position == replacement.position
        })
    }

    /// Count deferred Kitty deletes for diagnostics and tests.
    pub fn deferred_kitty_delete_count(&self) -> usize {
        self.deferred_kitty_deletes.len()
    }

    fn prune_deferred_kitty_deletes_without_tombstones(&mut self) {
        self.deferred_kitty_deletes.retain(|delete| {
            self.deleted_kitty_placements
                .iter()
                .any(|graphic| delete.matches(graphic))
        });
    }

    fn retain_deleted_kitty_placements(
        &mut self,
        image_id: Option<u32>,
        placement_id: Option<u32>,
        alternate_screen: Option<bool>,
    ) -> usize {
        let mut retained = self
            .placements
            .iter()
            .chain(self.cleared_kitty_placements.iter())
            .chain(self.deleted_kitty_placements.iter())
            .filter(|graphic| {
                if graphic.protocol != GraphicProtocol::Kitty {
                    return false;
                }
                if let Some(alternate_screen) = alternate_screen {
                    if graphic.alternate_screen != alternate_screen {
                        return false;
                    }
                }
                if let Some(image_id) = image_id {
                    if graphic.kitty_image_id != Some(image_id) {
                        return false;
                    }
                }
                if let Some(placement_id) = placement_id {
                    if graphic.kitty_placement_id != Some(placement_id) {
                        return false;
                    }
                }
                true
            })
            .cloned()
            .collect::<Vec<_>>();
        retained.sort_by_key(|graphic| graphic.id);
        retained.dedup_by_key(|graphic| graphic.id);

        let count = retained.len();
        for graphic in retained {
            self.deleted_kitty_placements
                .retain(|deleted| deleted.id != graphic.id);
            self.deleted_kitty_placements.push(graphic);
        }
        while self.deleted_kitty_placements.len() > self.limits.max_graphics_count {
            self.deleted_kitty_placements.remove(0);
        }
        count
    }

    fn clear_deleted_kitty_graphics_matching(
        &mut self,
        image_id: Option<u32>,
        placement_id: Option<u32>,
        alternate_screen: Option<bool>,
    ) {
        self.deleted_kitty_placements.retain(|graphic| {
            if graphic.protocol != GraphicProtocol::Kitty {
                return true;
            }
            if let Some(alternate_screen) = alternate_screen {
                if graphic.alternate_screen != alternate_screen {
                    return true;
                }
            }
            if let Some(image_id) = image_id {
                if graphic.kitty_image_id != Some(image_id) {
                    return true;
                }
            }
            if let Some(placement_id) = placement_id {
                if graphic.kitty_placement_id != Some(placement_id) {
                    return true;
                }
            }
            false
        });
    }

    fn delete_kitty_graphics_now(
        &mut self,
        image_id: Option<u32>,
        placement_id: Option<u32>,
        alternate_screen: Option<bool>,
    ) -> HashSet<u32> {
        let delete_keys = self.expand_with_relative_descendants(
            self.kitty_placement_keys_matching(image_id, placement_id, alternate_screen),
        );
        let mut deleted_image_ids = HashSet::new();
        self.placements.retain(|g| {
            let criteria_matches =
                kitty_delete_criteria_matches(g, image_id, placement_id, alternate_screen);
            let key_matches = KittyPlacementKey::for_graphic(g)
                .map(|key| delete_keys.contains(&key))
                .unwrap_or(false);
            if !criteria_matches && !key_matches {
                return true;
            }
            // Matches criteria, remove it
            if let Some(image_id) = g.kitty_image_id {
                deleted_image_ids.insert(image_id);
            }
            false
        });
        self.cleared_kitty_placements.retain(|g| {
            let criteria_matches =
                kitty_delete_criteria_matches(g, image_id, placement_id, alternate_screen);
            let key_matches = KittyPlacementKey::for_graphic(g)
                .map(|key| delete_keys.contains(&key))
                .unwrap_or(false);
            if !criteria_matches && !key_matches {
                return true;
            }
            if let Some(image_id) = g.kitty_image_id {
                deleted_image_ids.insert(image_id);
            }
            false
        });

        self.virtual_placements.retain(|_, graphic| {
            let criteria_matches =
                kitty_delete_criteria_matches(graphic, image_id, placement_id, alternate_screen);
            let key_matches = KittyPlacementKey::for_graphic(graphic)
                .map(|key| delete_keys.contains(&key))
                .unwrap_or(false);
            let keep = !criteria_matches && !key_matches;
            if !keep {
                if let Some(image_id) = graphic.kitty_image_id {
                    deleted_image_ids.insert(image_id);
                }
            }
            keep
        });
        self.scrollback.retain(|graphic| {
            let criteria_matches =
                kitty_delete_criteria_matches(graphic, image_id, placement_id, alternate_screen);
            let key_matches = KittyPlacementKey::for_graphic(graphic)
                .map(|key| delete_keys.contains(&key))
                .unwrap_or(false);
            let keep = !criteria_matches && !key_matches;
            if !keep {
                if let Some(image_id) = graphic.kitty_image_id {
                    deleted_image_ids.insert(image_id);
                }
            }
            keep
        });
        deleted_image_ids
    }

    fn kitty_image_ids_matching(
        &self,
        image_id: Option<u32>,
        placement_id: Option<u32>,
        alternate_screen: Option<bool>,
    ) -> HashSet<u32> {
        let mut image_ids = HashSet::new();
        for graphic in self
            .placements
            .iter()
            .chain(self.cleared_kitty_placements.iter())
            .chain(self.deleted_kitty_placements.iter())
            .chain(self.scrollback.iter())
            .chain(self.virtual_placements.values())
        {
            if graphic.protocol != GraphicProtocol::Kitty
                || screen_filter_excludes(graphic, alternate_screen)
            {
                continue;
            }
            if let Some(iid) = image_id {
                if graphic.kitty_image_id != Some(iid) {
                    continue;
                }
            }
            if let Some(pid) = placement_id {
                if graphic.kitty_placement_id != Some(pid) {
                    continue;
                }
            }
            if let Some(iid) = graphic.kitty_image_id {
                image_ids.insert(iid);
            }
        }
        image_ids
    }

    fn kitty_placement_keys_matching(
        &self,
        image_id: Option<u32>,
        placement_id: Option<u32>,
        alternate_screen: Option<bool>,
    ) -> HashSet<KittyPlacementKey> {
        let mut keys = HashSet::new();
        for graphic in self
            .placements
            .iter()
            .chain(self.cleared_kitty_placements.iter())
            .chain(self.deleted_kitty_placements.iter())
            .chain(self.scrollback.iter())
            .chain(self.virtual_placements.values())
        {
            if !kitty_delete_criteria_matches(graphic, image_id, placement_id, alternate_screen) {
                continue;
            }
            if let Some(key) = KittyPlacementKey::for_graphic(graphic) {
                keys.insert(key);
            }
        }
        keys
    }

    // --- Virtual placements ---

    /// Add or update a virtual placement
    pub fn add_virtual_placement(&mut self, mut graphic: TerminalGraphic) {
        graphic.is_virtual = true;
        let placement_key = KittyPlacementKey::for_graphic(&graphic);
        if let Some(placement_id) = self.resolve_deferred_kitty_deletes_for_graphic(&graphic) {
            graphic.id = placement_id;
        }
        let image_id = graphic.kitty_image_id.unwrap_or(0);
        let placement_id = graphic.kitty_placement_id.unwrap_or(0);
        self.virtual_placements
            .insert((image_id, placement_id), graphic);
        if let Some(placement_key) = placement_key {
            self.update_relative_kitty_descendants(placement_key);
        }
    }

    /// Get a virtual placement
    pub fn get_virtual_placement(
        &self,
        image_id: u32,
        placement_id: u32,
    ) -> Option<&TerminalGraphic> {
        self.virtual_placements.get(&(image_id, placement_id))
    }

    /// Remove a virtual placement
    pub fn remove_virtual_placement(
        &mut self,
        image_id: u32,
        placement_id: u32,
    ) -> Option<TerminalGraphic> {
        self.virtual_placements.remove(&(image_id, placement_id))
    }

    /// Get all virtual placements
    pub fn all_virtual_placements(&self) -> &HashMap<(u32, u32), TerminalGraphic> {
        &self.virtual_placements
    }

    /// Get a virtual placement for rendering a Unicode placeholder
    ///
    /// This looks up the virtual placement using the image_id and placement_id
    /// from the placeholder info, and returns it for rendering.
    pub fn get_placeholder_graphic(
        &self,
        placeholder_info: &PlaceholderInfo,
    ) -> Option<&TerminalGraphic> {
        let image_id = placeholder_info.full_image_id();
        let placement_id = placeholder_info.placement_id;

        // Try exact match first
        if let Some(graphic) = self.virtual_placements.get(&(image_id, placement_id)) {
            return Some(graphic);
        }

        // If placement_id is 0, try to find any virtual placement for this image
        if placement_id == 0 {
            for ((img_id, _pid), graphic) in &self.virtual_placements {
                if *img_id == image_id {
                    return Some(graphic);
                }
            }
        }

        None
    }

    // --- Animation management ---

    /// Create or get animation for an image
    pub fn get_or_create_animation(
        &mut self,
        image_id: u32,
        default_delay_ms: u32,
    ) -> &mut Animation {
        self.animations
            .entry(image_id)
            .or_insert_with(|| Animation::new(image_id, default_delay_ms))
    }

    /// Get animation for an image
    pub fn get_animation(&self, image_id: u32) -> Option<&Animation> {
        self.animations.get(&image_id)
    }

    /// Get mutable animation for an image
    pub fn get_animation_mut(&mut self, image_id: u32) -> Option<&mut Animation> {
        self.animations.get_mut(&image_id)
    }

    /// Add a frame to an animation
    pub fn add_animation_frame(&mut self, image_id: u32, frame: AnimationFrame) {
        let frame_num = frame.frame_number;
        if let Some(anim) = self.animations.get_mut(&image_id) {
            anim.frames.remove(&frame_num);
        }
        if !self.image_fits_limits(frame.width, frame.height, frame.pixels.len())
            || !self.evict_until_fits(frame.pixels.len())
        {
            self.dropped_count += 1;
            return;
        }
        let default_delay = if frame.delay_ms == 0 {
            100
        } else {
            frame.delay_ms
        };
        let current_frame_changed = {
            let anim = self.get_or_create_animation(image_id, default_delay);
            let current_frame_changed = anim.current_frame == frame_num;
            anim.add_frame(frame);
            current_frame_changed
        };
        debug_info!(
            "GRAPHICS",
            "Added animation frame {} to image_id={} (total frames: {})",
            frame_num,
            image_id,
            self.get_animation(image_id)
                .map(Animation::frame_count)
                .unwrap_or(0)
        );
        if current_frame_changed {
            self.sync_animation_frame_to_placements(image_id);
        }
    }

    /// Apply animation control to an image
    pub fn control_animation(&mut self, image_id: u32, control: AnimationControl) {
        if let Some(anim) = self.get_animation_mut(image_id) {
            anim.apply_control(control);
        }
        self.sync_animation_frame_to_placements(image_id);
    }

    /// Set loop count for an animation
    pub fn set_animation_loops(&mut self, image_id: u32, loop_count: u32) {
        if let Some(anim) = self.get_animation_mut(image_id) {
            anim.set_loops(loop_count);
        }
    }

    /// Set the current frame for an animation and immediately refresh placements.
    pub fn set_animation_current_frame(&mut self, image_id: u32, frame_number: u32) -> bool {
        let Some(anim) = self.get_animation_mut(image_id) else {
            return false;
        };
        if !anim.frames.contains_key(&frame_number) {
            return false;
        }
        anim.current_frame = frame_number;
        if anim.state == AnimationState::Playing {
            anim.frame_start_time = Some(std::time::Instant::now());
        }
        self.sync_animation_frame_to_placements(image_id)
    }

    /// Set the signed display gap for an existing animation frame.
    pub fn set_animation_frame_gap(
        &mut self,
        image_id: u32,
        frame_number: u32,
        gap_ms: i32,
    ) -> bool {
        let Some(anim) = self.get_animation_mut(image_id) else {
            return false;
        };
        let Some(frame) = anim.frames.get_mut(&frame_number) else {
            return false;
        };
        if gap_ms < 0 {
            frame.delay_ms = 0;
            frame.gapless = true;
        } else if gap_ms > 0 {
            frame.delay_ms = gap_ms as u32;
            frame.gapless = false;
        }
        true
    }

    /// Delete one Kitty animation frame.
    ///
    /// Returns true when uppercase frame deletion should remove the whole image
    /// because the requested frame is the final remaining animation frame.
    pub fn delete_animation_frame(
        &mut self,
        image_id: u32,
        frame_number: Option<u32>,
        delete_image_data: bool,
    ) -> bool {
        let mut sync_current_frame = false;
        let mut remove_entire_image = false;
        {
            let Some(animation) = self.get_animation_mut(image_id) else {
                return false;
            };
            let frame_count = animation.frames.len();
            if frame_count == 0 {
                return false;
            }
            if frame_count == 1 {
                if delete_image_data {
                    remove_entire_image = true;
                }
            } else {
                let requested_frame = frame_number.unwrap_or(1).max(1);
                let target_frame = if animation.frames.contains_key(&requested_frame) {
                    Some(requested_frame)
                } else {
                    animation
                        .frames
                        .keys()
                        .copied()
                        .max()
                        .filter(|max_frame| requested_frame > *max_frame)
                };
                let Some(target_frame) = target_frame else {
                    return false;
                };
                animation.frames.remove(&target_frame);
                if !animation.frames.contains_key(&animation.current_frame) {
                    animation.current_frame = animation
                        .frames
                        .keys()
                        .copied()
                        .filter(|candidate| *candidate >= target_frame)
                        .min()
                        .or_else(|| animation.frames.keys().copied().max())
                        .unwrap_or(1);
                    if animation.state == AnimationState::Playing {
                        animation.frame_start_time = Some(std::time::Instant::now());
                    }
                    sync_current_frame = true;
                }
            }
        }

        if remove_entire_image {
            self.animations.remove(&image_id);
            return true;
        }
        if sync_current_frame {
            self.sync_animation_frame_to_placements(image_id);
        }
        false
    }

    /// Compose a source frame rectangle into a destination animation frame.
    #[allow(clippy::too_many_arguments)]
    pub fn compose_animation_frame(
        &mut self,
        image_id: u32,
        source_frame_number: u32,
        destination_frame_number: u32,
        source_x: u32,
        source_y: u32,
        source_width: Option<u32>,
        source_height: Option<u32>,
        destination_x: u32,
        destination_y: u32,
        composition: CompositionMode,
    ) -> bool {
        let destination_is_current = {
            let Some(animation) = self.get_animation_mut(image_id) else {
                return false;
            };
            let Some(source_frame) = animation.frames.get(&source_frame_number).cloned() else {
                return false;
            };
            let Some(destination_frame) = animation.frames.get_mut(&destination_frame_number)
            else {
                return false;
            };
            if !compose_frame_pixels(
                &source_frame,
                destination_frame,
                source_x as usize,
                source_y as usize,
                source_width.map(|value| value as usize),
                source_height.map(|value| value as usize),
                destination_x as usize,
                destination_y as usize,
                composition,
            ) {
                return false;
            }
            animation.current_frame == destination_frame_number
        };

        if destination_is_current {
            self.sync_animation_frame_to_placements(image_id);
        }
        true
    }

    /// Build a new animation frame by drawing frame data over an existing base frame.
    pub fn composed_animation_frame_from_base(
        &self,
        image_id: u32,
        base_frame_number: u32,
        overlay_frame: &AnimationFrame,
    ) -> Option<AnimationFrame> {
        let base_frame = self
            .animations
            .get(&image_id)?
            .frames
            .get(&base_frame_number)?
            .clone();
        let mut composed = AnimationFrame::new(
            overlay_frame.frame_number,
            base_frame.pixels.as_ref().clone(),
            base_frame.width,
            base_frame.height,
        );
        composed.delay_ms = overlay_frame.delay_ms;
        composed.gapless = overlay_frame.gapless;
        composed.composition = overlay_frame.composition;
        if !compose_frame_pixels(
            overlay_frame,
            &mut composed,
            0,
            0,
            None,
            None,
            overlay_frame.x_offset as usize,
            overlay_frame.y_offset as usize,
            overlay_frame.composition,
        ) {
            return None;
        }
        Some(composed)
    }

    /// Update all animations and return list of image IDs that changed frames
    ///
    /// This method advances animation frames based on timing and updates the pixel data
    /// in all active and virtual placements associated with animated images.
    pub fn update_animations(&mut self) -> Vec<u32> {
        let mut changed = Vec::new();
        let mut updates = Vec::new();
        for (image_id, anim) in &mut self.animations {
            if anim.update() {
                changed.push(*image_id);

                if let Some(current_frame) = anim.current_frame() {
                    updates.push((
                        *image_id,
                        current_frame.pixels.clone(),
                        current_frame.width,
                        current_frame.height,
                    ));
                }
            }
        }
        for (image_id, frame_pixels, width, height) in updates {
            self.sync_animation_payload_to_placements(image_id, frame_pixels, width, height);
        }
        changed
    }

    fn sync_animation_frame_to_placements(&mut self, image_id: u32) -> bool {
        let Some((frame_pixels, width, height)) = self.current_animation_frame_payload(image_id)
        else {
            return false;
        };
        self.sync_animation_payload_to_placements(image_id, frame_pixels, width, height)
    }

    fn sync_animation_payload_to_placements(
        &mut self,
        image_id: u32,
        frame_pixels: Arc<Vec<u8>>,
        width: usize,
        height: usize,
    ) -> bool {
        let asset_version = graphic_content_version(width, height, frame_pixels.as_ref());
        let mut changed = false;
        if let Some(shared_image) = self.shared_images.get_mut(&image_id) {
            *shared_image = (width, height, frame_pixels.clone());
            changed = true;
        }
        for placement in &mut self.placements {
            if placement.kitty_image_id == Some(image_id)
                || placement.animation_id == Some(image_id)
            {
                placement.pixels = frame_pixels.clone();
                placement.width = width;
                placement.height = height;
                placement.asset_version = asset_version;
                changed = true;
            }
        }
        for placement in &mut self.scrollback {
            if placement.kitty_image_id == Some(image_id)
                || placement.animation_id == Some(image_id)
            {
                placement.pixels = frame_pixels.clone();
                placement.width = width;
                placement.height = height;
                placement.asset_version = asset_version;
                changed = true;
            }
        }
        for placement in self.virtual_placements.values_mut() {
            if placement.kitty_image_id == Some(image_id)
                || placement.animation_id == Some(image_id)
            {
                placement.pixels = frame_pixels.clone();
                placement.width = width;
                placement.height = height;
                placement.asset_version = asset_version;
                changed = true;
            }
        }
        changed
    }

    fn current_animation_frame_payload(
        &self,
        image_id: u32,
    ) -> Option<(Arc<Vec<u8>>, usize, usize)> {
        let frame = self.animations.get(&image_id)?.current_frame()?;
        Some((frame.pixels.clone(), frame.width, frame.height))
    }

    /// Remove animation for an image
    pub fn remove_animation(&mut self, image_id: u32) {
        self.animations.remove(&image_id);
    }

    /// Get all animations
    pub fn all_animations(&self) -> &HashMap<u32, Animation> {
        &self.animations
    }

    fn image_fits_limits(&self, width: usize, height: usize, bytes: usize) -> bool {
        image_values_fit_limits(self.limits, width, height, bytes)
    }

    fn current_memory_bytes(&self) -> usize {
        let mut seen = HashSet::new();
        let mut total = 0usize;
        for graphic in &self.placements {
            add_unique_pixel_bytes(&mut seen, &mut total, &graphic.pixels);
        }
        for graphic in &self.cleared_kitty_placements {
            add_unique_pixel_bytes(&mut seen, &mut total, &graphic.pixels);
        }
        for graphic in &self.deleted_kitty_placements {
            add_unique_pixel_bytes(&mut seen, &mut total, &graphic.pixels);
        }
        for graphic in &self.scrollback {
            add_unique_pixel_bytes(&mut seen, &mut total, &graphic.pixels);
        }
        for graphic in self.virtual_placements.values() {
            add_unique_pixel_bytes(&mut seen, &mut total, &graphic.pixels);
        }
        for (_, _, pixels) in self.shared_images.values() {
            add_unique_pixel_bytes(&mut seen, &mut total, pixels);
        }
        for animation in self.animations.values() {
            for frame in animation.frames.values() {
                add_unique_pixel_bytes(&mut seen, &mut total, &frame.pixels);
            }
        }
        total
    }

    fn evict_until_fits(&mut self, incoming_bytes: usize) -> bool {
        if incoming_bytes > self.limits.max_total_memory {
            return false;
        }
        while self.current_memory_bytes().saturating_add(incoming_bytes)
            > self.limits.max_total_memory
        {
            if !self.evict_one_memory_holder() {
                return false;
            }
        }
        true
    }

    fn enforce_limits(&mut self) {
        let limits = self.limits;
        self.placements.retain(|graphic| {
            image_values_fit_limits(limits, graphic.width, graphic.height, graphic.pixels.len())
        });
        self.cleared_kitty_placements.retain(|graphic| {
            image_values_fit_limits(limits, graphic.width, graphic.height, graphic.pixels.len())
        });
        self.deleted_kitty_placements.retain(|graphic| {
            image_values_fit_limits(limits, graphic.width, graphic.height, graphic.pixels.len())
        });
        self.scrollback.retain(|graphic| {
            image_values_fit_limits(limits, graphic.width, graphic.height, graphic.pixels.len())
        });
        self.virtual_placements.retain(|_, graphic| {
            image_values_fit_limits(limits, graphic.width, graphic.height, graphic.pixels.len())
        });
        self.shared_images.retain(|_, (width, height, pixels)| {
            image_values_fit_limits(limits, *width, *height, pixels.len())
        });
        self.animations.retain(|_, animation| {
            animation.frames.retain(|_, frame| {
                image_values_fit_limits(limits, frame.width, frame.height, frame.pixels.len())
            });
            !animation.frames.is_empty()
        });
        while self.current_memory_bytes() > self.limits.max_total_memory {
            if !self.evict_one_memory_holder() {
                break;
            }
        }
    }

    fn evict_one_memory_holder(&mut self) -> bool {
        if !self.cleared_kitty_placements.is_empty() {
            self.cleared_kitty_placements.remove(0);
            self.dropped_count += 1;
            return true;
        }
        if !self.deleted_kitty_placements.is_empty() {
            self.deleted_kitty_placements.remove(0);
            self.dropped_count += 1;
            return true;
        }
        if !self.scrollback.is_empty() {
            self.scrollback.remove(0);
            self.dropped_count += 1;
            return true;
        }
        if let Some(image_id) = self.shared_images.keys().next().copied() {
            self.shared_images.remove(&image_id);
            self.dropped_count += 1;
            return true;
        }
        if let Some(key) = self.virtual_placements.keys().next().copied() {
            self.virtual_placements.remove(&key);
            self.dropped_count += 1;
            return true;
        }
        if let Some(image_id) = self.animations.keys().next().copied() {
            self.animations.remove(&image_id);
            self.dropped_count += 1;
            return true;
        }
        if !self.placements.is_empty() {
            self.placements.remove(0);
            self.dropped_count += 1;
            return true;
        }
        false
    }

    // --- Scrolling ---

    /// Notify that lines have been added to text scrollback
    /// This should be called when text scrolls off the screen
    pub fn notify_scrollback_advance(&mut self, lines: usize) {
        self.scrollback_position += lines;
    }

    /// Get current scrollback position
    pub fn scrollback_position(&self) -> usize {
        self.scrollback_position
    }

    /// Adjust graphics positions when scrolling up
    pub fn adjust_for_scroll_up(&mut self, lines: usize, top: usize, bottom: usize) {
        self.adjust_for_scroll_up_with_scrollback(lines, top, bottom, 0);
    }

    /// Adjust graphics positions when scrolling up for a specific screen buffer.
    pub fn adjust_for_scroll_up_for_screen(
        &mut self,
        lines: usize,
        top: usize,
        bottom: usize,
        grid_scrollback_len: usize,
        alternate_screen: bool,
    ) {
        self.adjust_for_scroll_up_with_scope(
            lines,
            top,
            bottom,
            grid_scrollback_len,
            None,
            Some(alternate_screen),
        );
    }

    /// Adjust graphics positions when scrolling up and synchronize graphics
    /// scrollback with the text scrollback capacity after the grid has scrolled.
    pub fn adjust_for_scroll_up_for_screen_with_scrollback_len(
        &mut self,
        lines: usize,
        top: usize,
        bottom: usize,
        retained_old_scrollback_len: usize,
        current_scrollback_len: usize,
        alternate_screen: bool,
    ) {
        self.adjust_for_scroll_up_with_scope(
            lines,
            top,
            bottom,
            retained_old_scrollback_len,
            Some(current_scrollback_len),
            Some(alternate_screen),
        );
    }

    /// Adjust graphics positions when scrolling up, with scrollback tracking
    ///
    /// # Arguments
    /// * `lines` - Number of lines to scroll
    /// * `top` - Top of scroll region
    /// * `bottom` - Bottom of scroll region
    /// * `grid_scrollback_len` - Current length of text scrollback buffer
    pub fn adjust_for_scroll_up_with_scrollback(
        &mut self,
        lines: usize,
        top: usize,
        bottom: usize,
        grid_scrollback_len: usize,
    ) {
        self.adjust_for_scroll_up_with_scope(lines, top, bottom, grid_scrollback_len, None, None);
    }

    fn adjust_for_scroll_up_with_scope(
        &mut self,
        lines: usize,
        top: usize,
        bottom: usize,
        grid_scrollback_len: usize,
        current_grid_scrollback_len: Option<usize>,
        alternate_screen: Option<bool>,
    ) {
        let current_grid_scrollback_len = current_grid_scrollback_len
            .unwrap_or_else(|| grid_scrollback_len.saturating_add(lines));
        let retained_old_scrollback_len = grid_scrollback_len.min(current_grid_scrollback_len);
        if alternate_screen == Some(false) && top == 0 {
            self.sync_text_scrollback_rows(
                retained_old_scrollback_len,
                current_grid_scrollback_len,
            );
        }
        let retained_new_scrollback_rows =
            current_grid_scrollback_len.saturating_sub(retained_old_scrollback_len);
        let evicted_new_scrollback_rows = lines.saturating_sub(retained_new_scrollback_rows);
        let mut to_scrollback = Vec::new();
        let mut deleted_kitty_placements = Vec::new();

        self.placements.retain_mut(|g| {
            if alternate_screen
                .map(|screen| g.alternate_screen != screen)
                .unwrap_or(false)
            {
                return true;
            }
            let graphic_row = g.position.1;
            let (_, graphic_height_in_rows) = graphic_cell_span(g);
            let graphic_bottom = graphic_row.saturating_add(graphic_height_in_rows);

            if graphic_bottom <= top || graphic_row > bottom {
                return true;
            }

            if graphic_row < top {
                if g.protocol == GraphicProtocol::Kitty {
                    deleted_kitty_placements.push(g.clone());
                }
                return false;
            }

            // Check if graphic is within the scroll region
            if graphic_row <= bottom {
                let rows_above_region_top = lines.saturating_sub(graphic_row.saturating_sub(top));
                let new_position = graphic_row.saturating_sub(lines).max(top);
                let previous_scroll_offset = g.scroll_offset_rows;
                g.scroll_offset_rows = g.scroll_offset_rows.saturating_add(rows_above_region_top);
                g.position.1 = new_position;

                // Check if completely scrolled off
                if g.scroll_offset_rows >= graphic_height_in_rows {
                    if g.alternate_screen || top > 0 {
                        if g.protocol == GraphicProtocol::Kitty {
                            deleted_kitty_placements.push(g.clone());
                        }
                        return false;
                    }
                    // Move to scrollback - set scrollback_row to match text scrollback position
                    // The graphic was originally at graphic_row, which is now at scrollback position
                    let mut scrollback_graphic = g.clone();
                    let pushed_row = graphic_row
                        .saturating_sub(top)
                        .saturating_sub(previous_scroll_offset);
                    if pushed_row < evicted_new_scrollback_rows {
                        return false;
                    }
                    let scrollback_row = retained_old_scrollback_len
                        .saturating_add(pushed_row - evicted_new_scrollback_rows);
                    if scrollback_row >= current_grid_scrollback_len {
                        return false;
                    }
                    scrollback_graphic.scrollback_row = Some(scrollback_row);

                    to_scrollback.push(scrollback_graphic);
                    return false;
                }
            }
            true
        });

        self.remember_deleted_kitty_placements(deleted_kitty_placements);

        // Add to scrollback (with limit)
        for g in to_scrollback {
            if !self.image_fits_limits(g.width, g.height, g.pixels.len())
                || !self.evict_until_fits(g.pixels.len())
            {
                self.dropped_count += 1;
                continue;
            }
            if self.limits.max_scrollback_graphics == 0 {
                self.dropped_count += 1;
                continue;
            }
            if self.scrollback.len() >= self.limits.max_scrollback_graphics {
                self.scrollback.remove(0);
                self.dropped_count += 1;
            }
            self.scrollback.push(g);
        }
    }

    fn sync_text_scrollback_rows(
        &mut self,
        retained_old_scrollback_len: usize,
        current_scrollback_len: usize,
    ) {
        let evicted_old_rows = self
            .tracked_text_scrollback_len
            .saturating_sub(retained_old_scrollback_len);
        self.tracked_text_scrollback_len = current_scrollback_len;
        self.scrollback.retain_mut(|graphic| {
            let Some(row) = graphic.scrollback_row else {
                return false;
            };
            if row < evicted_old_rows {
                return false;
            }
            let next_row = row - evicted_old_rows;
            if next_row >= current_scrollback_len {
                return false;
            }
            graphic.scrollback_row = Some(next_row);
            true
        });
    }

    /// Synchronize graphics scrollback after the text grid reflows scrollback
    /// during resize. Graphics whose row no longer exists in text scrollback
    /// are dropped so they cannot be rendered against unrelated text rows.
    pub fn sync_text_scrollback_after_reflow(&mut self, current_scrollback_len: usize) {
        self.tracked_text_scrollback_len = current_scrollback_len;
        self.scrollback.retain(|graphic| {
            graphic
                .scrollback_row
                .map(|row| row < current_scrollback_len)
                .unwrap_or(false)
        });
    }

    /// Adjust graphics positions when scrolling down
    pub fn adjust_for_scroll_down(&mut self, lines: usize, top: usize, bottom: usize) {
        self.adjust_for_scroll_down_with_scope(lines, top, bottom, None);
    }

    /// Adjust graphics for CSI IL: insert blank lines and push existing rows down.
    pub fn adjust_for_insert_lines_for_screen(
        &mut self,
        lines: usize,
        top: usize,
        bottom: usize,
        alternate_screen: bool,
    ) {
        let Some(region_len) = bottom.checked_sub(top).map(|delta| delta + 1) else {
            return;
        };
        let lines = lines.min(region_len);
        if lines == 0 {
            return;
        }
        let last_shifted_row = bottom.saturating_sub(lines);
        let bottom_exclusive = bottom.saturating_add(1);
        let mut deleted_kitty_placements = Vec::new();
        self.placements.retain_mut(|graphic| {
            if graphic.alternate_screen != alternate_screen {
                return true;
            }
            let row = graphic.position.1;
            let (_, height_cells) = graphic_cell_span(graphic);
            let graphic_bottom = row.saturating_add(height_cells);
            if row < top && graphic_bottom > top {
                if graphic.protocol == GraphicProtocol::Kitty {
                    deleted_kitty_placements.push(graphic.clone());
                }
                return false;
            }
            if row < top || row > bottom {
                return true;
            }
            if row <= last_shifted_row {
                let shifted_row = row.saturating_add(lines);
                if shifted_row.saturating_add(height_cells) <= bottom_exclusive {
                    graphic.position.1 = shifted_row;
                    return true;
                }
            }
            if graphic.protocol == GraphicProtocol::Kitty {
                deleted_kitty_placements.push(graphic.clone());
            }
            false
        });
        self.remember_deleted_kitty_placements(deleted_kitty_placements);
    }

    /// Adjust graphics for CSI DL: delete rows and pull following rows up.
    pub fn adjust_for_delete_lines_for_screen(
        &mut self,
        lines: usize,
        top: usize,
        bottom: usize,
        alternate_screen: bool,
    ) {
        let Some(region_len) = bottom.checked_sub(top).map(|delta| delta + 1) else {
            return;
        };
        let lines = lines.min(region_len);
        if lines == 0 {
            return;
        }
        let first_shifted_row = top.saturating_add(lines);
        let mut deleted_kitty_placements = Vec::new();
        self.placements.retain_mut(|graphic| {
            if graphic.alternate_screen != alternate_screen {
                return true;
            }
            let row = graphic.position.1;
            let (_, height_cells) = graphic_cell_span(graphic);
            let graphic_bottom = row.saturating_add(height_cells);
            if graphic_bottom <= top || row > bottom {
                return true;
            }
            if row >= first_shifted_row {
                graphic.position.1 = row.saturating_sub(lines);
                return true;
            }
            if graphic.protocol == GraphicProtocol::Kitty {
                deleted_kitty_placements.push(graphic.clone());
            }
            false
        });
        self.remember_deleted_kitty_placements(deleted_kitty_placements);
    }

    /// Adjust graphics for CSI ICH: insert blank cells and push row content right.
    pub fn adjust_for_insert_characters_for_screen(
        &mut self,
        chars: usize,
        col: usize,
        row: usize,
        cols: usize,
        alternate_screen: bool,
    ) {
        if col >= cols {
            return;
        }
        let chars = chars.min(cols - col);
        if chars == 0 {
            return;
        }
        let right_shift_source_end = cols.saturating_sub(chars);
        let mut deleted_kitty_placements = Vec::new();
        self.placements.retain_mut(|graphic| {
            if graphic.alternate_screen != alternate_screen || !graphic_intersects_row(graphic, row)
            {
                return true;
            }
            let (width_cells, _) = graphic_cell_span(graphic);
            let start_col = graphic.position.0;
            let end_col = start_col.saturating_add(width_cells);

            if start_col < col && end_col > col {
                if graphic.protocol == GraphicProtocol::Kitty {
                    deleted_kitty_placements.push(graphic.clone());
                }
                return false;
            }

            if start_col >= col {
                let shifted_col = start_col.saturating_add(chars);
                if start_col >= right_shift_source_end
                    || shifted_col.saturating_add(width_cells) > cols
                {
                    if graphic.protocol == GraphicProtocol::Kitty {
                        deleted_kitty_placements.push(graphic.clone());
                    }
                    return false;
                }
                graphic.position.0 = shifted_col;
            }
            true
        });
        self.remember_deleted_kitty_placements(deleted_kitty_placements);
    }

    /// Adjust graphics for CSI DCH: delete cells and pull row content left.
    pub fn adjust_for_delete_characters_for_screen(
        &mut self,
        chars: usize,
        col: usize,
        row: usize,
        cols: usize,
        alternate_screen: bool,
    ) {
        if col >= cols {
            return;
        }
        let chars = chars.min(cols - col);
        if chars == 0 {
            return;
        }
        let delete_end_col = col.saturating_add(chars);
        let mut deleted_kitty_placements = Vec::new();
        self.placements.retain_mut(|graphic| {
            if graphic.alternate_screen != alternate_screen || !graphic_intersects_row(graphic, row)
            {
                return true;
            }
            let (width_cells, _) = graphic_cell_span(graphic);
            let start_col = graphic.position.0;
            let end_col = start_col.saturating_add(width_cells);

            if end_col <= col {
                return true;
            }
            if start_col < delete_end_col && end_col > col {
                if graphic.protocol == GraphicProtocol::Kitty {
                    deleted_kitty_placements.push(graphic.clone());
                }
                return false;
            }
            if start_col >= delete_end_col {
                graphic.position.0 = start_col.saturating_sub(chars);
            }
            true
        });
        self.remember_deleted_kitty_placements(deleted_kitty_placements);
    }

    /// Adjust graphics positions when scrolling down for a specific screen buffer.
    pub fn adjust_for_scroll_down_for_screen(
        &mut self,
        lines: usize,
        top: usize,
        bottom: usize,
        alternate_screen: bool,
    ) {
        self.adjust_for_scroll_down_with_scope(lines, top, bottom, Some(alternate_screen));
    }

    fn adjust_for_scroll_down_with_scope(
        &mut self,
        lines: usize,
        top: usize,
        bottom: usize,
        alternate_screen: Option<bool>,
    ) {
        let bottom_exclusive = bottom.saturating_add(1);
        let mut deleted_kitty_placements = Vec::new();
        self.placements.retain_mut(|g| {
            if alternate_screen
                .map(|screen| g.alternate_screen != screen)
                .unwrap_or(false)
            {
                return true;
            }
            let graphic_row = g.position.1;
            let (_, graphic_height_in_rows) = graphic_cell_span(g);
            let graphic_bottom = graphic_row + graphic_height_in_rows;

            if graphic_row < top && graphic_bottom > top {
                if g.protocol == GraphicProtocol::Kitty {
                    deleted_kitty_placements.push(g.clone());
                }
                return false;
            }

            // Graphic starts within scroll region
            if graphic_bottom > top && graphic_row >= top && graphic_row <= bottom {
                let new_row = graphic_row.saturating_add(lines);
                if new_row.saturating_add(graphic_height_in_rows) <= bottom_exclusive {
                    g.position.1 = new_row;
                } else {
                    if g.protocol == GraphicProtocol::Kitty {
                        deleted_kitty_placements.push(g.clone());
                    }
                    return false;
                }
            }
            true
        });
        self.remember_deleted_kitty_placements(deleted_kitty_placements);
    }

    // --- Scrollback ---

    /// Get graphics in scrollback for a range of scrollback rows
    pub fn graphics_in_scrollback(
        &self,
        start_row: usize,
        end_row: usize,
    ) -> Vec<&TerminalGraphic> {
        self.scrollback
            .iter()
            .filter(|g| {
                if let Some(sb_row) = g.scrollback_row {
                    sb_row >= start_row && sb_row < end_row
                } else {
                    false
                }
            })
            .collect()
    }

    /// Get all scrollback graphics
    pub fn all_scrollback_graphics(&self) -> &[TerminalGraphic] {
        &self.scrollback
    }

    /// Clear scrollback graphics
    pub fn clear_scrollback_graphics(&mut self) {
        self.scrollback.clear();
        self.tracked_text_scrollback_len = 0;
    }

    /// Get scrollback graphics count
    pub fn scrollback_count(&self) -> usize {
        self.scrollback.len()
    }
}

fn image_values_fit_limits(
    limits: GraphicsLimits,
    width: usize,
    height: usize,
    bytes: usize,
) -> bool {
    if bytes == 0 {
        return true;
    }
    width <= limits.max_width as usize
        && height <= limits.max_height as usize
        && width.saturating_mul(height) <= limits.max_pixels
        && bytes <= limits.max_image_bytes
        && bytes <= limits.max_total_memory
}

fn add_unique_pixel_bytes(seen: &mut HashSet<usize>, total: &mut usize, pixels: &Arc<Vec<u8>>) {
    let key = Arc::as_ptr(pixels) as usize;
    if seen.insert(key) {
        *total = total.saturating_add(pixels.len());
    }
}

fn refresh_graphic_cell_dimensions(
    graphic: &mut TerminalGraphic,
    cell_width: u32,
    cell_height: u32,
    cols: usize,
    rows: usize,
) {
    graphic.set_cell_dimensions(cell_width, cell_height);
    let (span_cols, span_rows) = graphic.resolved_cell_span(Some(cols), Some(rows));
    graphic.set_display_cell_span(span_cols, span_rows);
}

/// Graphics error types
#[derive(Debug, Clone)]
pub enum GraphicsError {
    InvalidDimensions(u32, u32),
    ImageTooLarge(usize, usize),
    UnsupportedFormat(String),
    DecodeError(String),
    Base64Error(String),
    ImageError(String),
    KittyError(String),
    ITermError(String),
}

impl std::fmt::Display for GraphicsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GraphicsError::InvalidDimensions(w, h) => {
                write!(f, "Invalid image dimensions: {}x{}", w, h)
            }
            GraphicsError::ImageTooLarge(size, max) => {
                write!(f, "Image too large: {} bytes (max {})", size, max)
            }
            GraphicsError::UnsupportedFormat(fmt) => write!(f, "Unsupported format: {}", fmt),
            GraphicsError::DecodeError(msg) => write!(f, "Decode error: {}", msg),
            GraphicsError::Base64Error(msg) => write!(f, "Invalid base64: {}", msg),
            GraphicsError::ImageError(msg) => write!(f, "Image decode failed: {}", msg),
            GraphicsError::KittyError(msg) => write!(f, "Kitty protocol error: {}", msg),
            GraphicsError::ITermError(msg) => write!(f, "iTerm protocol error: {}", msg),
        }
    }
}

impl std::error::Error for GraphicsError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_graphic_protocol_as_str() {
        assert_eq!(GraphicProtocol::Sixel.as_str(), "sixel");
        assert_eq!(GraphicProtocol::ITermInline.as_str(), "iterm");
        assert_eq!(GraphicProtocol::Kitty.as_str(), "kitty");
    }

    #[test]
    fn test_terminal_graphic_new() {
        let pixels = vec![255u8; 40]; // 10 RGBA pixels
        let graphic = TerminalGraphic::new(1, GraphicProtocol::Sixel, (5, 10), 10, 1, pixels);
        assert_eq!(graphic.id, 1);
        assert_eq!(graphic.position, (5, 10));
        assert_eq!(graphic.width, 10);
        assert_eq!(graphic.height, 1);
        assert_eq!(graphic.original_width, 10);
        assert_eq!(graphic.original_height, 1);
    }

    #[test]
    fn test_graphic_content_version_is_json_safe() {
        let pixels = vec![255u8; 40];
        let version = graphic_content_version(10, 1, &pixels);
        assert!(version > 0);
        assert!(version <= 9_007_199_254_740_991);
    }

    #[test]
    fn test_original_dimensions_preserved_after_mutation() {
        let pixels = vec![0u8; 200 * 100 * 4];
        let mut graphic = TerminalGraphic::new(1, GraphicProtocol::Kitty, (0, 0), 200, 100, pixels);
        assert_eq!(graphic.original_width, 200);
        assert_eq!(graphic.original_height, 100);

        // Simulate animation frame changing dimensions
        graphic.width = 150;
        graphic.height = 75;

        // Original dimensions should remain unchanged
        assert_eq!(graphic.original_width, 200);
        assert_eq!(graphic.original_height, 100);
        assert_eq!(graphic.width, 150);
        assert_eq!(graphic.height, 75);
    }

    #[test]
    fn test_original_dimensions_with_shared_pixels() {
        let pixels = Arc::new(vec![0u8; 64 * 32 * 4]);
        let graphic =
            TerminalGraphic::with_shared_pixels(1, GraphicProtocol::Kitty, (0, 0), 64, 32, pixels);
        assert_eq!(graphic.original_width, 64);
        assert_eq!(graphic.original_height, 32);
        assert_eq!(graphic.width, 64);
        assert_eq!(graphic.height, 32);
    }

    #[test]
    fn test_terminal_graphic_pixel_at() {
        // 2x2 image, RGBA
        let pixels = vec![
            255, 0, 0, 255, // (0,0) red
            0, 255, 0, 255, // (1,0) green
            0, 0, 255, 255, // (0,1) blue
            255, 255, 0, 255, // (1,1) yellow
        ];
        let graphic = TerminalGraphic::new(1, GraphicProtocol::Sixel, (0, 0), 2, 2, pixels);

        assert_eq!(graphic.pixel_at(0, 0), Some((255, 0, 0, 255)));
        assert_eq!(graphic.pixel_at(1, 0), Some((0, 255, 0, 255)));
        assert_eq!(graphic.pixel_at(0, 1), Some((0, 0, 255, 255)));
        assert_eq!(graphic.pixel_at(1, 1), Some((255, 255, 0, 255)));
        assert_eq!(graphic.pixel_at(2, 0), None);
    }

    #[test]
    fn test_graphics_store_add_remove() {
        let mut store = GraphicsStore::new();
        let graphic = TerminalGraphic::new(1, GraphicProtocol::Sixel, (0, 0), 10, 10, vec![]);

        store.add_graphic(graphic);
        assert_eq!(store.graphics_count(), 1);

        store.remove_graphic(1);
        assert_eq!(store.graphics_count(), 0);
    }

    #[test]
    fn test_graphics_store_kitty_image() {
        let mut store = GraphicsStore::new();
        let pixels = vec![255u8; 16];

        store.store_kitty_image(42, 2, 2, pixels);

        let result = store.get_kitty_image(42);
        assert!(result.is_some());
        let (w, h, data) = result.unwrap();
        assert_eq!(w, 2);
        assert_eq!(h, 2);
        assert_eq!(data.len(), 16);

        store.remove_kitty_image(42);
        assert!(store.get_kitty_image(42).is_none());
    }

    #[test]
    fn kitty_deferred_delete_survives_rejected_replacement() {
        let limits = GraphicsLimits {
            max_total_memory: 4,
            max_image_bytes: 1024,
            ..GraphicsLimits::default()
        };
        let mut store = GraphicsStore::with_limits(limits);
        let mut old_graphic = TerminalGraphic::new(
            1,
            GraphicProtocol::Kitty,
            (0, 0),
            1,
            1,
            vec![255, 0, 0, 255],
        );
        old_graphic.kitty_image_id = Some(49374);
        old_graphic.kitty_placement_id = Some(0);
        assert!(store.add_graphic(old_graphic));

        store.defer_kitty_delete(Some(49374), Some(0));
        assert_eq!(store.graphics_count(), 1);
        assert_eq!(store.deferred_kitty_delete_count(), 1);

        let mut oversized_graphic = TerminalGraphic::new(
            2,
            GraphicProtocol::Kitty,
            (0, 0),
            2,
            1,
            vec![0, 255, 0, 255, 0, 255, 0, 255],
        );
        oversized_graphic.kitty_image_id = Some(49374);
        oversized_graphic.kitty_placement_id = Some(0);
        assert!(!store.add_graphic(oversized_graphic));
        assert_eq!(store.graphics_count(), 1);
        assert_eq!(store.deferred_kitty_delete_count(), 1);

        store.commit_deferred_kitty_deletes();
        assert_eq!(store.deferred_kitty_delete_count(), 0);
        assert_eq!(store.graphics_count(), 0);
    }

    #[test]
    fn test_image_display_mode() {
        assert_eq!(ImageDisplayMode::Inline.as_str(), "inline");
        assert_eq!(ImageDisplayMode::Download.as_str(), "download");
        assert_eq!(ImageDisplayMode::default(), ImageDisplayMode::Inline);
    }

    #[test]
    fn test_image_size_unit() {
        assert_eq!(ImageSizeUnit::Auto.as_str(), "auto");
        assert_eq!(ImageSizeUnit::Cells.as_str(), "cells");
        assert_eq!(ImageSizeUnit::Pixels.as_str(), "pixels");
        assert_eq!(ImageSizeUnit::Percent.as_str(), "percent");
    }

    #[test]
    fn test_image_dimension_constructors() {
        let auto = ImageDimension::auto();
        assert!(auto.is_auto());
        assert_eq!(auto.unit, ImageSizeUnit::Auto);

        let cells = ImageDimension::cells(10.0);
        assert!(!cells.is_auto());
        assert_eq!(cells.value, 10.0);
        assert_eq!(cells.unit, ImageSizeUnit::Cells);

        let pixels = ImageDimension::pixels(100.0);
        assert_eq!(pixels.value, 100.0);
        assert_eq!(pixels.unit, ImageSizeUnit::Pixels);

        let pct = ImageDimension::percent(50.0);
        assert_eq!(pct.value, 50.0);
        assert_eq!(pct.unit, ImageSizeUnit::Percent);
    }

    #[test]
    fn test_image_dimension_zero_is_auto() {
        let dim = ImageDimension::cells(0.0);
        assert!(dim.is_auto());
    }

    #[test]
    fn test_image_dimension_negative_is_auto() {
        let dim = ImageDimension::pixels(-1.0);
        assert!(dim.is_auto());
    }

    #[test]
    fn test_image_placement_defaults() {
        let placement = ImagePlacement::default();
        assert_eq!(placement.display_mode, ImageDisplayMode::Inline);
        assert!(placement.requested_width.is_auto());
        assert!(placement.requested_height.is_auto());
        assert!(!placement.preserve_aspect_ratio); // Default struct is false
        assert_eq!(placement.z_index, 0);
        assert_eq!(placement.x_offset, 0);
        assert_eq!(placement.y_offset, 0);
        assert_eq!(placement.source_x_offset, 0);
        assert_eq!(placement.source_y_offset, 0);
        assert!(placement.source_width.is_none());
        assert!(placement.source_height.is_none());
        assert!(placement.columns.is_none());
        assert!(placement.rows.is_none());
    }

    #[test]
    fn test_image_placement_inline() {
        let placement = ImagePlacement::inline();
        assert_eq!(placement.display_mode, ImageDisplayMode::Inline);
        assert!(placement.preserve_aspect_ratio);
    }

    #[test]
    fn test_image_placement_download() {
        let placement = ImagePlacement::download();
        assert_eq!(placement.display_mode, ImageDisplayMode::Download);
    }

    #[test]
    fn test_terminal_graphic_has_default_placement() {
        let graphic = TerminalGraphic::new(1, GraphicProtocol::Sixel, (0, 0), 10, 10, vec![]);
        assert_eq!(graphic.placement.display_mode, ImageDisplayMode::Inline);
        assert!(graphic.placement.preserve_aspect_ratio);
    }

    fn make_graphics_test_graphic(
        width: usize,
        height: usize,
        col: usize,
        row: usize,
    ) -> TerminalGraphic {
        let pixels = vec![128u8; width * height * 4];
        TerminalGraphic::new(1, GraphicProtocol::Sixel, (col, row), width, height, pixels)
    }

    #[test]
    fn test_cell_span_exact_fit() {
        let graphic = make_graphics_test_graphic(100, 50, 0, 0);
        let (cols, rows) = graphic.cell_span(10, 10);
        assert_eq!(cols, 10);
        assert_eq!(rows, 5);
    }

    #[test]
    fn test_cell_span_ceiling_division() {
        let graphic = make_graphics_test_graphic(101, 51, 0, 0);
        let (cols, rows) = graphic.cell_span(10, 10);
        assert_eq!(cols, 11, "should ceil column count");
        assert_eq!(rows, 6, "should ceil row count");
    }

    #[test]
    fn test_cell_span_uses_stored_dimensions_when_set() {
        let mut graphic = make_graphics_test_graphic(100, 50, 0, 0);
        graphic.set_cell_dimensions(20, 25);
        let (cols, rows) = graphic.cell_span(10, 10);
        assert_eq!(cols, 5);
        assert_eq!(rows, 2);
    }

    #[test]
    fn test_height_in_rows_exact() {
        let graphic = make_graphics_test_graphic(100, 50, 0, 0);
        assert_eq!(graphic.height_in_rows(10), 5);
    }

    #[test]
    fn test_height_in_rows_ceiling() {
        let graphic = make_graphics_test_graphic(100, 51, 0, 0);
        assert_eq!(graphic.height_in_rows(10), 6);
    }

    #[test]
    fn test_height_in_rows_uses_stored_cell_height() {
        let mut graphic = make_graphics_test_graphic(100, 50, 0, 0);
        graphic.set_cell_dimensions(10, 25);
        assert_eq!(graphic.height_in_rows(10), 2);
    }

    #[test]
    fn test_set_cell_dimensions_affects_cell_span() {
        let mut graphic = make_graphics_test_graphic(100, 50, 0, 0);
        graphic.set_cell_dimensions(8, 16);
        let (cols, rows) = graphic.cell_span(10, 10);
        assert_eq!(cols, 13); // ceil(100/8) = 13
        assert_eq!(rows, 4); // ceil(50/16) = 4
    }

    #[test]
    fn kitty_delete_hit_testing_uses_requested_cell_span() {
        let mut store = GraphicsStore::new();
        let mut graphic = TerminalGraphic::new(
            1,
            GraphicProtocol::Kitty,
            (10, 8),
            200,
            160,
            vec![255u8; 200 * 160 * 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.requested_width = ImageDimension::cells(9.0);
        graphic.placement.requested_height = ImageDimension::cells(5.0);
        store.add_graphic(graphic);

        store.delete_kitty_graphics_in_column(19);
        assert_eq!(
            store.graphics_count(),
            1,
            "column outside requested c=9 display span must not delete"
        );

        store.delete_kitty_graphics_in_row(13);
        assert_eq!(
            store.graphics_count(),
            1,
            "row outside requested r=5 display span must not delete"
        );

        store.delete_kitty_graphics_intersecting_cell(18, 12, None);
        assert_eq!(
            store.graphics_count(),
            0,
            "last requested display cell should still delete the placement"
        );
    }

    #[test]
    fn kitty_delete_hit_testing_uses_resolved_percent_span() {
        let mut store = GraphicsStore::new();
        let mut graphic = TerminalGraphic::new(
            1,
            GraphicProtocol::Kitty,
            (2, 3),
            200,
            160,
            vec![255u8; 200 * 160 * 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.requested_width = ImageDimension::percent(50.0);
        graphic.placement.requested_height = ImageDimension::percent(50.0);
        let (cols, rows) = graphic.resolved_cell_span(Some(20), Some(10));
        assert_eq!((cols, rows), (10, 5));
        graphic.set_display_cell_span(cols, rows);
        store.add_graphic(graphic);

        store.delete_kitty_graphics_in_column(12);
        assert_eq!(
            store.graphics_count(),
            1,
            "column outside resolved percent display span must not delete"
        );

        store.delete_kitty_graphics_intersecting_cell(11, 7, None);
        assert_eq!(
            store.graphics_count(),
            0,
            "last resolved percent display cell should delete"
        );
    }

    #[test]
    fn kitty_predicate_delete_preserves_render_id_for_immediate_replacement() {
        let mut store = GraphicsStore::new();
        let mut graphic = TerminalGraphic::new(
            7,
            GraphicProtocol::Kitty,
            (10, 8),
            20,
            20,
            vec![255u8; 20 * 20 * 4],
        );
        graphic.kitty_image_id = Some(42);
        graphic.kitty_placement_id = Some(5);
        graphic.placement.z_index = 9;
        graphic.set_cell_dimensions(10, 20);
        graphic.set_display_cell_span(2, 1);
        assert!(store.add_graphic(graphic));

        store.delete_kitty_graphics_intersecting_cell(10, 8, Some(9));

        assert_eq!(store.graphics_count(), 0);
        assert_eq!(
            store.deferred_kitty_delete_count(),
            1,
            "predicate deletes should retain a tombstone for a following replacement"
        );

        let mut replacement = TerminalGraphic::new(
            99,
            GraphicProtocol::Kitty,
            (10, 8),
            20,
            20,
            vec![128u8; 20 * 20 * 4],
        );
        replacement.kitty_image_id = Some(43);
        replacement.kitty_placement_id = Some(5);
        replacement.placement.z_index = 9;
        replacement.set_cell_dimensions(10, 20);
        replacement.set_display_cell_span(2, 1);
        assert!(store.add_graphic(replacement));

        assert_eq!(store.deferred_kitty_delete_count(), 0);
        assert_eq!(store.graphics_count(), 1);
        assert_eq!(
            store.all_graphics()[0].id,
            7,
            "replacement should reuse the deleted placement render id"
        );
        assert_eq!(store.all_graphics()[0].kitty_image_id, Some(43));
    }

    #[test]
    fn resolved_cell_span_honors_single_dimension_without_preserving_aspect_ratio() {
        let mut graphic = TerminalGraphic::new(
            1,
            GraphicProtocol::ITermInline,
            (0, 0),
            1,
            1,
            vec![255u8; 4],
        );
        graphic.set_cell_dimensions(1, 2);
        graphic.placement.requested_height = ImageDimension::cells(3.0);
        graphic.placement.preserve_aspect_ratio = false;

        assert_eq!(graphic.resolved_cell_span(Some(80), Some(24)), (1, 3));

        let mut width_only = TerminalGraphic::new(
            2,
            GraphicProtocol::ITermInline,
            (0, 0),
            1,
            1,
            vec![255u8; 4],
        );
        width_only.set_cell_dimensions(1, 2);
        width_only.placement.requested_width = ImageDimension::cells(4.0);
        width_only.placement.preserve_aspect_ratio = false;

        assert_eq!(width_only.resolved_cell_span(Some(80), Some(24)), (4, 1));
    }

    #[test]
    fn resolved_cell_span_uses_kitty_source_rectangle() {
        let mut graphic = TerminalGraphic::new(
            1,
            GraphicProtocol::Kitty,
            (0, 0),
            100,
            50,
            vec![255u8; 100 * 50 * 4],
        );
        graphic.set_cell_dimensions(10, 10);
        graphic.placement.source_x_offset = 25;
        graphic.placement.source_y_offset = 10;
        graphic.placement.source_width = Some(20);
        graphic.placement.source_height = Some(15);

        assert_eq!(graphic.source_rect_pixels(), Some((25, 10, 20, 15)));
        assert_eq!(graphic.resolved_cell_span(Some(80), Some(24)), (2, 2));

        graphic.placement.requested_width = ImageDimension::cells(6.0);
        graphic.placement.requested_height = ImageDimension::cells(3.0);
        assert_eq!(graphic.resolved_cell_span(Some(80), Some(24)), (6, 3));
    }

    #[test]
    fn resolved_cell_span_includes_kitty_cell_offsets() {
        let mut graphic = TerminalGraphic::new(
            1,
            GraphicProtocol::Kitty,
            (0, 0),
            10,
            10,
            vec![255u8; 10 * 10 * 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.x_offset = 5;
        graphic.placement.y_offset = 15;

        assert_eq!(graphic.resolved_cell_span(Some(80), Some(24)), (2, 2));

        graphic.placement.requested_width = ImageDimension::cells(3.0);
        graphic.placement.requested_height = ImageDimension::cells(2.0);
        assert_eq!(graphic.resolved_cell_span(Some(80), Some(24)), (4, 3));
    }

    #[test]
    fn kitty_scroll_up_uses_resolved_display_span() {
        let mut store = GraphicsStore::new();
        let mut graphic =
            TerminalGraphic::new(1, GraphicProtocol::Kitty, (0, 0), 1, 1, vec![255u8; 4]);
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.requested_width = ImageDimension::cells(9.0);
        graphic.placement.requested_height = ImageDimension::cells(5.0);
        let (cols, rows) = graphic.resolved_cell_span(Some(80), Some(24));
        assert_eq!((cols, rows), (9, 5));
        graphic.set_display_cell_span(cols, rows);
        store.add_graphic(graphic);

        store.adjust_for_scroll_up_with_scrollback(1, 0, 23, 0);

        assert_eq!(
            store.graphics_count(),
            1,
            "a c=9,r=5 graphic should remain visible after one row scroll"
        );
        assert_eq!(store.scrollback_count(), 0);
        assert_eq!(store.all_graphics()[0].position.1, 0);
        assert_eq!(store.all_graphics()[0].scroll_offset_rows, 1);
    }

    #[test]
    fn nonzero_top_scroll_region_clips_graphics_without_scrollback() {
        let mut store = GraphicsStore::new();
        let mut graphic =
            TerminalGraphic::new(1, GraphicProtocol::Sixel, (0, 2), 1, 4, vec![255u8; 16]);
        graphic.set_cell_dimensions(1, 2);
        graphic.set_display_cell_span(1, 2);
        assert!(store.add_graphic(graphic));

        store.adjust_for_scroll_up_with_scrollback(1, 2, 5, 0);

        assert_eq!(
            store.graphics_count(),
            1,
            "a partially clipped region graphic should remain visible"
        );
        let graphic = &store.all_graphics()[0];
        assert_eq!(
            graphic.position.1, 2,
            "scroll-region clipping should not move graphics above the top margin"
        );
        assert_eq!(
            graphic.scroll_offset_rows, 1,
            "the clipped row should be tracked as a scroll offset"
        );
        assert_eq!(
            store.scrollback_count(),
            0,
            "non-zero scroll regions discard clipped rows instead of adding graphics scrollback"
        );

        store.adjust_for_scroll_up_with_scrollback(1, 2, 5, 0);

        assert_eq!(
            store.graphics_count(),
            0,
            "fully clipped region graphics should be discarded"
        );
        assert_eq!(
            store.scrollback_count(),
            0,
            "fully clipped region graphics must not be retained in scrollback"
        );
    }

    #[test]
    fn scrollback_graphics_count_toward_total_memory_budget() {
        let mut store = GraphicsStore::with_limits(GraphicsLimits {
            max_total_memory: 4,
            max_image_bytes: 1024,
            ..GraphicsLimits::default()
        });
        let graphic = TerminalGraphic::new(1, GraphicProtocol::Sixel, (0, 0), 1, 1, vec![255u8; 4]);
        assert!(store.add_graphic(graphic));

        store.adjust_for_scroll_up_with_scrollback(1, 0, 23, 0);
        assert_eq!(store.graphics_count(), 0);
        assert_eq!(store.scrollback_count(), 1);

        let replacement =
            TerminalGraphic::new(2, GraphicProtocol::Sixel, (0, 0), 1, 1, vec![128u8; 4]);
        assert!(store.add_graphic(replacement));

        assert_eq!(store.graphics_count(), 1);
        assert_eq!(
            store.scrollback_count(),
            0,
            "scrollback pixels must be evicted when they exceed max_total_memory"
        );
    }

    #[test]
    fn animation_frames_count_toward_total_memory_budget() {
        let mut store = GraphicsStore::with_limits(GraphicsLimits {
            max_total_memory: 4,
            max_image_bytes: 1024,
            ..GraphicsLimits::default()
        });

        store.add_animation_frame(42, AnimationFrame::new(1, vec![255u8; 4], 1, 1));
        assert_eq!(store.get_animation(42).unwrap().frame_count(), 1);

        store.add_animation_frame(42, AnimationFrame::new(2, vec![128u8; 4], 1, 1));

        let animation = store.get_animation(42).unwrap();
        assert_eq!(animation.frame_count(), 1);
        assert!(animation.get_frame(1).is_none());
        assert!(animation.get_frame(2).is_some());
        assert_eq!(store.dropped_count(), 1);
    }

    #[test]
    fn replacing_current_animation_frame_refreshes_kitty_references() {
        let mut store = GraphicsStore::new();
        let initial = vec![255, 0, 0, 255];
        let current = vec![0, 0, 255, 255];
        let replacement = vec![0, 255, 0, 255];

        let mut active_graphic =
            TerminalGraphic::new(1, GraphicProtocol::Kitty, (0, 0), 1, 1, initial.clone());
        active_graphic.kitty_image_id = Some(44);
        active_graphic.kitty_placement_id = Some(1);
        assert!(store.add_graphic(active_graphic));

        let mut virtual_graphic =
            TerminalGraphic::new(2, GraphicProtocol::Kitty, (1, 0), 1, 1, initial.clone());
        virtual_graphic.kitty_image_id = Some(44);
        virtual_graphic.kitty_placement_id = Some(2);
        store.add_virtual_placement(virtual_graphic);

        store.store_kitty_image(44, 1, 1, initial.clone());
        store.add_animation_frame(44, AnimationFrame::new(1, initial, 1, 1));
        store.add_animation_frame(44, AnimationFrame::new(2, current.clone(), 1, 1));
        assert!(store.set_animation_current_frame(44, 2));
        assert_eq!(
            store.all_graphics()[0].pixels.as_ref().as_slice(),
            current.as_slice()
        );

        let active_asset_version = store.all_graphics()[0].asset_version;
        let virtual_asset_version = store
            .get_virtual_placement(44, 2)
            .expect("expected Kitty virtual placement")
            .asset_version;

        store.add_animation_frame(44, AnimationFrame::new(2, replacement.clone(), 1, 1));

        assert_eq!(
            store.all_graphics()[0].pixels.as_ref().as_slice(),
            replacement.as_slice()
        );
        assert_ne!(store.all_graphics()[0].asset_version, active_asset_version);
        let virtual_placement = store
            .get_virtual_placement(44, 2)
            .expect("expected Kitty virtual placement");
        assert_eq!(
            virtual_placement.pixels.as_ref().as_slice(),
            replacement.as_slice()
        );
        assert_ne!(virtual_placement.asset_version, virtual_asset_version);
        let shared = store
            .get_kitty_image(44)
            .expect("expected Kitty shared image");
        assert_eq!(shared.2.as_ref().as_slice(), replacement.as_slice());
    }

    #[test]
    fn memory_eviction_prefers_non_visible_graphics() {
        let mut store = GraphicsStore::with_limits(GraphicsLimits {
            max_total_memory: 8,
            max_image_bytes: 1024,
            ..GraphicsLimits::default()
        });
        let mut cleared =
            TerminalGraphic::new(1, GraphicProtocol::Kitty, (0, 0), 1, 1, vec![255u8; 4]);
        cleared.kitty_image_id = Some(7);
        cleared.kitty_placement_id = Some(1);
        assert!(store.add_graphic(cleared));
        store.clear();
        assert_eq!(store.pending_cleared_kitty_graphics_count(), 1);

        let visible = TerminalGraphic::new(2, GraphicProtocol::Sixel, (0, 0), 1, 1, vec![128u8; 4]);
        assert!(store.add_graphic(visible));

        let replacement =
            TerminalGraphic::new(3, GraphicProtocol::Sixel, (1, 0), 1, 1, vec![64u8; 4]);
        assert!(store.add_graphic(replacement));

        assert_eq!(
            store.pending_cleared_kitty_graphics_count(),
            0,
            "non-visible cleared placements should be evicted before visible graphics"
        );
        assert_eq!(store.graphics_count(), 2);
        assert!(store.all_graphics().iter().any(|graphic| graphic.id == 2));
        assert!(store.all_graphics().iter().any(|graphic| graphic.id == 3));
    }

    #[test]
    fn scrollback_row_tracks_graphic_original_row() {
        let mut store = GraphicsStore::new();
        let graphic = TerminalGraphic::new(1, GraphicProtocol::Sixel, (0, 5), 1, 1, vec![255u8; 4]);
        assert!(store.add_graphic(graphic));

        store.adjust_for_scroll_up_with_scrollback(6, 0, 23, 10);

        assert_eq!(store.graphics_count(), 0);
        assert_eq!(store.scrollback_count(), 1);
        assert_eq!(store.all_scrollback_graphics()[0].scrollback_row, Some(15));
    }

    #[test]
    fn test_graphics_at_row_includes_graphic() {
        let mut store = GraphicsStore::new();
        let graphic = make_graphics_test_graphic(80, 20, 0, 2);
        store.add_graphic(graphic);
        let at_row2 = store.graphics_at_row(2);
        assert_eq!(at_row2.len(), 1, "should find graphic at row 2");
    }

    #[test]
    fn test_graphics_at_row_empty_store() {
        let store = GraphicsStore::new();
        assert!(store.graphics_at_row(0).is_empty());
    }

    #[test]
    fn test_graphics_at_row_out_of_range() {
        let mut store = GraphicsStore::new();
        let graphic = make_graphics_test_graphic(80, 10, 0, 5);
        store.add_graphic(graphic);
        assert!(
            store.graphics_at_row(0).is_empty(),
            "row 0 should not find graphic at row 5"
        );
        assert!(
            !store.graphics_at_row(5).is_empty(),
            "row 5 should find the graphic"
        );
    }

    #[test]
    fn graphics_at_row_uses_resolved_display_span() {
        let mut store = GraphicsStore::new();
        let mut graphic = TerminalGraphic::new(
            1,
            GraphicProtocol::Kitty,
            (10, 8),
            200,
            160,
            vec![255u8; 200 * 160 * 4],
        );
        graphic.set_cell_dimensions(10, 20);
        graphic.placement.requested_width = ImageDimension::cells(9.0);
        graphic.placement.requested_height = ImageDimension::cells(5.0);
        let (cols, rows) = graphic.resolved_cell_span(Some(80), Some(24));
        assert_eq!((cols, rows), (9, 5));
        graphic.set_display_cell_span(cols, rows);
        assert!(store.add_graphic(graphic));

        assert_eq!(store.graphics_at_row(12).len(), 1);
        assert!(
            store.graphics_at_row(13).is_empty(),
            "row outside resolved r=5 display span must not be reported"
        );
    }

    #[test]
    fn test_sample_half_block_returns_colors() {
        let graphic = make_graphics_test_graphic(20, 20, 0, 0);
        let result = graphic.sample_half_block(0, 0, 10, 10);
        assert!(
            result.is_some(),
            "sample_half_block should return Some for in-bounds cell"
        );
        let (_top, _bottom) = result.unwrap();
    }

    #[test]
    fn test_sample_half_block_out_of_bounds_returns_none() {
        let graphic = make_graphics_test_graphic(10, 10, 0, 0);
        let result = graphic.sample_half_block(100, 100, 10, 10);
        assert!(result.is_none(), "out-of-bounds cell should return None");
    }
}
