/// Utilities for handling grapheme clusters, emoji sequences, and Unicode modifiers
/// Check if a character is a variation selector.
///
/// Variation selectors control whether a character is rendered as text or emoji:
/// - U+FE0E (VS15) = Text style
/// - U+FE0F (VS16) = Emoji style
/// - U+E0100-U+E01EF = Variation Selectors Supplement
///
/// Examples:
/// - ⚠ (U+26A0) + U+FE0E = ⚠ (text style, black & white)
/// - ⚠ (U+26A0) + U+FE0F = ⚠️ (emoji style, colored)
#[inline]
pub fn is_variation_selector(c: char) -> bool {
    let code = c as u32;
    (0xFE00..=0xFE0F).contains(&code) || (0xE0100..=0xE01EF).contains(&code)
}

/// Check if a character is a Zero Width Joiner (U+200D)
///
/// ZWJ is used to combine multiple emoji into a single glyph:
/// - 👨‍👩‍👧‍👦 = MAN + ZWJ + WOMAN + ZWJ + GIRL + ZWJ + BOY
/// - 🏳️‍🌈 = WHITE FLAG + ZWJ + RAINBOW
#[inline]
pub fn is_zwj(c: char) -> bool {
    c == '\u{200D}'
}

/// Check if a character is a zero-width Unicode format control.
///
/// These Default_Ignorable / Cf controls affect shaping, joining, or direction
/// but should not consume terminal columns. They are kept with the preceding
/// cell when possible so copy/render paths preserve the original text without
/// shifting following glyphs.
#[inline]
pub fn is_zero_width_format(c: char) -> bool {
    let code = c as u32;
    matches!(
        code,
        0x00AD | // SOFT HYPHEN
        0x061C | // ARABIC LETTER MARK
        0x180E | // MONGOLIAN VOWEL SEPARATOR
        0x200B..=0x200C | // ZERO WIDTH SPACE, ZERO WIDTH NON-JOINER
        0x200E..=0x200F | // LEFT-TO-RIGHT / RIGHT-TO-LEFT MARK
        0x202A..=0x202E | // Bidirectional embedding/override controls
        0x2060..=0x2064 | // WORD JOINER and invisible operators
        0x2066..=0x206F | // Bidirectional isolate and deprecated format controls
        0xFEFF | // ZERO WIDTH NO-BREAK SPACE / BOM
        0xFFF9..=0xFFFB | // Interlinear annotation controls
        0x1BCA0..=0x1BCA3 | // Shorthand format controls
        0xE0001 // LANGUAGE TAG
    )
}

/// Check if a character is a skin tone modifier (U+1F3FB-U+1F3FF)
///
/// Skin tone modifiers (Emoji Modifier Fitzpatrick Type) modify the preceding emoji:
/// - U+1F3FB = Light skin tone
/// - U+1F3FC = Medium-light skin tone
/// - U+1F3FD = Medium skin tone
/// - U+1F3FE = Medium-dark skin tone
/// - U+1F3FF = Dark skin tone
///
/// Example: 👋🏽 = WAVING HAND (U+1F44B) + MEDIUM SKIN TONE (U+1F3FD)
#[inline]
pub fn is_skin_tone_modifier(c: char) -> bool {
    let code = c as u32;
    (0x1F3FB..=0x1F3FF).contains(&code)
}

/// Check if a character is an Emoji_Modifier_Base codepoint.
///
/// Skin tone modifiers only form emoji-width clusters after these bases. Treating
/// every preceding grapheme as a modifier base makes plain text such as `a🏽`
/// occupy emoji width and shift terminal columns.
#[inline]
pub fn is_emoji_modifier_base(c: char) -> bool {
    let code = c as u32;
    matches!(
        code,
        0x261D | 0x26F9 | 0x270A..=0x270D |
        0x1F385 |
        0x1F3C2..=0x1F3C4 | 0x1F3C7 | 0x1F3CA..=0x1F3CC |
        0x1F442..=0x1F443 | 0x1F446..=0x1F450 |
        0x1F466..=0x1F469 | 0x1F46E | 0x1F470..=0x1F478 |
        0x1F47C | 0x1F481..=0x1F483 | 0x1F485..=0x1F487 |
        0x1F4AA |
        0x1F574..=0x1F575 | 0x1F57A | 0x1F590 | 0x1F595..=0x1F596 |
        0x1F645..=0x1F647 | 0x1F64B..=0x1F64F |
        0x1F6A3 | 0x1F6B4..=0x1F6B6 | 0x1F6C0 | 0x1F6CC |
        0x1F90C | 0x1F90F | 0x1F918..=0x1F91F | 0x1F926 |
        0x1F930..=0x1F939 | 0x1F93D..=0x1F93E |
        0x1F977 |
        0x1F9B5..=0x1F9B6 | 0x1F9B8..=0x1F9B9 | 0x1F9BB |
        0x1F9CD..=0x1F9CF | 0x1F9D1..=0x1F9DD |
        0x1FAC3..=0x1FAC5 | 0x1FAF0..=0x1FAF8
    )
}

