//! Kitty graphics protocol support
//!
//! Parses Kitty APC graphics sequences:
//! `APC G <key>=<value>,<key>=<value>;<base64-data> ST`
//!
//! Reference: <https://sw.kovidgoyal.net/kitty/graphics-protocol/>

use std::collections::HashMap;
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use flate2::read::ZlibDecoder;

use crate::graphics::{
    next_graphic_id, AnimationControl, AnimationFrame, CompositionMode, GraphicProtocol,
    GraphicsError, GraphicsStore, ImageDimension, ImagePlacement, TerminalGraphic,
};

/// Kitty graphics transmission action
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum KittyAction {
    #[default]
    Transmit, // t - transmit image data
    TransmitDisplay,  // T - transmit and display
    Query,            // q - query terminal support
    Put,              // p - display previously transmitted image
    Delete,           // d - delete images
    Frame,            // f - animation frame
    Compose,          // c - compose animation frame rectangles
    AnimationControl, // a - animation control
}

impl KittyAction {
    /// Parse action character
    pub fn from_char(c: char) -> Option<Self> {
        match c {
            't' => Some(KittyAction::Transmit),
            'T' => Some(KittyAction::TransmitDisplay),
            'q' => Some(KittyAction::Query),
            'p' => Some(KittyAction::Put),
            'd' => Some(KittyAction::Delete),
            'f' => Some(KittyAction::Frame),
            'c' => Some(KittyAction::Compose),
            'a' => Some(KittyAction::AnimationControl),
            _ => None,
        }
    }
}

/// Kitty transmission format
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum KittyFormat {
    #[default]
    Rgba, // 32 - 32-bit RGBA
    Rgb, // 24 - 24-bit RGB
    Png, // 100 - PNG compressed
}

impl KittyFormat {
    /// Parse format code
    pub fn from_code(code: u32) -> Option<Self> {
        match code {
            24 => Some(KittyFormat::Rgb),
            32 => Some(KittyFormat::Rgba),
            100 => Some(KittyFormat::Png),
            _ => None,
        }
    }
}

/// Kitty transmission medium
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum KittyMedium {
    #[default]
    Direct, // d - direct in-band data
    File,      // f - read from file
    TempFile,  // t - read from temp file and delete
    SharedMem, // s - read from shared memory
}

impl KittyMedium {
    /// Parse medium character
    pub fn from_char(c: char) -> Option<Self> {
        match c {
            'd' => Some(KittyMedium::Direct),
            'f' => Some(KittyMedium::File),
            't' => Some(KittyMedium::TempFile),
            's' => Some(KittyMedium::SharedMem),
            _ => None,
        }
    }
}

/// Kitty compression format (o= parameter)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum KittyCompression {
    #[default]
    None, // No compression (default)
    Zlib, // zlib/deflate compression (o=z)
}

impl KittyCompression {
    /// Parse compression character
    pub fn from_char(c: char) -> Option<Self> {
        match c {
            'z' => Some(KittyCompression::Zlib),
            _ => None,
        }
    }
}

/// Kitty delete target
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KittyDeleteTarget {
    All,       // a - all images
    ById(u32), // i - by image id
    ByImageIdRange {
        start: u32,
        end: u32,
    }, // r - by image id range
    ByPlacement(u32, Option<u32>), // (image_id, placement_id)
    ByImageNumber(u32, Option<u32>), // (image_number, placement_id)
    AnimationFrame {
        image_id: u32,
        frame_number: Option<u32>,
    }, // f/F - animation frame
    AtCursor,  // c - at cursor position
    InCell {
        col: usize,
        row: usize,
        z_index: Option<i32>,
    }, // p/q - at specific cell, optional z
    OnScreen,  // z - visible on screen
    ByColumn(u32), // x - in column
    ByRow(u32), // y - in row
    ByZIndex(i32), // z - by z-index
}

/// Result of building a Kitty graphic
#[derive(Debug, Clone)]
#[allow(clippy::large_enum_variant)]
pub enum KittyGraphicResult {
    /// A regular graphic that should be displayed
    Graphic(TerminalGraphic),
    /// A virtual placement - insert Unicode placeholders into grid
    VirtualPlacement {
        image_id: u32,
        placement_id: u32,
        position: (usize, usize),
        cols: usize,
        rows: usize,
    },
    /// Command processed but no output (delete, query, transmit-only, etc.)
    None,
}

/// Kitty graphics parser
#[derive(Debug, Default)]
pub struct KittyParser {
    /// Current action
    pub action: KittyAction,
    /// Image ID for reuse
    pub image_id: Option<u32>,
    /// Image number for terminal-allocated image ids (I=).
    pub image_number: Option<u32>,
    /// Placement ID
    pub placement_id: Option<u32>,
    /// Transmission format
    pub format: KittyFormat,
    /// Transmission medium
    pub medium: KittyMedium,
    /// Image width
    pub width: Option<u32>,
    /// Image height
    pub height: Option<u32>,
    /// Columns to display (for scaling)
    pub columns: Option<u32>,
    /// Rows to display (for scaling)
    pub rows: Option<u32>,
    /// Byte size to read from file or shared-memory media (S=)
    pub file_read_size: Option<u64>,
    /// Byte offset to read from file or shared-memory media (O=)
    pub file_read_offset: Option<u64>,
    /// Source rectangle X offset, or delete/frame X depending on action.
    pub x_offset: Option<u32>,
    /// Source rectangle Y offset, or delete/frame Y depending on action.
    pub y_offset: Option<u32>,
    /// Source rectangle width (w=)
    pub source_width: Option<u32>,
    /// Source rectangle height (h=)
    pub source_height: Option<u32>,
    /// X offset within the first placement cell, or compose destination X offset (X=).
    pub cell_x_offset: Option<u32>,
    /// Y offset within the first placement cell, or compose destination Y offset (Y=).
    pub cell_y_offset: Option<u32>,
    /// Compression format (o= parameter)
    pub compression: KittyCompression,
    /// More chunks expected
    pub more_chunks: bool,
    /// Response suppression level (q=1 suppresses OK, q=2 suppresses OK and errors)
    pub response_suppression: u8,
    /// Accumulated data chunks
    data_chunks: Vec<Vec<u8>>,
    /// Delete target
    pub delete_target: Option<KittyDeleteTarget>,
    /// Whether a delete command should also release image data when unreferenced.
    pub delete_image_data: bool,
    /// Virtual placement (U=1)
    pub is_virtual: bool,
    /// Parent image ID for relative positioning (P= key)
    pub parent_image_id: Option<u32>,
    /// Parent placement ID for relative positioning (Q= key)
    pub parent_placement_id: Option<u32>,
    /// Relative X offset (H= key) in terminal cells
    pub relative_x_offset: Option<i32>,
    /// Relative Y offset (V= key) in terminal cells
    pub relative_y_offset: Option<i32>,
    /// Frame number for animation
    pub frame_number: Option<u32>,
    /// Base frame for frame-loading composition (c= when a=f)
    pub frame_base_frame: Option<u32>,
    /// Signed frame gap in milliseconds. Positive values delay; negative values are gapless.
    pub frame_delay_ms: Option<i32>,
    /// Frame composition mode
    pub frame_composition: Option<CompositionMode>,
    /// Destination frame for animation compose commands (c= when a=c)
    pub compose_destination_frame: Option<u32>,
    /// Animation control
    pub animation_control: Option<AnimationControl>,
    /// Current frame requested by an animation control command (c=).
    pub animation_current_frame: Option<u32>,
    /// Number of times to play animation (v= parameter)
    /// Per Kitty spec: v=0 ignored, v=1 infinite, v=N means play N times total
    pub num_plays: Option<u32>,
    /// Z-index for layering (z= for placement commands)
    pub z_index: Option<i32>,
    /// Cursor position captured when a multi-part placement transfer begins.
    pub placement_position: Option<(usize, usize)>,
    /// Whether the placement should leave the terminal cursor unchanged (C=1).
    pub suppress_cursor_movement: bool,
    /// Maximum accumulated and decompressed payload bytes accepted for this transfer.
    max_data_bytes: Option<usize>,
    /// Raw parameters for debugging
    params: HashMap<String, String>,
}

impl KittyParser {
    /// Create a new parser
    pub fn new() -> Self {
        Self::default()
    }

    /// Set the maximum decoded bytes accepted for subsequent chunks.
    pub fn set_max_data_bytes(&mut self, max_data_bytes: usize) {
        self.max_data_bytes = Some(max_data_bytes);
    }

