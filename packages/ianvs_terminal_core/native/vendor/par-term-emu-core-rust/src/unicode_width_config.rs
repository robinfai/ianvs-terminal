//! Configurable Unicode width calculation
//!
//! This module provides configurable character width calculations for terminal emulation.
//! It supports:
//! - Different Unicode versions for width tables
//! - Configurable treatment of East Asian Ambiguous width characters
//!
//! # Unicode Version Support
//!
//! Different Unicode versions have different width tables, particularly for emoji.
//! The `UnicodeVersion` enum allows specifying which version's width tables to use.
//!
//! # Ambiguous Width
//!
//! Some characters (East Asian Ambiguous) have uncertain width - they may be displayed
//! as either 1 or 2 cells depending on the context:
//! - Western contexts typically use narrow (1 cell)
//! - CJK contexts typically use wide (2 cells)
//!
//! # Example
//!
//! ```
//! use par_term_emu_core_rust::unicode_width_config::{WidthConfig, UnicodeVersion, AmbiguousWidth, char_width};
//!
//! let config = WidthConfig::default();
//! assert_eq!(char_width('A', &config), 1);
//! assert_eq!(char_width('\u{4E00}', &config), 2); // CJK character
//! ```

use serde::{Deserialize, Serialize};
use unicode_segmentation::UnicodeSegmentation;
use unicode_width::UnicodeWidthChar;

/// Unicode version for width calculation tables.
///
/// Different Unicode versions have different character width assignments,
/// particularly for newly added emoji and other characters.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UnicodeVersion {
    /// Unicode 8.0 (June 2015) - legacy single-cell emoji widths
    Unicode8,
    /// Unicode 9.0 (June 2016) - standardized emoji widths
    Unicode9,
    /// Unicode 10.0 (June 2017)
    Unicode10,
    /// Unicode 11.0 (June 2018)
    Unicode11,
    /// Unicode 12.0 (March 2019)
    Unicode12,
    /// Unicode 13.0 (March 2020)
    Unicode13,
    /// Unicode 14.0 (September 2021)
    Unicode14,
    /// Unicode 15.0 (September 2022)
    Unicode15,
    /// Unicode 15.1 (September 2023)
    Unicode15_1,
    /// Unicode 16.0 (September 2024)
    Unicode16,
    /// Use the latest available Unicode version (default)
    #[default]
    Auto,
}

impl UnicodeVersion {
    /// Returns true if this version is Auto (use latest)
    #[inline]
    pub fn is_auto(&self) -> bool {
        matches!(self, UnicodeVersion::Auto)
    }

    /// Returns the version number as a tuple (major, minor)
    pub fn version_tuple(&self) -> Option<(u8, u8)> {
        match self {
            UnicodeVersion::Unicode8 => Some((8, 0)),
            UnicodeVersion::Unicode9 => Some((9, 0)),
            UnicodeVersion::Unicode10 => Some((10, 0)),
            UnicodeVersion::Unicode11 => Some((11, 0)),
            UnicodeVersion::Unicode12 => Some((12, 0)),
            UnicodeVersion::Unicode13 => Some((13, 0)),
            UnicodeVersion::Unicode14 => Some((14, 0)),
            UnicodeVersion::Unicode15 => Some((15, 0)),
            UnicodeVersion::Unicode15_1 => Some((15, 1)),
            UnicodeVersion::Unicode16 => Some((16, 0)),
            UnicodeVersion::Auto => None,
        }
    }

    /// Returns a human-readable version string
    pub fn version_string(&self) -> &'static str {
        match self {
            UnicodeVersion::Unicode8 => "8.0",
            UnicodeVersion::Unicode9 => "9.0",
            UnicodeVersion::Unicode10 => "10.0",
            UnicodeVersion::Unicode11 => "11.0",
            UnicodeVersion::Unicode12 => "12.0",
            UnicodeVersion::Unicode13 => "13.0",
            UnicodeVersion::Unicode14 => "14.0",
            UnicodeVersion::Unicode15 => "15.0",
            UnicodeVersion::Unicode15_1 => "15.1",
            UnicodeVersion::Unicode16 => "16.0",
            UnicodeVersion::Auto => "auto",
        }
    }
}

/// Treatment of East Asian Ambiguous width characters.
///
/// Ambiguous characters include Greek/Cyrillic letters, some symbols, and
/// other characters that may display as either 1 or 2 cells depending on context.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AmbiguousWidth {
    /// Narrow (1 cell) - Western/default terminal behavior
    #[default]
    Narrow,
    /// Wide (2 cells) - CJK terminal behavior
    Wide,
}

impl AmbiguousWidth {
    /// Returns the width value (1 or 2)
    #[inline]
    pub fn width(&self) -> usize {
        match self {
            AmbiguousWidth::Narrow => 1,
            AmbiguousWidth::Wide => 2,
        }
    }

    /// Returns true if this is the narrow setting
    #[inline]
    pub fn is_narrow(&self) -> bool {
        matches!(self, AmbiguousWidth::Narrow)
    }

