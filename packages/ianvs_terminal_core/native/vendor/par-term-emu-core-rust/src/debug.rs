use parking_lot::Mutex;
/// Comprehensive debugging infrastructure for par-term-emu
///
/// Controlled by DEBUG_LEVEL environment variable:
/// - 0 or unset: No debugging
/// - 1: Errors only
/// - 2: Info level (screen switches, device queries)
/// - 3: Debug level (VT sequences, buffer changes)
/// - 4: Trace level (every operation, buffer snapshots)
///
/// All output goes to /tmp/par_term_emu_core_rust_debug_rust.log on Unix/macOS,
/// or %TEMP%\par_term_emu_core_rust_debug_rust.log on Windows.
/// This avoids breaking TUI apps by keeping debug output separate from stdout/stderr.
use std::fmt;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

/// Debug level configuration
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum DebugLevel {
    Off = 0,
    Error = 1,
    Info = 2,
    Debug = 3,
    Trace = 4,
}

impl DebugLevel {
    fn from_env() -> Self {
        match std::env::var("DEBUG_LEVEL") {
            Ok(val) => match val.trim().parse::<u8>() {
                Ok(0) => DebugLevel::Off,
                Ok(1) => DebugLevel::Error,
                Ok(2) => DebugLevel::Info,
                Ok(3) => DebugLevel::Debug,
                Ok(4) => DebugLevel::Trace,
                _ => DebugLevel::Off,
            },
            Err(_) => DebugLevel::Off,
        }
    }
}

/// Global debug logger
struct DebugLogger {
    level: DebugLevel,
    file: Option<std::fs::File>,
}

impl DebugLogger {
    fn new() -> Self {
        let level = DebugLevel::from_env();

        let file = if level != DebugLevel::Off {
            // Rust uses separate log file from Python
            // Use /tmp on Unix/macOS for consistency with documentation
            // Use %TEMP% on Windows
            #[cfg(unix)]
            let log_path = std::path::PathBuf::from("/tmp/par_term_emu_core_rust_debug_rust.log");
            #[cfg(windows)]
            let log_path = std::env::temp_dir().join("par_term_emu_core_rust_debug_rust.log");

            match OpenOptions::new()
                .write(true)
                .truncate(true)
                .create(true)
                .open(&log_path)
            {
                Ok(f) => {
                    // Write header
                    let mut logger = DebugLogger {
                        level,
                        file: Some(f),
                    };
                    logger.write_raw(&format!(
                        "\n{}\npar-term-emu Rust debug session started at {} (level={:?})\n{}\n",
                        "=".repeat(80),
                        get_timestamp(),
                        level,
                        "=".repeat(80)
                    ));
                    return logger;
                }
                Err(_e) => {
                    // Silently fail if log file can't be opened
                    // This prevents debug output from interfering with TUI applications
                    None
                }
            }
        } else {
            None
        };

        DebugLogger { level, file }
    }

    fn write_raw(&mut self, msg: &str) {
        if let Some(ref mut file) = self.file {
            let _ = file.write_all(msg.as_bytes());
            let _ = file.flush();
        }
    }

    fn log(&mut self, level: DebugLevel, category: &str, msg: &str) {
        if level <= self.level {
            let timestamp = get_timestamp();
            let level_str = match level {
                DebugLevel::Error => "ERROR",
                DebugLevel::Info => "INFO ",
                DebugLevel::Debug => "DEBUG",
                DebugLevel::Trace => "TRACE",
                DebugLevel::Off => return,
            };
            self.write_raw(&format!(
                "[{}] [{}] [{}] {}\n",
                timestamp, level_str, category, msg
            ));
        }
    }
}

static LOGGER: OnceLock<Mutex<DebugLogger>> = OnceLock::new();

fn get_logger() -> &'static Mutex<DebugLogger> {
    LOGGER.get_or_init(|| Mutex::new(DebugLogger::new()))
}

fn get_timestamp() -> String {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
    format!("{}.{:06}", now.as_secs(), now.subsec_micros())
}

/// Check if debugging is enabled at given level
pub fn is_enabled(level: DebugLevel) -> bool {
    let logger = get_logger().lock();
    level <= logger.level
}

/// Log a message at specified level
pub fn log(level: DebugLevel, category: &str, msg: &str) {
    let mut logger = get_logger().lock();
    logger.log(level, category, msg);
}

/// Log formatted message
pub fn logf(level: DebugLevel, category: &str, args: fmt::Arguments) {
    if is_enabled(level) {
        log(level, category, &format!("{}", args));
    }
}

// Convenience macros for logging
#[macro_export]
macro_rules! debug_error {
    ($category:expr, $($arg:tt)*) => {
        $crate::debug::logf($crate::debug::DebugLevel::Error, $category, format_args!($($arg)*))
    };
}