    /// Reset parser state for new transmission
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// Parse a Kitty graphics payload
    ///
    /// Format: `key=value,key=value,...;base64data`
    pub fn parse_chunk(&mut self, payload: &str) -> Result<bool, GraphicsError> {
        // Split into params and data
        let (params_str, data_str) = payload.split_once(';').unwrap_or((payload, ""));

        let pairs = params_str
            .split(',')
            .filter_map(|pair| pair.split_once('='))
            .collect::<Vec<_>>();
        let has_image_id = self.image_id.is_some() || pairs.iter().any(|(key, _)| *key == "i");
        let has_image_number =
            self.image_number.is_some() || pairs.iter().any(|(key, _)| *key == "I");
        if has_image_id && has_image_number {
            return Err(GraphicsError::KittyError(
                "Cannot specify both image id and image number".to_string(),
            ));
        }

        for (key, value) in &pairs {
            self.params.insert((*key).to_string(), (*value).to_string());
            if *key == "a" {
                if let Some(c) = value.chars().next() {
                    self.action = KittyAction::from_char(c).unwrap_or_default();
                }
            }
        }

        // Parse key=value pairs after action is known. Kitty parameters are unordered,
        // and several keys have action-dependent meanings.
        for (key, value) in pairs {
            match key {
                "a" => {}
                "f" => {
                    if let Ok(code) = value.parse::<u32>() {
                        self.format = KittyFormat::from_code(code).unwrap_or_default();
                    }
                }
                "t" => {
                    if let Some(c) = value.chars().next() {
                        self.medium = KittyMedium::from_char(c).unwrap_or_default();
                    }
                }
                "i" => {
                    self.image_id = value.parse().ok();
                }
                "I" => {
                    self.image_number = value.parse().ok();
                }
                "p" => {
                    self.placement_id = value.parse().ok();
                }
                "s" => {
                    // Animation control state (for AnimationControl action) takes priority
                    if self.action == KittyAction::AnimationControl {
                        self.animation_control = AnimationControl::from_value(value);
                        debug_log!(
                            "KITTY",
                            "Parsed animation control: s={} -> {:?}",
                            value,
                            self.animation_control
                        );
                    } else {
                        // Otherwise it's width
                        self.width = value.parse().ok();
                    }
                }
                "v" => {
                    // v= is overloaded: height for images, num_plays for animation control
                    if self.action == KittyAction::AnimationControl {
                        // Number of times to play animation (v= for animation control)
                        // Per Kitty spec: v=0 ignored, v=1 infinite, v=N means play N times total
                        self.num_plays = value.parse().ok();
                    } else {
                        // Height for image transmission/display
                        self.height = value.parse().ok();
                    }
                }
                "c" => {
                    if self.action == KittyAction::Frame {
                        self.frame_base_frame = value.parse().ok();
                    } else if self.action == KittyAction::Compose {
                        self.compose_destination_frame = value.parse().ok();
                    } else if self.action == KittyAction::AnimationControl {
                        self.animation_current_frame = value.parse().ok();
                    } else {
                        // Otherwise it's columns
                        self.columns = value.parse().ok();
                    }
                }
                "C" => {
                    if self.action == KittyAction::Compose {
                        if let Some(first_char) = value.chars().next() {
                            self.frame_composition = CompositionMode::from_char(first_char);
                        }
                    } else {
                        self.suppress_cursor_movement = value == "1";
                    }
                }
                "r" => {
                    // Frame number (for Frame action) takes priority
                    if self.action == KittyAction::Frame
                        || self.action == KittyAction::Compose
                        || self.action == KittyAction::AnimationControl
                        || self.delete_action_is_animation_frame()
                    {
                        self.frame_number = value.parse().ok();
                    } else {
                        // Otherwise it's rows
                        self.rows = value.parse().ok();
                    }
                }
                "S" => {
                    self.file_read_size = value.parse().ok();
                }
                "O" => {
                    self.file_read_offset = value.parse().ok();
                }
                "x" => {
                    self.x_offset = value.parse().ok();
                }
                "y" => {
                    self.y_offset = value.parse().ok();
                }
                "w" => {
                    self.source_width = value.parse().ok();
                }
                "h" => {
                    self.source_height = value.parse().ok();
                }
                "X" => {
                    if self.action == KittyAction::Frame {
                        if let Some(first_char) = value.chars().next() {
                            self.frame_composition = CompositionMode::from_char(first_char);
                        }
                    } else {
                        self.cell_x_offset = value.parse().ok();
                    }
                }
                "Y" => {
                    self.cell_y_offset = value.parse().ok();
                }
                "m" => {
                    self.more_chunks = value == "1";
                }
                "q" => {
                    self.response_suppression = value.parse().unwrap_or(0);
                }
                "d" => {}
                "U" => {
                    // Virtual placement
                    self.is_virtual = value == "1";
                }
                "P" => {
                    // Parent image ID for relative positioning
                    self.parent_image_id = value.parse().ok();
                }
                "Q" => {
                    // Parent placement ID for relative positioning
                    self.parent_placement_id = value.parse().ok();
                }
                "H" => {
                    // Relative X offset in terminal cells
                    self.relative_x_offset = value.parse().ok();
                }
                "V" => {
                    // Relative Y offset in terminal cells (note: different from v=height)
                    self.relative_y_offset = value.parse().ok();
                }
                "o" => {
                    // Compression format
                    if let Some(c) = value.chars().next() {
                        if let Some(comp) = KittyCompression::from_char(c) {
                            self.compression = comp;
                        }
                    }
                }
                "z" => {
                    // z= is overloaded: frame delay for animations, z-index for placements
                    if self.action == KittyAction::Frame
                        || self.action == KittyAction::AnimationControl
                    {
                        self.frame_delay_ms = value.parse().ok();
                    } else {
                        self.z_index = value.parse().ok();
                    }
                }
                _ => {}
            }
        }

        if self.action == KittyAction::Delete {
            self.resolve_delete_target();
        }

        // Decode and accumulate base64 data
        if !data_str.is_empty() {
            // Try STANDARD first (with padding), then NO_PAD if that fails
            // This handles both padded and unpadded base64 (Kitty allows both)
            let decoded =
                base64::Engine::decode(&base64::engine::general_purpose::STANDARD, data_str)
                    .or_else(|_| {
                        base64::Engine::decode(
                            &base64::engine::general_purpose::STANDARD_NO_PAD,
                            data_str,
                        )
                    })
                    .map_err(|e| GraphicsError::Base64Error(e.to_string()))?;
            if self
                .data_chunks
                .iter()
                .map(Vec::len)
                .sum::<usize>()
                .saturating_add(decoded.len())
                > self.max_data_bytes.unwrap_or(usize::MAX)
            {
                return Err(GraphicsError::KittyError(
                    "image data exceeds configured byte limit".to_string(),
                ));
            }
            self.data_chunks.push(decoded);
        }

        // Return true if more chunks expected
        Ok(self.more_chunks)
    }

    /// Parse delete target specification
    fn parse_delete_target(&mut self, value: &str) {
        if let Some(c) = value.chars().next() {
            self.delete_image_data = c.is_ascii_uppercase();
            self.delete_target = match c {
                'a' | 'A' => Some(KittyDeleteTarget::All),
                'i' | 'I' => self.image_id.map(|id| {
                    if self.placement_id.is_some() {
                        KittyDeleteTarget::ByPlacement(id, self.placement_id)
                    } else {
                        KittyDeleteTarget::ById(id)
                    }
                }),
                'n' | 'N' => self
                    .image_number
                    .map(|number| KittyDeleteTarget::ByImageNumber(number, self.placement_id)),
                'r' | 'R' => match (self.x_offset, self.y_offset) {
                    (Some(start), Some(end)) if start <= end => {
                        Some(KittyDeleteTarget::ByImageIdRange { start, end })
                    }
                    _ => None,
                },
                'f' | 'F' => self
                    .image_id
                    .map(|image_id| KittyDeleteTarget::AnimationFrame {
                        image_id,
                        frame_number: self.frame_number,
                    }),
                'c' | 'C' => Some(KittyDeleteTarget::AtCursor),
                'p' | 'P' => Some(KittyDeleteTarget::InCell {
                    col: self.x_offset.unwrap_or(1).saturating_sub(1) as usize,
                    row: self.y_offset.unwrap_or(1).saturating_sub(1) as usize,
                    z_index: None,
                }),
                'q' | 'Q' => Some(KittyDeleteTarget::InCell {
                    col: self.x_offset.unwrap_or(1).saturating_sub(1) as usize,
                    row: self.y_offset.unwrap_or(1).saturating_sub(1) as usize,
                    z_index: self.z_index,
                }),
                'x' | 'X' => self
                    .x_offset
                    .map(|col| KittyDeleteTarget::ByColumn(col.saturating_sub(1))),
                'y' | 'Y' => self
                    .y_offset
                    .map(|row| KittyDeleteTarget::ByRow(row.saturating_sub(1))),
                'z' | 'Z' => self.z_index.map(KittyDeleteTarget::ByZIndex),
                _ => None,
            };
        }
    }

    fn delete_action_is_animation_frame(&self) -> bool {
        self.action == KittyAction::Delete
            && self
                .params
                .get("d")
                .and_then(|value| value.chars().next())
                .is_some_and(|action| matches!(action, 'f' | 'F'))
    }

    fn resolve_delete_target(&mut self) {
        let target = self.params.get("d").cloned();
        if let Some(value) = target {
            self.parse_delete_target(&value);
        } else {
            self.delete_image_data = false;
            self.delete_target = Some(KittyDeleteTarget::OnScreen);
        }
    }

    fn new_image_id(&self, store: &mut GraphicsStore) -> Option<u32> {
        if let Some(image_id) = self.image_id {
            if let Some(image_number) = self.image_number {
                store.record_kitty_image_number(image_number, image_id);
            }
            return Some(image_id);
        }
        self.image_number
            .map(|image_number| store.allocate_kitty_image_id_for_number(image_number))
    }

    fn existing_image_id(&self, store: &GraphicsStore) -> Option<u32> {
        self.image_id.or_else(|| {
            self.image_number
                .and_then(|image_number| store.kitty_image_id_for_number(image_number))
        })
    }

    /// Get accumulated data, decompressing if necessary
    pub fn get_data(&self) -> Vec<u8> {
        let raw = self.data_chunks.concat();
        if self.compression == KittyCompression::Zlib {
            match Self::decompress_zlib(&raw) {
                Ok(decompressed) => decompressed,
                Err(_) => raw, // Fall back to raw data on decompression failure
            }
        } else {
            raw
        }
    }

    /// Get accumulated data with input and decompressed output byte limits.
    pub fn get_data_limited(&self, max_bytes: usize) -> Result<Vec<u8>, GraphicsError> {
        let raw = self.raw_data_limited(max_bytes)?;
        if self.compression == KittyCompression::Zlib {
            Self::decompress_zlib_limited(&raw, max_bytes)
        } else {
            Ok(raw)
        }
    }

    fn raw_data_limited(&self, max_bytes: usize) -> Result<Vec<u8>, GraphicsError> {
        let total = self.data_chunks.iter().map(Vec::len).sum::<usize>();
        if total > max_bytes {
            return Err(GraphicsError::KittyError(
                "image data exceeds configured byte limit".to_string(),
            ));
        }
        let mut raw = Vec::with_capacity(total);
        for chunk in &self.data_chunks {
            raw.extend_from_slice(chunk);
        }
        Ok(raw)
    }

    /// Decompress zlib-compressed data
    fn decompress_zlib(data: &[u8]) -> Result<Vec<u8>, GraphicsError> {
        let mut decoder = ZlibDecoder::new(data);
        let mut decompressed = Vec::new();
        decoder
            .read_to_end(&mut decompressed)
            .map_err(|e| GraphicsError::KittyError(format!("Zlib decompression failed: {}", e)))?;
        Ok(decompressed)
    }

    fn decompress_zlib_limited(data: &[u8], max_bytes: usize) -> Result<Vec<u8>, GraphicsError> {
        let decoder = ZlibDecoder::new(data);
        let mut limited = decoder.take(max_bytes.saturating_add(1) as u64);
        let mut decompressed = Vec::new();
        limited
            .read_to_end(&mut decompressed)
            .map_err(|e| GraphicsError::KittyError(format!("Zlib decompression failed: {}", e)))?;
        if decompressed.len() > max_bytes {
            return Err(GraphicsError::KittyError(
                "decompressed image data exceeds configured byte limit".to_string(),
            ));
        }
        Ok(decompressed)
    }

    /// Check if data was compressed
    pub fn is_compressed(&self) -> bool {
        self.compression != KittyCompression::None
    }

    /// Whether an OK response should be sent for this command.
    pub fn should_send_success_response(&self) -> bool {
        self.response_suppression == 0
    }

    /// Whether an error response should be sent for this command.
    pub fn should_send_error_response(&self) -> bool {
        self.response_suppression < 2
    }

    /// Whether a completed display placement should advance the terminal cursor.
    pub fn should_move_cursor_after_display(&self) -> bool {
        matches!(self.action, KittyAction::TransmitDisplay | KittyAction::Put)
            && !self.suppress_cursor_movement
            && !self.is_virtual
            && self.parent_image_id.is_none()
            && self.parent_placement_id.is_none()
    }

    /// Build an ImagePlacement from the parsed Kitty parameters
    pub fn build_placement(&self) -> ImagePlacement {
        let mut placement = ImagePlacement::inline();

        if let Some(cols) = self.columns {
            placement.columns = Some(cols);
            placement.requested_width = ImageDimension::cells(cols as f64);
        }

        if let Some(rows) = self.rows {
            placement.rows = Some(rows);
            placement.requested_height = ImageDimension::cells(rows as f64);
        }

        if let Some(z) = self.z_index {
            placement.z_index = z;
        }

        if let Some(x) = self.cell_x_offset {
            placement.x_offset = x;
        }

        if let Some(y) = self.cell_y_offset {
            placement.y_offset = y;
        }

        if let Some(x) = self.x_offset {
            placement.source_x_offset = x;
        }

        if let Some(y) = self.y_offset {
            placement.source_y_offset = y;
        }

        placement.source_width = self.source_width;
        placement.source_height = self.source_height;

        placement
    }

    fn apply_relative_metadata(
        &self,
        graphic: &mut TerminalGraphic,
        store: &GraphicsStore,
    ) -> Result<(), GraphicsError> {
        if let Some(parent_img_id) = self.parent_image_id {
            graphic.parent_image_id = Some(parent_img_id);
            graphic.parent_placement_id = self.parent_placement_id;
            graphic.relative_x_offset = self.relative_x_offset.unwrap_or(0);
            graphic.relative_y_offset = self.relative_y_offset.unwrap_or(0);
            store.resolve_relative_kitty_placement(graphic)?;
        }
        Ok(())
    }