    /// Returns true if this is the wide setting
    #[inline]
    pub fn is_wide(&self) -> bool {
        matches!(self, AmbiguousWidth::Wide)
    }
}

/// Configuration for Unicode width calculations.
///
/// This struct combines Unicode version and ambiguous width settings
/// to control how character widths are calculated in the terminal.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct WidthConfig {
    /// Unicode version for width tables
    #[serde(default)]
    pub unicode_version: UnicodeVersion,
    /// Treatment of East Asian Ambiguous width characters
    #[serde(default)]
    pub ambiguous_width: AmbiguousWidth,
}

impl WidthConfig {
    /// Create a new WidthConfig with specified settings
    pub fn new(unicode_version: UnicodeVersion, ambiguous_width: AmbiguousWidth) -> Self {
        Self {
            unicode_version,
            ambiguous_width,
        }
    }

    /// Create a WidthConfig optimized for CJK environments
    pub fn cjk() -> Self {
        Self {
            unicode_version: UnicodeVersion::Auto,
            ambiguous_width: AmbiguousWidth::Wide,
        }
    }

    /// Create a WidthConfig optimized for Western environments
    pub fn western() -> Self {
        Self {
            unicode_version: UnicodeVersion::Auto,
            ambiguous_width: AmbiguousWidth::Narrow,
        }
    }
}

