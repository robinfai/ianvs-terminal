//! iTerm2 OSC 1337 inline image support
//!
//! Parses iTerm2 inline image sequences:
//! `OSC 1337 ; File=name=<base64>;size=<bytes>;inline=1:<base64 data> ST`
//!
//! Reference: <https://iterm2.com/documentation-images.html>

use std::collections::HashMap;
use std::io::Cursor;

use crate::debug;
use crate::graphics::{
    next_graphic_id, AnimationFrame, GraphicProtocol, GraphicsError, ImageDimension,
    ImageDisplayMode, ImagePlacement, TerminalGraphic,
};
use base64::Engine;
use image::AnimationDecoder;

/// Maximum allowed image dimension (width or height) in pixels
const MAX_IMAGE_DIMENSION: usize = 16384;

/// Maximum allowed base64-encoded image data size in bytes (100 MB)
const MAX_IMAGE_DATA_SIZE: usize = 100 * 1024 * 1024;

/// iTerm2 inline image parser
#[derive(Debug, Default)]
pub struct ITermParser {
    /// Parsed parameters
    params: HashMap<String, String>,
    /// Base64-encoded image data
    data: Vec<u8>,
}

/// Decoded iTerm2 inline image plus optional animation frames.
#[derive(Debug)]
pub struct ITermDecodedImage {
    pub graphic: TerminalGraphic,
    pub animation_frames: Vec<AnimationFrame>,
}

impl ITermParser {
    /// Create a new parser
    pub fn new() -> Self {
        Self::default()
    }

    /// Parse parameters from OSC 1337 File= sequence
    ///
    /// Format: `name=<base64>;size=<bytes>;width=<n>;height=<n>;inline=1`
    ///
    /// This parses all key=value pairs from the params string. The `inline`
    /// parameter determines whether the data is displayed inline (inline=1)
    /// or treated as a file download (inline=0 or absent).
    pub fn parse_params(&mut self, params_str: &str) -> Result<(), GraphicsError> {
        self.params.clear();

        for part in params_str.split(';') {
            if let Some((key, value)) = part.split_once('=') {
                self.params.insert(key.to_string(), value.to_string());
            }
        }

        Ok(())
    }

    /// Check if this is an inline image (inline=1)
    ///
    /// Returns `true` if the `inline` parameter is set to "1", indicating
    /// the data should be displayed inline in the terminal.
    /// Returns `false` if `inline` is absent, "0", or any other value,
    /// indicating the data is a file download.
    pub fn is_inline(&self) -> bool {
        self.params.get("inline").map(|v| v == "1").unwrap_or(false)
    }

    /// Whether iTerm2 requested that the cursor stay at its original position.
    pub fn do_not_move_cursor(&self) -> bool {
        self.params
            .get("doNotMoveCursor")
            .map(|v| v == "1")
            .unwrap_or(false)
    }

    /// Declared decoded byte size from the optional iTerm2 `size=` parameter.
    pub fn declared_size(&self) -> Option<usize> {
        self.params
            .get("size")
            .and_then(|value| value.parse::<usize>().ok())
    }

    /// Get a reference to all parsed parameters
    pub fn params(&self) -> &HashMap<String, String> {
        &self.params
    }

    /// Set the base64-encoded image data
    ///
    /// Rejects data exceeding `MAX_IMAGE_DATA_SIZE` (100 MB) to prevent
    /// excessive memory allocation from malicious or malformed sequences.
    pub fn set_data(&mut self, data: &[u8]) {
        if data.len() > MAX_IMAGE_DATA_SIZE {
            debug::log(
                debug::DebugLevel::Debug,
                "ITERM",
                &format!(
                    "iTerm2 image data too large: {} bytes (max {} bytes), rejecting",
                    data.len(),
                    MAX_IMAGE_DATA_SIZE
                ),
            );
            self.data.clear();
            return;
        }
        self.data = data.to_vec();
    }