#[macro_export]
macro_rules! debug_info {
    ($category:expr, $($arg:tt)*) => {
        $crate::debug::logf($crate::debug::DebugLevel::Info, $category, format_args!($($arg)*))
    };
}

#[macro_export]
macro_rules! debug_log {
    ($category:expr, $($arg:tt)*) => {
        $crate::debug::logf($crate::debug::DebugLevel::Debug, $category, format_args!($($arg)*))
    };
}

#[macro_export]
macro_rules! debug_trace {
    ($category:expr, $($arg:tt)*) => {
        $crate::debug::logf($crate::debug::DebugLevel::Trace, $category, format_args!($($arg)*))
    };
}

/// VT sequence logging
pub fn log_vt_input(bytes: &[u8]) {
    if is_enabled(DebugLevel::Debug) {
        log(
            DebugLevel::Debug,
            "VT_INPUT",
            &format!("input_bytes={}", bytes.len()),
        );
    }
}

/// Screen switch logging
pub fn log_screen_switch(to_alt: bool, reason: &str) {
    if is_enabled(DebugLevel::Info) {
        log(
            DebugLevel::Info,
            "SCREEN_SWITCH",
            &format!(
                "switched to {} screen ({})",
                if to_alt { "ALTERNATE" } else { "PRIMARY" },
                reason
            ),
        );
    }
}

/// Device query logging
pub fn log_device_query(query: &str, response: &[u8]) {
    if is_enabled(DebugLevel::Info) {
        log(
            DebugLevel::Info,
            "DEVICE_QUERY",
            &format!("query_class={query} response_bytes={}", response.len()),
        );
    }
}

/// Buffer snapshot logging
pub fn log_buffer_snapshot(label: &str, rows: usize, cols: usize, content: &str) {
    if is_enabled(DebugLevel::Trace) {
        let mut logger = get_logger().lock();
        logger.write_raw(&format!(
            "{}\n",
            buffer_snapshot_log_message(label, rows, cols, content)
        ));
    }
}

fn buffer_snapshot_log_message(label: &str, rows: usize, cols: usize, content: &str) -> String {
    let non_empty_cells = content
        .chars()
        .filter(|character| !matches!(character, ' ' | '\r' | '\n'))
        .count();
    format!(
        "BUFFER SNAPSHOT: label_bytes={} rows={} cols={} content_bytes={} non_empty_cells={}",
        label.len(),
        rows,
        cols,
        content.len(),
        non_empty_cells
    )
}

/// Generation counter logging
pub fn log_generation_change(old: u64, new: u64, reason: &str) {
    if is_enabled(DebugLevel::Debug) {
        log(
            DebugLevel::Debug,
            "GENERATION",
            &format!("counter changed: {} -> {} ({})", old, new, reason),
        );
    }
}

/// CSI dispatch logging
pub fn log_csi_dispatch(params: &[i64], intermediates: &[u8], final_byte: char) {
    if is_enabled(DebugLevel::Debug) {
        let params_str: String = params
            .iter()
            .map(|p| p.to_string())
            .collect::<Vec<_>>()
            .join(";");
        let inter_str: String = intermediates.iter().map(|&b| b as char).collect();
        log(
            DebugLevel::Debug,
            "CSI",
            &format!(
                "CSI {}{}{}  (params=[{}])",
                if inter_str.is_empty() { "" } else { &inter_str },
                final_byte,
                "",
                params_str
            ),
        );
    }
}

/// OSC dispatch logging
pub fn log_osc_dispatch(params: &[&[u8]]) {
    if is_enabled(DebugLevel::Debug) {
        log(DebugLevel::Debug, "OSC", &osc_dispatch_log_message(params));
    }
}

fn osc_dispatch_log_message(params: &[&[u8]]) -> String {
    let command = params
        .first()
        .and_then(|value| std::str::from_utf8(value).ok())
        .filter(|value| value.bytes().all(|byte| byte.is_ascii_digit()))
        .unwrap_or("invalid");
    let payload_bytes = params
        .iter()
        .skip(1)
        .map(|parameter| parameter.len())
        .sum::<usize>();
    format!(
        "OSC command={} params={} payload_bytes={}",
        command,
        params.len().saturating_sub(1),
        payload_bytes
    )
}

/// ESC dispatch logging
pub fn log_esc_dispatch(intermediates: &[u8], final_byte: char) {
    if is_enabled(DebugLevel::Debug) {
        let inter_str: String = intermediates.iter().map(|&b| b as char).collect();
        log(
            DebugLevel::Debug,
            "ESC",
            &format!("ESC {}{}", inter_str, final_byte),
        );
    }
}

/// Print character logging
pub fn log_print(c: char, col: usize, row: usize) {
    if is_enabled(DebugLevel::Trace) {
        log(DebugLevel::Trace, "PRINT", &print_log_message(c, col, row));
    }
}