/// Check if a grapheme contains a skin tone modifier attached to an eligible
/// emoji modifier base.
#[inline]
pub fn has_emoji_modifier_sequence(grapheme: &str) -> bool {
    let mut last_base = None;
    for c in grapheme.chars() {
        if is_skin_tone_modifier(c) {
            return last_base.is_some_and(is_emoji_modifier_base);
        }
        if is_variation_selector(c) || is_combining_mark(c) || is_zwj(c) || is_emoji_tag(c) {
            continue;
        }
        last_base = Some(c);
    }
    false
}

/// Check if a character is a Regional Indicator Symbol (U+1F1E6-U+1F1FF)
///
/// Regional indicators are used in pairs to form flag emoji:
/// - 🇺🇸 = U+1F1FA (🇺) + U+1F1F8 (🇸)
/// - 🇬🇧 = U+1F1EC (🇬) + U+1F1E7 (🇧)
#[inline]
pub fn is_regional_indicator(c: char) -> bool {
    let code = c as u32;
    (0x1F1E6..=0x1F1FF).contains(&code)
}

/// Check if a character is an emoji tag character (U+E0020-U+E007F).
///
/// Emoji tag sequences are used by subdivision flags such as Scotland:
/// BLACK FLAG + tag letters + CANCEL TAG.
#[inline]
pub fn is_emoji_tag(c: char) -> bool {
    let code = c as u32;
    (0xE0020..=0xE007F).contains(&code)
}

/// Check if a grapheme is a complete emoji tag sequence used for subdivision flags.
///
/// Valid subdivision flag emoji are encoded as BLACK FLAG followed by one or more
/// tag characters and a final CANCEL TAG. Stray tag characters are default
/// ignorable text modifiers and must not force unrelated text to emoji width.
#[inline]
pub fn is_emoji_tag_sequence(grapheme: &str) -> bool {
    let mut chars = grapheme.chars();
    if chars.next() != Some('\u{1F3F4}') {
        return false;
    }

    let mut saw_tag_spec = false;
    while let Some(c) = chars.next() {
        if c == '\u{E007F}' {
            return saw_tag_spec && chars.next().is_none();
        }
        if !is_emoji_tag(c) {
            return false;
        }
        saw_tag_spec = true;
    }

    false
}

/// Check if a character can participate in an emoji presentation sequence.
///
/// This intentionally covers the broad symbol and emoji ranges terminals need
/// for common RGI ZWJ sequences without treating arbitrary text joined by ZWJ
/// as a single emoji glyph.
#[inline]
pub fn is_emoji_sequence_codepoint(c: char) -> bool {
    let code = c as u32;
    matches!(
        code,
        0x2600..=0x27BF | // Misc symbols and Dingbats used in emoji sequences
        0x1F000..=0x1FFFF // Emoji blocks and newer emoji supplements
    )
}

/// Check if a character is a base that can request emoji presentation with VS16.
#[inline]
pub fn is_emoji_variation_base(c: char) -> bool {
    let code = c as u32;
    is_emoji_sequence_codepoint(c)
        || matches!(
            code,
            0x00A9 | 0x00AE | // copyright, registered
            0x203C | 0x2049 | // double exclamation, interrobang
            0x2122 | 0x2139 | // trademark, information
            0x2194..=0x2199 | 0x21A9..=0x21AA | // arrows
            0x231A..=0x231B | 0x2328 | 0x23CF |
            0x23E9..=0x23F3 | 0x23F8..=0x23FA |
            0x24C2 |
            0x25AA..=0x25AB | 0x25B6 | 0x25C0 | 0x25FB..=0x25FE |
            0x2934..=0x2935 |
            0x2B05..=0x2B07 | 0x2B1B..=0x2B1C | 0x2B50 | 0x2B55
        )
}