/// Check if a character is East Asian Ambiguous.
///
/// East Asian Ambiguous characters are those that have uncertain width,
/// displaying as either 1 or 2 cells depending on context.
///
/// This includes characters like:
/// - Greek and Cyrillic letters
/// - Some mathematical symbols
/// - Some line-drawing characters
/// - Various punctuation marks
#[inline]
pub fn is_east_asian_ambiguous(c: char) -> bool {
    // Common East Asian Ambiguous ranges
    // Based on Unicode EastAsianWidth property
    let code = c as u32;
    matches!(code,
        // Latin extended characters with ambiguous width
        0x00A1 | // INVERTED EXCLAMATION MARK
        0x00A4 | // CURRENCY SIGN
        0x00A7..=0x00A8 | // SECTION SIGN, DIAERESIS
        0x00AA | // FEMININE ORDINAL INDICATOR
        0x00AD..=0x00AE | // SOFT HYPHEN, REGISTERED SIGN
        0x00B0..=0x00B4 | // DEGREE SIGN through ACUTE ACCENT
        0x00B6..=0x00BA | // PILCROW SIGN through MASCULINE ORDINAL
        0x00BC..=0x00BF | // VULGAR FRACTIONS, INVERTED QUESTION MARK
        0x00C6 | // LATIN CAPITAL LETTER AE
        0x00D0 | // LATIN CAPITAL LETTER ETH
        0x00D7..=0x00D8 | // MULTIPLICATION SIGN, LATIN CAPITAL O WITH STROKE
        0x00DE..=0x00E1 | // THORN through LATIN SMALL A WITH ACUTE
        0x00E6 | // LATIN SMALL LETTER AE
        0x00E8..=0x00EA | // E WITH GRAVE through E WITH CIRCUMFLEX
        0x00EC..=0x00ED | // I WITH GRAVE, I WITH ACUTE
        0x00F0 | // LATIN SMALL LETTER ETH
        0x00F2..=0x00F3 | // O WITH GRAVE, O WITH ACUTE
        0x00F7..=0x00FA | // DIVISION SIGN through U WITH ACUTE
        0x00FC | // U WITH DIAERESIS
        0x00FE | // LATIN SMALL LETTER THORN

        // Greek letters
        0x0391..=0x03A1 | // GREEK CAPITAL LETTERS
        0x03A3..=0x03A9 | // More Greek capitals
        0x03B1..=0x03C1 | // Greek small letters
        0x03C3..=0x03C9 | // More Greek small letters

        // Cyrillic letters
        0x0401 | // CYRILLIC CAPITAL LETTER IO
        0x0410..=0x044F | // Basic Cyrillic
        0x0451 | // CYRILLIC SMALL LETTER IO

        // General punctuation
        0x2010 | // HYPHEN
        0x2013..=0x2016 | // EN DASH through DOUBLE VERTICAL LINE
        0x2018..=0x2019 | // SINGLE QUOTATION MARKS
        0x201C..=0x201D | // DOUBLE QUOTATION MARKS
        0x2020..=0x2022 | // DAGGER, DOUBLE DAGGER, BULLET
        0x2024..=0x2027 | // ONE DOT LEADER through HYPHENATION POINT
        0x2030 | // PER MILLE SIGN
        0x2032..=0x2033 | // PRIME, DOUBLE PRIME
        0x2035 | // REVERSED PRIME
        0x203B | // REFERENCE MARK
        0x203E | // OVERLINE
        0x2074 | // SUPERSCRIPT FOUR
        0x207F | // SUPERSCRIPT LATIN SMALL LETTER N
        0x2081..=0x2084 | // SUBSCRIPTS 1-4

        // Letterlike symbols
        0x2103 | // DEGREE CELSIUS
        0x2105 | // CARE OF
        0x2109 | // DEGREE FAHRENHEIT
        0x2113 | // SCRIPT SMALL L
        0x2116 | // NUMERO SIGN
        0x2121..=0x2122 | // TEL, TM
        0x2126 | // OHM SIGN
        0x212B | // ANGSTROM SIGN
        0x2153..=0x2154 | // VULGAR FRACTIONS

        // Arrows
        0x2190..=0x2199 | // ARROWS
        0x21B8..=0x21B9 | // More arrows
        0x21D2 | // RIGHTWARDS DOUBLE ARROW
        0x21D4 | // LEFT RIGHT DOUBLE ARROW
        0x21E7 | // UPWARDS WHITE ARROW

        // Mathematical operators
        0x2200 | // FOR ALL
        0x2202..=0x2203 | // PARTIAL DIFFERENTIAL, THERE EXISTS
        0x2207..=0x2208 | // NABLA, ELEMENT OF
        0x220B | // CONTAINS AS MEMBER
        0x220F | // N-ARY PRODUCT
        0x2211 | // N-ARY SUMMATION
        0x2215 | // DIVISION SLASH
        0x221A | // SQUARE ROOT
        0x221D..=0x2220 | // PROPORTIONAL TO through ANGLE
        0x2223 | // DIVIDES
        0x2225 | // PARALLEL TO
        0x2227..=0x222C | // LOGICAL AND through DOUBLE INTEGRAL
        0x222E | // CONTOUR INTEGRAL
        0x2234..=0x2237 | // THEREFORE through PROPORTION
        0x223C..=0x223D | // TILDE OPERATOR, REVERSED TILDE
        0x2248 | // ALMOST EQUAL TO
        0x224C | // ALL EQUAL TO
        0x2252 | // APPROXIMATELY EQUAL TO OR THE IMAGE OF
        0x2260..=0x2261 | // NOT EQUAL TO, IDENTICAL TO
        0x2264..=0x2267 | // LESS/GREATER THAN OR EQUAL TO
        0x226A..=0x226B | // MUCH LESS/GREATER THAN
        0x226E..=0x226F | // NOT LESS/GREATER THAN
        0x2282..=0x2283 | // SUBSET/SUPERSET OF
        0x2286..=0x2287 | // SUBSET/SUPERSET OF OR EQUAL TO
        0x2295 | // CIRCLED PLUS
        0x2299 | // CIRCLED DOT OPERATOR
        0x22A5 | // UP TACK
        0x22BF | // RIGHT TRIANGLE

        // Miscellaneous technical
        0x2312 | // ARC

        // Box drawing (subset that's ambiguous)
        0x2500..=0x254B | // Box drawing

        // Block elements
        0x2550..=0x2573 | // More box drawing
        0x2580..=0x258F | // Block elements
        0x2592..=0x2595 | // Shades and light/medium/dark shades

        // Geometric shapes
        0x25A0..=0x25A1 | // BLACK/WHITE SQUARE
        0x25A3..=0x25A9 | // Various squares
        0x25B2..=0x25B3 | // BLACK/WHITE UP-POINTING TRIANGLE
        0x25B6..=0x25B7 | // BLACK/WHITE RIGHT-POINTING TRIANGLE
        0x25BC..=0x25BD | // BLACK/WHITE DOWN-POINTING TRIANGLE
        0x25C0..=0x25C1 | // BLACK/WHITE LEFT-POINTING TRIANGLE
        0x25C6..=0x25C8 | // BLACK/WHITE DIAMOND
        0x25CB | // WHITE CIRCLE
        0x25CE..=0x25D1 | // BULLSEYE through CIRCLE variants
        0x25E2..=0x25E5 | // BLACK triangles
        0x25EF | // LARGE CIRCLE

        // Miscellaneous symbols
        0x2605..=0x2606 | // BLACK/WHITE STAR
        0x2609 | // SUN
        0x260E..=0x260F | // Telephone symbols
        0x2614..=0x2615 | // Umbrella, hot beverage
        0x261C | // WHITE LEFT POINTING INDEX
        0x261E | // WHITE RIGHT POINTING INDEX
        0x2640 | // FEMALE SIGN
        0x2642 | // MALE SIGN
        0x2660..=0x2661 | // BLACK/WHITE SPADE SUIT
        0x2663..=0x2665 | // Card suit symbols
        0x2667..=0x266A | // More card suits, musical notes
        0x266C..=0x266D | // BEAMED SIXTEENTH NOTES, MUSIC FLAT SIGN
        0x266F | // MUSIC SHARP SIGN
        0x269E..=0x269F | // THREE LINES CONVERGING
        0x26BE..=0x26BF | // Baseball, squared key
        0x26C4..=0x26CD | // Various symbols
        0x26CF..=0x26E1 | // More symbols
        0x26E3 | // HEAVY CIRCLE WITH STROKE
        0x26E8..=0x26FF | // More symbols

        // Dingbats
        0x273D | // HEAVY TEARDROP-SPOKED ASTERISK
        0x2757 | // HEAVY EXCLAMATION MARK SYMBOL
        0x2776..=0x277F | // DINGBAT NEGATIVE CIRCLED DIGITS

        // CJK symbols
        0x2B55..=0x2B59 | // Heavy circles
        0xFE00..=0xFE0F | // Variation selectors
        0xFFFD // REPLACEMENT CHARACTER
    )
}