    /// Build a TerminalGraphic from parsed data
    pub fn build_graphic(
        &self,
        position: (usize, usize),
        store: &mut GraphicsStore,
    ) -> Result<KittyGraphicResult, GraphicsError> {
        self.build_graphic_for_screen(position, store, false)
    }

    /// Build a TerminalGraphic from parsed data for a specific screen buffer.
    pub fn build_graphic_for_screen(
        &self,
        position: (usize, usize),
        store: &mut GraphicsStore,
        alternate_screen: bool,
    ) -> Result<KittyGraphicResult, GraphicsError> {
        let data_limit = store.max_decoded_image_bytes();
        match self.action {
            KittyAction::Delete => {
                // Handle delete
                let screen = Some(alternate_screen);
                let deleted_image_ids = if let Some(target) = &self.delete_target {
                    match target {
                        KittyDeleteTarget::All => {
                            let mut image_ids = store.delete_all_kitty_graphics_for_screen(screen);
                            if self.delete_image_data {
                                image_ids.extend(store.kitty_image_data_ids());
                            }
                            image_ids
                        }
                        KittyDeleteTarget::ById(id) => {
                            let mut image_ids =
                                store.delete_kitty_graphics_for_screen(Some(*id), None, screen);
                            image_ids.insert(*id);
                            image_ids
                        }
                        KittyDeleteTarget::ByImageIdRange { start, end } => store
                            .delete_kitty_graphics_by_image_id_range_for_screen(
                                *start, *end, screen,
                            ),
                        KittyDeleteTarget::ByPlacement(iid, pid) => {
                            let mut image_ids =
                                store.delete_kitty_graphics_for_screen(Some(*iid), *pid, screen);
                            image_ids.insert(*iid);
                            image_ids
                        }
                        KittyDeleteTarget::ByImageNumber(number, pid) => {
                            if let Some(image_id) = store.kitty_image_id_for_number(*number) {
                                let mut image_ids = store.delete_kitty_graphics_for_screen(
                                    Some(image_id),
                                    *pid,
                                    screen,
                                );
                                image_ids.insert(image_id);
                                image_ids
                            } else {
                                Default::default()
                            }
                        }
                        KittyDeleteTarget::AnimationFrame {
                            image_id,
                            frame_number,
                        } => {
                            if store.delete_animation_frame(
                                *image_id,
                                *frame_number,
                                self.delete_image_data,
                            ) {
                                let mut image_ids = store.delete_kitty_graphics_for_screen(
                                    Some(*image_id),
                                    None,
                                    screen,
                                );
                                image_ids.insert(*image_id);
                                image_ids
                            } else {
                                Default::default()
                            }
                        }
                        KittyDeleteTarget::AtCursor => {
                            let (cursor_col, cursor_row) = position;
                            store.delete_kitty_graphics_intersecting_cell_for_screen(
                                cursor_col, cursor_row, None, screen,
                            )
                        }
                        KittyDeleteTarget::InCell { col, row, z_index } => store
                            .delete_kitty_graphics_intersecting_cell_for_screen(
                                *col, *row, *z_index, screen,
                            ),
                        KittyDeleteTarget::OnScreen => {
                            store.delete_all_kitty_graphics_for_screen(screen)
                        }
                        KittyDeleteTarget::ByColumn(col) => {
                            store.delete_kitty_graphics_in_column_for_screen(*col as usize, screen)
                        }
                        KittyDeleteTarget::ByRow(row) => {
                            store.delete_kitty_graphics_in_row_for_screen(*row as usize, screen)
                        }
                        KittyDeleteTarget::ByZIndex(z_index) => {
                            store.delete_kitty_graphics_by_z_index_for_screen(*z_index, screen)
                        }
                    }
                } else {
                    Default::default()
                };
                if self.delete_image_data {
                    store.remove_unreferenced_kitty_images(deleted_image_ids);
                }
                Ok(KittyGraphicResult::None)
            }

            KittyAction::Query => {
                if self.raw_data_limited(data_limit)?.is_empty() {
                    return Ok(KittyGraphicResult::None);
                }

                let image_data = self.load_image_data(data_limit)?;
                let _ = self.decode_pixels(&image_data)?;
                Ok(KittyGraphicResult::None)
            }

            KittyAction::Put => {
                // Display previously transmitted image or create virtual placement
                let image_id = self.existing_image_id(store).unwrap_or(0);

                // If U=1, create a virtual placement
                if self.is_virtual {
                    let cols = self.columns.unwrap_or(1) as usize;
                    let rows = self.rows.unwrap_or(1) as usize;
                    let placement_id = self.placement_id.unwrap_or(0);

                    let mut graphic =
                        if let Some((width, height, pixels)) = store.get_kitty_image(image_id) {
                            TerminalGraphic::with_shared_pixels(
                                next_graphic_id(),
                                GraphicProtocol::Kitty,
                                position,
                                width,
                                height,
                                pixels,
                            )
                        } else {
                            TerminalGraphic::new(
                                next_graphic_id(),
                                GraphicProtocol::Kitty,
                                position,
                                cols,
                                rows,
                                vec![],
                            )
                        };
                    graphic.kitty_image_id = Some(image_id);
                    graphic.kitty_placement_id = Some(placement_id);
                    graphic.is_virtual = true;
                    graphic.set_alternate_screen(alternate_screen);
                    graphic.placement = self.build_placement();
                    self.apply_relative_metadata(&mut graphic, store)?;
                    let resolved_position = graphic.position;
                    store.add_virtual_placement(graphic);

                    // Return virtual placement info for placeholder insertion
                    return Ok(KittyGraphicResult::VirtualPlacement {
                        image_id,
                        placement_id,
                        position: resolved_position,
                        cols,
                        rows,
                    });
                }

                // Regular placement
                if let Some((width, height, pixels)) = store.get_kitty_image(image_id) {
                    let mut graphic = TerminalGraphic::with_shared_pixels(
                        next_graphic_id(),
                        GraphicProtocol::Kitty,
                        position,
                        width,
                        height,
                        pixels,
                    );
                    graphic.kitty_image_id = Some(image_id);
                    graphic.kitty_placement_id = Some(self.placement_id.unwrap_or(0));
                    graphic.set_alternate_screen(alternate_screen);
                    graphic.placement = self.build_placement();
                    self.apply_relative_metadata(&mut graphic, store)?;

                    return Ok(KittyGraphicResult::Graphic(graphic));
                }
                Err(GraphicsError::KittyError("Image not found".to_string()))
            }

            KittyAction::Transmit | KittyAction::TransmitDisplay => {
                if self.raw_data_limited(data_limit)?.is_empty() {
                    return Err(GraphicsError::KittyError("No image data".to_string()));
                }

                let compressed = self.is_compressed();

                let image_data = self.load_image_data(data_limit)?;
                let (width, height, pixels) = self.decode_pixels(&image_data)?;
                let image_id = self.new_image_id(store);

                // Store for reuse if image_id is specified
                if let Some(image_id) = image_id {
                    store.store_kitty_image(image_id, width, height, pixels.clone());
                }

                // Create graphic if TransmitDisplay, or virtual placement if U=1
                if self.action == KittyAction::TransmitDisplay {
                    if self.is_virtual {
                        let cols = self.columns.unwrap_or(1) as usize;
                        let rows = self.rows.unwrap_or(1) as usize;
                        let image_id = image_id.unwrap_or(0);
                        let placement_id = self.placement_id.unwrap_or(0);

                        let mut graphic = TerminalGraphic::new(
                            next_graphic_id(),
                            GraphicProtocol::Kitty,
                            position,
                            width,
                            height,
                            pixels,
                        );
                        graphic.kitty_image_id = Some(image_id);
                        graphic.kitty_placement_id = Some(placement_id);
                        graphic.is_virtual = true;
                        graphic.was_compressed = compressed;
                        graphic.set_alternate_screen(alternate_screen);
                        graphic.placement = self.build_placement();
                        self.apply_relative_metadata(&mut graphic, store)?;
                        let resolved_position = graphic.position;
                        store.add_virtual_placement(graphic);

                        // Return virtual placement info for placeholder insertion
                        Ok(KittyGraphicResult::VirtualPlacement {
                            image_id,
                            placement_id,
                            position: resolved_position,
                            cols,
                            rows,
                        })
                    } else {
                        let mut graphic = TerminalGraphic::new(
                            next_graphic_id(),
                            GraphicProtocol::Kitty,
                            position,
                            width,
                            height,
                            pixels,
                        );
                        graphic.kitty_image_id = image_id;
                        graphic.kitty_placement_id = Some(self.placement_id.unwrap_or(0));
                        graphic.was_compressed = compressed;
                        graphic.set_alternate_screen(alternate_screen);
                        graphic.placement = self.build_placement();
                        self.apply_relative_metadata(&mut graphic, store)?;

                        Ok(KittyGraphicResult::Graphic(graphic))
                    }
                } else {
                    // Transmit only, no display
                    Ok(KittyGraphicResult::None)
                }
            }

            KittyAction::Frame => {
                // Add animation frame
                if self.raw_data_limited(data_limit)?.is_empty() {
                    return Err(GraphicsError::KittyError("No frame data".to_string()));
                }

                let compressed = self.is_compressed();

                let image_id = self.existing_image_id(store).ok_or_else(|| {
                    GraphicsError::KittyError("Frame requires image ID".to_string())
                })?;

                let image_data = self.load_image_data(data_limit)?;
                let (width, height, pixels) = self.decode_pixels(&image_data)?;

                // Create frame
                let frame_num = self.frame_number.unwrap_or(1);
                let mut frame = AnimationFrame::new(frame_num, pixels.clone(), width, height);

                if let Some(gap_ms) = self.frame_delay_ms {
                    frame = frame.with_gap(gap_ms);
                }

                if self.x_offset.is_some() || self.y_offset.is_some() {
                    frame =
                        frame.with_offset(self.x_offset.unwrap_or(0), self.y_offset.unwrap_or(0));
                }

                if let Some(comp) = self.frame_composition {
                    frame = frame.with_composition(comp);
                }

                let frame = if let Some(base_frame_number) = self.frame_base_frame {
                    store
                        .composed_animation_frame_from_base(image_id, base_frame_number, &frame)
                        .ok_or_else(|| {
                            GraphicsError::KittyError("Frame base composition failed".to_string())
                        })?
                } else {
                    frame
                };
                let display_width = frame.width;
                let display_height = frame.height;
                let display_pixels = frame.pixels.as_ref().clone();

                // Add frame to animation
                store.add_animation_frame(image_id, frame);

                // Frame 1 creates both animation entry AND a placement for display
                if frame_num == 1 {
                    // Store as shared image so it can be referenced by Put commands
                    store.store_kitty_image(
                        image_id,
                        display_width,
                        display_height,
                        display_pixels.clone(),
                    );

                    // Create placement to display the animation
                    let mut graphic = TerminalGraphic::new(
                        next_graphic_id(),
                        GraphicProtocol::Kitty,
                        position,
                        display_width,
                        display_height,
                        display_pixels,
                    );
                    graphic.kitty_image_id = Some(image_id);
                    graphic.kitty_placement_id = Some(self.placement_id.unwrap_or(0));
                    graphic.was_compressed = compressed;
                    graphic.set_alternate_screen(alternate_screen);
                    graphic.placement = self.build_placement();
                    self.apply_relative_metadata(&mut graphic, store)?;

                    return Ok(KittyGraphicResult::Graphic(graphic));
                }

                // Subsequent frames only add to animation, don't create new placements
                Ok(KittyGraphicResult::None)
            }

            KittyAction::Compose => {
                let image_id = self.existing_image_id(store).ok_or_else(|| {
                    GraphicsError::KittyError("Compose requires image ID".to_string())
                })?;
                let source_frame = self.frame_number.ok_or_else(|| {
                    GraphicsError::KittyError("Compose requires source frame".to_string())
                })?;
                let destination_frame = self.compose_destination_frame.ok_or_else(|| {
                    GraphicsError::KittyError("Compose requires destination frame".to_string())
                })?;
                let composition = self.frame_composition.unwrap_or_default();
                // Kitty compose uses x/y for the source rectangle and X/Y for the destination.
                if store.compose_animation_frame(
                    image_id,
                    source_frame,
                    destination_frame,
                    self.x_offset.unwrap_or(0),
                    self.y_offset.unwrap_or(0),
                    self.source_width,
                    self.source_height,
                    self.cell_x_offset.unwrap_or(0),
                    self.cell_y_offset.unwrap_or(0),
                    composition,
                ) {
                    Ok(KittyGraphicResult::None)
                } else {
                    Err(GraphicsError::KittyError(
                        "Animation frame compose failed".to_string(),
                    ))
                }
            }

            KittyAction::AnimationControl => {
                // Control animation playback
                let image_id = self.existing_image_id(store).ok_or_else(|| {
                    GraphicsError::KittyError("Animation control requires image ID".to_string())
                })?;

                // Handle num_plays (v= parameter) for setting loop count
                // Per Kitty spec: v=0 ignored, v=1 infinite, v=N means play N times total
                // We store loop_count as (N-1) so animation stops after (N-1) additional loops
                if let Some(num_plays) = self.num_plays {
                    if num_plays > 0 {
                        let loop_count = if num_plays == 1 {
                            0 // v=1 means infinite looping
                        } else {
                            num_plays - 1 // Store N-1 to get N total plays
                        };
                        debug_info!(
                            "KITTY",
                            "Setting loop count for image_id={}: num_plays={}, loop_count={}",
                            image_id,
                            num_plays,
                            loop_count
                        );
                        store.set_animation_loops(image_id, loop_count);
                    }
                }

                if let Some(frame_number) = self.animation_current_frame {
                    if !store.set_animation_current_frame(image_id, frame_number) {
                        return Err(GraphicsError::KittyError(format!(
                            "Animation frame {frame_number} not found"
                        )));
                    }
                }

                if let (Some(frame_number), Some(delay_ms)) =
                    (self.frame_number, self.frame_delay_ms)
                {
                    if !store.set_animation_frame_gap(image_id, frame_number, delay_ms) {
                        return Err(GraphicsError::KittyError(format!(
                            "Animation frame {frame_number} not found"
                        )));
                    }
                }

                // Handle state control (s= parameter)
                if let Some(control) = self.animation_control {
                    debug_info!(
                        "KITTY",
                        "Applying animation control: image_id={}, control={:?}",
                        image_id,
                        control
                    );
                    store.control_animation(image_id, control);
                } else {
                    debug_log!(
                        "KITTY",
                        "Animation control command received but no control parsed (image_id={})",
                        image_id
                    );
                }

                Ok(KittyGraphicResult::None)
            }
        }
    }