    /// Decode the image and create a TerminalGraphic
    pub fn decode_image(&self, position: (usize, usize)) -> Result<TerminalGraphic, GraphicsError> {
        self.decode_image_with_animation(position)
            .map(|decoded| decoded.graphic)
    }

    /// Decode the image and preserve multi-frame GIF payloads as animation frames.
    pub fn decode_image_with_animation(
        &self,
        position: (usize, usize),
    ) -> Result<ITermDecodedImage, GraphicsError> {
        // Reject empty data (e.g., cleared due to size limit)
        if self.data.is_empty() {
            return Err(GraphicsError::ITermError(
                "No image data available".to_string(),
            ));
        }

        // Check base64 data size before decoding
        if self.data.len() > MAX_IMAGE_DATA_SIZE {
            return Err(GraphicsError::ImageTooLarge(
                self.data.len(),
                MAX_IMAGE_DATA_SIZE,
            ));
        }

        // Decode base64. Some imgcat-like tools wrap base64 data; iTerm2 and
        // compatible terminals tolerate ASCII whitespace in the payload.
        let decoded = decode_base64_ignoring_ascii_whitespace(&self.data)
            .map_err(|e| GraphicsError::Base64Error(e.to_string()))?;
        if let Some(expected_size) = self.declared_size() {
            if decoded.len() != expected_size {
                return Err(GraphicsError::ITermError(format!(
                    "size mismatch: received {} bytes, expected {}",
                    decoded.len(),
                    expected_size
                )));
            }
        }

        if matches!(image::guess_format(&decoded), Ok(image::ImageFormat::Gif)) {
            if let Some(decoded_gif) = self.decode_animated_gif(position, &decoded)? {
                return Ok(decoded_gif);
            }
        }

        // Decode image using image crate
        let img = image::load_from_memory(&decoded)
            .map_err(|e| GraphicsError::ImageError(e.to_string()))?;

        let rgba = img.to_rgba8();
        let width = rgba.width() as usize;
        let height = rgba.height() as usize;

        // Validate decoded image dimensions
        if width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION {
            debug::log(
                debug::DebugLevel::Debug,
                "ITERM",
                &format!(
                    "iTerm2 image dimensions too large: {}x{} (max {}), rejecting",
                    width, height, MAX_IMAGE_DIMENSION
                ),
            );
            return Err(GraphicsError::ImageTooLarge(
                width.max(height),
                MAX_IMAGE_DIMENSION,
            ));
        }

        let pixels = rgba.into_raw();

        let mut graphic = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::ITermInline,
            position,
            width,
            height,
            pixels,
        );

        // Build placement metadata from parsed parameters
        graphic.placement = self.build_placement();