/// Unicode 8.0 East Asian Width `W`/`F` table used by iTerm2's
/// `OSC 1337;UnicodeVersion=8` compatibility mode.
///
/// Source: Unicode 8.0 `EastAsianWidth.txt`, mirrored by iTerm2's generated
/// `iTermCharacterWidth.c`. Unicode 9 and later use `unicode-width`'s current
/// generated tables, matching iTerm2's modern-width compatibility mode.
#[inline]
fn is_unicode8_full_width(c: char) -> bool {
    matches!(c as u32,
        0x1100..=0x115F |
        0x11A3..=0x11A7 |
        0x11FA..=0x11FF |
        0x2329..=0x232A |
        0x2E80..=0x2E99 |
        0x2E9B..=0x2EF3 |
        0x2F00..=0x2FD5 |
        0x2FF0..=0x2FFB |
        0x3000..=0x303E |
        0x3041..=0x3096 |
        0x3099..=0x30FF |
        0x3105..=0x312D |
        0x3131..=0x318E |
        0x3190..=0x31BA |
        0x31C0..=0x31E3 |
        0x31F0..=0x321E |
        0x3220..=0x3247 |
        0x3250..=0x32FE |
        0x3300..=0x4DBF |
        0x4E00..=0xA48C |
        0xA490..=0xA4C6 |
        0xA960..=0xA97C |
        0xAC00..=0xD7A3 |
        0xD7B0..=0xD7C6 |
        0xD7CB..=0xD7FB |
        0xF900..=0xFAFF |
        0xFE10..=0xFE19 |
        0xFE30..=0xFE52 |
        0xFE54..=0xFE66 |
        0xFE68..=0xFE6B |
        0xFF01..=0xFF60 |
        0xFFE0..=0xFFE6 |
        0x1B000..=0x1B001 |
        0x1F200..=0x1F202 |
        0x1F210..=0x1F23A |
        0x1F240..=0x1F248 |
        0x1F250..=0x1F251 |
        0x20000..=0x2FFFD |
        0x30000..=0x3FFFD
    )
}

/// Unicode 8.0 East Asian Width `A` table.
///
/// Private-use codepoints intentionally remain single-cell in `char_width`
/// before this table is consulted. That existing terminal-font override keeps
/// Nerd Font and Powerline glyphs aligned.
#[inline]
fn is_unicode8_ambiguous(c: char) -> bool {
    matches!(c as u32,
        0x00A1 |
        0x00A4 |
        0x00A7..=0x00A8 |
        0x00AA |
        0x00AD..=0x00AE |
        0x00B0..=0x00B4 |
        0x00B6..=0x00BA |
        0x00BC..=0x00BF |
        0x00C6 |
        0x00D0 |
        0x00D7..=0x00D8 |
        0x00DE..=0x00E1 |
        0x00E6 |
        0x00E8..=0x00EA |
        0x00EC..=0x00ED |
        0x00F0 |
        0x00F2..=0x00F3 |
        0x00F7..=0x00FA |
        0x00FC |
        0x00FE |
        0x0101 |
        0x0111 |
        0x0113 |
        0x011B |
        0x0126..=0x0127 |
        0x012B |
        0x0131..=0x0133 |
        0x0138 |
        0x013F..=0x0142 |
        0x0144 |
        0x0148..=0x014B |
        0x014D |
        0x0152..=0x0153 |
        0x0166..=0x0167 |
        0x016B |
        0x01CE |
        0x01D0 |
        0x01D2 |
        0x01D4 |
        0x01D6 |
        0x01D8 |
        0x01DA |
        0x01DC |
        0x0251 |
        0x0261 |
        0x02C4 |
        0x02C7 |
        0x02C9..=0x02CB |
        0x02CD |
        0x02D0 |
        0x02D8..=0x02DB |
        0x02DD |
        0x02DF |
        0x0300..=0x036F |
        0x0391..=0x03A1 |
        0x03A3..=0x03A9 |
        0x03B1..=0x03C1 |
        0x03C3..=0x03C9 |
        0x0401 |
        0x0410..=0x044F |
        0x0451 |
        0x2010 |
        0x2013..=0x2016 |
        0x2018..=0x2019 |
        0x201C..=0x201D |
        0x2020..=0x2022 |
        0x2024..=0x2027 |
        0x2030 |
        0x2032..=0x2033 |
        0x2035 |
        0x203B |
        0x203E |
        0x2074 |
        0x207F |
        0x2081..=0x2084 |
        0x20AC |
        0x2103 |
        0x2105 |
        0x2109 |
        0x2113 |
        0x2116 |
        0x2121..=0x2122 |
        0x2126 |
        0x212B |
        0x2153..=0x2154 |
        0x215B..=0x215E |
        0x2160..=0x216B |
        0x2170..=0x2179 |
        0x2189 |
        0x2190..=0x2199 |
        0x21B8..=0x21B9 |
        0x21D2 |
        0x21D4 |
        0x21E7 |
        0x2200 |
        0x2202..=0x2203 |
        0x2207..=0x2208 |
        0x220B |
        0x220F |
        0x2211 |
        0x2215 |
        0x221A |
        0x221D..=0x2220 |
        0x2223 |
        0x2225 |
        0x2227..=0x222C |
        0x222E |
        0x2234..=0x2237 |
        0x223C..=0x223D |
        0x2248 |
        0x224C |
        0x2252 |
        0x2260..=0x2261 |
        0x2264..=0x2267 |
        0x226A..=0x226B |
        0x226E..=0x226F |
        0x2282..=0x2283 |
        0x2286..=0x2287 |
        0x2295 |
        0x2299 |
        0x22A5 |
        0x22BF |
        0x2312 |
        0x2460..=0x24E9 |
        0x24EB..=0x254B |
        0x2550..=0x2573 |
        0x2580..=0x258F |
        0x2592..=0x2595 |
        0x25A0..=0x25A1 |
        0x25A3..=0x25A9 |
        0x25B2..=0x25B3 |
        0x25B6..=0x25B7 |
        0x25BC..=0x25BD |
        0x25C0..=0x25C1 |
        0x25C6..=0x25C8 |
        0x25CB |
        0x25CE..=0x25D1 |
        0x25E2..=0x25E5 |
        0x25EF |
        0x2605..=0x2606 |
        0x2609 |
        0x260E..=0x260F |
        0x2614..=0x2615 |
        0x261C |
        0x261E |
        0x2640 |
        0x2642 |
        0x2660..=0x2661 |
        0x2663..=0x2665 |
        0x2667..=0x266A |
        0x266C..=0x266D |
        0x266F |
        0x269E..=0x269F |
        0x26BE..=0x26BF |
        0x26C4..=0x26CD |
        0x26CF..=0x26E1 |
        0x26E3 |
        0x26E8..=0x26FF |
        0x273D |
        0x2757 |
        0x2776..=0x277F |
        0x2B55..=0x2B59 |
        0x3248..=0x324F |
        0xE000..=0xF8FF |
        0xFE00..=0xFE0F |
        0xFFFD |
        0x1F100..=0x1F10A |
        0x1F110..=0x1F12D |
        0x1F130..=0x1F169 |
        0x1F170..=0x1F19A |
        0xE0100..=0xE01EF |
        0xF0000..=0xFFFFD |
        0x100000..=0x10FFFD
    )
}