/// Check if a grapheme contains VS16 after an emoji-capable base.
#[inline]
pub fn has_emoji_presentation_selector(grapheme: &str) -> bool {
    let mut last_base = None;
    for c in grapheme.chars() {
        if c == '\u{FE0F}' {
            return last_base.is_some_and(is_emoji_variation_base);
        }
        if is_variation_selector(c) || is_combining_mark(c) {
            continue;
        }
        last_base = Some(c);
    }
    false
}

/// Check if a character can start an emoji keycap sequence.
#[inline]
pub fn is_keycap_base(c: char) -> bool {
    c.is_ascii_digit() || c == '#' || c == '*'
}

/// Check if a grapheme cluster is an emoji keycap sequence.
///
/// Unicode allows keycaps both with and without emoji variation selector:
/// - `1` + U+20E3
/// - `1` + U+FE0F + U+20E3
#[inline]
pub fn is_keycap_sequence(grapheme: &str) -> bool {
    let mut chars = grapheme.chars();
    let Some(base) = chars.next() else {
        return false;
    };
    if !is_keycap_base(base) {
        return false;
    }

    match (chars.next(), chars.next(), chars.next()) {
        (Some('\u{20E3}'), None, None) => true,
        (Some('\u{FE0F}'), Some('\u{20E3}'), None) => true,
        _ => false,
    }
}