        Ok(ITermDecodedImage {
            graphic,
            animation_frames: Vec::new(),
        })
    }

    fn decode_animated_gif(
        &self,
        position: (usize, usize),
        decoded: &[u8],
    ) -> Result<Option<ITermDecodedImage>, GraphicsError> {
        let decoder = image::codecs::gif::GifDecoder::new(Cursor::new(decoded))
            .map_err(|e| GraphicsError::ImageError(e.to_string()))?;
        let frames = decoder
            .into_frames()
            .collect_frames()
            .map_err(|e| GraphicsError::ImageError(e.to_string()))?;
        if frames.len() <= 1 {
            return Ok(None);
        }

        let mut animation_frames = Vec::with_capacity(frames.len());
        for (index, frame) in frames.into_iter().enumerate() {
            let delay_ms = frame_delay_ms(frame.delay());
            let rgba = frame.into_buffer();
            let width = rgba.width() as usize;
            let height = rgba.height() as usize;
            if width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION {
                return Err(GraphicsError::ImageTooLarge(
                    width.max(height),
                    MAX_IMAGE_DIMENSION,
                ));
            }
            let pixels = rgba.into_raw();
            animation_frames.push(
                AnimationFrame::new((index + 1) as u32, pixels, width, height).with_delay(delay_ms),
            );
        }

        let first_frame = animation_frames
            .first()
            .ok_or_else(|| GraphicsError::ITermError("No GIF frames decoded".to_string()))?;
        let mut graphic = TerminalGraphic::new(
            next_graphic_id(),
            GraphicProtocol::ITermInline,
            position,
            first_frame.width,
            first_frame.height,
            first_frame.pixels.as_ref().clone(),
        );
        graphic.placement = self.build_placement();

        Ok(Some(ITermDecodedImage {
            graphic,
            animation_frames,
        }))
    }

    /// Get a parameter value
    pub fn get_param(&self, key: &str) -> Option<&str> {
        self.params.get(key).map(|s| s.as_str())
    }

    /// Build an ImagePlacement from the parsed parameters
    pub fn build_placement(&self) -> ImagePlacement {
        let display_mode = match self.params.get("inline") {
            Some(v) if v == "1" => ImageDisplayMode::Inline,
            _ => ImageDisplayMode::Download,
        };

        let requested_width = self
            .params
            .get("width")
            .map(|s| Self::parse_dimension(s))
            .unwrap_or_default();

        let requested_height = self
            .params
            .get("height")
            .map(|s| Self::parse_dimension(s))
            .unwrap_or_default();

        let preserve_aspect_ratio = self
            .params
            .get("preserveAspectRatio")
            .map(|v| v != "0")
            .unwrap_or(true); // Default is true per iTerm2 spec

        ImagePlacement {
            display_mode,
            requested_width,
            requested_height,
            preserve_aspect_ratio,
            ..Default::default()
        }
    }

    /// Parse an iTerm2 dimension string (e.g., "100", "50px", "80%", "auto", "10")
    ///
    /// iTerm2 dimension format:
    /// - N or Npx: N pixels
    /// - N%: N percent of terminal
    /// - "auto": automatic sizing
    /// - Plain number without suffix: cells
    fn parse_dimension(s: &str) -> ImageDimension {
        let trimmed = s.trim();
        let compacted_unit;
        let parts = trimmed.split_whitespace().collect::<Vec<_>>();
        let s = if parts.len() == 2 && (parts[1].eq_ignore_ascii_case("px") || parts[1] == "%") {
            compacted_unit = format!("{}{}", parts[0], parts[1].to_ascii_lowercase());
            compacted_unit.as_str()
        } else {
            trimmed
        };

        if s.eq_ignore_ascii_case("auto") || s == "0" {
            return ImageDimension::auto();
        }

        if let Some(stripped) = s.strip_suffix('%') {
            if let Ok(val) = stripped.parse::<f64>() {
                return Self::positive_dimension(val, ImageDimension::percent);
            }
        }

        if let Some(stripped) = s
            .strip_suffix("px")
            .or_else(|| s.strip_suffix("PX"))
            .or_else(|| s.strip_suffix("Px"))
            .or_else(|| s.strip_suffix("pX"))
        {
            if let Ok(val) = stripped.parse::<f64>() {
                return Self::positive_dimension(val, ImageDimension::pixels);
            }
        }

        // Plain number = cells per iTerm2 spec
        if let Ok(val) = s.parse::<f64>() {
            return Self::positive_dimension(val, ImageDimension::cells);
        }

        ImageDimension::auto()
    }

    fn positive_dimension(val: f64, constructor: fn(f64) -> ImageDimension) -> ImageDimension {
        if val.is_finite() && val > 0.0 {
            constructor(val)
        } else {
            ImageDimension::auto()
        }
    }
}