/// Check if a character is in a Unicode Private Use Area.
///
/// Nerd Font and Powerline glyphs commonly live in these ranges. Terminals
/// treat these codepoints as font-selected glyphs rather than East Asian or
/// emoji characters, so the parser keeps them single-cell to match frontend
/// layout and common monospace terminal behavior.
#[inline]
pub fn is_private_use(c: char) -> bool {
    let code = c as u32;
    matches!(code, 0xE000..=0xF8FF | 0xF0000..=0xFFFFD | 0x100000..=0x10FFFD)
}

/// Calculate the display width of a character.
///
/// This function calculates how many terminal cells a character occupies,
/// taking into account the width configuration.
///
/// # Arguments
///
/// * `c` - The character to measure
/// * `config` - Width configuration settings
///
/// # Returns
///
/// The display width in cells (0, 1, or 2)
///
/// # Examples
///
/// ```
/// use par_term_emu_core_rust::unicode_width_config::{char_width, WidthConfig, AmbiguousWidth};
///
/// let config = WidthConfig::default();
/// assert_eq!(char_width('A', &config), 1);
/// assert_eq!(char_width('\u{4E00}', &config), 2); // CJK
///
/// // With CJK ambiguous width setting
/// let cjk_config = WidthConfig::cjk();
/// // Greek alpha is ambiguous
/// assert_eq!(char_width('\u{03B1}', &cjk_config), 2);
/// ```
#[inline]
pub fn char_width(c: char, config: &WidthConfig) -> usize {
    if crate::grapheme::is_variation_selector(c)
        || crate::grapheme::is_zwj(c)
        || crate::grapheme::is_zero_width_format(c)
        || crate::grapheme::is_emoji_tag(c)
        || crate::grapheme::is_skin_tone_modifier(c)
        || crate::grapheme::is_combining_mark(c)
    {
        return 0;
    }

    // Private-use glyphs are terminal font features. Keeping them single-cell
    // prevents Nerd Font icons from shifting prompt and status-line columns.
    if is_private_use(c) {
        return 1;
    }

    if config.unicode_version == UnicodeVersion::Unicode8 {
        if is_unicode8_full_width(c)
            || (config.ambiguous_width.is_wide() && is_unicode8_ambiguous(c))
        {
            return 2;
        }

        // Unicode 8 classified the remaining printable characters as narrow,
        // including most emoji that modern tables classify as wide.
        return match c.width() {
            Some(0) | None => 0,
            Some(_) => 1,
        };
    }

    if config.ambiguous_width.is_wide() {
        if is_east_asian_ambiguous(c) {
            return 2;
        }
        return c.width_cjk().unwrap_or(0);
    }

    c.width().unwrap_or(0)
}