    fn load_image_data(&self, max_bytes: usize) -> Result<Vec<u8>, GraphicsError> {
        let raw_data = self.raw_data_limited(max_bytes)?;
        let data = match self.medium {
            KittyMedium::Direct => raw_data,
            KittyMedium::File | KittyMedium::TempFile => {
                self.load_file_data(&raw_data, max_bytes)?
            }
            KittyMedium::SharedMem => self.load_shared_memory_data(&raw_data, max_bytes)?,
        };
        if self.compression == KittyCompression::Zlib {
            Self::decompress_zlib_limited(&data, max_bytes)
        } else {
            Ok(data)
        }
    }

    /// Load image data from file path with security validation.
    fn load_file_data(&self, path_data: &[u8], max_bytes: usize) -> Result<Vec<u8>, GraphicsError> {
        // Decode path from UTF-8 bytes (NOT base64-encoded for file transmission)
        let path_str = String::from_utf8(path_data.to_vec())
            .map_err(|e| GraphicsError::KittyError(format!("Invalid UTF-8 in file path: {}", e)))?;

        let path = Path::new(&path_str);

        // Security validations

        // 1. Check for directory traversal attacks
        if path_str.contains("..") {
            return Err(GraphicsError::KittyError(
                "Directory traversal not allowed".to_string(),
            ));
        }

        // 2. Validate file exists and is readable
        if !path.exists() {
            return Err(GraphicsError::KittyError(format!(
                "File not found: {}",
                path_str
            )));
        }

        if !path.is_file() {
            return Err(GraphicsError::KittyError(format!(
                "Path is not a file: {}",
                path_str
            )));
        }

        // 3. Check requested read range (limit to 100MB for safety)
        const MAX_FILE_SIZE: u64 = 100 * 1024 * 1024; // 100MB
        let max_read_size = MAX_FILE_SIZE.min(max_bytes as u64);
        let metadata = fs::metadata(path)
            .map_err(|e| GraphicsError::KittyError(format!("Cannot read file metadata: {}", e)))?;

        let file_len = metadata.len();
        let offset = self.file_read_offset.unwrap_or(0);
        if offset > file_len {
            return Err(GraphicsError::KittyError(format!(
                "File offset beyond end of file: {} > {}",
                offset, file_len
            )));
        }

        let available_len = file_len.saturating_sub(offset);
        let read_len = self
            .file_read_size
            .unwrap_or(available_len)
            .min(available_len);
        if read_len > max_read_size {
            return Err(GraphicsError::KittyError(format!(
                "Requested file range too large: {} bytes (max {})",
                read_len, max_read_size
            )));
        }

        // 4. Read file range
        let mut file = fs::File::open(path)
            .map_err(|e| GraphicsError::KittyError(format!("Cannot read file: {}", e)))?;
        if offset > 0 {
            file.seek(SeekFrom::Start(offset))
                .map_err(|e| GraphicsError::KittyError(format!("Cannot seek file: {}", e)))?;
        }
        let mut file_data = Vec::with_capacity(read_len as usize);
        file.take(read_len)
            .read_to_end(&mut file_data)
            .map_err(|e| GraphicsError::KittyError(format!("Cannot read file: {}", e)))?;

        // Delete temp file if requested
        if self.medium == KittyMedium::TempFile && should_delete_temp_kitty_file(path) {
            let _ = fs::remove_file(path); // Ignore errors on cleanup
        }

        Ok(file_data)
    }

    #[cfg(unix)]
    fn load_shared_memory_data(
        &self,
        name_data: &[u8],
        max_bytes: usize,
    ) -> Result<Vec<u8>, GraphicsError> {
        use std::mem::MaybeUninit;
        use std::{ffi::CString, ptr, slice};

        let name = String::from_utf8(name_data.to_vec()).map_err(|e| {
            GraphicsError::KittyError(format!("Invalid UTF-8 in shared memory name: {}", e))
        })?;
        if name.is_empty() || !name.starts_with('/') {
            return Err(GraphicsError::KittyError(
                "Shared memory name must start with '/'".to_string(),
            ));
        }
        if name[1..].contains('/') || name.contains("..") {
            return Err(GraphicsError::KittyError(
                "Invalid shared memory object name".to_string(),
            ));
        }

        let c_name = CString::new(name.as_bytes()).map_err(|_| {
            GraphicsError::KittyError("Shared memory name contains NUL byte".to_string())
        })?;
        let fd = unsafe { libc::shm_open(c_name.as_ptr(), libc::O_RDONLY, 0) };
        if fd < 0 {
            return Err(GraphicsError::KittyError(format!(
                "Cannot open shared memory object: {}",
                std::io::Error::last_os_error()
            )));
        }

        let mut stat = MaybeUninit::<libc::stat>::uninit();
        let fstat_result = unsafe { libc::fstat(fd, stat.as_mut_ptr()) };
        let _ = unsafe { libc::shm_unlink(c_name.as_ptr()) };
        if fstat_result != 0 {
            let error = std::io::Error::last_os_error();
            let _ = unsafe { libc::close(fd) };
            return Err(GraphicsError::KittyError(format!(
                "Cannot read shared memory metadata: {}",
                error
            )));
        }

        let stat = unsafe { stat.assume_init() };
        if stat.st_size < 0 {
            let _ = unsafe { libc::close(fd) };
            return Err(GraphicsError::KittyError(
                "Invalid shared memory object size".to_string(),
            ));
        }

        let object_len = stat.st_size as u64;
        let offset = self.file_read_offset.unwrap_or(0);
        if offset > object_len {
            let _ = unsafe { libc::close(fd) };
            return Err(GraphicsError::KittyError(format!(
                "Shared memory offset beyond end of object: {} > {}",
                offset, object_len
            )));
        }

        let available_len = object_len.saturating_sub(offset);
        let read_len = self
            .file_read_size
            .unwrap_or(available_len)
            .min(available_len);
        if read_len > max_bytes as u64 {
            let _ = unsafe { libc::close(fd) };
            return Err(GraphicsError::KittyError(format!(
                "Requested shared memory range too large: {} bytes (max {})",
                read_len, max_bytes
            )));
        }

        if read_len == 0 {
            let _ = unsafe { libc::close(fd) };
            return Ok(Vec::new());
        }

        let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
        let page_size = if page_size > 0 {
            page_size as u64
        } else {
            4096
        };
        let map_offset = (offset / page_size) * page_size;
        let map_delta = offset.saturating_sub(map_offset);
        let map_len = read_len.checked_add(map_delta).ok_or_else(|| {
            let _ = unsafe { libc::close(fd) };
            GraphicsError::KittyError("Shared memory map range overflow".to_string())
        })?;
        let map_len = usize::try_from(map_len).map_err(|_| {
            let _ = unsafe { libc::close(fd) };
            GraphicsError::KittyError("Shared memory map range too large".to_string())
        })?;
        let ptr = unsafe {
            libc::mmap(
                ptr::null_mut(),
                map_len,
                libc::PROT_READ,
                libc::MAP_SHARED,
                fd,
                map_offset as libc::off_t,
            )
        };
        let _ = unsafe { libc::close(fd) };
        if ptr == libc::MAP_FAILED {
            return Err(GraphicsError::KittyError(format!(
                "Cannot map shared memory object: {}",
                std::io::Error::last_os_error()
            )));
        }

        let data = unsafe {
            let start = (ptr as *const u8).add(map_delta as usize);
            let bytes = slice::from_raw_parts(start, read_len as usize).to_vec();
            let _ = libc::munmap(ptr, map_len);
            bytes
        };
        Ok(data)
    }

    #[cfg(not(unix))]
    fn load_shared_memory_data(
        &self,
        _name_data: &[u8],
        _max_bytes: usize,
    ) -> Result<Vec<u8>, GraphicsError> {
        Err(GraphicsError::KittyError(
            "Shared memory transmission is not supported on this platform".to_string(),
        ))
    }