/// Check if a character is a combining mark (diacritics, accents, etc.)
///
/// Combining marks modify the preceding base character.
/// This includes:
/// - Combining Diacritical Marks (U+0300-U+036F)
/// - Hebrew, Arabic, Indic, Southeast Asian, and other script marks
/// - Combining Marks for Symbols (U+20D0-U+20FF)
/// - And other Unicode combining character categories
#[inline]
pub fn is_combining_mark(c: char) -> bool {
    let code = c as u32;
    matches!(code,
        0x0300..=0x036F | // Combining Diacritical Marks
        0x0483..=0x0489 | // Cyrillic combining marks
        0x0591..=0x05BD | 0x05BF | 0x05C1..=0x05C2 | 0x05C4..=0x05C5 | 0x05C7 | // Hebrew marks
        0x0610..=0x061A | 0x064B..=0x065F | 0x0670 | 0x06D6..=0x06ED | // Arabic marks
        0x0711 | 0x0730..=0x074A | // Syriac marks
        0x07A6..=0x07B0 | 0x07EB..=0x07F3 | // Thaana and NKo marks
        0x0816..=0x0819 | 0x081B..=0x0823 | 0x0825..=0x0827 | 0x0829..=0x082D | // Samaritan marks
        0x0859..=0x085B | // Mandaic marks
        0x08D3..=0x08E1 | 0x08E3..=0x0902 | // Arabic extended and Indic inherited marks
        0x093A | 0x093C | 0x0941..=0x0948 | 0x094D | 0x0951..=0x0957 | 0x0962..=0x0963 | // Devanagari marks
        0x0981 | 0x09BC | 0x09CD | 0x09E2..=0x09E3 | // Bengali marks
        0x0A01..=0x0A02 | 0x0A3C | 0x0A41..=0x0A42 | 0x0A47..=0x0A48 | 0x0A4B..=0x0A4D | 0x0A51 | 0x0A70..=0x0A71 | 0x0A75 | // Gurmukhi marks
        0x0A81..=0x0A82 | 0x0ABC | 0x0AC1..=0x0AC5 | 0x0AC7..=0x0AC8 | 0x0ACD | 0x0AE2..=0x0AE3 | // Gujarati marks
        0x0B01 | 0x0B3C | 0x0B3F | 0x0B41..=0x0B44 | 0x0B4D | 0x0B55..=0x0B56 | 0x0B62..=0x0B63 | // Oriya marks
        0x0B82 | 0x0BC0 | 0x0BCD | // Tamil marks
        0x0C00 | 0x0C04 | 0x0C3C | 0x0C3E..=0x0C40 | 0x0C46..=0x0C48 | 0x0C4A..=0x0C4D | 0x0C55..=0x0C56 | 0x0C62..=0x0C63 | // Telugu marks
        0x0C81 | 0x0CBC | 0x0CBF | 0x0CC6 | 0x0CCC..=0x0CCD | 0x0CE2..=0x0CE3 | // Kannada marks
        0x0D00..=0x0D01 | 0x0D3B..=0x0D3C | 0x0D41..=0x0D44 | 0x0D4D | 0x0D62..=0x0D63 | // Malayalam marks
        0x0DCA | 0x0DD2..=0x0DD4 | 0x0DD6 | 0x0E31 | 0x0E34..=0x0E3A | 0x0E47..=0x0E4E | // Sinhala and Thai marks
        0x0EB1 | 0x0EB4..=0x0EBC | 0x0EC8..=0x0ECD | // Lao marks
        0x0F18..=0x0F19 | 0x0F35 | 0x0F37 | 0x0F39 | 0x0F71..=0x0F7E | 0x0F80..=0x0F84 | 0x0F86..=0x0F87 | // Tibetan marks
        0x0F8D..=0x0F97 | 0x0F99..=0x0FBC | 0x0FC6 | // Tibetan subjoined marks
        0x102D..=0x1030 | 0x1032..=0x1037 | 0x1039..=0x103A | 0x103D..=0x103E | 0x1058..=0x1059 | // Myanmar marks
        0x105E..=0x1060 | 0x1071..=0x1074 | 0x1082 | 0x1085..=0x1086 | 0x108D | 0x109D | // Myanmar extended marks
        0x135D..=0x135F | // Ethiopic marks
        0x1712..=0x1714 | 0x1732..=0x1734 | 0x1752..=0x1753 | 0x1772..=0x1773 | // Philippine script marks
        0x1AB0..=0x1AFF | // Combining Diacritical Marks Extended
        0x1B00..=0x1B03 | 0x1B34 | 0x1B36..=0x1B3A | 0x1B3C | 0x1B42 | 0x1B6B..=0x1B73 | // Balinese marks
        0x1B80..=0x1B81 | 0x1BA2..=0x1BA5 | 0x1BA8..=0x1BA9 | 0x1BAB..=0x1BAD | // Sundanese marks
        0x1BE6 | 0x1BE8..=0x1BE9 | 0x1BED | 0x1BEF..=0x1BF1 | // Batak marks
        0x1C2C..=0x1C33 | 0x1C36..=0x1C37 | // Lepcha marks
        0x1CD0..=0x1CD2 | 0x1CD4..=0x1CE0 | 0x1CE2..=0x1CE8 | 0x1CED | 0x1CF4 | 0x1CF8..=0x1CF9 | // Vedic marks
        0x1DC0..=0x1DFF | // Combining Diacritical Marks Supplement
        0x20D0..=0x20FF | // Combining Diacritical Marks for Symbols
        0xFE20..=0xFE2F   // Combining Half Marks
    )
}

/// Check if a grapheme cluster should be rendered with width 2 (wide character)
///
/// Wide emoji include:
/// - Regional indicator pairs (flags): 🇺🇸 🇬🇧
/// - ZWJ sequences: 👨‍👩‍👧‍👦 🏳️‍🌈
/// - Emoji with skin tone modifiers: 👋🏽 👍🏿
/// - Most emoji by default
///
/// # Arguments
///
/// * `grapheme` - The grapheme cluster to check
///
/// # Returns
///
/// true if the grapheme should occupy 2 cells, false if 1 cell
pub fn is_wide_grapheme(grapheme: &str) -> bool {
    // Regional Indicator pairs (flags) are always wide
    let regional_indicators: Vec<char> = grapheme
        .chars()
        .filter(|c| is_regional_indicator(*c))
        .collect();
    if regional_indicators.len() == 2 {
        return true;
    }

    // Emoji ZWJ sequences are wide. Plain-text ZWJ clusters such as "a\u{200D}"
    // stay narrow and are measured by their individual codepoints below.
    if grapheme.contains('\u{200D}') && grapheme.chars().any(is_emoji_sequence_codepoint) {
        return true;
    }

    // Emoji modifier sequences are wide only when the modifier follows an
    // eligible emoji modifier base.
    if has_emoji_modifier_sequence(grapheme) {
        return true;
    }

    // Complete emoji tag sequences (subdivision flags) are wide.
    if is_emoji_tag_sequence(grapheme) {
        return true;
    }

    // Keycap sequences are rendered as a single emoji glyph, including the
    // text/unqualified form without U+FE0F.
    if is_keycap_sequence(grapheme) {
        return true;
    }

    // Emoji-capable bases with VS16 request emoji presentation.
    if has_emoji_presentation_selector(grapheme) {
        return true;
    }

    // Fallback to unicode-width for other cases
    crate::unicode_width_config::str_width(
        grapheme,
        &crate::unicode_width_config::WidthConfig::default(),
    ) >= 2
}