/// Calculate the display width of a character with CJK ambiguous width.
///
/// This is a convenience function that uses `AmbiguousWidth::Wide`.
/// Equivalent to calling `char_width(c, &WidthConfig::cjk())`.
#[inline]
pub fn char_width_cjk(c: char) -> usize {
    char_width(c, &WidthConfig::cjk())
}

/// Calculate the display width of a string.
///
/// This measures by Unicode grapheme cluster so emoji ZWJ sequences, keycaps,
/// regional-indicator flags, variation selectors, and emoji modifiers occupy
/// the same number of terminal cells as the rendered cluster.
///
/// # Arguments
///
/// * `s` - The string to measure
/// * `config` - Width configuration settings
///
/// # Returns
///
/// The total display width in cells
pub fn str_width(s: &str, config: &WidthConfig) -> usize {
    UnicodeSegmentation::graphemes(s, true)
        .map(|grapheme| grapheme_width(grapheme, config))
        .sum()
}

fn grapheme_width(grapheme: &str, config: &WidthConfig) -> usize {
    if grapheme.is_empty() {
        return 0;
    }

    let regional_indicator_count = grapheme
        .chars()
        .filter(|c| crate::grapheme::is_regional_indicator(*c))
        .count();
    if crate::grapheme::has_emoji_presentation_selector(grapheme)
        || crate::grapheme::has_emoji_modifier_sequence(grapheme)
    {
        return 2;
    }

    let has_modern_emoji_cluster = regional_indicator_count == 2
        || crate::grapheme::is_keycap_sequence(grapheme)
        || crate::grapheme::is_emoji_tag_sequence(grapheme)
        || (grapheme.contains('\u{200D}')
            && grapheme
                .chars()
                .any(crate::grapheme::is_emoji_sequence_codepoint));
    if config.unicode_version != UnicodeVersion::Unicode8 && has_modern_emoji_cluster {
        return 2;
    }

    // iTerm2's Unicode 8 compatibility path assigns a composed cluster the
    // width of its base character. This keeps legacy emoji and flag clusters
    // single-cell unless an explicit emoji-presentation modifier above forces
    // two cells.
    if config.unicode_version == UnicodeVersion::Unicode8 && has_modern_emoji_cluster {
        return grapheme
            .chars()
            .find_map(|c| {
                let width = char_width(c, config);
                (width > 0).then_some(width)
            })
            .unwrap_or(0);
    }

    grapheme.chars().map(|c| char_width(c, config)).sum()
}