    /// Decode pixels based on format
    fn decode_pixels(&self, data: &[u8]) -> Result<(usize, usize, Vec<u8>), GraphicsError> {
        match self.format {
            KittyFormat::Png => {
                // Decode PNG
                let img = image::load_from_memory(data)
                    .map_err(|e| GraphicsError::ImageError(e.to_string()))?;
                let rgba = img.to_rgba8();
                let width = rgba.width() as usize;
                let height = rgba.height() as usize;
                Ok((width, height, rgba.into_raw()))
            }

            KittyFormat::Rgba => {
                // Raw RGBA data
                let width = self.width.ok_or_else(|| {
                    GraphicsError::KittyError("Width required for raw format".to_string())
                })? as usize;
                let height = self.height.ok_or_else(|| {
                    GraphicsError::KittyError("Height required for raw format".to_string())
                })? as usize;

                if data.len() != width * height * 4 {
                    return Err(GraphicsError::KittyError(format!(
                        "Data size mismatch: got {}, expected {}",
                        data.len(),
                        width * height * 4
                    )));
                }
                Ok((width, height, data.to_vec()))
            }

            KittyFormat::Rgb => {
                // Raw RGB data - convert to RGBA
                let width = self.width.ok_or_else(|| {
                    GraphicsError::KittyError("Width required for raw format".to_string())
                })? as usize;
                let height = self.height.ok_or_else(|| {
                    GraphicsError::KittyError("Height required for raw format".to_string())
                })? as usize;

                if data.len() != width * height * 3 {
                    return Err(GraphicsError::KittyError(format!(
                        "Data size mismatch: got {}, expected {}",
                        data.len(),
                        width * height * 3
                    )));
                }

                // Convert RGB to RGBA
                let mut rgba = Vec::with_capacity(width * height * 4);
                for chunk in data.chunks(3) {
                    rgba.push(chunk[0]);
                    rgba.push(chunk[1]);
                    rgba.push(chunk[2]);
                    rgba.push(255); // Alpha
                }
                Ok((width, height, rgba))
            }
        }
    }
}