/// Check if a grapheme cluster should be rendered with width 2 using a specific configuration
///
/// This variant allows specifying the width configuration for ambiguous characters.
///
/// # Arguments
///
/// * `grapheme` - The grapheme cluster to check
/// * `config` - The width configuration to use
///
/// # Returns
///
/// true if the grapheme should occupy 2 cells, false if 1 cell
pub fn is_wide_grapheme_with_config(
    grapheme: &str,
    config: &crate::unicode_width_config::WidthConfig,
) -> bool {
    // Regional Indicator pairs (flags) are always wide
    let regional_indicators: Vec<char> = grapheme
        .chars()
        .filter(|c| is_regional_indicator(*c))
        .collect();
    if regional_indicators.len() == 2 {
        return true;
    }

    // Emoji ZWJ sequences are wide. Plain-text ZWJ clusters such as "a\u{200D}"
    // stay narrow and are measured by their individual codepoints below.
    if grapheme.contains('\u{200D}') && grapheme.chars().any(is_emoji_sequence_codepoint) {
        return true;
    }

    // Emoji modifier sequences are wide only when the modifier follows an
    // eligible emoji modifier base.
    if has_emoji_modifier_sequence(grapheme) {
        return true;
    }

    // Complete emoji tag sequences (subdivision flags) are wide.
    if is_emoji_tag_sequence(grapheme) {
        return true;
    }

    // Keycap sequences are rendered as a single emoji glyph, including the
    // text/unqualified form without U+FE0F.
    if is_keycap_sequence(grapheme) {
        return true;
    }

    // Emoji-capable bases with VS16 request emoji presentation.
    if has_emoji_presentation_selector(grapheme) {
        return true;
    }

    // Use the configured width calculation
    crate::unicode_width_config::str_width(grapheme, config) >= 2
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_variation_selector_detection() {
        assert!(is_variation_selector('\u{FE0E}')); // Text style
        assert!(is_variation_selector('\u{FE0F}')); // Emoji style
        assert!(is_variation_selector('\u{E0100}')); // Supplement
        assert!(!is_variation_selector('a'));
        assert!(!is_variation_selector('⚠'));
    }

    #[test]
    fn test_zwj_detection() {
        assert!(is_zwj('\u{200D}'));
        assert!(!is_zwj('a'));
        assert!(!is_zwj(' '));
    }

    #[test]
    fn test_zero_width_format_detection() {
        assert!(is_zero_width_format('\u{200B}')); // ZERO WIDTH SPACE
        assert!(is_zero_width_format('\u{200C}')); // ZERO WIDTH NON-JOINER
        assert!(is_zero_width_format('\u{200E}')); // LEFT-TO-RIGHT MARK
        assert!(is_zero_width_format('\u{2060}')); // WORD JOINER
        assert!(is_zero_width_format('\u{FEFF}')); // ZERO WIDTH NO-BREAK SPACE
        assert!(!is_zero_width_format('\u{200D}')); // ZWJ has separate handling
        assert!(!is_zero_width_format('a'));
    }

    #[test]
    fn test_skin_tone_modifier_detection() {
        assert!(is_skin_tone_modifier('\u{1F3FB}')); // Light
        assert!(is_skin_tone_modifier('\u{1F3FC}')); // Medium-light
        assert!(is_skin_tone_modifier('\u{1F3FD}')); // Medium
        assert!(is_skin_tone_modifier('\u{1F3FE}')); // Medium-dark
        assert!(is_skin_tone_modifier('\u{1F3FF}')); // Dark
        assert!(!is_skin_tone_modifier('a'));
        assert!(!is_skin_tone_modifier('👋'));
    }

    #[test]
    fn test_emoji_modifier_base_detection() {
        assert!(is_emoji_modifier_base('👋'));
        assert!(is_emoji_modifier_base('👍'));
        assert!(is_emoji_modifier_base('🧑'));
        assert!(is_emoji_modifier_base('☝'));
        assert!(!is_emoji_modifier_base('a'));
        assert!(!is_emoji_modifier_base('🏳'));
        assert!(!is_emoji_modifier_base('\u{1F3FD}'));
    }

    #[test]
    fn test_emoji_modifier_sequence_detection() {
        assert!(has_emoji_modifier_sequence("👋🏽"));
        assert!(has_emoji_modifier_sequence("☝️🏽"));
        assert!(has_emoji_modifier_sequence("🧑🏿"));
        assert!(!has_emoji_modifier_sequence("a🏽"));
        assert!(!has_emoji_modifier_sequence("🏳🏽"));
        assert!(!has_emoji_modifier_sequence("\u{1F3FD}"));
    }

    #[test]
    fn test_regional_indicator_detection() {
        assert!(is_regional_indicator('\u{1F1FA}')); // 🇺
        assert!(is_regional_indicator('\u{1F1F8}')); // 🇸
        assert!(!is_regional_indicator('a'));
    }

    #[test]
    fn test_emoji_tag_detection() {
        assert!(is_emoji_tag('\u{E0067}')); // TAG LATIN SMALL LETTER G
        assert!(is_emoji_tag('\u{E007F}')); // CANCEL TAG
        assert!(!is_emoji_tag('g'));
    }

    #[test]
    fn test_emoji_tag_sequence_detection() {
        let scotland_flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}";

        assert!(is_emoji_tag_sequence(scotland_flag));
        assert!(!is_emoji_tag_sequence("a\u{E0067}"));
        assert!(!is_emoji_tag_sequence("\u{1F3F4}\u{E0067}"));
        assert!(!is_emoji_tag_sequence("\u{1F3F4}\u{E007F}"));
        assert!(!is_emoji_tag_sequence("\u{1F3F4}\u{E0067}\u{E007F}x"));
    }

    #[test]
    fn test_keycap_sequence_detection() {
        assert!(is_keycap_sequence("1\u{20E3}"));
        assert!(is_keycap_sequence("#\u{20E3}"));
        assert!(is_keycap_sequence("*\u{20E3}"));
        assert!(is_keycap_sequence("1\u{FE0F}\u{20E3}"));
        assert!(!is_keycap_sequence("a\u{20E3}"));
        assert!(!is_keycap_sequence("1\u{FE0E}\u{20E3}"));
    }

    #[test]
    fn test_combining_mark_detection() {
        assert!(is_combining_mark('\u{0301}')); // Combining acute accent
        assert!(is_combining_mark('\u{0300}')); // Combining grave accent
        assert!(is_combining_mark('\u{05C1}')); // Hebrew shin dot
        assert!(is_combining_mark('\u{0651}')); // Arabic shadda
        assert!(is_combining_mark('\u{093C}')); // Devanagari nukta
        assert!(!is_combining_mark('a'));
        assert!(!is_combining_mark('\u{200B}')); // Zero width space is format, not a mark
    }

    #[test]
    fn test_wide_grapheme_detection() {
        // ZWJ sequences
        assert!(is_wide_grapheme("👨‍👩‍👧‍👦")); // Family
        assert!(!is_wide_grapheme("a\u{200D}"));

        // Skin tone modifiers
        assert!(is_wide_grapheme("👋🏽")); // Waving hand with medium skin tone
        assert!(!is_wide_grapheme("a🏽"));

        // Variation selectors
        assert!(is_wide_grapheme("⚠️")); // Warning with emoji variation

        // Keycaps without emoji variation selector
        assert!(is_wide_grapheme("1\u{20E3}"));

        // Emoji tag sequence for subdivision flags
        assert!(is_wide_grapheme(
            "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        ));
        assert!(!is_wide_grapheme("a\u{E0067}"));

        // ASCII should not be wide
        assert!(!is_wide_grapheme("a"));
    }
}