/// Calculate the display width of a string with CJK ambiguous width.
///
/// This is a convenience function that uses `AmbiguousWidth::Wide`.
pub fn str_width_cjk(s: &str) -> usize {
    str_width(s, &WidthConfig::cjk())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_unicode_version_default() {
        let version = UnicodeVersion::default();
        assert!(version.is_auto());
    }

    #[test]
    fn test_unicode_version_tuple() {
        assert_eq!(UnicodeVersion::Unicode8.version_tuple(), Some((8, 0)));
        assert_eq!(UnicodeVersion::Unicode9.version_tuple(), Some((9, 0)));
        assert_eq!(UnicodeVersion::Unicode15_1.version_tuple(), Some((15, 1)));
        assert_eq!(UnicodeVersion::Auto.version_tuple(), None);
    }

    #[test]
    fn test_unicode_version_string() {
        assert_eq!(UnicodeVersion::Unicode8.version_string(), "8.0");
        assert_eq!(UnicodeVersion::Unicode9.version_string(), "9.0");
        assert_eq!(UnicodeVersion::Unicode15_1.version_string(), "15.1");
        assert_eq!(UnicodeVersion::Auto.version_string(), "auto");
    }

    #[test]
    fn test_ambiguous_width_default() {
        let width = AmbiguousWidth::default();
        assert!(width.is_narrow());
        assert_eq!(width.width(), 1);
    }

    #[test]
    fn test_ambiguous_width_wide() {
        let width = AmbiguousWidth::Wide;
        assert!(width.is_wide());
        assert_eq!(width.width(), 2);
    }

    #[test]
    fn test_width_config_default() {
        let config = WidthConfig::default();
        assert!(config.unicode_version.is_auto());
        assert!(config.ambiguous_width.is_narrow());
    }

    #[test]
    fn test_width_config_cjk() {
        let config = WidthConfig::cjk();
        assert!(config.unicode_version.is_auto());
        assert!(config.ambiguous_width.is_wide());
    }

    #[test]
    fn test_width_config_western() {
        let config = WidthConfig::western();
        assert!(config.unicode_version.is_auto());
        assert!(config.ambiguous_width.is_narrow());
    }

    #[test]
    fn test_char_width_ascii() {
        let config = WidthConfig::default();
        assert_eq!(char_width('A', &config), 1);
        assert_eq!(char_width('z', &config), 1);
        assert_eq!(char_width('0', &config), 1);
        assert_eq!(char_width(' ', &config), 1);
    }

    #[test]
    fn test_char_width_cjk_characters() {
        let config = WidthConfig::default();
        // CJK Unified Ideographs
        assert_eq!(char_width('\u{4E00}', &config), 2); // 一
        assert_eq!(char_width('\u{9FFF}', &config), 2);
        // Hiragana
        assert_eq!(char_width('\u{3042}', &config), 2); // あ
                                                        // Katakana
        assert_eq!(char_width('\u{30A2}', &config), 2); // ア
    }

    #[test]
    fn test_char_width_emoji() {
        let config = WidthConfig::default();
        // Basic emoji
        assert_eq!(char_width('\u{1F600}', &config), 2); // 😀
        assert_eq!(char_width('\u{1F44D}', &config), 2); // 👍
    }

    #[test]
    fn test_unicode8_and_unicode9_emoji_width_contract() {
        let unicode8 = WidthConfig::new(UnicodeVersion::Unicode8, AmbiguousWidth::Narrow);
        let unicode8_cjk = WidthConfig::new(UnicodeVersion::Unicode8, AmbiguousWidth::Wide);
        let unicode9 = WidthConfig::new(UnicodeVersion::Unicode9, AmbiguousWidth::Narrow);

        // U+2615 was ambiguous in Unicode 8 and wide in Unicode 9.
        assert_eq!(char_width('☕', &unicode8), 1);
        assert_eq!(char_width('☕', &unicode8_cjk), 2);
        assert_eq!(char_width('☕', &unicode9), 2);

        // CJK wide/full-width assignments remain two cells in either mode.
        assert_eq!(char_width('界', &unicode8), 2);
        assert_eq!(char_width('界', &unicode9), 2);

        // Terminal-font private-use behavior is a product-level override.
        assert_eq!(char_width('\u{E0B0}', &unicode8_cjk), 1);
    }

    #[test]
    fn test_unicode8_composed_emoji_uses_base_width_unless_vs16_forces_emoji() {
        let unicode8 = WidthConfig::new(UnicodeVersion::Unicode8, AmbiguousWidth::Narrow);
        let unicode9 = WidthConfig::new(UnicodeVersion::Unicode9, AmbiguousWidth::Narrow);

        assert_eq!(str_width("🇺🇸", &unicode8), 1);
        assert_eq!(str_width("👨‍💻", &unicode8), 1);
        assert_eq!(str_width("1\u{20E3}", &unicode8), 1);
        assert_eq!(
            str_width(
                "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
                &unicode8
            ),
            1
        );
        assert_eq!(str_width("☕", &unicode8), 1);
        assert_eq!(str_width("☕️", &unicode8), 2);
        assert_eq!(str_width("🇺🇸", &unicode9), 2);
        assert_eq!(str_width("👨‍💻", &unicode9), 2);
        assert_eq!(str_width("1\u{20E3}", &unicode9), 2);
    }

    #[test]
    fn test_char_width_private_use_nerd_font_icons_are_narrow() {
        let config = WidthConfig::default();

        assert!(is_private_use('\u{E0B0}'));
        assert!(is_private_use('\u{F08C7}'));
        assert!(is_private_use('\u{100000}'));
        assert_eq!(char_width('\u{E0B0}', &config), 1);
        assert_eq!(char_width('\u{F08C7}', &config), 1);
        assert_eq!(char_width('\u{100000}', &config), 1);
    }

    #[test]
    fn test_char_width_control_characters() {
        let config = WidthConfig::default();
        // Control characters have width 0
        assert_eq!(char_width('\x00', &config), 0);
        assert_eq!(char_width('\x1B', &config), 0); // ESC
        assert_eq!(char_width('\n', &config), 0);
        assert_eq!(char_width('\r', &config), 0);
    }

    #[test]
    fn test_char_width_zero_width_format_characters() {
        let config = WidthConfig::default();
        assert_eq!(char_width('\u{00AD}', &config), 0); // SOFT HYPHEN
        assert_eq!(char_width('\u{200B}', &config), 0); // ZERO WIDTH SPACE
        assert_eq!(char_width('\u{200C}', &config), 0); // ZERO WIDTH NON-JOINER
        assert_eq!(char_width('\u{200E}', &config), 0); // LEFT-TO-RIGHT MARK
        assert_eq!(char_width('\u{2060}', &config), 0); // WORD JOINER
        assert_eq!(char_width('\u{FEFF}', &config), 0); // ZERO WIDTH NO-BREAK SPACE
        assert_eq!(char_width('\u{1BCA0}', &config), 0); // SHORTHAND FORMAT LETTER OVERLAP
        assert_eq!(char_width('\u{E0001}', &config), 0); // LANGUAGE TAG
        assert_eq!(
            str_width(
                "a\u{00AD}\u{200B}\u{200C}\u{200E}\u{2060}\u{FEFF}\u{1BCA0}\u{E0001}b",
                &config
            ),
            2
        );
    }

    #[test]
    fn test_char_width_combining_characters() {
        let config = WidthConfig::default();
        // Combining characters have width 0
        assert_eq!(char_width('\u{0301}', &config), 0); // Combining acute accent
        assert_eq!(char_width('\u{0300}', &config), 0); // Combining grave accent
        assert_eq!(char_width('\u{1F3FD}', &config), 0); // Skin tone modifier
    }

    #[test]
    fn test_ambiguous_width_greek() {
        // Greek alpha is East Asian Ambiguous
        let narrow_config = WidthConfig::default();
        let wide_config = WidthConfig::cjk();

        // With narrow config, Greek alpha should be 1
        assert_eq!(char_width('\u{03B1}', &narrow_config), 1); // α

        // With wide config, Greek alpha should be 2
        assert_eq!(char_width('\u{03B1}', &wide_config), 2);
    }

    #[test]
    fn test_ambiguous_width_cyrillic() {
        // Some Cyrillic letters are East Asian Ambiguous
        let narrow_config = WidthConfig::default();
        let wide_config = WidthConfig::cjk();

        assert_eq!(char_width('\u{0410}', &narrow_config), 1); // А (Cyrillic A)
        assert_eq!(char_width('\u{0410}', &wide_config), 2);
    }

    #[test]
    fn test_ambiguous_width_box_drawing() {
        // Box drawing characters are East Asian Ambiguous
        let narrow_config = WidthConfig::default();
        let wide_config = WidthConfig::cjk();

        assert_eq!(char_width('\u{2500}', &narrow_config), 1); // ─
        assert_eq!(char_width('\u{2500}', &wide_config), 2);
    }

    #[test]
    fn test_str_width_ascii() {
        let config = WidthConfig::default();
        assert_eq!(str_width("hello", &config), 5);
        assert_eq!(str_width("", &config), 0);
    }

    #[test]
    fn test_str_width_mixed() {
        let config = WidthConfig::default();
        // "a" (1) + CJK char (2) + "b" (1) = 4
        assert_eq!(str_width("a\u{4E00}b", &config), 4);
    }

    #[test]
    fn test_str_width_grapheme_clusters() {
        let config = WidthConfig::default();

        // Emoji presentation variation selector should reserve a two-cell glyph.
        assert_eq!(str_width("⚠️", &config), 2);
        assert_eq!(str_width("✈️", &config), 2);

        // Text presentation variation selector should not force emoji width.
        assert_eq!(str_width("✈︎", &config), 1);

        // Complex emoji clusters render as one two-cell terminal glyph.
        assert_eq!(str_width("👍🏽", &config), 2);
        assert_eq!(str_width("a🏽", &config), 1);
        assert_eq!(str_width("\u{1F3FD}", &config), 0);
        assert_eq!(str_width("👨‍💻", &config), 2);
        assert_eq!(str_width("👨‍👩‍👧‍👦", &config), 2);
        assert_eq!(str_width("🏳️‍🌈", &config), 2);
        assert_eq!(str_width("a\u{200D}", &config), 1);
        assert_eq!(str_width("a\u{200D}b", &config), 2);
        assert_eq!(str_width("🇺🇸", &config), 2);
        assert_eq!(str_width("1️⃣", &config), 2);
        assert_eq!(str_width("1\u{20E3}", &config), 2);
        assert_eq!(str_width("#\u{20E3}", &config), 2);
        assert_eq!(str_width("*\u{20E3}", &config), 2);
        assert_eq!(
            str_width(
                "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
                &config
            ),
            2
        );
    }

    #[test]
    fn test_str_width_cjk_function() {
        // Test the convenience function
        assert_eq!(str_width_cjk("a\u{03B1}b"), 4); // "a" + Greek alpha (wide) + "b"
    }

    #[test]
    fn test_char_width_cjk_function() {
        assert_eq!(char_width_cjk('\u{03B1}'), 2); // Greek alpha with CJK width
    }

    #[test]
    fn test_is_east_asian_ambiguous() {
        // Test some known ambiguous characters
        assert!(is_east_asian_ambiguous('\u{00A1}')); // INVERTED EXCLAMATION MARK
        assert!(is_east_asian_ambiguous('\u{03B1}')); // Greek alpha
        assert!(is_east_asian_ambiguous('\u{0410}')); // Cyrillic A
        assert!(is_east_asian_ambiguous('\u{2500}')); // Box drawing

        // Test non-ambiguous characters
        assert!(!is_east_asian_ambiguous('A'));
        assert!(!is_east_asian_ambiguous('a'));
        assert!(!is_east_asian_ambiguous('\u{4E00}')); // CJK - wide, not ambiguous
    }

    #[test]
    fn test_serde_roundtrip() {
        let config = WidthConfig::new(UnicodeVersion::Unicode15, AmbiguousWidth::Wide);
        let json = serde_json::to_string(&config).unwrap();
        let deserialized: WidthConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(config, deserialized);
    }

    #[test]
    fn test_serde_default_values() {
        // Test that missing fields use defaults
        let json = "{}";
        let config: WidthConfig = serde_json::from_str(json).unwrap();
        assert!(config.unicode_version.is_auto());
        assert!(config.ambiguous_width.is_narrow());
    }
}