fn should_delete_temp_kitty_file(path: &Path) -> bool {
    const TEMP_FILE_MARKER: &str = "tty-graphics-protocol";

    let Ok(canonical_path) = fs::canonicalize(path) else {
        return false;
    };
    if !canonical_path.to_string_lossy().contains(TEMP_FILE_MARKER) {
        return false;
    }

    let mut temp_roots = vec![std::env::temp_dir()];
    if let Some(tmpdir) = std::env::var_os("TMPDIR") {
        temp_roots.push(PathBuf::from(tmpdir));
    }

    temp_roots.into_iter().any(|root| {
        fs::canonicalize(root)
            .ok()
            .is_some_and(|canonical_root| canonical_path.starts_with(canonical_root))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graphics::GraphicsLimits;

    #[test]
    fn test_kitty_action_from_char() {
        assert_eq!(KittyAction::from_char('t'), Some(KittyAction::Transmit));
        assert_eq!(
            KittyAction::from_char('T'),
            Some(KittyAction::TransmitDisplay)
        );
        assert_eq!(KittyAction::from_char('q'), Some(KittyAction::Query));
        assert_eq!(KittyAction::from_char('p'), Some(KittyAction::Put));
        assert_eq!(KittyAction::from_char('d'), Some(KittyAction::Delete));
        assert_eq!(KittyAction::from_char('c'), Some(KittyAction::Compose));
        assert_eq!(KittyAction::from_char('x'), None);
    }

    #[test]
    fn test_kitty_format_from_code() {
        assert_eq!(KittyFormat::from_code(24), Some(KittyFormat::Rgb));
        assert_eq!(KittyFormat::from_code(32), Some(KittyFormat::Rgba));
        assert_eq!(KittyFormat::from_code(100), Some(KittyFormat::Png));
        assert_eq!(KittyFormat::from_code(0), None);
    }

    #[test]
    fn test_kitty_parser_basic() {
        let mut parser = KittyParser::new();
        let result = parser.parse_chunk("a=T,f=100,i=1;");
        assert!(result.is_ok());
        assert_eq!(parser.action, KittyAction::TransmitDisplay);
        assert_eq!(parser.format, KittyFormat::Png);
        assert_eq!(parser.image_id, Some(1));
    }

    #[test]
    fn test_kitty_cursor_movement_parameter() {
        let mut default = KittyParser::new();
        default.parse_chunk("a=T,f=32,c=2,r=2;").unwrap();
        assert!(default.should_move_cursor_after_display());

        let mut suppressed = KittyParser::new();
        suppressed.parse_chunk("a=T,f=32,c=2,r=2,C=1;").unwrap();
        assert!(suppressed.suppress_cursor_movement);
        assert!(!suppressed.should_move_cursor_after_display());

        let mut relative = KittyParser::new();
        relative.parse_chunk("a=p,i=1,P=1,C=0;").unwrap();
        assert!(!relative.should_move_cursor_after_display());

        let mut virtual_placement = KittyParser::new();
        virtual_placement.parse_chunk("a=T,U=1,C=0;").unwrap();
        assert!(!virtual_placement.should_move_cursor_after_display());
    }

    #[test]
    fn test_kitty_parser_chunked() {
        let mut parser = KittyParser::new();

        // First chunk
        let result = parser.parse_chunk("a=T,f=100,m=1;AAAA");
        assert!(result.is_ok());
        assert!(result.unwrap()); // more_chunks = true

        // Final chunk
        let result = parser.parse_chunk("m=0;BBBB");
        assert!(result.is_ok());
        assert!(!result.unwrap()); // more_chunks = false
    }

    #[test]
    fn test_kitty_medium_from_char() {
        assert_eq!(KittyMedium::from_char('d'), Some(KittyMedium::Direct));
        assert_eq!(KittyMedium::from_char('f'), Some(KittyMedium::File));
        assert_eq!(KittyMedium::from_char('t'), Some(KittyMedium::TempFile));
        assert_eq!(KittyMedium::from_char('s'), Some(KittyMedium::SharedMem));
        assert_eq!(KittyMedium::from_char('x'), None);
    }

    #[test]
    fn test_kitty_file_transmission() {
        use std::io::Write;
        use tempfile::NamedTempFile;

        // Create a valid 1x1 red PNG using the image crate
        let img = image::RgbaImage::from_pixel(1, 1, image::Rgba([255, 0, 0, 255]));
        let mut png_data = Vec::new();
        img.write_to(
            &mut std::io::Cursor::new(&mut png_data),
            image::ImageFormat::Png,
        )
        .expect("Failed to encode PNG");

        // Write to temp file
        let mut temp_file = NamedTempFile::new().expect("Failed to create temp file");
        temp_file
            .write_all(&png_data)
            .expect("Failed to write PNG data");
        let file_path = temp_file.path().to_str().unwrap();

        // Create parser and parse file transmission command
        // Note: file path must be base64-encoded in the protocol (without padding to match Kitty)
        let file_path_b64 =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD_NO_PAD, file_path);
        let mut parser = KittyParser::new();
        let payload = format!("a=T,f=100,t=f;{}", file_path_b64);
        let result = parser.parse_chunk(&payload);

        assert!(result.is_ok());
        assert_eq!(parser.action, KittyAction::TransmitDisplay);
        assert_eq!(parser.format, KittyFormat::Png);
        assert_eq!(parser.medium, KittyMedium::File);

        // Test file loading
        let data = parser.get_data();
        assert!(!data.is_empty());
        assert_eq!(data, file_path.as_bytes());

        // Load file data
        let file_data = parser.load_file_data(&data, usize::MAX);
        assert!(file_data.is_ok());
        let file_data = file_data.unwrap();
        assert_eq!(file_data.len(), png_data.len());

        // Decode pixels
        let decode_result = parser.decode_pixels(&file_data);
        assert!(
            decode_result.is_ok(),
            "Failed to decode: {:?}",
            decode_result.err()
        );
        let (width, height, pixels) = decode_result.unwrap();
        assert_eq!(width, 1);
        assert_eq!(height, 1);
        assert_eq!(pixels.len(), 4); // RGBA
                                     // Verify it's red
        assert_eq!(pixels[0], 255); // R
        assert_eq!(pixels[1], 0); // G
        assert_eq!(pixels[2], 0); // B
        assert_eq!(pixels[3], 255); // A
    }

    #[test]
    fn test_kitty_file_transmission_decompresses_file_contents_not_path() {
        use flate2::write::ZlibEncoder;
        use flate2::Compression;
        use std::io::Write;
        use tempfile::NamedTempFile;

        let pixel_data = vec![255, 0, 0, 255];
        let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&pixel_data).unwrap();
        let compressed = encoder.finish().unwrap();

        let mut temp_file = NamedTempFile::new().expect("Failed to create temp file");
        temp_file
            .write_all(&compressed)
            .expect("Failed to write compressed image data");
        let file_path = temp_file.path().to_str().unwrap();
        let file_path_b64 =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD_NO_PAD, file_path);

        let mut parser = KittyParser::new();
        let payload = format!("a=T,f=32,t=f,o=z,s=1,v=1;{file_path_b64}");
        parser.parse_chunk(&payload).unwrap();

        let image_data = parser.load_image_data(1024).unwrap();
        assert_eq!(
            image_data, pixel_data,
            "o=z for file transfers must decompress the file contents, not the base64 path"
        );

        let (width, height, pixels) = parser.decode_pixels(&image_data).unwrap();
        assert_eq!((width, height), (1, 1));
        assert_eq!(pixels, pixel_data);
    }

    #[test]
    fn test_kitty_file_security_directory_traversal() {
        let mut parser = KittyParser::new();
        parser.medium = KittyMedium::File;

        // Test directory traversal attempt
        let malicious_path = b"../../../etc/passwd";
        let result = parser.load_file_data(malicious_path, usize::MAX);
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("Directory traversal"));
    }

    #[test]
    fn test_kitty_file_security_nonexistent() {
        let mut parser = KittyParser::new();
        parser.medium = KittyMedium::File;

        // Test nonexistent file
        let nonexistent_path = b"/this/file/does/not/exist.png";
        let result = parser.load_file_data(nonexistent_path, usize::MAX);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("File not found"));
    }

    #[test]
    fn test_kitty_compression_from_char() {
        assert_eq!(
            KittyCompression::from_char('z'),
            Some(KittyCompression::Zlib)
        );
        assert_eq!(KittyCompression::from_char('x'), None);
    }

    #[test]
    fn test_kitty_compression_default() {
        let parser = KittyParser::new();
        assert_eq!(parser.compression, KittyCompression::None);
        assert!(!parser.is_compressed());
    }

    #[test]
    fn test_kitty_parse_compression_param() {
        let mut parser = KittyParser::new();
        let result = parser.parse_chunk("a=T,f=32,o=z,s=2,v=2;");
        assert!(result.is_ok());
        assert_eq!(parser.compression, KittyCompression::Zlib);
        assert!(parser.is_compressed());
    }

    #[test]
    fn test_kitty_zlib_decompression() {
        use flate2::write::ZlibEncoder;
        use flate2::Compression;
        use std::io::Write;

        // Create a 2x2 RGBA image (16 bytes)
        let pixel_data: Vec<u8> = vec![
            255, 0, 0, 255, // Red
            0, 255, 0, 255, // Green
            0, 0, 255, 255, // Blue
            255, 255, 0, 255, // Yellow
        ];

        // Compress with zlib
        let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&pixel_data).unwrap();
        let compressed = encoder.finish().unwrap();

        // Base64 encode the compressed data
        let b64_compressed =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &compressed);

        // Parse with o=z compression flag
        let mut parser = KittyParser::new();
        let payload = format!("a=T,f=32,o=z,s=2,v=2;{}", b64_compressed);
        let result = parser.parse_chunk(&payload);
        assert!(result.is_ok());
        assert_eq!(parser.compression, KittyCompression::Zlib);

        // get_data() should return decompressed data
        let data = parser.get_data();
        assert_eq!(data, pixel_data);
    }

    #[test]
    fn test_kitty_parse_chunk_rejects_data_over_limit() {
        let pixel_data = vec![255u8; 8];
        let b64_data =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &pixel_data);
        let mut parser = KittyParser::new();
        parser.set_max_data_bytes(4);

        let result = parser.parse_chunk(&format!("a=T,f=32,s=2,v=1;{b64_data}"));

        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("byte limit"));
    }

    #[test]
    fn test_kitty_action_dependent_params_are_order_independent() {
        let mut control = KittyParser::new();
        control.parse_chunk("s=2,v=3,i=42,a=a;").unwrap();

        assert_eq!(control.action, KittyAction::AnimationControl);
        assert_eq!(
            control.animation_control,
            Some(AnimationControl::LoadingMode)
        );
        assert_eq!(control.num_plays, Some(3));
        assert_eq!(control.width, None);
        assert_eq!(control.height, None);

        let mut frame = KittyParser::new();
        frame.parse_chunk("r=7,X=1,z=50,a=f;").unwrap();

        assert_eq!(frame.action, KittyAction::Frame);
        assert_eq!(frame.frame_number, Some(7));
        assert_eq!(frame.frame_composition, Some(CompositionMode::Overwrite));
        assert_eq!(frame.frame_base_frame, None);
        assert_eq!(frame.frame_delay_ms, Some(50));
        assert_eq!(frame.columns, None);
        assert_eq!(frame.rows, None);
        assert_eq!(frame.z_index, None);

        let mut composed_frame = KittyParser::new();
        composed_frame.parse_chunk("a=f,i=42,r=7,c=4,X=1;").unwrap();
        assert_eq!(composed_frame.action, KittyAction::Frame);
        assert_eq!(composed_frame.frame_number, Some(7));
        assert_eq!(composed_frame.frame_base_frame, Some(4));
        assert_eq!(
            composed_frame.frame_composition,
            Some(CompositionMode::Overwrite)
        );
        assert_eq!(composed_frame.columns, None);
        assert_eq!(composed_frame.rows, None);

        let mut animation_control = KittyParser::new();
        animation_control
            .parse_chunk("a=a,i=42,c=2,r=3,z=75;")
            .unwrap();

        assert_eq!(animation_control.action, KittyAction::AnimationControl);
        assert_eq!(animation_control.animation_current_frame, Some(2));
        assert_eq!(animation_control.frame_number, Some(3));
        assert_eq!(animation_control.frame_delay_ms, Some(75));
        assert_eq!(animation_control.columns, None);
        assert_eq!(animation_control.rows, None);
        assert_eq!(animation_control.z_index, None);

        let mut compose = KittyParser::new();
        compose
            .parse_chunk("a=c,i=42,r=1,c=2,x=3,y=4,w=5,h=6,X=7,Y=8,C=1;")
            .unwrap();

        assert_eq!(compose.action, KittyAction::Compose);
        assert_eq!(compose.frame_number, Some(1));
        assert_eq!(compose.compose_destination_frame, Some(2));
        assert_eq!(compose.x_offset, Some(3));
        assert_eq!(compose.y_offset, Some(4));
        assert_eq!(compose.source_width, Some(5));
        assert_eq!(compose.source_height, Some(6));
        assert_eq!(compose.cell_x_offset, Some(7));
        assert_eq!(compose.cell_y_offset, Some(8));
        assert_eq!(compose.frame_composition, Some(CompositionMode::Overwrite));
        assert_eq!(compose.columns, None);
        assert_eq!(compose.rows, None);
    }

    #[test]
    fn test_kitty_zlib_decompression_rejects_output_over_limit() {
        use flate2::write::ZlibEncoder;
        use flate2::Compression;
        use std::io::Write;

        let pixel_data = vec![255u8; 16];
        let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&pixel_data).unwrap();
        let compressed = encoder.finish().unwrap();
        let b64_compressed =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &compressed);
        let mut parser = KittyParser::new();
        let payload = format!("a=T,f=32,o=z,s=2,v=2;{b64_compressed}");
        parser.parse_chunk(&payload).unwrap();

        let mut store = GraphicsStore::with_limits(GraphicsLimits {
            max_image_bytes: 8,
            max_total_memory: 8,
            ..GraphicsLimits::default()
        });
        let result = parser.build_graphic((0, 0), &mut store);

        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("byte limit"));
    }

    #[test]
    fn test_kitty_zlib_build_graphic() {
        use flate2::write::ZlibEncoder;
        use flate2::Compression;
        use std::io::Write;

        // Create a 2x2 RGBA image (16 bytes)
        let pixel_data: Vec<u8> = vec![
            255, 0, 0, 255, // Red
            0, 255, 0, 255, // Green
            0, 0, 255, 255, // Blue
            255, 255, 0, 255, // Yellow
        ];

        // Compress with zlib
        let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&pixel_data).unwrap();
        let compressed = encoder.finish().unwrap();

        // Base64 encode
        let b64_compressed =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &compressed);

        // Parse and build graphic
        let mut parser = KittyParser::new();
        let payload = format!("a=T,f=32,o=z,s=2,v=2,i=42;{}", b64_compressed);
        parser.parse_chunk(&payload).unwrap();

        let mut store = GraphicsStore::new();
        let result = parser.build_graphic((0, 0), &mut store);
        assert!(result.is_ok());

        // Transmit-only, no display - should store the image
        let stored = store.get_kitty_image(42);
        assert!(stored.is_some());
        let (w, h, pixels) = stored.unwrap();
        assert_eq!(w, 2);
        assert_eq!(h, 2);
        assert_eq!(*pixels, pixel_data);
    }

    #[test]
    fn test_kitty_zlib_transmit_display_sets_compressed_flag() {
        use flate2::write::ZlibEncoder;
        use flate2::Compression;
        use std::io::Write;

        // Create a 2x2 RGBA image (16 bytes)
        let pixel_data: Vec<u8> = vec![
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255,
        ];

        // Compress with zlib
        let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&pixel_data).unwrap();
        let compressed = encoder.finish().unwrap();

        let b64_compressed =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &compressed);

        // TransmitDisplay with compression
        let mut parser = KittyParser::new();
        let payload = format!("a=T,f=32,o=z,s=2,v=2;{}", b64_compressed);
        parser.parse_chunk(&payload).unwrap();

        let mut store = GraphicsStore::new();
        let result = parser.build_graphic((5, 10), &mut store).unwrap();

        match result {
            KittyGraphicResult::Graphic(graphic) => {
                assert!(graphic.was_compressed, "was_compressed should be true");
                assert_eq!(graphic.width, 2);
                assert_eq!(graphic.height, 2);
                assert_eq!(*graphic.pixels, pixel_data);
            }
            _ => panic!("Expected Graphic result"),
        }
    }

    #[test]
    fn test_kitty_no_compression_flag_unset() {
        // Uncompressed RGBA data for a 2x2 image
        let pixel_data: Vec<u8> = vec![
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255,
        ];

        let b64_data =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &pixel_data);

        let mut parser = KittyParser::new();
        let payload = format!("a=T,f=32,s=2,v=2;{}", b64_data);
        parser.parse_chunk(&payload).unwrap();

        let mut store = GraphicsStore::new();
        let result = parser.build_graphic((0, 0), &mut store).unwrap();

        match result {
            KittyGraphicResult::Graphic(graphic) => {
                assert!(!graphic.was_compressed, "was_compressed should be false");
            }
            _ => panic!("Expected Graphic result"),
        }
    }

    #[test]
    fn test_kitty_zlib_chunked_transfer() {
        use flate2::write::ZlibEncoder;
        use flate2::Compression;
        use std::io::Write;

        // Create a 2x2 RGBA image (16 bytes)
        let pixel_data: Vec<u8> = vec![
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255,
        ];

        // Compress with zlib
        let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&pixel_data).unwrap();
        let compressed = encoder.finish().unwrap();

        let b64_compressed =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &compressed);

        // Split base64 into two chunks at a 4-byte boundary (base64 block size)
        let mid = (b64_compressed.len() / 2) & !3; // Round down to nearest multiple of 4
        let chunk1 = &b64_compressed[..mid];
        let chunk2 = &b64_compressed[mid..];

        // First chunk
        let mut parser = KittyParser::new();
        let payload1 = format!("a=T,f=32,o=z,s=2,v=2,m=1;{}", chunk1);
        let more = parser.parse_chunk(&payload1).unwrap();
        assert!(more);
        assert_eq!(parser.compression, KittyCompression::Zlib);

        // Second chunk
        let payload2 = format!("m=0;{}", chunk2);
        let more = parser.parse_chunk(&payload2).unwrap();
        assert!(!more);

        // Data should be decompressed correctly
        let data = parser.get_data();
        assert_eq!(data, pixel_data);
    }

    #[test]
    fn test_kitty_decompress_zlib_invalid_data() {
        // Test decompression with invalid zlib data falls back gracefully
        let invalid_data = vec![0x00, 0x01, 0x02, 0x03];
        let result = KittyParser::decompress_zlib(&invalid_data);
        assert!(result.is_err());
    }

    #[test]
    fn test_kitty_build_placement_defaults() {
        let parser = KittyParser::new();
        let placement = parser.build_placement();
        assert_eq!(
            placement.display_mode,
            crate::graphics::ImageDisplayMode::Inline
        );
        assert!(placement.preserve_aspect_ratio);
        assert!(placement.columns.is_none());
        assert!(placement.rows.is_none());
        assert_eq!(placement.z_index, 0);
        assert_eq!(placement.x_offset, 0);
        assert_eq!(placement.y_offset, 0);
        assert_eq!(placement.source_x_offset, 0);
        assert_eq!(placement.source_y_offset, 0);
        assert_eq!(placement.source_width, None);
        assert_eq!(placement.source_height, None);
    }

    #[test]
    fn test_kitty_build_placement_with_columns_rows() {
        let mut parser = KittyParser::new();
        parser.parse_chunk("a=T,f=100,c=10,r=5;").unwrap();
        let placement = parser.build_placement();
        assert_eq!(placement.columns, Some(10));
        assert_eq!(placement.rows, Some(5));
        assert_eq!(placement.requested_width.value, 10.0);
        assert_eq!(
            placement.requested_width.unit,
            crate::graphics::ImageSizeUnit::Cells
        );
        assert_eq!(placement.requested_height.value, 5.0);
        assert_eq!(
            placement.requested_height.unit,
            crate::graphics::ImageSizeUnit::Cells
        );
    }

    #[test]
    fn test_kitty_build_placement_with_offsets() {
        let mut parser = KittyParser::new();
        parser.parse_chunk("a=T,f=100,X=5,Y=3;").unwrap();
        let placement = parser.build_placement();
        assert_eq!(placement.x_offset, 5);
        assert_eq!(placement.y_offset, 3);
    }

    #[test]
    fn test_kitty_build_placement_with_source_rect() {
        let mut parser = KittyParser::new();
        parser.parse_chunk("a=T,f=100,x=5,y=3,w=9,h=7;").unwrap();
        let placement = parser.build_placement();
        assert_eq!(placement.source_x_offset, 5);
        assert_eq!(placement.source_y_offset, 3);
        assert_eq!(placement.source_width, Some(9));
        assert_eq!(placement.source_height, Some(7));
        assert_eq!(placement.x_offset, 0);
        assert_eq!(placement.y_offset, 0);
    }

    #[test]
    fn test_kitty_delete_cell_coordinates_are_one_based() {
        let mut parser = KittyParser::new();
        parser.parse_chunk("a=d,d=p,x=1,y=2;").unwrap();
        assert_eq!(
            parser.delete_target,
            Some(KittyDeleteTarget::InCell {
                col: 0,
                row: 1,
                z_index: None,
            })
        );

        let mut parser = KittyParser::new();
        parser.parse_chunk("a=d,d=q,x=3,y=4,z=-2;").unwrap();
        assert_eq!(
            parser.delete_target,
            Some(KittyDeleteTarget::InCell {
                col: 2,
                row: 3,
                z_index: Some(-2),
            })
        );

        let mut parser = KittyParser::new();
        parser.parse_chunk("a=d,d=x,x=1;").unwrap();
        assert_eq!(parser.delete_target, Some(KittyDeleteTarget::ByColumn(0)));

        let mut parser = KittyParser::new();
        parser.parse_chunk("a=d,d=y,y=1;").unwrap();
        assert_eq!(parser.delete_target, Some(KittyDeleteTarget::ByRow(0)));
    }

    #[test]
    fn test_kitty_delete_animation_frame_parses_frame_number() {
        let mut parser = KittyParser::new();
        parser.parse_chunk("a=d,d=f,i=42,r=2;").unwrap();
        assert!(!parser.delete_image_data);
        assert_eq!(
            parser.delete_target,
            Some(KittyDeleteTarget::AnimationFrame {
                image_id: 42,
                frame_number: Some(2),
            })
        );

        let mut uppercase = KittyParser::new();
        uppercase.parse_chunk("a=d,d=F,i=42;").unwrap();
        assert!(uppercase.delete_image_data);
        assert_eq!(
            uppercase.delete_target,
            Some(KittyDeleteTarget::AnimationFrame {
                image_id: 42,
                frame_number: None,
            })
        );
    }

    #[test]
    fn test_kitty_delete_uppercase_requests_image_data_release() {
        let mut lowercase = KittyParser::new();
        lowercase.parse_chunk("a=d,d=i,i=42;").unwrap();
        assert!(!lowercase.delete_image_data);
        assert_eq!(lowercase.delete_target, Some(KittyDeleteTarget::ById(42)));

        let mut uppercase = KittyParser::new();
        uppercase.parse_chunk("a=d,d=I,i=42;").unwrap();
        assert!(uppercase.delete_image_data);
        assert_eq!(uppercase.delete_target, Some(KittyDeleteTarget::ById(42)));

        let mut placement = KittyParser::new();
        placement.parse_chunk("a=d,d=I,i=42,p=7;").unwrap();
        assert!(placement.delete_image_data);
        assert_eq!(
            placement.delete_target,
            Some(KittyDeleteTarget::ByPlacement(42, Some(7)))
        );
    }

    #[test]
    fn test_kitty_delete_image_number_parses_number_and_placement() {
        let mut parser = KittyParser::new();
        parser.parse_chunk("a=d,d=n,I=13,p=7;").unwrap();
        assert!(!parser.delete_image_data);
        assert_eq!(
            parser.delete_target,
            Some(KittyDeleteTarget::ByImageNumber(13, Some(7)))
        );

        let mut uppercase = KittyParser::new();
        uppercase.parse_chunk("a=d,d=N,I=13;").unwrap();
        assert!(uppercase.delete_image_data);
        assert_eq!(
            uppercase.delete_target,
            Some(KittyDeleteTarget::ByImageNumber(13, None))
        );
    }

    #[test]
    fn test_kitty_delete_image_id_range_parses_bounds() {
        let mut parser = KittyParser::new();
        parser.parse_chunk("a=d,d=r,x=10,y=12;").unwrap();
        assert!(!parser.delete_image_data);
        assert_eq!(
            parser.delete_target,
            Some(KittyDeleteTarget::ByImageIdRange { start: 10, end: 12 })
        );

        let mut uppercase = KittyParser::new();
        uppercase.parse_chunk("a=d,d=R,x=10,y=12;").unwrap();
        assert!(uppercase.delete_image_data);
        assert_eq!(
            uppercase.delete_target,
            Some(KittyDeleteTarget::ByImageIdRange { start: 10, end: 12 })
        );

        let mut reversed = KittyParser::new();
        reversed.parse_chunk("a=d,d=r,x=12,y=10;").unwrap();
        assert_eq!(reversed.delete_target, None);
    }

    #[test]
    fn test_kitty_rejects_image_id_and_number_together() {
        let mut parser = KittyParser::new();
        let error = parser
            .parse_chunk("a=T,f=32,s=1,v=1,i=42,I=13;AAAA")
            .unwrap_err();
        assert!(
            error.to_string().contains("both image id and image number"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn test_kitty_image_number_delete_targets_newest_image() {
        fn one_pixel_payload(r: u8, g: u8, b: u8) -> String {
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, [r, g, b, 255])
        }

        let mut store = GraphicsStore::new();

        let mut first = KittyParser::new();
        first
            .parse_chunk(&format!(
                "a=T,f=32,s=1,v=1,I=13,p=1;{}",
                one_pixel_payload(255, 0, 0)
            ))
            .unwrap();
        let first_graphic = match first.build_graphic((0, 0), &mut store).unwrap() {
            KittyGraphicResult::Graphic(graphic) => graphic,
            _ => panic!("expected first image-number placement"),
        };
        let first_id = first_graphic.kitty_image_id.expect("allocated first id");
        assert!(store.add_graphic(first_graphic));

        let mut second = KittyParser::new();
        second
            .parse_chunk(&format!(
                "a=T,f=32,s=1,v=1,I=13,p=2;{}",
                one_pixel_payload(0, 255, 0)
            ))
            .unwrap();
        let second_graphic = match second.build_graphic((3, 0), &mut store).unwrap() {
            KittyGraphicResult::Graphic(graphic) => graphic,
            _ => panic!("expected second image-number placement"),
        };
        let second_id = second_graphic.kitty_image_id.expect("allocated second id");
        assert_ne!(
            first_id, second_id,
            "I= image numbers must allocate a new image id per new image"
        );
        assert!(store.add_graphic(second_graphic));
        assert_eq!(store.kitty_image_id_for_number(13), Some(second_id));

        let mut delete_latest_placement = KittyParser::new();
        delete_latest_placement
            .parse_chunk("a=d,d=n,I=13,p=2;")
            .unwrap();
        delete_latest_placement
            .build_graphic((0, 0), &mut store)
            .unwrap();

        assert_eq!(store.graphics_count(), 1);
        assert_eq!(store.all_graphics()[0].kitty_image_id, Some(first_id));
        assert_eq!(
            store.kitty_image_id_for_number(13),
            Some(second_id),
            "lowercase delete keeps reusable image data for the newest number"
        );

        let mut release_latest = KittyParser::new();
        release_latest.parse_chunk("a=d,d=N,I=13;").unwrap();
        release_latest.build_graphic((0, 0), &mut store).unwrap();

        assert!(store.get_kitty_image(second_id).is_none());
        assert_eq!(
            store.kitty_image_id_for_number(13),
            Some(first_id),
            "after releasing the newest image id the number resolves to the previous live id"
        );
    }

    #[test]
    fn test_kitty_delete_animation_frame_updates_current_placement() {
        let red_pixels = vec![255, 0, 0, 255];
        let green_pixels = vec![0, 255, 0, 255];
        let mut store = GraphicsStore::new();
        store.add_animation_frame(42, AnimationFrame::new(1, red_pixels.clone(), 1, 1));
        store.add_animation_frame(42, AnimationFrame::new(2, green_pixels.clone(), 1, 1));

        let mut graphic = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Kitty,
            (0, 0),
            1,
            1,
            red_pixels.clone(),
        );
        graphic.kitty_image_id = Some(42);
        graphic.kitty_placement_id = Some(0);
        assert!(store.add_graphic(graphic));
        assert!(store.set_animation_current_frame(42, 2));
        assert_eq!(
            store.all_graphics()[0].pixels.as_ref().as_slice(),
            green_pixels.as_slice()
        );

        let mut delete = KittyParser::new();
        delete.parse_chunk("a=d,d=f,i=42,r=2;").unwrap();
        delete.build_graphic((0, 0), &mut store).unwrap();

        let animation = store.get_animation(42).unwrap();
        assert_eq!(animation.current_frame, 1);
        assert!(animation.get_frame(2).is_none());
        assert_eq!(
            store.all_graphics()[0].pixels.as_ref().as_slice(),
            red_pixels.as_slice()
        );
    }

    #[test]
    fn test_kitty_delete_final_animation_frame_can_release_image() {
        let red_pixels = vec![255, 0, 0, 255];
        let mut store = GraphicsStore::new();
        store.add_animation_frame(42, AnimationFrame::new(1, red_pixels.clone(), 1, 1));
        store.store_kitty_image(42, 1, 1, red_pixels.clone());

        let mut graphic = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Kitty,
            (0, 0),
            1,
            1,
            red_pixels,
        );
        graphic.kitty_image_id = Some(42);
        graphic.kitty_placement_id = Some(0);
        assert!(store.add_graphic(graphic));

        let mut delete = KittyParser::new();
        delete.parse_chunk("a=d,d=F,i=42;").unwrap();
        delete.build_graphic((0, 0), &mut store).unwrap();

        assert_eq!(store.graphics_count(), 0);
        assert!(store.get_animation(42).is_none());
        assert!(store.get_kitty_image(42).is_none());
    }

    #[test]
    fn test_kitty_lowercase_delete_keeps_shared_image_data() {
        let mut store = GraphicsStore::new();
        store.store_kitty_image(42, 1, 1, vec![255, 0, 0, 255]);

        let mut put = KittyParser::new();
        put.parse_chunk("a=p,i=42,p=1;").unwrap();
        let graphic = match put.build_graphic((0, 0), &mut store).unwrap() {
            KittyGraphicResult::Graphic(graphic) => graphic,
            _ => panic!("Expected placement"),
        };
        assert!(store.add_graphic(graphic));

        let mut delete = KittyParser::new();
        delete.parse_chunk("a=d,d=i,i=42;").unwrap();
        delete.build_graphic((0, 0), &mut store).unwrap();

        assert_eq!(store.graphics_count(), 0);
        assert!(
            store.get_kitty_image(42).is_some(),
            "lowercase delete removes placements but keeps reusable image data"
        );
    }

    #[test]
    fn test_kitty_uppercase_delete_releases_unreferenced_image_data() {
        let mut store = GraphicsStore::new();
        store.store_kitty_image(42, 1, 1, vec![255, 0, 0, 255]);
        store.add_animation_frame(42, AnimationFrame::new(1, vec![255, 0, 0, 255], 1, 1));

        let mut put = KittyParser::new();
        put.parse_chunk("a=p,i=42,p=1;").unwrap();
        let graphic = match put.build_graphic((0, 0), &mut store).unwrap() {
            KittyGraphicResult::Graphic(graphic) => graphic,
            _ => panic!("Expected placement"),
        };
        assert!(store.add_graphic(graphic));

        let mut delete = KittyParser::new();
        delete.parse_chunk("a=d,d=I,i=42;").unwrap();
        delete.build_graphic((0, 0), &mut store).unwrap();

        assert_eq!(store.graphics_count(), 0);
        assert!(store.get_kitty_image(42).is_none());
        assert!(store.get_animation(42).is_none());
    }

    #[test]
    fn test_kitty_uppercase_delete_all_releases_unplaced_image_data() {
        let mut store = GraphicsStore::new();
        store.store_kitty_image(42, 1, 1, vec![255, 0, 0, 255]);
        store.add_animation_frame(43, AnimationFrame::new(1, vec![0, 255, 0, 255], 1, 1));

        let mut delete = KittyParser::new();
        delete.parse_chunk("a=d,d=A;").unwrap();
        delete.build_graphic((0, 0), &mut store).unwrap();

        assert!(store.get_kitty_image(42).is_none());
        assert!(store.get_animation(43).is_none());
    }

    #[test]
    fn test_kitty_uppercase_placement_delete_keeps_referenced_image_data() {
        let mut store = GraphicsStore::new();
        store.store_kitty_image(42, 1, 1, vec![255, 0, 0, 255]);

        for (placement_id, col) in [(1, 0), (2, 3)] {
            let mut put = KittyParser::new();
            put.parse_chunk(&format!("a=p,i=42,p={placement_id};"))
                .unwrap();
            let graphic = match put.build_graphic((col, 0), &mut store).unwrap() {
                KittyGraphicResult::Graphic(graphic) => graphic,
                _ => panic!("Expected placement"),
            };
            assert!(store.add_graphic(graphic));
        }

        let mut delete = KittyParser::new();
        delete.parse_chunk("a=d,d=I,i=42,p=1;").unwrap();
        delete.build_graphic((0, 0), &mut store).unwrap();

        assert_eq!(store.graphics_count(), 1);
        assert_eq!(store.all_graphics()[0].kitty_placement_id, Some(2));
        assert!(
            store.get_kitty_image(42).is_some(),
            "image data must remain while another placement still references it"
        );
    }

    #[test]
    fn test_kitty_z_index_for_placement() {
        let mut parser = KittyParser::new();
        parser.parse_chunk("a=p,i=1,z=-1;").unwrap();
        let placement = parser.build_placement();
        assert_eq!(placement.z_index, -1);
    }

    #[test]
    fn test_kitty_z_as_frame_delay_for_frames() {
        let mut parser = KittyParser::new();
        parser.parse_chunk("a=f,i=1,z=100;").unwrap();
        // For frames, z is frame_delay, not z_index
        assert_eq!(parser.frame_delay_ms, Some(100));
        assert!(parser.z_index.is_none());
    }

    #[test]
    fn test_kitty_negative_z_marks_animation_frame_gapless() {
        let pixel_data = vec![255, 0, 0, 255];
        let b64_data =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &pixel_data);
        let mut parser = KittyParser::new();
        parser
            .parse_chunk(&format!("a=f,i=42,f=32,s=1,v=1,r=2,z=-1;{b64_data}"))
            .unwrap();

        assert_eq!(parser.frame_delay_ms, Some(-1));

        let mut store = GraphicsStore::new();
        parser.build_graphic((0, 0), &mut store).unwrap();
        let frame = store.get_animation(42).unwrap().get_frame(2).unwrap();

        assert!(frame.gapless);
        assert_eq!(frame.delay_ms, 0);
    }

    #[test]
    fn test_kitty_animation_control_sets_current_frame_and_updates_placement() {
        let mut store = GraphicsStore::new();
        store.add_animation_frame(42, AnimationFrame::new(1, vec![255, 0, 0, 255], 1, 1));
        store.add_animation_frame(42, AnimationFrame::new(2, vec![0, 0, 255, 255], 1, 1));

        let mut graphic = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Kitty,
            (0, 0),
            1,
            1,
            vec![255, 0, 0, 255],
        );
        graphic.kitty_image_id = Some(42);
        graphic.kitty_placement_id = Some(0);
        assert!(store.add_graphic(graphic));

        let mut control = KittyParser::new();
        control.parse_chunk("a=a,i=42,c=2;").unwrap();
        control.build_graphic((0, 0), &mut store).unwrap();

        let animation = store.get_animation(42).unwrap();
        assert_eq!(animation.current_frame, 2);
        assert_eq!(
            store.all_graphics()[0].pixels.as_ref().as_slice(),
            &[0, 0, 255, 255]
        );
    }

    #[test]
    fn test_kitty_animation_control_rejects_missing_current_frame() {
        let mut store = GraphicsStore::new();
        store.add_animation_frame(42, AnimationFrame::new(1, vec![255, 0, 0, 255], 1, 1));
        store.add_animation_frame(42, AnimationFrame::new(2, vec![0, 0, 255, 255], 1, 1));

        let mut graphic = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Kitty,
            (0, 0),
            1,
            1,
            vec![255, 0, 0, 255],
        );
        graphic.kitty_image_id = Some(42);
        graphic.kitty_placement_id = Some(0);
        assert!(store.add_graphic(graphic));

        assert!(store.set_animation_current_frame(42, 2));
        let mut control = KittyParser::new();
        control.parse_chunk("a=a,i=42,c=99;").unwrap();

        let error = control.build_graphic((0, 0), &mut store).unwrap_err();

        assert!(error.to_string().contains("Animation frame 99 not found"));
        let animation = store.get_animation(42).unwrap();
        assert_eq!(animation.current_frame, 2);
        assert_eq!(
            store.all_graphics()[0].pixels.as_ref().as_slice(),
            &[0, 0, 255, 255]
        );
    }

    #[test]
    fn test_kitty_compose_updates_current_animation_frame_placement() {
        let mut store = GraphicsStore::new();
        let source_pixels = vec![
            255, 0, 0, 255, // red
            0, 255, 0, 255, // green
            0, 0, 255, 255, // blue
            255, 255, 0, 255, // yellow
        ];
        let destination_pixels = [0, 0, 0, 255].repeat(4);
        store.add_animation_frame(42, AnimationFrame::new(1, source_pixels, 2, 2));
        store.add_animation_frame(42, AnimationFrame::new(2, destination_pixels, 2, 2));

        let mut graphic = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::Kitty,
            (0, 0),
            2,
            2,
            [0, 0, 0, 255].repeat(4),
        );
        graphic.kitty_image_id = Some(42);
        graphic.kitty_placement_id = Some(0);
        assert!(store.add_graphic(graphic));

        let mut select_destination = KittyParser::new();
        select_destination.parse_chunk("a=a,i=42,c=2;").unwrap();
        select_destination
            .build_graphic((0, 0), &mut store)
            .unwrap();

        let mut compose = KittyParser::new();
        compose
            .parse_chunk("a=c,i=42,r=1,c=2,x=1,y=1,w=1,h=1,X=0,Y=0,C=1;")
            .unwrap();
        compose.build_graphic((0, 0), &mut store).unwrap();

        let graphic = &store.all_graphics()[0];
        assert_eq!(
            graphic.pixels.as_ref().as_slice(),
            &[
                255, 255, 0, 255, // composed yellow source pixel
                0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255,
            ]
        );
    }

    #[test]
    fn test_kitty_animation_control_updates_frame_delay() {
        let mut store = GraphicsStore::new();
        store.add_animation_frame(42, AnimationFrame::new(1, vec![255, 0, 0, 255], 1, 1));
        store.add_animation_frame(42, AnimationFrame::new(2, vec![0, 0, 255, 255], 1, 1));

        let mut control = KittyParser::new();
        control.parse_chunk("a=a,i=42,r=2,z=250;").unwrap();
        control.build_graphic((0, 0), &mut store).unwrap();

        assert_eq!(
            store
                .get_animation(42)
                .unwrap()
                .get_frame(2)
                .unwrap()
                .delay_ms,
            250
        );
    }

    #[test]
    fn test_kitty_animation_control_rejects_missing_frame_delay_target() {
        let mut store = GraphicsStore::new();
        store.add_animation_frame(42, AnimationFrame::new(1, vec![255, 0, 0, 255], 1, 1));
        store.add_animation_frame(
            42,
            AnimationFrame::new(2, vec![0, 0, 255, 255], 1, 1).with_delay(125),
        );

        let mut control = KittyParser::new();
        control.parse_chunk("a=a,i=42,r=99,z=250;").unwrap();

        let error = control.build_graphic((0, 0), &mut store).unwrap_err();

        assert!(error.to_string().contains("Animation frame 99 not found"));
        assert_eq!(
            store
                .get_animation(42)
                .unwrap()
                .get_frame(2)
                .unwrap()
                .delay_ms,
            125
        );
    }

    #[test]
    fn test_kitty_animation_control_updates_frame_to_gapless() {
        let mut store = GraphicsStore::new();
        store.add_animation_frame(42, AnimationFrame::new(1, vec![255, 0, 0, 255], 1, 1));
        store.add_animation_frame(
            42,
            AnimationFrame::new(2, vec![0, 0, 255, 255], 1, 1).with_delay(250),
        );

        let mut control = KittyParser::new();
        control.parse_chunk("a=a,i=42,r=2,z=-1;").unwrap();
        control.build_graphic((0, 0), &mut store).unwrap();

        let frame = store.get_animation(42).unwrap().get_frame(2).unwrap();
        assert!(frame.gapless);
        assert_eq!(frame.delay_ms, 0);
    }

    #[test]
    fn test_kitty_frame_one_placement_keeps_alternate_screen_scope() {
        let pixel_data = vec![255, 0, 0, 255];
        let b64_data =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &pixel_data);
        let mut parser = KittyParser::new();
        parser
            .parse_chunk(&format!("a=f,i=42,f=32,s=1,v=1,r=1;{b64_data}"))
            .unwrap();

        let mut store = GraphicsStore::new();
        let result = parser
            .build_graphic_for_screen((0, 0), &mut store, true)
            .unwrap();

        match result {
            KittyGraphicResult::Graphic(graphic) => {
                assert!(graphic.alternate_screen);
                assert_eq!(graphic.kitty_image_id, Some(42));
            }
            _ => panic!("Expected frame 1 placement"),
        }
    }

    #[test]
    fn test_kitty_transmit_display_has_placement() {
        let pixel_data: Vec<u8> = vec![
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255,
        ];
        let b64_data =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &pixel_data);

        let mut parser = KittyParser::new();
        let payload = format!(
            "a=T,f=32,s=2,v=2,c=10,r=5,x=1,y=1,w=1,h=1,X=2,Y=3;{}",
            b64_data
        );
        parser.parse_chunk(&payload).unwrap();

        let mut store = GraphicsStore::new();
        let result = parser.build_graphic((0, 0), &mut store).unwrap();

        match result {
            KittyGraphicResult::Graphic(graphic) => {
                assert_eq!(graphic.placement.columns, Some(10));
                assert_eq!(graphic.placement.rows, Some(5));
                assert_eq!(graphic.placement.x_offset, 2);
                assert_eq!(graphic.placement.y_offset, 3);
                assert_eq!(graphic.placement.source_x_offset, 1);
                assert_eq!(graphic.placement.source_y_offset, 1);
                assert_eq!(graphic.placement.source_width, Some(1));
                assert_eq!(graphic.placement.source_height, Some(1));
                assert_eq!(
                    graphic.placement.display_mode,
                    crate::graphics::ImageDisplayMode::Inline
                );
            }
            _ => panic!("Expected Graphic result"),
        }
    }

    #[test]
    fn test_kitty_put_placement_with_z_index() {
        // First store an image
        let pixel_data: Vec<u8> = vec![255, 0, 0, 255];
        let b64_data =
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &pixel_data);

        let mut parser = KittyParser::new();
        let payload = format!("a=t,f=32,s=1,v=1,i=42;{}", b64_data);
        parser.parse_chunk(&payload).unwrap();
        let mut store = GraphicsStore::new();
        parser.build_graphic((0, 0), &mut store).unwrap();

        // Now put with z-index
        let mut parser2 = KittyParser::new();
        parser2.parse_chunk("a=p,i=42,z=5;").unwrap();
        let result = parser2.build_graphic((0, 0), &mut store).unwrap();

        match result {
            KittyGraphicResult::Graphic(graphic) => {
                assert_eq!(graphic.placement.z_index, 5);
            }
            _ => panic!("Expected Graphic result"),
        }
    }
}