fn print_log_message(c: char, col: usize, row: usize) -> String {
    let category = if c.is_ascii_whitespace() {
        "ascii_whitespace"
    } else if c.is_ascii() {
        "ascii"
    } else if c.is_whitespace() {
        "unicode_whitespace"
    } else {
        "unicode"
    };
    let display_width = unicode_width::UnicodeWidthChar::width(c).unwrap_or(0);
    format!(
        "char_class={} display_width={} at ({},{})",
        category, display_width, col, row
    )
}

/// Execute control code logging
pub fn log_execute(byte: u8) {
    if is_enabled(DebugLevel::Debug) {
        let name = match byte {
            0x07 => "BEL",
            0x08 => "BS",
            0x09 => "HT",
            0x0A => "LF",
            0x0B => "VT",
            0x0C => "FF",
            0x0D => "CR",
            0x0E => "SO",
            0x0F => "SI",
            _ => "???",
        };
        log(
            DebugLevel::Debug,
            "EXECUTE",
            &format!("control=0x{:02X} ({})", byte, name),
        );
    }
}

/// Cursor movement logging
pub fn log_cursor_move(
    from_col: usize,
    from_row: usize,
    to_col: usize,
    to_row: usize,
    reason: &str,
) {
    if is_enabled(DebugLevel::Trace) {
        log(
            DebugLevel::Trace,
            "CURSOR",
            &format!(
                "moved ({},{}) -> ({},{}) [{}]",
                from_col, from_row, to_col, to_row, reason
            ),
        );
    }
}

/// Scroll operation logging
pub fn log_scroll(direction: &str, region_top: usize, region_bottom: usize, lines: usize) {
    if is_enabled(DebugLevel::Debug) {
        log(
            DebugLevel::Debug,
            "SCROLL",
            &format!(
                "{} {} lines in region [{}..{}]",
                direction, lines, region_top, region_bottom
            ),
        );
    }
}

/// Grid operation logging
pub fn log_grid_op(operation: &str, details: &str) {
    if is_enabled(DebugLevel::Debug) {
        log(
            DebugLevel::Debug,
            "GRID_OP",
            &format!("{}: {}", operation, details),
        );
    }
}

/// PTY operation logging
pub fn log_pty_read(bytes_read: usize) {
    if is_enabled(DebugLevel::Trace) {
        log(
            DebugLevel::Trace,
            "PTY_READ",
            &format!("read {} bytes from PTY", bytes_read),
        );
    }
}

pub fn log_pty_write(bytes: &[u8]) {
    if is_enabled(DebugLevel::Debug) {
        log(
            DebugLevel::Debug,
            "PTY_WRITE",
            &format!("written_bytes={}", bytes.len()),
        );
    }
}

/// Mode change logging
pub fn log_mode_change(mode: &str, enabled: bool) {
    if is_enabled(DebugLevel::Info) {
        log(
            DebugLevel::Info,
            "MODE",
            &format!("{} {}", mode, if enabled { "enabled" } else { "disabled" }),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_debug_level_parsing() {
        std::env::set_var("DEBUG_LEVEL", "3");
        assert_eq!(DebugLevel::from_env(), DebugLevel::Debug);

        std::env::set_var("DEBUG_LEVEL", "0");
        assert_eq!(DebugLevel::from_env(), DebugLevel::Off);

        std::env::remove_var("DEBUG_LEVEL");
        assert_eq!(DebugLevel::from_env(), DebugLevel::Off);
    }

    #[test]
    fn osc_dispatch_log_message_never_contains_payload() {
        let secret = b"token=super-secret-value";
        let message = osc_dispatch_log_message(&[b"633", b"E", secret]);

        assert_eq!(
            message,
            format!(
                "OSC command=633 params=2 payload_bytes={}",
                b"E".len() + secret.len()
            )
        );
        assert!(!message.contains("super-secret-value"));

        let invalid_command = osc_dispatch_log_message(&[secret]);
        assert_eq!(
            invalid_command,
            "OSC command=invalid params=0 payload_bytes=0"
        );
        assert!(!invalid_command.contains("super-secret-value"));
    }

    #[test]
    fn trace_print_log_message_never_contains_character_or_codepoint() {
        let secret = '🕵';
        let message = print_log_message(secret, 4, 2);

        assert!(!message.contains(secret));
        assert!(!message.contains("1F575"));
        assert_eq!(message, "char_class=unicode display_width=1 at (4,2)");
    }

    #[test]
    fn buffer_snapshot_log_message_never_contains_label_or_content() {
        let label = "label-secret-canary";
        let content = "screen-secret-canary\n  next";
        let message = buffer_snapshot_log_message(label, 2, 20, content);

        assert!(!message.contains(label));
        assert!(!message.contains("screen-secret-canary"));
        assert!(!message.contains("next"));
        assert!(message.contains(&format!("label_bytes={}", label.len())));
        assert!(message.contains(&format!("content_bytes={}", content.len())));
    }
}