pub(crate) fn decode_base64_ignoring_ascii_whitespace(
    data: &[u8],
) -> Result<Vec<u8>, base64::DecodeError> {
    let compact;
    let data = if data.iter().all(|byte| !byte.is_ascii_whitespace()) {
        data
    } else {
        compact = data
            .iter()
            .copied()
            .filter(|byte| !byte.is_ascii_whitespace())
            .collect::<Vec<_>>();
        &compact
    };

    match base64::engine::general_purpose::STANDARD.decode(data) {
        Ok(decoded) => Ok(decoded),
        Err(error) => {
            let remainder = data.len() % 4;
            if remainder == 0 || remainder == 1 {
                return Err(error);
            }
            let mut padded = Vec::with_capacity(data.len() + (4 - remainder));
            padded.extend_from_slice(data);
            padded.extend(std::iter::repeat_n(b'=', 4 - remainder));
            base64::engine::general_purpose::STANDARD
                .decode(padded)
                .map_err(|_| error)
        }
    }
}

fn frame_delay_ms(delay: image::Delay) -> u32 {
    let (numerator, denominator) = delay.numer_denom_ms();
    if numerator == 0 || denominator == 0 {
        return 0;
    }
    numerator.div_ceil(denominator)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_params_basic() {
        let mut parser = ITermParser::new();
        let result = parser.parse_params("inline=1");
        assert!(result.is_ok());
    }

    #[test]
    fn test_parse_params_missing_inline() {
        let mut parser = ITermParser::new();
        let result = parser.parse_params("name=test");
        assert!(result.is_ok());
        assert!(!parser.is_inline());
    }

    #[test]
    fn test_is_inline() {
        let mut parser = ITermParser::new();
        parser.parse_params("inline=1").unwrap();
        assert!(parser.is_inline());

        let mut parser2 = ITermParser::new();
        parser2.parse_params("inline=0").unwrap();
        assert!(!parser2.is_inline());

        let mut parser3 = ITermParser::new();
        parser3.parse_params("name=test").unwrap();
        assert!(!parser3.is_inline());
    }

    #[test]
    fn test_parse_params_full() {
        let mut parser = ITermParser::new();
        let result = parser
            .parse_params("name=dGVzdA==;size=1234;width=100;height=50;inline=1;doNotMoveCursor=1");
        assert!(result.is_ok());
        assert_eq!(parser.get_param("name"), Some("dGVzdA=="));
        assert_eq!(parser.get_param("size"), Some("1234"));
        assert_eq!(parser.get_param("width"), Some("100"));
        assert_eq!(parser.get_param("height"), Some("50"));
        assert_eq!(parser.declared_size(), Some(1234));
        assert!(parser.do_not_move_cursor());
    }

    #[test]
    fn test_parse_dimension_auto() {
        let dim = ITermParser::parse_dimension("auto");
        assert!(dim.is_auto());
        assert_eq!(dim.unit, crate::graphics::ImageSizeUnit::Auto);
    }

    #[test]
    fn test_parse_dimension_zero() {
        let dim = ITermParser::parse_dimension("0");
        assert!(dim.is_auto());
    }

    #[test]
    fn test_parse_dimension_non_positive_values_are_auto() {
        for raw in [
            "-5", "-5px", "-5 px", "-10%", "-10 %", "0px", "0%", "0 px", "0 %",
        ] {
            let dim = ITermParser::parse_dimension(raw);
            assert!(
                dim.is_auto(),
                "expected {raw:?} to fall back to automatic sizing"
            );
            assert_eq!(dim.unit, crate::graphics::ImageSizeUnit::Auto);
        }
    }

    #[test]
    fn test_parse_dimension_non_finite_values_are_auto() {
        for raw in ["NaN", "inf", "infpx", "inf px", "inf%", "inf %"] {
            let dim = ITermParser::parse_dimension(raw);
            assert!(
                dim.is_auto(),
                "expected {raw:?} to fall back to automatic sizing"
            );
            assert_eq!(dim.unit, crate::graphics::ImageSizeUnit::Auto);
        }
    }

    #[test]
    fn test_parse_dimension_cells() {
        let dim = ITermParser::parse_dimension("10");
        assert_eq!(dim.value, 10.0);
        assert_eq!(dim.unit, crate::graphics::ImageSizeUnit::Cells);
    }

    #[test]
    fn test_parse_dimension_pixels() {
        let dim = ITermParser::parse_dimension("200px");
        assert_eq!(dim.value, 200.0);
        assert_eq!(dim.unit, crate::graphics::ImageSizeUnit::Pixels);
    }

    #[test]
    fn test_parse_dimension_pixels_accepts_space_before_unit() {
        let dim = ITermParser::parse_dimension("200 px");
        assert_eq!(dim.value, 200.0);
        assert_eq!(dim.unit, crate::graphics::ImageSizeUnit::Pixels);

        let uppercase = ITermParser::parse_dimension("200 PX");
        assert_eq!(uppercase.value, 200.0);
        assert_eq!(uppercase.unit, crate::graphics::ImageSizeUnit::Pixels);
    }

    #[test]
    fn test_parse_dimension_percent() {
        let dim = ITermParser::parse_dimension("50%");
        assert_eq!(dim.value, 50.0);
        assert_eq!(dim.unit, crate::graphics::ImageSizeUnit::Percent);
    }

    #[test]
    fn test_parse_dimension_percent_accepts_space_before_unit() {
        let dim = ITermParser::parse_dimension("50 %");
        assert_eq!(dim.value, 50.0);
        assert_eq!(dim.unit, crate::graphics::ImageSizeUnit::Percent);
    }

    #[test]
    fn test_parse_dimension_invalid() {
        let dim = ITermParser::parse_dimension("invalid");
        assert!(dim.is_auto());
    }

    #[test]
    fn test_build_placement_basic() {
        let mut parser = ITermParser::new();
        parser.parse_params("inline=1").unwrap();
        let placement = parser.build_placement();
        assert_eq!(
            placement.display_mode,
            crate::graphics::ImageDisplayMode::Inline
        );
        assert!(placement.preserve_aspect_ratio);
        assert!(placement.requested_width.is_auto());
        assert!(placement.requested_height.is_auto());
    }

    #[test]
    fn test_build_placement_with_dimensions() {
        let mut parser = ITermParser::new();
        parser
            .parse_params("inline=1;width=100px;height=50%")
            .unwrap();
        let placement = parser.build_placement();

        assert_eq!(placement.requested_width.value, 100.0);
        assert_eq!(
            placement.requested_width.unit,
            crate::graphics::ImageSizeUnit::Pixels
        );
        assert_eq!(placement.requested_height.value, 50.0);
        assert_eq!(
            placement.requested_height.unit,
            crate::graphics::ImageSizeUnit::Percent
        );
    }

    #[test]
    fn test_build_placement_preserve_aspect_ratio() {
        let mut parser = ITermParser::new();
        parser
            .parse_params("inline=1;preserveAspectRatio=0")
            .unwrap();
        let placement = parser.build_placement();
        assert!(!placement.preserve_aspect_ratio);

        let mut parser2 = ITermParser::new();
        parser2
            .parse_params("inline=1;preserveAspectRatio=1")
            .unwrap();
        let placement2 = parser2.build_placement();
        assert!(placement2.preserve_aspect_ratio);
    }

    #[test]
    fn test_build_placement_download_mode() {
        let mut parser = ITermParser::new();
        // parse_params fails without inline=1, but build_placement works on whatever was parsed
        parser.params.insert("inline".to_string(), "0".to_string());
        let placement = parser.build_placement();
        assert_eq!(
            placement.display_mode,
            crate::graphics::ImageDisplayMode::Download
        );
    }

    #[test]
    fn test_decode_base64_ignores_ascii_whitespace() {
        let decoded = decode_base64_ignoring_ascii_whitespace(b"aG Vs\nbG8=\r\t").unwrap();

        assert_eq!(decoded, b"hello");
    }

    #[test]
    fn test_decode_base64_accepts_missing_padding() {
        let decoded = decode_base64_ignoring_ascii_whitespace(b"aGVsbG8").unwrap();

        assert_eq!(decoded, b"hello");
    }
}
