use ianvs_core::model::{
    TerminalEmulation, TerminalProfile, TerminalProfileAppearance, TerminalProfileInteraction,
    TerminalProfileLaunch, TerminalProfileTerminal, TerminalShellIntegration,
};
use ianvs_core::session;
use par_term_emu_core_rust::cell::Cell;
use par_term_emu_core_rust::color::{Color, NamedColor};
use par_term_emu_core_rust::graphics::kitty::KittyParser;
use par_term_emu_core_rust::graphics::{
    AnimationControl, AnimationFrame, AnimationState, GraphicProtocol, GraphicsStore,
    ImageDimension, ImageSizeUnit, TerminalGraphic, next_graphic_id,
};
use par_term_emu_core_rust::mouse::{MouseEncoding, MouseEvent, MouseMode};
use par_term_emu_core_rust::screenshot::{ScreenshotConfig, SixelRenderMode};
use par_term_emu_core_rust::terminal::{
    Terminal as ParserTerminal, sanitize_bracketed_paste_content,
};
use par_term_emu_core_rust::{WidthConfig, str_width};
use std::collections::BTreeMap;
use std::ffi::CStr;
use std::fs;
use std::path::Path;
use std::ptr;
use std::thread;
use std::time::{Duration, Instant};
use tempfile::tempdir;

const SESSION_WAIT_ATTEMPTS: usize = 200;
const RED_PIXEL_PNG_BASE64: &str = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==";
const RED_GREEN_2X1_PNG_BASE64: &str = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=";
const TRANSPARENT_RED_2X1_PNG_BASE64: &str = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAD0lEQVR4nGNgAIL/DAwNAASFAYC4df53AAAAAElFTkSuQmCC";
const RED_GREEN_1X1_GIF_BASE64: &str = "R0lGODlhAQABAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQIAgAAACwAAAAAAQABAAAIBAABBAQAIfkECAMAAAAsAAAAAAEAAQCBAP8AAAAAAAAAAAAACAQAAQQEADs=";
const RED_RGBA_BASE64: &str = "/wAA/w==";
const GREEN_RGBA_BASE64: &str = "AP8A/w==";

fn red_pixel_png_bytes() -> &'static [u8] {
    &[
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6,
        0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240,
        31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
    ]
}

fn force_kitty_animation_frame_elapsed(terminal: &mut ParserTerminal, image_id: u32) {
    terminal
        .graphics_store_mut()
        .get_animation_mut(image_id)
        .expect("expected Kitty animation")
        .frame_start_time = Some(Instant::now() - Duration::from_millis(2));
}

fn base64_standard_no_pad_encode(data: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut output = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0];
        let b1 = *chunk.get(1).unwrap_or(&0);
        let b2 = *chunk.get(2).unwrap_or(&0);
        output.push(ALPHABET[(b0 >> 2) as usize] as char);
        output.push(ALPHABET[(((b0 & 0x03) << 4) | (b1 >> 4)) as usize] as char);
        if chunk.len() > 1 {
            output.push(ALPHABET[(((b1 & 0x0f) << 2) | (b2 >> 6)) as usize] as char);
        }
        if chunk.len() > 2 {
            output.push(ALPHABET[(b2 & 0x3f) as usize] as char);
        }
    }
    output
}

fn kitty_path_payload(path: &Path) -> String {
    base64_standard_no_pad_encode(path.to_string_lossy().as_bytes())
}

#[cfg(unix)]
fn create_kitty_shared_memory_payload(data: &[u8]) -> Option<(String, String)> {
    use std::ffi::CString;
    use std::ptr;
    use std::time::{SystemTime, UNIX_EPOCH};

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let name = format!(
        "/ivs{:x}{:x}",
        std::process::id() & 0xffff,
        nanos & 0xffff_ffff,
    );
    let c_name = CString::new(name.as_bytes()).unwrap();
    let fd = unsafe {
        libc::shm_open(
            c_name.as_ptr(),
            libc::O_CREAT | libc::O_EXCL | libc::O_RDWR,
            0o600,
        )
    };
    if fd < 0 {
        return skip_kitty_shared_memory_test(format!(
            "failed to create shared memory object {name}: {}",
            std::io::Error::last_os_error()
        ));
    }
    if unsafe { libc::ftruncate(fd, data.len() as libc::off_t) } != 0 {
        let error = std::io::Error::last_os_error();
        let _ = unsafe { libc::close(fd) };
        let _ = unsafe { libc::shm_unlink(c_name.as_ptr()) };
        return skip_kitty_shared_memory_test(format!(
            "failed to resize shared memory object {name}: {error}",
        ));
    }

    let ptr = unsafe {
        libc::mmap(
            ptr::null_mut(),
            data.len(),
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_SHARED,
            fd,
            0,
        )
    };
    if ptr == libc::MAP_FAILED {
        let error = std::io::Error::last_os_error();
        let _ = unsafe { libc::close(fd) };
        let _ = unsafe { libc::shm_unlink(c_name.as_ptr()) };
        return skip_kitty_shared_memory_test(format!(
            "failed to map shared memory object {name}: {error}",
        ));
    }
    unsafe {
        ptr::copy_nonoverlapping(data.as_ptr(), ptr.cast::<u8>(), data.len());
        let _ = libc::munmap(ptr, data.len());
        let _ = libc::close(fd);
    }

    let payload = base64_standard_no_pad_encode(name.as_bytes());
    Some((name, payload))
}

#[cfg(unix)]
fn skip_kitty_shared_memory_test(message: String) -> Option<(String, String)> {
    if std::env::var_os("IANVS_REQUIRE_POSIX_SHM_TESTS").is_some() {
        panic!("{message}");
    }
    eprintln!("skipping Kitty shared memory test: {message}");
    None
}

#[cfg(unix)]
fn kitty_shared_memory_exists(name: &str) -> bool {
    let c_name = std::ffi::CString::new(name.as_bytes()).unwrap();
    let fd = unsafe { libc::shm_open(c_name.as_ptr(), libc::O_RDONLY, 0) };
    if fd < 0 {
        return false;
    }
    let _ = unsafe { libc::close(fd) };
    true
}

#[cfg(unix)]
fn unlink_kitty_shared_memory(name: &str) {
    let c_name = std::ffi::CString::new(name.as_bytes()).unwrap();
    let _ = unsafe { libc::shm_unlink(c_name.as_ptr()) };
}

fn local_profile(
    id: &str,
    name: &str,
    shell: &str,
    args: Vec<String>,
    env: BTreeMap<String, String>,
    emulation: TerminalEmulation,
) -> TerminalProfile {
    local_profile_with_scrollback(id, name, shell, args, env, emulation, 8_000)
}

fn local_profile_with_scrollback(
    id: &str,
    name: &str,
    shell: &str,
    args: Vec<String>,
    env: BTreeMap<String, String>,
    emulation: TerminalEmulation,
    scrollback_lines: usize,
) -> TerminalProfile {
    TerminalProfile {
        id: id.to_string(),
        name: name.to_string(),
        launch: TerminalProfileLaunch {
            program: shell.to_string(),
            args,
            env,
            cwd: None,
        },
        terminal: TerminalProfileTerminal {
            emulation,
            scrollback_lines,
            ..TerminalProfileTerminal::default()
        },
        shell_integration: TerminalShellIntegration::default(),
        appearance: TerminalProfileAppearance::default(),
        interaction: TerminalProfileInteraction::default(),
    }
}

fn test_profile() -> TerminalProfile {
    local_profile(
        "test",
        "Test",
        "/bin/sh",
        vec!["-lc".to_string(), "printf 'hello\\n'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn interactive_profile() -> TerminalProfile {
    local_profile(
        "interactive",
        "Interactive",
        "/bin/sh",
        vec![],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn bash_readline_profile() -> TerminalProfile {
    let mut env = BTreeMap::new();
    env.insert("PS1".to_string(), "PROMPT-XYZ> ".to_string());
    env.insert("INPUTRC".to_string(), "/dev/null".to_string());
    local_profile(
        "bash-readline",
        "Bash Readline",
        "/bin/bash",
        vec![
            "--noprofile".to_string(),
            "--norc".to_string(),
            "-i".to_string(),
        ],
        env,
        TerminalEmulation::Xterm256,
    )
}

fn prompt_like_profile() -> TerminalProfile {
    local_profile(
        "prompt-like",
        "Prompt-Like",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r"printf '\x1b[38;5;196m\x1b[48;5;46mabc   \x1b[0m\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn sgr_colon_truecolor_profile() -> TerminalProfile {
    local_profile(
        "sgr-colon-truecolor",
        "SGR Colon Truecolor",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r"printf '\x1b[38:2::255:0:0mR\x1b[0m\x1b[48:2::0:0:255mB\x1b[0m\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn style_only_change_profile() -> TerminalProfile {
    local_profile(
        "style-only-change",
        "Style Only Change",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.write("\x1b[31msame\x1b[0m"); sys.stdout.flush(); time.sleep(0.35); sys.stdout.write("\r\x1b[32msame\x1b[0m\n"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn streaming_scrollback_profile() -> TerminalProfile {
    local_profile(
        "streaming-scrollback",
        "Streaming Scrollback",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "i=0; while [ \"$i\" -lt 14 ]; do printf 'line%02d\\n' \"$i\"; i=$((i + 1)); if [ \"$i\" -eq 7 ]; then sleep 0.35; fi; done"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn single_line_scroll_shift_profile(gate_path: &Path) -> TerminalProfile {
    let mut env = BTreeMap::new();
    env.insert(
        "IANVS_SCROLL_GATE".to_string(),
        gate_path.display().to_string(),
    );
    local_profile(
        "single-line-scroll-shift",
        "Single Line Scroll Shift",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os, sys, time
gate = os.environ["IANVS_SCROLL_GATE"]
for i in range(5):
    sys.stdout.write(f"line{i:02d}\n")
sys.stdout.flush()
while not os.path.exists(gate):
    time.sleep(0.01)
sys.stdout.write("line05\n")
sys.stdout.flush()
'"#
            .to_string(),
        ],
        env,
        TerminalEmulation::Xterm256,
    )
}

fn burst_stdout_profile(gate_path: &Path) -> TerminalProfile {
    let mut env = BTreeMap::new();
    env.insert(
        "IANVS_BURST_GATE".to_string(),
        gate_path.display().to_string(),
    );
    local_profile(
        "burst-stdout",
        "Burst Stdout",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os, sys, time
gate = os.environ["IANVS_BURST_GATE"]
sys.stdout.write("burst-ready\n")
sys.stdout.flush()
while not os.path.exists(gate):
    time.sleep(0.01)
for i in range(512):
    sys.stdout.write(f"burst-{i:05d}\n")
sys.stdout.flush()
'"#
            .to_string(),
        ],
        env,
        TerminalEmulation::Xterm256,
    )
}

fn clear_screen_profile() -> TerminalProfile {
    local_profile(
        "clear-screen",
        "Clear Screen",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.write("before\n"); sys.stdout.flush(); time.sleep(0.35); sys.stdout.write("\x1b[2J\x1b[Hafter\n"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn large_transcript_profile() -> TerminalProfile {
    local_profile_with_scrollback(
        "large-transcript",
        "Large Transcript",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys\nfor i in range(9000):\n    sys.stdout.write(f'line-{i:05d} abcdefghijklmnopqrstuvwxyz\\n')\nsys.stdout.flush()\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        8_000,
    )
}

fn scrollback_profile() -> TerminalProfile {
    local_profile(
        "scrollback",
        "Scrollback",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "i=0; while [ \"$i\" -lt 80 ]; do printf 'line%02d\\n' \"$i\"; i=$((i + 1)); done"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn search_modes_profile() -> TerminalProfile {
    local_profile(
        "search-modes",
        "Search Modes",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf 'Alpha\\nalpha\\nERR 100\\nerr 200\\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn limited_scrollback_profile() -> TerminalProfile {
    local_profile_with_scrollback(
        "scrollback-limited",
        "Scrollback Limited",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "i=0; while [ \"$i\" -lt 40 ]; do printf 'line%02d\\n' \"$i\"; i=$((i + 1)); done"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        4,
    )
}

fn top_anchored_partial_scrollback_profile() -> TerminalProfile {
    local_profile(
        "top-anchored-partial-scrollback",
        "Top Anchored Partial Scrollback",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
sys.stdout.write('\x1b[1;13r')
for row in range(1, 14):
    sys.stdout.write(f'\x1b[{row};1Hrow{row:02d}')
sys.stdout.write('\x1b[1;1H\x1b[2S')
sys.stdout.flush()
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn wrapped_selection_profile() -> TerminalProfile {
    local_profile(
        "wrapped-selection",
        "Wrapped Selection",
        "/bin/sh",
        vec!["-lc".to_string(), "printf 'abcdefghij\\nkl\\n'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn title_profile() -> TerminalProfile {
    local_profile(
        "title",
        "Title",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]2;构建目标\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn icon_name_profile() -> TerminalProfile {
    local_profile(
        "icon-name",
        "Icon Name",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]1;图标名称\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn legacy_title_alias_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "legacy-title-aliases",
        "xterm Legacy Title Aliases",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,sys,time; os.write(1,b"\x1b]0;OSC0 combined\x07OSC0-READY\n"); time.sleep(0.5); os.write(1,b"\x1b]lLegacy;window\x1b\\\x1b]LLegacy;icon\x07LEGACY-TITLE-READY\n"); token=sys.stdin.buffer.readline().strip(); os.write(1,b"LEGACY-TITLE-AFTER:"+token+b"\n"); time.sleep(0.2)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn xterm_title_window_ops_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "xterm-title-window-ops",
        "xterm Title Window Ops",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c "$(cat <<'PY'
import os
import select
import sys
import termios
import time
import tty

old = termios.tcgetattr(0)
tty.setraw(0)
time.sleep(0.2)
payload = (
    b"\x1b]2;Window;alpha\x1b\\"
    b"\x1b]1;Icon;beta\x1b\\"
    b"\x1b[20t\x1b[21t"
    b"\x1b[>1t\x1b[20t\x1b[21t\x1b[>1T"
    b"\x1b[22;0t\x1b]0;Changed\x1b\\\x1b[23;0t\x1b[20t\x1b[21t"
    b"\x1b]0;Direct;both\x1b\\\x1b[22;0;10t"
    b"\x1b]0;Mutated\x1b\\\x1b[23;0;10t\x1b[20t\x1b[21t"
)
os.write(1, payload)
data = b""
deadline = time.time() + 2.0
while time.time() < deadline:
    ready, _, _ = select.select([0], [], [], 0.1)
    if ready:
        data += os.read(0, 4096)
    if data.count(b"\x1b\\") >= 8:
        break

termios.tcsetattr(0, termios.TCSANOW, old)
responses = []
offset = 0
while True:
    start = data.find(b"\x1b]", offset)
    if start < 0:
        break
    end = data.find(b"\x1b\\", start + 2)
    if end < 0:
        break
    responses.append(data[start:end + 2])
    offset = end + 2

if responses:
    for index, response in enumerate(responses):
        os.write(1, f"TITLE-OPS-R{index}:{response.hex()}\n".encode())
else:
    os.write(1, b"TITLE-OPS-TIMEOUT\n")
os.write(1, b"TITLE-OPS-READY\n")
token = sys.stdin.buffer.readline().strip()
os.write(1, b"TITLE-OPS-AFTER:" + token + b"\n")
time.sleep(0.2)
PY
)""#
            .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn resize_request_profile() -> TerminalProfile {
    local_profile(
        "resize-request",
        "Resize Request",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033[8;30;100t'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn shell_hook_profile() -> TerminalProfile {
    local_profile(
        "shell-hook",
        "Shell Hook",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1bPhook;7b22686f6f6b223a22707265636d64222c22707764223a222f746d702f69616e7673207465726d696e616c227d\x1b\\")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn clipboard_copy_profile() -> TerminalProfile {
    local_profile(
        "clipboard-copy",
        "Clipboard Copy",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]52;c;5aSN5Yi25YaF5a658J+Mnw==\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn clipboard_empty_copy_profile() -> TerminalProfile {
    local_profile(
        "clipboard-empty-copy",
        "Clipboard Empty Copy",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033]52;c;\\a'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn iterm_clipboard_copy_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "iterm-clipboard-copy",
        "iTerm Clipboard Copy",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]1337;CopyToClipboard=find\x07streamed text\n\x1b]1337;EndCopy\x1b\\\x1b]1337;Copy=:ZGlyZWN0IPCfmIA=\x07")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn iterm_annotation_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "iterm-annotation",
        "iTerm Annotation",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.buffer.write(b"prefix \x1b]1337;AddAnnotation=4|Visible note\x07word\n\x1b]1337;AddHiddenAnnotation=Hidden note|6|0|1\x1b\\secret\nOSC1337-ANNOTATION-DONE\n"); sys.stdout.flush(); time.sleep(0.4)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn iterm_open_url_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "iterm-open-url",
        "iTerm Open URL",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]1337;OpenURL=:aHR0cHM6Ly9leGFtcGxlLnRlc3QvcGhhc2UyOQ==\x1b\\OSC1337-OPEN-URL-DONE\n"); sys.stdout.flush(); sys.stdin.readline(); sys.stdout.buffer.write(b"AFTER-OPEN-URL-RESIZE\n"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn iterm_attention_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "iterm-attention",
        "iTerm Attention",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]1337;RequestAttention=yes\x07\x1b]1337;RequestAttention=once\x1b\\\x1b]1337;RequestAttention=fireworks\x07\x1b]1337;RequestAttention=no\x1b\\\x1b]1337;RequestAttention=YES\x07OSC1337-ATTENTION-DONE\n"); sys.stdout.flush(); sys.stdin.readline(); sys.stdout.buffer.write(b"AFTER-ATTENTION-RESIZE\n"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn clipboard_paste_request_profile() -> TerminalProfile {
    local_profile(
        "clipboard-paste",
        "Clipboard Paste",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033]52;c;?\\a'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc5522_clipboard_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc5522-clipboard",
        "OSC5522 Clipboard",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]5522;type=write:id=w1:pw=c2VjcmV0:name=RWRpdG9y\x1b\\\x1b]5522;type=wdata:mime=dGV4dC9wbGFpbg==;aGk=\x1b\\\x1b]5522;type=wdata:mime=aW1hZ2UvcG5n;AAEC\x1b\\\x1b]5522;type=wdata\x1b\\\x1b]5522;type=read:id=list;Lg==\x1b\\\x1b]5522;type=read:id=r1:mime=aW1hZ2UvcG5n:pw=b25lLXRpbWU=;\x1b\\")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc7_shell_context_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc7-shell-context",
        "OSC7 Shell Context",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]7;file://alice@remote.example.com/tmp/ianvs%20project\x07")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc9_9_shell_context_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc9-9-shell-context",
        "OSC9;9 Shell Context",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]7;file://alice@remote.example/tmp/before\x07\x1b]9;9;/tmp/ianvs-osc9-9\x07")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn invalid_osc9_9_shell_context_profile() -> TerminalProfile {
    local_profile(
        "invalid-osc9-9-shell-context",
        "Invalid OSC9;9 Shell Context",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]9;9;relative/path\x07\x1b]9;9;/tmp/bad\xc2\x85path\x1b\\")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc1337_current_dir_profile() -> TerminalProfile {
    local_profile(
        "osc1337-current-dir",
        "OSC1337 CurrentDir",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]1337;CurrentDir=/tmp/ianvs%20current\x07")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc133_shell_command_profile() -> TerminalProfile {
    local_profile(
        "osc133-shell-command",
        "OSC133 Shell Command",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]133;N;aid=shell-1;k=i\\a\\033]133;P;k=s;aid=shell-1\\a\\033]133;B\\a\\033]133;C;echo ok\\aoutput\\n\\033]133;D;aid=shell-1;7\\a'"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc133_resize_replay_profile() -> TerminalProfile {
    local_profile(
        "osc133-resize-replay",
        "OSC133 Resize Replay",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]133;A\\a\\033]133;B\\a\\033]133;C;echo ready\\aREADY\\n\\033]133;D;0\\a'; read line; printf 'AFTER-RESIZE\\n'"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc633_shell_command_profile(emulation: TerminalEmulation) -> TerminalProfile {
    let mut env = BTreeMap::new();
    env.insert("VSCODE_NONCE".to_string(), "private-nonce-633".to_string());
    local_profile(
        "osc633-shell-command",
        "OSC633 Shell Command",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]7;file://alice@remote.example/tmp/before\x07\x1b]633;A\x07\x1b]633;B\x07\x1b]633;E;printf\\x3bvalue;private-nonce-633\x1b\\\x1b]633;C\x07\x1b]633;P;Cwd=/tmp/ianvs-osc633\x1b\\\x1b]633;D;7\x07")'"#
                .to_string(),
        ],
        env,
        emulation,
    )
}

fn osc633_resize_nonce_profile() -> TerminalProfile {
    let mut env = BTreeMap::new();
    env.insert("VSCODE_NONCE".to_string(), "private-nonce-633".to_string());
    local_profile(
        "osc633-resize-nonce",
        "OSC633 Resize Nonce",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]633;A\x07\x1b]633;B\x07\x1b]633;E;after-resize;private-nonce-633\x07WAITING\n"); sys.stdout.flush(); sys.stdin.readline(); sys.stdout.buffer.write(b"\x1b]633;C\x07DONE\n\x1b]633;D;0\x07"); sys.stdout.flush()'"#
                .to_string(),
        ],
        env,
        TerminalEmulation::Xterm256,
    )
}

fn osc133_alt_screen_shell_command_profile() -> TerminalProfile {
    local_profile(
        "osc133-alt-screen-shell-command",
        "OSC133 Alt Screen Shell Command",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.buffer.write(b"\x1b[?1049h\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C;vim-ish\x07alt-screen\x1b]133;D;0\x07\x1b[?1049l"); sys.stdout.flush(); time.sleep(0.2)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc1337_remote_host_user_var_profile() -> TerminalProfile {
    local_profile(
        "osc1337-remote-user-var",
        "OSC1337 RemoteHost SetUserVar",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]1337;RemoteHost=deploy@example.internal\\a\\033]1337;SetUserVar=IANVS_TEST=aGVsbG8=\\a'"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc1337_shell_metadata_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc1337-shell-metadata",
        "OSC1337 Shell Metadata",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]1337;ShellIntegrationVersion=17;zsh\x1b\\line\n\x1b]1337;SetMark\x07\x1b]1337;ReportCellSize\x1b\\")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc1337_report_variable_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc1337-report-variable",
        "OSC1337 Report Variable",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]1337;SetUserVar=REPORT_KEY=cmVwb3J0LXZhbHVl\x07\x1b]1337;ReportVariable=dXNlci5SRVBPUlRfS0VZ\x07\x1b]1337;ReportVariable=c2Vzc2lvbi5jb2x1bW5z\x1b\\\x1b]1337;ReportVariable=c2Vzc2lvbi5lbnZpcm9ubWVudA==\x07OSC1337-REPORT-VARIABLE-DONE\n"); sys.stdout.flush(); sys.stdin.readline(); sys.stdout.buffer.write(b"AFTER-REPORT-VARIABLE-RESIZE\n"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc1337_clear_captured_output_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc1337-clear-captured-output",
        "OSC1337 Clear Captured Output",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]1337;ClearCapturedOutput=1\x07\x1b]1337;ClearCapturedOutput\x07\x1b]1337;ClearCapturedOutput\x1b\\OSC1337-CLEAR-CAPTURED-DONE\n"); sys.stdout.flush(); sys.stdin.readline(); sys.stdout.buffer.write(b"AFTER-CLEAR-CAPTURED-RESIZE\n"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc1337_unicode_version_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc1337-unicode-version",
        "OSC1337 Unicode Version",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write("\x1b]1337;UnicodeVersion=8\x07U8:\u2615\x1b[31mX\x1b[0m\r\n\x1b]1337;UnicodeVersion=push real-pty\x1b\\\x1b]1337;UnicodeVersion=9\x1b\\U9:\u2615\x1b[31mX\x1b[0m\r\n\x1b]1337;UnicodeVersion=pop real-pty\x07U8R:\u2615\x1b[31mX\x1b[0m\r\nU8-FINAL:\u2615X".encode()); sys.stdout.flush(); sys.stdin.readline(); sys.stdout.buffer.write("\r\nAFTER:\u2615X".encode()); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc1337_cursor_shape_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc1337-cursor-shape",
        "OSC1337 Cursor Shape",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.buffer.write(b"\x1b]1337;CursorShape=1\x1b\\OSC1337-CURSOR-BEAM\n"); sys.stdout.flush(); time.sleep(0.5)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc1337_cursor_shape_only_profile() -> TerminalProfile {
    local_profile(
        "osc1337-cursor-shape-only",
        "OSC1337 Cursor Shape Only",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.buffer.write(b"\x1b]1337;CursorShape=1\x1b\\"); sys.stdout.flush(); time.sleep(0.5)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc1337_cursor_guide_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc1337-cursor-guide",
        "OSC1337 Cursor Guide",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.buffer.write(b"\x1b]1337;HighlightCursorLine=yes\x1b\\OSC1337-CURSOR-GUIDE\n"); sys.stdout.flush(); time.sleep(0.5)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc1337_clear_buffer_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile_with_scrollback(
        "osc1337-clear-buffer",
        "OSC1337 Clear Buffer",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; [sys.stdout.write(f"OSC1337-OLD-{index:02d}\n") for index in range(48)]; sys.stdout.buffer.write(b"\x1b]1337;ClearScrollback\x1b\\OSC1337-AFTER-CLEAR\n"); sys.stdout.flush(); time.sleep(0.5)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
        128,
    )
}

fn osc1337_block_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc1337-block",
        "OSC1337 Block",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.buffer.write(b"\x1b]1337;Block=id=build-1;attr=start;type=build\x1b\\block-first\nblock-secret\nblock-last\x1b]1337;Block=id=build-1;attr=end;render=1\x1b\\\x1b]1337;UpdateBlock=id=build-1;action=fold\x1b\\\nOSC1337-BLOCK-DONE\n"); sys.stdout.flush(); time.sleep(0.5)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc1337_inline_button_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc1337-inline-button",
        "OSC1337 Inline Button",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,sys,time,tty; fd=sys.stdin.fileno(); tty.setraw(fd); sys.stdout.buffer.write(b"\x1b]1337;Block=id=copy-1;attr=start\x1b\\copy-exact\x1b]1337;Block=id=copy-1;attr=end\x1b\\\r\n\x1b]1337;Button=type=copy;block=copy-1\x1b\\\x1b]1337;Button=type=custom;code=42;icon=star.fill\x07BUTTON-READY\r\n"); sys.stdout.flush(); time.sleep(0.2); data=os.read(fd,64); sys.stdout.buffer.write(("BUTTON-REPLY:"+data.hex()+"\r\n").encode()+b"\x1b]1337;Button=type=custom\x1b\\BUTTON-INVALID\r\n"); sys.stdout.flush(); time.sleep(1)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn decscusr_cursor_shape_profile() -> TerminalProfile {
    local_profile(
        "decscusr-cursor-shape",
        "DECSCUSR Cursor Shape",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.buffer.write(b"\x1b[4 qDECSCUSR-CURSOR-UNDERLINE\n"); sys.stdout.flush(); time.sleep(0.5)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc_notification_progress_badge_profile() -> TerminalProfile {
    local_profile(
        "osc-notification-progress-badge",
        "OSC Notification Progress Badge",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]9;Build finished\x07\x1b]777;notify;Deploy;Done\x07\x1b]9;4;1;55\x07\x1b]934;set;build;percent=80;label=Compiling\x07\x1b]1337;SetBadgeFormat=QnVpbGQ=\x07")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc21337_tab_status_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc21337-tab-status",
        "OSC21337 Tab Status",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.buffer.write(b"\x1b]21337;indicator=#ff9500;status=Working\\;phase;status-color=#5f87ff\x1b\\\x1b]21337;status-color=\x07OSC21337-READY\n"); sys.stdout.flush(); time.sleep(0.2)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc9_indeterminate_progress_profile() -> TerminalProfile {
    local_profile(
        "osc9-indeterminate-progress",
        "OSC9 Indeterminate Progress",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b]9;4;3\x07")'"#.to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn apc_unsupported_noop_profile() -> TerminalProfile {
    local_profile(
        "apc-unsupported-noop",
        "APC Unsupported Noop",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf 'before\\033_APC-LEAK\\033\\\\after\\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn non_csi_string_controls_profile() -> TerminalProfile {
    local_profile(
        "non-csi-string-controls",
        "Non-CSI String Controls",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf 'pre\\033^PM-LEAK\\033\\\\mid\\033XSOS-LEAK\\033\\\\post\\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn hyperlink_profile() -> TerminalProfile {
    local_profile(
        "hyperlink",
        "Hyperlink",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]8;;https://example.com/docs\\aDocs\\033]8;;\\a\\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn hyperlink_protocol_id_profile() -> TerminalProfile {
    local_profile(
        "hyperlink-protocol-id",
        "Hyperlink Protocol ID",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r"printf '\033]8;id=first;https://example.com/docs\aOne\033]8;;\a \033]8;id=second;https://example.com/docs\aTwo\033]8;;\a\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn vt220_hyperlink_profile() -> TerminalProfile {
    local_profile(
        "vt220-hyperlink",
        "VT220 Hyperlink",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]8;;https://example.com/docs\\aDocs\\033]8;;\\a\\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn mode_switch_profile() -> TerminalProfile {
    local_profile(
        "mode-switch",
        "Mode Switch",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033[?1h\\033='".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn alternate_screen_profile() -> TerminalProfile {
    local_profile(
        "alternate-screen",
        "Alternate Screen",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033[?1049hALTSCREEN'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn alternate_screen_1047_profile() -> TerminalProfile {
    local_profile(
        "alternate-screen-1047",
        "Alternate Screen 1047",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033[?1047hALT1047'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn alternate_screen_interaction_modes_profile() -> TerminalProfile {
    local_profile(
        "alternate-screen-interaction-modes",
        "Alternate Screen Interaction Modes",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("\x1b[?1049h")
sys.stdout.write("\x1b[?1004h\x1b[?1007h\x1b[?1002h\x1b[?1006h\x1b[=1u")
sys.stdout.write("ALTINTERACTION")
sys.stdout.flush()
time.sleep(0.15)
sys.stdout.write("\x1b[?1049lPRIMARYDONE")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn primary_interaction_modes_across_alternate_screen_profile() -> TerminalProfile {
    local_profile(
        "primary-interaction-modes-across-alternate-screen",
        "Primary Interaction Modes Across Alternate Screen",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

def out(value, delay=0.16):
    sys.stdout.write(value)
    sys.stdout.flush()
    time.sleep(delay)

out("\x1b[?1004h\x1b[?1007h\x1b[?1002h\x1b[?1006h\x1b[=1u\x1b[?2004hPRIMARYMODES")
out("\x1b[?1049hALTEMPTY")
out("\x1b[?1004h\x1b[?1007h\x1b[?1003h\x1b[?1016h\x1b[=8uALTMODES")
out("\x1b[?1049lPRIMARYRESTORED", 0.22)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn kitty_keyboard_profile() -> TerminalProfile {
    local_profile(
        "kitty-keyboard",
        "Kitty Keyboard",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033[=1uK'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn focus_tracking_profile() -> TerminalProfile {
    local_profile(
        "focus-tracking",
        "Focus Tracking",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033[?1004hFOCUS'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn bracketed_paste_mode_profile() -> TerminalProfile {
    local_profile(
        "bracketed-paste-mode",
        "Bracketed Paste Mode",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033[?2004hPASTE'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc5522_mime_paste_mode_profile() -> TerminalProfile {
    local_profile(
        "osc5522-mime-paste-mode",
        "OSC5522 MIME Paste Mode",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033[?5522hMIMEPASTE'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn mouse_sgr_pixels_profile() -> TerminalProfile {
    local_profile(
        "mouse-sgr-pixels",
        "Mouse SGR Pixels",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033[?1000h\\033[?1016hMOUSEPIX'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn mouse_x10_profile() -> TerminalProfile {
    local_profile(
        "mouse-x10",
        "Mouse X10",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033[?9hMOUSEX10'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn alternate_scroll_profile() -> TerminalProfile {
    local_profile(
        "alternate-scroll",
        "Alternate Scroll",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033[?1049h\\033[?1007hALTSCROLL'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn alternate_wrapped_line_profile() -> TerminalProfile {
    local_profile(
        "alternate-wrapped-line",
        "Alternate Wrapped Line",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time
time.sleep(0.2)
sys.stdout.write('\x1b[?1049hABCDEFGHIJK')
sys.stdout.flush()
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn synchronized_output_profile() -> TerminalProfile {
    local_profile(
        "synchronized-output",
        "Synchronized Output",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; time.sleep(0.2); sys.stdout.write("\x1b[?2026h"); sys.stdout.flush(); time.sleep(0.2); sys.stdout.write("\rSYNC-MID"); sys.stdout.flush(); time.sleep(0.8); sys.stdout.write("\rSYNC-FINAL\x1b[?2026l\n"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn stuck_synchronized_output_profile() -> TerminalProfile {
    local_profile(
        "stuck-synchronized-output",
        "Stuck Synchronized Output",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.write("\x1b[?2026hSYNC-STUCK"); sys.stdout.flush(); time.sleep(1.5)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn synchronized_output_host_events_profile() -> TerminalProfile {
    local_profile(
        "synchronized-output-host-events",
        "Synchronized Output Host Events",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("\x1b[?2026h")
sys.stdout.flush()
time.sleep(0.1)
sys.stdout.write("\x1b]52;c;5aSN5Yi25YaF5a658J+Mnw==\x07")
sys.stdout.write("\x1b[8;31;101t")
sys.stdout.flush()
time.sleep(2.0)
sys.stdout.write("\rSYNC-HOST-DONE\x1b[?2026l\n")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn synchronized_inline_progress_profile() -> TerminalProfile {
    local_profile(
        "synchronized-inline-progress",
        "Synchronized Inline Progress",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("READY\n")
sys.stdout.flush()
time.sleep(0.25)
sys.stdout.write("\x1b[?2026h")
sys.stdout.write("Deploy 10%")
sys.stdout.flush()
time.sleep(0.30)
sys.stdout.write("\r\x1b[KDeploy 40%")
sys.stdout.flush()
time.sleep(0.30)
sys.stdout.write("\r\x1b[KDeploy done\n\x1b[?2026l")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn inline_progress_spinner_profile() -> TerminalProfile {
    local_profile(
        "inline-progress-spinner",
        "Inline Progress Spinner",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("READY\n")
sys.stdout.flush()
time.sleep(0.6)
sys.stdout.write("Downloading 10%")
sys.stdout.write("\r\x1b[KDownloading 20%")
sys.stdout.write("\r\x1b[KDone\n")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn inline_progress_cr_only_spinner_profile() -> TerminalProfile {
    local_profile(
        "inline-progress-cr-only-spinner",
        "Inline Progress CR Only Spinner",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("READY\n")
sys.stdout.flush()
time.sleep(0.6)
sys.stdout.write("Working -")
sys.stdout.write("\rWorking \\")
sys.stdout.write("\rWorking |")
sys.stdout.write("\rWorking done\n")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn inline_progress_short_overwrite_profile() -> TerminalProfile {
    local_profile(
        "inline-progress-short-overwrite",
        "Inline Progress Short Overwrite",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("READY\n")
sys.stdout.flush()
time.sleep(0.35)
sys.stdout.write("Downloading 100%")
sys.stdout.flush()
time.sleep(0.35)
sys.stdout.write("\r")
sys.stdout.flush()
time.sleep(0.1)
sys.stdout.write("\x1b[KOK\n")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn inline_progress_wide_overwrite_profile() -> TerminalProfile {
    local_profile(
        "inline-progress-wide-overwrite",
        "Inline Progress Wide Overwrite",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("READY\n")
sys.stdout.flush()
time.sleep(0.35)
sys.stdout.write("\u23f3 Downloading 100%")
sys.stdout.flush()
time.sleep(0.35)
sys.stdout.write("\r")
sys.stdout.flush()
time.sleep(0.1)
sys.stdout.write("\x1b[KOK\n")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn inline_progress_wide_cr_only_overwrite_profile() -> TerminalProfile {
    local_profile(
        "inline-progress-wide-cr-only-overwrite",
        "Inline Progress Wide CR Only Overwrite",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("READY\n")
sys.stdout.flush()
time.sleep(0.35)
sys.stdout.write("\U0001f9d1\u200d\U0001f4bb Building")
sys.stdout.flush()
time.sleep(0.35)
sys.stdout.write("\rOK Building\n")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn inline_progress_split_clear_repaint_profile() -> TerminalProfile {
    local_profile(
        "inline-progress-split-clear-repaint",
        "Inline Progress Split Clear Repaint",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("READY\n")
sys.stdout.flush()
time.sleep(0.35)
sys.stdout.write("Downloading 100%")
sys.stdout.flush()
time.sleep(0.35)
sys.stdout.write("\r\x1b[K")
sys.stdout.flush()
time.sleep(0.12)
sys.stdout.write("OK\n")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn inline_progress_clear_without_repaint_profile() -> TerminalProfile {
    local_profile(
        "inline-progress-clear-without-repaint",
        "Inline Progress Clear Without Repaint",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("READY\n")
sys.stdout.flush()
time.sleep(0.35)
sys.stdout.write("Transient status")
sys.stdout.flush()
time.sleep(0.35)
sys.stdout.write("\r\x1b[K")
sys.stdout.flush()
time.sleep(0.35)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn vt220_da_profile() -> TerminalProfile {
    local_profile(
        "vt220-da",
        "VT220 DA",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,sys; os.write(1,b"\x1b[c"); sys.stdout.flush(); data=os.read(0,128); os.write(1,repr(data).encode()+b"\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn pixel_size_query_profile() -> TerminalProfile {
    local_profile(
        "pixel-size-query",
        "Pixel Size Query",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,sys,termios,tty,time; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b[14t"); sys.stdout.flush(); data=os.read(0,128); termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"PIXEL-RESPONSE:"+repr(data).encode()+b"\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc4_query_profile() -> TerminalProfile {
    local_profile(
        "osc4-query",
        "OSC 4 Query",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,sys,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]4;1;rgba:12/34/56/78\x1b\\"); os.write(1,b"\x1b]4;1;?\x1b\\"); sys.stdout.flush(); ready,_,_=select.select([0],[],[],2.0); data=os.read(0,128) if ready else b"TIMEOUT"; termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"OSC4-RESPONSE:"+repr(data).encode()+b"\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc21_color_control_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc21-color-control",
        "OSC 21 Color Control",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,sys,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]21;foreground=#123456;background=#234567;cursor=#345678;196=#456789;foreground=?;background=?;cursor=?;196=?;future=?\x1b\\"); sys.stdout.flush(); ready,_,_=select.select([0],[],[],2.0); data=os.read(0,512) if ready else b"TIMEOUT"; termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"OSC21-RESPONSE:"+repr(data).encode()+b"\n\x1b[38;5;196mP\x1b[0m OSC21-SET\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn xterm_special_colors_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "xterm-special-colors",
        "xterm Special Colors",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,sys,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]5;0;#ff00ff\x1b\\\x1b]6;0;1\x1b\\\x1b]17;#112233;#181818;#ddeeff\x1b\\\x1b]5;0;?\x1b\\\x1b]17;?;?;?\x1b\\"); sys.stdout.flush(); time.sleep(0.2); ready,_,_=select.select([0],[],[],2.0); data=os.read(0,1024) if ready else b"TIMEOUT"; termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"XTERM-RESPONSE:"+repr(data).encode()+b"\n\x1b[1mB\x1b[38;2;1;2;3mR\x1b[0m XTERM-COLORS\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn iterm_set_colors_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "iterm-set-colors",
        "iTerm2 SetColors",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,sys,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]1337;SetColors=fg=112233,bg=000000,bold=ff00ff,underline=00ff00,link=00ffff,selbg=ff0000,selfg=000000,curbg=ffff00,curfg=0000ff,tab=123456,red=aabbcc\x1b\\\x1b]4;-2;?;-1;?\x1b\\"); sys.stdout.flush(); time.sleep(0.2); ready,_,_=select.select([0],[],[],2.0); data=os.read(0,1024) if ready else b"TIMEOUT"; termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"ITERM-COLOR-RESPONSE:"+repr(data).encode()+b"\n\x1b[1mB\x1b[0;4mU\x1b[0;38;5;1mR\x1b[0m ITERM-COLORS\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn iterm_osc6_tab_color_profile(emulation: TerminalEmulation) -> TerminalProfile {
    let mut profile = local_profile(
        "iterm-osc6-tab-color",
        "iTerm2 OSC 6 Tab Color",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; time.sleep(0.2); sys.stdout.buffer.write(b"\x1b]6;1;bg;red;brightness;255\x07\x1b]6;1;bg;green;brightness;128\x1b\\\x1b]6;1;bg;blue;brightness;64\x07\x1b]6;1;bg;red;brightness;999\x07OSC6-TAB-SET\n"); sys.stdout.flush(); token=sys.stdin.buffer.readline().strip(); sys.stdout.buffer.write(b"\x1b]6;1;bg;*;default\x1b\\OSC6-TAB-RESET:"+token+b"\n"); sys.stdout.flush(); time.sleep(0.4)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    );
    profile.appearance.colors.special.tab = Some("#102030".to_string());
    profile
}

fn osc22_pointer_shape_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc22-pointer-shape",
        "OSC 22 Pointer Shape",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,sys,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]22;pointer\x1b\\\x1b]22;?__current__,__default__,__grabbed__,pointer,no-such-name\x1b\\"); sys.stdout.flush(); ready,_,_=select.select([0],[],[],2.0); data=os.read(0,512) if ready else b"TIMEOUT"; termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"OSC22-RESPONSE:"+repr(data).encode()+b"\nOSC22-SET\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc66_sized_text_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc66-sized-text",
        "OSC 66 Sized Text",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"printf '\033]66;s=2:w=2:n=1:d=2:v=2:h=1;AB\033\\OSC66-SET\n'; sleep 1"#.to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc72_drop_target_profile(emulation: TerminalEmulation) -> TerminalProfile {
    let mut profile = local_profile(
        "osc72-drop-target",
        "OSC 72 Drop Target",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"printf '\033]72;t=a:i=7;text/plain text/uri-list\033\\OSC72-READY\n'; sleep 1"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    );
    profile.terminal.drag_drop_enabled = true;
    profile
}

fn osc_palette_product_profile() -> TerminalProfile {
    let mut profile = local_profile(
        "osc-palette-product",
        "OSC Palette Product",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"printf 'PALETTE-READY\n'
IFS= read -r _
printf '\033]4;0;#112233;15;#445566;16;#778899;255;#aabbcc\033\\'
printf '\033[38;5;0mA\033[38;5;15mB\033[38;5;16mC\033[38;5;255mD\033[0m PALETTE-SET\n'
IFS= read -r _
printf '\033]104\033\\'
printf '\033[38;5;0ma\033[38;5;15mb\033[38;5;16mc\033[38;5;255md\033[0m PALETTE-RESET\n'
sleep 0.2"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    profile.appearance.colors.normal.black = Some("#010203".to_string());
    profile.appearance.colors.bright.white = Some("#f1f2f3".to_string());
    profile
}

fn osc934_query_profile() -> TerminalProfile {
    local_profile(
        "osc934-query",
        "OSC 934 Query",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,sys,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]934;query\x1b\\"); sys.stdout.flush(); ready,_,_=select.select([0],[],[],2.0); data=os.read(0,512) if ready else b"TIMEOUT"; termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"OSC934-RESPONSE:"+repr(data).encode()+b"\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn xterm_capability_query_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "xterm-capability-query",
        "xterm OSC Capability Query",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,sys,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]60\x1b\\\x1b]61;allowMouseOps\x07\x1b]62;allowColorOps\x1b\\\x1b]60;reply-like\x1b\\\x1b]61;unknown\x1b\\"); sys.stdout.flush(); data=b""; deadline=time.time()+2.0
while time.time()<deadline:
 ready,_,_=select.select([0],[],[],0.1)
 if ready: data+=os.read(0,4096)
 if data.count(b"\x1b]")>=3 and data.endswith(b"\x1b\\"): break
termios.tcsetattr(0,termios.TCSANOW,old); data=data or b"TIMEOUT"; os.write(1,b"OSC60-62-RESPONSE:"+repr(data).encode()+b"\n"); token=sys.stdin.buffer.readline(); os.write(1,b"OSC60-62-AFTER:"+repr(token).encode()+b"\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn xterm_font_ops_profile(emulation: TerminalEmulation) -> TerminalProfile {
    let mut profile = local_profile(
        "xterm-font-ops",
        "xterm OSC 50 Font Ops",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,sys,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]50;#4 Courier Prime\x1b\\\x1b]50;?\x1b\\"); sys.stdout.flush(); ready,_,_=select.select([0],[],[],2.0); data=os.read(0,512) if ready else b"TIMEOUT"; termios.tcsetattr(0,termios.TCSANOW,old); os.write(1,b"OSC50-RESPONSE:"+repr(data).encode()+b"\n"); token=sys.stdin.buffer.readline(); os.write(1,b"OSC50-AFTER:"+repr(token).encode()+b"\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    );
    profile.appearance.font.family = "Profile Mono".to_string();
    profile
}

fn osc99_notification_lifecycle_profile() -> TerminalProfile {
    local_profile(
        "osc99-notification-lifecycle",
        "OSC 99 Notification Lifecycle",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os; os.write(1,b"\x1b]99;i=build:d=0:e=1:f=YnVpbGRjdGw=:t=ZGVwbG95:a=report:c=1;VGl0bGU=\x1b\\\x1b]99;i=build:p=body:d=0:e=1:w=250;Qm9keQ==\x1b\\\x1b]99;i=build:p=buttons;Approve\xe2\x80\xa8Retry\x1b\\\x1b]99;i=build;Updated\x1b\\\x1b]99;i=build:p=close;\x1b\\")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc99_query_profile() -> TerminalProfile {
    local_profile(
        "osc99-query",
        "OSC 99 Query",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,sys,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]99;i=probe:p=?;\x1b\\"); sys.stdout.flush(); ready,_,_=select.select([0],[],[],2.0); data=os.read(0,512) if ready else b"TIMEOUT"; termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"OSC99-RESPONSE:"+repr(data).encode()+b"\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc99_interactive_report_profile() -> TerminalProfile {
    local_profile(
        "osc99-interactive-report",
        "OSC 99 Interactive Report",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,select,termios,time,tty; old=termios.tcgetattr(0); tty.setraw(0); time.sleep(0.2); os.write(1,b"\x1b]99;i=deploy:d=0:a=report:c=1;Deploy ready\x1b\\\x1b]99;i=deploy:p=buttons;Approve\xe2\x80\xa8Retry\x1b\\"); ready,_,_=select.select([0],[],[],2.0); data=os.read(0,512) if ready else b"TIMEOUT"; termios.tcsetattr(0, termios.TCSANOW, old); os.write(1,b"OSC99-ACTION:"+repr(data).encode()+b"\n")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc99_product_dismiss_profile() -> TerminalProfile {
    local_profile(
        "osc99-product-dismiss",
        "OSC 99 Product Dismiss",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os,time; os.write(1,b"\x1b]99;i=dismiss-me;Waiting\x1b\\"); time.sleep(2)'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn osc3008_context_profile(emulation: TerminalEmulation) -> TerminalProfile {
    local_profile(
        "osc3008-context",
        "OSC 3008 Context",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import os; os.write(1,b"\x1b]3008;start=root;type=shell;user=dev\\x3bops;cwd=/work\\x5cdir;pid=42\x1b\\\x1b]3008;start=child;type=command;cwd=/work;cmdline=dart test\x1b\\\x1b]3008;start=root;type=shell;user=new\x1b\\\x1b]3008;end=missing;exit=failure\x1b\\\x1b]3008;end=root;exit=success;status=0\x1b\\")'"#
                .to_string(),
        ],
        BTreeMap::new(),
        emulation,
    )
}

fn osc12_cursor_color_profile() -> TerminalProfile {
    local_profile(
        "osc12-cursor-color",
        "OSC 12 Cursor Color",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]12;#123456\\aOSC12-CURSOR\\n'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn vt220_title_profile() -> TerminalProfile {
    local_profile(
        "vt220-title",
        "VT220 Title",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]2;构建目标\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn vt220_icon_name_profile() -> TerminalProfile {
    local_profile(
        "vt220-icon-name",
        "VT220 Icon Name",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]1;图标名称\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn vt220_clipboard_copy_profile() -> TerminalProfile {
    local_profile(
        "vt220-clipboard-copy",
        "VT220 Clipboard Copy",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "printf '\\033]52;c;5aSN5Yi25YaF5a658J+Mnw==\\a'".to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn vt220_clipboard_paste_request_profile() -> TerminalProfile {
    local_profile(
        "vt220-clipboard-paste",
        "VT220 Clipboard Paste",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033]52;c;?\\a'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn nerd_font_icons_profile() -> TerminalProfile {
    local_profile(
        "nerd-font-icons",
        "Nerd Font Icons",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write("NF:\ue0b0\U000f08c7Z")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn complex_grapheme_style_profile() -> TerminalProfile {
    local_profile(
        "complex-grapheme-style",
        "Complex Grapheme Style",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

sys.stdout.write(
    "A"
    "\x1b[38;2;255;0;0m\u2708\ufe0f\x1b[0m"
    "B"
    "\x1b[38;2;0;255;0m\U0001f468\u200d\U0001f4bb\x1b[0m"
    "C"
    "\x1b[38;2;0;0;255m1\ufe0f\u20e3\x1b[0m"
    "D"
)
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn wide_grapheme_right_edge_profile() -> TerminalProfile {
    local_profile(
        "wide-grapheme-right-edge",
        "Wide Grapheme Right Edge",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
import time

time.sleep(0.15)
sys.stdout.write("A\U0001f1fa\U0001f1f8B")
sys.stdout.flush()
time.sleep(0.1)
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    )
}

fn vt220_bracketed_paste_mode_profile() -> TerminalProfile {
    local_profile(
        "vt220-bracketed-paste-mode",
        "VT220 Bracketed Paste Mode",
        "/bin/sh",
        vec!["-lc".to_string(), "printf '\\033[?2004hPASTE'".to_string()],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn vt220_wraparound_repaint_profile() -> TerminalProfile {
    local_profile(
        "vt220-wraparound-repaint",
        "VT220 Wraparound Repaint",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 -c 'import sys,time; sys.stdout.write("\x1b[2J\x1b[H*****\n***\n*****"); sys.stdout.flush(); time.sleep(0.35); sys.stdout.write("\x1b[H***************"); sys.stdout.flush()'"#
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Vt220,
    )
}

fn wait_for_frame_containing(session_id: u64, needle: &str) -> String {
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap()
            && frame.contains(needle)
        {
            return frame;
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for frame containing {needle}");
}

fn wait_for_frame_where(session_id: u64, predicate: impl Fn(&str) -> bool) -> String {
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        if let Some(frame) = session::take_frame_diff(session_id)
            .unwrap()
            .filter(|frame| predicate(frame))
        {
            return frame;
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for matching frame");
}

#[cfg(target_os = "macos")]
struct SessionGuard {
    session_id: u64,
}

#[cfg(target_os = "macos")]
impl SessionGuard {
    fn new(session_id: u64) -> Self {
        Self { session_id }
    }

    fn id(&self) -> u64 {
        self.session_id
    }
}

#[cfg(target_os = "macos")]
impl Drop for SessionGuard {
    fn drop(&mut self) {
        let _ = session::close_session(self.session_id);
    }
}

fn wait_for_event(session_id: u64, kind: &str) -> serde_json::Value {
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        if let Some(event) = parsed
            .as_array()
            .and_then(|entries| entries.iter().find(|entry| entry["kind"] == kind))
        {
            return event.clone();
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for event {kind:?}");
}

fn collect_events_until(
    session_id: u64,
    predicate: impl Fn(&[serde_json::Value]) -> bool,
) -> Vec<serde_json::Value> {
    let mut collected = Vec::new();
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        if let Some(entries) = parsed.as_array() {
            collected.extend(entries.iter().cloned());
        }
        if predicate(&collected) {
            return collected;
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!(
        "timed out waiting for event batch: {}",
        serde_json::to_string_pretty(&collected).unwrap()
    );
}

fn wait_for_shell_hook(session_id: u64, hook: &str) -> serde_json::Value {
    for _ in 0..30 {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        if let Some(event) = parsed.as_array().and_then(|entries| {
            entries.iter().find(|entry| {
                entry["kind"] == "shell_hook" && entry["payload"]["hook"].as_str() == Some(hook)
            })
        }) {
            return event.clone();
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for shell hook {hook:?}");
}

fn wait_for_shell_hook_sequence(session_id: u64, hooks: &[&str]) -> Vec<serde_json::Value> {
    let mut events = Vec::new();
    for _ in 0..30 {
        let polled = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&polled).unwrap();
        if let Some(entries) = parsed.as_array() {
            for entry in entries {
                if entry["kind"] != "shell_hook" {
                    continue;
                }
                let Some(next_hook) = hooks.get(events.len()) else {
                    return events;
                };
                if entry["payload"]["hook"].as_str() == Some(next_hook) {
                    events.push(entry.clone());
                    if events.len() == hooks.len() {
                        return events;
                    }
                }
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for shell hooks {hooks:?}");
}

fn find_shell(name: &str) -> Option<String> {
    [
        format!("/bin/{name}"),
        format!("/usr/bin/{name}"),
        format!("/opt/homebrew/bin/{name}"),
        format!("/usr/local/bin/{name}"),
    ]
    .into_iter()
    .find(|path| Path::new(path.as_str()).exists())
}

fn fish_runtime_stays_open(fish_path: &str) -> bool {
    let Ok(home) = tempdir() else {
        return false;
    };
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "fish-runtime-probe",
        "Fish Runtime Probe",
        fish_path,
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.shell_integration.enabled = false;
    let Ok(profile_json) = serde_json::to_string(&profile) else {
        return false;
    };
    let Ok(session_id) = session::create_session(&profile_json) else {
        return false;
    };
    thread::sleep(Duration::from_millis(250));
    let exited = session::poll_events(session_id)
        .ok()
        .and_then(|events| serde_json::from_str::<serde_json::Value>(&events).ok())
        .and_then(|events| {
            events.as_array().map(|entries| {
                entries
                    .iter()
                    .any(|entry| entry["kind"].as_str() == Some("exit"))
            })
        })
        .unwrap_or(true);
    let _ = session::close_session(session_id);
    !exited
}

fn assert_shell_hook_command_lifecycle(session_id: u64, shell: &str) {
    session::write_session(session_id, b"echo ok\n").unwrap();
    let hooks = wait_for_shell_hook_sequence(session_id, &["preexec", "command_finished"]);
    let preexec_event = &hooks[0];
    assert_eq!(preexec_event["payload"]["shell"].as_str(), Some(shell));
    assert_eq!(
        preexec_event["payload"]["command"].as_str(),
        Some("echo ok")
    );
    let finished_event = &hooks[1];
    assert_eq!(finished_event["payload"]["shell"].as_str(), Some(shell));
    assert_eq!(
        finished_event["payload"]["command"].as_str(),
        Some("echo ok")
    );
    assert_eq!(finished_event["payload"]["exit_code"].as_i64(), Some(0));

    session::write_session(session_id, b"false\n").unwrap();
    let hooks = wait_for_shell_hook_sequence(session_id, &["preexec", "command_finished"]);
    let failed_event = &hooks[1];
    assert_eq!(failed_event["payload"]["shell"].as_str(), Some(shell));
    assert_eq!(failed_event["payload"]["command"].as_str(), Some("false"));
    assert_eq!(failed_event["payload"]["exit_code"].as_i64(), Some(1));
}

fn assert_event_kind_never_arrives(session_id: u64, kind: &str) {
    for _ in 0..10 {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        let matching = parsed
            .as_array()
            .expect("expected events array")
            .iter()
            .find(|entry| entry["kind"] == kind);
        assert!(
            matching.is_none(),
            "unexpected event {kind:?}: {}",
            serde_json::to_string_pretty(&parsed).unwrap()
        );
        thread::sleep(Duration::from_millis(50));
    }
}

fn selection_request(
    start_row: usize,
    start_col: usize,
    end_row: usize,
    end_col: usize,
    block: bool,
) -> String {
    serde_json::json!({
        "start_row": start_row,
        "start_col": start_col,
        "end_row": end_row,
        "end_col": end_col,
        "block": block,
    })
    .to_string()
}

fn logical_rows_from_frame(frame: &str) -> Vec<String> {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    let rows = parsed["rows"].as_array().expect("expected rows");
    let mut logical_rows = Vec::new();
    let mut current = String::new();

    for row in rows {
        current.push_str(row["text"].as_str().unwrap_or_default().trim_end());
        if !row["wrapped"].as_bool().unwrap_or(false) {
            logical_rows.push(std::mem::take(&mut current));
        }
    }

    if !current.is_empty() {
        logical_rows.push(current);
    }

    logical_rows
}

fn frame_row_with_text<'a>(frame: &'a serde_json::Value, needle: &str) -> &'a serde_json::Value {
    frame["rows"]
        .as_array()
        .and_then(|rows| {
            rows.iter()
                .find(|row| row["text"].as_str().unwrap_or_default().contains(needle))
        })
        .expect("expected matching frame row")
}

fn assert_frame_json_protobuf_foreground_parity<const N: usize>(
    frame: &str,
    marker: &str,
    expected_foregrounds: [&str; N],
) {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    let json_row = frame_row_with_text(&parsed, marker);
    let frame_model: ianvs_core::model::TerminalFrameDiff = serde_json::from_str(frame).unwrap();
    // `take_frame_diff_protobuf` delegates to this encoder. Encoding the PTY-produced
    // JSON model proves parity for the exact frame, without introducing PTY timing skew.
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model)
        .expect("encode the same frame as protobuf");
    let protobuf = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes)
        .expect("decode the same protobuf frame");
    let protobuf_row = protobuf
        .rows
        .iter()
        .find(|row| row.text.contains(marker))
        .expect("expected matching protobuf frame row");

    for (column, expected) in expected_foregrounds.into_iter().enumerate() {
        let json_foreground = json_row["style_runs"]
            .as_array()
            .and_then(|runs| {
                runs.iter().find(|run| {
                    run["start"]
                        .as_u64()
                        .is_some_and(|start| start <= column as u64)
                        && run["end"].as_u64().is_some_and(|end| end > column as u64)
                })
            })
            .and_then(|run| run["foreground"].as_str())
            .expect("expected JSON foreground for indexed-color cell");
        assert_eq!(json_foreground, expected, "JSON column {column}");

        let protobuf_foreground = protobuf_row
            .style_runs
            .iter()
            .find(|run| run.start <= column as u32 && run.end > column as u32)
            .and_then(|run| run.foreground)
            .expect("expected protobuf foreground for indexed-color cell");
        assert!(protobuf_foreground.present);
        assert_eq!(
            protobuf_foreground.rgb,
            u32::from_str_radix(expected.trim_start_matches('#'), 16).unwrap(),
            "protobuf column {column}"
        );
    }
}

fn assert_frame_json_protobuf_pointer_shape_parity(frame: &str, expected: &str) {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    assert_eq!(parsed["pointer_shape"].as_str(), Some(expected));
    let frame_model: ianvs_core::model::TerminalFrameDiff = serde_json::from_str(frame).unwrap();
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model)
        .expect("encode the same pointer-shape frame as protobuf");
    let protobuf = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes)
        .expect("decode the same pointer-shape protobuf frame");
    assert_eq!(protobuf.pointer_shape, expected);
}

fn assert_frame_json_protobuf_selection_color_parity(
    frame: &str,
    expected_background: u32,
    expected_foreground: u32,
) {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    let expected_background_hex = format!("#{expected_background:06x}");
    let expected_foreground_hex = format!("#{expected_foreground:06x}");
    assert_eq!(
        parsed["selection_background"].as_str(),
        Some(expected_background_hex.as_str())
    );
    assert_eq!(
        parsed["selection_foreground"].as_str(),
        Some(expected_foreground_hex.as_str())
    );
    let frame_model: ianvs_core::model::TerminalFrameDiff = serde_json::from_str(frame).unwrap();
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model)
        .expect("encode selection-color frame");
    let protobuf = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes)
        .expect("decode selection-color protobuf frame");
    let background = protobuf
        .selection_background
        .expect("protobuf selection background");
    let foreground = protobuf
        .selection_foreground
        .expect("protobuf selection foreground");
    assert!(background.present);
    assert!(foreground.present);
    assert_eq!(background.rgb, expected_background);
    assert_eq!(foreground.rgb, expected_foreground);
}

fn assert_frame_json_protobuf_iterm_color_parity(frame: &str) {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    assert_eq!(parsed["link_color"].as_str(), Some("#00ffff"));
    assert_eq!(parsed["cursor_text_color"].as_str(), Some("#0000ff"));
    assert_eq!(parsed["tab_color"].as_str(), Some("#123456"));
    let json_row = frame_row_with_text(&parsed, "BUR ITERM-COLORS");
    assert_eq!(
        json_row["style_runs"][1]["underline_color"].as_str(),
        Some("#00ff00")
    );
    assert_eq!(
        json_row["style_runs"][2]["foreground"].as_str(),
        Some("#aabbcc")
    );

    let frame_model: ianvs_core::model::TerminalFrameDiff = serde_json::from_str(frame).unwrap();
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model)
        .expect("encode iTerm color frame");
    let protobuf = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes)
        .expect("decode iTerm color protobuf frame");
    assert_eq!(protobuf.link_color.expect("link color").rgb, 0x00ffff);
    assert_eq!(
        protobuf.cursor_text_color.expect("cursor text color").rgb,
        0x0000ff
    );
    assert_eq!(protobuf.tab_color.expect("tab color").rgb, 0x123456);
    let row = protobuf
        .rows
        .iter()
        .find(|row| row.text.contains("BUR ITERM-COLORS"))
        .expect("iTerm styled protobuf row");
    assert_eq!(
        row.style_runs[1]
            .underline_color
            .expect("underline color")
            .rgb,
        0x00ff00
    );
    assert_eq!(
        row.style_runs[2]
            .foreground
            .expect("palette foreground")
            .rgb,
        0xaabbcc
    );
}

fn assert_frame_json_protobuf_tab_color_parity(frame: &str, expected: u32) {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    let expected_hex = format!("#{expected:06x}");
    assert_eq!(parsed["tab_color"].as_str(), Some(expected_hex.as_str()));
    let frame_model: ianvs_core::model::TerminalFrameDiff = serde_json::from_str(frame).unwrap();
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model)
        .expect("encode tab-color frame");
    let protobuf = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes)
        .expect("decode tab-color protobuf frame");
    assert_eq!(
        protobuf.tab_color.expect("protobuf tab color").rgb,
        expected
    );
}

fn assert_frame_json_protobuf_cursor_override_parity(
    frame: &str,
    expected_shape: Option<&str>,
    expected_blink: Option<bool>,
) {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    assert_eq!(parsed["cursor"]["shape"].as_str(), expected_shape);
    assert_eq!(parsed["cursor"]["blink"].as_bool(), expected_blink);
    let frame_model: ianvs_core::model::TerminalFrameDiff = serde_json::from_str(frame).unwrap();
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model)
        .expect("encode the same cursor-override frame as protobuf");
    let protobuf = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes)
        .expect("decode the same cursor-override protobuf frame");
    let cursor = protobuf.cursor.expect("protobuf cursor");
    assert_eq!(cursor.shape.as_deref(), expected_shape);
    assert_eq!(cursor.blink, expected_blink);
}

fn assert_frame_json_protobuf_cursor_guide_parity(frame: &str, expected: bool) {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    assert_eq!(parsed["cursor"]["highlight_line"].as_bool(), Some(expected));
    assert_eq!(parsed["cursor_guide_color"].as_str(), Some("#a6e8ff"));

    let frame_model: ianvs_core::model::TerminalFrameDiff = serde_json::from_str(frame).unwrap();
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model)
        .expect("encode the same cursor-guide frame as protobuf");
    let protobuf = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes)
        .expect("decode the same cursor-guide protobuf frame");
    assert_eq!(
        protobuf.cursor.as_ref().map(|cursor| cursor.highlight_line),
        Some(expected)
    );
    assert_eq!(
        protobuf.cursor_guide_color.as_ref().map(|color| color.rgb),
        Some(0xa6e8ff)
    );
}

fn assert_frame_json_protobuf_sized_text_parity(frame: &str) {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    let placement = &parsed["sized_text"][0];
    assert_eq!(placement["text"], "AB");
    assert_eq!(placement["row"], 0);
    assert_eq!(placement["col"], 0);
    assert_eq!(placement["width_cells"], 4);
    assert_eq!(placement["height_cells"], 2);
    assert_eq!(placement["scale"], 2);
    assert_eq!(placement["subscale_n"], 1);
    assert_eq!(placement["subscale_d"], 2);
    assert_eq!(placement["vertical_align"], 2);
    assert_eq!(placement["horizontal_align"], 1);

    let frame_model: ianvs_core::model::TerminalFrameDiff = serde_json::from_str(frame).unwrap();
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model)
        .expect("encode the same sized-text frame as protobuf");
    let protobuf = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes)
        .expect("decode the same sized-text protobuf frame");
    let placement = &protobuf.sized_text[0];
    assert_eq!(placement.text, "AB");
    assert_eq!(placement.row, 0);
    assert_eq!(placement.col, 0);
    assert_eq!(placement.width_cells, 4);
    assert_eq!(placement.height_cells, 2);
    assert_eq!(placement.scale, 2);
    assert_eq!(placement.subscale_n, 1);
    assert_eq!(placement.subscale_d, 2);
    assert_eq!(placement.vertical_align, 2);
    assert_eq!(placement.horizontal_align, 1);
}

fn frame_row_at_index(frame: &serde_json::Value, index: u64) -> &serde_json::Value {
    frame["rows"]
        .as_array()
        .and_then(|rows| rows.iter().find(|row| row["index"].as_u64() == Some(index)))
        .expect("expected matching frame row index")
}

fn frame_has_blank_viewport_row(frame: &str, row_index: usize) -> bool {
    let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
    parsed["rows"].as_array().into_iter().flatten().any(|row| {
        row["index"].as_u64() == Some(row_index as u64)
            && row["text"].as_str().unwrap_or_default().trim().is_empty()
    })
}

#[test]
fn ping_returns_expected_value() {
    assert_eq!(session::ping(), 42);
}

#[test]
fn osc1337_download_crosses_session_event_and_one_shot_binary_bridge() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_where(session_id, |_| true);
    session::write_session(
        session_id,
        b"printf '\\033]1337;File=name=cmVwb3J0LnR4dA==;size=5;inline=0:aGVsbG8=\\007'\n",
    )
    .unwrap();

    let event = wait_for_event(session_id, "file_download");
    assert_eq!(event["payload"]["source"], "iterm1337");
    assert_eq!(event["payload"]["filename"], "report.txt");
    assert_eq!(event["payload"]["size"], 5);
    let download_id = event["payload"]["transferId"]
        .as_str()
        .and_then(|value| value.parse::<u64>().ok())
        .expect("download event must carry an opaque numeric string token");

    session::resize_session(session_id, 91, 25, 0, 0).unwrap();
    thread::sleep(Duration::from_millis(100));
    let replay_events: serde_json::Value =
        serde_json::from_str(&session::poll_events(session_id).unwrap()).unwrap();
    assert!(
        replay_events
            .as_array()
            .is_some_and(|events| { events.iter().all(|event| event["kind"] != "file_download") })
    );

    let mut bytes = [0_u8; 5];
    assert_eq!(
        session::take_file_download(session_id, download_id, &mut bytes).unwrap(),
        5
    );
    assert_eq!(&bytes, b"hello");
    assert!(session::take_file_download(session_id, download_id, &mut bytes).is_err());

    session::close_session(session_id).unwrap();
}

#[test]
fn refresh_hint_clears_after_frame_is_consumed() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();

    assert_eq!(session::REFRESH_HINT_FRAME_DIRTY, 1);
    assert_eq!(
        session::refresh_hint_flags(session_id).unwrap(),
        session::REFRESH_HINT_FRAME_DIRTY
    );

    let _ = wait_for_frame_containing(session_id, "hello");

    assert_eq!(session::refresh_hint_flags(session_id).unwrap(), 0);
    session::close_session(session_id).unwrap();
}

#[test]
fn refresh_hint_ignores_resize_damage_without_consuming_it() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "hello");

    session::resize_session(session_id, 90, 20, 0, 0).unwrap();

    assert_eq!(session::refresh_hint_flags(session_id).unwrap(), 0);
    assert_eq!(session::refresh_hint_flags(session_id).unwrap(), 0);
    let resized = session::take_frame_diff(session_id)
        .unwrap()
        .expect("resize hint must leave frame damage available");
    assert!(resized.contains("\"viewport_rows\":20"));
    assert_eq!(
        session::refresh_hint_flags(session_id).unwrap(),
        0,
        "resize damage must never publish a reader-driven refresh hint"
    );
    session::close_session(session_id).unwrap();
}

#[test]
fn refresh_hint_reports_pty_output_damage() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_where(session_id, |_| true);

    session::write_session(session_id, b"printf 'refresh-hint-output\\n'\n").unwrap();
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        if session::refresh_hint_flags(session_id).unwrap() == 1 {
            assert_eq!(session::refresh_hint_flags(session_id).unwrap(), 1);
            session::close_session(session_id).unwrap();
            return;
        }
        thread::sleep(Duration::from_millis(10));
    }

    session::close_session(session_id).unwrap();
    panic!("timed out waiting for PTY output refresh hint");
}

#[test]
fn ffi_refresh_hint_returns_zero_for_invalid_and_closed_sessions() {
    assert_eq!(ianvs_core::ffi::ianvs_session_refresh_hint(u64::MAX), 0);

    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    session::close_session(session_id).unwrap();

    assert_eq!(ianvs_core::ffi::ianvs_session_refresh_hint(session_id), 0);
}

#[test]
fn session_emits_frame_diff_for_simple_command() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");

    assert!(frame.contains("hello"));
    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_declares_schema_version() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(
        parsed["frame_schema_version"].as_str(),
        Some("terminal-frame-diff-v1"),
        "frame diffs must carry an explicit schema version: {}",
        serde_json::to_string_pretty(&parsed).unwrap()
    );
    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_global_bottom_row_has_json_protobuf_parity() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame_json = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame_json).unwrap();
    let frame_model: ianvs_core::model::TerminalFrameDiff =
        serde_json::from_str(&frame_json).unwrap();
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model)
        .expect("encode protobuf frame");
    let protobuf = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes)
        .expect("decode protobuf frame");

    let json_global_bottom = parsed["global_bottom_row"]
        .as_u64()
        .expect("JSON frame global bottom row");
    assert_eq!(json_global_bottom, frame_model.global_bottom_row);
    assert_eq!(protobuf.global_bottom_row, Some(json_global_bottom));
    assert!(
        json_global_bottom >= u64::from(frame_model.viewport_rows.saturating_sub(1)),
        "global bottom must cover the live viewport"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_protobuf_exposes_core_fields() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let bytes = session::take_frame_diff_protobuf(session_id)
        .expect("protobuf result")
        .expect("protobuf frame");
    assert!(!bytes.is_empty(), "protobuf payload should not be empty");

    let decoded = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&bytes)
        .expect("decode protobuf frame");
    assert_eq!(decoded.frame_schema_version, "terminal-frame-diff-v1");
    assert!(decoded.viewport_rows > 0);
    assert!(decoded.viewport_cols > 0);
    assert!(!decoded.rows.is_empty());
    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_protobuf_preserves_graphic_asset_version_for_loading() {
    let profile = local_profile(
        "protobuf-kitty-asset-version",
        "Protobuf Kitty Asset Version",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b_Ga=T,t=d,f=100,c=1,r=1,q=2,i=49374;{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.4)\nPY",
                RED_PIXEL_PNG_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    let deadline = Instant::now() + Duration::from_secs(3);
    let asset_key = loop {
        if let Some(bytes) = session::take_frame_diff_protobuf(session_id).unwrap() {
            let decoded = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&bytes)
                .expect("decode protobuf frame");
            if let Some(asset_key) = decoded
                .graphics
                .into_iter()
                .find_map(|graphic| graphic.asset_key)
            {
                break asset_key;
            }
        }
        assert!(
            Instant::now() < deadline,
            "timed out waiting for Kitty graphic in protobuf frame"
        );
        thread::sleep(Duration::from_millis(10));
    };

    assert_eq!(asset_key.asset_id, 49374);
    assert!(
        asset_key.asset_version > u64::from(u32::MAX),
        "test fixture must exercise the former uint32 truncation"
    );
    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_key.asset_id,
            asset_key.asset_version,
            &mut meta,
        )
    };
    assert_eq!(status, 0);
    assert_eq!(meta.version, asset_key.asset_version);
    assert_eq!(meta.rgba_len, 4);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_debug_stats_include_protobuf_encode_micros() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let _ = session::take_frame_diff_protobuf(session_id)
        .expect("protobuf result")
        .expect("protobuf frame");
    let debug_stats = session::take_frame_debug_stats_json(session_id)
        .expect("debug stats result")
        .expect("debug stats");
    let parsed: serde_json::Value = serde_json::from_str(&debug_stats).unwrap();

    assert!(parsed["protobuf_encode_micros"].as_u64().is_some());
    session::close_session(session_id).unwrap();
}

#[test]
fn ffi_take_frame_diff_protobuf_returns_bytes_and_len() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let mut len = 0usize;
    let ptr =
        unsafe { ianvs_core::ffi::ianvs_session_take_frame_diff_protobuf(session_id, &mut len) };
    assert!(!ptr.is_null());
    assert!(len > 0);

    unsafe {
        let bytes = std::slice::from_raw_parts(ptr, len);
        assert!(!bytes.is_empty());
        ianvs_core::ffi::ianvs_bytes_free(ptr, len);
    }
    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_omits_empty_optional_fields() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let object = parsed.as_object().expect("expected frame object");

    assert!(!object.contains_key("selection"));
    assert!(!object.contains_key("window_title"));
    assert!(!object.contains_key("window_icon_name"));
    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_graphic_placements_and_asset_bytes() {
    let profile = local_profile(
        "iterm-graphics",
        "iTerm Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1b]1337;File=inline=1;width=2;height=2:{}\\x1b\\\\')\nsys.stdout.flush()\nPY",
                RED_PIXEL_PNG_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"graphics\":[{"));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(graphics.len(), 1, "expected one graphic placement: {frame}");
    let placement = &graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("iterm"));
    assert_eq!(placement["row"].as_u64(), Some(0));
    assert_eq!(placement["col"].as_u64(), Some(0));
    assert_eq!(placement["width_px"].as_u64(), Some(2));
    assert_eq!(placement["height_px"].as_u64(), Some(4));
    assert_eq!(placement["width_cells"].as_u64(), Some(2));
    assert_eq!(placement["height_cells"].as_u64(), Some(2));
    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected graphic asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected graphic asset version");
    assert!(
        asset_version <= 9_007_199_254_740_991,
        "graphic asset version must round-trip through JSON safely"
    );

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 4);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(rgba.len(), 4);

    assert_eq!(
        unsafe {
            ianvs_core::ffi::ianvs_session_graphic_asset_meta(
                session_id,
                asset_id,
                asset_version + 1,
                &mut meta,
            )
        },
        -1,
        "stale asset version should be rejected"
    );
    assert_eq!(
        unsafe {
            ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
                session_id,
                asset_id,
                asset_version,
                ptr::null_mut(),
                rgba.len(),
            )
        },
        -1,
        "null destination should be rejected"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_iterm_inline_image_alpha_pixels() {
    let profile = local_profile(
        "iterm-alpha-graphics",
        "iTerm Alpha Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=2px;height=1px;preserveAspectRatio=0:{}\\x1b\\\\')\nsys.stdout.flush()\nPY",
                TRANSPARENT_RED_2X1_PNG_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"iterm\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(
        graphics.len(),
        1,
        "expected one alpha iTerm2 placement: {frame}"
    );
    let placement = &graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("iterm"));
    assert_eq!(placement["width_px"].as_u64(), Some(2));
    assert_eq!(placement["height_px"].as_u64(), Some(1));
    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected iTerm2 asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected iTerm2 asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 2);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 2 * 4);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(
        rgba,
        [0, 0, 0, 0, 255, 0, 0, 128],
        "iTerm2 inline image alpha should survive asset RGBA export"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_imgcat_style_iterm_wrapped_unpadded_payload() {
    let unpadded_payload = RED_PIXEL_PNG_BASE64.trim_end_matches('=');
    let wrapped_payload = unpadded_payload
        .as_bytes()
        .chunks(17)
        .map(|chunk| std::str::from_utf8(chunk).unwrap())
        .collect::<Vec<_>>()
        .join("\n\t");
    let profile = local_profile(
        "iterm-imgcat-wrapped-unpadded-graphics",
        "iTerm imgcat Wrapped Unpadded Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\npayload = '''{}'''\nsys.stdout.write('\\x1b]1337;File=name=cGl4ZWwucG5n;size={};inline=1;width=auto;height=auto;preserveAspectRatio=1:' + payload + '\\x1b\\\\')\nsys.stdout.flush()\nPY",
                wrapped_payload,
                red_pixel_png_bytes().len()
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"iterm\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(
        graphics.len(),
        1,
        "expected one imgcat-style iTerm2 placement: {frame}"
    );
    let placement = &graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("iterm"));
    assert_eq!(placement["row"].as_u64(), Some(0));
    assert_eq!(placement["col"].as_u64(), Some(0));
    assert_eq!(placement["width_px"].as_u64(), Some(1));
    assert_eq!(placement["height_px"].as_u64(), Some(1));
    assert_eq!(placement["width_cells"].as_u64(), Some(1));
    assert_eq!(placement["height_cells"].as_u64(), Some(1));
    assert_eq!(placement["preserve_aspect_ratio"].as_bool(), Some(true));
    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected iTerm2 asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected iTerm2 asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 4);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(
        rgba,
        [255, 0, 0, 255],
        "imgcat-style iTerm2 image should decode to the expected red pixel"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_screen_wrapped_iterm_inline_image() {
    let profile = local_profile(
        "iterm-screen-wrapped-graphics",
        "iTerm Screen Wrapped Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1b[3;4H')\nsys.stdout.write('\\x1bP\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=2;height=2;preserveAspectRatio=0:{}\\x07\\x1b\\\\')\nsys.stdout.flush()\nPY",
                RED_PIXEL_PNG_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"iterm\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(
        graphics.len(),
        1,
        "expected one screen-wrapped iTerm2 placement: {frame}"
    );
    let placement = &graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("iterm"));
    assert_eq!(placement["row"].as_u64(), Some(2));
    assert_eq!(placement["col"].as_u64(), Some(3));
    assert_eq!(placement["width_px"].as_u64(), Some(2));
    assert_eq!(placement["height_px"].as_u64(), Some(4));
    assert_eq!(placement["width_cells"].as_u64(), Some(2));
    assert_eq!(placement["height_cells"].as_u64(), Some(2));
    assert_eq!(placement["preserve_aspect_ratio"].as_bool(), Some(false));
    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected screen-wrapped iTerm2 asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected screen-wrapped iTerm2 asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 4);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(
        rgba,
        [255, 0, 0, 255],
        "screen-wrapped iTerm2 image should decode to the expected red pixel"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_tmux_wrapped_iterm_inline_image() {
    let profile = local_profile(
        "iterm-tmux-wrapped-graphics",
        "iTerm Tmux Wrapped Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                r#"python3 - <<'PY'
import sys

inner = '\x1b]1337;File=inline=1;doNotMoveCursor=1;width=2;height=2;preserveAspectRatio=0:{payload}\x1b\\'
wrapped = '\x1bPtmux;' + inner.replace('\x1b', '\x1b\x1b') + '\x1b\\'
sys.stdout.write('\x1b[4;5H')
sys.stdout.write(wrapped)
sys.stdout.flush()
PY"#,
                payload = RED_PIXEL_PNG_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"iterm\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(
        graphics.len(),
        1,
        "expected one tmux-wrapped iTerm2 placement: {frame}"
    );
    let placement = &graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("iterm"));
    assert_eq!(placement["row"].as_u64(), Some(3));
    assert_eq!(placement["col"].as_u64(), Some(4));
    assert_eq!(placement["width_px"].as_u64(), Some(2));
    assert_eq!(placement["height_px"].as_u64(), Some(4));
    assert_eq!(placement["width_cells"].as_u64(), Some(2));
    assert_eq!(placement["height_cells"].as_u64(), Some(2));
    assert_eq!(placement["preserve_aspect_ratio"].as_bool(), Some(false));
    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected tmux-wrapped iTerm2 asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected tmux-wrapped iTerm2 asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 4);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(
        rgba,
        [255, 0, 0, 255],
        "tmux-wrapped iTerm2 image should decode to the expected red pixel"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_iterm_multipart_inline_after_file_end() {
    let (first_chunk, remaining) = RED_PIXEL_PNG_BASE64.split_at(5);
    let (second_chunk, third_chunk) = remaining.split_at(23);
    let chunks_json = serde_json::to_string(&[first_chunk, second_chunk, third_chunk]).unwrap();
    let profile = local_profile(
        "iterm-multipart-inline-frame-diff",
        "iTerm Multipart Inline Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                r#"python3 - <<'PY'
import sys, time

chunks = {chunks_json}

def out(value, delay=0.0):
    sys.stdout.write(value)
    sys.stdout.flush()
    if delay:
        time.sleep(delay)

out('\x1b[2;3H')
out('\x1b]1337;MultipartFile=inline=1;size={decoded_size};name=cGl4ZWwucG5n;width=2;height=2;preserveAspectRatio=0;doNotMoveCursor=1\x1b\\')
out('\x1b]1337;FilePart=' + chunks[0] + '\x1b\\')
out('\x1b[10;1Hmultipart pending\n', 0.35)
out('\x1b[2;3H')
for chunk in chunks[1:]:
    out('\x1b]1337;FilePart=' + chunk + '\x1b\\')
out('\x1b]1337;FileEnd\x1b\\', 0.15)
PY"#,
                chunks_json = chunks_json,
                decoded_size = red_pixel_png_bytes().len(),
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let pending_frame =
        wait_for_frame_where(session_id, |frame| frame.contains("multipart pending"));
    let pending_parsed: serde_json::Value = serde_json::from_str(&pending_frame).unwrap();
    let pending_graphics = pending_parsed["graphics"]
        .as_array()
        .expect("expected graphics array in pending multipart frame");
    assert!(
        !pending_graphics
            .iter()
            .any(|graphic| graphic["protocol"].as_str() == Some("iterm")),
        "multipart iTerm2 image must not be exported before FileEnd: {pending_frame}"
    );

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"iterm\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(
        graphics.len(),
        1,
        "expected one multipart iTerm2 placement after FileEnd: {frame}"
    );
    let placement = &graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("iterm"));
    assert_eq!(placement["row"].as_u64(), Some(1));
    assert_eq!(placement["col"].as_u64(), Some(2));
    assert_eq!(placement["width_px"].as_u64(), Some(2));
    assert_eq!(placement["height_px"].as_u64(), Some(4));
    assert_eq!(placement["width_cells"].as_u64(), Some(2));
    assert_eq!(placement["height_cells"].as_u64(), Some(2));
    assert_eq!(placement["preserve_aspect_ratio"].as_bool(), Some(false));
    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected multipart iTerm2 asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected multipart iTerm2 asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 4);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(
        rgba,
        [255, 0, 0, 255],
        "multipart iTerm2 image should decode to the expected red pixel"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_recomputes_percent_graphic_placements_after_resize() {
    let profile = local_profile(
        "iterm-percent-resize-graphics",
        "iTerm Percent Resize Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b]1337;File=inline=1;width=50%;height=50%;preserveAspectRatio=0;doNotMoveCursor=1:{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nPY",
                RED_PIXEL_PNG_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let initial_frame = wait_for_frame_where(session_id, |frame| frame.contains("\"graphics\":[{"));
    let initial: serde_json::Value = serde_json::from_str(&initial_frame).unwrap();
    let initial_graphics = initial["graphics"]
        .as_array()
        .expect("expected initial graphic placements");
    assert_eq!(
        initial_graphics.len(),
        1,
        "expected one initial percent-sized graphic: {initial_frame}"
    );
    let initial_graphic = &initial_graphics[0];
    let initial_cols = initial["viewport_cols"]
        .as_u64()
        .expect("expected initial viewport cols");
    let initial_rows = initial["viewport_rows"]
        .as_u64()
        .expect("expected initial viewport rows");
    assert_eq!(initial_graphic["protocol"].as_str(), Some("iterm"));
    assert_eq!(
        initial_graphic["width_cells"].as_u64(),
        Some(initial_cols / 2)
    );
    assert_eq!(
        initial_graphic["height_cells"].as_u64(),
        Some(initial_rows / 2)
    );

    session::resize_session(session_id, 40, 12, 0, 0).unwrap();

    let resized_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"viewport_cols\":40") && frame.contains("\"graphics\":[{")
    });
    let resized: serde_json::Value = serde_json::from_str(&resized_frame).unwrap();
    let resized_graphics = resized["graphics"]
        .as_array()
        .expect("expected resized graphic placements");
    assert_eq!(
        resized_graphics.len(),
        1,
        "expected one resized percent-sized graphic: {resized_frame}"
    );
    let placement = &resized_graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("iterm"));
    assert_eq!(placement["width_cells"].as_u64(), Some(20));
    assert_eq!(placement["height_cells"].as_u64(), Some(6));
    assert_eq!(placement["width_px"].as_u64(), Some(20));
    assert_eq!(placement["height_px"].as_u64(), Some(12));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_resize_replay_preserves_profile_graphics_memory_limits() {
    for (case_name, max_image_bytes, max_total_bytes) in
        [("per-image", 3, 1024), ("total", 1024, 3)]
    {
        let profile_id = format!("resize-graphics-limit-{case_name}");
        let mut profile = local_profile(
            &profile_id,
            "Resize Graphics Limit",
            "/bin/sh",
            vec![
                "-lc".to_string(),
                format!(
                    "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b]1337;File=inline=1;doNotMoveCursor=1:{}\\x1b\\\\')\nsys.stdout.write('WAITING\\n')\nsys.stdout.flush()\ntime.sleep(2)\nPY",
                    RED_PIXEL_PNG_BASE64
                ),
            ],
            BTreeMap::new(),
            TerminalEmulation::Xterm256,
        );
        profile.terminal.graphics.max_image_bytes = max_image_bytes;
        profile.terminal.graphics.max_total_bytes = max_total_bytes;
        let session_id =
            session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

        let initial_frame = wait_for_frame_containing(session_id, "WAITING");
        let initial: serde_json::Value = serde_json::from_str(&initial_frame).unwrap();
        assert_eq!(
            initial["graphics"].as_array().map(Vec::len),
            Some(0),
            "{case_name} limit must reject the image before resize: {initial_frame}"
        );

        session::resize_session(session_id, 100, 30, 1000, 600).unwrap();
        let resized_frame = wait_for_frame_where(session_id, |frame| {
            frame.contains("\"viewport_cols\":100") && frame.contains("\"viewport_rows\":30")
        });
        let resized: serde_json::Value = serde_json::from_str(&resized_frame).unwrap();
        assert_eq!(
            resized["graphics"].as_array().map(Vec::len),
            Some(0),
            "{case_name} limit must survive transcript replay: {resized_frame}"
        );

        session::close_session(session_id).unwrap();
    }
}

#[test]
fn session_frame_diff_recomputes_percent_iterm_scrollback_placements_after_resize() {
    let profile = local_profile_with_scrollback(
        "iterm-percent-scrollback-resize-graphics",
        "iTerm Percent Scrollback Resize Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1b[1;1H\\x1b]1337;File=inline=1;width=50%;height=50%;preserveAspectRatio=0;doNotMoveCursor=1:{}\\x1b\\\\')\nsys.stdout.write('\\x1b[32;1H')\nfor i in range(80):\n    sys.stdout.write(f'line-{{i:02d}}\\n')\nsys.stdout.flush()\nPY",
                RED_PIXEL_PNG_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let initial_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("iterm"))
        })
    });
    let initial: serde_json::Value = serde_json::from_str(&initial_frame).unwrap();
    assert_eq!(
        initial["scrollback_offset"].as_u64(),
        initial["scrollback_max_offset"].as_u64(),
        "scroll-to-top frame should expose retained percent-sized iTerm2 scrollback placement before resize: {initial_frame}"
    );
    let initial_placement = initial["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["protocol"].as_str() == Some("iterm"))
        })
        .expect("expected iTerm2 scrollback placement before resize");
    let initial_cols = initial["viewport_cols"]
        .as_u64()
        .expect("expected initial viewport cols");
    let initial_rows = initial["viewport_rows"]
        .as_u64()
        .expect("expected initial viewport rows");
    assert_eq!(
        initial_placement["width_cells"].as_u64(),
        Some(initial_cols / 2)
    );
    assert_eq!(
        initial_placement["height_cells"].as_u64(),
        Some(initial_rows / 2)
    );
    assert_eq!(
        initial_placement["width_px"].as_u64(),
        Some(initial_cols / 2)
    );
    assert_eq!(initial_placement["height_px"].as_u64(), Some(initial_rows));

    session::resize_session(session_id, 40, 12, 0, 0).unwrap();
    session::scroll_to_session(session_id, usize::MAX).unwrap();

    let resized_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["viewport_cols"].as_u64() == Some(40)
            && parsed["graphics"].as_array().is_some_and(|graphics| {
                graphics
                    .iter()
                    .any(|graphic| graphic["protocol"].as_str() == Some("iterm"))
            })
    });
    let resized: serde_json::Value = serde_json::from_str(&resized_frame).unwrap();
    assert_eq!(
        resized["scrollback_offset"].as_u64(),
        resized["scrollback_max_offset"].as_u64(),
        "scroll-to-top frame should expose retained percent-sized iTerm2 scrollback placement after resize: {resized_frame}"
    );
    let resized_placement = resized["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["protocol"].as_str() == Some("iterm"))
        })
        .expect("expected iTerm2 scrollback placement after resize");
    assert_eq!(resized_placement["width_cells"].as_u64(), Some(20));
    assert_eq!(resized_placement["height_cells"].as_u64(), Some(6));
    assert_eq!(resized_placement["width_px"].as_u64(), Some(20));
    assert_eq!(resized_placement["height_px"].as_u64(), Some(12));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_recomputes_sixel_and_kitty_placements_after_cell_resize() {
    fn placement_with_protocol<'a>(
        parsed: &'a serde_json::Value,
        protocol: &str,
    ) -> &'a serde_json::Value {
        parsed["graphics"]
            .as_array()
            .expect("expected graphics placements")
            .iter()
            .find(|graphic| graphic["protocol"].as_str() == Some(protocol))
            .unwrap_or_else(|| panic!("expected {protocol} placement: {parsed}"))
    }

    let raw_pixels = [255u8, 0, 0, 255].repeat(12);
    let raw_rgba_base64 = base64_standard_no_pad_encode(&raw_pixels);
    let profile = local_profile(
        "graphics-cell-resize",
        "Graphics Cell Resize",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[1;1H\\x1bPq#2~\\x1b\\\\')\nsys.stdout.write('\\x1b[8;1H\\x1b_Ga=T,f=32,s=2,v=6,i=62010,q=1;{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nPY",
                raw_rgba_base64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let initial_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"protocol\":\"sixel\"") && frame.contains("\"asset_id\":62010")
    });
    let initial: serde_json::Value = serde_json::from_str(&initial_frame).unwrap();
    for protocol in ["sixel", "kitty"] {
        let placement = placement_with_protocol(&initial, protocol);
        assert_eq!(
            placement["width_cells"].as_u64(),
            Some(2),
            "initial {protocol} placement should span two 1px-wide cells: {initial_frame}"
        );
        assert_eq!(
            placement["height_cells"].as_u64(),
            Some(3),
            "initial {protocol} placement should span three 2px-tall cells: {initial_frame}"
        );
        assert_eq!(placement["width_px"].as_u64(), Some(2));
        assert_eq!(placement["height_px"].as_u64(), Some(6));
    }

    session::resize_session_with_cell_size(session_id, 90, 20, 180, 60, 2, 3).unwrap();

    let resized_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"viewport_cols\":90")
            && frame.contains("\"protocol\":\"sixel\"")
            && frame.contains("\"asset_id\":62010")
    });
    let resized: serde_json::Value = serde_json::from_str(&resized_frame).unwrap();
    for protocol in ["sixel", "kitty"] {
        let placement = placement_with_protocol(&resized, protocol);
        assert_eq!(
            placement["width_cells"].as_u64(),
            Some(1),
            "resized {protocol} placement should recompute against 2px-wide cells: {resized_frame}"
        );
        assert_eq!(
            placement["height_cells"].as_u64(),
            Some(2),
            "resized {protocol} placement should recompute against 3px-tall cells: {resized_frame}"
        );
        assert_eq!(placement["width_px"].as_u64(), Some(2));
        assert_eq!(placement["height_px"].as_u64(), Some(6));
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_preserves_primary_graphics_across_alt_screen_resize() {
    fn placement_with(
        parsed: &serde_json::Value,
        predicate: impl Fn(&serde_json::Value) -> bool,
    ) -> &serde_json::Value {
        parsed["graphics"]
            .as_array()
            .expect("expected graphics placements")
            .iter()
            .find(|graphic| predicate(graphic))
            .unwrap_or_else(|| panic!("expected matching graphic placement: {parsed}"))
    }

    let raw_pixels = [255u8, 0, 0, 255].repeat(12);
    let raw_rgba_base64 = base64_standard_no_pad_encode(&raw_pixels);
    let script = format!(
        r#"
import sys, time

def out(value, delay=0.12):
    sys.stdout.write(value)
    sys.stdout.flush()
    time.sleep(delay)

out('\x1b[1;1H\x1b]1337;File=inline=1;width=2px;height=6px;preserveAspectRatio=0;doNotMoveCursor=1:{png}\x1b\\')
out('\x1b[5;1H\x1bPq#2~\x1b\\')
out('\x1b[9;1H\x1b_Ga=T,f=32,s=2,v=6,i=62012,q=1;{raw}\x1b\\')
out('\x1b[?1049hALT READY\n', 0.85)
out('\x1b[?1049lprimary restored\n', 0.25)
"#,
        png = RED_PIXEL_PNG_BASE64,
        raw = raw_rgba_base64,
    );
    let profile = local_profile(
        "primary-graphics-alt-screen-resize",
        "Primary Graphics Alternate Screen Resize",
        "/usr/bin/env",
        vec!["python3".to_string(), "-c".to_string(), script],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let initial_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"protocol\":\"iterm\"")
            && frame.contains("\"protocol\":\"sixel\"")
            && frame.contains("\"asset_id\":62012")
    });
    let initial: serde_json::Value = serde_json::from_str(&initial_frame).unwrap();
    for (label, placement) in [
        (
            "iTerm2",
            placement_with(&initial, |graphic| {
                graphic["protocol"].as_str() == Some("iterm")
            }),
        ),
        (
            "Sixel",
            placement_with(&initial, |graphic| {
                graphic["protocol"].as_str() == Some("sixel")
            }),
        ),
        (
            "Kitty",
            placement_with(&initial, |graphic| {
                graphic["asset_id"].as_u64() == Some(62012)
            }),
        ),
    ] {
        assert_eq!(
            placement["width_cells"].as_u64(),
            Some(2),
            "initial {label} placement should use the original 1px-wide cell size: {initial_frame}"
        );
        assert_eq!(
            placement["height_cells"].as_u64(),
            Some(3),
            "initial {label} placement should use the original 2px-tall cell size: {initial_frame}"
        );
    }

    let alternate_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("ALT READY")
            && serde_json::from_str::<serde_json::Value>(frame)
                .is_ok_and(|parsed| parsed["modes"]["alternate_screen"].as_bool() == Some(true))
    });
    let alternate: serde_json::Value = serde_json::from_str(&alternate_frame).unwrap();
    assert!(
        alternate["graphics"].as_array().is_none_or(|graphics| {
            graphics.iter().all(|graphic| {
                graphic["protocol"].as_str() != Some("iterm")
                    && graphic["protocol"].as_str() != Some("sixel")
                    && graphic["asset_id"].as_u64() != Some(62012)
            })
        }),
        "primary-screen graphics must not leak into alternate-screen frames before resize: {alternate_frame}"
    );

    session::resize_session_with_cell_size(session_id, 90, 20, 180, 60, 2, 3).unwrap();

    let resized_alternate_frame = wait_for_frame_where(session_id, |frame| {
        serde_json::from_str::<serde_json::Value>(frame).is_ok_and(|parsed| {
            parsed["viewport_cols"].as_u64() == Some(90)
                && parsed["viewport_rows"].as_u64() == Some(20)
                && parsed["modes"]["alternate_screen"].as_bool() == Some(true)
        })
    });
    let resized_alternate: serde_json::Value =
        serde_json::from_str(&resized_alternate_frame).unwrap();
    assert!(
        resized_alternate["graphics"]
            .as_array()
            .is_none_or(|graphics| {
                graphics.iter().all(|graphic| {
                    graphic["protocol"].as_str() != Some("iterm")
                        && graphic["protocol"].as_str() != Some("sixel")
                        && graphic["asset_id"].as_u64() != Some(62012)
                })
            }),
        "primary-screen graphics must stay hidden while resizing alternate screen: {resized_alternate_frame}"
    );

    let restored_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("primary restored")
            && frame.contains("\"viewport_cols\":90")
            && frame.contains("\"protocol\":\"iterm\"")
            && frame.contains("\"protocol\":\"sixel\"")
            && frame.contains("\"asset_id\":62012")
    });
    let restored: serde_json::Value = serde_json::from_str(&restored_frame).unwrap();
    assert_eq!(
        restored["modes"]["alternate_screen"].as_bool(),
        Some(false),
        "restored frame should be back on the primary screen: {restored_frame}"
    );

    let restored_placements = [
        (
            "iTerm2",
            placement_with(&restored, |graphic| {
                graphic["protocol"].as_str() == Some("iterm")
            }),
            0,
        ),
        (
            "Sixel",
            placement_with(&restored, |graphic| {
                graphic["protocol"].as_str() == Some("sixel")
            }),
            4,
        ),
        (
            "Kitty",
            placement_with(&restored, |graphic| {
                graphic["asset_id"].as_u64() == Some(62012)
            }),
            8,
        ),
    ];
    for (label, placement, expected_row) in restored_placements {
        assert_eq!(
            placement["row"].as_u64(),
            Some(expected_row),
            "restored {label} placement should keep its primary-screen anchor row: {restored_frame}"
        );
        assert_eq!(placement["col"].as_u64(), Some(0));
        assert_eq!(placement["width_px"].as_u64(), Some(2));
        assert_eq!(placement["height_px"].as_u64(), Some(6));
        assert_eq!(
            placement["width_cells"].as_u64(),
            Some(1),
            "restored {label} placement should be recomputed against resized 2px-wide cells: {restored_frame}"
        );
        assert_eq!(
            placement["height_cells"].as_u64(),
            Some(2),
            "restored {label} placement should be recomputed against resized 3px-tall cells: {restored_frame}"
        );
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_recomputes_sixel_and_kitty_scrollback_placements_after_cell_resize() {
    fn placement_with_protocol<'a>(
        parsed: &'a serde_json::Value,
        protocol: &str,
    ) -> &'a serde_json::Value {
        parsed["graphics"]
            .as_array()
            .expect("expected graphics placements")
            .iter()
            .find(|graphic| graphic["protocol"].as_str() == Some(protocol))
            .unwrap_or_else(|| panic!("expected {protocol} scrollback placement: {parsed}"))
    }

    let raw_pixels = [255u8, 0, 0, 255].repeat(12);
    let raw_rgba_base64 = base64_standard_no_pad_encode(&raw_pixels);
    let profile = local_profile_with_scrollback(
        "graphics-scrollback-cell-resize",
        "Graphics Scrollback Cell Resize",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1b[1;1H\\x1bPq#2~\\x1b\\\\')\nsys.stdout.write('\\x1b[8;1H\\x1b_Ga=T,f=32,s=2,v=6,i=62011,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b[32;1H')\nfor i in range(80):\n    sys.stdout.write(f'line-{{i:02d}}\\n')\nsys.stdout.flush()\nPY",
                raw_rgba_base64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let initial_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            let has_sixel = graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("sixel"));
            let has_kitty = graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(62011));
            has_sixel && has_kitty
        })
    });
    let initial: serde_json::Value = serde_json::from_str(&initial_frame).unwrap();
    assert_eq!(
        initial["scrollback_offset"].as_u64(),
        initial["scrollback_max_offset"].as_u64(),
        "scroll-to-top frame should expose retained Sixel and Kitty scrollback placements before resize: {initial_frame}"
    );
    for protocol in ["sixel", "kitty"] {
        let placement = placement_with_protocol(&initial, protocol);
        assert_eq!(
            placement["width_cells"].as_u64(),
            Some(2),
            "initial {protocol} scrollback placement should span two 1px-wide cells: {initial_frame}"
        );
        assert_eq!(
            placement["height_cells"].as_u64(),
            Some(3),
            "initial {protocol} scrollback placement should span three 2px-tall cells: {initial_frame}"
        );
        assert_eq!(placement["width_px"].as_u64(), Some(2));
        assert_eq!(placement["height_px"].as_u64(), Some(6));
    }

    session::resize_session_with_cell_size(session_id, 90, 20, 180, 60, 2, 3).unwrap();
    session::scroll_to_session(session_id, usize::MAX).unwrap();

    let resized_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["viewport_cols"].as_u64() == Some(90)
            && parsed["graphics"].as_array().is_some_and(|graphics| {
                let has_sixel = graphics
                    .iter()
                    .any(|graphic| graphic["protocol"].as_str() == Some("sixel"));
                let has_kitty = graphics
                    .iter()
                    .any(|graphic| graphic["asset_id"].as_u64() == Some(62011));
                has_sixel && has_kitty
            })
    });
    let resized: serde_json::Value = serde_json::from_str(&resized_frame).unwrap();
    assert_eq!(
        resized["scrollback_offset"].as_u64(),
        resized["scrollback_max_offset"].as_u64(),
        "scroll-to-top frame should keep Sixel and Kitty scrollback placements visible after resize: {resized_frame}"
    );
    for protocol in ["sixel", "kitty"] {
        let placement = placement_with_protocol(&resized, protocol);
        assert_eq!(
            placement["width_cells"].as_u64(),
            Some(1),
            "resized {protocol} scrollback placement should recompute against 2px-wide cells: {resized_frame}"
        );
        assert_eq!(
            placement["height_cells"].as_u64(),
            Some(2),
            "resized {protocol} scrollback placement should recompute against 3px-tall cells: {resized_frame}"
        );
        assert_eq!(placement["width_px"].as_u64(), Some(2));
        assert_eq!(placement["height_px"].as_u64(), Some(6));
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_iterm_scrollback_placements_when_scrolled_back() {
    let profile = local_profile_with_scrollback(
        "iterm-scrollback-graphics",
        "iTerm Scrollback Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1b[1;1H\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{}\\x1b\\\\')\nsys.stdout.write('\\x1b[32;1H')\nfor i in range(80):\n    sys.stdout.write(f'line-{{i:02d}}\\n')\nsys.stdout.flush()\nPY",
                RED_PIXEL_PNG_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let bottom_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });
    let bottom: serde_json::Value = serde_json::from_str(&bottom_frame).unwrap();
    assert!(
        bottom["graphics"].as_array().is_none_or(|graphics| {
            !graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("iterm"))
        }),
        "iTerm2 scrollback placement should not be emitted while the viewport is at the bottom: {bottom_frame}"
    );

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let top_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("iterm"))
        })
    });
    let top: serde_json::Value = serde_json::from_str(&top_frame).unwrap();
    assert_eq!(
        top["scrollback_offset"].as_u64(),
        top["scrollback_max_offset"].as_u64(),
        "scroll-to-top frame should be anchored at the oldest scrollback rows: {top_frame}"
    );
    let placement = top["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["protocol"].as_str() == Some("iterm"))
        })
        .expect("expected iTerm2 scrollback placement");
    assert_eq!(placement["row"].as_u64(), Some(0));
    assert_eq!(placement["col"].as_u64(), Some(0));
    assert_eq!(placement["width_px"].as_u64(), Some(1));
    assert_eq!(placement["height_px"].as_u64(), Some(2));
    assert_eq!(placement["width_cells"].as_u64(), Some(1));
    assert_eq!(placement["height_cells"].as_u64(), Some(1));
    assert_eq!(placement["visible_height_px"].as_u64(), Some(2));
    assert_eq!(placement["source_y_offset_px"].as_u64(), Some(0));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_clear_scrollback_removes_iterm_scrollback_placements_from_frame_diff() {
    let profile = local_profile_with_scrollback(
        "iterm-scrollback-clear-frame-diff",
        "iTerm Scrollback Clear Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1b[1;1H\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{}\\x1b\\\\')\nsys.stdout.write('\\x1b[32;1H')\nfor i in range(80):\n    sys.stdout.write(f'line-{{i:02d}}\\n')\nsys.stdout.flush()\nPY",
                RED_PIXEL_PNG_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let _ = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("iterm"))
        })
    });

    let clear_response = session::clear_scrollback_session(session_id).unwrap();
    let clear_result: serde_json::Value = serde_json::from_str(&clear_response).unwrap();
    assert_eq!(clear_result["cleared"].as_bool(), Some(true));

    let cleared_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_offset"].as_u64() == Some(0)
            && parsed["scrollback_max_offset"].as_u64() == Some(0)
    });
    let cleared: serde_json::Value = serde_json::from_str(&cleared_frame).unwrap();
    assert!(
        cleared["graphics"].as_array().is_none_or(|graphics| {
            !graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("iterm"))
        }),
        "clear scrollback frame must not retain old iTerm2 scrollback placements: {cleared_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_scopes_iterm_graphics_to_alternate_screen() {
    let profile = local_profile(
        "iterm-alt-screen-frame-diff",
        "iTerm Alternate Screen Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\n\ndef out(value, delay=0.16):\n    sys.stdout.write(value)\n    sys.stdout.flush()\n    time.sleep(delay)\n\nout('\\x1b[2;1H\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{}\\x1b\\\\')\nout('\\x1b[?1049h')\nout('\\x1b[6;1H\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{}\\x1b\\\\')\nout('\\x1b[?1049lprimary restored\\n', 0.22)\nPY",
                RED_PIXEL_PNG_BASE64, RED_PIXEL_PNG_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let iterm_rows = |frame: &str| -> Vec<u64> {
        let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
        parsed["graphics"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|graphic| graphic["protocol"].as_str() == Some("iterm"))
            .filter_map(|graphic| graphic["row"].as_u64())
            .collect()
    };

    let primary = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics.iter().any(|graphic| {
                graphic["protocol"].as_str() == Some("iterm") && graphic["row"].as_u64() == Some(1)
            })
        })
    });
    let primary_rows = iterm_rows(&primary);
    assert!(
        primary_rows.contains(&1),
        "primary iTerm2 graphic should be visible before entering alternate screen: {primary}"
    );
    assert!(
        !primary_rows.contains(&5),
        "alternate iTerm2 graphic must not leak into the primary screen frame: {primary}"
    );

    let alternate = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics.iter().any(|graphic| {
                graphic["protocol"].as_str() == Some("iterm") && graphic["row"].as_u64() == Some(5)
            })
        })
    });
    let alternate_rows = iterm_rows(&alternate);
    assert!(
        alternate_rows.contains(&5),
        "alternate iTerm2 graphic should be visible while alternate screen is active: {alternate}"
    );
    assert!(
        !alternate_rows.contains(&1),
        "primary iTerm2 graphic must not leak into alternate screen frames: {alternate}"
    );

    let restored = wait_for_frame_where(session_id, |frame| {
        if !frame.contains("primary restored") {
            return false;
        }
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics.iter().any(|graphic| {
                graphic["protocol"].as_str() == Some("iterm") && graphic["row"].as_u64() == Some(1)
            })
        })
    });
    let restored_rows = iterm_rows(&restored);
    assert!(
        restored_rows.contains(&1),
        "primary iTerm2 graphic should be restored after leaving alternate screen: {restored}"
    );
    assert!(
        !restored_rows.contains(&5),
        "alternate iTerm2 graphic should be cleared after leaving alternate screen: {restored}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_sixel_placements_and_asset_bytes() {
    let profile = local_profile(
        "sixel-graphics",
        "Sixel Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1bPq#2~\\x1b\\\\')\nsys.stdout.flush()\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"sixel\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(graphics.len(), 1, "expected one Sixel placement: {frame}");
    let placement = &graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("sixel"));
    assert_eq!(placement["row"].as_u64(), Some(0));
    assert_eq!(placement["col"].as_u64(), Some(0));
    assert_eq!(placement["width_px"].as_u64(), Some(2));
    assert_eq!(placement["height_px"].as_u64(), Some(6));
    assert_eq!(placement["width_cells"].as_u64(), Some(2));
    assert_eq!(placement["height_cells"].as_u64(), Some(3));
    assert_eq!(placement["preserve_aspect_ratio"].as_bool(), Some(false));
    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected Sixel asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected Sixel asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 6);
    assert_eq!(meta.rgba_len, 24);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(&rgba[0..4], &[204, 51, 51, 255]);
    assert!(
        rgba.chunks_exact(4).all(|pixel| pixel[3] == 255),
        "Sixel '~' should emit six opaque pixels: {rgba:?}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_transparent_sixel_asset_alpha() {
    let profile = local_profile(
        "sixel-transparent-graphics",
        "Sixel Transparent Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1bP0;1q\"1;1;3;2@\\x1b\\\\')\nsys.stdout.flush()\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"sixel\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(
        graphics.len(),
        1,
        "expected one transparent Sixel placement: {frame}"
    );
    let placement = &graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("sixel"));
    assert_eq!(placement["width_px"].as_u64(), Some(3));
    assert_eq!(placement["height_px"].as_u64(), Some(2));
    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected Sixel asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected Sixel asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 3);
    assert_eq!(meta.height, 2);
    assert_eq!(meta.rgba_len, 3 * 2 * 4);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);

    let pixel_at = |x: usize, y: usize| {
        let start = (y * meta.width as usize + x) * 4;
        &rgba[start..start + 4]
    };
    assert_eq!(pixel_at(0, 0), &[0, 0, 0, 255]);
    assert_eq!(
        pixel_at(1, 0),
        &[0, 0, 0, 0],
        "transparent Sixel background should keep same-row unpainted asset pixels clear"
    );
    assert_eq!(
        pixel_at(2, 1),
        &[0, 0, 0, 0],
        "transparent Sixel background should keep lower-row unpainted asset pixels clear"
    );

    session::close_session(session_id).unwrap();
}

fn assert_wrapped_sixel_red_asset(
    session_id: u64,
    placement: &serde_json::Value,
    expected_row: u64,
    expected_col: u64,
    label: &str,
) {
    assert_eq!(placement["protocol"].as_str(), Some("sixel"));
    assert_eq!(placement["row"].as_u64(), Some(expected_row));
    assert_eq!(placement["col"].as_u64(), Some(expected_col));
    assert_eq!(placement["width_px"].as_u64(), Some(2));
    assert_eq!(placement["height_px"].as_u64(), Some(6));
    assert_eq!(placement["width_cells"].as_u64(), Some(2));
    assert_eq!(placement["height_cells"].as_u64(), Some(3));
    assert_eq!(placement["preserve_aspect_ratio"].as_bool(), Some(false));
    let asset_id = placement["asset_id"]
        .as_u64()
        .unwrap_or_else(|| panic!("expected {label} Sixel asset id"));
    let asset_version = placement["asset_version"]
        .as_u64()
        .unwrap_or_else(|| panic!("expected {label} Sixel asset version"));

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 6);
    assert_eq!(meta.rgba_len, 24);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(
        &rgba[0..4],
        &[255, 0, 0, 255],
        "{label} Sixel payload should decode the first pixel as red"
    );
    assert!(
        rgba.chunks_exact(4).all(|pixel| pixel[3] == 255),
        "{label} wrapped Sixel should retain opaque background pixels: {rgba:?}"
    );
}

#[test]
fn session_frame_diff_exports_screen_wrapped_sixel_graphics() {
    let profile = local_profile(
        "sixel-screen-wrapped-graphics",
        "Sixel Screen Wrapped Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
sys.stdout.write('\x1b[3;4H')
sys.stdout.write('\x1bP\x1bPq#1;2;100;0;0@\x1b\\\x1b\\')
sys.stdout.flush()
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"sixel\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(
        graphics.len(),
        1,
        "expected one screen-wrapped Sixel placement: {frame}"
    );
    assert_wrapped_sixel_red_asset(session_id, &graphics[0], 2, 3, "screen-wrapped");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_tmux_wrapped_sixel_graphics() {
    let profile = local_profile(
        "sixel-tmux-wrapped-graphics",
        "Sixel Tmux Wrapped Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys

inner = '\x1bPq#1;2;100;0;0@\x1b\\'
wrapped = '\x1bPtmux;' + inner.replace('\x1b', '\x1b\x1b') + '\x1b\\'
sys.stdout.write('\x1b[4;5H')
sys.stdout.write(wrapped)
sys.stdout.flush()
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"sixel\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(
        graphics.len(),
        1,
        "expected one tmux-wrapped Sixel placement: {frame}"
    );
    assert_wrapped_sixel_red_asset(session_id, &graphics[0], 3, 4, "tmux-wrapped");

    session::close_session(session_id).unwrap();
}

fn assert_wrapped_kitty_red_asset(
    session_id: u64,
    placement: &serde_json::Value,
    expected_asset_id: u64,
    expected_row: u64,
    expected_col: u64,
    label: &str,
) {
    assert_eq!(placement["protocol"].as_str(), Some("kitty"));
    assert_eq!(placement["asset_id"].as_u64(), Some(expected_asset_id));
    assert_eq!(placement["row"].as_u64(), Some(expected_row));
    assert_eq!(placement["col"].as_u64(), Some(expected_col));
    assert_eq!(placement["width_px"].as_u64(), Some(1));
    assert_eq!(placement["height_px"].as_u64(), Some(1));
    assert_eq!(placement["width_cells"].as_u64(), Some(1));
    assert_eq!(placement["height_cells"].as_u64(), Some(1));
    let asset_version = placement["asset_version"]
        .as_u64()
        .unwrap_or_else(|| panic!("expected {label} Kitty asset version"));

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            expected_asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 4);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            expected_asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(
        rgba,
        [255, 0, 0, 255],
        "{label} Kitty payload should decode to the expected red pixel"
    );
}

#[test]
fn session_frame_diff_exports_screen_wrapped_kitty_graphics() {
    let profile = local_profile(
        "kitty-screen-wrapped-graphics",
        "Kitty Screen Wrapped Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                r#"python3 - <<'PY'
import sys
sys.stdout.write('\x1b[5;6H')
sys.stdout.write('\x1bP\x1b_Ga=T,f=32,s=1,v=1,i=62031,q=1;{payload}\x1b\\\x1b\\')
sys.stdout.flush()
PY"#,
                payload = RED_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"asset_id\":62031"));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let placement = parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(62031))
        })
        .expect("expected screen-wrapped Kitty placement");
    assert_wrapped_kitty_red_asset(session_id, placement, 62031, 4, 5, "screen-wrapped");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_tmux_wrapped_kitty_graphics() {
    let profile = local_profile(
        "kitty-tmux-wrapped-graphics",
        "Kitty Tmux Wrapped Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                r#"python3 - <<'PY'
import sys

inner = '\x1b_Ga=T,f=32,s=1,v=1,i=62032,q=1;{payload}\x1b\\'
wrapped = '\x1bPtmux;' + inner.replace('\x1b', '\x1b\x1b') + '\x1b\\'
sys.stdout.write('\x1b[6;7H')
sys.stdout.write(wrapped)
sys.stdout.flush()
PY"#,
                payload = RED_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"asset_id\":62032"));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let placement = parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(62032))
        })
        .expect("expected tmux-wrapped Kitty placement");
    assert_wrapped_kitty_red_asset(session_id, placement, 62032, 5, 6, "tmux-wrapped");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_sixel_repeat_palette_pixels() {
    let profile = local_profile(
        "sixel-repeat-palette-graphics",
        "Sixel Repeat Palette Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1bPq#10;2;0;100;0!3~-#11;2;0;0;100!2~\\x1b\\\\')\nsys.stdout.flush()\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"sixel\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(graphics.len(), 1, "expected one Sixel placement: {frame}");
    let placement = &graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("sixel"));
    assert_eq!(
        placement["width_px"].as_u64(),
        Some(6),
        "default Sixel pixel aspect should double the repeated 3px asset width: {frame}"
    );
    assert_eq!(placement["height_px"].as_u64(), Some(12));
    assert_eq!(placement["width_cells"].as_u64(), Some(6));
    assert_eq!(placement["height_cells"].as_u64(), Some(6));
    assert_eq!(placement["preserve_aspect_ratio"].as_bool(), Some(false));
    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected Sixel asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected Sixel asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 3);
    assert_eq!(meta.height, 12);
    assert_eq!(meta.rgba_len, 3 * 12 * 4);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);

    let pixel_at = |x: usize, y: usize| {
        let start = (y * meta.width as usize + x) * 4;
        &rgba[start..start + 4]
    };
    for y in 0..6 {
        for x in 0..3 {
            assert_eq!(
                pixel_at(x, y),
                &[0, 255, 0, 255],
                "repeat-introduced first Sixel band should be green at ({x},{y})"
            );
        }
    }
    for y in 6..12 {
        for x in 0..2 {
            assert_eq!(
                pixel_at(x, y),
                &[0, 0, 255, 255],
                "second Sixel band should use the later blue palette color at ({x},{y})"
            );
        }
        assert_eq!(
            pixel_at(2, y),
            &[0, 0, 0, 255],
            "opaque Sixel background should fill the unpainted trailing column at y={y}"
        );
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_waits_for_incomplete_sixel_dcs_to_finish() {
    let profile = local_profile(
        "sixel-incomplete-dcs-frame-boundary",
        "Sixel Incomplete DCS Frame Boundary",
        "/usr/bin/env",
        vec![
            "python3".to_string(),
            "-c".to_string(),
            r#"
import sys, termios, time

try:
    attrs = termios.tcgetattr(sys.stdin.fileno())
    attrs[3] = attrs[3] & ~termios.ECHO
    termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, attrs)
except Exception:
    pass

def out(value, delay=0.08):
    sys.stdout.write(value)
    sys.stdout.flush()
    time.sleep(delay)

def wait():
    if sys.stdin.readline() == '':
        sys.exit(2)

out('\x1b[2;1H\x1bPq#2~\x1b\\')
wait()
out('\x1b[10;1H\x1bPq#10;2;0;100;0!3~', 0.02)
wait()
out('\x1b\\', 0.20)
"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"protocol\":\"sixel\"") && frame.contains("\"row\":1")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphics = first_parsed["graphics"]
        .as_array()
        .expect("expected first Sixel placement");
    assert!(
        first_graphics.iter().any(|graphic| {
            graphic["protocol"].as_str() == Some("sixel")
                && graphic["row"].as_u64() == Some(1)
                && graphic["col"].as_u64() == Some(0)
        }),
        "expected initial complete Sixel placement: {first}"
    );

    session::write_session(session_id, b"\n").unwrap();

    for _ in 0..8 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            let graphics = parsed["graphics"]
                .as_array()
                .expect("expected graphics placements field");
            assert!(
                !graphics.iter().any(|graphic| {
                    graphic["protocol"].as_str() == Some("sixel")
                        && graphic["row"].as_u64() == Some(9)
                }),
                "incomplete Sixel DCS must not export a placement before ST: {frame}"
            );
        }
        thread::sleep(Duration::from_millis(50));
    }

    session::write_session(session_id, b"\n").unwrap();

    let final_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"protocol\":\"sixel\"") && frame.contains("\"row\":9")
    });
    let final_parsed: serde_json::Value = serde_json::from_str(&final_frame).unwrap();
    let final_graphics = final_parsed["graphics"]
        .as_array()
        .expect("expected final graphics placements");
    let placement = final_graphics
        .iter()
        .find(|graphic| {
            graphic["protocol"].as_str() == Some("sixel") && graphic["row"].as_u64() == Some(9)
        })
        .unwrap_or_else(|| panic!("expected completed Sixel placement after ST: {final_frame}"));
    assert_eq!(placement["col"].as_u64(), Some(0));
    assert_eq!(placement["width_px"].as_u64(), Some(6));
    assert_eq!(placement["height_px"].as_u64(), Some(6));
    assert_eq!(placement["width_cells"].as_u64(), Some(6));
    assert_eq!(placement["height_cells"].as_u64(), Some(3));
    assert_eq!(placement["preserve_aspect_ratio"].as_bool(), Some(false));
    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected Sixel asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected Sixel asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 3);
    assert_eq!(meta.height, 6);
    assert_eq!(meta.rgba_len, 3 * 6 * 4);
    assert_eq!(meta.version, asset_version);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    for pixel in rgba.chunks_exact(4) {
        assert_eq!(
            pixel,
            &[0, 255, 0, 255],
            "completed Sixel DCS should decode the green repeat payload: {rgba:?}"
        );
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_clears_iterm_and_sixel_graphics_on_ed2() {
    let script = format!(
        "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[2;2H\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{}\\x1b\\\\')\nsys.stdout.write('\\x1b[6;2H\\x1bPq#2~\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nsys.stdout.write('\\x1b[2J\\x1b[Hafter clear\\n')\nsys.stdout.flush()\ntime.sleep(0.20)\nPY",
        RED_PIXEL_PNG_BASE64
    );
    let profile = local_profile(
        "iterm-sixel-ed2-clear-frame-diff",
        "iTerm2 Sixel ED2 Clear Frame Diff",
        "/bin/sh",
        vec!["-lc".to_string(), script],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let initial_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"protocol\":\"iterm\"") && frame.contains("\"protocol\":\"sixel\"")
    });
    let initial: serde_json::Value = serde_json::from_str(&initial_frame).unwrap();
    for protocol in ["iterm", "sixel"] {
        assert!(
            initial["graphics"].as_array().is_some_and(|graphics| {
                graphics
                    .iter()
                    .any(|graphic| graphic["protocol"].as_str() == Some(protocol))
            }),
            "expected {protocol} placement before ED2 clear: {initial_frame}"
        );
    }

    let cleared_frame = wait_for_frame_where(session_id, |frame| frame.contains("after clear"));
    let cleared: serde_json::Value = serde_json::from_str(&cleared_frame).unwrap();
    assert!(
        cleared["graphics"].as_array().is_none_or(|graphics| {
            !graphics.iter().any(|graphic| {
                matches!(graphic["protocol"].as_str(), Some("iterm") | Some("sixel"))
            })
        }),
        "ED2 clear frame must not retain old iTerm2 or Sixel placements: {cleared_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_applies_sixel_raster_pixel_aspect_ratio() {
    let profile = local_profile(
        "sixel-aspect-graphics",
        "Sixel Aspect Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1bPq\"2;1;2;6~~\\x1b\\\\')\nsys.stdout.flush()\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"protocol\":\"sixel\""));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in frame");
    assert_eq!(graphics.len(), 1, "expected one Sixel placement: {frame}");
    let placement = &graphics[0];
    assert_eq!(placement["protocol"].as_str(), Some("sixel"));
    assert_eq!(
        placement["width_px"].as_u64(),
        Some(4),
        "Sixel raster Pan/Pad=2/1 should double the display width without changing asset pixels: {frame}"
    );
    assert_eq!(placement["height_px"].as_u64(), Some(6));
    assert_eq!(placement["width_cells"].as_u64(), Some(4));
    assert_eq!(placement["height_cells"].as_u64(), Some(3));
    assert_eq!(placement["preserve_aspect_ratio"].as_bool(), Some(false));

    let asset_id = placement["asset_id"]
        .as_u64()
        .expect("expected Sixel asset id");
    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected Sixel asset version");
    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 2);
    assert_eq!(meta.height, 6);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_sixel_scrollback_placements_when_scrolled_back() {
    let profile = local_profile_with_scrollback(
        "sixel-scrollback-graphics",
        "Sixel Scrollback Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1bPq#2~\\x1b\\\\')\nfor i in range(80):\n    sys.stdout.write(f'line-{i:02d}\\n')\nsys.stdout.flush()\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let bottom_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });
    let bottom: serde_json::Value = serde_json::from_str(&bottom_frame).unwrap();
    assert!(
        bottom["graphics"].as_array().is_none_or(|graphics| {
            !graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("sixel"))
        }),
        "Sixel scrollback placement should not be emitted while the viewport is at the bottom: {bottom_frame}"
    );

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let top_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("sixel"))
        })
    });
    let top: serde_json::Value = serde_json::from_str(&top_frame).unwrap();
    assert_eq!(
        top["scrollback_offset"].as_u64(),
        top["scrollback_max_offset"].as_u64(),
        "scroll-to-top frame should be anchored at the oldest scrollback rows: {top_frame}"
    );
    let placement = top["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["protocol"].as_str() == Some("sixel"))
        })
        .expect("expected Sixel scrollback placement");
    assert_eq!(
        placement["row"].as_u64(),
        Some(2),
        "the 3-cell-tall Sixel should reappear at the retained scrollback row where its bottom edge entered history: {top_frame}"
    );
    assert_eq!(placement["col"].as_u64(), Some(0));
    assert_eq!(placement["width_px"].as_u64(), Some(2));
    assert_eq!(placement["height_px"].as_u64(), Some(6));
    assert_eq!(placement["visible_height_px"].as_u64(), Some(6));
    assert_eq!(placement["source_y_offset_px"].as_u64(), Some(0));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_clear_scrollback_removes_sixel_scrollback_placements_from_frame_diff() {
    let profile = local_profile_with_scrollback(
        "sixel-scrollback-clear-frame-diff",
        "Sixel Scrollback Clear Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1bPq#2~\\x1b\\\\')\nfor i in range(80):\n    sys.stdout.write(f'line-{i:02d}\\n')\nsys.stdout.flush()\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let _ = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("sixel"))
        })
    });

    let clear_response = session::clear_scrollback_session(session_id).unwrap();
    let clear_result: serde_json::Value = serde_json::from_str(&clear_response).unwrap();
    assert_eq!(clear_result["cleared"].as_bool(), Some(true));

    let cleared_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_offset"].as_u64() == Some(0)
            && parsed["scrollback_max_offset"].as_u64() == Some(0)
    });
    let cleared: serde_json::Value = serde_json::from_str(&cleared_frame).unwrap();
    assert!(
        cleared["graphics"].as_array().is_none_or(|graphics| {
            !graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("sixel"))
        }),
        "clear scrollback frame must not retain old Sixel scrollback placements: {cleared_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_csi3j_clears_iterm_and_sixel_scrollback_placements() {
    let script = format!(
        "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[1;1H\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{}\\x1b\\\\')\nsys.stdout.write('\\x1b[5;1H\\x1bPq#2~\\x1b\\\\')\nsys.stdout.write('\\x1b[32;1H')\nfor i in range(80):\n    sys.stdout.write(f'line-{{i:02d}}\\n')\nsys.stdout.flush()\ntime.sleep(0.90)\nsys.stdout.write('\\x1b[3J\\x1b[Hafter 3j\\n')\nsys.stdout.flush()\ntime.sleep(0.20)\nPY",
        RED_PIXEL_PNG_BASE64
    );
    let profile = local_profile_with_scrollback(
        "iterm-sixel-csi3j-scrollback-clear-frame-diff",
        "iTerm2 Sixel CSI 3J Scrollback Clear Frame Diff",
        "/bin/sh",
        vec!["-lc".to_string(), script],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let top_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            let has_iterm = graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("iterm"));
            let has_sixel = graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("sixel"));
            has_iterm && has_sixel
        })
    });
    let top: serde_json::Value = serde_json::from_str(&top_frame).unwrap();
    assert_eq!(
        top["scrollback_offset"].as_u64(),
        top["scrollback_max_offset"].as_u64(),
        "scroll-to-top frame should expose retained iTerm2 and Sixel scrollback placements before CSI 3J: {top_frame}"
    );

    let cleared_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains("after 3j"))
            && parsed["scrollback_max_offset"].as_u64() == Some(0)
    });
    let cleared: serde_json::Value = serde_json::from_str(&cleared_frame).unwrap();
    assert_eq!(
        cleared["scrollback_offset"].as_u64(),
        Some(0),
        "CSI 3J should clamp an existing scrollback viewport back to the live screen: {cleared_frame}"
    );
    assert!(
        cleared["graphics"].as_array().is_none_or(|graphics| {
            !graphics.iter().any(|graphic| {
                matches!(graphic["protocol"].as_str(), Some("iterm") | Some("sixel"))
            })
        }),
        "CSI 3J clear frame must not retain old iTerm2 or Sixel scrollback placements: {cleared_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_scopes_sixel_graphics_to_alternate_screen() {
    let profile = local_profile(
        "sixel-alt-screen-frame-diff",
        "Sixel Alternate Screen Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys, time\n\ndef out(value, delay=0.16):\n    sys.stdout.write(value)\n    sys.stdout.flush()\n    time.sleep(delay)\n\nout('\\x1b[2;1H\\x1bPq#2~\\x1b\\\\')\nout('\\x1b[?1049h')\nout('\\x1b[6;1H\\x1bPq#2~\\x1b\\\\')\nout('\\x1b[?1049lprimary restored\\n', 0.22)\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let sixel_rows = |frame: &str| -> Vec<u64> {
        let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
        parsed["graphics"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|graphic| graphic["protocol"].as_str() == Some("sixel"))
            .filter_map(|graphic| graphic["row"].as_u64())
            .collect()
    };

    let primary = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics.iter().any(|graphic| {
                graphic["protocol"].as_str() == Some("sixel") && graphic["row"].as_u64() == Some(1)
            })
        })
    });
    let primary_rows = sixel_rows(&primary);
    assert!(
        primary_rows.contains(&1),
        "primary Sixel graphic should be visible before entering alternate screen: {primary}"
    );
    assert!(
        !primary_rows.contains(&5),
        "alternate Sixel graphic must not leak into the primary screen frame: {primary}"
    );

    let alternate = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics.iter().any(|graphic| {
                graphic["protocol"].as_str() == Some("sixel") && graphic["row"].as_u64() == Some(5)
            })
        })
    });
    let alternate_rows = sixel_rows(&alternate);
    assert!(
        alternate_rows.contains(&5),
        "alternate Sixel graphic should be visible while alternate screen is active: {alternate}"
    );
    assert!(
        !alternate_rows.contains(&1),
        "primary Sixel graphic must not leak into alternate screen frames: {alternate}"
    );

    let restored = wait_for_frame_where(session_id, |frame| {
        if !frame.contains("primary restored") {
            return false;
        }
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics.iter().any(|graphic| {
                graphic["protocol"].as_str() == Some("sixel") && graphic["row"].as_u64() == Some(1)
            })
        })
    });
    let restored_rows = sixel_rows(&restored);
    assert!(
        restored_rows.contains(&1),
        "primary Sixel graphic should be restored after leaving alternate screen: {restored}"
    );
    assert!(
        !restored_rows.contains(&5),
        "alternate Sixel graphic should be cleared after leaving alternate screen: {restored}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_kitty_scrollback_placements_when_scrolled_back() {
    let profile = local_profile_with_scrollback(
        "kitty-scrollback-graphics",
        "Kitty Scrollback Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1b[1;1H\\x1b_Ga=T,f=32,s=1,v=1,i=812,p=4,c=1,r=1,C=1,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b[32;1H')\nfor i in range(80):\n    sys.stdout.write(f'line-{{i:02d}}\\n')\nsys.stdout.flush()\nPY",
                RED_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let bottom_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });
    let bottom: serde_json::Value = serde_json::from_str(&bottom_frame).unwrap();
    assert!(
        bottom["graphics"].as_array().is_none_or(|graphics| {
            !graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(812))
        }),
        "Kitty scrollback placement should not be emitted while the viewport is at the bottom: {bottom_frame}"
    );

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let top_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(812))
        })
    });
    let top: serde_json::Value = serde_json::from_str(&top_frame).unwrap();
    assert_eq!(
        top["scrollback_offset"].as_u64(),
        top["scrollback_max_offset"].as_u64(),
        "scroll-to-top frame should be anchored at the oldest scrollback rows: {top_frame}"
    );
    let placement = top["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(812))
        })
        .expect("expected Kitty scrollback placement");
    assert_eq!(placement["protocol"].as_str(), Some("kitty"));
    assert_eq!(placement["row"].as_u64(), Some(0));
    assert_eq!(placement["col"].as_u64(), Some(0));
    assert_eq!(placement["width_px"].as_u64(), Some(1));
    assert_eq!(placement["height_px"].as_u64(), Some(2));
    assert_eq!(placement["width_cells"].as_u64(), Some(1));
    assert_eq!(placement["height_cells"].as_u64(), Some(1));
    assert_eq!(placement["visible_height_px"].as_u64(), Some(2));
    assert_eq!(placement["source_y_offset_px"].as_u64(), Some(0));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_updates_kitty_animation_scrollback_asset_after_current_frame_change() {
    let profile = local_profile_with_scrollback(
        "kitty-animation-scrollback-frame-diff",
        "Kitty Animation Scrollback Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[1;1H\\x1b_Ga=f,f=32,s=1,v=1,i=61004,r=1,z=1,q=1;{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.90)\nsys.stdout.write('\\x1b[32;1H')\nfor i in range(80):\n    sys.stdout.write('line-%02d\\n' % i)\nsys.stdout.flush()\ntime.sleep(0.45)\nsys.stdout.write('\\x1b_Ga=f,f=32,s=1,v=1,i=61004,r=2,z=1,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b_Ga=a,i=61004,c=2,q=1;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.30)\nPY",
                RED_RGBA_BASE64, GREEN_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(61004))
        })
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphic = first_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61004))
        })
        .expect("expected first Kitty animation placement");
    let first_render_id = first_graphic["render_id"].as_u64();
    let first_placement_id = first_graphic["placement_id"].as_u64();
    let first_version = first_graphic["asset_version"]
        .as_u64()
        .expect("expected first Kitty animation asset version");

    let mut first_meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let first_meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            61004,
            first_version,
            &mut first_meta,
        )
    };
    assert_eq!(first_meta_status, 0);
    assert_eq!(first_meta.rgba_len, 4);
    let mut first_rgba = vec![0_u8; first_meta.rgba_len];
    let first_copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            61004,
            first_version,
            first_rgba.as_mut_ptr(),
            first_rgba.len(),
        )
    };
    assert_eq!(first_copy_status, first_rgba.len() as isize);
    assert_eq!(first_rgba, [255, 0, 0, 255]);

    let bottom_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });
    let bottom: serde_json::Value = serde_json::from_str(&bottom_frame).unwrap();
    assert!(
        bottom["graphics"].as_array().is_none_or(|graphics| {
            !graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(61004))
        }),
        "Kitty animation scrollback placement should not be emitted while the viewport is at the bottom: {bottom_frame}"
    );

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let updated = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_offset"].as_u64() == parsed["scrollback_max_offset"].as_u64()
            && parsed["graphics"]
                .as_array()
                .and_then(|graphics| {
                    graphics
                        .iter()
                        .find(|graphic| graphic["asset_id"].as_u64() == Some(61004))
                })
                .and_then(|graphic| graphic["asset_version"].as_u64())
                .is_some_and(|version| version != first_version)
    });
    let updated_parsed: serde_json::Value = serde_json::from_str(&updated).unwrap();
    let updated_graphic = updated_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61004))
        })
        .expect("expected updated Kitty animation scrollback placement");
    assert_eq!(updated_graphic["render_id"].as_u64(), first_render_id);
    assert_eq!(updated_graphic["placement_id"].as_u64(), first_placement_id);
    assert_eq!(updated_graphic["width_px"].as_u64(), Some(1));
    assert_eq!(updated_graphic["height_px"].as_u64(), Some(1));
    let updated_version = updated_graphic["asset_version"]
        .as_u64()
        .expect("expected current-frame control to update the scrollback asset version");

    let mut updated_meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let updated_meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            61004,
            updated_version,
            &mut updated_meta,
        )
    };
    assert_eq!(updated_meta_status, 0);
    assert_eq!(updated_meta.rgba_len, 4);
    let mut updated_rgba = vec![0_u8; updated_meta.rgba_len];
    let updated_copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            61004,
            updated_version,
            updated_rgba.as_mut_ptr(),
            updated_rgba.len(),
        )
    };
    assert_eq!(updated_copy_status, updated_rgba.len() as isize);
    assert_eq!(updated_rgba, [0, 255, 0, 255]);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_clear_scrollback_removes_kitty_scrollback_placements_from_frame_diff() {
    let profile = local_profile_with_scrollback(
        "kitty-scrollback-clear-frame-diff",
        "Kitty Scrollback Clear Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\nsys.stdout.write('\\x1b[1;1H\\x1b_Ga=T,f=32,s=1,v=1,i=61003,p=4,c=1,r=1,C=1,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b[32;1H')\nfor i in range(80):\n    sys.stdout.write(f'line-{{i:02d}}\\n')\nsys.stdout.flush()\nPY",
                RED_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let _ = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(61003))
        })
    });

    let clear_response = session::clear_scrollback_session(session_id).unwrap();
    let clear_result: serde_json::Value = serde_json::from_str(&clear_response).unwrap();
    assert_eq!(clear_result["cleared"].as_bool(), Some(true));

    let cleared_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_offset"].as_u64() == Some(0)
            && parsed["scrollback_max_offset"].as_u64() == Some(0)
    });
    let cleared: serde_json::Value = serde_json::from_str(&cleared_frame).unwrap();
    assert!(
        cleared["graphics"].as_array().is_none_or(|graphics| {
            !graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(61003))
        }),
        "clear scrollback frame must not retain old Kitty scrollback placements: {cleared_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_clear_scrollback_preserves_active_graphics_placements() {
    let script = format!(
        "python3 - <<'PY'\nimport sys\nfor i in range(80):\n    sys.stdout.write(f'line-{{i:02d}}\\n')\nsys.stdout.write('\\x1b[2;2H\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{}\\x1b\\\\')\nsys.stdout.write('\\x1b[5;2H\\x1bPq#2~\\x1b\\\\')\nsys.stdout.write('\\x1b[9;2H\\x1b_Ga=T,f=32,s=1,v=1,i=62020,p=1,c=1,r=1,C=1,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b[20;1Hactive graphics ready\\n')\nsys.stdout.flush()\nPY",
        RED_PIXEL_PNG_BASE64, RED_RGBA_BASE64
    );
    let profile = local_profile_with_scrollback(
        "active-graphics-clear-scrollback-frame-diff",
        "Active Graphics Clear Scrollback Frame Diff",
        "/bin/sh",
        vec!["-lc".to_string(), script],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let initial_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("active graphics ready"))
    });
    let initial: serde_json::Value = serde_json::from_str(&initial_frame).unwrap();
    let initial_graphics = initial["graphics"]
        .as_array()
        .expect("initial frame should include active graphics placements");
    assert!(
        initial_graphics
            .iter()
            .any(|graphic| graphic["protocol"].as_str() == Some("iterm")),
        "expected initial active iTerm2 placement: {initial_frame}"
    );
    assert!(
        initial_graphics
            .iter()
            .any(|graphic| graphic["protocol"].as_str() == Some("sixel")),
        "expected initial active Sixel placement: {initial_frame}"
    );
    assert!(
        initial_graphics
            .iter()
            .any(|graphic| graphic["asset_id"].as_u64() == Some(62020)),
        "expected initial active Kitty placement: {initial_frame}"
    );

    let clear_response = session::clear_scrollback_session(session_id).unwrap();
    let clear_result: serde_json::Value = serde_json::from_str(&clear_response).unwrap();
    assert_eq!(clear_result["cleared"].as_bool(), Some(true));

    let cleared_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_offset"].as_u64() == Some(0)
            && parsed["scrollback_max_offset"].as_u64() == Some(0)
    });
    let cleared: serde_json::Value = serde_json::from_str(&cleared_frame).unwrap();
    let graphics = cleared["graphics"]
        .as_array()
        .expect("clear scrollback frame should keep active graphics placements");
    assert!(
        graphics
            .iter()
            .any(|graphic| graphic["protocol"].as_str() == Some("iterm")),
        "clear scrollback must preserve active iTerm2 placements: {cleared_frame}"
    );
    assert!(
        graphics
            .iter()
            .any(|graphic| graphic["protocol"].as_str() == Some("sixel")),
        "clear scrollback must preserve active Sixel placements: {cleared_frame}"
    );
    assert!(
        graphics
            .iter()
            .any(|graphic| graphic["asset_id"].as_u64() == Some(62020)),
        "clear scrollback must preserve active Kitty placements: {cleared_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_csi3j_clears_kitty_scrollback_placements() {
    let profile = local_profile_with_scrollback(
        "kitty-csi3j-scrollback-clear-frame-diff",
        "Kitty CSI 3J Scrollback Clear Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[1;1H\\x1b_Ga=T,f=32,s=1,v=1,i=61005,p=4,c=1,r=1,C=1,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b[32;1H')\nfor i in range(80):\n    sys.stdout.write(f'line-{{i:02d}}\\n')\nsys.stdout.flush()\ntime.sleep(0.90)\nsys.stdout.write('\\x1b[3J\\x1b[Hafter kitty 3j\\n')\nsys.stdout.flush()\ntime.sleep(0.20)\nPY",
                RED_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let top_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(61005))
        })
    });
    let top: serde_json::Value = serde_json::from_str(&top_frame).unwrap();
    assert_eq!(
        top["scrollback_offset"].as_u64(),
        top["scrollback_max_offset"].as_u64(),
        "scroll-to-top frame should expose retained Kitty scrollback placement before CSI 3J: {top_frame}"
    );

    let cleared_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains("after kitty 3j"))
            && parsed["scrollback_max_offset"].as_u64() == Some(0)
    });
    let cleared: serde_json::Value = serde_json::from_str(&cleared_frame).unwrap();
    assert_eq!(
        cleared["scrollback_offset"].as_u64(),
        Some(0),
        "CSI 3J should clamp a Kitty scrollback viewport back to the live screen: {cleared_frame}"
    );
    assert!(
        cleared["graphics"].as_array().is_none_or(|graphics| {
            !graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(61005))
        }),
        "CSI 3J clear frame must not retain old Kitty scrollback placements: {cleared_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_scopes_kitty_graphics_to_alternate_screen() {
    let script = format!(
        r#"
import sys, time

def out(value, delay=0.16):
    sys.stdout.write(value)
    sys.stdout.flush()
    time.sleep(delay)

out('\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=750,C=1,q=1;{red}\x1b\\')
out('\x1b[?1049h')
out('\x1b[4;1H\x1b_Ga=T,f=32,s=1,v=1,i=751,C=1,q=1;{green}\x1b\\')
out('\x1b[?1049lprimary restored\n', 0.22)
"#,
        red = RED_RGBA_BASE64,
        green = GREEN_RGBA_BASE64,
    );
    let profile = local_profile(
        "kitty-alt-screen-frame-diff",
        "Kitty Alternate Screen Frame Diff",
        "/usr/bin/env",
        vec!["python3".to_string(), "-c".to_string(), script],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":750")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphics = first_parsed["graphics"]
        .as_array()
        .expect("expected primary graphics placement");
    assert!(
        first_graphics
            .iter()
            .any(|graphic| graphic["asset_id"].as_u64() == Some(750)),
        "primary Kitty graphic should be visible before entering alternate screen: {first}"
    );
    assert!(
        !first_graphics
            .iter()
            .any(|graphic| graphic["asset_id"].as_u64() == Some(751)),
        "alternate Kitty graphic must not leak into the primary screen frame: {first}"
    );

    let alternate = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":751")
    });
    let alternate_parsed: serde_json::Value = serde_json::from_str(&alternate).unwrap();
    let alternate_graphics = alternate_parsed["graphics"]
        .as_array()
        .expect("expected alternate graphics placement");
    assert!(
        alternate_graphics
            .iter()
            .any(|graphic| graphic["asset_id"].as_u64() == Some(751)),
        "alternate Kitty graphic should be visible while alternate screen is active: {alternate}"
    );
    assert!(
        !alternate_graphics
            .iter()
            .any(|graphic| graphic["asset_id"].as_u64() == Some(750)),
        "primary Kitty graphic must not leak into alternate screen frames: {alternate}"
    );

    let restored = wait_for_frame_where(session_id, |frame| {
        frame.contains("primary restored")
            && frame.contains("\"graphics\":[{")
            && frame.contains("\"asset_id\":750")
    });
    let restored_parsed: serde_json::Value = serde_json::from_str(&restored).unwrap();
    let restored_graphics = restored_parsed["graphics"]
        .as_array()
        .expect("expected restored primary graphics placement");
    assert!(
        restored_graphics
            .iter()
            .any(|graphic| graphic["asset_id"].as_u64() == Some(750)),
        "primary Kitty graphic should be restored after leaving alternate screen: {restored}"
    );
    assert!(
        !restored_graphics
            .iter()
            .any(|graphic| graphic["asset_id"].as_u64() == Some(751)),
        "alternate Kitty graphic should be cleared after leaving alternate screen: {restored}"
    );

    session::close_session(session_id).unwrap();
}

#[cfg(unix)]
#[test]
fn session_frame_diff_exports_kitty_shared_memory_placement_and_asset_bytes() {
    let mut shared_data = b"skip".to_vec();
    shared_data.extend_from_slice(red_pixel_png_bytes());
    let Some((shared_memory_name, shared_memory_payload)) =
        create_kitty_shared_memory_payload(&shared_data)
    else {
        return;
    };
    let profile = local_profile(
        "kitty-shared-memory-frame-diff",
        "Kitty Shared Memory Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.buffer.write(b\"\\x1b_Ga=T,t=s,f=100,i=815,O=4,S={},q=1;{}\\x1b\\\\\")\nsys.stdout.flush()\ntime.sleep(0.2)\nPY",
                red_pixel_png_bytes().len(),
                shared_memory_payload,
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| frame.contains("\"asset_id\":815"));
    let still_exists = kitty_shared_memory_exists(&shared_memory_name);
    if still_exists {
        unlink_kitty_shared_memory(&shared_memory_name);
    }
    assert!(
        !still_exists,
        "session-level Kitty shared memory transfer must unlink the object after reading"
    );

    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let placement = parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(815))
        })
        .expect("expected Kitty shared memory placement");
    assert_eq!(placement["protocol"].as_str(), Some("kitty"));
    assert_eq!(placement["row"].as_u64(), Some(0));
    assert_eq!(placement["col"].as_u64(), Some(0));
    assert_eq!(placement["width_px"].as_u64(), Some(1));
    assert_eq!(placement["height_px"].as_u64(), Some(1));
    assert_eq!(placement["width_cells"].as_u64(), Some(1));
    assert_eq!(placement["height_cells"].as_u64(), Some(1));

    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected graphic asset version");
    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(session_id, 815, asset_version, &mut meta)
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 4);

    let mut rgba = vec![0u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            815,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(rgba, vec![255, 0, 0, 255]);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_kitty_virtual_placeholder_placements() {
    let profile = local_profile(
        "kitty-virtual-placeholder-graphics",
        "Kitty Virtual Placeholder Graphics",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys\nplaceholder = chr(0x10eeee) + '\\u0305\\u0305'\nsys.stdout.write('\\x1b[1;1H')\nsys.stdout.write('\\x1b_Ga=T,U=1,f=32,s=1,v=1,i=812,p=4,c=1,r=1,C=1,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b[3;5H')\nsys.stdout.write('\\x1b[38;2;0;3;44m\\x1b[58;2;0;0;4m' + placeholder + '\\x1b[0m')\nsys.stdout.flush()\nPY",
                RED_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(812))
        })
    });
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let placement = parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(812))
        })
        .expect("expected Kitty virtual placeholder placement");
    assert_eq!(placement["protocol"].as_str(), Some("kitty"));
    assert_eq!(placement["row"].as_u64(), Some(2));
    assert_eq!(placement["col"].as_u64(), Some(4));
    assert_eq!(placement["width_cells"].as_u64(), Some(1));
    assert_eq!(placement["height_cells"].as_u64(), Some(1));
    assert_eq!(placement["source_x_offset_px"].as_u64(), Some(0));
    assert_eq!(placement["source_y_offset_px"].as_u64(), Some(0));

    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected graphic asset version");
    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(session_id, 812, asset_version, &mut meta)
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 4);

    let mut rgba = vec![0u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            812,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(rgba, vec![255, 0, 0, 255]);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exports_kitty_source_rect_offsets_and_z_index() {
    let rgba = [
        255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255, 255, 0, 255, 255, 0, 255,
        255, 255, 255, 255, 255, 255, 32, 64, 96, 255, 96, 64, 32, 255, 16, 32, 48, 255, 48, 32,
        16, 255, 192, 128, 64, 255, 64, 128, 192, 255, 8, 16, 24, 255, 24, 16, 8, 255, 128, 128,
        128, 255,
    ];
    let rgba_payload = base64_standard_no_pad_encode(&rgba);
    let profile = local_profile(
        "kitty-source-rect-placement-frame-diff",
        "Kitty Source Rect Placement Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[4;6H')\nsys.stdout.write('\\x1b_Ga=T,f=32,s=4,v=4,i=813,p=9,c=4,r=3,x=1,y=1,w=2,h=2,X=1,Y=2,z=-7,C=1,q=1;{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.2)\nPY",
                rgba_payload,
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"asset_id\":813") && frame.contains("\"z_index\":-7")
    });
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let placement = parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(813))
        })
        .expect("expected Kitty source-rect placement");
    assert_eq!(placement["protocol"].as_str(), Some("kitty"));
    assert_eq!(placement["row"].as_u64(), Some(3));
    assert_eq!(placement["col"].as_u64(), Some(5));
    assert_eq!(placement["width_px"].as_u64(), Some(8));
    assert_eq!(placement["height_px"].as_u64(), Some(12));
    assert_eq!(placement["width_cells"].as_u64(), Some(5));
    assert_eq!(placement["height_cells"].as_u64(), Some(4));
    assert_eq!(placement["source_x_offset_px"].as_u64(), Some(2));
    assert_eq!(placement["source_y_offset_px"].as_u64(), Some(3));
    assert_eq!(placement["visible_width_px"].as_u64(), Some(4));
    assert_eq!(placement["visible_height_px"].as_u64(), Some(6));
    assert_eq!(placement["x_offset_px"].as_u64(), Some(1));
    assert_eq!(placement["y_offset_px"].as_u64(), Some(2));
    assert_eq!(placement["z_index"].as_i64(), Some(-7));
    assert_eq!(placement["preserve_aspect_ratio"].as_bool(), Some(true));

    let asset_version = placement["asset_version"]
        .as_u64()
        .expect("expected graphic asset version");
    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(session_id, 813, asset_version, &mut meta)
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 4);
    assert_eq!(meta.height, 4);
    assert_eq!(meta.rgba_len, rgba.len());

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_ticks_kitty_animation_without_new_output() {
    let profile = local_profile(
        "kitty-animation-frame-diff",
        "Kitty Animation Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b_Ga=f,f=32,s=1,v=1,i=61000,r=1,z=1,q=1;{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nsys.stdout.write('\\x1b_Ga=f,f=32,s=1,v=1,i=61000,r=2,z=1,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b_Ga=a,i=61000,s=3,q=1;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nPY",
                RED_RGBA_BASE64, GREEN_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| frame.contains("\"asset_id\":61000"));
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphic = first_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61000))
        })
        .expect("expected first animated Kitty placement");
    let first_version = first_graphic["asset_version"]
        .as_u64()
        .expect("expected first asset version");

    let updated = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"]
            .as_array()
            .and_then(|graphics| {
                graphics
                    .iter()
                    .find(|graphic| graphic["asset_id"].as_u64() == Some(61000))
            })
            .and_then(|graphic| graphic["asset_version"].as_u64())
            .is_some_and(|version| version != first_version)
    });
    let updated_parsed: serde_json::Value = serde_json::from_str(&updated).unwrap();
    let updated_graphic = updated_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61000))
        })
        .expect("expected updated animated Kitty placement");
    let updated_version = updated_graphic["asset_version"]
        .as_u64()
        .expect("expected updated asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            61000,
            updated_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.rgba_len, 4);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            61000,
            updated_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(rgba, [0, 255, 0, 255]);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_ticks_iterm_gif_animation_without_new_output() {
    let profile = local_profile(
        "iterm-gif-animation-frame-diff",
        "iTerm GIF Animation Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b]1337;File=inline=1;doNotMoveCursor=1:{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nPY",
                RED_GREEN_1X1_GIF_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["protocol"] == "iterm")
        })
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphic = first_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["protocol"] == "iterm")
        })
        .expect("expected first animated iTerm GIF placement");
    let asset_id = first_graphic["asset_id"]
        .as_u64()
        .expect("expected animated iTerm GIF asset id");
    let first_version = first_graphic["asset_version"]
        .as_u64()
        .expect("expected first animated iTerm GIF asset version");
    let mut first_meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let first_meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            first_version,
            &mut first_meta,
        )
    };
    assert_eq!(first_meta_status, 0);
    assert_eq!(first_meta.rgba_len, 4);
    let mut first_rgba = vec![0_u8; first_meta.rgba_len];
    let first_copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            first_version,
            first_rgba.as_mut_ptr(),
            first_rgba.len(),
        )
    };
    assert_eq!(first_copy_status, first_rgba.len() as isize);

    let updated = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"]
            .as_array()
            .and_then(|graphics| {
                graphics
                    .iter()
                    .find(|graphic| graphic["asset_id"].as_u64() == Some(asset_id))
            })
            .and_then(|graphic| graphic["asset_version"].as_u64())
            .is_some_and(|version| version != first_version)
    });
    let updated_parsed: serde_json::Value = serde_json::from_str(&updated).unwrap();
    let updated_graphic = updated_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(asset_id))
        })
        .expect("expected updated animated iTerm GIF placement");
    let updated_version = updated_graphic["asset_version"]
        .as_u64()
        .expect("expected updated animated iTerm GIF asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            updated_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.rgba_len, 4);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            updated_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_ne!(rgba, first_rgba);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_updates_iterm_gif_scrollback_asset_after_animation_tick() {
    let profile = local_profile_with_scrollback(
        "iterm-gif-animation-scrollback-frame-diff",
        "iTerm GIF Animation Scrollback Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[1;1H\\x1b]1337;File=inline=1;doNotMoveCursor=1:{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.45)\nsys.stdout.write('\\x1b[32;1H')\nfor i in range(80):\n    sys.stdout.write(f'line-{{i:02d}}\\n')\nsys.stdout.flush()\ntime.sleep(0.45)\nPY",
                RED_GREEN_1X1_GIF_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
        128,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("iterm"))
        })
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphic = first_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["protocol"].as_str() == Some("iterm"))
        })
        .expect("expected first animated iTerm GIF placement");
    let asset_id = first_graphic["asset_id"]
        .as_u64()
        .expect("expected animated iTerm GIF asset id");
    let first_render_id = first_graphic["render_id"].as_u64();
    let first_placement_id = first_graphic["placement_id"].as_u64();
    let first_version = first_graphic["asset_version"]
        .as_u64()
        .expect("expected first animated iTerm GIF asset version");
    let mut first_meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let first_meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            first_version,
            &mut first_meta,
        )
    };
    assert_eq!(first_meta_status, 0);
    assert_eq!(first_meta.rgba_len, 4);
    let mut first_rgba = vec![0_u8; first_meta.rgba_len];
    let first_copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            first_version,
            first_rgba.as_mut_ptr(),
            first_rgba.len(),
        )
    };
    assert_eq!(first_copy_status, first_rgba.len() as isize);

    let bottom_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("line-79"))
    });
    let bottom: serde_json::Value = serde_json::from_str(&bottom_frame).unwrap();
    assert!(
        bottom["graphics"].as_array().is_none_or(|graphics| {
            !graphics
                .iter()
                .any(|graphic| graphic["asset_id"].as_u64() == Some(asset_id))
        }),
        "iTerm GIF scrollback placement should not be emitted while viewport is at the bottom: {bottom_frame}"
    );

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let updated = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["scrollback_offset"].as_u64() == parsed["scrollback_max_offset"].as_u64()
            && parsed["graphics"]
                .as_array()
                .and_then(|graphics| {
                    graphics
                        .iter()
                        .find(|graphic| graphic["asset_id"].as_u64() == Some(asset_id))
                })
                .and_then(|graphic| graphic["asset_version"].as_u64())
                .is_some_and(|version| version != first_version)
    });
    let updated_parsed: serde_json::Value = serde_json::from_str(&updated).unwrap();
    let updated_graphic = updated_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(asset_id))
        })
        .expect("expected updated animated iTerm GIF scrollback placement");
    assert_eq!(updated_graphic["protocol"].as_str(), Some("iterm"));
    assert_eq!(updated_graphic["render_id"].as_u64(), first_render_id);
    assert_eq!(updated_graphic["placement_id"].as_u64(), first_placement_id);
    assert_eq!(updated_graphic["row"].as_u64(), Some(0));
    assert_eq!(updated_graphic["col"].as_u64(), Some(0));
    let updated_version = updated_graphic["asset_version"]
        .as_u64()
        .expect("expected updated animated iTerm GIF asset version");

    let mut updated_meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let updated_meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            asset_id,
            updated_version,
            &mut updated_meta,
        )
    };
    assert_eq!(updated_meta_status, 0);
    assert_eq!(updated_meta.rgba_len, 4);

    let mut updated_rgba = vec![0_u8; updated_meta.rgba_len];
    let updated_copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            asset_id,
            updated_version,
            updated_rgba.as_mut_ptr(),
            updated_rgba.len(),
        )
    };
    assert_eq!(updated_copy_status, updated_rgba.len() as isize);
    assert_ne!(
        updated_rgba, first_rgba,
        "iTerm GIF scrollback asset should publish the current animation frame"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_applies_kitty_animation_current_frame_control() {
    const GREEN_2X1_RGBA_BASE64: &str = "AP8A/wD/AP8=";

    let profile = local_profile(
        "kitty-animation-current-frame-diff",
        "Kitty Animation Current Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b_Ga=f,f=32,s=1,v=1,i=61001,r=1,z=1000,q=1;{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nsys.stdout.write('\\x1b_Ga=f,f=32,s=2,v=1,i=61001,r=2,z=1000,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b_Ga=a,i=61001,c=2,q=1;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nPY",
                RED_RGBA_BASE64, GREEN_2X1_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| frame.contains("\"asset_id\":61001"));
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphic = first_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61001))
        })
        .expect("expected first Kitty animation placement");
    let first_render_id = first_graphic["render_id"].as_u64();
    let first_placement_id = first_graphic["placement_id"].as_u64();
    assert_eq!(first_graphic["width_px"].as_u64(), Some(1));
    assert_eq!(first_graphic["height_px"].as_u64(), Some(1));
    let first_version = first_graphic["asset_version"]
        .as_u64()
        .expect("expected first Kitty animation asset version");

    let updated = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"]
            .as_array()
            .and_then(|graphics| {
                graphics
                    .iter()
                    .find(|graphic| graphic["asset_id"].as_u64() == Some(61001))
            })
            .and_then(|graphic| graphic["asset_version"].as_u64())
            .is_some_and(|version| version != first_version)
    });
    let updated_parsed: serde_json::Value = serde_json::from_str(&updated).unwrap();
    let updated_graphic = updated_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61001))
        })
        .expect("expected updated Kitty animation placement");
    assert_eq!(updated_graphic["render_id"].as_u64(), first_render_id);
    assert_eq!(updated_graphic["placement_id"].as_u64(), first_placement_id);
    assert_eq!(updated_graphic["width_px"].as_u64(), Some(2));
    assert_eq!(updated_graphic["height_px"].as_u64(), Some(1));
    let updated_version = updated_graphic["asset_version"]
        .as_u64()
        .expect("expected current-frame control to publish a new asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            61001,
            updated_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 2);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 8);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            61001,
            updated_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(rgba, [0, 255, 0, 255, 0, 255, 0, 255]);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_applies_kitty_animation_compose_control() {
    const SOURCE_2X2_RGBA_BASE64: &str = "/wAA/wD/AP8AAP////8A/w==";
    const BLACK_2X2_RGBA_BASE64: &str = "AAAA/wAAAP8AAAD/AAAA/w==";
    const IMAGE_ID: u64 = 61007;

    let profile = local_profile(
        "kitty-animation-compose-frame-diff",
        "Kitty Animation Compose Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b_Ga=f,f=32,s=2,v=2,i={image_id},r=1,z=1000,q=1;{source}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nsys.stdout.write('\\x1b_Ga=f,f=32,s=2,v=2,i={image_id},r=2,z=1000,q=1;{black}\\x1b\\\\')\nsys.stdout.write('\\x1b_Ga=a,i={image_id},c=2,q=1;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nsys.stdout.write('\\x1b_Ga=c,i={image_id},r=1,c=2,x=1,y=0,w=1,h=1,X=0,Y=1,C=1,q=1;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nPY",
                image_id = IMAGE_ID,
                source = SOURCE_2X2_RGBA_BASE64,
                black = BLACK_2X2_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains(&format!("\"asset_id\":{IMAGE_ID}"))
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphic = first_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(IMAGE_ID))
        })
        .expect("expected first Kitty animation placement");
    let first_render_id = first_graphic["render_id"].as_u64();
    let first_placement_id = first_graphic["placement_id"].as_u64();
    assert_eq!(first_graphic["width_px"].as_u64(), Some(2));
    assert_eq!(first_graphic["height_px"].as_u64(), Some(2));
    let first_version = first_graphic["asset_version"]
        .as_u64()
        .expect("expected first Kitty animation asset version");

    let black_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"]
            .as_array()
            .and_then(|graphics| {
                graphics
                    .iter()
                    .find(|graphic| graphic["asset_id"].as_u64() == Some(IMAGE_ID))
            })
            .and_then(|graphic| graphic["asset_version"].as_u64())
            .is_some_and(|version| version != first_version)
    });
    let black_parsed: serde_json::Value = serde_json::from_str(&black_frame).unwrap();
    let black_graphic = black_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(IMAGE_ID))
        })
        .expect("expected selected destination Kitty animation placement");
    assert_eq!(black_graphic["render_id"].as_u64(), first_render_id);
    assert_eq!(black_graphic["placement_id"].as_u64(), first_placement_id);
    assert_eq!(black_graphic["width_px"].as_u64(), Some(2));
    assert_eq!(black_graphic["height_px"].as_u64(), Some(2));
    let black_version = black_graphic["asset_version"]
        .as_u64()
        .expect("expected destination frame asset version");

    let composed_frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"]
            .as_array()
            .and_then(|graphics| {
                graphics
                    .iter()
                    .find(|graphic| graphic["asset_id"].as_u64() == Some(IMAGE_ID))
            })
            .and_then(|graphic| graphic["asset_version"].as_u64())
            .is_some_and(|version| version != black_version)
    });
    let composed_parsed: serde_json::Value = serde_json::from_str(&composed_frame).unwrap();
    let composed_graphic = composed_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(IMAGE_ID))
        })
        .expect("expected composed Kitty animation placement");
    assert_eq!(composed_graphic["render_id"].as_u64(), first_render_id);
    assert_eq!(
        composed_graphic["placement_id"].as_u64(),
        first_placement_id
    );
    assert_eq!(composed_graphic["width_px"].as_u64(), Some(2));
    assert_eq!(composed_graphic["height_px"].as_u64(), Some(2));
    let composed_version = composed_graphic["asset_version"]
        .as_u64()
        .expect("expected compose command to publish a new asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            IMAGE_ID,
            composed_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 2);
    assert_eq!(meta.height, 2);
    assert_eq!(meta.rgba_len, 16);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            IMAGE_ID,
            composed_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(
        rgba,
        vec![
            0, 0, 0, 255, 0, 0, 0, 255, // first row remains black
            0, 255, 0, 255, // composed green source pixel
            0, 0, 0, 255,
        ]
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_applies_kitty_animation_stop_control() {
    let profile = local_profile(
        "kitty-animation-stop-frame-diff",
        "Kitty Animation Stop Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b_Ga=f,f=32,s=1,v=1,i=61006,r=1,z=1000,q=1;{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nsys.stdout.write('\\x1b_Ga=f,f=32,s=1,v=1,i=61006,r=2,z=1000,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b_Ga=a,i=61006,c=2,q=1;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nsys.stdout.write('\\x1b_Ga=a,i=61006,s=1,q=1;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nPY",
                RED_RGBA_BASE64, GREEN_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| frame.contains("\"asset_id\":61006"));
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphic = first_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61006))
        })
        .expect("expected first Kitty animation placement");
    let first_render_id = first_graphic["render_id"].as_u64();
    let first_placement_id = first_graphic["placement_id"].as_u64();
    assert_eq!(first_graphic["width_px"].as_u64(), Some(1));
    assert_eq!(first_graphic["height_px"].as_u64(), Some(1));
    let first_version = first_graphic["asset_version"]
        .as_u64()
        .expect("expected first Kitty animation asset version");

    let updated = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"]
            .as_array()
            .and_then(|graphics| {
                graphics
                    .iter()
                    .find(|graphic| graphic["asset_id"].as_u64() == Some(61006))
            })
            .and_then(|graphic| graphic["asset_version"].as_u64())
            .is_some_and(|version| version != first_version)
    });
    let updated_parsed: serde_json::Value = serde_json::from_str(&updated).unwrap();
    let updated_graphic = updated_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61006))
        })
        .expect("expected updated Kitty animation placement");
    assert_eq!(updated_graphic["render_id"].as_u64(), first_render_id);
    assert_eq!(updated_graphic["placement_id"].as_u64(), first_placement_id);
    let updated_version = updated_graphic["asset_version"]
        .as_u64()
        .expect("expected current-frame control to publish a new asset version");

    let stopped = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"]
            .as_array()
            .and_then(|graphics| {
                graphics
                    .iter()
                    .find(|graphic| graphic["asset_id"].as_u64() == Some(61006))
            })
            .and_then(|graphic| graphic["asset_version"].as_u64())
            .is_some_and(|version| version == first_version && version != updated_version)
    });
    let stopped_parsed: serde_json::Value = serde_json::from_str(&stopped).unwrap();
    let stopped_graphic = stopped_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61006))
        })
        .expect("expected stopped Kitty animation placement");
    assert_eq!(stopped_graphic["render_id"].as_u64(), first_render_id);
    assert_eq!(stopped_graphic["placement_id"].as_u64(), first_placement_id);
    assert_eq!(stopped_graphic["width_px"].as_u64(), Some(1));
    assert_eq!(stopped_graphic["height_px"].as_u64(), Some(1));

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            61006,
            first_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 4);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            61006,
            first_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(rgba, [255, 0, 0, 255]);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_applies_kitty_animation_frame_delete() {
    let profile = local_profile(
        "kitty-animation-frame-delete-diff",
        "Kitty Animation Frame Delete Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b_Ga=f,f=32,s=1,v=1,i=61002,r=1,z=1000,q=1;{}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nsys.stdout.write('\\x1b_Ga=f,f=32,s=1,v=1,i=61002,r=2,z=1000,q=1;{}\\x1b\\\\')\nsys.stdout.write('\\x1b_Ga=a,i=61002,c=2,q=1;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nsys.stdout.write('\\x1b_Ga=d,d=f,i=61002,r=2,q=1;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nPY",
                RED_RGBA_BASE64, GREEN_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| frame.contains("\"asset_id\":61002"));
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphic = first_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61002))
        })
        .expect("expected first Kitty animation placement");
    let first_render_id = first_graphic["render_id"].as_u64();
    let first_placement_id = first_graphic["placement_id"].as_u64();
    assert_eq!(first_graphic["width_px"].as_u64(), Some(1));
    assert_eq!(first_graphic["height_px"].as_u64(), Some(1));
    let first_version = first_graphic["asset_version"]
        .as_u64()
        .expect("expected first Kitty animation asset version");

    let updated = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"]
            .as_array()
            .and_then(|graphics| {
                graphics
                    .iter()
                    .find(|graphic| graphic["asset_id"].as_u64() == Some(61002))
            })
            .and_then(|graphic| graphic["asset_version"].as_u64())
            .is_some_and(|version| version != first_version)
    });
    let updated_parsed: serde_json::Value = serde_json::from_str(&updated).unwrap();
    let updated_graphic = updated_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61002))
        })
        .expect("expected updated Kitty animation placement");
    assert_eq!(updated_graphic["render_id"].as_u64(), first_render_id);
    assert_eq!(updated_graphic["placement_id"].as_u64(), first_placement_id);
    assert_eq!(updated_graphic["width_px"].as_u64(), Some(1));
    assert_eq!(updated_graphic["height_px"].as_u64(), Some(1));
    let updated_version = updated_graphic["asset_version"]
        .as_u64()
        .expect("expected current-frame control to publish a new asset version");

    let deleted = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"]
            .as_array()
            .and_then(|graphics| {
                graphics
                    .iter()
                    .find(|graphic| graphic["asset_id"].as_u64() == Some(61002))
            })
            .and_then(|graphic| graphic["asset_version"].as_u64())
            .is_some_and(|version| version != updated_version)
    });
    let deleted_parsed: serde_json::Value = serde_json::from_str(&deleted).unwrap();
    let deleted_graphic = deleted_parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(61002))
        })
        .expect("expected fallback Kitty animation placement after frame delete");
    assert_eq!(deleted_graphic["render_id"].as_u64(), first_render_id);
    assert_eq!(deleted_graphic["placement_id"].as_u64(), first_placement_id);
    assert_eq!(deleted_graphic["width_px"].as_u64(), Some(1));
    assert_eq!(deleted_graphic["height_px"].as_u64(), Some(1));
    let deleted_version = deleted_graphic["asset_version"]
        .as_u64()
        .expect("expected frame delete to publish a fallback asset version");
    assert_eq!(deleted_version, first_version);

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            61002,
            deleted_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 1);
    assert_eq!(meta.height, 1);
    assert_eq!(meta.rgba_len, 4);

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            61002,
            deleted_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(rgba, [255, 0, 0, 255]);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_clears_quiet_kitty_delete_without_replacement() {
    let profile = local_profile(
        "kitty-quiet-delete-clear-frame-diff",
        "Kitty Quiet Delete Clear Frame Diff",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=1;/wAA/w==\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.2)\nsys.stdout.write('\\x1b_Ga=d,d=I,i=49374,q=2;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.45)\nfor row in (1, 2, 1):\n    sys.stdout.write(f'\\x1b[{row};1H')\n    sys.stdout.flush()\n    time.sleep(0.15)\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    let first = wait_for_frame_where(session_id, |frame| frame.contains("\"graphics\":[{"));
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    assert_eq!(
        first_parsed["graphics"]
            .as_array()
            .expect("expected graphics placements")
            .len(),
        1
    );

    let mut observed_empty_graphics_frame = false;
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            let graphics = parsed["graphics"]
                .as_array()
                .expect("expected graphics placements field");
            assert_eq!(
                graphics.len(),
                0,
                "quiet Kitty delete without a following replacement must clear graphics in frame diff: {frame}"
            );
            observed_empty_graphics_frame = true;
        }
        if observed_empty_graphics_frame {
            break;
        }
        thread::sleep(Duration::from_millis(100));
    }
    assert!(
        observed_empty_graphics_frame,
        "expected a post-delete frame with empty graphics"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_clears_codex_shutdown_delete_without_replacement() {
    let script = format!(
        r#"
import sys, termios, time

try:
    attrs = termios.tcgetattr(sys.stdin.fileno())
    attrs[3] = attrs[3] & ~termios.ECHO
    termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, attrs)
except Exception:
    pass

def out(value, delay=0.12):
    sys.stdout.write(value)
    sys.stdout.flush()
    time.sleep(delay)

def wait():
    if sys.stdin.readline() == '':
        sys.exit(2)

out('\x1b[10;10H\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374;{png}\x1b\\')
wait()
out('\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\', 0.02)
wait()
out('\x1b[?2026h\x1b[20;1H\x1b[J', 0.02)
out('\x1b[20;2H\x1b[0m\x1b[m\x1b[K\x1b[21;2H\x1b[0m\x1b[m\x1b[K\x1b[22;19H\x1b[0m\x1b[m\x1b[K\x1b[23;2H\x1b[0m\x1b[m\x1b[K\x1b[22;1H›\x1b[22;3HShutting down...\x1b[?2026l', 0.65)
"#,
        png = RED_PIXEL_PNG_BASE64,
    );
    let profile = local_profile(
        "kitty-shutdown-delete-clear",
        "Kitty Shutdown Delete Clear",
        "/usr/bin/env",
        vec!["python3".to_string(), "-c".to_string(), script],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":49374")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphics = first_parsed["graphics"]
        .as_array()
        .expect("expected first graphics placements");
    assert_eq!(first_graphics.len(), 1, "expected first pet frame: {first}");

    session::write_session(session_id, b"\n").unwrap();
    let delete_frame = wait_for_frame_where(session_id, |frame| frame.contains("\"graphics\":[]"));
    let delete_parsed: serde_json::Value = serde_json::from_str(&delete_frame).unwrap();
    let delete_graphics = delete_parsed["graphics"]
        .as_array()
        .expect("expected graphics placements field");
    assert_eq!(
        delete_graphics.len(),
        0,
        "Codex shutdown delete has no following Kitty replacement and must clear graphics before shutdown text: {delete_frame}"
    );

    session::write_session(session_id, b"\n").unwrap();

    let mut observed_shutdown_frame = false;
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            let graphics = parsed["graphics"]
                .as_array()
                .expect("expected graphics placements field");
            if frame.contains("Shutting down") {
                assert_eq!(
                    graphics.len(),
                    0,
                    "Codex shutdown delete has no following Kitty replacement and must clear graphics: {frame}"
                );
                observed_shutdown_frame = true;
                break;
            }
        }
        thread::sleep(Duration::from_millis(50));
    }

    assert!(
        observed_shutdown_frame,
        "expected to observe a Codex-style shutdown frame"
    );
    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_defers_single_clear_screen_graphics_gap() {
    let profile = local_profile(
        "kitty-clear-screen-graphics-gap",
        "Kitty Clear Screen Graphics Gap",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[10;10H\\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=1;/wAA/w==\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nsys.stdout.write('\\x1b[2J\\x1b[3J\\x1b[Hafter clear\\n')\nsys.stdout.flush()\ntime.sleep(1.00)\nsys.stdout.write('\\x1b[20;30H\\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=1;AP8A/w==\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":49374")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_render_id = first_parsed["graphics"][0]["render_id"]
        .as_u64()
        .expect("expected first render id");
    let first_version = first_parsed["graphics"][0]["asset_version"]
        .as_u64()
        .expect("expected first asset version");

    thread::sleep(Duration::from_millis(300));
    let mut observed_retained_clear_frame = false;
    for _ in 0..5 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            let graphics = parsed["graphics"]
                .as_array()
                .expect("expected graphics field in clear-screen frame");
            assert!(
                !graphics.is_empty(),
                "clear-screen redraw window must not emit an empty graphics frame after a visible graphic: {frame}"
            );
            assert_eq!(
                graphics[0]["render_id"].as_u64(),
                Some(first_render_id),
                "retained clear-screen placement should keep the previous render id: {frame}"
            );
            if graphics[0]["asset_version"].as_u64() == Some(first_version) {
                observed_retained_clear_frame = true;
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    assert!(
        observed_retained_clear_frame,
        "expected to observe the old graphic retained while clear-screen redraw waits for replacement"
    );

    let replacement = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{")
            && !frame.contains(&format!("\"asset_version\":{first_version}"))
    });
    let parsed: serde_json::Value = serde_json::from_str(&replacement).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected replacement graphics placements");
    assert_eq!(
        graphics.len(),
        1,
        "replacement frame must keep graphics visible after clear coalescing: {replacement}"
    );
    assert_eq!(
        graphics[0]["render_id"].as_u64(),
        Some(first_render_id),
        "clear-screen redraw should preserve the graphic render id so Flutter keeps the existing overlay while the replacement asset loads: {replacement}"
    );
    assert_eq!(
        graphics[0]["row"].as_u64(),
        Some(19),
        "replacement should still be allowed to move after clear-screen redraw: {replacement}"
    );
    assert_eq!(
        graphics[0]["col"].as_u64(),
        Some(29),
        "replacement should still be allowed to move after clear-screen redraw: {replacement}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_clears_kitty_clear_screen_when_no_replacement_arrives() {
    let profile = local_profile(
        "kitty-clear-screen-no-replacement",
        "Kitty Clear Screen No Replacement",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[10;10H\\x1b_Ga=T,f=32,s=1,v=1,i=62060,q=1;{red}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nsys.stdout.write('\\x1b[2J\\x1b[3J\\x1b[Hafter clear\\n')\nsys.stdout.flush()\ntime.sleep(0.25)\nsys.stdout.write('settled no replacement\\n')\nsys.stdout.flush()\ntime.sleep(0.20)\nPY",
                red = RED_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":62060")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_render_id = first_parsed["graphics"][0]["render_id"]
        .as_u64()
        .expect("expected first render id");

    let clear_frame = wait_for_frame_where(session_id, |frame| frame.contains("after clear"));
    let clear_parsed: serde_json::Value = serde_json::from_str(&clear_frame).unwrap();
    let clear_graphics = clear_parsed["graphics"]
        .as_array()
        .expect("expected graphics field in clear-screen frame");
    assert!(
        clear_graphics.iter().any(|graphic| {
            graphic["asset_id"].as_u64() == Some(62060)
                && graphic["render_id"].as_u64() == Some(first_render_id)
        }),
        "clear-screen frame should retain the previous Kitty overlay for a redraw window: {clear_frame}"
    );

    let settled_frame =
        wait_for_frame_where(session_id, |frame| frame.contains("settled no replacement"));
    let settled_parsed: serde_json::Value = serde_json::from_str(&settled_frame).unwrap();
    assert!(
        settled_parsed["graphics"]
            .as_array()
            .is_none_or(|graphics| {
                !graphics
                    .iter()
                    .any(|graphic| graphic["asset_id"].as_u64() == Some(62060))
            }),
        "ordinary output after a clear-screen with no Kitty replacement must stop exporting the stale placement: {settled_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_synchronized_output_coalesces_clear_screen_graphics_replacement() {
    let profile = local_profile(
        "sync-kitty-clear-screen-replacement",
        "Synchronized Kitty Clear Screen Replacement",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[10;10H\\x1b_Ga=T,f=32,s=1,v=1,i=62006,q=1;{red}\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nsys.stdout.write('\\x1b[?2026h')\nsys.stdout.write('\\x1b[2J\\x1b[Hsync replace pending\\n')\nsys.stdout.flush()\ntime.sleep(0.35)\nsys.stdout.write('\\x1b[20;30H\\x1b_Ga=T,f=32,s=1,v=1,i=62006,q=1;{green}\\x1b\\\\')\nsys.stdout.write('\\x1b[?2026l')\nsys.stdout.flush()\ntime.sleep(0.20)\nPY",
                red = RED_RGBA_BASE64,
                green = GREEN_RGBA_BASE64
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":62006")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_render_id = first_parsed["graphics"][0]["render_id"]
        .as_u64()
        .expect("expected first render id");
    let first_version = first_parsed["graphics"][0]["asset_version"]
        .as_u64()
        .expect("expected first asset version");

    thread::sleep(Duration::from_millis(450));
    for _ in 0..6 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            assert_eq!(
                parsed["modes"]["synchronized_output"].as_bool(),
                Some(false),
                "synchronized output should not publish intermediate graphics frames: {frame}"
            );
            let graphics = parsed["graphics"]
                .as_array()
                .expect("expected graphics field after synchronized output flush");
            assert!(
                !graphics.is_empty(),
                "synchronized clear-screen replacement must not publish an empty graphics frame: {frame}"
            );
            assert!(
                frame.contains("sync replace pending"),
                "synchronized output should flush the final redrawn text with the replacement: {frame}"
            );
            assert_eq!(
                graphics[0]["render_id"].as_u64(),
                Some(first_render_id),
                "synchronized replacement should preserve render identity across clear: {frame}"
            );
            assert_ne!(
                graphics[0]["asset_version"].as_u64(),
                Some(first_version),
                "synchronized replacement should publish the replacement asset version: {frame}"
            );
            assert_eq!(graphics[0]["row"].as_u64(), Some(19));
            assert_eq!(graphics[0]["col"].as_u64(), Some(29));
            session::close_session(session_id).unwrap();
            return;
        }
        thread::sleep(Duration::from_millis(75));
    }

    let frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("sync replace pending")
            && frame.contains("\"graphics\":[{")
            && !frame.contains(&format!("\"asset_version\":{first_version}"))
    });
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let graphics = parsed["graphics"]
        .as_array()
        .expect("expected graphics field after synchronized output flush");
    assert_eq!(
        parsed["modes"]["synchronized_output"].as_bool(),
        Some(false),
        "synchronized output should be disabled after final flush: {frame}"
    );
    assert_eq!(
        graphics[0]["render_id"].as_u64(),
        Some(first_render_id),
        "synchronized replacement should preserve render identity across clear: {frame}"
    );
    assert_eq!(graphics[0]["row"].as_u64(), Some(19));
    assert_eq!(graphics[0]["col"].as_u64(), Some(29));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_synchronized_output_coalesces_iterm_and_sixel_redraw() {
    let profile = local_profile(
        "sync-iterm-sixel-redraw",
        "Synchronized iTerm Sixel Redraw",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b[2;2H\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{png}\\x1b\\\\')\nsys.stdout.write('\\x1b[6;2H\\x1bPq#2~\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nsys.stdout.write('\\x1b[?2026h')\nsys.stdout.write('\\x1b[2J\\x1b[Hsync raster redraw\\n')\nsys.stdout.flush()\ntime.sleep(0.35)\nsys.stdout.write('\\x1b[10;5H\\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{png}\\x1b\\\\')\nsys.stdout.write('\\x1b[15;5H\\x1bPq#2~\\x1b\\\\')\nsys.stdout.write('\\x1b[?2026l')\nsys.stdout.flush()\ntime.sleep(0.20)\nPY",
                png = RED_PIXEL_PNG_BASE64,
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let graphic_rows_for_protocol = |frame: &str, protocol: &str| -> Vec<(u64, u64)> {
        let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
        parsed["graphics"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|graphic| graphic["protocol"].as_str() == Some(protocol))
            .filter_map(|graphic| Some((graphic["row"].as_u64()?, graphic["col"].as_u64()?)))
            .collect()
    };

    let initial = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["graphics"].as_array().is_some_and(|graphics| {
            let has_iterm = graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("iterm"));
            let has_sixel = graphics
                .iter()
                .any(|graphic| graphic["protocol"].as_str() == Some("sixel"));
            has_iterm && has_sixel
        })
    });
    assert_eq!(
        graphic_rows_for_protocol(&initial, "iterm"),
        vec![(1, 1)],
        "initial iTerm graphic should be visible before synchronized redraw: {initial}"
    );
    assert_eq!(
        graphic_rows_for_protocol(&initial, "sixel"),
        vec![(5, 1)],
        "initial Sixel graphic should be visible before synchronized redraw: {initial}"
    );

    thread::sleep(Duration::from_millis(450));
    for _ in 0..6 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            assert_eq!(
                parsed["modes"]["synchronized_output"].as_bool(),
                Some(false),
                "synchronized output must not publish an intermediate iTerm/Sixel redraw frame: {frame}"
            );
            assert!(
                frame.contains("sync raster redraw"),
                "synchronized output should flush final text with the replacement graphics: {frame}"
            );
            assert_eq!(
                graphic_rows_for_protocol(&frame, "iterm"),
                vec![(9, 4)],
                "final synchronized iTerm graphic should use the replacement anchor: {frame}"
            );
            assert_eq!(
                graphic_rows_for_protocol(&frame, "sixel"),
                vec![(14, 4)],
                "final synchronized Sixel graphic should use the replacement anchor: {frame}"
            );
            session::close_session(session_id).unwrap();
            return;
        }
        thread::sleep(Duration::from_millis(75));
    }

    let final_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("sync raster redraw")
            && graphic_rows_for_protocol(frame, "iterm") == vec![(9, 4)]
            && graphic_rows_for_protocol(frame, "sixel") == vec![(14, 4)]
    });
    let final_parsed: serde_json::Value = serde_json::from_str(&final_frame).unwrap();
    assert_eq!(
        final_parsed["modes"]["synchronized_output"].as_bool(),
        Some(false),
        "synchronized output should be disabled after final iTerm/Sixel redraw: {final_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_keeps_codex_pet_graphic_across_split_replacement() {
    let chunks = RED_PIXEL_PNG_BASE64
        .as_bytes()
        .chunks(16)
        .map(|chunk| std::str::from_utf8(chunk).unwrap())
        .collect::<Vec<_>>();
    let chunks_json = serde_json::to_string(&chunks).unwrap();
    let script = format!(
        r#"
import sys, termios, time

chunks = {chunks_json}

try:
    attrs = termios.tcgetattr(sys.stdin.fileno())
    attrs[3] = attrs[3] & ~termios.ECHO
    termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, attrs)
except Exception:
    pass

def out(value):
    sys.stdout.write(value)
    sys.stdout.flush()
    time.sleep(0.04)

def wait():
    if sys.stdin.readline() == '':
        sys.exit(2)

out('\x1b7\x1b[10;10H\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374;{png}\x1b\\\x1b8')
wait()
out('\x1b[?2026h\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\\x1b7\x1b[10;10H')
for index, payload in enumerate(chunks):
    if index == 0:
        out('\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49375,m=1;' + payload + '\x1b\\')
    elif index + 1 == len(chunks):
        out('\x1b_Gm=0;' + payload + '\x1b\\\x1b8\x1b[?2026l')
    else:
        out('\x1b_Gm=1;' + payload + '\x1b\\')
    if index + 1 < len(chunks):
        out('\x1b7\x1b[1;1Hstartup log line\x1b8')
    out('\x1b[' + str(1 + (index % 2)) + ';1H')
    wait()
"#,
        chunks_json = chunks_json,
        png = RED_PIXEL_PNG_BASE64,
    );
    let profile = local_profile(
        "kitty-split-pet-frame-diff",
        "Kitty Split Pet Frame Diff",
        "/usr/bin/env",
        vec!["python3".to_string(), "-c".to_string(), script],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":49374")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphics = first_parsed["graphics"]
        .as_array()
        .expect("expected graphics placements in first frame");
    assert_eq!(first_graphics.len(), 1, "expected first pet frame: {first}");
    let placement_id = first_graphics[0]["placement_id"]
        .as_u64()
        .expect("expected stable placement id");

    session::write_session(session_id, b"\n").unwrap();

    let assert_replacement_frame = |frame: &str| -> u64 {
        let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
        let graphics = parsed["graphics"]
            .as_array()
            .expect("expected graphics placements field");
        assert_eq!(
            graphics.len(),
            1,
            "split Kitty pet replacement must not emit a frame without graphics: {frame}"
        );
        assert_eq!(
            graphics[0]["placement_id"].as_u64(),
            Some(placement_id),
            "replacement must keep the same placement identity: {frame}"
        );
        graphics[0]["asset_id"]
            .as_u64()
            .expect("expected graphic asset id")
    };

    let mut observed_final_asset = false;
    for chunk_index in 0..chunks.len() {
        for _ in 0..20 {
            if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
                let asset_id = assert_replacement_frame(&frame);
                if asset_id == 49375 {
                    observed_final_asset = true;
                    break;
                }
                assert_eq!(asset_id, 49374, "unexpected intermediate asset: {frame}");
            }
            thread::sleep(Duration::from_millis(50));
        }
        if observed_final_asset || chunk_index + 1 == chunks.len() {
            break;
        }
        session::write_session(session_id, b"\n").unwrap();
    }

    if !observed_final_asset {
        for _ in 0..SESSION_WAIT_ATTEMPTS {
            if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
                let asset_id = assert_replacement_frame(&frame);
                if asset_id == 49375 {
                    observed_final_asset = true;
                    break;
                }
                assert_eq!(asset_id, 49374, "unexpected intermediate asset: {frame}");
            }
            thread::sleep(Duration::from_millis(50));
        }
    }

    assert!(
        observed_final_asset,
        "expected final replacement asset in frame diff"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_clears_codex_pet_after_split_replacement_final_delete() {
    let chunks = RED_PIXEL_PNG_BASE64
        .as_bytes()
        .chunks(16)
        .map(|chunk| std::str::from_utf8(chunk).unwrap())
        .collect::<Vec<_>>();
    let chunks_json = serde_json::to_string(&chunks).unwrap();
    let profile = local_profile(
        "kitty-split-pet-final-delete",
        "Kitty Split Pet Final Delete",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                r#"python3 - <<'PY'
import sys, time

chunks = {chunks_json}

def out(value, delay=0.04):
    sys.stdout.write(value)
    sys.stdout.flush()
    time.sleep(delay)

out('\x1b7\x1b[10;10H\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374;{png}\x1b\\\x1b8', 0.18)
out('\x1b[?2026h\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\\x1b7\x1b[10;10H', 0.02)
for index, payload in enumerate(chunks):
    if index == 0:
        out('\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374,m=1;' + payload + '\x1b\\', 0.01)
    elif index + 1 == len(chunks):
        out('\x1b_Gm=0;' + payload + '\x1b\\\x1b8\x1b[?2026l', 0.12)
    else:
        out('\x1b_Gm=1;' + payload + '\x1b\\', 0.01)
out('\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\', 0.02)
out('\x1b[?2026h\x1b[20;1H\x1b[J\x1b[22;1HShutting down...\x1b[?2026l', 0.60)
PY"#,
                chunks_json = chunks_json,
                png = RED_PIXEL_PNG_BASE64,
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":49374")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphics = first_parsed["graphics"]
        .as_array()
        .expect("expected first graphics placements");
    assert_eq!(first_graphics.len(), 1, "expected first pet frame: {first}");

    let mut observed_shutdown_clear = false;
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            let graphics = parsed["graphics"]
                .as_array()
                .expect("expected graphics placements field");
            if frame.contains("Shutting down") {
                assert_eq!(
                    graphics.len(),
                    0,
                    "final Kitty delete after split replacement must clear graphics in the shutdown frame: {frame}"
                );
                observed_shutdown_clear = true;
                break;
            }
        }
        thread::sleep(Duration::from_millis(50));
    }

    assert!(
        observed_shutdown_clear,
        "expected a shutdown frame after final Kitty delete"
    );
    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_waits_for_synchronized_graphics_update_to_finish() {
    let profile = local_profile(
        "kitty-sync-graphics-frame-boundary",
        "Kitty Sync Graphics Frame Boundary",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=1;/wAA/w==\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nsys.stdout.write('\\x1b[?2026h\\x1b_Ga=d,d=I,i=49374,q=2;\\x1b\\\\\\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=2,m=1;AP8A\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.75)\nsys.stdout.write('\\x1b_Gm=0;/w==\\x1b\\\\\\x1b[?2026l')\nsys.stdout.flush()\ntime.sleep(0.15)\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":49374")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphics = first_parsed["graphics"]
        .as_array()
        .expect("expected first graphics placements");
    assert_eq!(first_graphics.len(), 1, "expected initial graphic: {first}");
    let placement_id = first_graphics[0]["placement_id"]
        .as_u64()
        .expect("expected stable placement id");
    let first_asset_version = first_graphics[0]["asset_version"]
        .as_u64()
        .expect("expected first asset version");

    thread::sleep(Duration::from_millis(420));
    assert!(
        session::take_frame_diff(session_id).unwrap().is_none(),
        "frame diff must not expose a partially applied synchronized graphics update"
    );

    let final_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{")
            && !frame.contains(&format!("\"asset_version\":{first_asset_version}"))
    });
    let final_parsed: serde_json::Value = serde_json::from_str(&final_frame).unwrap();
    let final_graphics = final_parsed["graphics"]
        .as_array()
        .expect("expected final graphics placements");
    assert_eq!(
        final_graphics.len(),
        1,
        "expected final replacement graphic: {final_frame}"
    );
    assert_eq!(
        final_graphics[0]["placement_id"].as_u64(),
        Some(placement_id),
        "synchronized replacement must keep placement identity: {final_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_graces_delayed_kitty_replacement_start() {
    let profile = local_profile(
        "kitty-delayed-replacement-frame-boundary",
        "Kitty Delayed Replacement Frame Boundary",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            "python3 - <<'PY'\nimport sys, time\nsys.stdout.write('\\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=1;/wAA/w==\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.25)\nsys.stdout.write('\\x1b_Ga=d,d=I,i=49374,q=2;\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(1.0)\nsys.stdout.write('\\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=2;AP8A/w==\\x1b\\\\')\nsys.stdout.flush()\ntime.sleep(0.15)\nPY"
                .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":49374")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphics = first_parsed["graphics"]
        .as_array()
        .expect("expected first graphics placements");
    assert_eq!(first_graphics.len(), 1, "expected initial graphic: {first}");
    let first_asset_version = first_graphics[0]["asset_version"]
        .as_u64()
        .expect("expected first asset version");

    thread::sleep(Duration::from_millis(450));
    assert!(
        session::take_frame_diff(session_id).unwrap().is_none(),
        "first poll in the delayed replacement gap should defer the clear frame"
    );
    assert!(
        session::take_frame_diff(session_id).unwrap().is_none(),
        "second poll in the delayed replacement gap should still defer the clear frame"
    );

    let final_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{")
            && !frame.contains(&format!("\"asset_version\":{first_asset_version}"))
    });
    let final_parsed: serde_json::Value = serde_json::from_str(&final_frame).unwrap();
    let final_graphics = final_parsed["graphics"]
        .as_array()
        .expect("expected final graphics placements");
    assert_eq!(
        final_graphics.len(),
        1,
        "expected final replacement graphic: {final_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_waits_for_incomplete_kitty_transfer_to_finish() {
    let chunks = RED_PIXEL_PNG_BASE64
        .as_bytes()
        .chunks(16)
        .map(|chunk| std::str::from_utf8(chunk).unwrap())
        .collect::<Vec<_>>();
    let first_chunk = chunks[0];
    let final_chunk = chunks[1..].join("");
    let profile = local_profile(
        "kitty-transfer-frame-boundary",
        "Kitty Transfer Frame Boundary",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                r#"python3 - <<'PY'
import sys, time

def out(value):
    sys.stdout.write(value)
    sys.stdout.flush()

out('\x1b_Ga=T,f=32,s=1,v=1,i=49374;/wAA/w==\x1b\\')
time.sleep(0.25)
out('\x1b_Ga=d,d=I,i=49374;\x1b\\')
out('\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49375,m=1;{first_chunk}\x1b\\')
time.sleep(0.75)
out('\x1b_Gm=0;{final_chunk}\x1b\\')
time.sleep(0.15)
PY"#,
                first_chunk = first_chunk,
                final_chunk = final_chunk,
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let first = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":49374")
    });
    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let first_graphics = first_parsed["graphics"]
        .as_array()
        .expect("expected first graphics placements");
    assert_eq!(first_graphics.len(), 1, "expected initial graphic: {first}");

    thread::sleep(Duration::from_millis(420));
    assert!(
        session::take_frame_diff(session_id).unwrap().is_none(),
        "frame diff must not expose an empty intermediate graphics state while Kitty transfer is incomplete"
    );

    let final_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":49375")
    });
    let final_parsed: serde_json::Value = serde_json::from_str(&final_frame).unwrap();
    let final_graphics = final_parsed["graphics"]
        .as_array()
        .expect("expected final graphics placements");
    assert_eq!(
        final_graphics.len(),
        1,
        "expected final replacement graphic: {final_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_accepts_chunked_kitty_raw_pixel_transfer() {
    let raw_pixels = (0..64)
        .flat_map(|index| {
            if index % 2 == 0 {
                [255, 0, 0, 255]
            } else {
                [0, 255, 0, 255]
            }
        })
        .collect::<Vec<_>>();
    let raw_pixels_base64 = base64_standard_no_pad_encode(&raw_pixels);
    let chunks = raw_pixels_base64
        .as_bytes()
        .chunks(32)
        .map(|chunk| std::str::from_utf8(chunk).unwrap())
        .collect::<Vec<_>>();
    assert!(
        chunks.len() > 4,
        "test setup must exercise a multi-chunk raw pixel transfer"
    );
    let mut chunk_commands = String::new();
    for (index, chunk) in chunks.iter().enumerate() {
        let header = if index == 0 {
            "a=T,f=32,s=8,v=8,c=4,r=4,i=49376,q=1,m=1;"
        } else if index == chunks.len() - 1 {
            "m=0;"
        } else {
            "m=1;"
        };
        chunk_commands.push_str(&format!("out('\\x1b_G{header}{chunk}\\x1b\\\\')\n"));
        chunk_commands.push_str("time.sleep(0.05)\n");
    }
    let profile = local_profile(
        "kitty-raw-pixel-chunked-transfer",
        "Kitty Raw Pixel Chunked Transfer",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            format!(
                r#"python3 - <<'PY'
import sys, time

def out(value):
    sys.stdout.write(value)
    sys.stdout.flush()

{chunk_commands}
time.sleep(0.15)
PY"#,
                chunk_commands = chunk_commands,
            ),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    thread::sleep(Duration::from_millis(280));
    for _ in 0..3 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            assert!(
                !frame.contains("\"asset_id\":49376"),
                "raw-pixel Kitty transfer must not publish before the final chunk: {frame}"
            );
        }
    }

    let final_frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"graphics\":[{") && frame.contains("\"asset_id\":49376")
    });
    let parsed: serde_json::Value = serde_json::from_str(&final_frame).unwrap();
    let graphic = parsed["graphics"]
        .as_array()
        .and_then(|graphics| {
            graphics
                .iter()
                .find(|graphic| graphic["asset_id"].as_u64() == Some(49376))
        })
        .expect("expected chunked raw-pixel Kitty placement");
    assert_eq!(graphic["protocol"].as_str(), Some("kitty"));
    assert_eq!(graphic["width_cells"].as_u64(), Some(4));
    assert_eq!(graphic["height_cells"].as_u64(), Some(4));
    let asset_version = graphic["asset_version"]
        .as_u64()
        .expect("expected chunked raw-pixel asset version");

    let mut meta = ianvs_core::ffi::IanvsGraphicAssetMeta::default();
    let meta_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_meta(
            session_id,
            49376,
            asset_version,
            &mut meta,
        )
    };
    assert_eq!(meta_status, 0);
    assert_eq!(meta.width, 8);
    assert_eq!(meta.height, 8);
    assert_eq!(meta.rgba_len, raw_pixels.len());

    let mut rgba = vec![0_u8; meta.rgba_len];
    let copy_status = unsafe {
        ianvs_core::ffi::ianvs_session_graphic_asset_rgba_copy(
            session_id,
            49376,
            asset_version,
            rgba.as_mut_ptr(),
            rgba.len(),
        )
    };
    assert_eq!(copy_status, rgba.len() as isize);
    assert_eq!(rgba, raw_pixels);

    session::close_session(session_id).unwrap();
}

#[test]
fn parser_terminal_handles_kitty_direct_graphics_and_query() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let transmit_display =
        format!("\x1b_Ga=T,f=32,s=1,v=1,c=2,r=2,i=7,p=5;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(transmit_display.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
    assert_eq!(graphic.kitty_image_id, Some(7));
    assert_eq!(graphic.kitty_placement_id, Some(5));
    assert_eq!(graphic.placement.columns, Some(2));
    assert_eq!(graphic.placement.rows, Some(2));
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b_Gi=7;OK\x1b\\"
    );

    let mut source_rect_terminal = ParserTerminal::new(80, 24);
    const TWO_BY_TWO_RGBA_BASE64: &str = "/wAA/wD/AP8AAP////8A/w==";
    let source_rect_display = format!(
        "\x1b_Ga=T,f=32,s=2,v=2,x=1,y=0,w=1,h=2,X=3,Y=4,c=4,r=2,i=11,p=6;{TWO_BY_TWO_RGBA_BASE64}\x1b\\"
    );
    source_rect_terminal.process(source_rect_display.as_bytes());

    assert_eq!(source_rect_terminal.graphics_count(), 1);
    let graphic = &source_rect_terminal.all_graphics()[0];
    assert_eq!(graphic.width, 2);
    assert_eq!(graphic.height, 2);
    assert_eq!(graphic.kitty_image_id, Some(11));
    assert_eq!(graphic.kitty_placement_id, Some(6));
    assert_eq!(graphic.placement.columns, Some(4));
    assert_eq!(graphic.placement.rows, Some(2));
    assert_eq!(graphic.placement.source_x_offset, 1);
    assert_eq!(graphic.placement.source_y_offset, 0);
    assert_eq!(graphic.placement.source_width, Some(1));
    assert_eq!(graphic.placement.source_height, Some(2));
    assert_eq!(graphic.placement.x_offset, 3);
    assert_eq!(graphic.placement.y_offset, 4);

    let mut query_terminal = ParserTerminal::new(80, 24);
    let query = format!("\x1b_Ga=q,f=32,s=1,v=1,i=9;{RED_RGBA_BASE64}\x1b\\");
    query_terminal.process(query.as_bytes());

    assert_eq!(query_terminal.graphics_count(), 0);
    assert_eq!(
        String::from_utf8(query_terminal.drain_responses()).unwrap(),
        "\x1b_Gi=9;OK\x1b\\"
    );

    let mut empty_query_terminal = ParserTerminal::new(80, 24);
    empty_query_terminal.process(b"\x1b_Ga=q,i=10;\x1b\\");
    assert_eq!(empty_query_terminal.graphics_count(), 0);
    assert_eq!(
        String::from_utf8(empty_query_terminal.drain_responses()).unwrap(),
        "\x1b_Gi=10;OK\x1b\\"
    );

    let mut quiet_terminal = ParserTerminal::new(80, 24);
    let quiet = format!("\x1b_Ga=T,f=32,s=1,v=1,i=12,q=1;{RED_RGBA_BASE64}\x1b\\");
    quiet_terminal.process(quiet.as_bytes());
    assert_eq!(quiet_terminal.graphics_count(), 1);
    assert!(quiet_terminal.drain_responses().is_empty());

    let mut quiet_error_terminal = ParserTerminal::new(80, 24);
    quiet_error_terminal.process(b"\x1b_Ga=p,i=404,q=2;\x1b\\");
    assert_eq!(quiet_error_terminal.graphics_count(), 0);
    assert!(quiet_error_terminal.drain_responses().is_empty());
}

#[test]
fn parser_terminal_kitty_direct_graphics_accepts_c1_apc_and_st_controls() {
    let mut terminal = ParserTerminal::new(80, 24);
    let mut sequence = Vec::new();
    sequence.push(0x9f);
    sequence.extend_from_slice(b"Ga=T,f=32,s=1,v=1,i=17,q=1;/wAA/w==");
    sequence.push(0x9c);

    terminal.process(&sequence);

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
    assert_eq!(graphic.kitty_image_id, Some(17));
    assert_eq!(graphic.pixels.as_ref(), &[255, 0, 0, 255]);
    assert!(terminal.drain_responses().is_empty());
}

#[test]
fn parser_terminal_kitty_uppercase_delete_all_releases_unplaced_image_data() {
    let mut terminal = ParserTerminal::new(8, 4);
    let transmit = format!("\x1b_Ga=t,f=32,s=1,v=1,i=810,q=1;{RED_RGBA_BASE64}\x1b\\");

    terminal.process(transmit.as_bytes());
    assert_eq!(
        terminal.graphics_count(),
        0,
        "transmit-only Kitty image should retain data without adding a placement"
    );

    terminal.process(b"\x1b_Ga=d,d=A,q=1;\x1b\\");
    terminal.process(b"\x1b_Ga=p,i=810,p=1,q=1;\x1b\\");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "uppercase d=A should release unplaced image data so later Put cannot display it"
    );
}

#[test]
fn parser_terminal_kitty_uppercase_placement_delete_keeps_referenced_image_data() {
    let mut terminal = ParserTerminal::new(8, 4);
    let transmit = format!("\x1b_Ga=t,f=32,s=1,v=1,i=811,q=1;{RED_RGBA_BASE64}\x1b\\");

    terminal.process(transmit.as_bytes());
    terminal.process(b"\x1b[1;1H\x1b_Ga=p,i=811,p=1,C=1,q=1;\x1b\\");
    terminal.process(b"\x1b[1;4H\x1b_Ga=p,i=811,p=2,C=1,q=1;\x1b\\");

    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b_Ga=d,d=I,i=811,p=1,q=1;\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(811));
    assert_eq!(terminal.all_graphics()[0].kitty_placement_id, Some(2));

    terminal.process(b"\x1b[3;1H\x1b_Ga=p,i=811,p=3,C=1,q=1;\x1b\\");

    assert_eq!(
        terminal.graphics_count(),
        2,
        "uppercase placement delete must keep shared image data while another placement references it"
    );
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.kitty_placement_id == Some(3))
    );
}

#[test]
fn parser_terminal_kitty_file_medium_reads_png_from_path() {
    let temp = tempdir().unwrap();
    let path = temp.path().join("kitty-file-image.png");
    fs::write(&path, red_pixel_png_bytes()).unwrap();

    let mut terminal = ParserTerminal::new(80, 24);
    let path_payload = kitty_path_payload(&path);
    let sequence = format!("\x1b_Ga=T,t=f,f=100,i=810,q=1;{path_payload}\x1b\\");
    terminal.process(sequence.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
    assert_eq!(graphic.kitty_image_id, Some(810));
    assert_eq!(graphic.pixels.as_ref(), &[255, 0, 0, 255]);
    assert!(path.exists(), "t=f must not delete the source file");
}

#[test]
fn parser_terminal_kitty_file_medium_respects_offset_and_size() {
    let temp = tempdir().unwrap();
    let path = temp.path().join("kitty-file-range.bin");
    let mut bytes = b"junk".to_vec();
    bytes.extend_from_slice(red_pixel_png_bytes());
    bytes.extend_from_slice(b"tail");
    fs::write(&path, bytes).unwrap();

    let mut terminal = ParserTerminal::new(80, 24);
    let path_payload = kitty_path_payload(&path);
    let sequence = format!(
        "\x1b_Ga=T,t=f,f=100,O=4,S={},i=811,q=1;{path_payload}\x1b\\",
        red_pixel_png_bytes().len()
    );
    terminal.process(sequence.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.kitty_image_id, Some(811));
    assert_eq!(graphic.pixels.as_ref(), &[255, 0, 0, 255]);
    assert!(
        path.exists(),
        "t=f range reads must not delete the source file"
    );
}

#[test]
fn parser_terminal_kitty_file_medium_decompresses_file_contents_after_path_read() {
    let temp = tempdir().unwrap();
    let compressed_path = temp.path().join("compressed-rgba.bin");
    let compressed_rgba = [120, 156, 251, 207, 192, 240, 31, 0, 4, 255, 1, 255];
    fs::write(&compressed_path, compressed_rgba).unwrap();

    let mut terminal = ParserTerminal::new(80, 24);
    let path_payload = kitty_path_payload(&compressed_path);
    let sequence = format!("\x1b_Ga=T,t=f,o=z,f=32,s=1,v=1,i=812,q=1;{path_payload}\x1b\\");
    terminal.process(sequence.as_bytes());

    assert!(
        terminal.drain_responses().is_empty(),
        "q=1 compressed file transfer should not emit an OK response"
    );
    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.kitty_image_id, Some(812));
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
    assert_eq!(
        graphic.pixels.as_ref(),
        &[255, 0, 0, 255],
        "Kitty o=z file transfers must decompress the file contents after resolving the path"
    );
}

#[test]
fn parser_terminal_kitty_temp_file_medium_deletes_only_safe_temp_paths() {
    let temp = tempdir().unwrap();
    let safe_path = temp.path().join("tty-graphics-protocol-image.png");
    fs::write(&safe_path, red_pixel_png_bytes()).unwrap();

    let mut terminal = ParserTerminal::new(80, 24);
    let safe_payload = kitty_path_payload(&safe_path);
    let safe_sequence = format!("\x1b_Ga=T,t=t,f=100,i=812,q=1;{safe_payload}\x1b\\");
    terminal.process(safe_sequence.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(812));
    assert!(
        !safe_path.exists(),
        "safe t=t files should be deleted after reading"
    );

    let unmarked_path = temp.path().join("plain-image.png");
    fs::write(&unmarked_path, red_pixel_png_bytes()).unwrap();

    let unmarked_payload = kitty_path_payload(&unmarked_path);
    let unmarked_sequence = format!("\x1b_Ga=T,t=t,f=100,i=813,q=1;{unmarked_payload}\x1b\\");
    terminal.process(unmarked_sequence.as_bytes());

    assert_eq!(terminal.graphics_count(), 2);
    assert_eq!(terminal.all_graphics()[1].kitty_image_id, Some(813));
    assert!(
        unmarked_path.exists(),
        "t=t must not delete temp files missing the Kitty marker"
    );
}

#[cfg(unix)]
#[test]
fn parser_terminal_kitty_shared_memory_medium_renders_png_range_and_unlinks() {
    let mut terminal = ParserTerminal::new(80, 24);
    let mut shared_data = b"skip".to_vec();
    shared_data.extend_from_slice(red_pixel_png_bytes());
    let Some((shared_memory_name, shared_memory_payload)) =
        create_kitty_shared_memory_payload(&shared_data)
    else {
        return;
    };

    let sequence = format!(
        "\x1b_Ga=T,t=s,f=100,i=814,O=4,S={},q=1;{}\x1b\\",
        red_pixel_png_bytes().len(),
        shared_memory_payload,
    );
    terminal.process(sequence.as_bytes());

    let still_exists = kitty_shared_memory_exists(&shared_memory_name);
    if still_exists {
        unlink_kitty_shared_memory(&shared_memory_name);
    }
    assert!(
        !still_exists,
        "POSIX shared memory transfer must unlink the object after reading"
    );
    assert!(
        terminal.drain_responses().is_empty(),
        "q=1 shared memory transfer should not emit an OK response"
    );
    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.kitty_image_id, Some(814));
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
    assert_eq!(
        graphic.pixels.as_ref(),
        &[255, 0, 0, 255],
        "Kitty shared memory should decode the PNG range selected by O/S"
    );
}

#[test]
fn parser_terminal_parses_kitty_cursor_movement_parameter() {
    let mut default = KittyParser::new();
    default.parse_chunk("a=T,f=32,c=2,r=2;").unwrap();
    assert!(default.should_move_cursor_after_display());

    let mut suppressed = KittyParser::new();
    suppressed.parse_chunk("a=T,f=32,c=2,r=2,C=1;").unwrap();
    assert!(!suppressed.should_move_cursor_after_display());

    let mut relative = KittyParser::new();
    relative.parse_chunk("a=p,i=1,P=1,C=0;").unwrap();
    assert!(!relative.should_move_cursor_after_display());

    let mut virtual_placement = KittyParser::new();
    virtual_placement.parse_chunk("a=T,U=1,C=0;").unwrap();
    assert!(!virtual_placement.should_move_cursor_after_display());
}

#[test]
fn parser_terminal_moves_cursor_after_kitty_display_unless_suppressed() {
    let mut default_terminal = ParserTerminal::new(10, 6);
    let default_display = format!("\x1b_Ga=T,f=32,s=1,v=1,c=2,r=2,q=1;{RED_RGBA_BASE64}\x1b\\");
    default_terminal.process(default_display.as_bytes());
    default_terminal.process(b"X");
    assert_eq!(default_terminal.active_grid().row_text(0).trim_end(), "");
    assert_eq!(default_terminal.active_grid().row_text(1).trim_end(), "");
    assert_eq!(default_terminal.active_grid().row_text(2).trim_end(), "  X");

    let mut suppressed_terminal = ParserTerminal::new(10, 6);
    let suppressed_display =
        format!("\x1b_Ga=T,f=32,s=1,v=1,c=2,r=2,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    suppressed_terminal.process(suppressed_display.as_bytes());
    suppressed_terminal.process(b"X");
    assert_eq!(
        suppressed_terminal.active_grid().row_text(0).trim_end(),
        "X"
    );
    assert_eq!(suppressed_terminal.active_grid().row_text(2).trim_end(), "");
}

#[test]
fn parser_terminal_kitty_display_respects_scroll_region_bottom() {
    let mut terminal = ParserTerminal::new(8, 6);
    let image = format!(
        "\x1b[1;1Htop\x1b[2;1Hone\x1b[3;1Htwo\x1b[4;1Hthree\x1b[5;1Hbottom\
         \x1b[2;4r\x1b[4;1H\x1b_Ga=T,f=32,s=1,v=1,c=2,r=3,q=1;{RED_RGBA_BASE64}\x1b\\"
    );

    terminal.process(image.as_bytes());

    assert_eq!(
        terminal.cursor().row,
        3,
        "Kitty display cursor advancement should stay pinned to the scroll region bottom"
    );
    assert_eq!(
        terminal.cursor().col,
        2,
        "Kitty display cursor advancement should preserve the right-edge column movement"
    );
    assert_eq!(
        terminal.active_grid().row_text(4).trim_end(),
        "bottom",
        "Kitty display advancement inside a partial scroll region must not move rows below the region"
    );
    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.display_cell_span, Some((2, 3)));
    assert_eq!(
        graphic.position,
        (0, 1),
        "partially clipped Kitty display images should stay anchored at the scroll region top"
    );
    assert_eq!(
        graphic.scroll_offset_rows, 1,
        "Kitty images clipped by partial scroll regions should track hidden top rows"
    );
}

#[test]
fn parser_terminal_chunked_kitty_display_moves_cursor_from_captured_position() {
    let mut terminal = ParserTerminal::new(10, 6);
    terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,c=2,r=2,m=1,q=1;/wAA\x1b\\");
    terminal.process(b"\x1b[5;1Htext");
    terminal.process(b"\x1b_Gm=0;/w==\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.position, (0, 0));
    assert_eq!(
        terminal.cursor().row,
        2,
        "chunked Kitty display cursor movement must use the first chunk's captured placement row"
    );
    assert_eq!(
        terminal.cursor().col,
        2,
        "chunked Kitty display cursor movement must use the captured placement column plus display width"
    );
    assert_eq!(terminal.active_grid().row_text(4).trim_end(), "text");
}

#[test]
fn parser_terminal_advances_kitty_animation_frames() {
    let mut terminal = ParserTerminal::new(80, 24);

    let frame_one = format!("\x1b_Ga=f,f=32,s=1,v=1,i=77,r=1,z=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(frame_one.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(77));
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[255, 0, 0, 255]
    );
    let first_asset_version = terminal.all_graphics()[0].asset_version;

    let frame_two = format!("\x1b_Ga=f,f=32,s=1,v=1,i=77,r=2,z=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(frame_two.as_bytes());
    terminal.process(b"\x1b_Ga=a,i=77,s=3,q=1;\x1b\\");
    thread::sleep(Duration::from_millis(5));

    let changed = terminal.update_animations();

    assert_eq!(changed, vec![77]);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.pixels.as_ref(), &[0, 255, 0, 255]);
    assert_ne!(graphic.asset_version, first_asset_version);
}

#[test]
fn parser_terminal_kitty_loading_mode_waits_for_late_frames() {
    let mut terminal = ParserTerminal::new(80, 24);
    const BLUE_RGBA_BASE64: &str = "AAD//w==";

    let frame_one = format!("\x1b_Ga=f,f=32,s=1,v=1,i=91,r=1,z=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(frame_one.as_bytes());
    let frame_two = format!("\x1b_Ga=f,f=32,s=1,v=1,i=91,r=2,z=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(frame_two.as_bytes());
    terminal.process(b"\x1b_Ga=a,i=91,s=2,q=1;\x1b\\");
    thread::sleep(Duration::from_millis(5));

    assert_eq!(terminal.update_animations(), vec![91]);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 255, 0, 255]
    );

    thread::sleep(Duration::from_millis(5));
    assert!(
        terminal.update_animations().is_empty(),
        "loading mode must wait at the last available frame instead of looping"
    );
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 255, 0, 255]
    );
    assert!(
        terminal
            .graphics_store()
            .get_animation(91)
            .expect("animation should exist")
            .loading_mode
    );

    let frame_three = format!("\x1b_Ga=f,f=32,s=1,v=1,i=91,r=3,z=1,q=1;{BLUE_RGBA_BASE64}\x1b\\");
    terminal.process(frame_three.as_bytes());
    thread::sleep(Duration::from_millis(5));

    assert_eq!(terminal.update_animations(), vec![91]);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 0, 255, 255]
    );

    terminal.process(b"\x1b_Ga=a,i=91,s=3,q=1;\x1b\\");
    thread::sleep(Duration::from_millis(5));

    assert_eq!(terminal.update_animations(), vec![91]);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[255, 0, 0, 255]
    );
    assert!(
        !terminal
            .graphics_store()
            .get_animation(91)
            .expect("animation should exist")
            .loading_mode
    );
}

#[test]
fn parser_terminal_honors_kitty_animation_num_plays_loop_count() {
    let mut terminal = ParserTerminal::new(80, 24);

    let frame_one = format!("\x1b_Ga=f,f=32,s=1,v=1,i=92,r=1,z=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(frame_one.as_bytes());
    let frame_two = format!("\x1b_Ga=f,f=32,s=1,v=1,i=92,r=2,z=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(frame_two.as_bytes());
    terminal.process(b"\x1b_Ga=a,i=92,v=2,s=3,q=1;\x1b\\");

    let animation = terminal
        .graphics_store()
        .get_animation(92)
        .expect("animation should exist");
    assert_eq!(
        animation.loop_count, 1,
        "Kitty v=2 should allow one additional loop"
    );
    assert_eq!(animation.state, AnimationState::Playing);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[255, 0, 0, 255]
    );

    force_kitty_animation_frame_elapsed(&mut terminal, 92);
    assert_eq!(terminal.update_animations(), vec![92]);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 255, 0, 255]
    );

    force_kitty_animation_frame_elapsed(&mut terminal, 92);
    assert_eq!(terminal.update_animations(), vec![92]);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[255, 0, 0, 255]
    );

    force_kitty_animation_frame_elapsed(&mut terminal, 92);
    assert_eq!(terminal.update_animations(), vec![92]);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 255, 0, 255]
    );

    force_kitty_animation_frame_elapsed(&mut terminal, 92);
    assert_eq!(terminal.update_animations(), vec![92]);
    let stopped = terminal
        .graphics_store()
        .get_animation(92)
        .expect("animation should remain after loop completion");
    assert_eq!(stopped.state, AnimationState::Stopped);
    assert_eq!(stopped.current_frame, 1);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[255, 0, 0, 255],
        "loop completion should sync the reset frame to visible placements"
    );
}

#[test]
fn parser_terminal_deletes_kitty_animation_frames() {
    let mut terminal = ParserTerminal::new(80, 24);

    let frame_one = format!("\x1b_Ga=f,f=32,s=1,v=1,i=78,r=1,z=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(frame_one.as_bytes());
    let frame_two = format!("\x1b_Ga=f,f=32,s=1,v=1,i=78,r=2,z=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(frame_two.as_bytes());
    terminal.process(b"\x1b_Ga=a,i=78,c=2,q=1;\x1b\\");

    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 255, 0, 255]
    );

    terminal.process(b"\x1b_Ga=d,d=f,i=78,r=2,q=1;\x1b\\");

    let animation = terminal
        .graphics_store()
        .get_animation(78)
        .expect("animation should remain after deleting one frame");
    assert_eq!(animation.current_frame, 1);
    assert!(animation.get_frame(2).is_none());
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[255, 0, 0, 255]
    );

    terminal.process(b"\x1b_Ga=d,d=F,i=78,q=1;\x1b\\");

    assert_eq!(terminal.graphics_count(), 0);
    assert!(terminal.graphics_store().get_animation(78).is_none());
}

#[test]
fn parser_terminal_reports_invalid_kitty_animation_control_frame() {
    let mut terminal = ParserTerminal::new(80, 24);

    let frame_one = format!("\x1b_Ga=f,f=32,s=1,v=1,i=79,r=1,z=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(frame_one.as_bytes());
    let frame_two = format!("\x1b_Ga=f,f=32,s=1,v=1,i=79,r=2,z=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(frame_two.as_bytes());
    terminal.process(b"\x1b_Ga=a,i=79,c=2,q=1;\x1b\\");
    assert!(terminal.drain_responses().is_empty());
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 255, 0, 255]
    );

    terminal.process(b"\x1b_Ga=a,i=79,c=99,q=1;\x1b\\");

    let response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert_eq!(
        response,
        "\x1b_Gi=79;EINVAL: Kitty protocol error: Animation frame 99 not found\x1b\\"
    );
    let animation = terminal
        .graphics_store()
        .get_animation(79)
        .expect("animation should remain after rejected control");
    assert_eq!(animation.current_frame, 2);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 255, 0, 255]
    );
}

#[test]
fn parser_terminal_composes_kitty_animation_frame_rectangles() {
    let mut terminal = ParserTerminal::new(80, 24);
    const SOURCE_RGBA_BASE64: &str = "/wAA/wD/AP8AAP////8A/w==";
    const BLACK_RGBA_BASE64: &str = "AAAA/wAAAP8AAAD/AAAA/w==";

    let frame_one = format!("\x1b_Ga=f,f=32,s=2,v=2,i=88,r=1,q=1;{SOURCE_RGBA_BASE64}\x1b\\");
    terminal.process(frame_one.as_bytes());
    let frame_two = format!("\x1b_Ga=f,f=32,s=2,v=2,i=88,r=2,q=1;{BLACK_RGBA_BASE64}\x1b\\");
    terminal.process(frame_two.as_bytes());
    terminal.process(b"\x1b_Ga=a,i=88,c=2,q=1;\x1b\\");

    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref().as_slice(),
        &[0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255,]
    );

    terminal.process(b"\x1b_Ga=c,i=88,r=1,c=2,x=1,y=0,w=1,h=1,X=0,Y=1,C=1,q=1;\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.kitty_image_id, Some(88));
    assert_eq!(
        graphic.pixels.as_ref().as_slice(),
        &[
            0, 0, 0, 255, 0, 0, 0, 255, // first row remains black
            0, 255, 0, 255, // composed green source pixel
            0, 0, 0, 255,
        ]
    );
}

#[test]
fn parser_terminal_loads_kitty_animation_frame_over_base_frame() {
    let mut terminal = ParserTerminal::new(80, 24);
    const BLACK_RGBA_BASE64: &str = "AAAA/wAAAP8AAAD/AAAA/w==";

    let frame_one = format!("\x1b_Ga=f,f=32,s=2,v=2,i=89,r=1,q=1;{BLACK_RGBA_BASE64}\x1b\\");
    terminal.process(frame_one.as_bytes());
    let frame_two =
        format!("\x1b_Ga=f,f=32,s=1,v=1,i=89,r=2,c=1,x=1,X=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(frame_two.as_bytes());
    terminal.process(b"\x1b_Ga=a,i=89,c=2,q=1;\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.kitty_image_id, Some(89));
    assert_eq!(
        graphic.pixels.as_ref().as_slice(),
        &[
            0, 0, 0, 255, 0, 255, 0, 255, // frame data composed over the base frame
            0, 0, 0, 255, 0, 0, 0, 255,
        ]
    );
}

#[test]
fn parser_terminal_handles_tmux_wrapped_kitty_graphics() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let inner = format!("\x1b_Ga=T,f=32,s=1,v=1,i=11;{RED_RGBA_BASE64}\x1b\\");
    let mut wrapped = b"\x1bPtmux;".to_vec();
    for byte in inner.as_bytes() {
        if *byte == b'\x1b' {
            wrapped.push(b'\x1b');
        }
        wrapped.push(*byte);
    }
    wrapped.extend_from_slice(b"\x1b\\");

    terminal.process(&wrapped);

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.kitty_image_id, Some(11));
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b_Gi=11;OK\x1b\\"
    );
}

#[test]
fn parser_terminal_handles_tmux_wrapped_sixel_graphics() {
    let mut terminal = ParserTerminal::new(80, 24);

    let inner = "\x1bPq#1;2;100;0;0@\x1b\\";
    let mut wrapped = b"\x1bPtmux;".to_vec();
    for byte in inner.as_bytes() {
        if *byte == b'\x1b' {
            wrapped.push(b'\x1b');
        }
        wrapped.push(*byte);
    }
    wrapped.extend_from_slice(b"\x1b\\");

    terminal.process(&wrapped);

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(&graphic.pixels[0..4], &[255, 0, 0, 255]);
}

#[test]
fn parser_terminal_streams_split_tmux_wrapped_sixel_before_outer_terminator() {
    let mut terminal = ParserTerminal::new(80, 24);

    let inner = "\x1bPq#1;2;100;0;0@\x1b\\";
    let mut wrapped = b"\x1bPtmux;".to_vec();
    for byte in inner.as_bytes() {
        if *byte == b'\x1b' {
            wrapped.push(b'\x1b');
        }
        wrapped.push(*byte);
    }
    wrapped.extend_from_slice(b"\x1b\\");
    let (head, tail) = wrapped.split_at(wrapped.len() - 2);

    terminal.process(head);

    // The doubled inner ST is complete, so the decoded Sixel reaches its
    // parser without waiting for the outer tmux wrapper's ST.
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(tail);

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(&graphic.pixels[0..4], &[255, 0, 0, 255]);
}

#[test]
fn parser_terminal_handles_tmux_wrapped_iterm_graphics() {
    let mut terminal = ParserTerminal::new(80, 24);

    let inner = format!("\x1b]1337;File=inline=1:{}\x1b\\", RED_PIXEL_PNG_BASE64);
    let mut wrapped = b"\x1bPtmux;".to_vec();
    for byte in inner.as_bytes() {
        if *byte == b'\x1b' {
            wrapped.push(b'\x1b');
        }
        wrapped.push(*byte);
    }
    wrapped.extend_from_slice(b"\x1b\\");

    terminal.process(&wrapped);

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn parser_terminal_replaces_and_deletes_kitty_placements() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let first = format!("\x1b_Ga=T,f=32,s=1,v=1,i=31,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    terminal.process(b"\x1b[10;10H");
    let second = format!("\x1b_Ga=T,f=32,s=1,v=1,i=31,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(second.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].kitty_placement_id, Some(0));
    assert_eq!(terminal.all_graphics()[0].position, (9, 9));

    let p1 = format!("\x1b_Ga=T,f=32,s=1,v=1,i=40,p=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    let p2 = format!("\x1b_Ga=T,f=32,s=1,v=1,i=40,p=2,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(p1.as_bytes());
    terminal.process(p2.as_bytes());
    assert_eq!(terminal.graphics_count(), 3);

    terminal.process(b"\x1b_Ga=d,d=i,i=40,p=1,q=1;\x1b\\");
    terminal.settle_graphics_transactions();
    terminal.settle_graphics_transactions();
    assert_eq!(terminal.graphics_count(), 2);
    assert!(
        terminal
            .all_graphics()
            .iter()
            .all(|graphic| graphic.kitty_placement_id != Some(1))
    );

    terminal.process(b"\x1b_Ga=d,d=i,i=40,q=1;\x1b\\");
    terminal.settle_graphics_transactions();
    terminal.settle_graphics_transactions();
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b_Ga=d,q=1;\x1b\\");
    terminal.settle_graphics_transactions();
    terminal.settle_graphics_transactions();
    assert_eq!(terminal.graphics_count(), 0);
}

#[test]
fn parser_terminal_kitty_image_number_delete_targets_newest_image() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(
        format!("\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,I=13,p=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\")
            .as_bytes(),
    );
    terminal.process(
        format!("\x1b[1;4H\x1b_Ga=T,f=32,s=1,v=1,I=13,p=2,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\")
            .as_bytes(),
    );

    assert_eq!(terminal.graphics_count(), 2);
    let first_id = terminal
        .all_graphics()
        .iter()
        .find(|graphic| graphic.kitty_placement_id == Some(1))
        .and_then(|graphic| graphic.kitty_image_id)
        .expect("expected first image-number id");
    let second_id = terminal
        .all_graphics()
        .iter()
        .find(|graphic| graphic.kitty_placement_id == Some(2))
        .and_then(|graphic| graphic.kitty_image_id)
        .expect("expected second image-number id");
    assert_ne!(
        first_id, second_id,
        "I= image numbers must allocate a new id for each new image"
    );

    terminal.process(b"\x1b_Ga=d,d=n,I=13,p=2,q=1;\x1b\\");
    terminal.settle_graphics_transactions();
    terminal.settle_graphics_transactions();

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(first_id));

    terminal.process(b"\x1b_Ga=d,d=N,I=13,q=1;\x1b\\");
    terminal.settle_graphics_transactions();
    terminal.settle_graphics_transactions();
    terminal.process(b"\x1b[2;1H\x1b_Ga=p,I=13,p=3,C=1,q=1;\x1b\\");

    assert!(
        terminal.all_graphics().iter().any(|graphic| {
            graphic.kitty_image_id == Some(first_id) && graphic.kitty_placement_id == Some(3)
        }),
        "after releasing the newest image number target, I=13 should resolve to the previous live image id"
    );
    assert!(
        terminal
            .all_graphics()
            .iter()
            .all(|graphic| graphic.kitty_image_id != Some(second_id)),
        "uppercase N delete should release the latest image-number id"
    );
}

#[test]
fn parser_terminal_kitty_image_number_response_reports_allocated_id() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(
        format!("\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,I=21,p=1,C=1;{RED_RGBA_BASE64}\x1b\\").as_bytes(),
    );
    let first_id = terminal
        .all_graphics()
        .first()
        .and_then(|graphic| graphic.kitty_image_id)
        .expect("expected terminal-allocated image id");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        format!("\x1b_Gi={first_id},I=21;OK\x1b\\")
    );

    terminal.process(format!("\x1b_Ga=t,f=32,s=1,v=1,I=22;{GREEN_RGBA_BASE64}\x1b\\").as_bytes());
    let transmit_response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert!(
        transmit_response.starts_with("\x1b_Gi=") && transmit_response.ends_with(",I=22;OK\x1b\\"),
        "terminal-allocated transmit-only response should include the allocated image id and image number: {transmit_response:?}"
    );
    let transmit_id = transmit_response
        .strip_prefix("\x1b_Gi=")
        .and_then(|rest| rest.strip_suffix(",I=22;OK\x1b\\"))
        .and_then(|value| value.parse::<u32>().ok())
        .expect("expected numeric allocated transmit-only image id");
    terminal.process(b"\x1b[2;1H\x1b_Ga=p,I=22,p=1,C=1,q=1;\x1b\\");
    assert!(
        terminal.all_graphics().iter().any(|graphic| {
            graphic.kitty_image_id == Some(transmit_id) && graphic.kitty_placement_id == Some(1)
        }),
        "I=22 should remain reusable by image number after transmit-only allocation"
    );

    terminal.process(
        format!("\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,I=23,p=1,C=1;{RED_RGBA_BASE64}\x1b\\").as_bytes(),
    );
    let create_response = String::from_utf8(terminal.drain_responses()).unwrap();
    let delete_target_id = create_response
        .strip_prefix("\x1b_Gi=")
        .and_then(|rest| rest.strip_suffix(",I=23;OK\x1b\\"))
        .and_then(|value| value.parse::<u32>().ok())
        .expect("expected image number delete target id");
    terminal.process(b"\x1b_Ga=d,d=N,I=23;\x1b\\");
    terminal.settle_graphics_transactions();
    terminal.settle_graphics_transactions();
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        format!("\x1b_Gi={delete_target_id},I=23;OK\x1b\\"),
        "uppercase image-number delete should report the resolved target id even after releasing it"
    );
}

#[test]
fn parser_terminal_kitty_delete_image_id_range_removes_scrollback_and_releases_data() {
    let mut terminal = ParserTerminal::with_scrollback(8, 4, 20);

    terminal.process(
        format!(
            "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=700,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
        )
        .as_bytes(),
    );
    terminal.process(
        format!(
            "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=701,p=1,c=1,r=1,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
        )
        .as_bytes(),
    );
    terminal.process(b"\x1b[4;1H\n\n");
    terminal.process(
        format!(
            "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=704,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
        )
        .as_bytes(),
    );
    terminal
        .process(format!("\x1b_Ga=t,f=32,s=1,v=1,i=703,q=1;{GREEN_RGBA_BASE64}\x1b\\").as_bytes());

    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.kitty_image_id == Some(704)),
        "range setup should leave the out-of-range image visible"
    );
    assert!(
        terminal
            .all_scrollback_graphics()
            .iter()
            .any(|graphic| graphic.kitty_image_id == Some(701)),
        "range setup should retain one in-range placement in scrollback"
    );

    terminal.process(b"\x1b_Ga=d,d=R,x=700,y=703,q=1;\x1b\\");
    terminal.settle_graphics_transactions();
    terminal.settle_graphics_transactions();

    assert!(
        terminal
            .all_graphics()
            .iter()
            .all(|graphic| !matches!(graphic.kitty_image_id, Some(700 | 701 | 703))),
        "Kitty d=R range should remove in-range active placements"
    );
    assert!(
        terminal
            .all_scrollback_graphics()
            .iter()
            .all(|graphic| !matches!(graphic.kitty_image_id, Some(700 | 701 | 703))),
        "Kitty d=R range should remove in-range scrollback placements"
    );
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.kitty_image_id == Some(704)),
        "Kitty d=R range should not remove out-of-range placements"
    );

    terminal.process(b"\x1b[1;1H\x1b_Ga=p,i=700,p=2,C=1,q=1;\x1b\\");
    terminal.process(b"\x1b[2;1H\x1b_Ga=p,i=701,p=2,C=1,q=1;\x1b\\");
    terminal.process(b"\x1b[2;3H\x1b_Ga=p,i=703,p=2,C=1,q=1;\x1b\\");
    terminal.process(b"\x1b[3;3H\x1b_Ga=p,i=704,p=2,C=1,q=1;\x1b\\");

    assert!(
        terminal
            .all_graphics()
            .iter()
            .all(|graphic| !matches!(graphic.kitty_image_id, Some(700 | 701 | 703))),
        "uppercase d=R should release in-range image data after deletion"
    );
    assert!(
        terminal.all_graphics().iter().any(|graphic| {
            graphic.kitty_image_id == Some(704) && graphic.kitty_placement_id == Some(2)
        }),
        "out-of-range image data should remain reusable"
    );
}

#[test]
fn parser_terminal_kitty_delete_by_id_removes_scrollback_placement_and_releases_data() {
    let mut terminal = ParserTerminal::with_scrollback(8, 4, 20);
    let kitty = format!(
        "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=762,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );

    terminal.process(kitty.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(762));
    assert_eq!(terminal.all_graphics()[0].kitty_placement_id, Some(1));

    terminal.process(b"\x1b[4;1H\n\n\n\n");
    assert_eq!(
        terminal.graphics_count(),
        0,
        "Kitty placement should leave the active viewport after scrolling off"
    );
    assert_eq!(
        terminal.scrollback_graphics_count(),
        1,
        "Kitty placement should be retained in graphics scrollback before deletion"
    );
    assert_eq!(
        terminal.all_scrollback_graphics()[0].kitty_image_id,
        Some(762)
    );

    terminal.process(b"\x1b_Ga=d,d=I,i=762,p=1,q=1;\x1b\\");

    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "Kitty delete by image/placement id should remove matching scrollback placements"
    );

    terminal.process(b"\x1b[1;1H\x1b_Ga=p,i=762,p=2,C=1,q=1;\x1b\\");
    assert_eq!(
        terminal.graphics_count(),
        0,
        "uppercase Kitty delete should release image data once the scrollback placement is removed"
    );
}

#[test]
fn parser_terminal_kitty_delete_all_removes_scrollback_placements_and_releases_data() {
    let mut terminal = ParserTerminal::with_scrollback(8, 4, 20);
    let kitty = format!(
        "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=763,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );

    terminal.process(kitty.as_bytes());
    terminal.process(b"\x1b[4;1H\n\n\n\n");

    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(
        terminal.scrollback_graphics_count(),
        1,
        "Kitty placement should be retained in graphics scrollback before delete-all"
    );

    terminal.process(b"\x1b_Ga=d,d=A,q=1;\x1b\\");

    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "Kitty delete-all should remove matching scrollback placements"
    );

    terminal.process(b"\x1b[1;1H\x1b_Ga=p,i=763,p=2,C=1,q=1;\x1b\\");
    assert_eq!(
        terminal.graphics_count(),
        0,
        "uppercase Kitty delete-all should release image data once scrollback placements are removed"
    );
}

#[test]
fn parser_terminal_kitty_relative_placement_tracks_parent_replacement_and_delete() {
    let mut terminal = ParserTerminal::new(80, 24);

    let parent =
        format!("\x1b[5;6H\x1b_Ga=T,f=32,s=1,v=1,i=70,p=4,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(parent.as_bytes());
    let child = format!(
        "\x1b_Ga=T,f=32,s=1,v=1,i=71,p=8,P=70,Q=4,H=3,V=2,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );
    terminal.process(child.as_bytes());
    terminal.process(b"\x1b_Ga=p,i=72,p=9,U=1,P=70,Q=4,H=2,V=1,C=1,q=1;\x1b\\");

    assert_eq!(terminal.graphics_count(), 2);
    let child = terminal
        .all_graphics()
        .iter()
        .find(|graphic| graphic.kitty_image_id == Some(71))
        .expect("expected relative child placement");
    assert_eq!(
        child.position,
        (8, 6),
        "relative Kitty placement should use parent row/col plus H/V cell offsets"
    );
    let virtual_child = terminal
        .graphics_store()
        .get_virtual_placement(72, 9)
        .expect("expected relative virtual child placement");
    assert_eq!(
        virtual_child.position,
        (7, 5),
        "relative Kitty virtual placement should use parent row/col plus H/V cell offsets"
    );

    let moved_parent =
        format!("\x1b[10;2H\x1b_Ga=T,f=32,s=1,v=1,i=70,p=4,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(moved_parent.as_bytes());

    assert_eq!(terminal.graphics_count(), 2);
    let child = terminal
        .all_graphics()
        .iter()
        .find(|graphic| graphic.kitty_image_id == Some(71))
        .expect("expected relative child after parent replacement");
    assert_eq!(
        child.position,
        (4, 11),
        "relative Kitty child should follow parent placement replacements"
    );
    let virtual_child = terminal
        .graphics_store()
        .get_virtual_placement(72, 9)
        .expect("expected relative virtual child after parent replacement");
    assert_eq!(
        virtual_child.position,
        (3, 10),
        "relative Kitty virtual child should follow parent placement replacements"
    );

    terminal.process(b"\x1b_Ga=d,d=i,i=70,p=4,q=1;\x1b\\");
    terminal.settle_graphics_transactions();
    terminal.settle_graphics_transactions();

    assert_eq!(
        terminal.graphics_count(),
        0,
        "deleting a Kitty parent placement should recursively delete relative children"
    );
    assert!(
        terminal
            .graphics_store()
            .get_virtual_placement(72, 9)
            .is_none(),
        "deleting a Kitty parent placement should recursively delete relative virtual children"
    );
}

#[test]
fn parser_terminal_kitty_delete_aborts_incomplete_chunked_transfer() {
    let mut terminal = ParserTerminal::new(80, 24);

    let visible = format!("\x1b_Ga=T,f=32,s=1,v=1,i=91,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(visible.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=92,m=1,q=1;/wAA\x1b\\");
    assert!(terminal.kitty_graphics_transfer_in_progress());

    terminal.process(b"\x1b_Gd=i,i=91,a=d,q=1;\x1b\\");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "Kitty delete commands must abort any incomplete chunked transfer and still apply"
    );
    assert!(
        !terminal.kitty_graphics_transfer_in_progress(),
        "delete must clear the incomplete Kitty transfer state"
    );

    terminal.process(b"\x1b_Gm=0;/w==\x1b\\");
    assert_eq!(
        terminal.graphics_count(),
        0,
        "a stray final chunk from the aborted transfer must not create a graphic"
    );
}

#[test]
fn parser_terminal_kitty_bel_terminator_delete_aborts_incomplete_chunked_transfer() {
    let mut terminal = ParserTerminal::new(80, 24);

    let visible = format!("\x1b_Ga=T,f=32,s=1,v=1,i=93,q=1;{RED_RGBA_BASE64}\x07");
    terminal.process(visible.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=94,m=1,q=1;/wAA\x07");
    assert!(terminal.kitty_graphics_transfer_in_progress());

    terminal.process(b"\x1b_Gd=i,i=93,a=d,q=1;\x07");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "BEL-terminated Kitty delete commands must abort any incomplete chunked transfer and still apply"
    );
    assert!(
        !terminal.kitty_graphics_transfer_in_progress(),
        "BEL-terminated delete must clear the incomplete Kitty transfer state"
    );

    terminal.process(b"\x1b_Gm=0;/w==\x07");
    assert_eq!(
        terminal.graphics_count(),
        0,
        "the final BEL-terminated chunk of the aborted transfer must not create a graphic"
    );
}

#[test]
fn parser_terminal_kitty_delete_all_preserves_non_kitty_graphics() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let iterm = format!("\x1b]1337;File=inline=1:{}\x1b\\", RED_PIXEL_PNG_BASE64);
    terminal.process(iterm.as_bytes());
    let kitty = format!("\x1b_Ga=T,f=32,s=1,v=1,i=41,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(kitty.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b_Ga=d,d=a,q=1;\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
}

#[test]
fn parser_terminal_kitty_delete_by_z_index_clears_pending_clear_hold() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let kitty = format!("\x1b_Ga=T,f=32,s=1,v=1,i=42,z=7,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(kitty.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b[2J\x1b[3J\x1b[H");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 1);

    terminal.process(b"\x1b_Ga=d,d=z,z=7,q=1;\x1b\\");

    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 0);
}

#[test]
fn parser_terminal_kitty_cell_delete_reuses_render_id_for_immediate_replacement() {
    let mut terminal = ParserTerminal::new(80, 24);

    let first =
        format!("\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=510,p=9,z=7,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;

    terminal.process(b"\x1b_Ga=d,d=q,x=1,y=1,z=7,q=2;\x1b\\");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "cell+z deletes should retain a tombstone for an immediate replacement"
    );

    let replacement =
        format!("\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=511,p=9,z=7,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(replacement.as_bytes());

    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 1);
    let replacement = &terminal.all_graphics()[0];
    assert_eq!(replacement.id, first_graphic_id);
    assert_eq!(replacement.kitty_image_id, Some(511));
    assert_eq!(replacement.kitty_placement_id, Some(9));
    assert_eq!(replacement.position, (0, 0));
    assert_eq!(replacement.placement.z_index, 7);
}

#[test]
fn parser_terminal_kitty_delete_at_cursor_hits_display_span() {
    let mut terminal = ParserTerminal::new(80, 24);

    let graphic = format!(
        "\x1b[3;4H\x1b_Ga=T,f=32,s=1,v=1,i=520,p=1,c=3,r=2,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    terminal.process(graphic.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].position, (3, 2));

    terminal.process(b"\x1b[4;5H\x1b_Ga=d,d=c,q=1;\x1b\\");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "Kitty d=c should delete placements that intersect the cursor cell, not only placements that start at the cursor"
    );
}

#[test]
fn parser_terminal_kitty_delete_by_column_and_row_hits_display_span() {
    let mut terminal = ParserTerminal::new(80, 24);

    let first = format!(
        "\x1b[3;4H\x1b_Ga=T,f=32,s=1,v=1,i=521,p=1,c=3,r=2,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    let second = format!(
        "\x1b[8;10H\x1b_Ga=T,f=32,s=1,v=1,i=522,p=1,c=2,r=2,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );
    terminal.process(first.as_bytes());
    terminal.process(second.as_bytes());

    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b_Ga=d,d=x,x=5,q=1;\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(
        terminal.all_graphics()[0].kitty_image_id,
        Some(522),
        "Kitty d=x should delete only placements intersecting the requested column"
    );

    terminal.process(b"\x1b_Ga=d,d=y,y=9,q=1;\x1b\\");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "Kitty d=y should delete placements intersecting the requested row"
    );
}

#[test]
fn parser_terminal_keeps_kitty_replacement_visible_during_chunked_transfer() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let first = format!("\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[255, 0, 0, 255]
    );

    terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);
    assert_eq!(terminal.graphics_count(), 0);
    terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=2,m=1;AP8A\x1b\\");

    assert!(terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"\x1b_Gm=0;/w==\x1b\\");

    assert!(!terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(49374));
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 255, 0, 255]
    );
}

#[test]
fn parser_terminal_keeps_kitty_replacement_visible_when_image_id_changes() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let first = format!("\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(49374));

    terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);
    assert_eq!(terminal.graphics_count(), 0);
    terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49375,q=2,m=1;AP8A\x1b\\");

    assert!(terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"\x1b_Gm=0;/w==\x1b\\");

    assert!(!terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, first_graphic_id);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(49375));
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 255, 0, 255]
    );
}

#[test]
fn parser_terminal_keeps_kitty_replacement_visible_when_text_interleaves() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let first = format!("\x1b_Ga=T,f=32,s=1,v=1,i=49374,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;

    terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
    terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49375,C=1,q=2,m=1;AP8A\x1b\\");
    assert!(terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);
    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"startup log line");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "visible text interleaved with a split Kitty replacement must not remove the old graphic"
    );

    terminal.process(b"\x1b_Gm=0;/w==\x1b\\");

    assert!(!terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, first_graphic_id);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(49375));
}

#[test]
fn parser_terminal_keeps_transmit_then_put_replacement_visible_when_text_interleaves() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let first = format!("\x1b_Ga=T,f=32,s=1,v=1,i=300,p=3,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;

    terminal.process(b"\x1b_Ga=d,d=I,i=300,q=2;\x1b\\");
    terminal.process(b"\x1b_Ga=t,f=32,s=1,v=1,i=300,q=2,m=1;AP8A\x1b\\");
    assert!(terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);
    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"startup log line");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "visible text interleaved with a split Kitty transmit must not remove the old graphic"
    );

    terminal.process(b"\x1b_Gm=0;/w==\x1b\\");
    assert!(!terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);
    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"\x1b[1;1H\x1b_Ga=p,i=300,p=3,q=2;\x1b\\");

    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, first_graphic_id);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(300));
    assert_eq!(terminal.all_graphics()[0].kitty_placement_id, Some(3));
}

#[test]
fn parser_terminal_keeps_cross_image_transmit_then_put_visible_when_text_interleaves() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let first = format!("\x1b_Ga=T,f=32,s=1,v=1,i=300,p=3,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;

    terminal.process(b"\x1b_Ga=d,d=I,i=300,q=2;\x1b\\");
    terminal.process(b"\x1b_Ga=t,f=32,s=1,v=1,i=301,q=2,m=1;AP8A\x1b\\");
    assert!(terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);
    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"startup log line");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "visible text interleaved with a split Kitty transmit must keep the old cross-image replacement visible"
    );

    terminal.process(b"\x1b_Gm=0;/w==\x1b\\");
    assert!(!terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);
    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"\x1b[1;1H\x1b_Ga=p,i=301,p=3,q=2;\x1b\\");

    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, first_graphic_id);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(301));
    assert_eq!(terminal.all_graphics()[0].kitty_placement_id, Some(3));
}

#[test]
fn parser_terminal_commits_unrelated_delete_during_kitty_replacement_transfer() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let unrelated = format!("\x1b_Ga=T,f=32,s=1,v=1,i=100,p=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(unrelated.as_bytes());
    let old = format!("\x1b_Ga=T,f=32,s=1,v=1,i=200,p=2,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(old.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);
    let old_replacement_graphic_id = terminal
        .all_graphics()
        .iter()
        .find(|graphic| graphic.kitty_image_id == Some(200))
        .expect("expected old replacement graphic")
        .id;

    terminal.process(b"\x1b_Ga=d,d=I,i=100,q=2;\x1b\\");
    terminal.process(b"\x1b_Ga=d,d=I,i=200,q=2;\x1b\\");
    terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=201,p=2,C=1,q=2,m=1;AP8A\x1b\\");
    assert!(terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 2);
    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"startup log line");

    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"\x1b_Gm=0;/w==\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let replacement = &terminal.all_graphics()[0];
    assert_eq!(replacement.id, old_replacement_graphic_id);
    assert_eq!(replacement.kitty_image_id, Some(201));
    assert_eq!(replacement.kitty_placement_id, Some(2));
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
}

#[test]
fn parser_terminal_commits_unrelated_default_placement_delete_during_replacement_transfer() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let unrelated = format!("\x1b[2;2H\x1b_Ga=T,f=32,s=1,v=1,i=100,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(unrelated.as_bytes());
    let old = format!("\x1b[10;10H\x1b_Ga=T,f=32,s=1,v=1,i=200,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(old.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);
    let old_replacement_graphic_id = terminal
        .all_graphics()
        .iter()
        .find(|graphic| graphic.kitty_image_id == Some(200))
        .expect("expected old replacement graphic")
        .id;

    terminal.process(b"\x1b_Ga=d,d=I,i=100,q=2;\x1b\\");
    terminal.process(b"\x1b_Ga=d,d=I,i=200,q=2;\x1b\\");
    terminal.process(b"\x1b[10;10H\x1b_Ga=T,f=32,s=1,v=1,i=201,q=2,m=1;AP8A\x1b\\");
    assert!(terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 2);
    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"startup log line");

    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(b"\x1b_Gm=0;/w==\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let replacement = &terminal.all_graphics()[0];
    assert_eq!(replacement.id, old_replacement_graphic_id);
    assert_eq!(replacement.kitty_image_id, Some(201));
    assert_eq!(replacement.kitty_placement_id, Some(0));
    assert_eq!(replacement.position, (9, 9));
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
}

#[test]
fn parser_terminal_keeps_codex_pet_visible_across_double_delete_and_split_png() {
    let mut terminal = ParserTerminal::new(226, 43);
    let first = format!(
        "\x1b7\x1b[25;205H\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374;{RED_PIXEL_PNG_BASE64}\x1b\\\x1b8"
    );
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(49374));

    terminal.process(b"\x1b[?2026h\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\\x1b[?2026l");
    terminal.process(b"\x1b[?2026h\x1b_Ga=d,d=I,i=49375,q=2;\x1b\\\x1b7\x1b[25;205H");
    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);
    assert_eq!(terminal.graphics_count(), 0);

    let chunk_size = 16;
    let chunks = RED_PIXEL_PNG_BASE64
        .as_bytes()
        .chunks(chunk_size)
        .collect::<Vec<_>>();
    for (index, chunk) in chunks.iter().enumerate() {
        let payload = std::str::from_utf8(chunk).unwrap();
        let sequence = if index == 0 {
            format!("\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49375,m=1;{payload}\x1b\\")
        } else if index + 1 == chunks.len() {
            format!("\x1b_Gm=0;{payload}\x1b\\\x1b8\x1b[?2026l")
        } else {
            format!("\x1b_Gm=1;{payload}\x1b\\")
        };
        terminal.process(sequence.as_bytes());

        if index + 1 < chunks.len() {
            assert!(terminal.synchronized_updates());
            assert_eq!(terminal.deferred_kitty_delete_count(), 1);
            assert_eq!(terminal.graphics_count(), 0);
        } else {
            assert_eq!(terminal.graphics_count(), 1);
            assert_eq!(terminal.all_graphics()[0].id, first_graphic_id);
        }
    }

    assert!(!terminal.synchronized_updates());
    assert!(!terminal.kitty_graphics_transfer_in_progress());
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, first_graphic_id);
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(49375));
    assert_eq!(terminal.all_graphics()[0].kitty_placement_id, Some(0));
    assert_eq!(terminal.all_graphics()[0].position, (204, 24));
    assert_eq!(terminal.all_graphics()[0].placement.columns, Some(9));
    assert_eq!(terminal.all_graphics()[0].placement.rows, Some(5));
}

#[test]
fn parser_terminal_clears_codex_pet_after_split_replacement_final_delete() {
    let mut terminal = ParserTerminal::new(226, 43);
    let first = format!(
        "\x1b7\x1b[25;205H\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374;{RED_PIXEL_PNG_BASE64}\x1b\\\x1b8"
    );
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b[?2026h\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\\x1b7\x1b[25;205H");
    let chunks = RED_PIXEL_PNG_BASE64
        .as_bytes()
        .chunks(16)
        .collect::<Vec<_>>();
    for (index, chunk) in chunks.iter().enumerate() {
        let payload = std::str::from_utf8(chunk).unwrap();
        let sequence = if index == 0 {
            format!("\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374,m=1;{payload}\x1b\\")
        } else if index + 1 == chunks.len() {
            format!("\x1b_Gm=0;{payload}\x1b\\\x1b8\x1b[?2026l")
        } else {
            format!("\x1b_Gm=1;{payload}\x1b\\")
        };
        terminal.process(sequence.as_bytes());
    }
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);

    terminal.process(b"\x1b[?2026h\x1b[20;1H\x1b[J\x1b[22;1HShutting down...\x1b[?2026l");
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 0);
}

#[test]
fn parser_terminal_reuses_pet_render_id_across_adjacent_sync_replacement() {
    let mut terminal = ParserTerminal::new(226, 43);
    let first = format!(
        "\x1b7\x1b[19;218H\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374;{RED_PIXEL_PNG_BASE64}\x1b\\\x1b8"
    );
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;

    let chunks = RED_PIXEL_PNG_BASE64
        .as_bytes()
        .chunks(16)
        .collect::<Vec<_>>();
    let first_payload = std::str::from_utf8(chunks[0]).unwrap();
    let adjacent_sync_start = format!(
        "\x1b[?2026h\x1b[20;2H\x1b[K\x1b[?2026l\x1b[?2026h\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\\x1b7\x1b[19;218H\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374,m=1;{first_payload}\x1b\\"
    );
    terminal.process(adjacent_sync_start.as_bytes());
    assert!(terminal.synchronized_updates());

    for (index, chunk) in chunks.iter().enumerate().skip(1) {
        let payload = std::str::from_utf8(chunk).unwrap();
        let sequence = if index + 1 == chunks.len() {
            format!("\x1b_Gm=0;{payload}\x1b\\\x1b8\x1b[?2026l")
        } else {
            format!("\x1b_Gm=1;{payload}\x1b\\")
        };
        terminal.process(sequence.as_bytes());
    }

    assert!(!terminal.synchronized_updates());
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(
        terminal.all_graphics()[0].id,
        first_graphic_id,
        "adjacent synchronized updates must not drop the Kitty replacement tombstone"
    );
}

#[test]
fn parser_terminal_reuses_pet_render_id_across_clear_quiet_delete_and_moved_redraw() {
    let mut terminal = ParserTerminal::new(226, 43);
    let first = format!(
        "\x1b7\x1b[38;218H\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374;{RED_PIXEL_PNG_BASE64}\x1b\\\x1b8"
    );
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;
    assert_eq!(terminal.all_graphics()[0].position, (217, 37));

    terminal.process(b"\x1b[r\x1b[0m\x1b[H\x1b[2J\x1b[3J\x1b[H");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 1);

    terminal.process(b"\x1b[?2026h\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\\x1b7\x1b[21;218H");
    let chunk_size = 16;
    let chunks = RED_PIXEL_PNG_BASE64
        .as_bytes()
        .chunks(chunk_size)
        .collect::<Vec<_>>();
    for (index, chunk) in chunks.iter().enumerate() {
        let payload = std::str::from_utf8(chunk).unwrap();
        let sequence = if index == 0 {
            format!("\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374,m=1;{payload}\x1b\\")
        } else if index + 1 == chunks.len() {
            format!("\x1b_Gm=0;{payload}\x1b\\\x1b8\x1b[?2026l")
        } else {
            format!("\x1b_Gm=1;{payload}\x1b\\")
        };
        terminal.process(sequence.as_bytes());
    }

    assert_eq!(terminal.graphics_count(), 1);
    let replacement = &terminal.all_graphics()[0];
    assert_eq!(
        replacement.id, first_graphic_id,
        "pet redraw after clear and quiet delete should keep the same render identity"
    );
    assert_eq!(replacement.kitty_image_id, Some(49374));
    assert_eq!(replacement.kitty_placement_id, Some(0));
    assert_eq!(replacement.position, (217, 20));
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 0);
}

#[test]
fn parser_terminal_scopes_kitty_clear_screen_to_alternate_screen() {
    let mut terminal = ParserTerminal::new(80, 24);
    let primary = format!("\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=10,p=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(primary.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let primary_graphic_id = terminal.all_graphics()[0].id;
    assert!(!terminal.all_graphics()[0].alternate_screen);

    terminal.use_alt_screen();
    let alternate =
        format!("\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=20,p=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(alternate.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.alternate_screen)
    );

    terminal.process(b"\x1b[2J");

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, primary_graphic_id);
    assert!(!terminal.all_graphics()[0].alternate_screen);
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 1);
    assert!(terminal.pending_cleared_kitty_graphics()[0].alternate_screen);

    terminal.use_primary_screen();

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, primary_graphic_id);
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 0);
}

#[test]
fn parser_terminal_keeps_primary_kitty_redraw_identity_after_alt_screen_teardown() {
    let mut terminal = ParserTerminal::new(80, 24);
    let primary = format!("\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=10,p=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(primary.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let primary_graphic_id = terminal.all_graphics()[0].id;

    terminal.process(b"\x1b[2J");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 1);
    assert!(!terminal.pending_cleared_kitty_graphics()[0].alternate_screen);

    terminal.use_alt_screen();
    let alternate =
        format!("\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=20,p=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(alternate.as_bytes());
    terminal.process(b"\x1b[2J");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 2);

    terminal.use_primary_screen();
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 1);
    assert!(!terminal.pending_cleared_kitty_graphics()[0].alternate_screen);

    terminal.process(primary.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(
        terminal.all_graphics()[0].id,
        primary_graphic_id,
        "primary Kitty redraw should keep render identity after alt screen teardown"
    );
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 0);
}

#[test]
fn parser_terminal_scopes_iterm_graphics_to_alternate_screen() {
    let mut terminal = ParserTerminal::new(80, 24);
    let primary = format!(
        "\x1b[1;1H\x1b]1337;File=inline=1;doNotMoveCursor=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );
    terminal.process(primary.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let primary_graphic_id = terminal.all_graphics()[0].id;
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
    assert!(!terminal.all_graphics()[0].alternate_screen);

    terminal.use_alt_screen();
    let alternate = format!(
        "\x1b[2;1H\x1b]1337;File=inline=1;doNotMoveCursor=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );
    terminal.process(alternate.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.protocol.as_str() == "iterm" && graphic.alternate_screen),
        "iTerm2 graphics emitted in the alternate screen must be scoped there"
    );

    terminal.process(b"\x1b[2J");

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, primary_graphic_id);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
    assert!(!terminal.all_graphics()[0].alternate_screen);
    assert_eq!(
        terminal.pending_cleared_kitty_graphics_count(),
        0,
        "non-Kitty iTerm graphics should not use Kitty clear-screen hold state"
    );

    terminal.use_primary_screen();

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, primary_graphic_id);
    assert!(!terminal.all_graphics()[0].alternate_screen);
}

#[test]
fn parser_terminal_scopes_multipart_iterm_graphics_to_alternate_screen() {
    let mut terminal = ParserTerminal::new(80, 24);
    let primary = format!(
        "\x1b[1;1H\x1b]1337;File=inline=1;doNotMoveCursor=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );
    terminal.process(primary.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let primary_graphic_id = terminal.all_graphics()[0].id;

    terminal.use_alt_screen();
    let start = "\x1b[2;1H\x1b]1337;MultipartFile=inline=1;name=cGl4ZWwucG5n\x1b\\";
    let part = format!("\x1b]1337;FilePart={RED_PIXEL_PNG_BASE64}\x1b\\");
    terminal.process(start.as_bytes());
    terminal.process(part.as_bytes());
    assert_eq!(
        terminal.graphics_count(),
        1,
        "multipart iTerm2 images without size wait for FileEnd before display"
    );

    terminal.process(b"\x1b]1337;FileEnd\x1b\\");
    assert_eq!(terminal.graphics_count(), 2);
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.protocol.as_str() == "iterm" && graphic.alternate_screen),
        "multipart iTerm2 graphics emitted in the alternate screen must be scoped there"
    );

    terminal.process(b"\x1b[2J");

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, primary_graphic_id);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
    assert!(!terminal.all_graphics()[0].alternate_screen);

    terminal.use_primary_screen();

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, primary_graphic_id);
    assert!(!terminal.all_graphics()[0].alternate_screen);
}

#[test]
fn parser_terminal_iterm_multipart_with_size_waits_for_file_end() {
    let mut terminal = ParserTerminal::new(80, 24);
    let start = "\x1b]1337;MultipartFile=inline=1;size=70;name=cGl4ZWwucG5n\x1b\\";
    let part = format!("\x1b]1337;FilePart={RED_PIXEL_PNG_BASE64}\x1b\\");

    terminal.process(start.as_bytes());
    terminal.process(part.as_bytes());

    assert_eq!(
        terminal.graphics_count(),
        0,
        "size= reaching the decoded byte count must not finalize before FileEnd"
    );

    terminal.process(b"\x1b]1337;FileEnd\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn parser_terminal_iterm_multipart_inline_accepts_unaligned_file_parts() {
    let mut terminal = ParserTerminal::new(80, 24);
    let start = "\x1b]1337;MultipartFile=inline=1;size=70;name=cGl4ZWwucG5n\x1b\\";
    let (first, rest) = RED_PIXEL_PNG_BASE64.split_at(5);
    let (second, third) = rest.split_at(7);

    terminal.process(start.as_bytes());
    for chunk in [first, second, third] {
        let part = format!("\x1b]1337;FilePart={chunk}\x1b\\");
        terminal.process(part.as_bytes());
    }

    assert_eq!(
        terminal.graphics_count(),
        0,
        "unaligned multipart iTerm2 images must wait for FileEnd"
    );

    terminal.process(b"\x1b]1337;FileEnd\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn parser_terminal_iterm_multipart_inline_rejects_short_declared_size() {
    let mut terminal = ParserTerminal::new(80, 24);
    let start = "\x1b]1337;MultipartFile=inline=1;size=71;name=cGl4ZWwucG5n\x1b\\";
    let part = format!("\x1b]1337;FilePart={RED_PIXEL_PNG_BASE64}\x1b\\");

    terminal.process(start.as_bytes());
    terminal.process(part.as_bytes());
    terminal.process(b"\x1b]1337;FileEnd\x1b\\");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "inline multipart images with a short declared size must not render at FileEnd"
    );
}

#[test]
fn parser_terminal_iterm_multipart_inline_rejects_data_after_base64_padding() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b]1337;MultipartFile=inline=1;name=cGl4ZWwucG5n\x1b\\");
    terminal.process(b"\x1b]1337;FilePart=aGVsbG8=\x1b\\");
    terminal.process(b"\x1b]1337;FilePart=AAAA\x1b\\");
    terminal.process(b"\x1b]1337;FileEnd\x1b\\");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "inline multipart iTerm2 base64 must reject data after padding instead of rendering partial bytes"
    );
    assert!(
        terminal.poll_events().iter().all(|event| !matches!(
            event,
            par_term_emu_core_rust::terminal::TerminalEvent::GraphicsAdded(_)
        )),
        "rejected inline multipart iTerm2 payload must not emit GraphicsAdded"
    );
}

#[test]
fn parser_terminal_iterm_single_file_aborts_pending_multipart_inline() {
    let mut terminal = ParserTerminal::new(80, 24);
    let start = "\x1b]1337;MultipartFile=inline=1;name=cGl4ZWwucG5n\x1b\\";
    let part = format!("\x1b]1337;FilePart={RED_PIXEL_PNG_BASE64}\x1b\\");
    let replacement = format!("\x1b]1337;File=inline=1:{RED_GREEN_2X1_PNG_BASE64}\x1b\\");

    terminal.process(start.as_bytes());
    terminal.process(part.as_bytes());
    assert_eq!(terminal.graphics_count(), 0);

    terminal.process(replacement.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
    assert_eq!(terminal.all_graphics()[0].width, 2);

    terminal.process(b"\x1b]1337;FileEnd\x1b\\");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "a stale FileEnd from an aborted iTerm2 multipart image must not render the old image"
    );
    assert_eq!(terminal.all_graphics()[0].width, 2);
}

#[test]
fn parser_terminal_iterm_new_multipart_fails_pending_download() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b]1337;MultipartFile=inline=0;size=5;name=Zmlyc3QudHh0\x1b\\");
    let started_events = terminal.poll_events();
    let first_transfer_id = started_events
        .iter()
        .find_map(|event| match event {
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferStarted {
                id,
                filename,
                ..
            } => {
                assert_eq!(filename.as_deref(), Some("first.txt"));
                Some(*id)
            }
            _ => None,
        })
        .expect("first MultipartFile should start a download transfer");

    terminal.process(b"\x1b]1337;MultipartFile=inline=0;size=5;name=c2Vjb25kLnR4dA==\x1b\\");
    let interrupted_events = terminal.poll_events();

    assert!(interrupted_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferFailed {
            id,
            reason,
        } if *id == first_transfer_id && reason.contains("interrupted by new MultipartFile")
    )));
    assert!(interrupted_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferStarted {
            id,
            filename,
            ..
        } if *id != first_transfer_id && filename.as_deref() == Some("second.txt")
    )));
}

#[test]
fn parser_terminal_iterm_multipart_download_with_size_waits_for_file_end() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b]1337;MultipartFile=inline=0;size=5;name=YXJ0aWZhY3QudHh0\x1b\\");
    let started_events = terminal.poll_events();
    let transfer_id = started_events
        .iter()
        .find_map(|event| match event {
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferStarted {
                id,
                direction,
                filename,
                total_bytes,
            } => {
                assert!(matches!(
                    direction,
                    par_term_emu_core_rust::terminal::TransferDirection::Download
                ));
                assert_eq!(filename.as_deref(), Some("artifact.txt"));
                assert_eq!(*total_bytes, Some(5));
                Some(*id)
            }
            _ => None,
        })
        .expect("MultipartFile should start a download transfer");

    terminal.process(b"\x1b]1337;FilePart=aGVsbG8=\x1b\\");
    let part_events = terminal.poll_events();
    assert!(part_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferProgress {
            id,
            bytes_transferred: 5,
            total_bytes: Some(5),
        } if *id == transfer_id
    )));
    assert!(
        part_events.iter().all(|event| !matches!(
            event,
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted { .. }
                | par_term_emu_core_rust::terminal::TerminalEvent::FileTransferFailed { .. }
        )),
        "download multipart transfers must wait for FileEnd even when size is reached"
    );

    terminal.process(b"\x1b]1337;FileEnd\x1b\\");
    let completed_events = terminal.poll_events();
    assert!(completed_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted {
            id,
            filename,
            size: 5,
        } if *id == transfer_id && filename.as_deref() == Some("artifact.txt")
    )));
}

#[test]
fn parser_terminal_iterm_multipart_download_accepts_unaligned_file_parts() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b]1337;MultipartFile=inline=0;size=5;name=YXJ0aWZhY3QudHh0\x1b\\");
    let started_events = terminal.poll_events();
    let transfer_id = started_events
        .iter()
        .find_map(|event| match event {
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferStarted { id, .. } => {
                Some(*id)
            }
            _ => None,
        })
        .expect("MultipartFile should start a download transfer");

    terminal.process(b"\x1b]1337;FilePart=aGV\x1b\\");
    let first_events = terminal.poll_events();
    assert!(
        first_events.iter().all(|event| !matches!(
            event,
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferProgress { .. }
                | par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted { .. }
                | par_term_emu_core_rust::terminal::TerminalEvent::FileTransferFailed { .. }
        )),
        "partial base64 quantum should not emit transfer progress"
    );

    terminal.process(b"\x1b]1337;FilePart=sb\x1b\\");
    let second_events = terminal.poll_events();
    assert!(second_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferProgress {
            id,
            bytes_transferred: 3,
            total_bytes: Some(5),
        } if *id == transfer_id
    )));

    terminal.process(b"\x1b]1337;FilePart=G8=\x1b\\");
    let third_events = terminal.poll_events();
    assert!(third_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferProgress {
            id,
            bytes_transferred: 5,
            total_bytes: Some(5),
        } if *id == transfer_id
    )));
    assert!(
        third_events.iter().all(|event| !matches!(
            event,
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted { .. }
                | par_term_emu_core_rust::terminal::TerminalEvent::FileTransferFailed { .. }
        )),
        "unaligned download transfer must still wait for FileEnd"
    );

    terminal.process(b"\x1b]1337;FileEnd\x1b\\");
    let completed_events = terminal.poll_events();
    assert!(completed_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted {
            id,
            filename,
            size: 5,
        } if *id == transfer_id && filename.as_deref() == Some("artifact.txt")
    )));
}

#[test]
fn parser_terminal_iterm_multipart_download_rejects_short_declared_size_on_file_end() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b]1337;MultipartFile=inline=0;size=10;name=YXJ0aWZhY3QudHh0\x1b\\");
    let started_events = terminal.poll_events();
    let transfer_id = started_events
        .iter()
        .find_map(|event| match event {
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferStarted { id, .. } => {
                Some(*id)
            }
            _ => None,
        })
        .expect("MultipartFile should start a download transfer");

    terminal.process(b"\x1b]1337;FilePart=aGVsbG8=\x1b\\");
    let part_events = terminal.poll_events();
    assert!(part_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferProgress {
            id,
            bytes_transferred: 5,
            total_bytes: Some(10),
        } if *id == transfer_id
    )));

    terminal.process(b"\x1b]1337;FileEnd\x1b\\");
    let completed_events = terminal.poll_events();
    assert!(completed_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferFailed {
            id,
            reason,
        } if *id == transfer_id && reason.contains("received 5 bytes, expected 10")
    )));
    assert!(
        completed_events.iter().all(|event| !matches!(
            event,
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted { .. }
        )),
        "short iTerm2 download transfers must fail instead of completing"
    );
}

#[test]
fn parser_terminal_iterm_multipart_download_rejects_oversized_part() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b]1337;MultipartFile=inline=0;size=4;name=YXJ0aWZhY3QudHh0\x1b\\");
    let started_events = terminal.poll_events();
    let transfer_id = started_events
        .iter()
        .find_map(|event| match event {
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferStarted { id, .. } => {
                Some(*id)
            }
            _ => None,
        })
        .expect("MultipartFile should start a download transfer");

    terminal.process(b"\x1b]1337;FilePart=aGVsbG8=\x1b\\");
    let failed_events = terminal.poll_events();
    assert!(failed_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferFailed {
            id,
            reason,
        } if *id == transfer_id && reason.contains("received 5 bytes, expected 4")
    )));
    assert!(
        failed_events.iter().all(|event| !matches!(
            event,
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferProgress { .. }
                | par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted { .. }
        )),
        "oversized iTerm2 download chunks must fail before progress/completion"
    );
}

#[test]
fn parser_terminal_iterm_multipart_download_rejects_data_after_base64_padding() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b]1337;MultipartFile=inline=0;size=5;name=YXJ0aWZhY3QudHh0\x1b\\");
    let started_events = terminal.poll_events();
    let transfer_id = started_events
        .iter()
        .find_map(|event| match event {
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferStarted { id, .. } => {
                Some(*id)
            }
            _ => None,
        })
        .expect("MultipartFile should start a download transfer");

    terminal.process(b"\x1b]1337;FilePart=aGVsbG8=\x1b\\");
    let first_part_events = terminal.poll_events();
    assert!(first_part_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferProgress {
            id,
            bytes_transferred: 5,
            total_bytes: Some(5),
        } if *id == transfer_id
    )));

    terminal.process(b"\x1b]1337;FilePart=AAAA\x1b\\");
    let failed_events = terminal.poll_events();
    assert!(failed_events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferFailed {
            id,
            reason,
        } if *id == transfer_id && reason.contains("continued after padding")
    )));
    assert!(
        failed_events.iter().all(|event| !matches!(
            event,
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted { .. }
        )),
        "download multipart iTerm2 base64 must fail, not complete, when data follows padding"
    );

    terminal.process(b"\x1b]1337;FileEnd\x1b\\");
    assert!(
        terminal.poll_events().iter().all(|event| !matches!(
            event,
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted { .. }
        )),
        "FileEnd after a padding error must not complete the failed transfer"
    );
}

#[test]
fn parser_terminal_iterm_single_download_rejects_size_mismatch() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b]1337;File=inline=0;size=10;name=YXJ0aWZhY3QudHh0:aGVsbG8=\x1b\\");
    let events = terminal.poll_events();
    let transfer_id = events
        .iter()
        .find_map(|event| match event {
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferStarted {
                id,
                total_bytes,
                ..
            } => {
                assert_eq!(*total_bytes, Some(10));
                Some(*id)
            }
            _ => None,
        })
        .expect("single File transfer should emit a started event");

    assert!(events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferFailed {
            id,
            reason,
        } if *id == transfer_id && reason.contains("received 5 bytes, expected 10")
    )));
    assert!(
        events.iter().all(|event| !matches!(
            event,
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted { .. }
        )),
        "single iTerm2 downloads with a mismatched size must fail"
    );
}

#[test]
fn parser_terminal_iterm_download_without_name_uses_default_filename() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b]1337;File=inline=0:aGVsbG8=\x1b\\");
    let events = terminal.poll_events();
    let transfer_id = events
        .iter()
        .find_map(|event| match event {
            par_term_emu_core_rust::terminal::TerminalEvent::FileTransferStarted {
                id,
                filename,
                ..
            } => {
                assert_eq!(filename.as_deref(), Some("Unnamed file"));
                Some(*id)
            }
            _ => None,
        })
        .expect("single File transfer should emit a started event");

    assert!(events.iter().any(|event| matches!(
        event,
        par_term_emu_core_rust::terminal::TerminalEvent::FileTransferCompleted {
            id,
            filename,
            size: 5,
        } if *id == transfer_id && filename.as_deref() == Some("Unnamed file")
    )));
}

#[test]
fn parser_terminal_sixel_color_definition_selects_painted_color() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bPq#1;2;100;0;0@\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(
        &graphic.pixels.as_ref()[0..4],
        &[255, 0, 0, 255],
        "Sixel color definition should select the defined color for following pixels"
    );
}

#[test]
fn parser_terminal_sixel_hls_color_definition_selects_painted_color() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bPq#1;1;240;50;100@\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(
        &graphic.pixels.as_ref()[0..4],
        &[0, 0, 255, 255],
        "Sixel HLS color definitions should select the defined color for following pixels"
    );
}

#[test]
fn parser_terminal_sixel_accepts_c1_dcs_and_st_controls() {
    for sequence in [
        b"\x1bPq#1;2;100;0;0@\x9c".as_slice(),
        b"\x90q#1;2;100;0;0@\x9c".as_slice(),
    ] {
        let mut terminal = ParserTerminal::new(12, 6);

        terminal.process(sequence);

        assert_eq!(
            terminal.graphics_count(),
            1,
            "C1 DCS/ST Sixel sequence should create one graphic: {sequence:?}"
        );
        let graphic = &terminal.all_graphics()[0];
        assert_eq!(graphic.protocol.as_str(), "sixel");
        assert_eq!(
            &graphic.pixels.as_ref()[0..4],
            &[255, 0, 0, 255],
            "C1 control-terminated Sixel should preserve painted pixels"
        );
    }
}

#[test]
fn parser_terminal_sixel_transparent_raster_preserves_unpainted_alpha() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bP0;1q\"1;1;3;2@\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(graphic.width, 3);
    assert_eq!(graphic.height, 2);
    assert_eq!(&graphic.pixels.as_ref()[0..4], &[0, 0, 0, 255]);
    assert_eq!(
        graphic.pixels.as_ref()[7],
        0,
        "transparent Sixel background should leave unpainted same-row pixels transparent"
    );
    assert_eq!(
        graphic.pixels.as_ref()[15],
        0,
        "transparent Sixel background should leave unpainted lower-row pixels transparent"
    );
}

#[test]
fn parser_terminal_sixel_omitted_p1_preserves_transparent_p2() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bP;1q@\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 6);
    assert_eq!(&graphic.pixels.as_ref()[0..4], &[0, 0, 0, 255]);
    assert_eq!(
        graphic.pixels.as_ref()[23],
        0,
        "omitted P1 must not shift transparent-background P2 out of position"
    );
}

#[test]
fn parser_terminal_sixel_empty_color_fields_default_to_zero() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bPq#1;2;100;;0@\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(
        &graphic.pixels.as_ref()[0..4],
        &[255, 0, 0, 255],
        "empty Sixel RGB component should default to 0 instead of dropping the color definition"
    );
}

#[test]
fn parser_terminal_sixel_empty_raster_width_defaults_to_data_extent() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bPq\"1;1;;2@\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.width, 1);
    assert_eq!(
        graphic.height, 2,
        "empty Sixel raster width should default to 0 without dropping the provided height"
    );
}

#[test]
fn parser_terminal_sixel_sparse_band_preserves_six_pixel_height() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bP0;1q@\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 6);
    assert_eq!(&graphic.pixels.as_ref()[0..4], &[0, 0, 0, 255]);
    assert_eq!(
        graphic.pixels.as_ref()[23],
        0,
        "transparent Sixel background should preserve clear rows inside a sparse sixel band"
    );
}

#[test]
fn parser_terminal_sixel_zero_raster_dimensions_fall_back_to_data_extents() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bPq\"1;1;0;0~\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 6);
    assert_eq!(&graphic.pixels.as_ref()[20..24], &[0, 0, 0, 255]);
}

#[test]
fn parser_terminal_sixel_oversized_raster_width_clamps_without_dropping_height() {
    let mut terminal = ParserTerminal::new(12, 6);
    terminal.set_sixel_limits(8, 5, 100);

    terminal.process(b"\x1bPq\"1;1;999999;4@\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(
        graphic.width, 8,
        "oversized Sixel raster width should clamp to the configured width limit"
    );
    assert_eq!(
        graphic.height, 4,
        "oversized Sixel raster width must not drop a valid raster height"
    );
    assert_eq!(&graphic.pixels.as_ref()[0..4], &[0, 0, 0, 255]);
}

#[test]
fn parser_terminal_sixel_carriage_return_and_newline_compose_bands() {
    let mut terminal = ParserTerminal::new(12, 10);

    terminal.process(b"\x1bP0;1q#1;2;100;0;0~$#2;2;0;100;0@-#3;2;0;0;100@\x1b\\X");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 12);

    let pixels = graphic.pixels.as_ref();
    assert_eq!(
        &pixels[0..4],
        &[0, 255, 0, 255],
        "Sixel '$' should return to the current band and allow later data to repaint x=0"
    );
    assert_eq!(
        &pixels[4..8],
        &[255, 0, 0, 255],
        "Sixel '$' must not clear the rest of the current six-pixel band"
    );
    assert_eq!(
        &pixels[20..24],
        &[255, 0, 0, 255],
        "the first band tail should survive the carriage-return repaint"
    );
    assert_eq!(
        &pixels[24..28],
        &[0, 0, 255, 255],
        "Sixel '-' should advance to the next six-pixel band before painting"
    );
    assert_eq!(
        &pixels[28..32],
        &[0, 0, 0, 0],
        "transparent Sixel background should keep unpainted pixels in the second band clear"
    );
    assert_eq!(
        terminal.active_grid().row_text(6).trim_end(),
        "X",
        "text after a multi-band Sixel graphic should land after the resolved graphic cell span"
    );
}

#[test]
fn parser_terminal_sixel_omitted_macro_pixel_aspect_defaults_to_2_to_1() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bPq~~\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(graphic.width, 2);
    assert_eq!(graphic.height, 6);
    assert_eq!(
        graphic.display_cell_span,
        Some((4, 3)),
        "omitted Sixel P1 should use the DEC default 2:1 macro pixel aspect ratio"
    );
    assert!(!graphic.placement.preserve_aspect_ratio);
}

#[test]
fn parser_terminal_sixel_macro_pixel_aspect_ratio_updates_display_span() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bP2q~~\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(graphic.width, 2);
    assert_eq!(graphic.height, 6);
    assert_eq!(
        graphic.display_cell_span,
        Some((10, 3)),
        "Sixel P1=2 macro pixel aspect ratio should scale display width as 5:1"
    );
    assert!(!graphic.placement.preserve_aspect_ratio);
}

#[test]
fn parser_terminal_sixel_raster_pixel_aspect_ratio_updates_display_span() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bP2q\"2;1;2;6~~\x1b\\X");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(graphic.width, 2);
    assert_eq!(graphic.height, 6);
    assert_eq!(
        graphic.display_cell_span,
        Some((4, 3)),
        "Sixel raster attributes should override the P1 macro pixel aspect ratio"
    );
    assert!(!graphic.placement.preserve_aspect_ratio);
    assert_eq!(
        terminal.active_grid().row_text(3).trim_end(),
        "X",
        "Sixel cursor advancement should use the aspect-corrected display span"
    );
}

#[test]
fn parser_terminal_sixel_square_macro_pixel_aspect_keeps_natural_span() {
    let mut terminal = ParserTerminal::new(12, 6);

    terminal.process(b"\x1bP7q~~\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(graphic.display_cell_span, Some((2, 3)));
    assert!(
        graphic.placement.preserve_aspect_ratio,
        "Sixel P1=7 is 1:1 and should not synthesize a scaled display width"
    );
}

#[test]
fn sixel_parser_newline_clamps_sparse_data_to_renderable_height() {
    let limits = par_term_emu_core_rust::sixel::SixelLimits::new(8, 12, 100);
    let mut parser = par_term_emu_core_rust::sixel::SixelParser::new_with_limits(limits);
    parser.set_params(&[0, 1, 0]);

    for _ in 0..100 {
        parser.new_line();
    }
    parser.parse_sixel('@');

    let graphic = parser.build_graphic((0, 0));

    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, limits.max_height);
    assert_eq!(graphic.get_pixel(0, 0), Some((0, 0, 0, 0)));
    assert_eq!(graphic.get_pixel(0, 6), Some((0, 0, 0, 255)));
}

#[test]
fn parser_terminal_ed2_removes_sixel_graphics_on_active_screen() {
    let mut terminal = ParserTerminal::new(12, 10);

    terminal.process(b"\x1b[2;2H\x1bPq????\x1b\\");
    terminal.process(b"\x1b[6;2H\x1bPq????\x1b\\");
    assert_eq!(terminal.graphics_count(), 2);
    assert!(
        terminal
            .all_graphics()
            .iter()
            .all(|graphic| graphic.protocol.as_str() == "sixel")
    );

    terminal.process(b"\x1b[2J");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "ED 2 should clear Sixel graphics from the active screen buffer"
    );
}

#[test]
fn parser_terminal_ed0_removes_current_row_right_and_lower_graphics() {
    let mut terminal = ParserTerminal::new(12, 8);

    let kept_iterm = format!(
        "\x1b[2;2H\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{RED_PIXEL_PNG_BASE64}\x1b\\"
    );
    let deleted_kitty =
        format!("\x1b[4;7H\x1b_Ga=T,f=32,s=1,v=1,i=760,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(kept_iterm.as_bytes());
    terminal.process(deleted_kitty.as_bytes());
    terminal.process(b"\x1b[6;2H\x1bPq????\x1b\\");
    assert_eq!(terminal.graphics_count(), 3);

    terminal.process(b"\x1b[3;5H\x1b[J");

    let remaining_summary: Vec<_> = terminal
        .all_graphics()
        .iter()
        .map(|graphic| {
            (
                graphic.protocol.as_str(),
                graphic.position,
                graphic.kitty_image_id,
            )
        })
        .collect();
    assert_eq!(
        terminal.graphics_count(),
        1,
        "ED 0 should remove graphics from the cursor to the screen end; remaining: {remaining_summary:?}"
    );
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.protocol.as_str(), "iterm");
    assert!(
        remaining.position.1 < 2,
        "ED 0 should keep only graphics entirely above the cursor; remaining: {remaining_summary:?}"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "ED 0 should remember deleted Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_ed1_removes_upper_and_current_row_left_graphics() {
    let mut terminal = ParserTerminal::new(12, 8);

    let deleted_iterm = format!(
        "\x1b[2;2H\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{RED_PIXEL_PNG_BASE64}\x1b\\"
    );
    let deleted_kitty =
        format!("\x1b[4;3H\x1b_Ga=T,f=32,s=1,v=1,i=761,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    let kept_kitty =
        format!("\x1b[6;3H\x1b_Ga=T,f=32,s=1,v=1,i=762,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(deleted_iterm.as_bytes());
    terminal.process(deleted_kitty.as_bytes());
    terminal.process(b"\x1b[4;8H\x1bPq????\x1b\\");
    terminal.process(kept_kitty.as_bytes());
    assert_eq!(terminal.graphics_count(), 4);

    terminal.process(b"\x1b[4;5H\x1b[1J");

    let remaining_summary: Vec<_> = terminal
        .all_graphics()
        .iter()
        .map(|graphic| {
            (
                graphic.protocol.as_str(),
                graphic.position,
                graphic.kitty_image_id,
            )
        })
        .collect();
    assert_eq!(
        terminal.graphics_count(),
        2,
        "ED 1 should remove graphics from the screen start through the cursor; remaining: {remaining_summary:?}"
    );
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.protocol.as_str() == "sixel" && graphic.position == (7, 3)),
        "ED 1 should keep current-row graphics to the right of the cursor"
    );
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.kitty_image_id == Some(762) && graphic.position == (2, 5)),
        "ED 1 should keep graphics below the cursor"
    );
    assert!(
        terminal
            .all_graphics()
            .iter()
            .all(|graphic| graphic.protocol.as_str() != "iterm"),
        "ED 1 should remove graphics on rows above the cursor"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "ED 1 should remember deleted Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_el_removes_intersecting_iterm_and_sixel_graphics() {
    let mut terminal = ParserTerminal::new(12, 10);

    let iterm = format!(
        "\x1b[2;3H\x1b]1337;File=inline=1;doNotMoveCursor=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );
    terminal.process(iterm.as_bytes());
    terminal.process(b"\x1b[6;3H\x1bPq????\x1b\\");
    assert_eq!(terminal.graphics_count(), 2);
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.protocol.as_str() == "iterm")
    );
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.protocol.as_str() == "sixel")
    );

    terminal.process(b"\x1b[2;3H\x1b[K");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "EL should clear only graphics intersecting the erased row segment"
    );
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.protocol.as_str(), "sixel");
    assert_eq!(remaining.position.1, 5);

    terminal.process(b"\x1b[6;1H\x1b[2K");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "EL 2 should clear Sixel graphics intersecting the erased row"
    );
}

#[test]
fn parser_terminal_decera_removes_intersecting_graphics_on_active_screen() {
    let mut terminal = ParserTerminal::new(12, 8);

    let first = format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=770,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    let second = format!("\x1b[6;3H\x1b_Ga=T,f=32,s=1,v=1,i=771,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    terminal.process(second.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[2;3;2;3$z");

    assert!(
        terminal.graphics_at_row(1).is_empty(),
        "DECERA should clear graphics intersecting the erased rectangle"
    );
    assert_eq!(
        terminal.graphics_count(),
        1,
        "DECERA should leave graphics outside the erased rectangle intact"
    );
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.kitty_image_id, Some(771));
    assert_eq!(terminal.graphics_at_row(5).len(), 1);
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "DECERA should remember deleted Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_decfra_removes_intersecting_graphics_on_active_screen() {
    let mut terminal = ParserTerminal::new(12, 8);

    let first = format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=772,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    let second = format!("\x1b[6;3H\x1b_Ga=T,f=32,s=1,v=1,i=773,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    terminal.process(second.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[35;2;3;2;3$x");

    assert!(
        terminal.graphics_at_row(1).is_empty(),
        "DECFRA should clear graphics intersecting the filled rectangle"
    );
    assert_eq!(
        terminal.graphics_count(),
        1,
        "DECFRA should leave graphics outside the filled rectangle intact"
    );
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.kitty_image_id, Some(773));
    assert_eq!(terminal.graphics_at_row(5).len(), 1);
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "DECFRA should remember deleted Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_deccra_clears_graphics_in_destination_rectangle() {
    let mut terminal = ParserTerminal::new(12, 8);

    terminal.process(b"\x1b[1;1HA");
    let overwritten =
        format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=774,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    let outside =
        format!("\x1b[6;3H\x1b_Ga=T,f=32,s=1,v=1,i=775,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(overwritten.as_bytes());
    terminal.process(outside.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[1;1;1;1;1;2;3$v");

    assert!(
        terminal.graphics_at_row(1).is_empty(),
        "DECCRA should clear graphics intersecting the copied-to destination rectangle"
    );
    assert_eq!(
        terminal.graphics_count(),
        1,
        "DECCRA should leave graphics outside the destination rectangle intact"
    );
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.kitty_image_id, Some(775));
    assert_eq!(terminal.graphics_at_row(5).len(), 1);
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "DECCRA should remember deleted Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_ed3_scopes_scrollback_graphics_to_primary_screen() {
    let mut terminal = ParserTerminal::with_scrollback(12, 4, 20);

    terminal.process(b"\x1b[1;1H\x1bPq????\x1b\\");
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "sixel");
    assert!(!terminal.all_graphics()[0].alternate_screen);

    terminal.process(b"\n\n\n\n");
    assert_eq!(
        terminal.graphics_count(),
        0,
        "primary Sixel graphic should leave the active screen after scrolling off"
    );
    assert_eq!(
        terminal.scrollback_graphics_count(),
        1,
        "primary Sixel graphic should be retained in graphics scrollback"
    );

    terminal.use_alt_screen();
    terminal.process(b"\x1b[3J");
    assert_eq!(
        terminal.scrollback_graphics_count(),
        1,
        "alternate-screen ED 3 must not clear primary-screen graphics scrollback"
    );

    terminal.use_primary_screen();
    terminal.process(b"\x1b[3J");
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "primary-screen ED 3 should clear primary graphics scrollback"
    );
}

#[test]
fn parser_terminal_ed3_scopes_iterm_scrollback_graphics_to_primary_screen() {
    let mut terminal = ParserTerminal::with_scrollback(12, 4, 20);
    let iterm = format!(
        "\x1b[1;1H\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(iterm.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
    assert!(!terminal.all_graphics()[0].alternate_screen);

    terminal.process(b"\n\n\n\n");
    assert_eq!(
        terminal.graphics_count(),
        0,
        "primary iTerm2 graphic should leave the active screen after scrolling off"
    );
    assert_eq!(
        terminal.scrollback_graphics_count(),
        1,
        "primary iTerm2 graphic should be retained in graphics scrollback"
    );
    assert_eq!(
        terminal.all_scrollback_graphics()[0].protocol.as_str(),
        "iterm"
    );
    assert!(
        !terminal.all_scrollback_graphics()[0].alternate_screen,
        "iTerm2 scrollback graphics should stay scoped to the primary screen"
    );

    terminal.use_alt_screen();
    terminal.process(b"\x1b[3J");
    assert_eq!(
        terminal.scrollback_graphics_count(),
        1,
        "alternate-screen ED 3 must not clear primary iTerm2 graphics scrollback"
    );

    terminal.use_primary_screen();
    terminal.process(b"\x1b[3J");
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "primary-screen ED 3 should clear primary iTerm2 graphics scrollback"
    );
}

#[test]
fn parser_terminal_scrollback_capacity_evicts_stale_graphics_rows() {
    let mut terminal = ParserTerminal::with_scrollback(8, 2, 2);
    let kitty = format!(
        "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=762,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );

    terminal.process(kitty.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b[2;1H\n");

    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(
        terminal.scrollback_graphics_count(),
        1,
        "graphic should follow its text row into graphics scrollback"
    );
    assert_eq!(
        terminal.all_scrollback_graphics()[0].scrollback_row,
        Some(0)
    );

    terminal.process(b"\x1b[2;1H\n");
    assert_eq!(terminal.grid().scrollback_len(), 2);
    assert_eq!(
        terminal.scrollback_graphics_count(),
        1,
        "graphic should remain while its text row is still retained"
    );

    terminal.process(b"\x1b[2;1H\n");

    assert_eq!(terminal.grid().scrollback_len(), 2);
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "graphics scrollback should drop placements once text scrollback capacity evicts the corresponding row"
    );
}

#[test]
fn parser_terminal_1049_exit_clears_alternate_graphics_and_keeps_primary_graphics() {
    let mut terminal = ParserTerminal::new(10, 6);
    let primary = format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=750,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(primary.as_bytes());
    let primary_graphic_id = terminal.all_graphics()[0].id;

    terminal.process(b"\x1b[?1049h");
    assert!(terminal.is_alt_screen_active());

    let alternate =
        format!("\x1b[4;3H\x1b_Ga=T,f=32,s=1,v=1,i=751,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(alternate.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);
    assert!(
        terminal.graphics_at_row(1).is_empty(),
        "primary graphics should not be visible while alternate screen is active"
    );
    assert_eq!(terminal.graphics_at_row(3).len(), 1);

    terminal.process(b"\x1b[?1049l");

    assert!(!terminal.is_alt_screen_active());
    assert_eq!(terminal.graphics_count(), 1);
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.id, primary_graphic_id);
    assert_eq!(remaining.kitty_image_id, Some(750));
    assert!(!remaining.alternate_screen);
    assert_eq!(terminal.graphics_at_row(1).len(), 1);
    assert!(
        terminal.graphics_at_row(3).is_empty(),
        "alternate-screen graphics should be cleared when returning to primary"
    );
}

#[test]
fn parser_terminal_1049_exit_clears_alternate_sixel_and_keeps_primary_sixel() {
    let mut terminal = ParserTerminal::new(10, 8);

    terminal.process(b"\x1b[2;1H\x1bPq????\x1b\\");
    let primary_graphic_id = terminal.all_graphics()[0].id;
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "sixel");
    assert!(!terminal.all_graphics()[0].alternate_screen);

    terminal.process(b"\x1b[?1049h");
    terminal.process(b"\x1b[6;1H\x1bPq????\x1b\\");
    assert_eq!(terminal.graphics_count(), 2);
    assert!(
        terminal.graphics_at_row(1).is_empty(),
        "primary Sixel graphics should not be visible while alternate screen is active"
    );
    assert_eq!(terminal.graphics_at_row(5).len(), 1);

    terminal.process(b"\x1b[?1049l");

    assert_eq!(terminal.graphics_count(), 1);
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.id, primary_graphic_id);
    assert_eq!(remaining.protocol.as_str(), "sixel");
    assert!(!remaining.alternate_screen);
    assert_eq!(terminal.graphics_at_row(1).len(), 1);
    assert!(
        terminal.graphics_at_row(5).is_empty(),
        "alternate Sixel graphics should be cleared when returning to primary"
    );
}

#[test]
fn parser_terminal_ed2_in_alternate_screen_clears_only_alternate_graphics() {
    let mut terminal = ParserTerminal::new(10, 6);
    let primary = format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=760,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(primary.as_bytes());
    let primary_graphic_id = terminal.all_graphics()[0].id;

    terminal.process(b"\x1b[?1049h");
    let alternate =
        format!("\x1b[4;3H\x1b_Ga=T,f=32,s=1,v=1,i=761,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(alternate.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[2J");

    assert!(terminal.is_alt_screen_active());
    assert_eq!(terminal.graphics_count(), 1);
    assert!(
        terminal.graphics_at_row(3).is_empty(),
        "ED 2 should clear alternate-screen graphics from the active screen"
    );
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.id, primary_graphic_id);
    assert_eq!(remaining.kitty_image_id, Some(760));
    assert!(!remaining.alternate_screen);

    terminal.process(b"\x1b[?1049l");
    assert_eq!(terminal.graphics_at_row(1).len(), 1);
}

#[test]
fn parser_terminal_alternate_screen_scroll_drops_sixel_without_scrollback_retention() {
    let mut terminal = ParserTerminal::with_scrollback(8, 4, 20);

    terminal.process(b"\x1b[?1049h");
    terminal.process(b"\x1b[1;1H\x1bPq????\x1b\\");
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "sixel");
    assert!(terminal.all_graphics()[0].alternate_screen);

    terminal.process(b"\x1b[4;1H\n\n\n\n\n");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "alternate-screen graphics should be dropped after scrolling out of the active viewport"
    );
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "alternate-screen graphics must not be retained in primary graphics scrollback"
    );
}

#[test]
fn parser_terminal_alternate_screen_scroll_drops_kitty_without_scrollback_retention() {
    let mut terminal = ParserTerminal::with_scrollback(8, 4, 20);
    let graphic = format!(
        "\x1b[?1049h\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=772,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );

    terminal.process(graphic.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "kitty");
    assert!(terminal.all_graphics()[0].alternate_screen);

    terminal.process(b"\x1b[4;1H\n\n\n\n\n");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "alternate-screen Kitty graphics should be dropped after scrolling out of the active viewport"
    );
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "alternate-screen Kitty graphics must not be retained in primary graphics scrollback"
    );
}

#[test]
fn parser_terminal_alternate_screen_scroll_drops_iterm_without_scrollback_retention() {
    let mut terminal = ParserTerminal::with_scrollback(8, 4, 20);
    let graphic =
        format!("\x1b[?1049h\x1b[1;1H\x1b]1337;File=inline=1:{RED_PIXEL_PNG_BASE64}\x1b\\");

    terminal.process(graphic.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
    assert!(terminal.all_graphics()[0].alternate_screen);

    terminal.process(b"\x1b[4;1H\n\n\n\n\n");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "alternate-screen iTerm2 graphics should be dropped after scrolling out of the active viewport"
    );
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "alternate-screen iTerm2 graphics must not be retained in primary graphics scrollback"
    );
}

#[test]
fn parser_terminal_nonzero_top_scroll_region_drops_graphics_without_scrollback_retention() {
    let mut terminal = ParserTerminal::with_scrollback(8, 6, 20);
    let graphic =
        format!("\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=770,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");

    terminal.process(b"\x1b[3;6r");
    terminal.process(graphic.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].position, (0, 2));

    terminal.process(b"\x1b[1S");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "graphics clipped out of a non-zero-top scroll region should be discarded"
    );
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "non-zero-top scroll regions do not append text rows or graphics to scrollback"
    );
}

#[test]
fn parser_terminal_scroll_up_drops_multirow_graphics_overlapping_top_margin() {
    let mut terminal = ParserTerminal::with_scrollback(12, 6, 20);
    let clipped = format!(
        "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=772,p=1,c=1,r=2,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    let shifted = format!(
        "\x1b[5;1H\x1b_Ga=T,f=32,s=1,v=1,i=773,p=1,c=1,r=1,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );

    terminal.process(b"\x1b[3;5r");
    terminal.process(clipped.as_bytes());
    terminal.process(shifted.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[1S");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "SU should discard graphics that overlap the deleted top row even when anchored above the scroll region"
    );
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(773));
    assert_eq!(terminal.all_graphics()[0].position.1, 3);
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "non-zero-top SU must not retain clipped graphics in scrollback"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "SU should remember overlapping Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_scroll_up_deferred_delete_for_clipped_nonzero_top_kitty() {
    let mut terminal = ParserTerminal::with_scrollback(12, 6, 20);
    let clipped = format!(
        "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=774,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );

    terminal.process(b"\x1b[3;5r");
    terminal.process(clipped.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b[1S");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "SU should discard graphics fully clipped out of a non-zero-top scroll region"
    );
    assert_eq!(terminal.scrollback_graphics_count(), 0);
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "fully clipped Kitty placements should be remembered for frontend clearing"
    );
}

#[test]
fn parser_terminal_sixel_at_bottom_scrolls_region() {
    let mut terminal = ParserTerminal::with_scrollback(8, 4, 20);

    terminal.process(b"\x1b[4;1H\x1bPq~\x1b\\");

    assert_eq!(terminal.cursor().col, 0);
    assert_eq!(terminal.cursor().row, 3);
    assert_eq!(
        terminal.grid().scrollback_len(),
        3,
        "Sixel cursor advancement at the bottom should scroll the active region"
    );
    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(
        graphic.position,
        (0, 0),
        "Sixel graphic should move with the scrolled active region"
    );
}

#[test]
fn parser_terminal_sixel_advancement_respects_scroll_region_bottom() {
    let mut terminal = ParserTerminal::new(8, 6);

    terminal.process(b"\x1b[1;1Htop\x1b[2;1Hone\x1b[3;1Htwo\x1b[4;1Hthree\x1b[5;1Hbottom");
    terminal.process(b"\x1b[2;4r\x1b[4;1H\x1bPq~\x1b\\");

    assert_eq!(
        terminal.cursor().row,
        3,
        "Sixel cursor advancement should stay pinned to the scroll region bottom"
    );
    assert_eq!(
        terminal.active_grid().row_text(4).trim_end(),
        "bottom",
        "Sixel advancement inside a partial scroll region must not move into rows below the region"
    );
    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(
        graphic.position,
        (0, 1),
        "partially clipped Sixel graphics should stay anchored at the scroll region top"
    );
    assert_eq!(
        graphic.scroll_offset_rows, 1,
        "Sixel graphics clipped by partial scroll regions should track the hidden top rows"
    );
}

fn screenshot_sixel_graphic(
    row: usize,
    height: usize,
    pixels: Vec<u8>,
    scroll_offset_rows: usize,
) -> TerminalGraphic {
    screenshot_rgba_graphic_at(0, row, 1, height, pixels, scroll_offset_rows)
}

fn screenshot_rgba_graphic_at(
    col: usize,
    row: usize,
    width: usize,
    height: usize,
    pixels: Vec<u8>,
    scroll_offset_rows: usize,
) -> TerminalGraphic {
    let width = width.max(1);
    let height = height.max(1);
    let mut graphic = TerminalGraphic::new(
        next_graphic_id(),
        GraphicProtocol::Sixel,
        (col, row),
        width,
        height,
        pixels,
    );
    graphic.set_cell_dimensions(1, 1);
    graphic.set_display_cell_span(width, height);
    graphic.scroll_offset_rows = scroll_offset_rows;
    graphic
}

fn screenshot_pixels_config() -> ScreenshotConfig {
    ScreenshotConfig::default()
        .with_padding(0)
        .with_sixel_mode(SixelRenderMode::Pixels)
}

fn screenshot_halfblocks_config() -> ScreenshotConfig {
    ScreenshotConfig::default()
        .with_padding(0)
        .with_sixel_mode(SixelRenderMode::HalfBlocks)
}

#[test]
fn parser_terminal_screenshot_includes_scrollback_graphics_at_offset() {
    let mut terminal = ParserTerminal::with_scrollback(4, 2, 16);
    terminal.set_cell_dimensions(1, 1);
    terminal.process(b"one\ntwo\nthree\n");
    let scrollback_len = terminal.active_grid().scrollback_len();
    assert!(
        scrollback_len > 0,
        "test setup should create text scrollback"
    );

    assert!(
        terminal
            .graphics_store_mut()
            .add_graphic(screenshot_sixel_graphic(0, 1, vec![255, 0, 0, 255], 0))
    );
    terminal
        .graphics_store_mut()
        .adjust_for_scroll_up_with_scrollback(1, 0, 1, scrollback_len.saturating_sub(1));
    assert_eq!(terminal.scrollback_graphics_count(), 1);

    let disabled = terminal
        .screenshot(
            ScreenshotConfig::default()
                .with_padding(0)
                .with_sixel_mode(SixelRenderMode::Disabled),
            1,
        )
        .expect("disabled screenshot should render");
    let pixels = terminal
        .screenshot(screenshot_pixels_config(), 1)
        .expect("scrollback graphics screenshot should render");

    assert_ne!(
        pixels, disabled,
        "scrollback screenshots should render graphics when pixel mode is enabled"
    );
}

#[test]
fn parser_terminal_screenshot_crops_partially_scrolled_graphic_top() {
    let mut cropped = ParserTerminal::with_scrollback(4, 2, 16);
    cropped.set_cell_dimensions(1, 1);
    assert!(
        cropped
            .graphics_store_mut()
            .add_graphic(screenshot_sixel_graphic(
                0,
                2,
                vec![255, 0, 0, 255, 0, 255, 0, 255],
                1,
            ))
    );

    let mut expected = ParserTerminal::with_scrollback(4, 2, 16);
    expected.set_cell_dimensions(1, 1);
    assert!(
        expected
            .graphics_store_mut()
            .add_graphic(screenshot_sixel_graphic(0, 1, vec![0, 255, 0, 255], 0))
    );

    let cropped_png = cropped
        .screenshot(screenshot_pixels_config(), 0)
        .expect("cropped graphic screenshot should render");
    let expected_png = expected
        .screenshot(screenshot_pixels_config(), 0)
        .expect("expected graphic screenshot should render");

    assert_eq!(
        cropped_png, expected_png,
        "screenshot renderer should skip graphic rows hidden by scroll_offset_rows"
    );
}

#[test]
fn parser_terminal_screenshot_applies_graphic_source_rectangle() {
    let mut source_rect = ParserTerminal::with_scrollback(4, 2, 16);
    source_rect.set_cell_dimensions(1, 1);
    let mut graphic =
        screenshot_rgba_graphic_at(0, 0, 2, 1, vec![255, 0, 0, 255, 0, 255, 0, 255], 0);
    graphic.placement.source_x_offset = 1;
    graphic.placement.source_width = Some(1);
    assert!(source_rect.graphics_store_mut().add_graphic(graphic));

    let mut expected = ParserTerminal::with_scrollback(4, 2, 16);
    expected.set_cell_dimensions(1, 1);
    assert!(
        expected
            .graphics_store_mut()
            .add_graphic(screenshot_rgba_graphic_at(
                0,
                0,
                1,
                1,
                vec![0, 255, 0, 255],
                0,
            ))
    );

    assert_eq!(
        source_rect
            .screenshot(screenshot_pixels_config(), 0)
            .expect("source-rect screenshot should render"),
        expected
            .screenshot(screenshot_pixels_config(), 0)
            .expect("expected screenshot should render"),
        "screenshot renderer should sample only the requested graphic source rectangle"
    );
}

#[test]
fn parser_terminal_screenshot_halfblocks_applies_graphic_source_rectangle() {
    let mut source_rect = ParserTerminal::with_scrollback(4, 2, 16);
    source_rect.set_cell_dimensions(1, 1);
    let mut graphic =
        screenshot_rgba_graphic_at(0, 0, 2, 1, vec![255, 0, 0, 255, 0, 255, 0, 255], 0);
    graphic.placement.source_x_offset = 1;
    graphic.placement.source_width = Some(1);
    assert!(source_rect.graphics_store_mut().add_graphic(graphic));

    let mut expected = ParserTerminal::with_scrollback(4, 2, 16);
    expected.set_cell_dimensions(1, 1);
    assert!(
        expected
            .graphics_store_mut()
            .add_graphic(screenshot_rgba_graphic_at(
                0,
                0,
                1,
                1,
                vec![0, 255, 0, 255],
                0,
            ))
    );

    assert_eq!(
        source_rect
            .screenshot(screenshot_halfblocks_config(), 0)
            .expect("halfblocks source-rect screenshot should render"),
        expected
            .screenshot(screenshot_halfblocks_config(), 0)
            .expect("expected halfblocks screenshot should render"),
        "halfblocks screenshot renderer should sample only the requested source rectangle"
    );
}

#[test]
fn parser_terminal_screenshot_applies_graphic_offsets() {
    let mut offset = ParserTerminal::with_scrollback(4, 3, 16);
    offset.set_cell_dimensions(1, 1);
    let mut graphic = screenshot_rgba_graphic_at(0, 0, 1, 1, vec![255, 0, 0, 255], 0);
    graphic.placement.x_offset = 1;
    graphic.placement.y_offset = 1;
    assert!(offset.graphics_store_mut().add_graphic(graphic));

    let mut expected = ParserTerminal::with_scrollback(4, 3, 16);
    expected.set_cell_dimensions(1, 1);
    assert!(
        expected
            .graphics_store_mut()
            .add_graphic(screenshot_rgba_graphic_at(
                0,
                0,
                2,
                2,
                vec![0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 255,],
                0,
            ))
    );

    assert_eq!(
        offset
            .screenshot(screenshot_pixels_config(), 0)
            .expect("offset screenshot should render"),
        expected
            .screenshot(screenshot_pixels_config(), 0)
            .expect("expected screenshot should render"),
        "screenshot renderer should apply per-cell graphic x/y offsets"
    );
}

#[test]
fn parser_terminal_screenshot_orders_graphics_by_z_index() {
    let mut layered = ParserTerminal::with_scrollback(4, 2, 16);
    layered.set_cell_dimensions(1, 1);
    let mut top = screenshot_rgba_graphic_at(0, 0, 1, 1, vec![255, 0, 0, 255], 0);
    top.placement.z_index = 9;
    let mut bottom = screenshot_rgba_graphic_at(0, 0, 1, 1, vec![0, 255, 0, 255], 0);
    bottom.placement.z_index = 0;
    assert!(layered.graphics_store_mut().add_graphic(top));
    assert!(layered.graphics_store_mut().add_graphic(bottom));

    let mut expected = ParserTerminal::with_scrollback(4, 2, 16);
    expected.set_cell_dimensions(1, 1);
    assert!(
        expected
            .graphics_store_mut()
            .add_graphic(screenshot_rgba_graphic_at(
                0,
                0,
                1,
                1,
                vec![255, 0, 0, 255],
                0,
            ))
    );

    assert_eq!(
        layered
            .screenshot(screenshot_pixels_config(), 0)
            .expect("layered screenshot should render"),
        expected
            .screenshot(screenshot_pixels_config(), 0)
            .expect("expected screenshot should render"),
        "higher z-index graphics should render above lower z-index graphics"
    );
}

#[test]
fn parser_terminal_screenshot_applies_requested_pixel_size() {
    let mut scaled = ParserTerminal::with_scrollback(4, 2, 16);
    scaled.set_cell_dimensions(1, 1);
    let mut graphic = screenshot_rgba_graphic_at(0, 0, 1, 1, vec![255, 0, 0, 255], 0);
    graphic.placement.requested_width = ImageDimension::pixels(2.0);
    graphic.placement.requested_height = ImageDimension::pixels(1.0);
    assert!(scaled.graphics_store_mut().add_graphic(graphic));

    let mut expected = ParserTerminal::with_scrollback(4, 2, 16);
    expected.set_cell_dimensions(1, 1);
    assert!(
        expected
            .graphics_store_mut()
            .add_graphic(screenshot_rgba_graphic_at(
                0,
                0,
                2,
                1,
                vec![255, 0, 0, 255, 255, 0, 0, 255],
                0,
            ))
    );

    assert_eq!(
        scaled
            .screenshot(screenshot_pixels_config(), 0)
            .expect("scaled screenshot should render"),
        expected
            .screenshot(screenshot_pixels_config(), 0)
            .expect("expected screenshot should render"),
        "screenshot renderer should scale graphics to requested pixel dimensions"
    );
}

#[test]
fn parser_terminal_screenshot_halfblocks_applies_requested_pixel_size() {
    let mut scaled = ParserTerminal::with_scrollback(4, 2, 16);
    scaled.set_cell_dimensions(1, 1);
    let mut graphic = screenshot_rgba_graphic_at(0, 0, 1, 1, vec![255, 0, 0, 255], 0);
    graphic.placement.requested_width = ImageDimension::pixels(2.0);
    graphic.placement.requested_height = ImageDimension::pixels(1.0);
    assert!(scaled.graphics_store_mut().add_graphic(graphic));

    let mut expected = ParserTerminal::with_scrollback(4, 2, 16);
    expected.set_cell_dimensions(1, 1);
    assert!(
        expected
            .graphics_store_mut()
            .add_graphic(screenshot_rgba_graphic_at(
                0,
                0,
                2,
                1,
                vec![255, 0, 0, 255, 255, 0, 0, 255],
                0,
            ))
    );

    assert_eq!(
        scaled
            .screenshot(screenshot_halfblocks_config(), 0)
            .expect("halfblocks scaled screenshot should render"),
        expected
            .screenshot(screenshot_halfblocks_config(), 0)
            .expect("expected halfblocks screenshot should render"),
        "halfblocks screenshot renderer should scale graphics to requested pixel dimensions"
    );
}

#[test]
fn parser_terminal_il_moves_graphics_and_drops_bottom_region_graphics() {
    let mut terminal = ParserTerminal::new(12, 6);
    let shifted = format!(
        "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=780,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    let dropped = format!(
        "\x1b[5;1H\x1b_Ga=T,f=32,s=1,v=1,i=781,p=1,c=1,r=1,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );

    terminal.process(b"\x1b[3;5r");
    terminal.process(shifted.as_bytes());
    terminal.process(dropped.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[3;1H\x1b[L");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "IL should discard graphics anchored in rows pushed past the bottom margin"
    );
    assert_eq!(
        terminal.all_graphics()[0].position.1,
        3,
        "IL should move graphics below the insertion row down with their text rows"
    );
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(780));
}

#[test]
fn parser_terminal_il_drops_multirow_graphics_partly_pushed_past_bottom() {
    let mut terminal = ParserTerminal::new(12, 6);
    let shifted = format!(
        "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=782,p=1,c=1,r=2,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    let clipped = format!(
        "\x1b[4;1H\x1b_Ga=T,f=32,s=1,v=1,i=783,p=1,c=1,r=2,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );

    terminal.process(b"\x1b[3;5r");
    terminal.process(shifted.as_bytes());
    terminal.process(clipped.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[3;1H\x1b[L");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "IL should discard multirow graphics whose bottom rows are pushed past the margin"
    );
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(782));
    assert_eq!(terminal.all_graphics()[0].position.1, 3);
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "IL should remember partly clipped Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_il_drops_multirow_graphics_overlapping_insert_top() {
    let mut terminal = ParserTerminal::with_scrollback(12, 6, 20);
    let clipped = format!(
        "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=784,p=1,c=1,r=2,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    let shifted = format!(
        "\x1b[4;1H\x1b_Ga=T,f=32,s=1,v=1,i=785,p=1,c=1,r=1,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );

    terminal.process(b"\x1b[3;5r");
    terminal.process(clipped.as_bytes());
    terminal.process(shifted.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[3;1H\x1b[L");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "IL should discard multirow graphics that overlap inserted top rows even when anchored above the margin"
    );
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(785));
    assert_eq!(terminal.all_graphics()[0].position.1, 4);
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "IL must not retain graphics clipped by inserted rows in primary scrollback"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "IL should remember top-overlapping Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_dl_moves_graphics_without_scrollback_retention() {
    let mut terminal = ParserTerminal::with_scrollback(12, 6, 20);
    let deleted = format!(
        "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=790,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    let shifted = format!(
        "\x1b[5;1H\x1b_Ga=T,f=32,s=1,v=1,i=791,p=1,c=1,r=1,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );

    terminal.process(deleted.as_bytes());
    terminal.process(shifted.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[3;1H\x1b[M");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "DL should delete graphics anchored in the deleted line range"
    );
    assert_eq!(
        terminal.all_graphics()[0].position.1,
        3,
        "DL should move graphics below the deleted rows up with their text rows"
    );
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(791));
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "DL removes lines from the scroll region and must not retain deleted graphics in scrollback"
    );
}

#[test]
fn parser_terminal_dl_drops_multirow_graphics_overlapping_deleted_rows() {
    let mut terminal = ParserTerminal::with_scrollback(12, 6, 20);
    let clipped = format!(
        "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=796,p=1,c=1,r=2,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    let shifted = format!(
        "\x1b[5;1H\x1b_Ga=T,f=32,s=1,v=1,i=797,p=1,c=1,r=1,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );

    terminal.process(b"\x1b[3;5r");
    terminal.process(clipped.as_bytes());
    terminal.process(shifted.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[3;1H\x1b[M");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "DL should discard multirow graphics that overlap deleted rows even when anchored above the margin"
    );
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(797));
    assert_eq!(terminal.all_graphics()[0].position.1, 3);
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "DL must not retain deleted-region graphics in scrollback"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "DL should remember overlapping Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_sd_moves_graphics_and_drops_bottom_region_graphics() {
    let mut terminal = ParserTerminal::with_scrollback(12, 6, 20);
    let shifted = format!(
        "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=792,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    let dropped = format!(
        "\x1b[5;1H\x1b_Ga=T,f=32,s=1,v=1,i=793,p=1,c=1,r=1,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );

    terminal.process(b"\x1b[3;5r");
    terminal.process(shifted.as_bytes());
    terminal.process(dropped.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[3;1H\x1b[T");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "SD should discard graphics anchored in rows pushed past the bottom margin"
    );
    assert_eq!(
        terminal.all_graphics()[0].position.1,
        3,
        "SD should move graphics inside the scroll region down with their text rows"
    );
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(792));
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "SD inserts lines into the scroll region and must not retain pushed graphics in scrollback"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "SD should remember deleted Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_sd_drops_multirow_graphics_partly_pushed_past_bottom() {
    let mut terminal = ParserTerminal::with_scrollback(12, 6, 20);
    let shifted = format!(
        "\x1b[3;1H\x1b_Ga=T,f=32,s=1,v=1,i=794,p=1,c=1,r=2,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    let clipped = format!(
        "\x1b[4;1H\x1b_Ga=T,f=32,s=1,v=1,i=795,p=1,c=1,r=2,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );

    terminal.process(b"\x1b[3;5r");
    terminal.process(shifted.as_bytes());
    terminal.process(clipped.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[3;1H\x1b[T");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "SD should discard multirow graphics whose bottom rows are pushed past the margin"
    );
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(794));
    assert_eq!(terminal.all_graphics()[0].position.1, 3);
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "SD must not retain partly clipped graphics in primary scrollback"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "SD should remember partly clipped Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_sd_drops_multirow_graphics_overlapping_scroll_top() {
    let mut terminal = ParserTerminal::with_scrollback(12, 6, 20);
    let clipped = format!(
        "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=798,p=1,c=1,r=2,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );
    let shifted = format!(
        "\x1b[4;1H\x1b_Ga=T,f=32,s=1,v=1,i=799,p=1,c=1,r=1,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\"
    );

    terminal.process(b"\x1b[3;5r");
    terminal.process(clipped.as_bytes());
    terminal.process(shifted.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[1T");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "SD should discard multirow graphics that overlap inserted top rows even when anchored above the margin"
    );
    assert_eq!(terminal.all_graphics()[0].kitty_image_id, Some(799));
    assert_eq!(terminal.all_graphics()[0].position.1, 4);
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "SD must not retain graphics clipped by scroll-down insertion in primary scrollback"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "SD should remember top-overlapping Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_ich_moves_graphics_and_drops_right_margin_graphics() {
    let mut terminal = ParserTerminal::new(8, 4);
    let shifted = format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=710,p=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    let dropped =
        format!("\x1b[2;8H\x1b_Ga=T,f=32,s=1,v=1,i=711,p=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");

    terminal.process(shifted.as_bytes());
    terminal.process(dropped.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[2;2H\x1b[2@");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "ICH should discard graphics pushed past the right margin"
    );
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.kitty_image_id, Some(710));
    assert_eq!(
        graphic.position.0, 4,
        "ICH should move graphics right with shifted row content"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "ICH should remember deleted Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_insert_mode_write_moves_graphics_like_ich() {
    let mut terminal = ParserTerminal::new(8, 4);
    let shifted = format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=712,p=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    let dropped =
        format!("\x1b[2;8H\x1b_Ga=T,f=32,s=1,v=1,i=713,p=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");

    terminal.process(shifted.as_bytes());
    terminal.process(dropped.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[4h\x1b[2;2HZ");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "IRM character writes should discard graphics pushed past the right margin"
    );
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.kitty_image_id, Some(712));
    assert_eq!(
        graphic.position.0, 3,
        "IRM character writes should move graphics right with shifted row content"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "IRM character writes should remember deleted Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_insert_mode_ascii_run_inserts_and_moves_graphics_by_run_width() {
    let mut terminal = ParserTerminal::new(10, 4);
    let shifted = format!("\x1b[2;5H\x1b_Ga=T,f=32,s=1,v=1,i=714,p=1,q=1;{RED_RGBA_BASE64}\x1b\\");

    terminal.process(b"\x1b[2;1HABCDE");
    terminal.process(shifted.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b[4h\x1b[2;2HXY");

    assert_eq!(
        terminal.active_grid().row_text(1).trim_end(),
        "AXYBCDE",
        "IRM must insert every printable ASCII byte in a run instead of overwriting row text"
    );
    assert_eq!(
        terminal.graphics_count(),
        1,
        "IRM ASCII runs should keep graphics that remain inside the row"
    );
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.kitty_image_id, Some(714));
    assert_eq!(
        graphic.position.0, 6,
        "IRM ASCII runs should move graphics right by the inserted run width"
    );
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
}

#[test]
fn parser_terminal_dch_deletes_intersecting_graphics_and_moves_right_side_left() {
    let mut terminal = ParserTerminal::new(8, 4);
    let deleted = format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=720,p=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    let shifted =
        format!("\x1b[2;6H\x1b_Ga=T,f=32,s=1,v=1,i=721,p=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");

    terminal.process(deleted.as_bytes());
    terminal.process(shifted.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[2;3H\x1b[P");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "DCH should delete graphics intersecting the deleted cell range"
    );
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.kitty_image_id, Some(721));
    assert_eq!(
        graphic.position.0, 4,
        "DCH should move graphics after the deleted range left"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "DCH should remember deleted Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_alt_screen_erase_keeps_primary_graphics() {
    let mut terminal = ParserTerminal::new(10, 6);
    let primary = format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=730,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(primary.as_bytes());
    let primary_graphic_id = terminal.all_graphics()[0].id;

    terminal.use_alt_screen();
    let alternate =
        format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=731,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(alternate.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[2;3H\x1b[K");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "EL in the alternate screen must delete only alternate-screen graphics"
    );
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.id, primary_graphic_id);
    assert_eq!(remaining.kitty_image_id, Some(730));
    assert!(!remaining.alternate_screen);
    assert_eq!(remaining.position, (2, 1));
}

#[test]
fn parser_terminal_alt_screen_character_edits_keep_primary_graphics() {
    let mut terminal = ParserTerminal::new(10, 6);
    let primary = format!("\x1b[2;6H\x1b_Ga=T,f=32,s=1,v=1,i=740,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(primary.as_bytes());
    let primary_graphic_id = terminal.all_graphics()[0].id;

    terminal.use_alt_screen();
    let alternate =
        format!("\x1b[2;4H\x1b_Ga=T,f=32,s=1,v=1,i=741,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    terminal.process(alternate.as_bytes());
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[2;2H\x1b[2@");
    let primary_after_ich = terminal
        .all_graphics()
        .iter()
        .find(|graphic| graphic.id == primary_graphic_id)
        .expect("primary graphic should survive alternate-screen ICH");
    assert_eq!(
        primary_after_ich.position,
        (5, 1),
        "ICH in the alternate screen must not move primary-screen graphics"
    );
    let alternate_after_ich = terminal
        .all_graphics()
        .iter()
        .find(|graphic| graphic.kitty_image_id == Some(741))
        .expect("alternate graphic should survive alternate-screen ICH");
    assert_eq!(
        alternate_after_ich.position,
        (5, 1),
        "ICH should move alternate-screen graphics with the edited row"
    );

    terminal.process(b"\x1b[2;6H\x1b[P");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "DCH in the alternate screen must delete only alternate-screen graphics"
    );
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.id, primary_graphic_id);
    assert_eq!(remaining.kitty_image_id, Some(740));
    assert_eq!(remaining.position, (5, 1));
    assert!(!remaining.alternate_screen);
}

#[test]
fn parser_terminal_decsera_removes_graphics_intersecting_erased_cells() {
    let mut terminal = ParserTerminal::new(10, 6);
    let graphic = format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=742,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");

    terminal.process(graphic.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b[2;3;2;3${");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "DECSERA should remove graphics intersecting cells it actually erased"
    );
    assert_eq!(
        terminal.deferred_kitty_delete_count(),
        1,
        "DECSERA should remember deleted Kitty placements for frontend clearing"
    );
}

#[test]
fn parser_terminal_decsera_removes_intersecting_iterm_and_sixel_graphics() {
    let mut terminal = ParserTerminal::new(12, 8);
    let iterm = format!(
        "\x1b[2;3H\x1b]1337;File=inline=1;doNotMoveCursor=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(iterm.as_bytes());
    terminal.process(b"\x1b[5;3H\x1bPq????\x1b\\");
    assert_eq!(terminal.graphics_count(), 2);
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.protocol.as_str() == "iterm")
    );
    assert!(
        terminal
            .all_graphics()
            .iter()
            .any(|graphic| graphic.protocol.as_str() == "sixel")
    );

    terminal.process(b"\x1b[2;3;2;3${");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "DECSERA should remove non-Kitty graphics intersecting erased cells"
    );
    let remaining = &terminal.all_graphics()[0];
    assert_eq!(remaining.protocol.as_str(), "sixel");
    assert_eq!(remaining.position.1, 4);

    terminal.process(b"\x1b[5;3;5;3${");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "DECSERA should clear Sixel graphics intersecting erased cells"
    );
}

#[test]
fn parser_terminal_decsera_keeps_graphics_over_protected_cells() {
    let mut terminal = ParserTerminal::new(10, 6);
    let graphic = format!("\x1b[2;3H\x1b_Ga=T,f=32,s=1,v=1,i=743,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");

    terminal.process(b"\x1b[2;3H\x1b[1\"qX\x1b[0\"q");
    assert!(terminal.active_grid().get(2, 1).unwrap().flags.guarded());
    terminal.process(graphic.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b[2;3;2;3${");

    assert_eq!(
        terminal.graphics_count(),
        1,
        "DECSERA should not remove graphics when every intersecting cell is protected"
    );
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    let protected = terminal.active_grid().get(2, 1).unwrap();
    assert_eq!(protected.c, 'X');
    assert!(protected.flags.guarded());
}

#[test]
fn parser_terminal_c1_normalization_preserves_valid_utf8_text() {
    let mut terminal = ParserTerminal::new(80, 24);
    let text = "ok ✓ 😀";

    terminal.process(text.as_bytes());

    assert_eq!(terminal.active_grid().row_text(0).trim_end(), text);
}

#[test]
fn parser_terminal_keeps_emoji_tag_sequence_in_one_wide_cell() {
    let mut terminal = ParserTerminal::new(80, 24);
    let scotland_flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}";

    terminal.process(scotland_flag.as_bytes());
    terminal.process(b"X");

    let flag = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(flag.get_grapheme(), scotland_flag);
    assert_eq!(flag.width(), 2);
    assert!(
        flag.flags.wide_char(),
        "emoji tag sequence should occupy a wide leading cell"
    );
    assert!(
        terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "emoji tag sequence should reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{scotland_flag}X")
    );
}

#[test]
fn terminal_width_helpers_treat_emoji_tag_sequence_as_wide_cluster() {
    let scotland_flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}";

    assert_eq!(str_width(scotland_flag, &WidthConfig::default()), 2);

    let cell = Cell::from_grapheme(scotland_flag);
    assert_eq!(cell.get_grapheme(), scotland_flag);
    assert_eq!(cell.width(), 2);
}

#[test]
fn parser_terminal_keeps_dangling_emoji_tag_text_narrow() {
    let mut terminal = ParserTerminal::new(80, 24);
    let tagged_text = "a\u{E0067}";

    terminal.process(tagged_text.as_bytes());
    terminal.process(b"X");

    let cell = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(cell.get_grapheme(), tagged_text);
    assert_eq!(cell.width(), 1);
    assert!(
        !cell.flags.wide_char(),
        "dangling emoji tag characters must not force plain text wide"
    );
    assert!(
        !terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "dangling emoji tag characters must not reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(1, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{tagged_text}X")
    );
}

#[test]
fn terminal_width_helpers_keep_dangling_emoji_tag_text_narrow() {
    let tagged_text = "a\u{E0067}";

    assert_eq!(str_width(tagged_text, &WidthConfig::default()), 1);

    let cell = Cell::from_grapheme(tagged_text);
    assert_eq!(cell.get_grapheme(), tagged_text);
    assert_eq!(cell.width(), 1);
}

#[test]
fn parser_terminal_keeps_text_keycap_sequence_in_one_wide_cell() {
    let mut terminal = ParserTerminal::new(80, 24);
    let keycap = "1\u{20E3}";

    terminal.process(keycap.as_bytes());
    terminal.process(b"X");

    let cell = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(cell.get_grapheme(), keycap);
    assert_eq!(cell.width(), 2);
    assert!(
        cell.flags.wide_char(),
        "text keycap sequence should occupy a wide leading cell"
    );
    assert!(
        terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "text keycap sequence should reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{keycap}X")
    );
}

#[test]
fn terminal_width_helpers_treat_text_keycap_sequence_as_wide_cluster() {
    let keycap = "#\u{20E3}";

    assert_eq!(str_width(keycap, &WidthConfig::default()), 2);

    let cell = Cell::from_grapheme(keycap);
    assert_eq!(cell.get_grapheme(), keycap);
    assert_eq!(cell.width(), 2);
}

#[test]
fn parser_terminal_keeps_text_presentation_variation_selector_narrow() {
    let mut terminal = ParserTerminal::new(80, 24);
    let text_airplane = "\u{2708}\u{FE0E}";

    terminal.process(text_airplane.as_bytes());
    terminal.process(b"X");

    let airplane = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(airplane.get_grapheme(), text_airplane);
    assert_eq!(airplane.width(), 1);
    assert!(
        !airplane.flags.wide_char(),
        "VS15 text presentation should not force emoji-width rendering"
    );
    assert!(
        !terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "VS15 text presentation should not reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(1, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{text_airplane}X")
    );
}

#[test]
fn parser_terminal_keeps_private_use_nerd_font_icons_narrow() {
    let mut terminal = ParserTerminal::new(80, 24);
    let powerline_separator = '\u{E0B0}';
    let supplementary_nerd_icon = '\u{F08C7}';
    let text = format!("{powerline_separator}{supplementary_nerd_icon}a");

    terminal.process(text.as_bytes());

    let powerline = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(powerline.c, powerline_separator);
    assert_eq!(powerline.width(), 1);
    assert!(!powerline.flags.wide_char());

    let nerd_icon = terminal.active_grid().get(1, 0).unwrap();
    assert_eq!(nerd_icon.c, supplementary_nerd_icon);
    assert_eq!(nerd_icon.width(), 1);
    assert!(!nerd_icon.flags.wide_char());

    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'a');
    assert_eq!(terminal.cursor().col, 3);
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), text);
}

#[test]
fn terminal_width_helpers_keep_private_use_nerd_font_icons_narrow() {
    let powerline_separator = "\u{E0B0}";
    let supplementary_nerd_icon = "\u{F08C7}";

    assert_eq!(str_width(powerline_separator, &WidthConfig::default()), 1);
    assert_eq!(
        str_width(supplementary_nerd_icon, &WidthConfig::default()),
        1
    );

    let powerline = Cell::from_grapheme(powerline_separator);
    assert_eq!(powerline.get_grapheme(), powerline_separator);
    assert_eq!(powerline.width(), 1);

    let nerd_icon = Cell::from_grapheme(supplementary_nerd_icon);
    assert_eq!(nerd_icon.get_grapheme(), supplementary_nerd_icon);
    assert_eq!(nerd_icon.width(), 1);
}

#[test]
fn session_frame_diff_keeps_private_use_nerd_font_icons_narrow() {
    let session_id =
        session::create_session(&serde_json::to_string(&nerd_font_icons_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "NF:");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let expected = "NF:\u{E0B0}\u{F08C7}Z";

    assert_eq!(
        frame_row_at_index(&parsed, 0)["text"]
            .as_str()
            .unwrap_or_default()
            .trim_end(),
        expected
    );
    assert_eq!(
        parsed["cursor"]["col"].as_u64(),
        Some(6),
        "private-use icons should each advance by one cell in frame diff: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_serializes_complex_grapheme_styles_in_terminal_columns() {
    let session_id =
        session::create_session(&serde_json::to_string(&complex_grapheme_style_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_where(session_id, |frame| {
        frame.contains("A") && frame.contains("D") && frame.contains("#ff0000")
    });
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let row = frame_row_at_index(&parsed, 0);
    let expected = "A\u{2708}\u{FE0F}B\u{1F468}\u{200D}\u{1F4BB}C1\u{FE0F}\u{20E3}D";

    assert_eq!(
        row["text"].as_str().unwrap_or_default().trim_end(),
        expected
    );
    assert_eq!(
        parsed["cursor"]["col"].as_u64(),
        Some(10),
        "emoji-width graphemes should advance the frame cursor by terminal columns: {frame}"
    );

    let style_runs = row["style_runs"].as_array().expect("expected style runs");
    let styled_columns = ["#ff0000", "#00ff00", "#0000ff"]
        .into_iter()
        .map(|foreground| {
            let run = style_runs
                .iter()
                .find(|run| run["foreground"].as_str() == Some(foreground))
                .unwrap_or_else(|| panic!("missing style run for {foreground}: {frame}"));
            (
                foreground,
                run["start"].as_u64().unwrap(),
                run["end"].as_u64().unwrap(),
            )
        })
        .collect::<Vec<_>>();

    assert_eq!(
        styled_columns,
        vec![("#ff0000", 1, 3), ("#00ff00", 4, 6), ("#0000ff", 7, 9)],
        "style runs should use terminal columns across wide graphemes: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_wraps_wide_grapheme_cluster_at_right_edge() {
    let session_id = session::create_session(
        &serde_json::to_string(&wide_grapheme_right_edge_profile()).unwrap(),
    )
    .unwrap();
    session::resize_session(session_id, 2, 4, 0, 0).unwrap();

    let flag = "\u{1F1FA}\u{1F1F8}";
    let frame = wait_for_frame_where(session_id, |frame| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(frame) else {
            return false;
        };
        parsed["viewport_cols"].as_u64() == Some(2)
            && frame_row_at_index(&parsed, 2)["text"]
                .as_str()
                .is_some_and(|text| text.trim_end() == "B")
    });
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(
        frame_row_at_index(&parsed, 0)["text"]
            .as_str()
            .unwrap_or_default()
            .trim_end(),
        "A",
        "wide grapheme should wrap before the right edge instead of overwriting row 0: {frame}"
    );
    assert_eq!(
        frame_row_at_index(&parsed, 1)["text"]
            .as_str()
            .unwrap_or_default()
            .trim_end(),
        flag,
        "regional flag pair should stay one grapheme on the wrapped row: {frame}"
    );
    assert_eq!(
        frame_row_at_index(&parsed, 2)["text"]
            .as_str()
            .unwrap_or_default()
            .trim_end(),
        "B",
        "text after the full-width flag should continue after the reserved continuation cell: {frame}"
    );
    assert_eq!(
        logical_rows_from_frame(&frame)
            .into_iter()
            .filter(|row| !row.is_empty())
            .collect::<Vec<_>>(),
        vec![format!("A{flag}B")],
        "non-empty logical rows should reassemble the wrapped wide cluster without fragments: {frame}"
    );
    assert_eq!(
        parsed["cursor"]["row"].as_u64(),
        Some(2),
        "cursor row should reflect the wide-cluster wrap and following text: {frame}"
    );
    assert_eq!(
        parsed["cursor"]["col"].as_u64(),
        Some(1),
        "cursor column should advance one cell after trailing text: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn parser_terminal_keeps_plain_text_variation_selectors_narrow() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.set_width_config(WidthConfig::cjk());
    let plain_vs16 = "a\u{FE0F}";
    let private_use_vs16 = "\u{E0B0}\u{FE0F}";

    terminal.process(format!("{plain_vs16}{private_use_vs16}X").as_bytes());

    let text_cell = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(text_cell.get_grapheme(), plain_vs16);
    assert_eq!(text_cell.width(), 1);
    assert!(!text_cell.flags.wide_char());

    let private_use_cell = terminal.active_grid().get(1, 0).unwrap();
    assert_eq!(private_use_cell.get_grapheme(), private_use_vs16);
    assert_eq!(private_use_cell.width(), 1);
    assert!(!private_use_cell.flags.wide_char());

    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    for col in 0..3 {
        assert!(
            !terminal
                .active_grid()
                .get(col, 0)
                .unwrap()
                .flags
                .wide_char_spacer(),
            "plain text variation selector should not leave a spacer at column {col}"
        );
    }
}

#[test]
fn terminal_width_helpers_ignore_plain_text_variation_selectors() {
    let plain_vs16 = "a\u{FE0F}";
    let plain_vs15 = "a\u{FE0E}";
    let private_use_vs16 = "\u{E0B0}\u{FE0F}";

    assert_eq!(str_width(plain_vs16, &WidthConfig::default()), 1);
    assert_eq!(str_width(plain_vs16, &WidthConfig::cjk()), 1);
    assert_eq!(str_width(plain_vs15, &WidthConfig::cjk()), 1);
    assert_eq!(str_width(private_use_vs16, &WidthConfig::default()), 1);

    let plain_cell = Cell::from_grapheme(plain_vs16);
    assert_eq!(plain_cell.get_grapheme(), plain_vs16);
    assert_eq!(plain_cell.width(), 1);
}

#[test]
fn terminal_width_helpers_keep_common_emoji_variation_bases_wide() {
    for grapheme in ["\u{00A9}\u{FE0F}", "\u{2194}\u{FE0F}"] {
        assert_eq!(str_width(grapheme, &WidthConfig::default()), 2);

        let cell = Cell::from_grapheme(grapheme);
        assert_eq!(cell.get_grapheme(), grapheme);
        assert_eq!(cell.width(), 2);
    }
}

#[test]
fn parser_terminal_recalculates_combining_grapheme_with_cjk_width_config() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.set_width_config(WidthConfig::cjk());

    terminal.process("e\u{0301}".as_bytes());
    terminal.process(b"X");

    let composed = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(composed.get_grapheme(), "\u{00E9}");
    assert_eq!(composed.width(), 2);
    assert!(
        composed.flags.wide_char(),
        "NFC-composed ambiguous grapheme should use the active CJK width config"
    );
    assert!(
        terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "NFC-composed ambiguous grapheme should reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "\u{00E9}X");
}

#[test]
fn parser_terminal_wraps_cjk_ambiguous_combining_grapheme_that_becomes_wide_at_right_edge() {
    let mut terminal = ParserTerminal::new(2, 4);
    terminal.set_width_config(WidthConfig::cjk());

    terminal.process("Ae\u{0301}X".as_bytes());

    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "A");
    assert_eq!(terminal.active_grid().row_text(1).trim_end(), "\u{00E9}");
    let composed = terminal.active_grid().get(0, 1).unwrap();
    assert_eq!(composed.get_grapheme(), "\u{00E9}");
    assert_eq!(composed.width(), 2);
    assert!(
        composed.flags.wide_char(),
        "CJK-ambiguous composed grapheme should become wide after NFC normalization"
    );
    assert!(
        terminal
            .active_grid()
            .get(1, 1)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "widened CJK-ambiguous grapheme should reserve a spacer after wrapping"
    );
    assert_eq!(terminal.active_grid().row_text(2).trim_end(), "X");
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "A",
        "the old right-edge narrow base cell should be cleared after wrap"
    );
}

#[test]
fn parser_terminal_wraps_grapheme_that_becomes_wide_at_right_edge() {
    let mut terminal = ParserTerminal::new(2, 4);
    let airplane_emoji = "✈️";

    terminal.process(format!("A{airplane_emoji}B").as_bytes());

    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "A");
    assert_eq!(
        terminal.active_grid().row_text(1).trim_end(),
        airplane_emoji
    );
    let emoji = terminal.active_grid().get(0, 1).unwrap();
    assert_eq!(emoji.get_grapheme(), airplane_emoji);
    assert_eq!(emoji.width(), 2);
    assert!(emoji.flags.wide_char());
    assert!(
        terminal
            .active_grid()
            .get(1, 1)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "widened grapheme should reserve a spacer after wrapping"
    );
    assert_eq!(terminal.active_grid().row_text(2).trim_end(), "B");
}

#[test]
fn parser_terminal_widened_grapheme_clears_displaced_wide_neighbor_fragment() {
    let mut terminal = ParserTerminal::new(8, 4);

    terminal.process("✈中Z".as_bytes());
    terminal.process(b"\x1b[1;2H");
    terminal.process("\u{FE0F}".as_bytes());

    let airplane = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(airplane.get_grapheme(), "✈️");
    assert_eq!(airplane.width(), 2);
    assert!(airplane.flags.wide_char());
    assert!(
        terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "widened grapheme should replace the displaced wide neighbor with its own spacer"
    );

    let cleared_old_spacer = terminal.active_grid().get(2, 0).unwrap();
    assert_eq!(cleared_old_spacer.c, ' ');
    assert!(!cleared_old_spacer.flags.wide_char());
    assert!(
        !cleared_old_spacer.flags.wide_char_spacer(),
        "old displaced wide neighbor spacer must not survive as a dangling fragment"
    );
    assert_eq!(terminal.active_grid().get(3, 0).unwrap().c, 'Z');
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "✈️ Z");
}

#[test]
fn parser_terminal_wraps_regional_flag_that_becomes_wide_at_right_edge() {
    let mut terminal = ParserTerminal::new(2, 4);
    let flag = "🇺🇸";

    terminal.process(format!("A{flag}B").as_bytes());

    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "A");
    assert_eq!(terminal.active_grid().row_text(1).trim_end(), flag);
    let flag_cell = terminal.active_grid().get(0, 1).unwrap();
    assert_eq!(flag_cell.get_grapheme(), flag);
    assert_eq!(flag_cell.width(), 2);
    assert!(flag_cell.flags.wide_char());
    assert!(
        terminal
            .active_grid()
            .get(1, 1)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "flag pair should reserve a spacer after wrapping"
    );
    assert_eq!(terminal.active_grid().row_text(2).trim_end(), "B");
}

#[test]
fn parser_terminal_keeps_non_latin_combining_mark_with_base_cell() {
    let mut terminal = ParserTerminal::new(80, 24);
    let hebrew_shin_with_dot = "ש\u{05C1}";

    terminal.process(hebrew_shin_with_dot.as_bytes());
    terminal.process(b"X");

    let composed = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(composed.get_grapheme(), hebrew_shin_with_dot);
    assert_eq!(composed.width(), 1);
    assert!(!composed.flags.wide_char());
    assert_eq!(terminal.active_grid().get(1, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{hebrew_shin_with_dot}X")
    );
}

#[test]
fn parser_terminal_keeps_plain_text_zwj_sequence_narrow() {
    let mut terminal = ParserTerminal::new(80, 24);
    let plain_text_zwj = "a\u{200D}";

    terminal.process(plain_text_zwj.as_bytes());
    terminal.process(b"bX");

    let joined = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(joined.get_grapheme(), plain_text_zwj);
    assert_eq!(joined.width(), 1);
    assert!(
        !joined.flags.wide_char(),
        "plain text joined by ZWJ should not reserve emoji width"
    );
    assert!(
        !terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "plain text ZWJ should not leave a wide-character spacer"
    );
    assert_eq!(terminal.active_grid().get(1, 0).unwrap().c, 'b');
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    assert_eq!(terminal.cursor().col, 3);
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{plain_text_zwj}bX")
    );
}

#[test]
fn parser_terminal_keeps_zero_width_format_controls_with_base_cell() {
    let mut terminal = ParserTerminal::new(80, 24);
    let zero_width_formats = "\u{200B}\u{200C}\u{200E}\u{2060}\u{FEFF}";
    let formatted_text = format!("a{zero_width_formats}");

    terminal.process(formatted_text.as_bytes());
    terminal.process(b"bX");

    let joined = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(joined.get_grapheme(), formatted_text);
    assert_eq!(joined.width(), 1);
    assert!(
        !joined.flags.wide_char(),
        "zero-width format controls should not force wide-cell rendering"
    );
    assert!(
        !terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "zero-width format controls should not reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(1, 0).unwrap().c, 'b');
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    assert_eq!(terminal.cursor().col, 3);
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{formatted_text}bX")
    );
}

#[test]
fn terminal_width_helpers_ignore_zero_width_format_controls() {
    let zero_width_formats = "\u{00AD}\u{200B}\u{200C}\u{200E}\u{2060}\u{FEFF}\u{1BCA0}\u{E0001}";
    let formatted_text = format!("a{zero_width_formats}");

    assert_eq!(str_width(zero_width_formats, &WidthConfig::default()), 0);
    assert_eq!(str_width(&formatted_text, &WidthConfig::default()), 1);
    assert_eq!(
        str_width(&format!("{formatted_text}b"), &WidthConfig::default()),
        2
    );

    let cell = Cell::from_grapheme(&formatted_text);
    assert_eq!(cell.get_grapheme(), formatted_text);
    assert_eq!(cell.width(), 1);
}

#[test]
fn parser_terminal_keeps_emoji_zwj_sequence_in_one_wide_cell() {
    let mut terminal = ParserTerminal::new(80, 24);
    let technologist = "👩\u{200D}💻";

    terminal.process(technologist.as_bytes());
    terminal.process(b"X");

    let emoji = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(emoji.get_grapheme(), technologist);
    assert_eq!(emoji.width(), 2);
    assert!(
        emoji.flags.wide_char(),
        "emoji ZWJ sequence should occupy a wide leading cell"
    );
    assert!(
        terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "emoji ZWJ sequence should reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{technologist}X")
    );
}

#[test]
fn parser_terminal_wraps_vs16_emoji_zwj_sequence_from_right_edge() {
    let mut terminal = ParserTerminal::new(2, 4);
    let rainbow_flag = "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}";

    terminal.process(format!("A{rainbow_flag}B").as_bytes());

    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "A");
    assert_eq!(terminal.active_grid().row_text(1).trim_end(), rainbow_flag);
    let flag = terminal.active_grid().get(0, 1).unwrap();
    assert_eq!(flag.get_grapheme(), rainbow_flag);
    assert_eq!(flag.width(), 2);
    assert!(
        flag.flags.wide_char(),
        "VS16 emoji ZWJ sequence should stay a wide leading cell after right-edge wrap"
    );
    assert!(
        terminal
            .active_grid()
            .get(1, 1)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "wrapped VS16 emoji ZWJ sequence should reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().row_text(2).trim_end(), "B");
    assert!(terminal.active_grid().is_line_wrapped(0));
    assert!(terminal.active_grid().is_line_wrapped(1));
    assert_eq!(
        [
            terminal.active_grid().row_text(0).trim_end(),
            terminal.active_grid().row_text(1).trim_end(),
            terminal.active_grid().row_text(2).trim_end(),
        ]
        .join(""),
        format!("A{rainbow_flag}B"),
        "logical rows should reassemble the wrapped rainbow flag without splitting the ZWJ sequence"
    );
}

#[test]
fn parser_terminal_keeps_multi_emoji_zwj_sequence_in_one_wide_cell() {
    let mut terminal = ParserTerminal::new(80, 24);
    let family = "👨\u{200D}👩\u{200D}👧\u{200D}👦";

    terminal.process(family.as_bytes());
    terminal.process(b"X");

    let emoji = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(emoji.get_grapheme(), family);
    assert_eq!(emoji.width(), 2);
    assert!(
        emoji.flags.wide_char(),
        "multi-codepoint emoji ZWJ sequence should occupy a wide leading cell"
    );
    assert!(
        terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "multi-codepoint emoji ZWJ sequence should reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{family}X")
    );
}

#[test]
fn parser_terminal_keeps_emoji_skin_tone_sequence_in_one_wide_cell() {
    let mut terminal = ParserTerminal::new(80, 24);
    let waving_hand_medium_skin_tone = "👋🏽";

    terminal.process(waving_hand_medium_skin_tone.as_bytes());
    terminal.process(b"X");

    let emoji = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(emoji.get_grapheme(), waving_hand_medium_skin_tone);
    assert_eq!(emoji.width(), 2);
    assert!(
        emoji.flags.wide_char(),
        "emoji skin tone sequence should occupy a wide leading cell"
    );
    assert!(
        terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "emoji skin tone sequence should reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{waving_hand_medium_skin_tone}X")
    );
}

#[test]
fn parser_terminal_keeps_emoji_modifier_zwj_sequence_in_one_wide_cell() {
    let mut terminal = ParserTerminal::new(80, 24);
    let technologist_medium_skin_tone = "🧑🏽\u{200D}💻";

    terminal.process(technologist_medium_skin_tone.as_bytes());
    terminal.process(b"X");

    let emoji = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(emoji.get_grapheme(), technologist_medium_skin_tone);
    assert_eq!(emoji.width(), 2);
    assert!(
        emoji.flags.wide_char(),
        "emoji modifier ZWJ sequence should occupy a wide leading cell"
    );
    assert!(
        terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "emoji modifier ZWJ sequence should reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{technologist_medium_skin_tone}X")
    );
}

#[test]
fn parser_terminal_keeps_plain_text_skin_tone_modifier_narrow() {
    let mut terminal = ParserTerminal::new(80, 24);
    let plain_text_skin_tone = "a🏽";

    terminal.process(plain_text_skin_tone.as_bytes());
    terminal.process(b"X");

    let text = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(text.get_grapheme(), plain_text_skin_tone);
    assert_eq!(text.width(), 1);
    assert!(
        !text.flags.wide_char(),
        "skin tone modifiers must not force non-emoji text to emoji width"
    );
    assert!(
        !terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer(),
        "plain text skin tone modifiers must not reserve a continuation cell"
    );
    assert_eq!(terminal.active_grid().get(1, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{plain_text_skin_tone}X")
    );
}

#[test]
fn terminal_width_helpers_treat_emoji_skin_tone_sequence_as_wide_cluster() {
    let thumbs_up_dark_skin_tone = "👍🏿";

    assert_eq!(
        str_width(thumbs_up_dark_skin_tone, &WidthConfig::default()),
        2
    );

    let cell = Cell::from_grapheme(thumbs_up_dark_skin_tone);
    assert_eq!(cell.get_grapheme(), thumbs_up_dark_skin_tone);
    assert_eq!(cell.width(), 2);
}

#[test]
fn terminal_width_helpers_treat_emoji_modifier_zwj_sequence_as_wide_cluster() {
    let technologist_medium_skin_tone = "🧑🏽\u{200D}💻";

    assert_eq!(
        str_width(technologist_medium_skin_tone, &WidthConfig::default()),
        2
    );

    let cell = Cell::from_grapheme(technologist_medium_skin_tone);
    assert_eq!(cell.get_grapheme(), technologist_medium_skin_tone);
    assert_eq!(cell.width(), 2);
}

#[test]
fn terminal_width_helpers_keep_plain_text_skin_tone_modifier_narrow() {
    let plain_text_skin_tone = "a🏽";

    assert_eq!(str_width(plain_text_skin_tone, &WidthConfig::default()), 1);
    assert_eq!(str_width("\u{1F3FD}", &WidthConfig::default()), 0);

    let cell = Cell::from_grapheme(plain_text_skin_tone);
    assert_eq!(cell.get_grapheme(), plain_text_skin_tone);
    assert_eq!(cell.width(), 1);
}

#[test]
fn parser_terminal_attaches_variation_selector_supplement_to_base_cell() {
    let mut terminal = ParserTerminal::new(80, 24);
    let ideographic_variant = "字\u{E0100}";

    terminal.process(ideographic_variant.as_bytes());
    terminal.process(b"X");

    let ideograph = terminal.active_grid().get(0, 0).unwrap();
    assert_eq!(ideograph.get_grapheme(), ideographic_variant);
    assert_eq!(ideograph.width(), 2);
    assert!(ideograph.flags.wide_char());
    assert!(
        terminal
            .active_grid()
            .get(1, 0)
            .unwrap()
            .flags
            .wide_char_spacer()
    );
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'X');
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("{ideographic_variant}X")
    );
}

#[test]
fn parser_terminal_dch_at_wide_spacer_deletes_whole_grapheme() {
    let mut terminal = ParserTerminal::new(12, 4);

    terminal.process("A中BC".as_bytes());
    terminal.process(b"\x1b[1;3H\x1b[P");

    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "ABC");
    assert_eq!(terminal.active_grid().get(1, 0).unwrap().c, 'B');
    assert!(!terminal.active_grid().get(1, 0).unwrap().flags.wide_char());
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, 'C');
    assert!(
        !terminal
            .active_grid()
            .get(2, 0)
            .unwrap()
            .flags
            .wide_char_spacer()
    );
}

#[test]
fn parser_terminal_ech_at_wide_spacer_erases_whole_grapheme() {
    let mut terminal = ParserTerminal::new(12, 4);

    terminal.process("A中B".as_bytes());
    terminal.process(b"\x1b[1;3H\x1b[X");

    assert_eq!(terminal.active_grid().get(0, 0).unwrap().c, 'A');
    assert_eq!(terminal.active_grid().get(1, 0).unwrap().c, ' ');
    assert_eq!(terminal.active_grid().get(2, 0).unwrap().c, ' ');
    assert!(!terminal.active_grid().get(1, 0).unwrap().flags.wide_char());
    assert!(
        !terminal
            .active_grid()
            .get(2, 0)
            .unwrap()
            .flags
            .wide_char_spacer()
    );
    assert_eq!(terminal.active_grid().get(3, 0).unwrap().c, 'B');
}

#[test]
fn parser_terminal_ich_at_wide_spacer_leaves_no_wide_fragments() {
    let mut terminal = ParserTerminal::new(12, 4);

    terminal.process("A中BC".as_bytes());
    terminal.process(b"\x1b[1;3H\x1b[@");

    for col in 0..terminal.active_grid().cols() {
        let cell = terminal.active_grid().get(col, 0).unwrap();
        assert!(
            !cell.flags.wide_char() && !cell.flags.wide_char_spacer(),
            "ICH should not leave a wide-character fragment at column {col}"
        );
    }
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "A   BC");
}

#[test]
fn parser_terminal_plain_ascii_overwrites_wide_lead_without_fragment() {
    let mut terminal = ParserTerminal::new(12, 4);

    terminal.process("A中B".as_bytes());
    terminal.process(b"\x1b[1;2H");
    terminal.process(b"X");

    assert_eq!(terminal.active_grid().get(0, 0).unwrap().c, 'A');
    let replacement = terminal.active_grid().get(1, 0).unwrap();
    assert_eq!(replacement.c, 'X');
    assert!(!replacement.flags.wide_char());
    assert!(!replacement.flags.wide_char_spacer());

    let cleared_spacer = terminal.active_grid().get(2, 0).unwrap();
    assert_eq!(cleared_spacer.c, ' ');
    assert!(!cleared_spacer.flags.wide_char());
    assert!(!cleared_spacer.flags.wide_char_spacer());
    assert_eq!(terminal.active_grid().get(3, 0).unwrap().c, 'B');
}

#[test]
fn parser_terminal_plain_ascii_overwrites_wide_spacer_without_fragment() {
    let mut terminal = ParserTerminal::new(12, 4);

    terminal.process("A中B".as_bytes());
    terminal.process(b"\x1b[1;3H");
    terminal.process(b"X");

    assert_eq!(terminal.active_grid().get(0, 0).unwrap().c, 'A');
    let cleared_lead = terminal.active_grid().get(1, 0).unwrap();
    assert_eq!(cleared_lead.c, ' ');
    assert!(!cleared_lead.flags.wide_char());
    assert!(!cleared_lead.flags.wide_char_spacer());

    let replacement = terminal.active_grid().get(2, 0).unwrap();
    assert_eq!(replacement.c, 'X');
    assert!(!replacement.flags.wide_char());
    assert!(!replacement.flags.wide_char_spacer());
    assert_eq!(terminal.active_grid().get(3, 0).unwrap().c, 'B');
}

#[test]
fn parser_terminal_narrow_unicode_overwrites_wide_lead_without_fragment() {
    let mut terminal = ParserTerminal::new(12, 4);

    terminal.process("A中B".as_bytes());
    terminal.process(b"\x1b[1;2H");
    terminal.process("é".as_bytes());

    assert_eq!(terminal.active_grid().get(0, 0).unwrap().c, 'A');
    let replacement = terminal.active_grid().get(1, 0).unwrap();
    assert_eq!(replacement.c, 'é');
    assert!(!replacement.flags.wide_char());
    assert!(!replacement.flags.wide_char_spacer());

    let cleared_spacer = terminal.active_grid().get(2, 0).unwrap();
    assert_eq!(cleared_spacer.c, ' ');
    assert!(!cleared_spacer.flags.wide_char());
    assert!(!cleared_spacer.flags.wide_char_spacer());
    assert_eq!(terminal.active_grid().get(3, 0).unwrap().c, 'B');
}

#[test]
fn parser_terminal_applies_quiet_kitty_delete_without_replacement() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let first = format!("\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);

    terminal.process(b"\x1b[?2026h\x1b[20;2HShutting down...\x1b[?2026l");
    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 0);
}

#[test]
fn parser_terminal_reuses_render_id_for_quiet_kitty_replacement() {
    let mut terminal = ParserTerminal::new(80, 24);
    const RED_RGBA_BASE64: &str = "/wAA/w==";

    let first = format!("\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=1;{RED_RGBA_BASE64}\x1b\\");
    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;

    terminal.process(b"\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);

    terminal.process(b"\x1b_Ga=T,f=32,s=1,v=1,i=49374,q=2;AP8A/w==\x1b\\");

    assert_eq!(terminal.deferred_kitty_delete_count(), 0);
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].id, first_graphic_id);
    assert_eq!(
        terminal.all_graphics()[0].pixels.as_ref(),
        &[0, 255, 0, 255]
    );
}

#[test]
fn parser_terminal_handles_codex_style_kitty_pet_png_sequence() {
    let mut terminal = ParserTerminal::new(112, 43);
    let sequence = format!(
        "\x1b_Ga=d,d=I,i=49374,q=2;\x1b\\\x1b7\x1b[14;85H\x1b_Ga=T,t=d,f=100,c=9,r=5,q=2,i=49374;{}\x1b\\\x1b8",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(sequence.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.kitty_image_id, Some(49374));
    assert_eq!(graphic.kitty_placement_id, Some(0));
    assert_eq!(graphic.position, (84, 13));
    assert_eq!(graphic.placement.columns, Some(9));
    assert_eq!(graphic.placement.rows, Some(5));
    assert!(terminal.drain_responses().is_empty());
}

fn long_private_mode_params_with_2026() -> String {
    [
        "1000", "1002", "1006", "1007", "1004", "2004", "1", "7", "25", "69", "9", "1005", "1015",
        "1016", "2026",
    ]
    .join(";")
}

#[test]
fn parser_terminal_buffers_synchronized_update_remainder_in_same_chunk() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden");

    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"-shown\x1b[?2026l");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn parser_terminal_buffers_synchronized_update_after_long_multi_mode_enable() {
    let mut terminal = ParserTerminal::new(80, 24);
    let params = long_private_mode_params_with_2026();
    let sequence = format!("before\x1b[?{params}hhidden");

    terminal.process(sequence.as_bytes());

    assert!(terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "before",
        "long DECSET parameter lists must still hide same-chunk synchronized output"
    );

    terminal.process(b"-shown\x1b[?2026l");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn parser_terminal_buffers_synchronized_update_remainder_after_split_enable() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2");
    terminal.process(b"026hhidden");

    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"-shown\x1b[?2026l");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn parser_terminal_buffers_synchronized_update_remainder_after_multi_split_enable() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b");
    terminal.process(b"[?202");
    terminal.process(b"6hhidden");

    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"-shown\x1b[?2026l");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn parser_terminal_buffers_synchronized_update_remainder_when_2026_is_not_first_mode() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?25;2026hhidden");

    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"-shown\x1b[?2026l");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn parser_terminal_buffers_synchronized_update_after_c1_csi_enable() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x9b?2026hhidden");

    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"-shown\x9b?2026l");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-shown"
    );
}

#[test]
fn parser_terminal_flushes_synchronized_update_that_starts_and_ends_in_same_chunk() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden\x1b[?2026l-after");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-after"
    );
}

#[test]
fn parser_terminal_flushes_synchronized_update_when_2026_is_not_first_reset_mode() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden");
    terminal.process(b"-shown\x1b[?25;2026l-after");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-shown-after"
    );
}

#[test]
fn parser_terminal_flushes_synchronized_update_after_long_multi_mode_disable() {
    let mut terminal = ParserTerminal::new(80, 24);
    let params = long_private_mode_params_with_2026();

    terminal.process(b"before\x1b[?2026hhidden");
    terminal.process(format!("-shown\x1b[?{params}l-after").as_bytes());

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-shown-after",
        "long DECRST parameter lists must flush synchronized output without waiting for timeout"
    );
}

#[test]
fn parser_terminal_does_not_flush_synchronized_update_for_osc_embedded_disable() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden\x1b]0;fake-\x1b[?2026l-title\x07still");

    assert!(
        terminal.synchronized_updates(),
        "OSC payload bytes that look like DEC 2026 reset must not end synchronized output"
    );
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"-shown\x1b[?2026l-after");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-titlestill-shown-after"
    );
}

#[test]
fn parser_terminal_does_not_flush_synchronized_update_for_st_control_string_embedded_disable() {
    for (name, start, end) in [
        ("DCS", b"\x1bP".as_slice(), b"\x1b\\".as_slice()),
        ("SOS", b"\x1bX".as_slice(), b"\x1b\\".as_slice()),
        ("PM", b"\x1b^".as_slice(), b"\x1b\\".as_slice()),
        ("APC", b"\x1b_".as_slice(), b"\x1b\\".as_slice()),
    ] {
        let mut terminal = ParserTerminal::new(80, 24);

        terminal.process(b"before\x1b[?2026hhidden");
        terminal.process(start);
        terminal.process(b"not-sync-\x1b[?2026l");
        terminal.process(end);
        terminal.process(b"still");

        assert!(
            terminal.synchronized_updates(),
            "{name} payload bytes that look like DEC 2026 reset must not end synchronized output"
        );
        assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

        terminal.process(b"-shown\x1b[?2026l-after");

        assert!(!terminal.synchronized_updates());
        assert_eq!(
            terminal.active_grid().row_text(0).trim_end(),
            "beforehiddenstill-shown-after",
            "{name} payload should not flush synchronized output before its real DEC 2026 reset"
        );
    }
}

#[test]
fn parser_terminal_does_not_flush_synchronized_update_for_split_dcs_embedded_disable() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden\x1bPnot-sync-\x1b");

    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"[?2026l\x1b\\still");

    assert!(
        terminal.synchronized_updates(),
        "split DCS payload bytes that look like DEC 2026 reset must not end synchronized output"
    );
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"-shown\x1b[?2026l-after");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehiddenstill-shown-after"
    );
}

#[test]
fn parser_terminal_flushes_synchronized_update_after_split_multi_mode_disable() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden\x1b[?25;20");
    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"26l-after");

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        "beforehidden-after"
    );
}

#[test]
fn parser_terminal_flushes_synchronized_update_with_long_trailing_remainder() {
    let mut terminal = ParserTerminal::new(80, 24);
    let trailing = "x".repeat(64);
    let update = format!("hidden\x1b[?2026l{trailing}");

    terminal.process(b"before\x1b[?2026h");
    terminal.process(update.as_bytes());

    assert!(!terminal.synchronized_updates());
    assert_eq!(
        terminal.active_grid().row_text(0).trim_end(),
        format!("beforehidden{trailing}")
    );
}

#[test]
fn parser_terminal_timeout_ignores_nested_sync_enable_while_flushing_stale_buffer() {
    let mut nested = ParserTerminal::new(80, 24);
    let mut reset_then_nested = ParserTerminal::new(80, 24);

    nested.process(b"before\x1b[?2026hhidden\x1b[?2026hnested");
    reset_then_nested.process(b"before\x1b[?2026hhidden\x1bcafter\x1b[?2026hnested");

    thread::sleep(Duration::from_millis(1100));

    assert!(nested.flush_synchronized_updates_if_timed_out());
    assert!(!nested.synchronized_updates());
    assert_eq!(
        nested.active_grid().row_text(0).trim_end(),
        "beforehiddennested"
    );

    assert!(reset_then_nested.flush_synchronized_updates_if_timed_out());
    assert!(!reset_then_nested.synchronized_updates());
    assert_eq!(
        reset_then_nested.active_grid().row_text(0).trim_end(),
        "afternested"
    );
}

#[test]
fn parser_terminal_does_not_buffer_split_non_sync_private_mode() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2");
    terminal.process(b"5hshown");

    assert!(!terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "beforeshown");
}

#[test]
fn parser_terminal_flushes_synchronized_update_on_hard_reset() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden");

    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"\x1bcafter");

    assert!(!terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "after");
}

#[test]
fn parser_terminal_flushes_synchronized_update_on_split_hard_reset() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden\x1b");

    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"cafter");

    assert!(!terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "after");
}

#[test]
fn parser_terminal_does_not_flush_sync_update_for_osc_embedded_hard_reset() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden\x1b]0;not-a-reset-\x1bctitle\x07");

    assert!(
        terminal.synchronized_updates(),
        "OSC payload bytes that look like RIS must not end synchronized output"
    );
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"-shown\x1b[?2026l");

    assert!(!terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "title-shown");
}

#[test]
fn parser_terminal_does_not_flush_sync_update_for_split_osc_embedded_hard_reset() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden\x1b]0;not-a-reset-\x1b");

    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"ctitle\x07-shown");

    assert!(
        terminal.synchronized_updates(),
        "split OSC payload bytes that look like RIS must not end synchronized output"
    );
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    terminal.process(b"\x1b[?2026l");

    assert!(!terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "title-shown");
}

#[test]
fn parser_terminal_handles_screen_wrapped_iterm_graphics() {
    let mut terminal = ParserTerminal::new(80, 24);
    let wrapped = format!(
        "\x1bP\x1b]1337;File=inline=1:{}\x07\x1b\\",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(wrapped.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn parser_terminal_handles_screen_wrapped_kitty_graphics() {
    let mut terminal = ParserTerminal::new(80, 24);
    let wrapped = format!("\x1bP\x1b_Ga=T,f=32,s=1,v=1,i=12;{RED_RGBA_BASE64}\x1b\\\x1b\\");

    terminal.process(wrapped.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.kitty_image_id, Some(12));
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b_Gi=12;OK\x1b\\"
    );
}

#[test]
fn parser_terminal_buffers_split_screen_wrapped_kitty_graphics() {
    let mut terminal = ParserTerminal::new(80, 24);
    let wrapped = format!("\x1bP\x1b_Ga=T,f=32,s=1,v=1,i=13;{RED_RGBA_BASE64}\x1b\\\x1b\\");
    let (head, tail) = wrapped.as_bytes().split_at(wrapped.len() - 4);

    terminal.process(head);

    assert_eq!(terminal.graphics_count(), 0);
    assert!(terminal.drain_responses().is_empty());

    terminal.process(tail);

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.kitty_image_id, Some(13));
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b_Gi=13;OK\x1b\\"
    );
}

#[test]
fn parser_terminal_handles_screen_wrapped_sixel_graphics() {
    let mut terminal = ParserTerminal::new(80, 24);
    let wrapped = "\x1bP\x1bPq#1;2;100;0;0@\x1b\\\x1b\\";

    terminal.process(wrapped.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(&graphic.pixels[0..4], &[255, 0, 0, 255]);
}

#[test]
fn parser_terminal_iterm_inline_image_accepts_wrapped_base64() {
    let mut terminal = ParserTerminal::new(80, 24);
    let wrapped_base64 = RED_PIXEL_PNG_BASE64
        .as_bytes()
        .chunks(16)
        .map(|chunk| std::str::from_utf8(chunk).unwrap())
        .collect::<Vec<_>>()
        .join("\n");
    let image = format!("\x1b]1337;File=inline=1:{wrapped_base64}\x1b\\");

    terminal.process(image.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn parser_terminal_iterm_inline_image_accepts_c1_osc_and_st_controls() {
    let mut terminal = ParserTerminal::new(80, 24);
    let mut image = Vec::new();
    image.push(0x9d);
    image.extend_from_slice(format!("1337;File=inline=1:{RED_PIXEL_PNG_BASE64}").as_bytes());
    image.push(0x9c);

    terminal.process(&image);

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn parser_terminal_iterm_inline_image_accepts_unpadded_base64() {
    let mut terminal = ParserTerminal::new(80, 24);
    let unpadded_base64 = RED_PIXEL_PNG_BASE64.trim_end_matches('=');
    let image = format!("\x1b]1337;File=inline=1:{unpadded_base64}\x1b\\");

    terminal.process(image.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn parser_terminal_iterm_inline_gif_registers_animation_frames() {
    let mut terminal = ParserTerminal::new(80, 24);
    let image =
        format!("\x1b]1337;File=inline=1;doNotMoveCursor=1:{RED_GREEN_1X1_GIF_BASE64}\x1b\\");

    terminal.process(image.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.kitty_image_id, None);
    let animation_id = graphic
        .animation_id
        .expect("animated iTerm GIF should carry an animation id");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
    assert_eq!(graphic.pixels.as_ref(), &[255, 0, 0, 255]);
    let first_asset_version = graphic.asset_version;

    let animation = terminal
        .graphics_store()
        .get_animation(animation_id)
        .expect("animated iTerm GIF should register animation frames");
    assert_eq!(animation.frame_count(), 2);

    thread::sleep(Duration::from_millis(25));
    let changed = terminal.update_animations();

    assert_eq!(changed, vec![animation_id]);
    let updated = &terminal.all_graphics()[0];
    assert_eq!(updated.pixels.as_ref(), &[0, 255, 0, 255]);
    assert_ne!(updated.asset_version, first_asset_version);
}

#[test]
fn parser_terminal_iterm_single_inline_accepts_matching_declared_size() {
    let mut terminal = ParserTerminal::new(80, 24);
    let image = format!("\x1b]1337;File=inline=1;size=70:{RED_PIXEL_PNG_BASE64}\x1b\\");

    terminal.process(image.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn parser_terminal_iterm_single_inline_rejects_size_mismatch() {
    let mut terminal = ParserTerminal::new(80, 24);
    let image = format!("\x1b]1337;File=inline=1;size=71:{RED_PIXEL_PNG_BASE64}\x1b\\");

    terminal.process(image.as_bytes());

    assert_eq!(
        terminal.graphics_count(),
        0,
        "single iTerm2 inline images with a mismatched size must not render"
    );
}

#[test]
fn parser_terminal_iterm_single_inline_rejects_unsupported_image_payload() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.process(b"\x1b]1337;File=inline=1:aGVsbG8=\x1b\\");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "unsupported iTerm2 inline image payloads must not render"
    );
    assert!(
        terminal.poll_events().iter().all(|event| !matches!(
            event,
            par_term_emu_core_rust::terminal::TerminalEvent::GraphicsAdded(_)
        )),
        "unsupported iTerm2 inline image payloads must not emit GraphicsAdded"
    );
}

#[test]
fn parser_terminal_iterm_multipart_image_accepts_wrapped_file_part_base64() {
    let mut terminal = ParserTerminal::new(80, 24);
    let chunks = RED_PIXEL_PNG_BASE64
        .as_bytes()
        .chunks(20)
        .map(|chunk| std::str::from_utf8(chunk).unwrap())
        .collect::<Vec<_>>();
    let wrapped_part = chunks.join("\r\n\t");
    let start = "\x1b]1337;MultipartFile=inline=1;name=cGl4ZWwucG5n\x1b\\";
    let part = format!("\x1b]1337;FilePart={wrapped_part}\x1b\\");

    terminal.process(start.as_bytes());
    terminal.process(part.as_bytes());
    terminal.process(b"\x1b]1337;FileEnd\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 1);
    assert_eq!(graphic.height, 1);
}

#[test]
fn parser_terminal_iterm_requested_height_advances_cursor_by_display_span() {
    let mut terminal = ParserTerminal::new(80, 24);
    let image = format!(
        "\x1b]1337;File=inline=1;height=3;preserveAspectRatio=0:{}\x1b\\X",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(image.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
    assert_eq!(terminal.all_graphics()[0].display_cell_span, Some((1, 3)));
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "");
    assert_eq!(terminal.active_grid().row_text(3).trim_end(), "X");
}

#[test]
fn parser_terminal_iterm_advancement_respects_scroll_region_bottom() {
    let mut terminal = ParserTerminal::new(8, 6);
    let image = format!(
        "\x1b[1;1Htop\x1b[2;1Hone\x1b[3;1Htwo\x1b[4;1Hthree\x1b[5;1Hbottom\
         \x1b[2;4r\x1b[4;1H\x1b]1337;File=inline=1;height=3;preserveAspectRatio=0:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(image.as_bytes());

    assert_eq!(
        terminal.cursor().row,
        3,
        "iTerm2 inline image cursor advancement should stay pinned to the scroll region bottom"
    );
    assert_eq!(
        terminal.active_grid().row_text(4).trim_end(),
        "bottom",
        "iTerm2 inline image advancement inside a partial scroll region must not move into rows below the region"
    );
    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.display_cell_span, Some((1, 3)));
    assert_eq!(
        graphic.position,
        (0, 1),
        "partially clipped iTerm2 images should stay anchored at the scroll region top"
    );
    assert_eq!(
        graphic.scroll_offset_rows, 1,
        "iTerm2 images clipped by partial scroll regions should track hidden top rows"
    );
}

#[test]
fn parser_terminal_iterm_px_dimensions_accept_space_before_unit() {
    let mut terminal = ParserTerminal::new(80, 24);
    let image = format!(
        "\x1b]1337;File=inline=1;width=2 px;height=4 PX;preserveAspectRatio=0;doNotMoveCursor=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(image.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(
        graphic.display_cell_span,
        Some((2, 2)),
        "iTerm2 px dimensions should accept a space before the unit"
    );
}

#[test]
fn parser_terminal_iterm_non_positive_dimensions_fall_back_to_auto() {
    let mut terminal = ParserTerminal::new(80, 24);
    let image = format!(
        "\x1b]1337;File=inline=1;width=-5 px;height=-10%;preserveAspectRatio=0;doNotMoveCursor=1:{}\x1b\\",
        RED_GREEN_2X1_PNG_BASE64
    );

    terminal.process(image.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "iterm");
    assert_eq!(graphic.width, 2);
    assert_eq!(graphic.height, 1);
    assert!(graphic.placement.requested_width.is_auto());
    assert_eq!(graphic.placement.requested_width.unit, ImageSizeUnit::Auto);
    assert!(graphic.placement.requested_height.is_auto());
    assert_eq!(graphic.placement.requested_height.unit, ImageSizeUnit::Auto);
    assert_eq!(
        graphic.display_cell_span,
        Some((2, 1)),
        "invalid iTerm2 dimensions should use the decoded image's natural span, not a coerced 1px size"
    );
}

#[test]
fn parser_terminal_iterm_do_not_move_cursor_keeps_text_position() {
    let mut terminal = ParserTerminal::new(80, 24);
    let image = format!(
        "\x1b]1337;File=inline=1;height=3;preserveAspectRatio=0;doNotMoveCursor=1:{}\x1b\\X",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(image.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
    assert_eq!(terminal.all_graphics()[0].display_cell_span, Some((1, 3)));
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "X");
    assert_eq!(terminal.active_grid().row_text(3).trim_end(), "");
}

#[test]
fn parser_terminal_resize_refreshes_percent_graphic_cell_span() {
    let mut terminal = ParserTerminal::new(80, 24);
    let image = format!(
        "\x1b]1337;File=inline=1;width=50%;height=50%;preserveAspectRatio=0;doNotMoveCursor=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(image.as_bytes());

    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
    assert_eq!(terminal.all_graphics()[0].display_cell_span, Some((40, 12)));

    terminal.resize(40, 12);

    assert_eq!(
        terminal.all_graphics()[0].display_cell_span,
        Some((20, 6)),
        "resize should recompute percent-sized graphic spans against the new viewport"
    );
}

#[test]
fn parser_terminal_resize_refreshes_scrollback_percent_graphic_cell_span() {
    let mut terminal = ParserTerminal::with_scrollback(80, 24, 40);
    let image = format!(
        "\x1b[1;1H\x1b]1337;File=inline=1;width=50%;height=50%;preserveAspectRatio=0;doNotMoveCursor=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(image.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    assert_eq!(terminal.all_graphics()[0].protocol.as_str(), "iterm");
    assert_eq!(terminal.all_graphics()[0].display_cell_span, Some((40, 12)));

    terminal.process(b"\x1b[24;1H");
    for _ in 0..13 {
        terminal.process(b"\n");
    }

    assert_eq!(
        terminal.graphics_count(),
        0,
        "percent-sized graphic should leave the active viewport after scrolling off"
    );
    assert_eq!(terminal.scrollback_graphics_count(), 1);
    assert_eq!(
        terminal.all_scrollback_graphics()[0].display_cell_span,
        Some((40, 12))
    );

    terminal.resize(40, 12);

    assert_eq!(
        terminal.all_scrollback_graphics()[0].display_cell_span,
        Some((20, 6)),
        "resize should recompute percent-sized graphics retained in scrollback"
    );
}

#[test]
fn parser_terminal_resize_evicts_scrollback_graphics_for_reflowed_away_rows() {
    let mut terminal = ParserTerminal::with_scrollback(4, 2, 10);
    let kitty = format!(
        "\x1b[2;1H\x1b_Ga=T,f=32,s=1,v=1,i=763,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );

    terminal.process(b"ABCDEFGH");
    terminal.process(kitty.as_bytes());
    terminal.process(b"\x1b[2;1H\n\n");

    assert_eq!(terminal.grid().scrollback_len(), 2);
    assert_eq!(
        terminal.scrollback_graphics_count(),
        1,
        "test setup should retain the graphic on the second wrapped scrollback row"
    );
    assert_eq!(
        terminal.all_scrollback_graphics()[0].scrollback_row,
        Some(1)
    );

    terminal.resize(8, 2);

    assert_eq!(
        terminal.grid().scrollback_len(),
        1,
        "resize should reflow the wrapped scrollback rows into one row"
    );
    assert_eq!(
        terminal.scrollback_graphics_count(),
        0,
        "graphics scrollback should drop placements whose text row disappears during resize reflow"
    );
}

#[test]
fn parser_terminal_enforces_graphics_memory_limits() {
    let image = format!("\x1b]1337;File=inline=1:{}\x1b\\", RED_PIXEL_PNG_BASE64);

    let mut too_small_for_one_image = ParserTerminal::new(80, 24);
    too_small_for_one_image.set_graphics_memory_limits(3, 1024);
    too_small_for_one_image.process(image.as_bytes());
    assert_eq!(too_small_for_one_image.graphics_count(), 0);
    assert!(
        too_small_for_one_image
            .poll_events()
            .iter()
            .all(|event| !matches!(
                event,
                par_term_emu_core_rust::terminal::TerminalEvent::GraphicsAdded(_)
            )),
        "a rejected iTerm2 image must not emit a graphics-added event"
    );

    let mut one_image_total_budget = ParserTerminal::new(80, 24);
    one_image_total_budget.set_graphics_memory_limits(4, 4);
    one_image_total_budget.process(image.as_bytes());
    one_image_total_budget.process(image.as_bytes());
    assert_eq!(one_image_total_budget.graphics_count(), 1);
    assert!(one_image_total_budget.dropped_sixel_graphics() > 0);
}

#[test]
fn parser_terminal_empty_sixel_does_not_create_phantom_graphic() {
    let mut terminal = ParserTerminal::new(80, 24);
    let start_cursor = (terminal.cursor().col, terminal.cursor().row);

    terminal.process(b"\x1bPq\x1b\\");

    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!((terminal.cursor().col, terminal.cursor().row), start_cursor);
}

#[test]
fn parser_terminal_dcs_q_with_intermediate_is_not_sixel() {
    let mut terminal = ParserTerminal::new(80, 24);
    let start_cursor = (terminal.cursor().col, terminal.cursor().row);

    terminal.process(b"\x1bP$qm\x1b\\");

    assert_eq!(
        terminal.graphics_count(),
        0,
        "DCS $ q is DECRQSS-shaped control traffic and must not create a Sixel graphic"
    );
    assert_eq!((terminal.cursor().col, terminal.cursor().row), start_cursor);
}

#[test]
fn parser_terminal_zero_repeat_sixel_is_noop() {
    let mut empty_repeat = ParserTerminal::new(80, 24);
    let start_cursor = (empty_repeat.cursor().col, empty_repeat.cursor().row);

    empty_repeat.process(b"\x1bPq!0~\x1b\\");

    assert_eq!(empty_repeat.graphics_count(), 0);
    assert_eq!(
        (empty_repeat.cursor().col, empty_repeat.cursor().row),
        start_cursor
    );

    let mut followed_by_data = ParserTerminal::new(80, 24);
    followed_by_data.process(b"\x1bPq!0~~\x1b\\");

    assert_eq!(followed_by_data.graphics_count(), 1);
    let graphic = &followed_by_data.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(
        graphic.width, 1,
        "explicit zero-repeat data must not add an empty leading Sixel column"
    );
    assert_eq!(graphic.height, 6);
}

#[test]
fn parser_terminal_huge_sixel_repeat_clamps_to_configured_limit() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.set_sixel_limits(10, 12, 4);

    terminal.process(b"\x1bPq!999999999999999999999999999999999999999999999999~\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(
        graphic.width, 4,
        "overflowing Sixel repeat counts should saturate before max_repeat clamps them"
    );
    assert_eq!(
        &graphic.pixels.as_ref()[((5 * 4 + 3) * 4)..((5 * 4 + 4) * 4)],
        &[0, 0, 0, 255]
    );
}

#[test]
fn parser_terminal_sixel_width_reaches_configured_limit() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.set_sixel_limits(4, 12, 100);

    terminal.process(b"\x1bPq~~~~\x1b\\");

    assert_eq!(terminal.graphics_count(), 1);
    let graphic = &terminal.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "sixel");
    assert_eq!(
        graphic.width, 4,
        "Sixel graphic width should include the last column at the configured limit"
    );
    assert_eq!(
        &graphic.pixels.as_ref()[((5 * 4 + 3) * 4)..((5 * 4 + 4) * 4)],
        &[0, 0, 0, 255]
    );
}

#[test]
fn parser_terminal_answers_xtsmgraphics_sixel_geometry_queries() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[?2;4;0S");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[?2;0;1024;1024S"
    );

    terminal.set_pixel_size(800, 600);
    terminal.process(b"\x1b[?2;1;0S");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[?2;0;800;600S"
    );
}

#[test]
fn parser_terminal_answers_xtsmgraphics_sixel_capability_queries() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[?1;1;0S");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[?1;0;256S",
        "Sixel color-register queries should report the supported register count"
    );

    terminal.process(b"\x1b[?1;4;0S");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[?1;0;256S",
        "Sixel maximum color-register queries should report the supported register count"
    );

    terminal.process(b"\x1b[?1;2;256S");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[?1;3;0S",
        "XTSMGRAPHICS set requests are intentionally read-only"
    );

    terminal.process(b"\x1b[?2;9;0S");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[?2;2;0S",
        "unknown XTSMGRAPHICS actions should report invalid action"
    );

    terminal.process(b"\x1b[?9;1;0S");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[?9;1;0S",
        "unknown XTSMGRAPHICS items should report invalid item"
    );

    terminal.process(b"\x1b[?3;1;0S");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[?3;3;0S",
        "unimplemented graphics geometry item should report invalid value"
    );
}

#[test]
fn parser_terminal_tracks_kitty_keyboard_flags() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[=1u\x1b[?u");
    assert_eq!(terminal.keyboard_flags(), 1);
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[?1u"
    );

    terminal.process(b"\x1b[>5u");
    assert_eq!(terminal.keyboard_flags(), 5);
    terminal.process(b"\x1b[<1u");
    assert_eq!(terminal.keyboard_flags(), 1);

    terminal.process(b"\x1b[=4;2u");
    assert_eq!(terminal.keyboard_flags(), 5);
    terminal.process(b"\x1b[=4;3u");
    assert_eq!(terminal.keyboard_flags(), 1);
    terminal.process(b"\x1b[<1u");
    assert_eq!(
        terminal.keyboard_flags(),
        0,
        "popping an empty Kitty keyboard stack should reset to default flags"
    );
}

#[test]
fn parser_terminal_limits_kitty_keyboard_stack_depth() {
    let mut terminal = ParserTerminal::new(80, 24);

    for flags in 1..=34u16 {
        let sequence = format!("\x1b[>{flags}u");
        terminal.process(sequence.as_bytes());
        assert_eq!(terminal.keyboard_flags(), flags);
    }

    for expected_flags in (2..=33u16).rev() {
        terminal.process(b"\x1b[<1u");
        assert_eq!(
            terminal.keyboard_flags(),
            expected_flags,
            "Kitty keyboard stack should retain the newest 32 saved flag states"
        );
    }

    terminal.process(b"\x1b[<1u");
    assert_eq!(
        terminal.keyboard_flags(),
        0,
        "popping past the bounded Kitty keyboard stack should reset to default flags"
    );
}

#[test]
fn parser_terminal_keeps_plain_csi_u_out_of_kitty_keyboard_protocol() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[=5u");
    assert_eq!(terminal.keyboard_flags(), 5);

    terminal.process(b"\x1b[7u");
    assert_eq!(
        terminal.keyboard_flags(),
        5,
        "plain CSI Ps u is DECSMBV and must not overwrite Kitty keyboard flags"
    );
    assert_eq!(terminal.margin_bell_volume(), 7);
    assert!(terminal.drain_responses().is_empty());

    terminal.process(b"\x1b[0u");
    assert_eq!(
        terminal.keyboard_flags(),
        5,
        "plain CSI 0 u is SCORC/DECSMBV and must not clear Kitty keyboard flags"
    );
    assert_eq!(terminal.margin_bell_volume(), 0);

    terminal.process(b"\x1b[?u");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[?5u"
    );
}

#[test]
fn parser_terminal_scopes_kitty_keyboard_stack_to_alternate_screen() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[=1u");
    assert_eq!(terminal.keyboard_flags(), 1);

    terminal.use_alt_screen();
    assert_eq!(
        terminal.keyboard_flags(),
        0,
        "alternate screen starts with its own Kitty keyboard flags"
    );

    terminal.process(b"\x1b[>8u");
    assert_eq!(terminal.keyboard_flags(), 8);
    terminal.process(b"\x1b[=1;2u");
    assert_eq!(terminal.keyboard_flags(), 9);
    terminal.process(b"\x1b[<1u");
    assert_eq!(terminal.keyboard_flags(), 0);

    terminal.process(b"\x1b[>8u");
    assert_eq!(terminal.keyboard_flags(), 8);
    terminal.use_primary_screen();
    assert_eq!(
        terminal.keyboard_flags(),
        1,
        "leaving alternate screen should restore primary Kitty keyboard flags"
    );

    terminal.use_alt_screen();
    assert_eq!(
        terminal.keyboard_flags(),
        0,
        "alternate-screen Kitty keyboard flags should not leak across 1049 cycles"
    );
}

#[test]
fn parser_terminal_scopes_modify_other_keys_to_alternate_screen() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[>4;2m");
    assert_eq!(terminal.modify_other_keys_mode(), 2);

    terminal.use_alt_screen();
    assert_eq!(
        terminal.modify_other_keys_mode(),
        0,
        "alternate screen should start with its own modifyOtherKeys mode"
    );

    terminal.process(b"\x1b[>4;1m");
    assert_eq!(terminal.modify_other_keys_mode(), 1);
    terminal.process(b"\x1b[?4m");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[>4;1m"
    );

    terminal.use_primary_screen();
    assert_eq!(
        terminal.modify_other_keys_mode(),
        2,
        "leaving alternate screen should restore primary modifyOtherKeys mode"
    );
    terminal.process(b"\x1b[?4m");
    assert_eq!(
        String::from_utf8(terminal.drain_responses()).unwrap(),
        "\x1b[>4;2m"
    );

    terminal.use_alt_screen();
    assert_eq!(
        terminal.modify_other_keys_mode(),
        0,
        "alternate-screen modifyOtherKeys mode should not leak across 1049 cycles"
    );
}

#[test]
fn parser_terminal_handles_alt_screen_private_mode_variants() {
    for (enter, exit) in [
        (b"\x1b[?47h".as_slice(), b"\x1b[?47l".as_slice()),
        (b"\x1b[?1047h".as_slice(), b"\x1b[?1047l".as_slice()),
    ] {
        let mut terminal = ParserTerminal::new(80, 24);
        terminal.process(b"PRIMARY");
        assert_eq!(terminal.active_grid().row_text(0).trim_end(), "PRIMARY");

        terminal.process(enter);
        assert!(terminal.is_alt_screen_active());
        assert_eq!(terminal.active_grid().row_text(0).trim_end(), "");

        terminal.process(b"ALT");
        assert_eq!(terminal.active_grid().row_text(0).trim_end(), "ALT");

        terminal.process(exit);
        assert!(!terminal.is_alt_screen_active());
        assert_eq!(terminal.active_grid().row_text(0).trim_end(), "PRIMARY");
    }
}

#[test]
fn parser_terminal_alt_screen_variants_scope_interaction_modes() {
    for (enter, exit) in [
        (b"\x1b[?47h".as_slice(), b"\x1b[?47l".as_slice()),
        (b"\x1b[?1047h".as_slice(), b"\x1b[?1047l".as_slice()),
        (b"\x1b[?1049h".as_slice(), b"\x1b[?1049l".as_slice()),
    ] {
        let mut terminal = ParserTerminal::new(80, 24);

        terminal.process(b"\x1b[?1004h\x1b[?1007h\x1b[?1002h\x1b[?1006h\x1b[=1u");
        assert!(terminal.focus_tracking());
        assert!(terminal.alternate_scroll());
        assert_eq!(terminal.mouse_mode(), MouseMode::ButtonEvent);
        assert_eq!(terminal.mouse_encoding(), MouseEncoding::Sgr);
        assert_eq!(terminal.keyboard_flags(), 1);

        terminal.process(enter);
        assert!(terminal.is_alt_screen_active());
        assert!(
            !terminal.focus_tracking(),
            "alternate screen should start with independent focus tracking for {enter:?}"
        );
        assert!(
            !terminal.alternate_scroll(),
            "alternate screen should start with independent alternate-scroll state for {enter:?}"
        );
        assert_eq!(
            terminal.mouse_mode(),
            MouseMode::Off,
            "alternate screen should start with independent mouse mode for {enter:?}"
        );
        assert_eq!(
            terminal.mouse_encoding(),
            MouseEncoding::Default,
            "alternate screen should start with independent mouse encoding for {enter:?}"
        );
        assert_eq!(
            terminal.keyboard_flags(),
            0,
            "alternate screen should start with independent Kitty keyboard flags for {enter:?}"
        );

        terminal.process(b"\x1b[?1004h\x1b[?1007h\x1b[?1003h\x1b[?1016h\x1b[=8u");
        assert!(terminal.focus_tracking());
        assert!(terminal.alternate_scroll());
        assert_eq!(terminal.mouse_mode(), MouseMode::AnyEvent);
        assert_eq!(terminal.mouse_encoding(), MouseEncoding::SgrPixels);
        assert_eq!(terminal.keyboard_flags(), 8);

        terminal.process(exit);
        assert!(!terminal.is_alt_screen_active());
        assert!(
            terminal.focus_tracking(),
            "primary focus tracking should be restored after {exit:?}"
        );
        assert!(
            terminal.alternate_scroll(),
            "primary alternate-scroll should be restored after {exit:?}"
        );
        assert_eq!(
            terminal.mouse_mode(),
            MouseMode::ButtonEvent,
            "primary mouse mode should be restored after {exit:?}"
        );
        assert_eq!(
            terminal.mouse_encoding(),
            MouseEncoding::Sgr,
            "primary mouse encoding should be restored after {exit:?}"
        );
        assert_eq!(
            terminal.keyboard_flags(),
            1,
            "primary Kitty keyboard flags should be restored after {exit:?}"
        );

        terminal.process(enter);
        assert!(terminal.is_alt_screen_active());
        assert!(
            !terminal.focus_tracking(),
            "alternate-screen focus tracking should not leak across cycles for {enter:?}"
        );
        assert!(
            !terminal.alternate_scroll(),
            "alternate-screen alternate-scroll should not leak across cycles for {enter:?}"
        );
        assert_eq!(
            terminal.mouse_mode(),
            MouseMode::Off,
            "alternate-screen mouse mode should not leak across cycles for {enter:?}"
        );
        assert_eq!(
            terminal.mouse_encoding(),
            MouseEncoding::Default,
            "alternate-screen mouse encoding should not leak across cycles for {enter:?}"
        );
        assert_eq!(
            terminal.keyboard_flags(),
            0,
            "alternate-screen Kitty keyboard flags should not leak across cycles for {enter:?}"
        );
    }
}

#[test]
fn parser_terminal_reports_alt_screen_private_mode_status() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[?47$p\x1b[?1047$p\x1b[?1049$p");
    let response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert!(
        response.contains("\x1b[?47;2$y")
            && response.contains("\x1b[?1047;2$y")
            && response.contains("\x1b[?1049;2$y"),
        "alternate screen private modes should report reset by default: {response:?}"
    );

    terminal.process(b"\x1b[?1047h\x1b[?47$p\x1b[?1047$p\x1b[?1049$p");
    let response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert!(
        response.contains("\x1b[?47;1$y")
            && response.contains("\x1b[?1047;1$y")
            && response.contains("\x1b[?1049;1$y"),
        "alternate screen private modes should report set while alt screen is active: {response:?}"
    );

    terminal.process(b"\x1b[?1047l\x1b[?1047$p");
    let response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert!(
        response.contains("\x1b[?1047;2$y"),
        "alternate screen private modes should report reset after DECRST 1047: {response:?}"
    );
}

#[test]
fn parser_terminal_restores_cursor_state_for_1048_and_1049() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[3;5H\x1b[1m\x1b[?1048h");
    terminal.process(b"\x1b[10;20H\x1b[22m\x1b[?1048lX");
    let restored_1048 = terminal.active_grid().get(4, 2).unwrap();
    assert_eq!(restored_1048.c, 'X');
    assert!(
        restored_1048.flags.bold(),
        "DECRST 1048 should restore the saved character attributes"
    );

    let mut terminal = ParserTerminal::new(80, 24);
    terminal.process(b"\x1b[4;6H\x1b[1m\x1b[?1049hALT\x1b[22m\x1b[?1049lX");
    assert!(!terminal.is_alt_screen_active());
    let restored_1049 = terminal.active_grid().get(5, 3).unwrap();
    assert_eq!(restored_1049.c, 'X');
    assert!(
        restored_1049.flags.bold(),
        "DECRST 1049 should restore the cursor attributes saved on DECSET 1049"
    );
}

#[test]
fn parser_terminal_tracks_x10_mouse_mode() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[?9h");
    assert_eq!(terminal.mouse_mode(), MouseMode::X10);
    terminal.process(b"\x1b[?9$p\x1b[?1000$p");
    let response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert!(
        response.contains("\x1b[?9;1$y"),
        "X10 mouse mode should report set for DECRQM ?9$p: {response:?}"
    );
    assert!(
        response.contains("\x1b[?1000;2$y"),
        "X10 mouse mode should not report normal mouse mode as set: {response:?}"
    );

    terminal.process(b"\x1b[?9l");
    assert_eq!(terminal.mouse_mode(), MouseMode::Off);
}

#[test]
fn parser_terminal_tracks_sgr_pixel_mouse_encoding() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[?1016h");
    assert_eq!(terminal.mouse_encoding(), MouseEncoding::SgrPixels);
    terminal.process(b"\x1b[?1006$p\x1b[?1016$p");
    let response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert!(
        response.contains("\x1b[?1006;2$y"),
        "SGR cell mouse encoding should not report set while pixel mode is active: {response:?}"
    );
    assert!(
        response.contains("\x1b[?1016;1$y"),
        "SGR pixel mouse encoding should report set for DECRQM ?1016$p: {response:?}"
    );

    terminal.process(b"\x1b[?1016l");
    assert_eq!(terminal.mouse_encoding(), MouseEncoding::Default);
}

#[test]
fn parser_terminal_reports_focus_events_only_when_focus_tracking_is_enabled() {
    let mut terminal = ParserTerminal::new(80, 24);

    assert!(terminal.report_focus_in().is_empty());
    assert!(terminal.report_focus_out().is_empty());

    terminal.process(b"\x1b[?1004h");
    assert_eq!(terminal.report_focus_in(), b"\x1b[I");
    assert_eq!(terminal.report_focus_out(), b"\x1b[O");

    terminal.process(b"\x1b[?1004l");
    assert!(terminal.report_focus_in().is_empty());
    assert!(terminal.report_focus_out().is_empty());
}

#[test]
fn parser_terminal_alternate_screen_exit_resets_transient_interaction_modes() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[?1049h\x1b[?1004h\x1b[?1007h\x1b[?1000h\x1b[?1016h");

    assert!(terminal.is_alt_screen_active());
    assert!(terminal.focus_tracking());
    assert!(terminal.alternate_scroll());
    assert_eq!(terminal.mouse_mode(), MouseMode::Normal);
    assert_eq!(terminal.mouse_encoding(), MouseEncoding::SgrPixels);
    assert_eq!(terminal.report_focus_in(), b"\x1b[I");

    terminal.process(b"\x1b[?1049l");

    assert!(!terminal.is_alt_screen_active());
    assert!(
        !terminal.focus_tracking(),
        "focus tracking enabled by a full-screen app must not leak back to the primary screen"
    );
    assert!(
        !terminal.alternate_scroll(),
        "alternate-scroll enabled in alternate screen must reset on return to primary"
    );
    assert_eq!(
        terminal.mouse_mode(),
        MouseMode::Off,
        "mouse mode enabled in alternate screen must reset on return to primary"
    );
    assert_eq!(
        terminal.mouse_encoding(),
        MouseEncoding::Default,
        "mouse encoding enabled in alternate screen must reset on return to primary"
    );
    assert!(terminal.report_focus_in().is_empty());
}

#[test]
fn parser_terminal_restores_primary_interaction_modes_after_alt_screen_exit() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[?1004h\x1b[?1007h\x1b[?1002h\x1b[?1006h");
    assert!(terminal.focus_tracking());
    assert!(terminal.alternate_scroll());
    assert_eq!(terminal.mouse_mode(), MouseMode::ButtonEvent);
    assert_eq!(terminal.mouse_encoding(), MouseEncoding::Sgr);

    terminal.process(b"\x1b[?1049h");
    assert!(terminal.is_alt_screen_active());
    assert!(
        !terminal.focus_tracking(),
        "alternate screen should start with independent focus tracking"
    );
    assert!(
        !terminal.alternate_scroll(),
        "alternate screen should start with independent alternate-scroll state"
    );
    assert_eq!(
        terminal.mouse_mode(),
        MouseMode::Off,
        "alternate screen should start with independent mouse mode"
    );
    assert_eq!(
        terminal.mouse_encoding(),
        MouseEncoding::Default,
        "alternate screen should start with independent mouse encoding"
    );

    terminal.process(b"\x1b[?1004h\x1b[?1007h\x1b[?1000h\x1b[?1016h");
    terminal.process(b"\x1b[?1004$p\x1b[?1007$p\x1b[?1000$p\x1b[?1016$p");
    let alt_response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert!(
        alt_response.contains("\x1b[?1004;1$y")
            && alt_response.contains("\x1b[?1007;1$y")
            && alt_response.contains("\x1b[?1000;1$y")
            && alt_response.contains("\x1b[?1016;1$y"),
        "active alternate interaction modes should report set: {alt_response:?}"
    );

    terminal.process(b"\x1b[?1049l");
    assert!(!terminal.is_alt_screen_active());
    assert!(terminal.focus_tracking());
    assert!(terminal.alternate_scroll());
    assert_eq!(terminal.mouse_mode(), MouseMode::ButtonEvent);
    assert_eq!(terminal.mouse_encoding(), MouseEncoding::Sgr);
    assert_eq!(terminal.report_focus_in(), b"\x1b[I");

    terminal.process(b"\x1b[?1004$p\x1b[?1007$p\x1b[?1002$p\x1b[?1006$p");
    let primary_response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert!(
        primary_response.contains("\x1b[?1004;1$y")
            && primary_response.contains("\x1b[?1007;1$y")
            && primary_response.contains("\x1b[?1002;1$y")
            && primary_response.contains("\x1b[?1006;1$y"),
        "primary interaction modes should be restored after alt exit: {primary_response:?}"
    );

    terminal.process(b"\x1b[?1049h");
    assert_eq!(
        terminal.mouse_mode(),
        MouseMode::Off,
        "alternate-screen mouse mode should not leak across 1049 cycles"
    );
    assert!(
        !terminal.focus_tracking(),
        "alternate-screen focus tracking should not leak across 1049 cycles"
    );
}

#[test]
fn parser_terminal_hard_reset_clears_interaction_modes() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[?1004h\x1b[?1007h\x1b[?1002h\x1b[?1006h\x1b[?2004h\x1b[?5522h\x1b[=1u");
    assert!(terminal.focus_tracking());
    assert!(terminal.alternate_scroll());
    assert!(terminal.bracketed_paste());
    assert_eq!(terminal.mouse_mode(), MouseMode::ButtonEvent);
    assert_eq!(terminal.mouse_encoding(), MouseEncoding::Sgr);
    assert_eq!(terminal.keyboard_flags(), 1);

    terminal.process(b"\x1b[?1049h\x1b[?1004h\x1b[?1007h\x1b[?1003h\x1b[?1016h\x1b[=8u");
    assert!(terminal.is_alt_screen_active());
    assert!(terminal.focus_tracking());
    assert!(terminal.alternate_scroll());
    assert_eq!(terminal.mouse_mode(), MouseMode::AnyEvent);
    assert_eq!(terminal.mouse_encoding(), MouseEncoding::SgrPixels);
    assert_eq!(terminal.keyboard_flags(), 8);

    terminal.process(b"\x1b[?2026h\x1bc");

    assert!(!terminal.is_alt_screen_active());
    assert!(!terminal.synchronized_updates());
    assert!(!terminal.focus_tracking());
    assert!(!terminal.alternate_scroll());
    assert!(!terminal.bracketed_paste());
    assert!(!terminal.mime_paste());
    assert_eq!(terminal.mouse_mode(), MouseMode::Off);
    assert_eq!(terminal.mouse_encoding(), MouseEncoding::Default);
    assert_eq!(terminal.keyboard_flags(), 0);
    assert!(terminal.report_focus_in().is_empty());
    assert_eq!(terminal.paste_input_bytes("reset"), b"reset");

    terminal.process(
        b"\x1b[?1004$p\x1b[?1007$p\x1b[?1003$p\x1b[?1016$p\x1b[?2004$p\x1b[?2026$p\x1b[?u",
    );
    terminal.process(b"\x1b[?5522$p");
    let response = String::from_utf8(terminal.drain_responses()).unwrap();
    for mode in [1004, 1007, 1003, 1016, 2004, 2026, 5522] {
        assert!(
            response.contains(&format!("\x1b[?{mode};2$y")),
            "RIS should report interaction mode {mode} reset: {response:?}"
        );
    }
    assert!(
        response.contains("\x1b[?0u"),
        "RIS should reset Kitty keyboard flags: {response:?}"
    );
}

#[test]
fn parser_terminal_reports_synchronized_output_private_mode_status() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[?2026$p");
    let response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert!(
        response.contains("\x1b[?2026;2$y"),
        "synchronized output should report reset by default: {response:?}"
    );

    terminal.process(b"\x1b[?2026h\x1b[?2026l\x1b[?2026h");
    assert!(terminal.synchronized_updates());
    terminal.process(b"\x1b[?2026$p\x1b[?2026l\x1b[?2026$p");
    let response = String::from_utf8(terminal.drain_responses()).unwrap();
    assert!(
        response.contains("\x1b[?2026;1$y"),
        "synchronized output should report set while DEC 2026 is active: {response:?}"
    );
    assert!(
        response.contains("\x1b[?2026;2$y"),
        "synchronized output should report reset after DECRST 2026 in the same flushed buffer: {response:?}"
    );
}

#[test]
fn parser_terminal_reports_sgr_pixel_mouse_coordinates() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.set_mouse_mode(MouseMode::Normal);
    terminal.set_mouse_encoding(MouseEncoding::SgrPixels);

    assert_eq!(
        terminal.report_mouse(MouseEvent::new_with_pixels(0, 4, 2, true, 1, 57, 23)),
        b"\x1b[<4;58;24M",
        "SGR 1016 reports should use viewport-local pixel coordinates"
    );
    assert_eq!(
        terminal.report_mouse(MouseEvent::new_with_pixels(0, 4, 2, false, 0, 57, 23)),
        b"\x1b[<0;58;24m",
        "SGR 1016 release reports should keep pixel coordinates"
    );
    assert_eq!(
        terminal.report_mouse(MouseEvent::new(0, 4, 2, true, 0)),
        b"\x1b[<0;5;3M",
        "SGR 1016 should fall back to cell coordinates when no pixel position is supplied"
    );
}

#[test]
fn parser_terminal_reports_utf8_mouse_coordinates_beyond_default_bounds() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.set_mouse_mode(MouseMode::Normal);
    terminal.set_mouse_encoding(MouseEncoding::Utf8);

    let report = terminal.report_mouse(MouseEvent::new(0, 300, 301, true, 0));
    assert_eq!(&report[..4], b"\x1b[M ");
    assert_eq!(
        std::str::from_utf8(&report[4..]).unwrap(),
        "ōŎ",
        "UTF-8 mouse mode should encode coordinates as UTF-8 codepoints instead of clamping like default mode"
    );
}

#[test]
fn parser_terminal_mouse_reports_saturate_extreme_coordinates() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.set_mouse_mode(MouseMode::Normal);

    terminal.set_mouse_encoding(MouseEncoding::Sgr);
    let sgr = terminal.report_mouse(MouseEvent::new(0, usize::MAX, usize::MAX, true, 0));
    assert_eq!(
        String::from_utf8_lossy(&sgr),
        format!("\x1b[<0;{};{}M", usize::MAX, usize::MAX),
        "SGR mouse encoding should saturate instead of overflowing extreme coordinates"
    );

    terminal.set_mouse_encoding(MouseEncoding::SgrPixels);
    let sgr_pixels = terminal.report_mouse(MouseEvent::new_with_pixels(
        0,
        0,
        0,
        true,
        0,
        usize::MAX,
        usize::MAX,
    ));
    assert_eq!(
        String::from_utf8_lossy(&sgr_pixels),
        format!("\x1b[<0;{};{}M", usize::MAX, usize::MAX),
        "SGR pixel mouse encoding should saturate pixel coordinates"
    );

    terminal.set_mouse_encoding(MouseEncoding::Urxvt);
    let urxvt = terminal.report_mouse(MouseEvent::new(0, usize::MAX, usize::MAX, true, 0));
    assert_eq!(
        String::from_utf8_lossy(&urxvt),
        format!("\x1b[32;{};{}M", usize::MAX, usize::MAX),
        "URXVT mouse encoding should saturate instead of overflowing extreme coordinates"
    );
}

#[test]
fn parser_terminal_mouse_reports_limit_modifier_bits() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.set_mouse_mode(MouseMode::Normal);

    terminal.set_mouse_encoding(MouseEncoding::Sgr);
    assert_eq!(
        terminal.report_mouse(MouseEvent::new(0, 0, 0, true, u8::MAX)),
        b"\x1b[<28;1;1M",
        "SGR mouse reports should ignore modifier bits outside shift/alt/control"
    );

    terminal.set_mouse_encoding(MouseEncoding::Default);
    assert_eq!(
        terminal.report_mouse(MouseEvent::new(0, 0, 0, true, u8::MAX)),
        &[0x1b, b'[', b'M', 60, 33, 33],
        "default mouse reports should keep the encoded button byte in range"
    );
}

#[test]
fn parser_terminal_filters_mouse_reports_by_tracking_mode() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.set_mouse_encoding(MouseEncoding::Sgr);

    terminal.set_mouse_mode(MouseMode::X10);
    assert_eq!(
        terminal.report_mouse(MouseEvent::new(0, 0, 0, true, 0)),
        b"\x1b[<0;1;1M"
    );
    assert!(
        terminal
            .report_mouse(MouseEvent::new(0, 0, 0, false, 0))
            .is_empty()
    );
    assert!(
        terminal
            .report_mouse(MouseEvent::new(32, 0, 0, true, 0))
            .is_empty()
    );
    assert!(
        terminal
            .report_mouse(MouseEvent::new(64, 0, 0, true, 0))
            .is_empty()
    );

    terminal.set_mouse_mode(MouseMode::Normal);
    assert_eq!(
        terminal.report_mouse(MouseEvent::new(0, 0, 0, false, 0)),
        b"\x1b[<0;1;1m"
    );
    assert!(
        terminal
            .report_mouse(MouseEvent::new(32, 0, 0, true, 0))
            .is_empty()
    );
    assert!(
        terminal
            .report_mouse(MouseEvent::new(35, 0, 0, true, 0))
            .is_empty()
    );
    assert_eq!(
        terminal.report_mouse(MouseEvent::new(64, 0, 0, true, 0)),
        b"\x1b[<64;1;1M"
    );

    terminal.set_mouse_mode(MouseMode::ButtonEvent);
    assert_eq!(
        terminal.report_mouse(MouseEvent::new(32, 0, 0, true, 0)),
        b"\x1b[<32;1;1M"
    );
    assert!(
        terminal
            .report_mouse(MouseEvent::new(35, 0, 0, true, 0))
            .is_empty()
    );

    terminal.set_mouse_mode(MouseMode::AnyEvent);
    assert_eq!(
        terminal.report_mouse(MouseEvent::new(35, 0, 0, true, 0)),
        b"\x1b[<35;1;1M"
    );
}

#[test]
fn parser_terminal_snapshot_restores_active_alt_screen_kitty_keyboard_flags() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[=1u");
    assert_eq!(terminal.keyboard_flags(), 1);
    terminal.use_alt_screen();
    terminal.process(b"\x1b[=8u");
    assert_eq!(terminal.keyboard_flags(), 8);

    let snapshot = terminal.capture_snapshot();
    let mut restored = ParserTerminal::new(80, 24);
    restored.restore_from_snapshot(snapshot);

    assert!(restored.is_alt_screen_active());
    assert_eq!(
        restored.keyboard_flags(),
        8,
        "restored alt-screen snapshot should expose active alt Kitty flags"
    );
    restored.process(b"\x1b[?u");
    assert_eq!(
        String::from_utf8(restored.drain_responses()).unwrap(),
        "\x1b[?8u"
    );

    restored.use_primary_screen();
    assert_eq!(
        restored.keyboard_flags(),
        1,
        "leaving restored alt screen should recover primary Kitty flags"
    );
}

#[test]
fn parser_terminal_snapshot_restores_kitty_keyboard_stacks() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[=1u");
    terminal.process(b"\x1b[>8u");
    assert_eq!(terminal.keyboard_flags(), 8);

    terminal.use_alt_screen();
    terminal.process(b"\x1b[=2u");
    terminal.process(b"\x1b[>16u");
    assert_eq!(terminal.keyboard_flags(), 16);

    let snapshot = terminal.capture_snapshot();
    let mut restored = ParserTerminal::new(80, 24);
    restored.restore_from_snapshot(snapshot);

    assert!(restored.is_alt_screen_active());
    assert_eq!(restored.keyboard_flags(), 16);
    restored.process(b"\x1b[<1u");
    assert_eq!(
        restored.keyboard_flags(),
        2,
        "restored alt-screen Kitty keyboard stack should pop to the prior alt flags"
    );

    restored.use_primary_screen();
    assert_eq!(restored.keyboard_flags(), 8);
    restored.process(b"\x1b[<1u");
    assert_eq!(
        restored.keyboard_flags(),
        1,
        "restored primary Kitty keyboard stack should pop to the prior primary flags"
    );
}

#[test]
fn parser_terminal_snapshot_restores_active_alt_screen_modify_other_keys() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[>4;2m");
    assert_eq!(terminal.modify_other_keys_mode(), 2);
    terminal.use_alt_screen();
    terminal.process(b"\x1b[>4;1m");
    assert_eq!(terminal.modify_other_keys_mode(), 1);

    let snapshot = terminal.capture_snapshot();
    let mut restored = ParserTerminal::new(80, 24);
    restored.restore_from_snapshot(snapshot);

    assert!(restored.is_alt_screen_active());
    assert_eq!(
        restored.modify_other_keys_mode(),
        1,
        "restored alt-screen snapshot should expose active alt modifyOtherKeys mode"
    );
    restored.process(b"\x1b[?4m");
    assert_eq!(
        String::from_utf8(restored.drain_responses()).unwrap(),
        "\x1b[>4;1m"
    );

    restored.use_primary_screen();
    assert_eq!(
        restored.modify_other_keys_mode(),
        2,
        "leaving restored alt screen should recover primary modifyOtherKeys mode"
    );
}

#[test]
fn parser_terminal_snapshot_restores_split_synchronized_update_state() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"before\x1b[?2026hhidden\x1b[?20");
    assert!(terminal.synchronized_updates());
    assert_eq!(terminal.active_grid().row_text(0).trim_end(), "before");

    let snapshot = terminal.capture_snapshot();
    let mut restored = ParserTerminal::new(80, 24);
    restored.restore_from_snapshot(snapshot);

    assert!(restored.synchronized_updates());
    assert_eq!(restored.active_grid().row_text(0).trim_end(), "before");

    restored.process(b"26l-after");

    assert!(!restored.synchronized_updates());
    assert_eq!(
        restored.active_grid().row_text(0).trim_end(),
        "beforehidden-after",
        "restored synchronized update state should keep buffered output hidden until DECRST 2026 completes"
    );
}

#[test]
fn parser_terminal_snapshot_restores_active_kitty_graphics() {
    let mut terminal = ParserTerminal::new(80, 24);
    let kitty = format!(
        "\x1b[4;5H\x1b_Ga=T,f=32,s=1,v=1,i=904,p=7,c=2,r=3,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );

    terminal.process(kitty.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);

    let snapshot = terminal.capture_snapshot();
    let mut restored = ParserTerminal::new(80, 24);
    restored.restore_from_snapshot(snapshot);

    assert_eq!(
        restored.graphics_count(),
        1,
        "terminal snapshot restore should keep active Kitty graphics"
    );
    let graphic = &restored.all_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.kitty_image_id, Some(904));
    assert_eq!(graphic.kitty_placement_id, Some(7));
    assert_eq!(graphic.position, (4, 3));
    assert_eq!(graphic.placement.columns, Some(2));
    assert_eq!(graphic.placement.rows, Some(3));
    assert_eq!(graphic.pixels.as_ref(), &[255, 0, 0, 255]);
}

#[test]
fn parser_terminal_snapshot_restores_scrollback_kitty_graphics() {
    let mut terminal = ParserTerminal::with_scrollback(8, 4, 20);
    let kitty = format!(
        "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=905,p=1,c=1,r=1,C=1,q=1;{RED_RGBA_BASE64}\x1b\\"
    );

    terminal.process(kitty.as_bytes());
    terminal.process(b"\x1b[4;1H\n\n\n\n");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.scrollback_graphics_count(), 1);

    let snapshot = terminal.capture_snapshot();
    let mut restored = ParserTerminal::with_scrollback(8, 4, 20);
    restored.restore_from_snapshot(snapshot);

    assert_eq!(
        restored.graphics_count(),
        0,
        "restoring a scrolled-off graphics snapshot should not resurrect active placements"
    );
    assert_eq!(
        restored.scrollback_graphics_count(),
        1,
        "terminal snapshot restore should keep Kitty graphics retained in scrollback"
    );
    let graphic = &restored.all_scrollback_graphics()[0];
    assert_eq!(graphic.protocol.as_str(), "kitty");
    assert_eq!(graphic.kitty_image_id, Some(905));
    assert_eq!(graphic.kitty_placement_id, Some(1));
    assert_eq!(graphic.scrollback_row, Some(0));
    assert_eq!(graphic.pixels.as_ref(), &[255, 0, 0, 255]);
}

#[test]
fn parser_terminal_snapshot_restores_active_iterm_and_sixel_graphics() {
    let mut terminal = ParserTerminal::new(12, 6);
    let iterm = format!(
        "\x1b[2;3H\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(iterm.as_bytes());
    terminal.process(b"\x1b[4;5H\x1bPq#1;2;100;0;0@\x1b\\");
    assert_eq!(terminal.graphics_count(), 2);
    let mut original_graphics = terminal
        .all_graphics()
        .iter()
        .map(|graphic| {
            (
                graphic.protocol.as_str().to_string(),
                graphic.position,
                graphic.display_cell_span,
                graphic.pixels.as_ref()[0..4].to_vec(),
            )
        })
        .collect::<Vec<_>>();
    original_graphics.sort_by(|left, right| left.0.cmp(&right.0));

    let snapshot = terminal.capture_snapshot();
    let mut restored = ParserTerminal::new(12, 6);
    restored.restore_from_snapshot(snapshot);

    assert_eq!(
        restored.graphics_count(),
        2,
        "terminal snapshot restore should keep active iTerm2 and Sixel graphics"
    );
    let mut restored_graphics = restored
        .all_graphics()
        .iter()
        .map(|graphic| {
            (
                graphic.protocol.as_str().to_string(),
                graphic.position,
                graphic.display_cell_span,
                graphic.pixels.as_ref()[0..4].to_vec(),
            )
        })
        .collect::<Vec<_>>();
    restored_graphics.sort_by(|left, right| left.0.cmp(&right.0));
    assert_eq!(restored_graphics, original_graphics);
}

#[test]
fn parser_terminal_snapshot_restores_scrollback_iterm_and_sixel_graphics() {
    let mut terminal = ParserTerminal::with_scrollback(12, 12, 30);
    let iterm = format!(
        "\x1b[1;1H\x1b]1337;File=inline=1;doNotMoveCursor=1;width=1;height=1:{}\x1b\\",
        RED_PIXEL_PNG_BASE64
    );

    terminal.process(iterm.as_bytes());
    terminal.process(b"\x1b[5;1H\x1bPq#1;2;100;0;0@\x1b\\");
    assert_eq!(terminal.graphics_count(), 2);

    terminal.process(b"\x1b[12;1H");
    for _ in 0..16 {
        terminal.process(b"\n");
    }
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.scrollback_graphics_count(), 2);
    let mut original_graphics = terminal
        .all_scrollback_graphics()
        .iter()
        .map(|graphic| {
            (
                graphic.protocol.as_str().to_string(),
                graphic.position,
                graphic.scrollback_row,
                graphic.display_cell_span,
                graphic.pixels.as_ref()[0..4].to_vec(),
            )
        })
        .collect::<Vec<_>>();
    original_graphics.sort_by(|left, right| left.0.cmp(&right.0));

    let snapshot = terminal.capture_snapshot();
    let mut restored = ParserTerminal::with_scrollback(12, 12, 30);
    restored.restore_from_snapshot(snapshot);

    assert_eq!(
        restored.graphics_count(),
        0,
        "restoring scrolled-off iTerm2/Sixel graphics should not create active placements"
    );
    assert_eq!(
        restored.scrollback_graphics_count(),
        2,
        "terminal snapshot restore should keep iTerm2 and Sixel graphics retained in scrollback"
    );
    let mut restored_graphics = restored
        .all_scrollback_graphics()
        .iter()
        .map(|graphic| {
            (
                graphic.protocol.as_str().to_string(),
                graphic.position,
                graphic.scrollback_row,
                graphic.display_cell_span,
                graphic.pixels.as_ref()[0..4].to_vec(),
            )
        })
        .collect::<Vec<_>>();
    restored_graphics.sort_by(|left, right| left.0.cmp(&right.0));
    assert_eq!(restored_graphics, original_graphics);
}

#[test]
fn parser_terminal_snapshot_restores_kitty_clear_redraw_tombstone() {
    let mut terminal = ParserTerminal::new(80, 24);
    let first =
        format!("\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=906,p=4,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");

    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;

    terminal.process(b"\x1b[2J");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.pending_cleared_kitty_graphics_count(), 1);

    let snapshot = terminal.capture_snapshot();
    let mut restored = ParserTerminal::new(80, 24);
    restored.restore_from_snapshot(snapshot);

    assert_eq!(restored.graphics_count(), 0);
    assert_eq!(
        restored.pending_cleared_kitty_graphics_count(),
        1,
        "snapshot restore should retain Kitty clear-screen tombstones for immediate redraw"
    );

    let replacement =
        format!("\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=906,p=4,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    restored.process(replacement.as_bytes());

    assert_eq!(restored.graphics_count(), 1);
    assert_eq!(
        restored.all_graphics()[0].id,
        first_graphic_id,
        "redraw after restored clear tombstone should keep the original render identity"
    );
    assert_eq!(restored.pending_cleared_kitty_graphics_count(), 0);
}

#[test]
fn parser_terminal_snapshot_restores_kitty_deferred_delete_tombstone() {
    let mut terminal = ParserTerminal::new(80, 24);
    let first =
        format!("\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=907,p=5,C=1,q=1;{RED_RGBA_BASE64}\x1b\\");

    terminal.process(first.as_bytes());
    assert_eq!(terminal.graphics_count(), 1);
    let first_graphic_id = terminal.all_graphics()[0].id;

    terminal.process(b"\x1b_Ga=d,d=I,i=907,p=5,q=2;\x1b\\");
    assert_eq!(terminal.graphics_count(), 0);
    assert_eq!(terminal.deferred_kitty_delete_count(), 1);

    let snapshot = terminal.capture_snapshot();
    let mut restored = ParserTerminal::new(80, 24);
    restored.restore_from_snapshot(snapshot);

    assert_eq!(restored.graphics_count(), 0);
    assert_eq!(
        restored.deferred_kitty_delete_count(),
        1,
        "snapshot restore should retain Kitty delete tombstones for immediate replacement"
    );

    let replacement =
        format!("\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i=908,p=5,C=1,q=1;{GREEN_RGBA_BASE64}\x1b\\");
    restored.process(replacement.as_bytes());

    assert_eq!(restored.deferred_kitty_delete_count(), 0);
    assert_eq!(restored.graphics_count(), 1);
    assert_eq!(
        restored.all_graphics()[0].id,
        first_graphic_id,
        "replacement after restored delete tombstone should keep the original render identity"
    );
    assert_eq!(restored.all_graphics()[0].kitty_image_id, Some(908));
}

#[test]
fn session_can_resize() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    session::resize_session(session_id, 90, 20, 0, 0).unwrap();
    thread::sleep(Duration::from_millis(100));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");

    assert!(frame.contains("\"viewport_rows\":20"));
    assert!(frame.contains("\"viewport_cols\":90"));
    session::close_session(session_id).unwrap();
}

#[test]
fn resize_stress_returns_snapshots_with_current_dimensions() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"frame_kind\":\"snapshot\"")
    });

    for (cols, rows, pixel_width, pixel_height) in [
        (100, 30, 900, 540),
        (40, 8, 360, 144),
        (120, 24, 1080, 432),
        (80, 12, 720, 216),
    ] {
        session::resize_session(session_id, cols, rows, pixel_width, pixel_height).unwrap();
        let frame = session::take_frame_diff(session_id)
            .unwrap()
            .expect("expected frame after resize stress step");
        let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

        assert_eq!(parsed["frame_kind"].as_str(), Some("snapshot"));
        assert_eq!(parsed["viewport_cols"].as_u64(), Some(cols as u64));
        assert_eq!(parsed["viewport_rows"].as_u64(), Some(rows as u64));
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_reports_scrollback_bounds_and_clamps_absolute_scroll() {
    let session_id =
        session::create_session(&serde_json::to_string(&scrollback_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "line79");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let max_offset = parsed["scrollback_max_offset"]
        .as_u64()
        .expect("expected scrollback max offset");
    assert!(max_offset > 0);

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected scrolled frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let offset = parsed["scrollback_offset"]
        .as_u64()
        .expect("expected scrollback offset");
    let max_after_scroll = parsed["scrollback_max_offset"]
        .as_u64()
        .expect("expected scrollback max offset");
    let debug_stats = session::take_frame_debug_stats_json(session_id)
        .unwrap()
        .expect("expected frame debug stats");
    let debug_parsed: serde_json::Value = serde_json::from_str(&debug_stats).unwrap();

    assert_eq!(parsed["frame_kind"].as_str(), Some("snapshot"));
    assert_eq!(offset, max_after_scroll);
    assert_eq!(
        debug_parsed["snapshot_fallback_reason"].as_str(),
        Some("scrollback_navigation")
    );
    session::close_session(session_id).unwrap();
}

#[test]
fn session_top_anchored_partial_scroll_region_contributes_to_scrollback() {
    let session_id = session::create_session(
        &serde_json::to_string(&top_anchored_partial_scrollback_profile()).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "row03");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert!(parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0);

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let scrolled = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected scrolled frame diff");
    assert!(scrolled.contains("row01"));
    assert!(scrolled.contains("row02"));

    session::close_session(session_id).unwrap();
}

#[test]
fn burst_stdout_delta_stays_bounded_to_visible_rows() {
    let gate = tempdir().unwrap();
    let gate_path = gate.path().join("continue");
    let session_id =
        session::create_session(&serde_json::to_string(&burst_stdout_profile(&gate_path)).unwrap())
            .unwrap();
    session::resize_session(session_id, 80, 12, 720, 216).unwrap();

    let _ = wait_for_frame_containing(session_id, "burst-ready");
    fs::write(&gate_path, "").unwrap();

    let frame = wait_for_frame_containing(session_id, "burst-00511");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let debug_stats = session::take_frame_debug_stats_json(session_id)
        .unwrap()
        .expect("expected frame debug stats");
    let debug_parsed: serde_json::Value = serde_json::from_str(&debug_stats).unwrap();

    assert_eq!(parsed["frame_kind"].as_str(), Some("delta"));
    assert!(
        parsed["viewport_row_shift"].as_i64().unwrap_or_default() < 0,
        "burst stdout should advance the viewport with a negative row shift: {}",
        serde_json::to_string_pretty(&parsed).unwrap()
    );
    assert!(
        debug_parsed["rows_scanned"].as_u64().unwrap_or(u64::MAX) <= 12,
        "burst delta scan should stay bounded to visible rows: {}",
        serde_json::to_string_pretty(&debug_parsed).unwrap()
    );
    assert!(
        debug_parsed["rows_emitted"].as_u64().unwrap_or(u64::MAX) <= 12,
        "burst delta emission should stay bounded to visible rows: {}",
        serde_json::to_string_pretty(&debug_parsed).unwrap()
    );
    assert!(debug_parsed["snapshot_fallback_reason"].is_null());

    session::close_session(session_id).unwrap();
}

#[test]
fn session_uses_profile_scrollback_limit_for_spawn_and_resize_rebuild() {
    let session_id =
        session::create_session(&serde_json::to_string(&limited_scrollback_profile()).unwrap())
            .unwrap();

    thread::sleep(Duration::from_millis(250));
    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected initial limited scrollback frame");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["scrollback_max_offset"].as_u64(), Some(4));

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let top_frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected top-of-scrollback frame");
    assert!(!top_frame.contains("line00"));

    session::resize_session(session_id, 120, 20, 0, 0).unwrap();
    let resized_frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected resized limited scrollback frame");
    let resized_parsed: serde_json::Value = serde_json::from_str(&resized_frame).unwrap();
    assert_eq!(resized_parsed["scrollback_max_offset"].as_u64(), Some(4));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_selection_text_reads_linear_ranges_across_scrollback() {
    let session_id =
        session::create_session(&serde_json::to_string(&scrollback_profile()).unwrap()).unwrap();

    let _ = wait_for_frame_containing(session_id, "line79");
    let text =
        session::selection_text_session(session_id, &selection_request(5, 2, 7, 4, false)).unwrap();

    assert_eq!(text, "ne05\nline06\nline");
    session::close_session(session_id).unwrap();
}

#[test]
fn session_selection_text_keeps_wrapped_rows_contiguous() {
    let session_id =
        session::create_session(&serde_json::to_string(&wrapped_selection_profile()).unwrap())
            .unwrap();

    thread::sleep(Duration::from_millis(200));
    session::resize_session(session_id, 5, 4, 50, 80).unwrap();
    let _ = wait_for_frame_containing(session_id, "kl");
    let text =
        session::selection_text_session(session_id, &selection_request(0, 3, 1, 2, false)).unwrap();

    assert_eq!(text, "defg");
    session::close_session(session_id).unwrap();
}

#[test]
fn session_selection_text_clamps_block_ranges_to_available_rows_and_columns() {
    let session_id =
        session::create_session(&serde_json::to_string(&scrollback_profile()).unwrap()).unwrap();

    let _ = wait_for_frame_containing(session_id, "line79");
    let text =
        session::selection_text_session(session_id, &selection_request(78, 4, 120, 20, true))
            .unwrap();

    assert_eq!(text, "78\n79\n");
    session::close_session(session_id).unwrap();
}

#[test]
fn session_reflows_single_long_line_across_resize() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::take_frame_diff(session_id).unwrap();

    session::write_session(session_id, b"printf 'reflow-%0130d\\n' 0\n").unwrap();

    let before = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.starts_with("reflow-") && row.len() == 137)
    });
    assert!(
        logical_rows_from_frame(&before)
            .iter()
            .any(|row| row.starts_with("reflow-") && row.len() == 137)
    );

    session::resize_session(session_id, 40, 24, 0, 0).unwrap();

    let after = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.starts_with("reflow-") && row.len() == 137)
    });
    let after_parsed: serde_json::Value = serde_json::from_str(&after).unwrap();
    assert!(
        after_parsed["rows"]
            .as_array()
            .expect("expected rows")
            .iter()
            .any(|row| row["wrapped"].as_bool() == Some(true))
    );
    assert!(
        logical_rows_from_frame(&after)
            .iter()
            .any(|row| row.starts_with("reflow-") && row.len() == 137)
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_preserves_latest_visible_output_when_shrinking_height() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::take_frame_diff(session_id).unwrap();

    session::write_session(
        session_id,
        b"i=0; while [ \"$i\" -lt 40 ]; do printf 'keep-%02d\\n' \"$i\"; i=$((i + 1)); done\n",
    )
    .unwrap();

    let before = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains("keep-39"))
    });
    assert!(
        logical_rows_from_frame(&before)
            .iter()
            .any(|row| row.contains("keep-39"))
    );

    session::resize_session(session_id, 120, 16, 0, 0).unwrap();

    let after = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected resized frame diff");
    assert!(
        logical_rows_from_frame(&after)
            .iter()
            .any(|row| row.contains("keep-39")),
        "expected the latest visible output to remain on screen after shrinking height",
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_application_cursor_and_keypad_modes() {
    let session_id =
        session::create_session(&serde_json::to_string(&mode_switch_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["application_cursor"].as_bool(), Some(true));
    assert_eq!(parsed["modes"]["application_keypad"].as_bool(), Some(true));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_kitty_keyboard_flags() {
    let session_id =
        session::create_session(&serde_json::to_string(&kitty_keyboard_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "K");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["kitty_keyboard_flags"].as_u64(), Some(1));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_focus_tracking_mode() {
    let session_id =
        session::create_session(&serde_json::to_string(&focus_tracking_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "FOCUS");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["focus_tracking"].as_bool(), Some(true));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_bracketed_paste_mode_for_xterm_profiles() {
    let session_id =
        session::create_session(&serde_json::to_string(&bracketed_paste_mode_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "PASTE");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["bracketed_paste"].as_bool(), Some(true));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_osc5522_mime_paste_mode() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc5522_mime_paste_mode_profile()).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "MIMEPASTE");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["mime_paste"].as_bool(), Some(true));

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_do_not_surface_bracketed_paste_mode() {
    let session_id = session::create_session(
        &serde_json::to_string(&vt220_bracketed_paste_mode_profile()).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "PASTE");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["bracketed_paste"].as_bool(), Some(false));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_sgr_pixel_mouse_encoding() {
    let session_id =
        session::create_session(&serde_json::to_string(&mouse_sgr_pixels_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "MOUSEPIX");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["mouse_mode"].as_str(), Some("normal"));
    assert_eq!(
        parsed["modes"]["mouse_encoding"].as_str(),
        Some("sgr_pixels")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_x10_mouse_mode() {
    let session_id =
        session::create_session(&serde_json::to_string(&mouse_x10_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "MOUSEX10");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["mouse_mode"].as_str(), Some("x10"));
    assert_eq!(parsed["modes"]["mouse_encoding"].as_str(), Some("default"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_alternate_screen_mode() {
    let session_id =
        session::create_session(&serde_json::to_string(&alternate_screen_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "ALTSCREEN");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["alternate_screen"].as_bool(), Some(true));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_resets_alt_screen_interaction_modes_on_exit() {
    let session_id = session::create_session(
        &serde_json::to_string(&alternate_screen_interaction_modes_profile()).unwrap(),
    )
    .unwrap();

    let alt_frame = wait_for_frame_containing(session_id, "ALTINTERACTION");
    let alt: serde_json::Value = serde_json::from_str(&alt_frame).unwrap();
    assert_eq!(alt["modes"]["alternate_screen"].as_bool(), Some(true));
    assert_eq!(alt["modes"]["focus_tracking"].as_bool(), Some(true));
    assert_eq!(alt["modes"]["alternate_scroll"].as_bool(), Some(true));
    assert_eq!(alt["modes"]["mouse_mode"].as_str(), Some("button_event"));
    assert_eq!(alt["modes"]["mouse_encoding"].as_str(), Some("sgr"));
    assert_eq!(alt["modes"]["kitty_keyboard_flags"].as_u64(), Some(1));

    let primary_frame = wait_for_frame_containing(session_id, "PRIMARYDONE");
    let primary: serde_json::Value = serde_json::from_str(&primary_frame).unwrap();
    assert_eq!(primary["modes"]["alternate_screen"].as_bool(), Some(false));
    assert_eq!(primary["modes"]["focus_tracking"].as_bool(), Some(false));
    assert_eq!(primary["modes"]["alternate_scroll"].as_bool(), Some(false));
    assert_eq!(primary["modes"]["mouse_mode"].as_str(), Some("off"));
    assert_eq!(primary["modes"]["mouse_encoding"].as_str(), Some("default"));
    assert_eq!(primary["modes"]["kitty_keyboard_flags"].as_u64(), Some(0));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_restores_primary_interaction_modes_after_alt_screen() {
    let session_id = session::create_session(
        &serde_json::to_string(&primary_interaction_modes_across_alternate_screen_profile())
            .unwrap(),
    )
    .unwrap();

    let primary_modes_frame = wait_for_frame_containing(session_id, "PRIMARYMODES");
    let primary_modes: serde_json::Value = serde_json::from_str(&primary_modes_frame).unwrap();
    assert_eq!(
        primary_modes["modes"]["alternate_screen"].as_bool(),
        Some(false)
    );
    assert_eq!(
        primary_modes["modes"]["focus_tracking"].as_bool(),
        Some(true)
    );
    assert_eq!(
        primary_modes["modes"]["alternate_scroll"].as_bool(),
        Some(true)
    );
    assert_eq!(
        primary_modes["modes"]["bracketed_paste"].as_bool(),
        Some(true)
    );
    assert_eq!(
        primary_modes["modes"]["mouse_mode"].as_str(),
        Some("button_event")
    );
    assert_eq!(
        primary_modes["modes"]["mouse_encoding"].as_str(),
        Some("sgr")
    );
    assert_eq!(
        primary_modes["modes"]["kitty_keyboard_flags"].as_u64(),
        Some(1)
    );

    let alt_empty_frame = wait_for_frame_containing(session_id, "ALTEMPTY");
    let alt_empty: serde_json::Value = serde_json::from_str(&alt_empty_frame).unwrap();
    assert_eq!(alt_empty["modes"]["alternate_screen"].as_bool(), Some(true));
    assert_eq!(
        alt_empty["modes"]["focus_tracking"].as_bool(),
        Some(false),
        "primary focus tracking must not leak into alternate screen: {alt_empty_frame}"
    );
    assert_eq!(
        alt_empty["modes"]["alternate_scroll"].as_bool(),
        Some(false),
        "primary alternate-scroll must not leak into alternate screen: {alt_empty_frame}"
    );
    assert_eq!(
        alt_empty["modes"]["bracketed_paste"].as_bool(),
        Some(true),
        "bracketed paste is a terminal-wide mode and should stay visible in alternate screen: {alt_empty_frame}"
    );
    assert_eq!(alt_empty["modes"]["mouse_mode"].as_str(), Some("off"));
    assert_eq!(
        alt_empty["modes"]["mouse_encoding"].as_str(),
        Some("default")
    );
    assert_eq!(alt_empty["modes"]["kitty_keyboard_flags"].as_u64(), Some(0));

    let alt_modes_frame = wait_for_frame_containing(session_id, "ALTMODES");
    let alt_modes: serde_json::Value = serde_json::from_str(&alt_modes_frame).unwrap();
    assert_eq!(alt_modes["modes"]["alternate_screen"].as_bool(), Some(true));
    assert_eq!(alt_modes["modes"]["focus_tracking"].as_bool(), Some(true));
    assert_eq!(alt_modes["modes"]["alternate_scroll"].as_bool(), Some(true));
    assert_eq!(alt_modes["modes"]["mouse_mode"].as_str(), Some("any_event"));
    assert_eq!(
        alt_modes["modes"]["mouse_encoding"].as_str(),
        Some("sgr_pixels")
    );
    assert_eq!(alt_modes["modes"]["kitty_keyboard_flags"].as_u64(), Some(8));

    let restored_frame = wait_for_frame_containing(session_id, "PRIMARYRESTORED");
    let restored: serde_json::Value = serde_json::from_str(&restored_frame).unwrap();
    assert_eq!(restored["modes"]["alternate_screen"].as_bool(), Some(false));
    assert_eq!(
        restored["modes"]["focus_tracking"].as_bool(),
        Some(true),
        "primary focus tracking should be restored after alternate screen exit: {restored_frame}"
    );
    assert_eq!(
        restored["modes"]["alternate_scroll"].as_bool(),
        Some(true),
        "primary alternate-scroll should be restored after alternate screen exit: {restored_frame}"
    );
    assert_eq!(
        restored["modes"]["bracketed_paste"].as_bool(),
        Some(true),
        "primary bracketed paste mode should remain active after alternate screen exit: {restored_frame}"
    );
    assert_eq!(
        restored["modes"]["mouse_mode"].as_str(),
        Some("button_event"),
        "primary mouse mode should be restored after alternate screen exit: {restored_frame}"
    );
    assert_eq!(
        restored["modes"]["mouse_encoding"].as_str(),
        Some("sgr"),
        "primary mouse encoding should be restored after alternate screen exit: {restored_frame}"
    );
    assert_eq!(
        restored["modes"]["kitty_keyboard_flags"].as_u64(),
        Some(1),
        "primary Kitty keyboard flags should be restored after alternate screen exit: {restored_frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_1047_alternate_screen_mode() {
    let session_id =
        session::create_session(&serde_json::to_string(&alternate_screen_1047_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "ALT1047");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["alternate_screen"].as_bool(), Some(true));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_alternate_scroll_mode() {
    let session_id =
        session::create_session(&serde_json::to_string(&alternate_scroll_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "ALTSCROLL");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["alternate_screen"].as_bool(), Some(true));
    assert_eq!(parsed["modes"]["alternate_scroll"].as_bool(), Some(true));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_preserves_wrapped_line_metadata_in_alternate_screen() {
    let session_id =
        session::create_session(&serde_json::to_string(&alternate_wrapped_line_profile()).unwrap())
            .unwrap();
    session::resize_session(session_id, 5, 4, 0, 0).unwrap();

    let frame = wait_for_frame_containing(session_id, "K");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["modes"]["alternate_screen"].as_bool(), Some(true));
    assert_eq!(
        frame_row_at_index(&parsed, 0)["text"].as_str(),
        Some("ABCDE")
    );
    assert_eq!(
        frame_row_at_index(&parsed, 0)["wrapped"].as_bool(),
        Some(true)
    );
    assert_eq!(
        frame_row_at_index(&parsed, 1)["text"].as_str(),
        Some("FGHIJ")
    );
    assert_eq!(
        frame_row_at_index(&parsed, 1)["wrapped"].as_bool(),
        Some(true)
    );
    assert_eq!(
        frame_row_at_index(&parsed, 2)["text"]
            .as_str()
            .unwrap_or_default()
            .trim_end(),
        "K"
    );
    assert_eq!(
        frame_row_at_index(&parsed, 2)["wrapped"].as_bool(),
        Some(false)
    );
    assert!(
        logical_rows_from_frame(&frame)
            .iter()
            .any(|row| row == "ABCDEFGHIJK"),
        "alternate-screen wrapped rows should reassemble as one logical row: {}",
        serde_json::to_string_pretty(&parsed).unwrap()
    );

    let text =
        session::selection_text_session(session_id, &selection_request(0, 3, 2, 1, false)).unwrap();
    assert_eq!(text, "DEFGHIJK");

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_reply_with_vt220_primary_device_attributes() {
    let session_id =
        session::create_session(&serde_json::to_string(&vt220_da_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "?62;1;2;6;7;8;9c");
    assert!(!frame.contains("?62;1;4;6;9;15;22;52c"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_surfaces_window_title_from_osc_sequences() {
    let session_id =
        session::create_session(&serde_json::to_string(&title_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["window_title"].as_str(), Some("构建目标"),);

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_do_not_surface_window_title_from_osc_sequences() {
    let session_id =
        session::create_session(&serde_json::to_string(&vt220_title_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["window_title"].as_str(), None);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_surfaces_window_icon_name_from_osc_sequences() {
    let session_id =
        session::create_session(&serde_json::to_string(&icon_name_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["window_icon_name"].as_str(), Some("图标名称"),);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_surfaces_osc0_and_legacy_title_aliases_from_real_pty() {
    let session_id = session::create_session(
        &serde_json::to_string(&legacy_title_alias_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let combined = wait_for_frame_containing(session_id, "OSC0-READY");
    let combined: serde_json::Value = serde_json::from_str(&combined).unwrap();
    assert_eq!(combined["window_title"].as_str(), Some("OSC0 combined"));
    assert_eq!(combined["window_icon_name"].as_str(), Some("OSC0 combined"));

    let legacy = wait_for_frame_containing(session_id, "LEGACY-TITLE-READY");
    let parsed: serde_json::Value = serde_json::from_str(&legacy).unwrap();
    assert_eq!(parsed["window_title"].as_str(), Some("Legacy;window"));
    assert_eq!(parsed["window_icon_name"].as_str(), Some("Legacy;icon"));

    let frame_model: ianvs_core::model::TerminalFrameDiff = serde_json::from_str(&legacy).unwrap();
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model).unwrap();
    let protobuf =
        ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes).unwrap();
    assert_eq!(protobuf.window_title, "Legacy;window");
    assert_eq!(protobuf.window_icon_name, "Legacy;icon");

    session::resize_session(session_id, 96, 28, 960, 560).unwrap();
    session::write_session(session_id, b"continued\n").unwrap();
    let after = wait_for_frame_containing(session_id, "LEGACY-TITLE-AFTER:continued");
    let after: serde_json::Value = serde_json::from_str(&after).unwrap();
    assert_eq!(after["window_title"].as_str(), Some("Legacy;window"));
    assert_eq!(after["window_icon_name"].as_str(), Some("Legacy;icon"));

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc0_and_legacy_title_aliases() {
    let session_id = session::create_session(
        &serde_json::to_string(&legacy_title_alias_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "LEGACY-TITLE-READY");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["window_title"].as_str(), None);
    assert_eq!(parsed["window_icon_name"].as_str(), None);

    session::write_session(session_id, b"continued\n").unwrap();
    let after = wait_for_frame_containing(session_id, "LEGACY-TITLE-AFTER:continued");
    let after: serde_json::Value = serde_json::from_str(&after).unwrap();
    assert_eq!(after["window_title"].as_str(), None);
    assert_eq!(after["window_icon_name"].as_str(), None);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_round_trips_xterm_title_queries_modes_and_stack_from_real_pty() {
    let session_id = session::create_session(
        &serde_json::to_string(&xterm_title_window_ops_profile(TerminalEmulation::Xterm256))
            .unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "TITLE-OPS-READY");
    let rows = logical_rows_from_frame(&frame);
    let expected: &[&[u8]] = &[
        b"\x1b]LIcon;beta\x1b\\",
        b"\x1b]lWindow;alpha\x1b\\",
        b"\x1b]L49636F6E3B62657461\x1b\\",
        b"\x1b]l57696E646F773B616C706861\x1b\\",
        b"\x1b]LIcon;beta\x1b\\",
        b"\x1b]lWindow;alpha\x1b\\",
        b"\x1b]LDirect;both\x1b\\",
        b"\x1b]lDirect;both\x1b\\",
    ];
    for (index, response) in expected.iter().enumerate() {
        let hex = response
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let line = format!("TITLE-OPS-R{index}:{hex}");
        assert!(
            rows.iter().any(|row| row == &line),
            "missing exact title response {line}: {rows:?}"
        );
    }
    assert!(!rows.iter().any(|row| row.contains("TITLE-OPS-R8:")));

    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["window_title"].as_str(), Some("Direct;both"));
    assert_eq!(parsed["window_icon_name"].as_str(), Some("Direct;both"));

    session::resize_session(session_id, 96, 28, 960, 560).unwrap();
    session::write_session(session_id, b"continued\n").unwrap();
    let after = wait_for_frame_containing(session_id, "TITLE-OPS-AFTER:continued");
    let after: serde_json::Value = serde_json::from_str(&after).unwrap();
    assert_eq!(after["window_title"].as_str(), Some("Direct;both"));
    assert_eq!(after["window_icon_name"].as_str(), Some("Direct;both"));

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_silence_xterm_title_queries_modes_and_stack() {
    let session_id = session::create_session(
        &serde_json::to_string(&xterm_title_window_ops_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "TITLE-OPS-READY");
    let rows = logical_rows_from_frame(&frame);
    assert!(rows.iter().any(|row| row == "TITLE-OPS-TIMEOUT"));
    assert!(
        !rows.iter().any(|row| row.starts_with("TITLE-OPS-R0:")),
        "VT220 unexpectedly returned title replies: {rows:?}"
    );
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["window_title"].as_str(), None);
    assert_eq!(parsed["window_icon_name"].as_str(), None);

    session::write_session(session_id, b"continued\n").unwrap();
    wait_for_frame_containing(session_id, "TITLE-OPS-AFTER:continued");
    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_do_not_surface_window_icon_name_from_osc_sequences() {
    let session_id =
        session::create_session(&serde_json::to_string(&vt220_icon_name_profile()).unwrap())
            .unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["window_icon_name"].as_str(), None);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_resize_events_from_terminal_requests() {
    let session_id =
        session::create_session(&serde_json::to_string(&resize_request_profile()).unwrap())
            .unwrap();

    let event = wait_for_event(session_id, "resize");
    assert_eq!(event["payload"]["rows"].as_u64(), Some(30));
    assert_eq!(event["payload"]["cols"].as_u64(), Some(100));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_shell_hook_events_from_dcs_hooks() {
    let session_id =
        session::create_session(&serde_json::to_string(&shell_hook_profile()).unwrap()).unwrap();

    let event = wait_for_event(session_id, "shell_hook");
    assert_eq!(event["payload"]["hook"].as_str(), Some("precmd"));
    assert_eq!(
        event["payload"]["pwd"].as_str(),
        Some("/tmp/ianvs terminal")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_shell_hook_integration_emits_lifecycle_hooks_when_enabled() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "PROMPT='ianvs terminal-test% '\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-shell-integration",
            "Zsh Shell Integration",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let pwd_event = wait_for_shell_hook(session_id, "precmd.pwd");
    let expected_pwd = fs::canonicalize(original_zdotdir.path()).unwrap();
    assert_eq!(
        pwd_event["payload"]["pwd"].as_str(),
        Some(expected_pwd.to_string_lossy().as_ref())
    );

    session::write_session(session_id, b"echo ok\n").unwrap();
    let hooks = wait_for_shell_hook_sequence(session_id, &["preexec", "command_finished"]);
    let preexec_event = &hooks[0];
    assert_eq!(
        preexec_event["payload"]["command"].as_str(),
        Some("echo ok")
    );
    let finished_event = &hooks[1];
    assert_eq!(
        finished_event["payload"]["command"].as_str(),
        Some("echo ok")
    );
    assert_eq!(finished_event["payload"]["exit_code"].as_i64(), Some(0));

    session::write_session(session_id, b"false\n").unwrap();
    let hooks = wait_for_shell_hook_sequence(session_id, &["preexec", "command_finished"]);
    let failed_event = &hooks[1];
    assert_eq!(failed_event["payload"]["command"].as_str(), Some("false"));
    assert_eq!(failed_event["payload"]["exit_code"].as_i64(), Some(1));

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_shell_hook_integration_preserves_prompt_substitution_from_zshrc() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "setopt prompt_subst\nPROMPT='$(print ianvs terminal-subst)% '\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-shell-integration-prompt-subst",
            "Zsh Shell Integration Prompt Substitution",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "ianvs terminal-subst");
    assert!(
        !frame.contains("$(print ianvs terminal-subst)"),
        "prompt substitution should be evaluated, not displayed literally: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_shell_hook_integration_sources_zshrc_with_original_zdotdir() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        r#"if [[ "${ZDOTDIR:-}" == "${HOME:-}" ]]; then
  PROMPT='ianvs terminal-zdot-ok% '
else
  PROMPT='ianvs terminal-zdot-bad% '
fi
"#,
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-shell-integration-original-zdotdir",
            "Zsh Shell Integration Original ZDOTDIR",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "ianvs terminal-zdot-ok");
    assert!(
        !frame.contains("ianvs terminal-zdot-bad"),
        "original .zshrc should see the user's ZDOTDIR, not the ianvs terminal proxy: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[cfg(target_os = "macos")]
#[test]
fn zsh_shell_hook_integration_loads_history_from_original_zdotdir() {
    let original_zdotdir = tempdir().unwrap();
    let histfile_capture_path = original_zdotdir.path().join("histfile-capture");
    fs::write(
        original_zdotdir.path().join(".zsh_history"),
        ": 1783987200:0;echo ianvs-persisted-history-sentinel\n",
    )
    .unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        r#"HISTSIZE=50000
SAVEHIST=50000
if [[ -z "${HISTFILE:-}" ]]; then
  HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
fi
setopt SHARE_HISTORY APPEND_HISTORY INC_APPEND_HISTORY EXTENDED_HISTORY
PROMPT='ianvs-history-original-zdotdir% '
"#,
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "IANVS_TEST_HISTFILE_CAPTURE".to_string(),
        histfile_capture_path.to_string_lossy().into_owned(),
    );
    let session_guard = SessionGuard::new(
        session::create_session(
            &serde_json::to_string(&local_profile(
                "zsh-shell-integration-history-original-zdotdir",
                "Zsh Shell Integration History From Original ZDOTDIR",
                "/bin/zsh",
                vec![],
                env,
                TerminalEmulation::Xterm256,
            ))
            .unwrap(),
        )
        .unwrap(),
    );
    let session_id = session_guard.id();

    let diagnostics_request = serde_json::json!({
        "kind": "terminal.export_diagnostics",
        "maxSamples": 1,
    });
    let diagnostics = session::request_session_json(session_id, &diagnostics_request.to_string())
        .unwrap()
        .expect("expected diagnostics export response");
    let diagnostics: serde_json::Value = serde_json::from_str(&diagnostics).unwrap();
    let started = diagnostics["events"]
        .as_array()
        .expect("expected diagnostics events")
        .iter()
        .find(|entry| entry["kind"] == "started")
        .expect("expected started diagnostics event");
    let shell_integration = &started["payload"]["shell_integration"];
    assert_eq!(shell_integration["status"].as_str(), Some("enabled"));
    assert_eq!(shell_integration["reason"].as_str(), Some("applied"));
    assert_eq!(shell_integration["kind"].as_str(), Some("zsh"));

    let _ = wait_for_frame_containing(session_id, "ianvs-history-original-zdotdir");
    session::write_session(
        session_id,
        b"builtin print -r -- \"$HISTFILE\" >| \"$IANVS_TEST_HISTFILE_CAPTURE\"\nbuiltin print -r -- \"${:-ianvs-histfile-capture}-complete\"\n",
    )
    .unwrap();
    let _ = wait_for_frame_containing(session_id, "ianvs-histfile-capture-complete");
    let actual_histfile = fs::read_to_string(&histfile_capture_path).unwrap();

    session::write_session(
        session_id,
        b"history 1\nbuiltin print -r -- \"${:-ianvs-history-query}-complete\"\n",
    )
    .unwrap();
    let mut history_frames = Vec::new();
    let mut query_completed = false;
    for _ in 0..SESSION_WAIT_ATTEMPTS {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            query_completed = frame.contains("ianvs-history-query-complete");
            history_frames.push(frame);
            if query_completed {
                break;
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    assert!(
        query_completed,
        "timed out waiting for history query completion; actual HISTFILE: {actual_histfile:?}"
    );
    assert!(
        history_frames
            .iter()
            .any(|frame| frame.contains("ianvs-persisted-history-sentinel")),
        "history should be loaded from the original ZDOTDIR; actual HISTFILE: {actual_histfile:?}; history frames: {history_frames:?}"
    );
}

#[test]
fn zsh_shell_hook_integration_preserves_postdisplay_redraws() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "PROMPT='ianvs terminal-postdisplay% '\n\
         __ianvs_test_self_insert() {\n\
           zle .self-insert\n\
           POSTDISPLAY=' ghost-suggestion'\n\
           region_highlight+=(\"$#BUFFER $(($#BUFFER + $#POSTDISPLAY)) fg=8\")\n\
           zle -R\n\
         }\n\
         zle -N self-insert __ianvs_test_self_insert\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-shell-integration-postdisplay",
            "Zsh Shell Integration POSTDISPLAY",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let _ = wait_for_frame_containing(session_id, "ianvs terminal-postdisplay");
    session::write_session(session_id, b"g").unwrap();
    let frame = wait_for_frame_containing(session_id, "ghost-suggestion");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let row = frame_row_with_text(&parsed, "ghost-suggestion");
    let ghost_style = row["style_runs"]
        .as_array()
        .expect("expected style runs")
        .iter()
        .find(|run| run["foreground"].as_str() == Some("#687378"))
        .expect("expected fg=8 autosuggestion style run");
    assert!(
        frame.contains("ghost-suggestion"),
        "zsh POSTDISPLAY redraws should remain visible with shell integration: {frame}"
    );
    assert!(
        ghost_style["start"].as_u64().unwrap_or_default()
            < ghost_style["end"].as_u64().unwrap_or_default(),
        "autosuggestion style run should cover visible cells: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_initial_prompt_sp_marker_is_cleared_before_multiline_prompt() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "setopt prompt_sp\nPROMPT=$'\\nianvs terminal-prompt> '\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-prompt-sp-marker",
            "Zsh Prompt SP Marker",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "ianvs terminal-prompt");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let marker_row = parsed["rows"]
        .as_array()
        .expect("expected rows")
        .iter()
        .find(|row| row["text"].as_str().unwrap_or_default().starts_with('%'));
    assert!(
        marker_row.is_none(),
        "zsh PROMPT_SP marker should be cleared before the prompt frame: {frame}"
    );
    let prompt_row = frame_row_with_text(&parsed, "ianvs terminal-prompt");
    assert_eq!(
        prompt_row["index"].as_u64(),
        Some(0),
        "the startup prompt should not leave a blank first row: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn prompt_sp_clear_sequence_marks_cleared_marker_row_dirty() {
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "prompt-sp-clear-sequence",
            "Prompt SP Clear Sequence",
            "/bin/sh",
            vec![
                "-lc".to_string(),
                "printf '\\033[1m\\033[7m%%\\033[27m\\033[1m\\033[0m                                                                               '; \
                 sleep 0.2; \
                 printf '\\r \\r\\033Phook;68656c6c6f\\033\\\\\\r\\033[0m\\033[27m\\033[24m\\033[J\\r\\nianvs terminal-prompt\\r\\n> '; \
                 sleep 0.2"
                    .to_string(),
            ],
            BTreeMap::new(),
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        let parsed: serde_json::Value = serde_json::from_str(frame).unwrap();
        parsed["rows"]
            .as_array()
            .expect("expected rows")
            .iter()
            .any(|row| {
                row["index"].as_u64() == Some(0)
                    && row["text"].as_str().unwrap_or_default().starts_with('%')
            })
    });
    let frame = wait_for_frame_containing(session_id, "ianvs terminal-prompt");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let row_zero = frame_row_at_index(&parsed, 0);
    assert!(
        !row_zero["text"]
            .as_str()
            .unwrap_or_default()
            .starts_with('%'),
        "clearing zsh's PROMPT_SP marker must dirty row 0: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn bash_shell_hook_integration_emits_lifecycle_hooks_when_enabled() {
    let Some(bash_path) = find_shell("bash") else {
        return;
    };

    let home = tempdir().unwrap();
    let cwd = tempdir().unwrap();
    fs::write(home.path().join(".bashrc"), "PS1='ianvs terminal-bash$ '\n").unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "bash-shell-integration",
        "Bash Shell Integration",
        &bash_path,
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.launch.cwd = Some(cwd.path().to_string_lossy().into_owned());
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let pwd_event = wait_for_shell_hook(session_id, "precmd.pwd");
    let expected_pwd = fs::canonicalize(cwd.path()).unwrap();
    assert_eq!(pwd_event["payload"]["shell"].as_str(), Some("bash"));
    assert_eq!(
        pwd_event["payload"]["pwd"].as_str(),
        Some(expected_pwd.to_string_lossy().as_ref())
    );

    assert_shell_hook_command_lifecycle(session_id, "bash");

    session::close_session(session_id).unwrap();
}

#[test]
fn fish_shell_hook_integration_emits_lifecycle_hooks_when_enabled() {
    let Some(fish_path) = find_shell("fish") else {
        return;
    };
    if !fish_runtime_stays_open(&fish_path) {
        return;
    }

    let home = tempdir().unwrap();
    let cwd = tempdir().unwrap();
    let fish_config_dir = home.path().join(".config/fish");
    fs::create_dir_all(&fish_config_dir).unwrap();
    fs::write(
        fish_config_dir.join("config.fish"),
        "function fish_prompt; printf 'ianvs terminal-fish> '; end\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "fish-shell-integration",
        "Fish Shell Integration",
        &fish_path,
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.launch.cwd = Some(cwd.path().to_string_lossy().into_owned());
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let pwd_event = wait_for_shell_hook(session_id, "precmd.pwd");
    let expected_pwd = fs::canonicalize(cwd.path()).unwrap();
    assert_eq!(pwd_event["payload"]["shell"].as_str(), Some("fish"));
    assert_eq!(
        pwd_event["payload"]["pwd"].as_str(),
        Some(expected_pwd.to_string_lossy().as_ref())
    );

    assert_shell_hook_command_lifecycle(session_id, "fish");

    session::close_session(session_id).unwrap();
}

#[test]
fn zsh_shell_hook_integration_disabled_emits_no_shell_hooks() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "PROMPT='ianvs terminal-disabled% '\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "zsh-shell-integration-disabled",
        "Zsh Shell Integration Disabled",
        "/bin/zsh",
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.shell_integration.enabled = false;
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::poll_events(session_id).unwrap();

    session::write_session(session_id, b"echo still-works\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "still-works");
    assert_event_kind_never_arrives(session_id, "shell_hook");

    session::close_session(session_id).unwrap();
}

#[test]
fn bash_shell_hook_integration_disabled_emits_no_shell_hooks() {
    let Some(bash_path) = find_shell("bash") else {
        return;
    };

    let home = tempdir().unwrap();
    fs::write(
        home.path().join(".bashrc"),
        "PS1='ianvs terminal-disabled$ '\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "bash-shell-integration-disabled",
        "Bash Shell Integration Disabled",
        &bash_path,
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.shell_integration.enabled = false;
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::poll_events(session_id).unwrap();

    session::write_session(session_id, b"echo still-works\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "still-works");
    assert_event_kind_never_arrives(session_id, "shell_hook");

    session::close_session(session_id).unwrap();
}

#[test]
fn fish_shell_hook_integration_disabled_emits_no_shell_hooks() {
    let Some(fish_path) = find_shell("fish") else {
        return;
    };
    if !fish_runtime_stays_open(&fish_path) {
        return;
    }

    let home = tempdir().unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        home.path().to_string_lossy().into_owned(),
    );
    let mut profile = local_profile(
        "fish-shell-integration-disabled",
        "Fish Shell Integration Disabled",
        &fish_path,
        vec![],
        env,
        TerminalEmulation::Xterm256,
    );
    profile.shell_integration.enabled = false;
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::poll_events(session_id).unwrap();

    session::write_session(session_id, b"echo still-works\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "still-works");
    assert_event_kind_never_arrives(session_id, "shell_hook");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_output_does_not_emit_activity_events() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));
    let _ = session::take_frame_diff(session_id).unwrap();
    let _ = session::poll_events(session_id).unwrap();

    session::write_session(session_id, b"printf 'quiet-output\\n'\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "quiet-output");

    let events = session::poll_events(session_id).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
    let activity = parsed
        .as_array()
        .expect("expected events array")
        .iter()
        .find(|entry| entry["kind"] == "activity");

    assert!(
        activity.is_none(),
        "output should not enqueue activity events: {}",
        serde_json::to_string_pretty(&parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn ffi_poll_events_returns_null_when_queue_is_empty() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();

    let first_ptr = ianvs_core::ffi::ianvs_session_poll_events_json(session_id);
    assert!(
        !first_ptr.is_null(),
        "expected initial started event payload"
    );
    let first_payload = unsafe { CStr::from_ptr(first_ptr) }
        .to_str()
        .expect("expected utf8 event payload")
        .to_string();
    assert!(
        first_payload.contains("\"kind\":\"started\""),
        "expected started event payload: {first_payload}"
    );
    unsafe { ianvs_core::ffi::ianvs_string_free(first_ptr) };

    let second_ptr = ianvs_core::ffi::ianvs_session_poll_events_json(session_id);
    assert!(
        second_ptr.is_null(),
        "expected empty event queue to short-circuit without JSON allocation"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn ffi_session_write_accepts_null_pointer_for_empty_payload() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();

    let empty_result =
        unsafe { ianvs_core::ffi::ianvs_session_write(session_id, std::ptr::null(), 0) };
    assert_eq!(
        empty_result, 0,
        "empty writes should not require callers to allocate a sentinel buffer"
    );

    let non_empty_result =
        unsafe { ianvs_core::ffi::ianvs_session_write(session_id, std::ptr::null(), 1) };
    assert_eq!(
        non_empty_result, -1,
        "non-empty writes still require a readable pointer"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_reflows_scrollback_history_across_resize() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    let marker = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZreflow";
    let first_line = format!("L00-{marker}");
    let last_line = format!("L47-{marker}");
    thread::sleep(Duration::from_millis(250));
    let _ = session::take_frame_diff(session_id);

    let command = format!(
        "i=0; while [ \"$i\" -lt 48 ]; do printf 'L%02d-{marker}\\n' \"$i\"; i=$((i + 1)); done\n"
    );
    session::write_session(session_id, command.as_bytes()).unwrap();

    let bottom_frame = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains(&last_line))
    });
    let bottom_parsed: serde_json::Value = serde_json::from_str(&bottom_frame).unwrap();
    assert!(
        bottom_parsed["scrollback_max_offset"]
            .as_u64()
            .expect("expected scrollback max offset")
            > 0
    );

    session::scroll_to_session(session_id, usize::MAX).unwrap();
    let top_before = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains(&first_line))
    });
    assert!(
        logical_rows_from_frame(&top_before)
            .iter()
            .any(|row| row.contains(&first_line))
    );

    session::resize_session(session_id, 40, 24, 0, 0).unwrap();
    let top_after = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains(&first_line))
    });
    let top_after_parsed: serde_json::Value = serde_json::from_str(&top_after).unwrap();
    assert!(
        top_after_parsed["rows"]
            .as_array()
            .expect("expected rows")
            .iter()
            .any(|row| row["wrapped"].as_bool() == Some(true))
    );
    assert!(
        logical_rows_from_frame(&top_after)
            .iter()
            .any(|row| row.contains(&first_line))
    );

    session::scroll_to_session(session_id, 0).unwrap();
    let bottom_after = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains(&last_line))
    });
    assert!(
        logical_rows_from_frame(&bottom_after)
            .iter()
            .any(|row| row.contains(&last_line))
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_resize_does_not_insert_blank_rows_before_readline_prompt() {
    let session_id =
        session::create_session(&serde_json::to_string(&bash_readline_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "PROMPT-XYZ>");

    session::write_session(
        session_id,
        b"printf 'HEADER-%050d\\nMID-%050d\\nENDMARK\\n' 0 0\n",
    )
    .unwrap();

    let before = wait_for_frame_where(session_id, |frame| {
        let rows = logical_rows_from_frame(frame);
        rows.iter().any(|row| row.contains("ENDMARK"))
            && rows.iter().any(|row| row.contains("PROMPT-XYZ>"))
    });
    let before_rows = logical_rows_from_frame(&before);
    let before_end = before_rows
        .iter()
        .rposition(|row| row.contains("ENDMARK"))
        .expect("expected ENDMARK before resize");
    let before_prompt = before_rows
        .iter()
        .rposition(|row| row.contains("PROMPT-XYZ>"))
        .expect("expected prompt before resize");
    assert_eq!(
        before_prompt,
        before_end + 1,
        "expected prompt to stay adjacent before resize: {before_rows:#?}"
    );

    session::resize_session(session_id, 48, 24, 0, 0).unwrap();
    let _ = wait_for_frame_where(session_id, |frame| frame.contains("PROMPT-XYZ>"));
    session::resize_session(session_id, 92, 24, 0, 0).unwrap();

    let after = wait_for_frame_where(session_id, |frame| {
        let rows = logical_rows_from_frame(frame);
        rows.iter().any(|row| row.contains("ENDMARK"))
            && rows.iter().any(|row| row.contains("PROMPT-XYZ>"))
    });
    let after_rows = logical_rows_from_frame(&after);
    let after_end = after_rows
        .iter()
        .rposition(|row| row.contains("ENDMARK"))
        .expect("expected ENDMARK after resize");
    let after_prompt = after_rows
        .iter()
        .rposition(|row| row.contains("PROMPT-XYZ>"))
        .expect("expected prompt after resize");

    assert_eq!(
        after_prompt,
        after_end + 1,
        "resize inserted blank logical rows before prompt: {after_rows:#?}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_resize_keeps_readline_input_compact() {
    let session_id =
        session::create_session(&serde_json::to_string(&bash_readline_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "PROMPT-XYZ>");

    const READLINE_INPUT: &str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    session::write_session(session_id, READLINE_INPUT.as_bytes()).unwrap();

    let _ = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains("PROMPT-XYZ>") && row.contains(READLINE_INPUT))
    });

    session::resize_session(session_id, 40, 24, 0, 0).unwrap();
    let _ = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row.contains("PROMPT-XYZ>") && row.contains(READLINE_INPUT))
    });
    session::resize_session(session_id, 96, 24, 0, 0).unwrap();

    let after = wait_for_frame_where(session_id, |frame| {
        frame.contains("\"frame_kind\":\"snapshot\"")
            && logical_rows_from_frame(frame)
                .iter()
                .any(|row| row.contains("PROMPT-XYZ>") && row.contains(READLINE_INPUT))
    });
    let parsed: serde_json::Value = serde_json::from_str(&after).unwrap();
    let rows = parsed["rows"].as_array().expect("expected rows");
    let prompt_row = rows
        .iter()
        .rposition(|row| {
            row["text"]
                .as_str()
                .unwrap_or_default()
                .contains("PROMPT-XYZ>")
        })
        .expect("expected prompt row after resize");
    let cursor_row = parsed["cursor"]["row"]
        .as_u64()
        .expect("expected cursor row") as usize;

    for row in &rows[prompt_row..=cursor_row] {
        let text = row["text"].as_str().unwrap_or_default().trim_end();
        assert!(
            !text.is_empty(),
            "resize inserted blank physical rows inside readline block: {}",
            serde_json::to_string_pretty(&parsed).unwrap()
        );
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_pixel_only_resize_does_not_emit_winch_redraw() {
    let session_id =
        session::create_session(&serde_json::to_string(&bash_readline_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "PROMPT-XYZ>");

    session::write_session(session_id, b"trap 'printf \"\\127INCH-MARKER\"' WINCH\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "PROMPT-XYZ>");

    for _ in 0..3 {
        let _ = session::take_frame_diff(session_id).unwrap();
        thread::sleep(Duration::from_millis(20));
    }

    session::resize_session(session_id, 120, 32, 1600, 768).unwrap();
    thread::sleep(Duration::from_millis(200));

    let frame = session::take_frame_diff(session_id).unwrap();
    let frame_text = frame.unwrap_or_default();
    assert!(
        !frame_text.contains("WINCH-MARKER"),
        "pixel-only resize should not signal readline redraw: {frame_text}"
    );

    session::resize_session(session_id, 119, 32, 1600, 768).unwrap();
    let _ = wait_for_frame_containing(session_id, "WINCH-MARKER");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_pixel_only_resize_updates_xtwinops_pixel_size() {
    let session_id =
        session::create_session(&serde_json::to_string(&pixel_size_query_profile()).unwrap())
            .unwrap();

    session::resize_session(session_id, 120, 32, 1600, 768).unwrap();

    let frame = wait_for_frame_containing(session_id, "PIXEL-RESPONSE");
    assert!(
        frame.contains(r"PIXEL-RESPONSE:b'\\x1b[4;768;1600t'"),
        "expected CSI 14 t to report pixel-only resize dimensions: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_synchronized_output_defers_intermediate_frames_until_disable() {
    let session_id =
        session::create_session(&serde_json::to_string(&synchronized_output_profile()).unwrap())
            .unwrap();

    thread::sleep(Duration::from_millis(700));
    let mut final_frame = None;
    for _ in 0..5 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let visible_text = logical_rows_from_frame(&frame).join("\n");
            assert!(
                !visible_text.contains("SYNC-MID"),
                "synchronized output must not publish the intermediate frame: {frame}"
            );
            if visible_text.contains("SYNC-FINAL") {
                final_frame = Some(frame);
                break;
            }
        }
        thread::sleep(Duration::from_millis(50));
    }

    let frame = final_frame.unwrap_or_else(|| wait_for_frame_containing(session_id, "SYNC-FINAL"));
    let visible_text = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible_text.contains("SYNC-FINAL"),
        "expected synchronized output to flush the final frame: {frame}"
    );
    assert!(
        !visible_text.contains("SYNC-MID"),
        "final synchronized frame should only expose the latest output: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_synchronized_output_allows_host_events_before_visible_flush() {
    let session_id = session::create_session(
        &serde_json::to_string(&synchronized_output_host_events_profile()).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| event["kind"] == "clipboard_copy")
            && events.iter().any(|event| event["kind"] == "resize")
    });
    let clipboard_event = events
        .iter()
        .find(|event| event["kind"] == "clipboard_copy")
        .expect("expected OSC 52 clipboard event during synchronized output");
    let resize_event = events
        .iter()
        .find(|event| event["kind"] == "resize")
        .expect("expected resize event during synchronized output");

    assert_eq!(clipboard_event["payload"]["selection"].as_str(), Some("c"));
    assert_eq!(
        clipboard_event["payload"]["data"].as_str(),
        Some("5aSN5Yi25YaF5a658J+Mnw==")
    );
    assert_eq!(resize_event["payload"]["rows"].as_u64(), Some(31));
    assert_eq!(resize_event["payload"]["cols"].as_u64(), Some(101));

    for _ in 0..5 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            assert!(
                !frame.contains("SYNC-HOST-DONE"),
                "host events should flow before the synchronized output frame flushes: {frame}"
            );
        }
        thread::sleep(Duration::from_millis(50));
    }

    let frame = wait_for_frame_containing(session_id, "SYNC-HOST-DONE");
    let visible_text = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible_text.contains("SYNC-HOST-DONE"),
        "expected synchronized output to flush after host callbacks: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_synchronized_output_coalesces_inline_progress_burst() {
    let session_id = session::create_session(
        &serde_json::to_string(&synchronized_inline_progress_profile()).unwrap(),
    )
    .unwrap();
    let _ = wait_for_frame_containing(session_id, "READY");

    let deadline = Instant::now() + Duration::from_millis(700);
    let mut final_frame = None;
    while Instant::now() < deadline {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            let visible_text = logical_rows_from_frame(&frame).join("\n");
            assert!(
                !visible_text.contains("Deploy 10%") && !visible_text.contains("Deploy 40%"),
                "synchronized inline progress must not publish intermediate progress frames: {frame}"
            );
            if visible_text.contains("Deploy done") {
                final_frame = Some(frame);
                break;
            }
        }
        thread::sleep(Duration::from_millis(25));
    }

    let frame = final_frame.unwrap_or_else(|| wait_for_frame_containing(session_id, "Deploy done"));
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let visible_text = logical_rows_from_frame(&frame).join("\n");

    assert_eq!(
        parsed["modes"]["synchronized_output"].as_bool(),
        Some(false),
        "final synchronized inline progress frame should leave synchronized output disabled: {frame}"
    );
    assert!(
        visible_text.contains("Deploy done"),
        "expected final synchronized inline progress text: {frame}"
    );
    assert!(
        !visible_text.contains("Deploy 10%") && !visible_text.contains("Deploy 40%"),
        "final synchronized inline progress frame should only expose the latest repaint: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_synchronized_output_timeout_flushes_stuck_frame() {
    let session_id = session::create_session(
        &serde_json::to_string(&stuck_synchronized_output_profile()).unwrap(),
    )
    .unwrap();

    thread::sleep(Duration::from_millis(300));
    for _ in 0..5 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            assert!(
                !frame.contains("SYNC-STUCK"),
                "synchronized output should not publish before timeout: {frame}"
            );
        }
        thread::sleep(Duration::from_millis(100));
    }

    let frame = wait_for_frame_containing(session_id, "SYNC-STUCK");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(
        parsed["modes"]["synchronized_output"].as_bool(),
        Some(false),
        "timeout flush should disable synchronized output mode: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_coalesces_inline_progress_spinner_repaint() {
    let session_id = session::create_session(
        &serde_json::to_string(&inline_progress_spinner_profile()).unwrap(),
    )
    .unwrap();
    let _ = wait_for_frame_containing(session_id, "READY");

    let frame = wait_for_frame_containing(session_id, "Done");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let visible_text = logical_rows_from_frame(&frame).join("\n");

    assert_eq!(
        parsed["frame_kind"].as_str(),
        Some("delta"),
        "inline progress repaint should update incrementally after the baseline frame: {frame}"
    );
    assert!(
        visible_text.contains("Done"),
        "expected final progress text: {frame}"
    );
    assert!(
        !visible_text.contains("Downloading 10%") && !visible_text.contains("Downloading 20%"),
        "spinner burst should not expose intermediate progress text: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["start"].as_u64()),
        Some(1),
        "only the progress row should be dirty: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["end"].as_u64()),
        Some(2),
        "only the progress row should be dirty: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_coalesces_cr_only_inline_spinner_repaint() {
    let session_id = session::create_session(
        &serde_json::to_string(&inline_progress_cr_only_spinner_profile()).unwrap(),
    )
    .unwrap();
    let _ = wait_for_frame_containing(session_id, "READY");

    let frame = wait_for_frame_containing(session_id, "Working done");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let visible_text = logical_rows_from_frame(&frame).join("\n");

    assert_eq!(
        parsed["frame_kind"].as_str(),
        Some("delta"),
        "CR-only spinner repaint should update incrementally after the baseline frame: {frame}"
    );
    assert!(
        visible_text.contains("Working done"),
        "expected final CR-only spinner text: {frame}"
    );
    assert!(
        !visible_text.contains("Working -")
            && !visible_text.contains("Working \\")
            && !visible_text.contains("Working |"),
        "CR-only spinner burst should not expose intermediate frames: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["start"].as_u64()),
        Some(1),
        "only the CR-only spinner row should be dirty: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["end"].as_u64()),
        Some(2),
        "only the CR-only spinner row should be dirty: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_clears_inline_progress_tail_after_split_cr_el() {
    let session_id = session::create_session(
        &serde_json::to_string(&inline_progress_short_overwrite_profile()).unwrap(),
    )
    .unwrap();
    let _ = wait_for_frame_containing(session_id, "READY");
    let _ = wait_for_frame_containing(session_id, "Downloading 100%");

    let frame = wait_for_frame_containing(session_id, "OK");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let visible_text = logical_rows_from_frame(&frame).join("\n");

    assert_eq!(
        parsed["frame_kind"].as_str(),
        Some("delta"),
        "short progress overwrite should remain an incremental update: {frame}"
    );
    assert!(
        visible_text.contains("OK"),
        "expected final short progress text: {frame}"
    );
    assert!(
        !visible_text.contains("Downloading") && !visible_text.contains("100%"),
        "short progress overwrite must not retain the previous long tail: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["start"].as_u64()),
        Some(1),
        "only the progress row should be dirty after CR+EL overwrite: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["end"].as_u64()),
        Some(2),
        "only the progress row should be dirty after CR+EL overwrite: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_clears_wide_inline_progress_tail_after_split_cr_el() {
    let session_id = session::create_session(
        &serde_json::to_string(&inline_progress_wide_overwrite_profile()).unwrap(),
    )
    .unwrap();
    let _ = wait_for_frame_containing(session_id, "READY");
    let _ = wait_for_frame_containing(session_id, "Downloading 100%");

    let frame = wait_for_frame_containing(session_id, "OK");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let visible_text = logical_rows_from_frame(&frame).join("\n");

    assert_eq!(
        parsed["frame_kind"].as_str(),
        Some("delta"),
        "wide progress overwrite should remain an incremental update: {frame}"
    );
    assert!(
        visible_text.contains("OK"),
        "expected final wide progress text: {frame}"
    );
    assert!(
        !visible_text.contains("Downloading")
            && !visible_text.contains("100%")
            && !visible_text.contains("⏳"),
        "wide progress overwrite must not retain the previous wide prompt tail: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["start"].as_u64()),
        Some(1),
        "only the wide progress row should be dirty after CR+EL overwrite: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["end"].as_u64()),
        Some(2),
        "only the wide progress row should be dirty after CR+EL overwrite: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_overwrites_wide_inline_progress_with_cr_only_repaint() {
    let session_id = session::create_session(
        &serde_json::to_string(&inline_progress_wide_cr_only_overwrite_profile()).unwrap(),
    )
    .unwrap();
    let _ = wait_for_frame_containing(session_id, "READY");
    let _ = wait_for_frame_containing(session_id, "🧑‍💻 Building");

    let frame = wait_for_frame_containing(session_id, "OK Building");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let visible_text = logical_rows_from_frame(&frame).join("\n");

    assert_eq!(
        parsed["frame_kind"].as_str(),
        Some("delta"),
        "wide CR-only progress overwrite should remain an incremental update: {frame}"
    );
    assert!(
        visible_text.contains("OK Building"),
        "expected final CR-only wide progress text: {frame}"
    );
    assert!(
        !visible_text.contains("🧑‍💻"),
        "CR-only overwrite must clear the previous wide emoji cluster without leaving fragments: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["start"].as_u64()),
        Some(1),
        "only the wide CR-only progress row should be dirty after repaint: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["end"].as_u64()),
        Some(2),
        "only the wide CR-only progress row should be dirty after repaint: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_defers_split_inline_clear_until_repaint() {
    let session_id = session::create_session(
        &serde_json::to_string(&inline_progress_split_clear_repaint_profile()).unwrap(),
    )
    .unwrap();
    let _ = wait_for_frame_containing(session_id, "READY");
    let _ = wait_for_frame_containing(session_id, "Downloading 100%");

    let deadline = Instant::now() + Duration::from_millis(700);
    let mut final_frame = None;
    while Instant::now() < deadline {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            assert!(
                !frame_has_blank_viewport_row(&frame, 1),
                "split CR+EL should not publish a blank progress row before repaint: {frame}"
            );
            if frame.contains("OK") {
                final_frame = Some(frame);
                break;
            }
        }
        thread::sleep(Duration::from_millis(25));
    }

    let frame = final_frame.unwrap_or_else(|| wait_for_frame_containing(session_id, "OK"));
    let visible_text = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible_text.contains("OK"),
        "expected repaint after split inline clear: {frame}"
    );
    assert!(
        !visible_text.contains("Downloading"),
        "split inline clear repaint must not retain the previous progress tail: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_flushes_split_inline_clear_without_repaint_after_grace() {
    let session_id = session::create_session(
        &serde_json::to_string(&inline_progress_clear_without_repaint_profile()).unwrap(),
    )
    .unwrap();
    let _ = wait_for_frame_containing(session_id, "READY");
    let _ = wait_for_frame_containing(session_id, "Transient status");

    let frame = wait_for_frame_where(session_id, |frame| {
        frame_has_blank_viewport_row(frame, 1) && !frame.contains("Transient status")
    });
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(
        parsed["frame_kind"].as_str(),
        Some("delta"),
        "real split inline clear should flush as a delta after the grace window: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["start"].as_u64()),
        Some(1),
        "only the cleared progress row should be dirty: {frame}"
    );
    assert_eq!(
        parsed["dirty_ranges"]
            .as_array()
            .and_then(|ranges| ranges.first())
            .and_then(|range| range["end"].as_u64()),
        Some(2),
        "only the cleared progress row should be dirty: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc4_query_reports_rgb_for_alpha_color_specs() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc4_query_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC4-RESPONSE");
    assert!(
        frame.contains(r"OSC4-RESPONSE:b'\\x1b]4;1;rgb:1212/3434/5656\\x1b\\\\'"),
        "expected OSC 4 query to report the RGB portion of an alpha color spec: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc21_query_and_frame_colors_cross_the_real_pty() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc21_color_control_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC21-SET");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains(
            r"OSC21-RESPONSE:b'\x1b]21;foreground=rgb:12/34/56;background=rgb:23/45/67;cursor=rgb:34/56/78;196=rgb:45/67/89;future=?\x1b\\'"
        ),
        "expected OSC 21 combined query response: {visible}"
    );
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["default_foreground"].as_str(), Some("#123456"));
    assert_eq!(parsed["default_background"].as_str(), Some("#234567"));
    assert_eq!(parsed["cursor_color"].as_str(), Some("#345678"));
    assert_frame_json_protobuf_foreground_parity(&frame, "OSC21-SET", ["#456789"]);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_xterm_special_and_dynamic_colors_cross_real_pty_and_frame_codecs() {
    let session_id = session::create_session(
        &serde_json::to_string(&xterm_special_colors_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "XTERM-COLORS");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains(r"\x1b]5;0;rgb:ffff/0000/ffff\x1b\\"),
        "expected OSC 5 query response: {visible}"
    );
    assert!(
        visible.contains(r"\x1b]17;rgb:1111/2222/3333\x1b\\"),
        "expected OSC 17 query response: {visible}"
    );
    assert!(
        visible.contains(r"\x1b]19;rgb:dddd/eeee/ffff\x1b\\"),
        "expected OSC 19 query response: {visible}"
    );
    assert_frame_json_protobuf_foreground_parity(&frame, "BR XTERM-COLORS", ["#ff00ff", "#010203"]);
    assert_frame_json_protobuf_selection_color_parity(&frame, 0x112233, 0xddeeff);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_iterm_set_colors_and_negative_osc4_queries_cross_real_pty_and_codecs() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_set_colors_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "ITERM-COLORS");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains(r"\x1b]4;-2;rgb:0000/0000/0000\x1b\\"),
        "expected iTerm background query response: {visible}"
    );
    assert!(
        visible.contains(r"\x1b]4;-1;rgb:1111/2222/3333\x1b\\"),
        "expected iTerm foreground query response: {visible}"
    );
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["default_foreground"].as_str(), Some("#112233"));
    assert_eq!(parsed["default_background"].as_str(), Some("#000000"));
    assert_eq!(parsed["cursor_color"].as_str(), Some("#ffff00"));
    assert_frame_json_protobuf_foreground_parity(&frame, "BUR ITERM-COLORS", ["#ff00ff"]);
    assert_frame_json_protobuf_selection_color_parity(&frame, 0xff0000, 0x000000);
    assert_frame_json_protobuf_iterm_color_parity(&frame);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_iterm_osc6_tab_color_crosses_real_pty_replay_and_profile_reset() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_osc6_tab_color_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC6-TAB-SET");
    assert_frame_json_protobuf_tab_color_parity(&frame, 0xff8040);

    session::resize_session(session_id, 96, 28, 960, 560).unwrap();
    let replayed = wait_for_frame_where(session_id, |frame| frame.contains("OSC6-TAB-SET"));
    assert_frame_json_protobuf_tab_color_parity(&replayed, 0xff8040);

    session::write_session(session_id, b"continued\n").unwrap();
    let reset = wait_for_frame_containing(session_id, "OSC6-TAB-RESET:continued");
    assert_frame_json_protobuf_tab_color_parity(&reset, 0x102030);

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_iterm_osc6_tab_color_but_keep_profile_baseline() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_osc6_tab_color_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC6-TAB-SET");
    assert_frame_json_protobuf_tab_color_parity(&frame, 0x102030);
    session::write_session(session_id, b"continued\n").unwrap();
    let reset = wait_for_frame_containing(session_id, "OSC6-TAB-RESET:continued");
    assert_frame_json_protobuf_tab_color_parity(&reset, 0x102030);

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_iterm_set_colors_and_negative_osc4_queries() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_set_colors_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "ITERM-COLORS");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains("ITERM-COLOR-RESPONSE:b'TIMEOUT'"),
        "VT220 must deny iTerm color extensions: {visible}"
    );
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert!(parsed.get("link_color").is_none());
    assert!(parsed.get("cursor_text_color").is_none());
    assert!(parsed.get("tab_color").is_none());

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_xterm_special_and_dynamic_colors() {
    let session_id = session::create_session(
        &serde_json::to_string(&xterm_special_colors_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "XTERM-COLORS");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains("XTERM-RESPONSE:b'TIMEOUT'"),
        "VT220 must not expose xterm color-query support: {visible}"
    );
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert!(parsed.get("selection_foreground").is_none());

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc21_color_control_and_queries() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc21_color_control_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC21-SET");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains("OSC21-RESPONSE:b'TIMEOUT'"),
        "VT220 must not expose OSC 21 query support: {visible}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc22_query_and_pointer_shape_cross_the_real_pty() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc22_pointer_shape_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC22-SET");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains(r"OSC22-RESPONSE:b'\x1b]22;pointer,text,default,1,0\x1b\\'"),
        "expected OSC 22 combined query response: {visible}"
    );
    assert_frame_json_protobuf_pointer_shape_parity(&frame, "pointer");

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc22_pointer_shape_and_queries() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc22_pointer_shape_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC22-SET");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains("OSC22-RESPONSE:b'TIMEOUT'"),
        "VT220 must not expose OSC 22 query support: {visible}"
    );
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert!(parsed.get("pointer_shape").is_none());

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc66_sized_text_crosses_the_real_pty_and_frame_codecs() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc66_sized_text_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC66-SET");
    assert_frame_json_protobuf_sized_text_parity(&frame);
    assert!(
        logical_rows_from_frame(&frame)
            .iter()
            .any(|row| row.starts_with("    OSC66-SET")),
        "OSC 66 must reserve four typed frame columns before the marker"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc66_sized_text() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc66_sized_text_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC66-SET");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["sized_text"], serde_json::json!([]));
    assert!(
        logical_rows_from_frame(&frame)
            .iter()
            .any(|row| row == "OSC66-SET"),
        "VT220 policy must ignore OSC 66 without moving the cursor"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc72_drop_target_command_crosses_the_real_pty() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc72_drop_target_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let event = wait_for_event(session_id, "drag_drop_command");
    assert_eq!(event["payload"]["source"], "osc72");
    assert_eq!(event["payload"]["action"], "a");
    assert_eq!(event["payload"]["identifier"], 7);
    assert_eq!(event["payload"]["payload"], "text/plain text/uri-list");

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc72_drop_target_commands() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc72_drop_target_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let _ = wait_for_frame_containing(session_id, "OSC72-READY");
    assert_event_kind_never_arrives(session_id, "drag_drop_command");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc4_palette_boundaries_profile_reset_and_same_frame_json_protobuf_rgb_parity() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc_palette_product_profile()).unwrap())
            .unwrap();

    let _ = wait_for_frame_containing(session_id, "PALETTE-READY");
    session::write_session(session_id, b"\n").unwrap();
    let set_frame = wait_for_frame_containing(session_id, "PALETTE-SET");
    assert_frame_json_protobuf_foreground_parity(
        &set_frame,
        "PALETTE-SET",
        ["#112233", "#445566", "#778899", "#aabbcc"],
    );

    session::write_session(session_id, b"\n").unwrap();
    let reset_frame = wait_for_frame_containing(session_id, "PALETTE-RESET");
    assert_frame_json_protobuf_foreground_parity(
        &reset_frame,
        "PALETTE-RESET",
        ["#010203", "#f1f2f3", "#000000", "#eeeeee"],
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc934_query_reports_static_versioned_capability() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc934_query_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC934-RESPONSE");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains(
            r"OSC934-RESPONSE:b'\x1b]934;capability;ianvs-osc934/1;actions=set,remove,remove_all;states=normal,indeterminate,warning,error,hidden\x1b\\'"
        ),
        "expected OSC 934 query to report only the static versioned capability: {visible}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_xterm_osc60_61_62_queries_round_trip_over_real_pty_without_replay() {
    let session_id = session::create_session(
        &serde_json::to_string(&xterm_capability_query_profile(TerminalEmulation::Xterm256))
            .unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC60-62-RESPONSE");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains(
            r"OSC60-62-RESPONSE:b'\x1b]60;allowColorOps,allowFontOps,allowTitleOps\x1b\\\x1b]61;Locator,VT200Hilite\x07\x1b]62;SetColor,GetColor,GetAnsiColor\x1b\\'"
        ),
        "expected exact OSC 60/61/62 replies and no reply-shaped echo: {visible}"
    );

    session::resize_session(session_id, 96, 28, 960, 560).unwrap();
    session::write_session(session_id, b"continued\n").unwrap();
    let after = wait_for_frame_containing(session_id, "OSC60-62-AFTER");
    let after_visible = logical_rows_from_frame(&after).join("\n");
    assert!(
        after_visible.contains(r"OSC60-62-AFTER:b'continued\n'"),
        "resize replay must not inject a historical capability response: {after_visible}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_xterm_osc60_61_62_queries() {
    let session_id = session::create_session(
        &serde_json::to_string(&xterm_capability_query_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC60-62-RESPONSE");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains("OSC60-62-RESPONSE:b'TIMEOUT'"),
        "VT220 must not expose xterm OSC capability-query support: {visible}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_xterm_osc50_sets_queries_and_survives_resize_replay() {
    let session_id = session::create_session(
        &serde_json::to_string(&xterm_font_ops_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC50-RESPONSE");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains(r"OSC50-RESPONSE:b'\x1b]50;Courier Prime\x1b\\'"),
        "expected exact OSC 50 query reply: {visible}"
    );
    assert_eq!(parsed["font_family"].as_str(), Some("Courier Prime"));

    let frame_model: ianvs_core::model::TerminalFrameDiff = serde_json::from_str(&frame).unwrap();
    let protobuf_bytes = ianvs_core::frame_diff_proto::encode_frame_diff(&frame_model).unwrap();
    let protobuf =
        ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&protobuf_bytes).unwrap();
    assert_eq!(protobuf.font_family.as_deref(), Some("Courier Prime"));

    session::resize_session(session_id, 96, 28, 960, 560).unwrap();
    session::write_session(session_id, b"continued\n").unwrap();
    let after = wait_for_frame_containing(session_id, "OSC50-AFTER");
    let after_parsed: serde_json::Value = serde_json::from_str(&after).unwrap();
    let after_visible = logical_rows_from_frame(&after).join("\n");
    assert!(
        after_visible.contains(r"OSC50-AFTER:b'continued\n'"),
        "resize replay must preserve live input without injecting a font reply: {after_visible}"
    );
    assert_eq!(after_parsed["font_family"].as_str(), Some("Courier Prime"));

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_xterm_osc50_and_keep_profile_font() {
    let session_id = session::create_session(
        &serde_json::to_string(&xterm_font_ops_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC50-RESPONSE");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains("OSC50-RESPONSE:b'TIMEOUT'"),
        "VT220 must not expose xterm OSC 50: {visible}"
    );
    assert_eq!(parsed["font_family"].as_str(), Some("Profile Mono"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc99_query_reports_safe_notification_capability() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc99_query_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC99-RESPONSE");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains(
            r"OSC99-RESPONSE:b'\x1b]99;i=probe:p=?;a=report:c=1:o=always:p=title,body,close,alive,buttons:w=1\x1b\\'"
        ),
        "expected OSC 99 query to report only the safe subset: {visible}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc99_interactive_report_round_trips_over_real_pty() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc99_interactive_report_profile()).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "session_notification"
                && event["payload"]["id"].as_str() == Some("deploy")
        })
    });
    let notification = events
        .iter()
        .find(|event| {
            event["kind"] == "session_notification"
                && event["payload"]["id"].as_str() == Some("deploy")
        })
        .expect("expected interactive OSC 99 notification");
    assert_eq!(
        notification["payload"]["reportActivation"].as_bool(),
        Some(true)
    );
    assert_eq!(notification["payload"]["reportClose"].as_bool(), Some(true));
    assert_eq!(
        notification["payload"]["buttons"][1].as_str(),
        Some("Retry")
    );

    session::write_session(session_id, b"\x1b]99;i=deploy;2\x1b\\").unwrap();
    let frame = wait_for_frame_containing(session_id, "OSC99-ACTION:");
    let visible = logical_rows_from_frame(&frame).join("\n");
    assert!(
        visible.contains(r"OSC99-ACTION:b'\x1b]99;i=deploy;2\x1b\\'"),
        "expected exact OSC 99 button report over the PTY: {visible}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc99_product_dismiss_request_synchronizes_native_lifecycle() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc99_product_dismiss_profile()).unwrap())
            .unwrap();

    let notification = wait_for_event(session_id, "session_notification");
    assert_eq!(notification["payload"]["id"].as_str(), Some("dismiss-me"));

    let request = serde_json::json!({
        "kind": "terminal.dismiss_osc99_notification",
        "id": "dismiss-me",
    });
    let response = session::request_session_json(session_id, &request.to_string())
        .unwrap()
        .expect("expected product-dismiss response");
    let response: serde_json::Value = serde_json::from_str(&response).unwrap();
    assert_eq!(response["dismissed"].as_bool(), Some(true));

    let repeated = session::request_session_json(session_id, &request.to_string())
        .unwrap()
        .expect("expected repeated product-dismiss response");
    let repeated: serde_json::Value = serde_json::from_str(&repeated).unwrap();
    assert_eq!(repeated["dismissed"].as_bool(), Some(false));

    let malformed = serde_json::json!({
        "kind": "terminal.dismiss_osc99_notification",
        "id": "bad:id",
    });
    let malformed = session::request_session_json(session_id, &malformed.to_string())
        .unwrap()
        .expect("expected malformed product-dismiss response");
    let malformed: serde_json::Value = serde_json::from_str(&malformed).unwrap();
    assert_eq!(malformed["dismissed"].as_bool(), Some(false));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_frame_diff_exposes_osc12_cursor_color() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc12_cursor_color_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC12-CURSOR");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();

    assert_eq!(parsed["cursor_color"].as_str(), Some("#123456"));

    session::close_session(session_id).unwrap();
}

#[test]
fn parser_terminal_bracketed_paste_input_bytes_strip_embedded_markers() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.set_bracketed_paste(true);

    let bytes = terminal
        .paste_input_bytes("safe\x1b[201~echo unsafe\x1b[200~tail\u{009B}0200~end\u{009B}0201~");

    assert_eq!(
        String::from_utf8(bytes).unwrap(),
        "\x1b[200~safeecho unsafetailend\x1b[201~"
    );
}

#[test]
fn parser_terminal_bracketed_paste_input_bytes_preserve_non_marker_csi_text() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.set_bracketed_paste(true);

    let bytes =
        terminal.paste_input_bytes("UTF-8 🌟 keep\x1b[1;201~literal\u{009B}202~\x1b[200:1~tail");

    assert_eq!(
        String::from_utf8(bytes).unwrap(),
        "\x1b[200~UTF-8 🌟 keep\x1b[1;201~literal\u{009B}202~\x1b[200:1~tail\x1b[201~"
    );
    assert_eq!(
        sanitize_bracketed_paste_content("only markers\x1b[200~\u{009B}201~"),
        "only markers"
    );
}

#[test]
fn parser_terminal_bracketed_paste_input_bytes_noop_for_marker_only_text() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.set_bracketed_paste(true);

    let bytes = terminal.paste_input_bytes("\x1b[200~\x1b[201~\u{009B}200~\u{009B}201~");

    assert!(bytes.is_empty());
}

#[test]
fn parser_terminal_paste_input_bytes_preserve_content_without_bracketed_mode() {
    let terminal = ParserTerminal::new(80, 24);
    let content = "safe\x1b[201~echo";

    assert_eq!(terminal.paste_input_bytes(content), content.as_bytes());
}

#[test]
fn session_emits_clipboard_copy_events_from_osc_52() {
    let session_id =
        session::create_session(&serde_json::to_string(&clipboard_copy_profile()).unwrap())
            .unwrap();

    let event = wait_for_event(session_id, "clipboard_copy");
    assert_eq!(event["payload"]["selection"].as_str(), Some("c"));
    assert_eq!(
        event["payload"]["data"].as_str(),
        Some("5aSN5Yi25YaF5a658J+Mnw=="),
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_empty_clipboard_copy_events_from_osc_52() {
    let session_id =
        session::create_session(&serde_json::to_string(&clipboard_empty_copy_profile()).unwrap())
            .unwrap();

    let event = wait_for_event(session_id, "clipboard_copy");
    assert_eq!(event["payload"]["selection"].as_str(), Some("c"));
    assert_eq!(event["payload"]["data"].as_str(), Some(""));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_iterm_clipboard_stream_and_base64_copy_cross_the_real_pty() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_clipboard_copy_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events
            .iter()
            .filter(|event| event["kind"] == "clipboard_copy")
            .count()
            >= 2
    });
    let copies = events
        .iter()
        .filter(|event| event["kind"] == "clipboard_copy")
        .collect::<Vec<_>>();
    assert_eq!(copies.len(), 2);
    assert_eq!(copies[0]["payload"]["protocol"], "iterm1337");
    assert_eq!(copies[0]["payload"]["mode"], "stream");
    assert_eq!(copies[0]["payload"]["selection"], "find");
    assert_eq!(copies[0]["payload"]["data"], "c3RyZWFtZWQgdGV4dA0K");
    assert_eq!(copies[1]["payload"]["protocol"], "iterm1337");
    assert_eq!(copies[1]["payload"]["mode"], "base64");
    assert_eq!(copies[1]["payload"]["selection"], "c");
    assert_eq!(copies[1]["payload"]["data"], "ZGlyZWN0IPCfmIA=");

    let frame = wait_for_frame_containing(session_id, "streamed text");
    assert!(
        logical_rows_from_frame(&frame)
            .join("\n")
            .contains("streamed text"),
        "legacy copy content should still render: {frame}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_iterm_clipboard_copy() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_clipboard_copy_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "clipboard_copy");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_iterm_annotations_cross_the_real_pty_with_text_ranges() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_annotation_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events
            .iter()
            .filter(|event| event["kind"] == "session_annotation")
            .count()
            >= 2
    });
    let annotations = events
        .iter()
        .filter(|event| event["kind"] == "session_annotation")
        .collect::<Vec<_>>();
    assert_eq!(annotations.len(), 2);
    assert_eq!(annotations[0]["payload"]["source"], "iterm1337");
    assert_eq!(annotations[0]["payload"]["message"], "Visible note");
    assert_eq!(annotations[0]["payload"]["selectedText"], "word");
    assert_eq!(annotations[0]["payload"]["visible"], true);
    assert_eq!(annotations[0]["payload"]["startCol"], 7);
    assert_eq!(annotations[0]["payload"]["endCol"], 11);
    assert_eq!(annotations[1]["payload"]["message"], "Hidden note");
    assert_eq!(annotations[1]["payload"]["selectedText"], "secret");
    assert_eq!(annotations[1]["payload"]["visible"], false);

    let frame = wait_for_frame_containing(session_id, "OSC1337-ANNOTATION-DONE");
    assert!(
        logical_rows_from_frame(&frame).join("\n").contains("word"),
        "annotated text should remain visible: {frame}"
    );
    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_iterm_annotations() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_annotation_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "session_annotation");
    session::close_session(session_id).unwrap();
}

#[test]
fn session_iterm_open_url_crosses_the_real_pty_as_an_untrusted_request() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_open_url_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events
            .iter()
            .any(|event| event["kind"] == "open_url_request")
    });
    let request = events
        .iter()
        .find(|event| event["kind"] == "open_url_request")
        .expect("expected OSC 1337 OpenURL request");
    assert_eq!(request["payload"]["source"], "iterm1337");
    assert_eq!(request["payload"]["url"], "https://example.test/phase29");
    let frame = wait_for_frame_containing(session_id, "OSC1337-OPEN-URL-DONE");
    assert!(
        logical_rows_from_frame(&frame)
            .join("\n")
            .contains("OSC1337-OPEN-URL-DONE")
    );
    session::close_session(session_id).unwrap();
}

#[test]
fn session_iterm_report_variable_crosses_real_pty_once_with_owned_values() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_report_variable_profile(
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let initial = collect_events_until(session_id, |events| {
        events
            .iter()
            .filter(|event| event["kind"] == "report_variable_request")
            .count()
            >= 3
    });
    let requests = initial
        .iter()
        .filter(|event| event["kind"] == "report_variable_request")
        .collect::<Vec<_>>();
    assert_eq!(requests.len(), 3);
    assert_eq!(requests[0]["payload"]["source"], "iterm1337");
    assert_eq!(requests[0]["payload"]["name"], "user.REPORT_KEY");
    assert_eq!(requests[0]["payload"]["value"], "report-value");
    assert_eq!(requests[1]["payload"]["name"], "session.columns");
    assert_eq!(requests[1]["payload"]["value"], "120");
    assert_eq!(requests[2]["payload"]["name"], "session.environment");
    assert!(requests[2]["payload"]["value"].is_null());
    let _ = wait_for_frame_containing(session_id, "OSC1337-REPORT-VARIABLE-DONE");

    session::resize_session(session_id, 100, 30, 1000, 600).unwrap();
    session::write_session(session_id, b"continue\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "AFTER-REPORT-VARIABLE-RESIZE");
    for _ in 0..10 {
        let payload = session::poll_events(session_id).unwrap();
        let events: serde_json::Value = serde_json::from_str(&payload).unwrap();
        assert!(
            events
                .as_array()
                .unwrap()
                .iter()
                .all(|event| event["kind"] != "report_variable_request"),
            "resize replay redelivered a historical ReportVariable request: {events}"
        );
        thread::sleep(Duration::from_millis(20));
    }
    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_iterm_report_variable_requests() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_report_variable_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "report_variable_request");
    session::write_session(session_id, b"continue\n").unwrap();
    session::close_session(session_id).unwrap();
}

#[test]
fn session_iterm_clear_captured_output_crosses_real_pty_once_per_exact_sequence() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_clear_captured_output_profile(
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let initial = collect_events_until(session_id, |events| {
        events
            .iter()
            .filter(|event| event["kind"] == "clear_captured_output")
            .count()
            >= 2
    });
    let clears = initial
        .iter()
        .filter(|event| event["kind"] == "clear_captured_output")
        .collect::<Vec<_>>();
    assert_eq!(clears.len(), 2);
    assert!(
        clears
            .iter()
            .all(|event| event["payload"]["source"] == "iterm1337")
    );
    let _ = wait_for_frame_containing(session_id, "OSC1337-CLEAR-CAPTURED-DONE");

    session::resize_session(session_id, 100, 30, 1000, 600).unwrap();
    session::write_session(session_id, b"continue\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "AFTER-CLEAR-CAPTURED-RESIZE");
    for _ in 0..10 {
        let payload = session::poll_events(session_id).unwrap();
        let events: serde_json::Value = serde_json::from_str(&payload).unwrap();
        assert!(
            events
                .as_array()
                .unwrap()
                .iter()
                .all(|event| event["kind"] != "clear_captured_output"),
            "resize replay redelivered historical ClearCapturedOutput: {events}"
        );
        thread::sleep(Duration::from_millis(20));
    }
    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_iterm_clear_captured_output_requests() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_clear_captured_output_profile(
            TerminalEmulation::Vt220,
        ))
        .unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "clear_captured_output");
    session::write_session(session_id, b"continue\n").unwrap();
    session::close_session(session_id).unwrap();
}

#[test]
fn session_iterm_unicode_version_crosses_real_pty_and_survives_resize_replay() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_unicode_version_profile(
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "U8-FINAL:");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let colored_span = |marker: &str| {
        let row = frame_row_with_text(&parsed, marker);
        let run = row["style_runs"]
            .as_array()
            .expect("expected style runs")
            .iter()
            .find(|run| run["foreground"].as_str().is_some())
            .unwrap_or_else(|| panic!("missing colored marker for {marker}: {frame}"));
        (run["start"].as_u64().unwrap(), run["end"].as_u64().unwrap())
    };
    assert_eq!(colored_span("U8:"), (4, 5));
    assert_eq!(colored_span("U9:"), (5, 6));
    assert_eq!(colored_span("U8R:"), (5, 6));
    assert_eq!(parsed["cursor"]["col"].as_u64(), Some(11));

    session::resize_session(session_id, 100, 30, 1000, 600).unwrap();
    session::write_session(session_id, b"continue\n").unwrap();
    let after = wait_for_frame_containing(session_id, "AFTER:☕X");
    let after_parsed: serde_json::Value = serde_json::from_str(&after).unwrap();
    assert_eq!(
        after_parsed["cursor"]["col"].as_u64(),
        Some(8),
        "resize replay must retain the restored Unicode 8 width: {after}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_iterm_unicode_version_appearance_changes() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_unicode_version_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "U8-FINAL:");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(
        parsed["cursor"]["col"].as_u64(),
        Some(12),
        "VT220 must keep the default modern two-cell emoji width: {frame}"
    );

    session::write_session(session_id, b"continue\n").unwrap();
    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_iterm_open_url_requests() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_open_url_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "open_url_request");
    session::close_session(session_id).unwrap();
}

#[test]
fn resize_transcript_replay_does_not_redeliver_iterm_open_url_requests() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_open_url_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();
    let initial = collect_events_until(session_id, |events| {
        events
            .iter()
            .any(|event| event["kind"] == "open_url_request")
    });
    assert_eq!(
        initial
            .iter()
            .filter(|event| event["kind"] == "open_url_request")
            .count(),
        1
    );

    session::resize_session(session_id, 100, 30, 1000, 600).unwrap();
    session::write_session(session_id, b"continue\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "AFTER-OPEN-URL-RESIZE");
    for _ in 0..10 {
        let payload = session::poll_events(session_id).unwrap();
        let events: serde_json::Value = serde_json::from_str(&payload).unwrap();
        assert!(
            events
                .as_array()
                .unwrap()
                .iter()
                .all(|event| event["kind"] != "open_url_request"),
            "resize replay redelivered a historical OpenURL request: {events}"
        );
        thread::sleep(Duration::from_millis(20));
    }
    session::close_session(session_id).unwrap();
}

#[test]
fn session_iterm_attention_crosses_real_pty_once_and_resize_does_not_replay_it() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_attention_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let initial = collect_events_until(session_id, |events| {
        events
            .iter()
            .filter(|event| event["kind"] == "attention_request")
            .count()
            >= 4
    });
    let requests = initial
        .iter()
        .filter(|event| event["kind"] == "attention_request")
        .collect::<Vec<_>>();
    assert_eq!(requests.len(), 4);
    assert!(
        requests
            .iter()
            .all(|event| event["payload"]["source"] == "iterm1337")
    );
    assert_eq!(
        requests
            .iter()
            .map(|event| event["payload"]["action"].as_str().unwrap())
            .collect::<Vec<_>>(),
        vec!["yes", "once", "fireworks", "no"]
    );

    let _ = wait_for_frame_containing(session_id, "OSC1337-ATTENTION-DONE");
    session::resize_session(session_id, 100, 30, 1000, 600).unwrap();
    session::write_session(session_id, b"continue\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "AFTER-ATTENTION-RESIZE");
    for _ in 0..10 {
        let payload = session::poll_events(session_id).unwrap();
        let events: serde_json::Value = serde_json::from_str(&payload).unwrap();
        assert!(
            events
                .as_array()
                .unwrap()
                .iter()
                .all(|event| event["kind"] != "attention_request"),
            "resize replay redelivered historical attention: {events}"
        );
        thread::sleep(Duration::from_millis(20));
    }
    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_iterm_attention_requests() {
    let session_id = session::create_session(
        &serde_json::to_string(&iterm_attention_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "attention_request");
    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_do_not_emit_clipboard_copy_events_from_osc_52() {
    let session_id =
        session::create_session(&serde_json::to_string(&vt220_clipboard_copy_profile()).unwrap())
            .unwrap();

    assert_event_kind_never_arrives(session_id, "clipboard_copy");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_clipboard_paste_requests_from_osc_52_queries() {
    let session_id = session::create_session(
        &serde_json::to_string(&clipboard_paste_request_profile()).unwrap(),
    )
    .unwrap();

    let event = wait_for_event(session_id, "clipboard_paste_request");
    assert_eq!(event["payload"]["selection"].as_str(), Some("c"));

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_do_not_emit_clipboard_paste_requests_from_osc_52_queries() {
    let session_id = session::create_session(
        &serde_json::to_string(&vt220_clipboard_paste_request_profile()).unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "clipboard_paste_request");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_binary_mime_write_list_and_read_requests_from_osc5522() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc5522_clipboard_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();
    let events = collect_events_until(session_id, |events| {
        ["clipboard_mime_write", "clipboard_mime_read_request"]
            .iter()
            .all(|kind| events.iter().any(|event| event["kind"] == *kind))
            && events
                .iter()
                .filter(|event| event["kind"] == "clipboard_mime_read_request")
                .count()
                == 2
    });
    let write = events
        .iter()
        .find(|event| event["kind"] == "clipboard_mime_write")
        .expect("expected MIME write");
    assert_eq!(write["payload"]["id"], "w1");
    assert_eq!(write["payload"]["items"][0]["mime"], "image/png");
    assert_eq!(write["payload"]["items"][0]["data"], "AAEC");
    assert_eq!(write["payload"]["items"][1]["mime"], "text/plain");
    assert_eq!(write["payload"]["password"], "secret");
    assert_eq!(write["payload"]["applicationName"], "Editor");
    assert!(events.iter().any(|event| {
        event["kind"] == "clipboard_mime_read_request"
            && event["payload"]["listOnly"] == true
            && event["payload"]["id"] == "list"
    }));
    assert!(events.iter().any(|event| {
        event["kind"] == "clipboard_mime_read_request"
            && event["payload"]["listOnly"] == false
            && event["payload"]["mimeTypes"][0] == "image/png"
            && event["payload"]["password"] == "one-time"
            && event["payload"]["applicationName"].is_null()
    }));
    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc5522_clipboard_events() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc5522_clipboard_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();
    for kind in [
        "clipboard_mime_write",
        "clipboard_mime_read_request",
        "clipboard_mime_error",
    ] {
        assert_event_kind_never_arrives(session_id, kind);
    }
    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_shell_context_from_osc7() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc7_shell_context_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let event = wait_for_event(session_id, "shell_context");
    assert_eq!(event["payload"]["source"].as_str(), Some("osc7"));
    assert_eq!(event["payload"]["cwd"].as_str(), Some("/tmp/ianvs project"));
    assert_eq!(
        event["payload"]["hostname"].as_str(),
        Some("remote.example.com")
    );
    assert_eq!(event["payload"]["username"].as_str(), Some("alice"));

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_do_not_emit_shell_context_from_osc7() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc7_shell_context_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "shell_context");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_osc9_9_shell_context_without_notification_side_effect() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc9_9_shell_context_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "shell_context"
                && event["payload"]["source"].as_str() == Some("osc9;9")
        })
    });
    let event = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_context"
                && event["payload"]["source"].as_str() == Some("osc9;9")
        })
        .expect("expected OSC 9;9 context");
    assert_eq!(event["payload"]["source"].as_str(), Some("osc9;9"));
    assert_eq!(event["payload"]["cwd"].as_str(), Some("/tmp/ianvs-osc9-9"));
    assert_eq!(
        event["payload"]["hostname"].as_str(),
        Some("remote.example")
    );
    assert_eq!(event["payload"]["username"].as_str(), Some("alice"));
    assert!(
        events
            .iter()
            .all(|event| event["kind"] != "session_notification")
    );
    assert_event_kind_never_arrives(session_id, "session_notification");

    session::close_session(session_id).unwrap();
}

#[test]
fn invalid_osc9_9_paths_emit_neither_context_nor_notification() {
    let session_id = session::create_session(
        &serde_json::to_string(&invalid_osc9_9_shell_context_profile()).unwrap(),
    )
    .unwrap();

    for _ in 0..10 {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        assert!(parsed.as_array().unwrap().iter().all(|event| {
            event["kind"] != "shell_context" && event["kind"] != "session_notification"
        }));
        thread::sleep(Duration::from_millis(50));
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc9_9_shell_context_and_notifications() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc9_9_shell_context_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    for _ in 0..10 {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        assert!(parsed.as_array().unwrap().iter().all(|event| {
            event["kind"] != "shell_context" && event["kind"] != "session_notification"
        }));
        thread::sleep(Duration::from_millis(50));
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_shell_context_from_osc1337_current_dir() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc1337_current_dir_profile()).unwrap())
            .unwrap();

    let event = wait_for_event(session_id, "shell_context");
    assert_eq!(
        event["payload"]["source"].as_str(),
        Some("osc1337_current_dir")
    );
    assert_eq!(event["payload"]["cwd"].as_str(), Some("/tmp/ianvs current"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_shell_command_events_from_osc133() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc133_shell_command_profile()).unwrap())
            .unwrap();

    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("semantic_prompt")
        }) && events.iter().any(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("command_executed")
        }) && events.iter().any(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("command_finished")
        }) && events.iter().any(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("zone_closed")
                && event["payload"]["zoneType"].as_str() == Some("output")
        })
    });
    let prompt = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("prompt_start")
        })
        .expect("expected prompt_start event");
    assert_eq!(prompt["payload"]["promptKind"].as_str(), Some("initial"));
    assert_eq!(prompt["payload"]["aid"].as_str(), Some("shell-1"));
    assert_eq!(prompt["payload"]["freshLine"].as_bool(), Some(true));
    let semantic = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("semantic_prompt")
        })
        .expect("expected semantic_prompt event");
    assert_eq!(
        semantic["payload"]["promptKind"].as_str(),
        Some("secondary")
    );
    assert_eq!(semantic["payload"]["freshLine"].as_bool(), Some(false));
    let executed = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("command_executed")
        })
        .expect("expected command_executed event");
    assert_eq!(executed["payload"]["command"].as_str(), Some("echo ok"));

    let finished = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("command_finished")
        })
        .expect("expected command_finished event");
    assert_eq!(finished["payload"]["exitCode"].as_i64(), Some(7));
    assert_eq!(finished["payload"]["aid"].as_str(), Some("shell-1"));

    let zone = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("zone_closed")
                && event["payload"]["zoneType"].as_str() == Some("output")
        })
        .expect("expected output zone_closed event");
    assert_eq!(zone["payload"]["exitCode"].as_i64(), Some(7));

    session::close_session(session_id).unwrap();
}

#[test]
fn resize_transcript_replay_does_not_redeliver_shell_events() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc133_resize_replay_profile()).unwrap())
            .unwrap();

    let initial = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("command_finished")
        })
    });
    assert!(initial.iter().any(|event| {
        event["kind"] == "shell_command"
            && event["payload"]["eventType"].as_str() == Some("command_finished")
    }));

    session::resize_session(session_id, 100, 30, 1000, 600).unwrap();
    session::write_session(session_id, b"continue\n").unwrap();
    let _ = wait_for_frame_containing(session_id, "AFTER-RESIZE");

    for _ in 0..10 {
        let payload = session::poll_events(session_id).unwrap();
        let events: serde_json::Value = serde_json::from_str(&payload).unwrap();
        assert!(
            events.as_array().unwrap().iter().all(|event| {
                event["kind"] != "shell_command"
                    && event["kind"] != "shell_context"
                    && event["kind"] != "session_notification"
            }),
            "resize replay redelivered historical host events: {events}"
        );
        thread::sleep(Duration::from_millis(20));
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_normalized_osc633_context_and_command_events() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc633_shell_command_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "shell_context"
                && event["payload"]["source"].as_str() == Some("osc633")
        }) && events.iter().any(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["source"].as_str() == Some("osc633")
                && event["payload"]["eventType"].as_str() == Some("command_finished")
        })
    });

    let context = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_context"
                && event["payload"]["source"].as_str() == Some("osc633")
        })
        .expect("expected OSC 633 cwd context");
    assert_eq!(
        context["payload"]["cwd"].as_str(),
        Some("/tmp/ianvs-osc633")
    );
    assert_eq!(
        context["payload"]["hostname"].as_str(),
        Some("remote.example")
    );
    assert_eq!(context["payload"]["username"].as_str(), Some("alice"));

    let executed = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["source"].as_str() == Some("osc633")
                && event["payload"]["eventType"].as_str() == Some("command_executed")
        })
        .expect("expected OSC 633 command_executed event");
    assert_eq!(
        executed["payload"]["command"].as_str(),
        Some("printf;value")
    );

    let finished = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["source"].as_str() == Some("osc633")
                && event["payload"]["eventType"].as_str() == Some("command_finished")
        })
        .expect("expected OSC 633 command_finished event");
    assert_eq!(finished["payload"]["exitCode"].as_i64(), Some(7));

    let serialized = serde_json::to_string(&events).unwrap();
    assert!(!serialized.contains("private-nonce-633"));
    assert!(
        events
            .iter()
            .all(|event| event["kind"] != "session_notification")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_rejects_osc633_command_metadata_with_mismatched_profile_nonce() {
    let mut profile = osc633_shell_command_profile(TerminalEmulation::Xterm256);
    profile.launch.env.insert(
        "VSCODE_NONCE".to_string(),
        "different-expected-nonce".to_string(),
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["source"].as_str() == Some("osc633")
                && event["payload"]["eventType"].as_str() == Some("command_finished")
        })
    });
    let executed = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["source"].as_str() == Some("osc633")
                && event["payload"]["eventType"].as_str() == Some("command_executed")
        })
        .expect("expected lifecycle event without unverified command metadata");
    assert!(executed["payload"]["command"].is_null());
    let serialized = serde_json::to_string(&events).unwrap();
    assert!(!serialized.contains("private-nonce-633"));
    assert!(!serialized.contains("different-expected-nonce"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_preserves_osc633_nonce_validation_across_resize_replay() {
    let session_id =
        session::create_session(&serde_json::to_string(&osc633_resize_nonce_profile()).unwrap())
            .unwrap();
    let _ = wait_for_frame_containing(session_id, "WAITING");

    session::resize_session(session_id, 100, 30, 1000, 600).unwrap();
    session::write_session(session_id, b"continue\n").unwrap();
    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["source"].as_str() == Some("osc633")
                && event["payload"]["eventType"].as_str() == Some("command_finished")
        })
    });
    let executed = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["source"].as_str() == Some("osc633")
                && event["payload"]["eventType"].as_str() == Some("command_executed")
        })
        .expect("expected post-resize OSC 633 lifecycle");
    assert_eq!(
        executed["payload"]["command"].as_str(),
        Some("after-resize")
    );
    assert!(
        !serde_json::to_string(&events)
            .unwrap()
            .contains("private-nonce-633")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_rejects_invalid_profile_osc633_nonce_without_echoing_it() {
    let mut profile = osc633_shell_command_profile(TerminalEmulation::Xterm256);
    profile.launch.env.insert(
        "VSCODE_NONCE".to_string(),
        "private;invalid;nonce".to_string(),
    );
    let error = session::create_session(&serde_json::to_string(&profile).unwrap())
        .expect_err("invalid nonce must fail before spawning the PTY");
    let message = error.to_string();
    assert!(message.contains("VSCODE_NONCE"));
    assert!(!message.contains("private;invalid;nonce"));
}

#[test]
fn vt220_sessions_gate_osc633_context_and_command_events() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc633_shell_command_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    for _ in 0..10 {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        assert!(
            parsed.as_array().unwrap().iter().all(|event| {
                event["kind"] != "shell_context" && event["kind"] != "shell_command"
            })
        );
        thread::sleep(Duration::from_millis(50));
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn alt_screen_osc133_does_not_emit_shell_command_events() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc133_alt_screen_shell_command_profile()).unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "shell_command");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_remote_host_and_user_var_from_osc1337() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_remote_host_user_var_profile()).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "shell_context"
                && event["payload"]["source"].as_str() == Some("osc1337_remote_host")
        }) && events.iter().any(|event| event["kind"] == "shell_user_var")
    });
    let context = events
        .iter()
        .find(|event| {
            event["kind"] == "shell_context"
                && event["payload"]["source"].as_str() == Some("osc1337_remote_host")
        })
        .expect("expected remote host context");
    assert_eq!(
        context["payload"]["hostname"].as_str(),
        Some("example.internal")
    );
    assert_eq!(context["payload"]["username"].as_str(), Some("deploy"));

    let user_var = events
        .iter()
        .find(|event| event["kind"] == "shell_user_var")
        .expect("expected user var event");
    assert_eq!(user_var["payload"]["name"].as_str(), Some("IANVS_TEST"));
    assert_eq!(user_var["payload"]["value"].as_str(), Some("hello"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_osc1337_mark_version_and_cell_size_request() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_shell_metadata_profile(TerminalEmulation::Xterm256))
            .unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("mark")
        }) && events.iter().any(|event| {
            event["kind"] == "shell_command"
                && event["payload"]["eventType"].as_str() == Some("integration_version")
        }) && events
            .iter()
            .any(|event| event["kind"] == "cell_size_report_request")
    });
    let mark = events
        .iter()
        .find(|event| event["payload"]["eventType"].as_str() == Some("mark"))
        .expect("expected OSC 1337 mark");
    assert_eq!(mark["payload"]["source"].as_str(), Some("osc1337"));
    assert_eq!(mark["payload"]["cursorLine"].as_u64(), Some(1));
    let version = events
        .iter()
        .find(|event| event["payload"]["eventType"].as_str() == Some("integration_version"))
        .expect("expected OSC 1337 integration version");
    assert_eq!(version["payload"]["version"].as_str(), Some("17"));
    assert_eq!(version["payload"]["shell"].as_str(), Some("zsh"));

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc1337_mark_version_and_cell_size_request() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_shell_metadata_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    for _ in 0..10 {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        assert!(parsed.as_array().unwrap().iter().all(|event| {
            event["kind"] != "shell_command" && event["kind"] != "cell_size_report_request"
        }));
        thread::sleep(Duration::from_millis(50));
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc1337_cursor_shape_crosses_real_pty_and_frame_codecs() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_cursor_shape_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC1337-CURSOR-BEAM");
    assert_frame_json_protobuf_cursor_override_parity(&frame, Some("beam"), None);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc1337_cursor_shape_only_emits_a_cursor_delta_frame() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_cursor_shape_only_profile()).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_where(session_id, |frame| {
        serde_json::from_str::<serde_json::Value>(frame)
            .ok()
            .and_then(|value| value["cursor"]["shape"].as_str().map(str::to_owned))
            .as_deref()
            == Some("beam")
    });
    assert_frame_json_protobuf_cursor_override_parity(&frame, Some("beam"), None);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_decscusr_cursor_style_crosses_real_pty_and_frame_codecs() {
    let session_id =
        session::create_session(&serde_json::to_string(&decscusr_cursor_shape_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "DECSCUSR-CURSOR-UNDERLINE");
    assert_frame_json_protobuf_cursor_override_parity(&frame, Some("underline"), Some(false));

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc1337_cursor_shape() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_cursor_shape_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC1337-CURSOR-BEAM");
    assert_frame_json_protobuf_cursor_override_parity(&frame, None, None);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc1337_cursor_guide_crosses_real_pty_and_frame_codecs() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_cursor_guide_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC1337-CURSOR-GUIDE");
    assert_frame_json_protobuf_cursor_guide_parity(&frame, true);

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc1337_cursor_guide() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_cursor_guide_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC1337-CURSOR-GUIDE");
    assert_frame_json_protobuf_cursor_guide_parity(&frame, false);

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc1337_clear_buffer_clears_scrollback_and_cannot_resurrect_on_resize() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_clear_buffer_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC1337-AFTER-CLEAR");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["scrollback_offset"].as_u64(), Some(0));
    assert_eq!(parsed["scrollback_max_offset"].as_u64(), Some(0));
    assert!(
        logical_rows_from_frame(&frame)
            .iter()
            .all(|row| !row.contains("OSC1337-OLD-"))
    );

    let exported: serde_json::Value =
        serde_json::from_str(&session::export_scrollback_session(session_id, None).unwrap())
            .unwrap();
    assert_eq!(exported["content"].as_str(), Some(""));
    let stats = session::take_session_debug_stats_json(session_id)
        .unwrap()
        .expect("expected session debug stats");
    let stats: serde_json::Value = serde_json::from_str(&stats).unwrap();
    assert_eq!(stats["transcript_truncated"].as_bool(), Some(true));

    session::resize_session(session_id, 96, 12, 0, 0).unwrap();
    let resized = wait_for_frame_where(session_id, |candidate| {
        let Ok(value) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        value["viewport_cols"].as_u64() == Some(96)
            && logical_rows_from_frame(candidate)
                .iter()
                .any(|row| row.contains("OSC1337-AFTER-CLEAR"))
    });
    assert!(
        logical_rows_from_frame(&resized)
            .iter()
            .all(|row| !row.contains("OSC1337-OLD-"))
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc1337_block_folding_crosses_real_pty_search_selection_and_runtime_requests() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_block_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();
    session::resize_session(session_id, 80, 6, 0, 0).unwrap();

    let frame = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        parsed["blocks"].as_array().is_some_and(|blocks| {
            blocks
                .iter()
                .any(|block| block["id"] == "build-1" && block["folded"] == true)
        }) && candidate.contains("OSC1337-BLOCK-DONE")
    });
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let block = parsed["blocks"]
        .as_array()
        .and_then(|blocks| blocks.first())
        .expect("expected folded OSC 1337 block");
    assert_eq!(block["id"], "build-1");
    assert_eq!(block["block_type"], "build");
    assert_eq!(block["start_row"].as_u64(), Some(0));
    assert_eq!(block["end_row"].as_u64(), Some(0));
    assert_eq!(block["source_start_row"].as_u64(), Some(0));
    assert_eq!(block["source_end_row"].as_u64(), Some(2));
    assert_eq!(block["hidden_rows"].as_u64(), Some(2));
    assert_eq!(block["rendered"].as_bool(), Some(true));
    let summary = frame_row_at_index(&parsed, 0);
    assert_eq!(summary["source_row"].as_u64(), Some(0));
    assert_eq!(summary["source_end_row"].as_u64(), Some(2));
    let summary_text = summary["text"].as_str().unwrap_or_default();
    assert!(summary_text.contains("block-first"));
    assert!(summary_text.contains("1 line"));
    assert!(summary_text.contains("block-last"));
    assert!(!frame.contains("block-secret"));

    let search = session::search_session(session_id, "block-secret").unwrap();
    let matches: serde_json::Value = serde_json::from_str(&search).unwrap();
    let hidden_match = matches
        .as_array()
        .and_then(|entries| entries.first())
        .expect("hidden block content should remain searchable");
    assert_eq!(hidden_match["row"].as_u64(), Some(1));
    assert_eq!(hidden_match["scrollback_offset"].as_u64(), Some(0));

    let selected =
        session::selection_text_session(session_id, &selection_request(0, 0, 2, 10, false))
            .unwrap();
    assert_eq!(selected, "block-first\nblock-secret\nblock-last");

    session::resize_session(session_id, 8, 6, 0, 0).unwrap();
    let narrow = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        parsed["blocks"].as_array().is_some_and(|blocks| {
            blocks.iter().any(|block| {
                block["id"] == "build-1"
                    && block["folded"] == true
                    && block["source_end_row"].as_u64().unwrap_or_default() > 2
            })
        })
    });
    let narrow: serde_json::Value = serde_json::from_str(&narrow).unwrap();
    let narrow_block = narrow["blocks"].as_array().unwrap().first().unwrap();
    assert!(narrow_block["hidden_rows"].as_u64().unwrap_or_default() > 2);

    session::resize_session(session_id, 80, 6, 0, 0).unwrap();
    let restored = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        parsed["blocks"].as_array().is_some_and(|blocks| {
            blocks.iter().any(|block| {
                block["id"] == "build-1"
                    && block["folded"] == true
                    && block["source_start_row"] == 0
                    && block["source_end_row"] == 2
            })
        })
    });
    assert!(restored.contains("OSC1337-BLOCK-DONE"));

    let unfold_request = serde_json::json!({
        "kind": "terminal.set_block_folded",
        "id": "build-1",
        "folded": false,
    });
    let response = session::request_session_json(session_id, &unfold_request.to_string())
        .unwrap()
        .expect("expected unfold response");
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&response).unwrap()["updated"],
        true
    );

    let unfolded = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        candidate.contains("block-secret")
            && parsed["blocks"].as_array().is_some_and(|blocks| {
                blocks
                    .iter()
                    .any(|block| block["id"] == "build-1" && block["folded"] == false)
            })
    });
    let unfolded: serde_json::Value = serde_json::from_str(&unfolded).unwrap();
    let block = unfolded["blocks"].as_array().unwrap().first().unwrap();
    assert_eq!(block["start_row"].as_u64(), Some(0));
    assert_eq!(block["end_row"].as_u64(), Some(2));
    assert_eq!(block["hidden_rows"].as_u64(), Some(0));
    assert_eq!(block["rendered"].as_bool(), Some(true));

    session::resize_session(session_id, 79, 6, 0, 0).unwrap();
    let resized_rendered = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        parsed["viewport_cols"] == 79
            && parsed["blocks"].as_array().is_some_and(|blocks| {
                blocks.iter().any(|block| {
                    block["id"] == "build-1"
                        && block["folded"] == false
                        && block["rendered"] == true
                })
            })
    });
    assert!(resized_rendered.contains("block-secret"));

    session::resize_session(session_id, 80, 6, 0, 0).unwrap();
    let restored_rendered = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        parsed["viewport_cols"] == 80
            && parsed["blocks"].as_array().is_some_and(|blocks| {
                blocks.iter().any(|block| {
                    block["id"] == "build-1"
                        && block["folded"] == false
                        && block["rendered"] == true
                })
            })
    });
    assert!(restored_rendered.contains("block-secret"));

    let restore_request = serde_json::json!({
        "kind": "terminal.set_block_rendered",
        "id": "build-1",
        "rendered": false,
    });
    let response = session::request_session_json(session_id, &restore_request.to_string())
        .unwrap()
        .expect("expected document restore response");
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&response).unwrap()["updated"],
        true
    );
    let restored_plain = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        parsed["blocks"].as_array().is_some_and(|blocks| {
            blocks.iter().any(|block| {
                block["id"] == "build-1" && block["folded"] == false && block["rendered"] == false
            })
        })
    });
    assert!(restored_plain.contains("block-secret"));

    session::resize_session(session_id, 79, 6, 0, 0).unwrap();
    let resized_plain = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        parsed["viewport_cols"] == 79
            && parsed["blocks"].as_array().is_some_and(|blocks| {
                blocks.iter().any(|block| {
                    block["id"] == "build-1"
                        && block["folded"] == false
                        && block["rendered"] == false
                })
            })
    });
    assert!(resized_plain.contains("block-secret"));

    let missing_request = serde_json::json!({
        "kind": "terminal.set_block_folded",
        "id": "missing",
        "folded": true,
    });
    let response = session::request_session_json(session_id, &missing_request.to_string())
        .unwrap()
        .expect("expected missing-block response");
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&response).unwrap()["updated"],
        false
    );
    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc1337_block_source_ranges_have_json_protobuf_parity() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_block_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();
    session::resize_session(session_id, 80, 6, 0, 0).unwrap();

    let deadline = Instant::now() + Duration::from_secs(3);
    let decoded = loop {
        if let Some(bytes) = session::take_frame_diff_protobuf(session_id).unwrap() {
            let decoded = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&bytes)
                .expect("valid protobuf frame");
            if decoded
                .blocks
                .iter()
                .any(|block| block.id == "build-1" && block.folded)
            {
                break decoded;
            }
        }
        assert!(
            Instant::now() < deadline,
            "timed out waiting for OSC 1337 block in protobuf frame"
        );
        thread::sleep(Duration::from_millis(10));
    };
    let block = decoded
        .blocks
        .iter()
        .find(|block| block.id == "build-1")
        .unwrap();
    assert_eq!(block.block_type, "build");
    assert_eq!((block.start_row, block.end_row), (0, 0));
    assert_eq!((block.source_start_row, block.source_end_row), (0, 2));
    assert_eq!(block.hidden_rows, 2);
    assert!(block.rendered);
    let summary = decoded.rows.iter().find(|row| row.index == 0).unwrap();
    assert_eq!(
        (summary.source_row, summary.source_end_row),
        (Some(0), Some(2))
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc1337_inline_buttons_cross_real_pty_frame_copy_and_exact_custom_reply() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_inline_button_profile(TerminalEmulation::Xterm256))
            .unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        candidate.contains("BUTTON-READY")
            && parsed["inline_buttons"]
                .as_array()
                .is_some_and(|buttons| buttons.len() == 2)
    });
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let buttons = parsed["inline_buttons"].as_array().unwrap();
    let copy = buttons
        .iter()
        .find(|button| button["kind"] == "copy")
        .unwrap();
    let custom = buttons
        .iter()
        .find(|button| button["kind"] == "custom")
        .unwrap();
    assert_eq!(copy["block_id"], "copy-1");
    assert_eq!(copy["width_cells"].as_u64(), Some(4));
    assert_eq!(custom["code"].as_i64(), Some(42));
    assert_eq!(custom["icon"], "star.fill");
    assert_eq!(custom["valid"].as_bool(), Some(true));

    let copy_request = serde_json::json!({
        "kind": "terminal.activate_iterm_button",
        "id": copy["id"].as_u64().unwrap(),
    });
    let copy_response = session::request_session_json(session_id, &copy_request.to_string())
        .unwrap()
        .expect("expected copy activation response");
    let copy_response: serde_json::Value = serde_json::from_str(&copy_response).unwrap();
    assert_eq!(copy_response["activated"], true);
    assert_eq!(copy_response["kind"], "copy");
    assert_eq!(copy_response["text"], "copy-exact");

    let custom_request = serde_json::json!({
        "kind": "terminal.activate_iterm_button",
        "id": custom["id"].as_u64().unwrap(),
    });
    let custom_response = session::request_session_json(session_id, &custom_request.to_string())
        .unwrap()
        .expect("expected custom activation response");
    let custom_response: serde_json::Value = serde_json::from_str(&custom_response).unwrap();
    assert_eq!(custom_response["activated"], true);
    assert_eq!(custom_response["kind"], "custom");

    let invalidated = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        candidate.contains("BUTTON-REPLY:1b5b3f313333373b34327e")
            && candidate.contains("BUTTON-INVALID")
            && parsed["inline_buttons"].as_array().is_some_and(|buttons| {
                buttons
                    .iter()
                    .any(|button| button["kind"] == "custom" && button["valid"] == false)
            })
    });
    assert!(invalidated.contains("BUTTON-REPLY:1b5b3f313333373b34327e"));

    let rejected = session::request_session_json(session_id, &custom_request.to_string())
        .unwrap()
        .expect("expected invalid custom response");
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&rejected).unwrap()["activated"],
        false
    );
    let missing = serde_json::json!({
        "kind": "terminal.activate_iterm_button",
        "id": u64::MAX,
    });
    let missing = session::request_session_json(session_id, &missing.to_string())
        .unwrap()
        .expect("expected stale button response");
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&missing).unwrap()["activated"],
        false
    );

    session::resize_session(session_id, 96, 12, 0, 0).unwrap();
    let resized = wait_for_frame_where(session_id, |candidate| {
        let Ok(parsed) = serde_json::from_str::<serde_json::Value>(candidate) else {
            return false;
        };
        parsed["viewport_cols"] == 96
            && parsed["inline_buttons"].as_array().is_some_and(|buttons| {
                buttons.len() == 2
                    && buttons
                        .iter()
                        .any(|button| button["kind"] == "custom" && button["valid"] == false)
            })
    });
    assert!(resized.contains("BUTTON-INVALID"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc1337_inline_buttons_have_protobuf_field_parity() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_inline_button_profile(TerminalEmulation::Xterm256))
            .unwrap(),
    )
    .unwrap();
    let deadline = Instant::now() + Duration::from_secs(3);
    let decoded = loop {
        if let Some(bytes) = session::take_frame_diff_protobuf(session_id).unwrap() {
            let decoded = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&bytes)
                .expect("valid protobuf frame");
            if decoded.inline_buttons.len() == 2 {
                break decoded;
            }
        }
        assert!(
            Instant::now() < deadline,
            "timed out waiting for OSC 1337 buttons in protobuf frame"
        );
        thread::sleep(Duration::from_millis(10));
    };
    let copy = decoded
        .inline_buttons
        .iter()
        .find(|button| button.kind == "copy")
        .unwrap();
    assert_eq!(copy.block_id, "copy-1");
    assert_eq!(copy.width_cells, 4);
    assert!(copy.valid);
    let custom = decoded
        .inline_buttons
        .iter()
        .find(|button| button.kind == "custom")
        .unwrap();
    assert_eq!(custom.code, Some(42));
    assert_eq!(custom.icon, "star.fill");
    assert_eq!(custom.width_cells, 4);
    assert!(custom.valid);
    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_do_not_expose_or_activate_osc1337_inline_buttons() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_inline_button_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();
    let frame = wait_for_frame_containing(session_id, "BUTTON-READY");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert!(parsed["inline_buttons"].as_array().unwrap().is_empty());
    let request = serde_json::json!({
        "kind": "terminal.activate_iterm_button",
        "id": 1,
    });
    let response = session::request_session_json(session_id, &request.to_string())
        .unwrap()
        .expect("expected VT220 rejection response");
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&response).unwrap()["activated"],
        false
    );
    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc1337_clear_buffer() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc1337_clear_buffer_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "OSC1337-AFTER-CLEAR");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert!(parsed["scrollback_max_offset"].as_u64().unwrap_or(0) > 0);
    let exported: serde_json::Value =
        serde_json::from_str(&session::export_scrollback_session(session_id, None).unwrap())
            .unwrap();
    assert!(
        exported["content"]
            .as_str()
            .is_some_and(|text| text.contains("OSC1337-OLD-00"))
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_osc9_osc777_osc934_notification_progress_and_badge_events() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc_notification_progress_badge_profile()).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "session_notification"
                && event["payload"]["message"].as_str() == Some("Build finished")
        }) && events.iter().any(|event| {
            event["kind"] == "session_notification"
                && event["payload"]["title"].as_str() == Some("Deploy")
        }) && events.iter().any(|event| {
            event["kind"] == "session_progress"
                && event["payload"]["source"].as_str() == Some("osc9;4")
        }) && events.iter().any(|event| {
            event["kind"] == "session_progress"
                && event["payload"]["source"].as_str() == Some("ianvs_osc934")
        }) && events.iter().any(|event| event["kind"] == "session_badge")
    });
    let osc9_notification = events
        .iter()
        .find(|event| {
            event["kind"] == "session_notification"
                && event["payload"]["message"].as_str() == Some("Build finished")
        })
        .expect("expected OSC 9 notification");
    assert_eq!(osc9_notification["payload"]["title"].as_str(), Some(""));

    let osc777_notification = events
        .iter()
        .find(|event| {
            event["kind"] == "session_notification"
                && event["payload"]["title"].as_str() == Some("Deploy")
        })
        .expect("expected OSC 777 notification");
    assert_eq!(
        osc777_notification["payload"]["message"].as_str(),
        Some("Done")
    );

    let primary_progress = events
        .iter()
        .find(|event| {
            event["kind"] == "session_progress"
                && event["payload"]["source"].as_str() == Some("osc9;4")
        })
        .expect("expected OSC 9;4 progress");
    assert_eq!(
        primary_progress["payload"]["state"].as_str(),
        Some("normal")
    );
    assert_eq!(primary_progress["payload"]["percent"].as_u64(), Some(55));

    let named_progress = events
        .iter()
        .find(|event| {
            event["kind"] == "session_progress"
                && event["payload"]["source"].as_str() == Some("ianvs_osc934")
        })
        .expect("expected OSC 934 named progress");
    assert_eq!(named_progress["payload"]["id"].as_str(), Some("build"));
    assert_eq!(named_progress["payload"]["percent"].as_u64(), Some(80));
    assert_eq!(
        named_progress["payload"]["label"].as_str(),
        Some("Compiling")
    );

    let badge = events
        .iter()
        .find(|event| event["kind"] == "session_badge")
        .expect("expected badge event");
    assert_eq!(badge["payload"]["text"].as_str(), Some("Build"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_osc21337_crosses_real_pty_as_ordered_incremental_events() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc21337_tab_status_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let _ = wait_for_frame_containing(session_id, "OSC21337-READY");
    let events = collect_events_until(session_id, |events| {
        events
            .iter()
            .filter(|event| event["kind"] == "session_tab_status")
            .count()
            >= 2
    });
    let updates = events
        .iter()
        .filter(|event| event["kind"] == "session_tab_status")
        .collect::<Vec<_>>();
    assert_eq!(updates.len(), 2);
    assert_eq!(updates[0]["payload"]["source"].as_str(), Some("osc21337"));
    assert_eq!(updates[0]["payload"]["indicator"].as_str(), Some("#ff9500"));
    assert_eq!(
        updates[0]["payload"]["status"].as_str(),
        Some("Working;phase")
    );
    assert_eq!(
        updates[0]["payload"]["statusColor"].as_str(),
        Some("#5f87ff")
    );
    assert_eq!(
        updates[1]["payload"]["indicatorPresent"].as_bool(),
        Some(false)
    );
    assert_eq!(
        updates[1]["payload"]["statusPresent"].as_bool(),
        Some(false)
    );
    assert_eq!(
        updates[1]["payload"]["statusColorPresent"].as_bool(),
        Some(true)
    );
    assert!(updates[1]["payload"]["statusColor"].is_null());

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc21337_tab_status() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc21337_tab_status_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    let _ = wait_for_frame_containing(session_id, "OSC21337-READY");
    for _ in 0..10 {
        let events = session::poll_events(session_id).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&events).unwrap();
        assert!(
            parsed
                .as_array()
                .unwrap()
                .iter()
                .all(|event| event["kind"] != "session_tab_status")
        );
        thread::sleep(Duration::from_millis(25));
    }

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_typed_osc99_show_update_and_close_events() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc99_notification_lifecycle_profile()).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events
            .iter()
            .filter(|event| {
                event["kind"] == "session_notification"
                    && event["payload"]["source"].as_str() == Some("osc99")
            })
            .count()
            >= 3
    });
    let notifications = events
        .iter()
        .filter(|event| {
            event["kind"] == "session_notification"
                && event["payload"]["source"].as_str() == Some("osc99")
        })
        .collect::<Vec<_>>();
    assert_eq!(notifications.len(), 3);

    let show = notifications
        .iter()
        .find(|event| event["payload"]["action"].as_str() == Some("show"))
        .expect("expected OSC 99 show event");
    assert_eq!(show["payload"]["id"].as_str(), Some("build"));
    assert_eq!(show["payload"]["title"].as_str(), Some("Title"));
    assert_eq!(show["payload"]["message"].as_str(), Some("Body"));
    assert_eq!(show["payload"]["application"].as_str(), Some("buildctl"));
    assert_eq!(show["payload"]["types"][0].as_str(), Some("deploy"));
    assert_eq!(show["payload"]["expiresAfterMs"].as_u64(), Some(250));
    assert_eq!(show["payload"]["reportActivation"].as_bool(), Some(true));
    assert_eq!(show["payload"]["reportClose"].as_bool(), Some(true));
    assert_eq!(show["payload"]["buttons"][0].as_str(), Some("Approve"));
    assert_eq!(show["payload"]["buttons"][1].as_str(), Some("Retry"));

    let update = notifications
        .iter()
        .find(|event| event["payload"]["action"].as_str() == Some("update"))
        .expect("expected OSC 99 update event");
    assert_eq!(update["payload"]["title"].as_str(), Some("Updated"));

    let close = notifications
        .iter()
        .find(|event| event["payload"]["action"].as_str() == Some("close"))
        .expect("expected OSC 99 close event");
    assert_eq!(close["payload"]["id"].as_str(), Some("build"));
    assert_eq!(close["payload"]["title"].as_str(), Some(""));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_typed_osc3008_hierarchy_and_recovers_malformed_close() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc3008_context_profile(TerminalEmulation::Xterm256)).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events
            .iter()
            .filter(|event| event["kind"] == "terminal_context")
            .count()
            >= 4
    });
    let contexts = events
        .iter()
        .filter(|event| event["kind"] == "terminal_context")
        .collect::<Vec<_>>();
    assert_eq!(contexts.len(), 4, "unknown end must not emit an event");

    assert_eq!(contexts[0]["payload"]["source"].as_str(), Some("osc3008"));
    assert_eq!(contexts[0]["payload"]["action"].as_str(), Some("start"));
    assert_eq!(contexts[0]["payload"]["id"].as_str(), Some("root"));
    assert_eq!(contexts[0]["payload"]["depth"].as_u64(), Some(1));
    assert_eq!(contexts[0]["payload"]["user"].as_str(), Some("dev;ops"));
    assert_eq!(contexts[0]["payload"]["cwd"].as_str(), Some("/work\\dir"));
    assert_eq!(contexts[0]["payload"]["pid"].as_u64(), Some(42));

    assert_eq!(contexts[1]["payload"]["id"].as_str(), Some("child"));
    assert_eq!(contexts[1]["payload"]["depth"].as_u64(), Some(2));
    assert_eq!(
        contexts[1]["payload"]["commandLine"].as_str(),
        Some("dart test")
    );

    assert_eq!(contexts[2]["payload"]["action"].as_str(), Some("update"));
    assert_eq!(
        contexts[2]["payload"]["implicitClosedCount"].as_u64(),
        Some(1)
    );
    assert!(contexts[2]["payload"]["cwd"].is_null());

    assert_eq!(contexts[3]["payload"]["action"].as_str(), Some("end"));
    assert_eq!(contexts[3]["payload"]["depth"].as_u64(), Some(0));
    assert_eq!(contexts[3]["payload"]["active"].as_bool(), Some(false));
    assert_eq!(contexts[3]["payload"]["exit"].as_str(), Some("success"));
    assert_eq!(contexts[3]["payload"]["status"].as_u64(), Some(0));

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_sessions_gate_osc3008_context_events() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc3008_context_profile(TerminalEmulation::Vt220)).unwrap(),
    )
    .unwrap();

    assert_event_kind_never_arrives(session_id, "terminal_context");

    session::close_session(session_id).unwrap();
}

#[test]
fn session_emits_osc9_indeterminate_progress_without_synthetic_percent() {
    let session_id = session::create_session(
        &serde_json::to_string(&osc9_indeterminate_progress_profile()).unwrap(),
    )
    .unwrap();

    let events = collect_events_until(session_id, |events| {
        events.iter().any(|event| {
            event["kind"] == "session_progress"
                && event["payload"]["source"].as_str() == Some("osc9;4")
        })
    });
    let progress = events
        .iter()
        .find(|event| {
            event["kind"] == "session_progress"
                && event["payload"]["source"].as_str() == Some("osc9;4")
        })
        .expect("expected OSC 9;4 progress");
    assert_eq!(progress["payload"]["state"].as_str(), Some("indeterminate"));
    assert!(progress["payload"].get("percent").is_none());

    session::close_session(session_id).unwrap();
}

#[test]
fn session_apc_sequence_is_unsupported_noop() {
    let session_id =
        session::create_session(&serde_json::to_string(&apc_unsupported_noop_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "before");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let rows = logical_rows_from_frame(&frame);
    assert!(
        rows.iter().any(|row| row.contains("beforeafter")),
        "APC should not interrupt surrounding printable text: {rows:?}"
    );
    assert!(
        !frame.contains("APC-LEAK"),
        "APC payload must not render into terminal rows: {frame}"
    );
    assert!(
        parsed["rows"]
            .as_array()
            .expect("expected rows")
            .iter()
            .all(|row| !row["text"]
                .as_str()
                .unwrap_or_default()
                .contains("APC-LEAK"))
    );

    let events = session::poll_events(session_id).unwrap();
    assert!(
        !events.contains("APC-LEAK"),
        "APC payload must not surface through app events: {events}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_pm_and_sos_sequences_are_unsupported_noops() {
    let session_id = session::create_session(
        &serde_json::to_string(&non_csi_string_controls_profile()).unwrap(),
    )
    .unwrap();

    let frame = wait_for_frame_containing(session_id, "pre");
    let rows = logical_rows_from_frame(&frame);
    assert!(
        rows.iter().any(|row| row.contains("premidpost")),
        "PM/SOS should not interrupt surrounding printable text: {rows:?}"
    );
    assert!(
        !frame.contains("PM-LEAK") && !frame.contains("SOS-LEAK"),
        "PM/SOS payloads must not render into terminal rows: {frame}"
    );

    let events = session::poll_events(session_id).unwrap();
    assert!(
        !events.contains("PM-LEAK") && !events.contains("SOS-LEAK"),
        "PM/SOS payloads must not surface through app events: {events}"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn vt220_wraparound_repaint_keeps_full_width_rows_dirty_and_complete() {
    let session_id = session::create_session(
        &serde_json::to_string(&vt220_wraparound_repaint_profile()).unwrap(),
    )
    .unwrap();
    session::resize_session(session_id, 5, 4, 0, 0).unwrap();

    let mut first_phase_history = Vec::new();
    let mut saw_first_phase = false;
    for _ in 0..20 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            first_phase_history.push(frame.clone());
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            saw_first_phase = parsed["rows"].as_array().is_some_and(|rows| {
                rows.iter()
                    .find(|row| row["index"].as_u64() == Some(1))
                    .and_then(|row| row["text"].as_str())
                    == Some("***  ")
            });
            if saw_first_phase {
                break;
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    assert!(
        saw_first_phase,
        "timed out waiting for initial shorter middle row: {}",
        first_phase_history.join("\n---\n")
    );

    let mut second_phase_history = Vec::new();
    let mut second = None;
    for _ in 0..20 {
        if let Some(frame) = session::take_frame_diff(session_id).unwrap() {
            second_phase_history.push(frame.clone());
            let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
            let has_full_rows = parsed["rows"].as_array().is_some_and(|rows| {
                rows.iter()
                    .find(|row| row["index"].as_u64() == Some(0))
                    .and_then(|row| row["text"].as_str())
                    == Some("*****")
                    && rows
                        .iter()
                        .find(|row| row["index"].as_u64() == Some(1))
                        .and_then(|row| row["text"].as_str())
                        == Some("*****")
                    && rows
                        .iter()
                        .find(|row| row["index"].as_u64() == Some(2))
                        .and_then(|row| row["text"].as_str())
                        == Some("*****")
            });
            if has_full_rows {
                second = Some(frame);
                break;
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    let second = second.unwrap_or_else(|| {
        panic!(
            "timed out waiting for full-width wrap repaint: {}",
            second_phase_history.join("\n---\n")
        )
    });

    let second_parsed: serde_json::Value = serde_json::from_str(&second).unwrap();
    assert_eq!(
        frame_row_at_index(&second_parsed, 0)["text"].as_str(),
        Some("*****")
    );
    assert_eq!(
        frame_row_at_index(&second_parsed, 1)["text"].as_str(),
        Some("*****")
    );
    assert_eq!(
        frame_row_at_index(&second_parsed, 2)["text"].as_str(),
        Some("*****")
    );
    assert!(
        second_parsed["dirty_ranges"]
            .as_array()
            .is_some_and(|ranges| ranges.iter().any(|range| {
                range["start"].as_u64() == Some(0) && range["end"].as_u64().unwrap_or_default() >= 3
            })),
        "wrap-around repaint should cover all three rows in at least one dirty range: {}",
        serde_json::to_string_pretty(&second_parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn xterm_sessions_surface_osc8_hyperlink_ranges() {
    let session_id =
        session::create_session(&serde_json::to_string(&hyperlink_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "Docs");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let hyperlinks = parsed["hyperlinks"]
        .as_array()
        .expect("expected hyperlink ranges");

    assert_eq!(hyperlinks.len(), 1);
    assert_eq!(hyperlinks[0]["row"].as_u64(), Some(0));
    assert_eq!(hyperlinks[0]["start_col"].as_u64(), Some(0));
    assert_eq!(hyperlinks[0]["end_col"].as_u64(), Some(4));
    assert_eq!(
        hyperlinks[0]["uri"].as_str(),
        Some("https://example.com/docs")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn xterm_sessions_preserve_distinct_osc8_protocol_ids_in_json_and_protobuf() {
    let session_id =
        session::create_session(&serde_json::to_string(&hyperlink_protocol_id_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "One Two");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let hyperlinks = parsed["hyperlinks"]
        .as_array()
        .expect("expected hyperlink ranges");
    assert_eq!(hyperlinks.len(), 2);
    assert_eq!(hyperlinks[0]["uri"], "https://example.com/docs");
    assert_eq!(hyperlinks[0]["protocol_id"], "first");
    assert_eq!(hyperlinks[1]["uri"], "https://example.com/docs");
    assert_eq!(hyperlinks[1]["protocol_id"], "second");

    session::close_session(session_id).unwrap();

    let protobuf_session_id =
        session::create_session(&serde_json::to_string(&hyperlink_protocol_id_profile()).unwrap())
            .unwrap();
    let deadline = Instant::now() + Duration::from_secs(3);
    let decoded = loop {
        if let Some(bytes) = session::take_frame_diff_protobuf(protobuf_session_id).unwrap() {
            let decoded = ianvs_core::frame_diff_proto::decode_frame_diff_for_test(&bytes)
                .expect("valid protobuf frame");
            if decoded.hyperlinks.len() == 2 {
                break decoded;
            }
        }
        assert!(
            Instant::now() < deadline,
            "timed out waiting for OSC 8 protocol IDs in protobuf frame"
        );
        thread::sleep(Duration::from_millis(10));
    };
    assert_eq!(decoded.hyperlinks[0].protocol_id, "first");
    assert_eq!(decoded.hyperlinks[1].protocol_id, "second");
    session::close_session(protobuf_session_id).unwrap();
}

#[test]
fn vt220_sessions_do_not_surface_osc8_hyperlink_ranges() {
    let session_id =
        session::create_session(&serde_json::to_string(&vt220_hyperlink_profile()).unwrap())
            .unwrap();

    let frame = wait_for_frame_containing(session_id, "Docs");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let hyperlinks = parsed["hyperlinks"]
        .as_array()
        .expect("expected hyperlink ranges");

    assert!(hyperlinks.is_empty());

    session::close_session(session_id).unwrap();
}

#[test]
fn session_searches_scrollback_text_without_changing_scroll_position() {
    let session_id =
        session::create_session(&serde_json::to_string(&scrollback_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "line79");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["scrollback_offset"].as_u64(), Some(0));

    let search = session::search_session(session_id, "line05").unwrap();
    let matches: serde_json::Value = serde_json::from_str(&search).unwrap();
    let first = matches
        .as_array()
        .and_then(|entries| entries.first())
        .expect("expected search match");

    assert_eq!(first["text"].as_str(), Some("line05"));
    assert_eq!(first["start_col"].as_u64(), Some(0));
    assert_eq!(first["end_col"].as_u64(), Some(6));
    assert!(
        first["scrollback_offset"].as_u64().unwrap_or_default() > 0,
        "expected old scrollback match to have a non-zero scrollback offset"
    );

    let frame_after = session::take_frame_diff(session_id).unwrap();
    assert!(
        frame_after.is_none(),
        "search should not dirty or scroll the terminal"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_search_empty_query_returns_no_matches() {
    let session_id =
        session::create_session(&serde_json::to_string(&scrollback_profile()).unwrap()).unwrap();

    wait_for_frame_containing(session_id, "line79");

    let search = session::search_session(session_id, "").unwrap();
    let matches: serde_json::Value = serde_json::from_str(&search).unwrap();

    assert_eq!(matches.as_array().map(Vec::len), Some(0));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_wrapped_line_search_matches_across_visual_rows() {
    let session_id =
        session::create_session(&serde_json::to_string(&wrapped_selection_profile()).unwrap())
            .unwrap();

    thread::sleep(Duration::from_millis(200));
    session::resize_session(session_id, 5, 4, 50, 80).unwrap();
    let _ = wait_for_frame_where(session_id, |frame| {
        logical_rows_from_frame(frame)
            .iter()
            .any(|row| row == "abcdefghij")
    });

    let search = session::search_session(session_id, "defg").unwrap();
    let matches: serde_json::Value = serde_json::from_str(&search).unwrap();
    let first = matches
        .as_array()
        .and_then(|entries| entries.first())
        .expect("expected wrapped search match");

    assert_eq!(first["text"].as_str(), Some("defg"));
    assert_eq!(first["row"].as_u64(), Some(0));
    assert_eq!(first["start_col"].as_u64(), Some(3));
    assert_eq!(first["end_col"].as_u64(), Some(7));
    assert_eq!(first["scrollback_offset"].as_u64(), Some(0));

    let frame_after = session::take_frame_diff(session_id).unwrap();
    assert!(
        frame_after.is_none(),
        "search should not dirty or scroll the terminal"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_search_request_supports_substring_case_modes() {
    let session_id =
        session::create_session(&serde_json::to_string(&search_modes_profile()).unwrap()).unwrap();

    let frame = wait_for_frame_containing(session_id, "err 200");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed["scrollback_offset"].as_u64(), Some(0));

    let smart_lower = search_request(session_id, "alpha", "smart_case_substring");
    assert_eq!(smart_lower["error_text"].as_str(), None);
    assert_eq!(smart_lower["matches"].as_array().map(Vec::len), Some(2));

    let smart_upper = search_request(session_id, "Alpha", "smart_case_substring");
    assert_eq!(smart_upper["matches"].as_array().map(Vec::len), Some(1));
    assert_eq!(smart_upper["matches"][0]["text"].as_str(), Some("Alpha"));

    let case_sensitive = search_request(session_id, "alpha", "case_sensitive_substring");
    assert_eq!(case_sensitive["matches"].as_array().map(Vec::len), Some(1));
    assert_eq!(case_sensitive["matches"][0]["text"].as_str(), Some("alpha"));

    let case_insensitive = search_request(session_id, "alpha", "case_insensitive_substring");
    assert_eq!(
        case_insensitive["matches"].as_array().map(Vec::len),
        Some(2)
    );

    let frame_after = session::take_frame_diff(session_id).unwrap();
    assert!(
        frame_after.is_none(),
        "search should not dirty or scroll the terminal"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_search_request_supports_regex_modes_and_errors() {
    let session_id =
        session::create_session(&serde_json::to_string(&search_modes_profile()).unwrap()).unwrap();

    wait_for_frame_containing(session_id, "err 200");

    let case_sensitive = search_request(session_id, r"ERR \d+", "case_sensitive_regex");
    assert_eq!(case_sensitive["error_text"].as_str(), None);
    assert_eq!(case_sensitive["matches"].as_array().map(Vec::len), Some(1));
    assert_eq!(
        case_sensitive["matches"][0]["text"].as_str(),
        Some("ERR 100")
    );

    let case_insensitive = search_request(session_id, r"ERR \d+", "case_insensitive_regex");
    assert_eq!(
        case_insensitive["matches"].as_array().map(Vec::len),
        Some(2)
    );
    assert_eq!(
        case_insensitive["matches"][1]["text"].as_str(),
        Some("err 200")
    );

    let invalid = search_request(session_id, r"ERR \d+(", "case_sensitive_regex");
    assert_eq!(invalid["matches"].as_array().map(Vec::len), Some(0));
    assert_eq!(
        invalid["error_text"].as_str(),
        Some("Invalid regular expression")
    );

    let frame_after = session::take_frame_diff(session_id).unwrap();
    assert!(
        frame_after.is_none(),
        "search should not dirty or scroll the terminal"
    );

    session::close_session(session_id).unwrap();
}

fn search_request(session_id: u64, query: &str, mode: &str) -> serde_json::Value {
    let request = serde_json::json!({
        "kind": "terminal.search_text",
        "query": query,
        "mode": mode,
    });
    let response = session::request_session_json(session_id, &request.to_string())
        .unwrap()
        .expect("expected search response");
    serde_json::from_str(&response).unwrap()
}

#[test]
fn interactive_session_accepts_input_and_emits_output() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();

    thread::sleep(Duration::from_millis(250));
    let _ = session::take_frame_diff(session_id);

    session::write_session(session_id, b"printf 'roundtrip\\n'\n").unwrap();

    let frame = wait_for_frame_containing(session_id, "roundtrip");
    assert!(frame.contains("roundtrip"));

    session::write_session(session_id, b"exit\n").unwrap();
    session::close_session(session_id).unwrap();
}

#[test]
fn first_frame_uses_snapshot_kind_and_incremental_output_uses_delta_kind() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let initial = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected initial frame");
    let initial_parsed: serde_json::Value = serde_json::from_str(&initial).unwrap();
    assert_eq!(initial_parsed["frame_kind"].as_str(), Some("snapshot"));

    session::write_session(session_id, b"printf 'delta-one\\n'\n").unwrap();

    let updated = wait_for_frame_containing(session_id, "delta-one");
    let updated_parsed: serde_json::Value = serde_json::from_str(&updated).unwrap();
    assert_eq!(updated_parsed["frame_kind"].as_str(), Some("delta"));
    assert!(
        updated_parsed["rows"]
            .as_array()
            .expect("expected frame rows")
            .len()
            < updated_parsed["viewport_rows"]
                .as_u64()
                .expect("expected viewport row count") as usize,
        "delta frame should only send changed rows: {}",
        serde_json::to_string_pretty(&updated_parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn style_only_output_changes_still_mark_the_row_dirty() {
    let session_id =
        session::create_session(&serde_json::to_string(&style_only_change_profile()).unwrap())
            .unwrap();

    let first = wait_for_frame_containing(session_id, "same");
    let second = wait_for_frame_containing(session_id, "same");

    let first_parsed: serde_json::Value = serde_json::from_str(&first).unwrap();
    let second_parsed: serde_json::Value = serde_json::from_str(&second).unwrap();
    let first_row = frame_row_with_text(&first_parsed, "same");
    let second_row = frame_row_with_text(&second_parsed, "same");
    let first_foreground = first_row["style_runs"]
        .as_array()
        .and_then(|runs| runs.first())
        .and_then(|run| run["foreground"].as_str())
        .expect("expected first foreground");
    let second_foreground = second_row["style_runs"]
        .as_array()
        .and_then(|runs| runs.first())
        .and_then(|run| run["foreground"].as_str())
        .expect("expected second foreground");

    assert_ne!(first_foreground, second_foreground);
    assert_eq!(second_parsed["frame_kind"].as_str(), Some("delta"));
    assert_eq!(
        second_parsed["dirty_ranges"]
            .as_array()
            .expect("expected dirty ranges")
            .first()
            .and_then(|range| range["start"].as_u64()),
        Some(
            second_row["index"]
                .as_u64()
                .expect("expected dirty row index")
        ),
        "style-only changes should still flag the row dirty: {}",
        serde_json::to_string_pretty(&second_parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn scrolling_output_keeps_using_delta_frames_after_viewport_advances() {
    let session_id =
        session::create_session(&serde_json::to_string(&streaming_scrollback_profile()).unwrap())
            .unwrap();
    session::resize_session(session_id, 40, 5, 0, 0).unwrap();

    let _ = wait_for_frame_containing(session_id, "line06");

    let second = wait_for_frame_containing(session_id, "line13");
    let second_parsed: serde_json::Value = serde_json::from_str(&second).unwrap();
    assert_eq!(
        second_parsed["frame_kind"].as_str(),
        Some("delta"),
        "streaming output should stay on the delta path even after the visible window advances: {}",
        serde_json::to_string_pretty(&second_parsed).unwrap()
    );
    assert!(
        second_parsed["viewport_row_shift"]
            .as_i64()
            .expect("expected viewport row shift")
            < 0,
        "streaming delta frame should report that the viewport moved upward: {}",
        serde_json::to_string_pretty(&second_parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn single_line_scroll_reports_viewport_row_shift_and_bottom_dirty_range() {
    let gate = tempdir().unwrap();
    let gate_path = gate.path().join("continue");
    let session_id = session::create_session(
        &serde_json::to_string(&single_line_scroll_shift_profile(&gate_path)).unwrap(),
    )
    .unwrap();
    session::resize_session(session_id, 40, 5, 0, 0).unwrap();

    let _ = wait_for_frame_containing(session_id, "line04");
    fs::write(&gate_path, "").unwrap();

    let shifted = wait_for_frame_containing(session_id, "line05");
    let shifted_parsed: serde_json::Value = serde_json::from_str(&shifted).unwrap();

    assert_eq!(shifted_parsed["frame_kind"].as_str(), Some("delta"));
    assert_eq!(shifted_parsed["viewport_row_shift"].as_i64(), Some(-1));
    assert_eq!(
        shifted_parsed["dirty_ranges"].as_array(),
        Some(&vec![serde_json::json!({
            "start": 3,
            "end": 5,
        })]),
        "single-line viewport scroll should only dirty the newly revealed line plus the trailing cursor row: {}",
        serde_json::to_string_pretty(&shifted_parsed).unwrap()
    );
    assert_eq!(
        shifted_parsed["rows"]
            .as_array()
            .expect("expected delta rows")
            .len(),
        2,
        "single-line viewport scroll should only emit the newly revealed line plus the trailing cursor row: {}",
        serde_json::to_string_pretty(&shifted_parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn damage_driven_delta_reports_low_rows_scanned_for_single_line_scroll() {
    let gate = tempdir().unwrap();
    let gate_path = gate.path().join("continue");
    let session_id = session::create_session(
        &serde_json::to_string(&single_line_scroll_shift_profile(&gate_path)).unwrap(),
    )
    .unwrap();
    session::resize_session(session_id, 40, 5, 0, 0).unwrap();

    let _ = wait_for_frame_containing(session_id, "line04");
    fs::write(&gate_path, "").unwrap();
    let _ = wait_for_frame_containing(session_id, "line05");
    let debug_stats = session::take_frame_debug_stats_json(session_id)
        .unwrap()
        .expect("expected frame debug stats");
    let parsed: serde_json::Value = serde_json::from_str(&debug_stats).unwrap();

    assert_eq!(parsed["viewport_row_shift"].as_i64(), Some(-1));
    assert_eq!(parsed["rows_emitted"].as_u64(), Some(2));
    assert_eq!(parsed["full_repaint"].as_bool(), Some(false));
    assert!(parsed["snapshot_fallback_reason"].is_null());
    assert!(parsed["state_lock_wait_micros"].as_u64().is_some());
    assert!(parsed["frame_extract_micros"].as_u64().is_some());
    assert!(parsed["json_encode_micros"].as_u64().is_some());
    let rows_scanned = parsed["rows_scanned"]
        .as_u64()
        .expect("expected rows_scanned");
    assert!(
        rows_scanned <= 5,
        "single-line scroll debug scan should stay bounded to the visible viewport: {}",
        serde_json::to_string_pretty(&parsed).unwrap()
    );
    assert!(
        rows_scanned >= parsed["rows_emitted"].as_u64().unwrap_or_default(),
        "debug scan accounting should cover emitted rows: {}",
        serde_json::to_string_pretty(&parsed).unwrap()
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn clear_screen_falls_back_to_snapshot_with_reason() {
    let session_id =
        session::create_session(&serde_json::to_string(&clear_screen_profile()).unwrap()).unwrap();
    session::resize_session(session_id, 40, 5, 0, 0).unwrap();

    let _ = wait_for_frame_containing(session_id, "before");
    let frame = wait_for_frame_containing(session_id, "after");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let debug_stats = session::take_frame_debug_stats_json(session_id)
        .unwrap()
        .expect("expected frame debug stats");
    let debug_parsed: serde_json::Value = serde_json::from_str(&debug_stats).unwrap();

    assert_eq!(parsed["frame_kind"].as_str(), Some("snapshot"));
    assert_eq!(debug_parsed["full_repaint"].as_bool(), Some(true));
    assert_eq!(
        debug_parsed["snapshot_fallback_reason"].as_str(),
        Some("clear_screen")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn session_debug_stats_accumulate_input_processing_costs() {
    let session_id =
        session::create_session(&serde_json::to_string(&test_profile()).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "hello");

    let stats = session::take_session_debug_stats_json(session_id)
        .unwrap()
        .expect("expected session debug stats");
    let parsed: serde_json::Value = serde_json::from_str(&stats).unwrap();

    assert!(parsed["bytes_read"].as_u64().unwrap_or_default() > 0);
    assert!(parsed["read_chunks"].as_u64().unwrap_or_default() > 0);
    assert!(parsed["terminal_process_micros"].as_u64().is_some());
    assert!(parsed["host_protocol_micros"].as_u64().is_some());
    assert!(parsed["damage_merge_micros"].as_u64().is_some());
    assert!(parsed["pending_dirty_rows"].as_u64().is_some());
    for key in [
        "osc_ingress_accepted",
        "osc_ingress_oversized",
        "osc_ingress_policy_denied",
        "synchronized_update_discards",
        "non_sixel_dcs_discards",
        "response_buffer_overflows",
        "vendor_terminal_event_drops",
        "tmux_notification_drops",
        "recording_dropped_events",
    ] {
        assert!(parsed[key].as_u64().is_some(), "missing {key}: {parsed}");
    }
    let breakdown = &parsed["terminal_process_breakdown"];
    assert!(
        breakdown.is_object(),
        "missing terminal_process_breakdown: {parsed}"
    );
    assert!(breakdown["process_calls"].as_u64().unwrap_or_default() > 0);
    assert!(breakdown["process_bytes"].as_u64().unwrap_or_default() > 0);
    assert!(breakdown["plain_ascii_bytes"].as_u64().unwrap_or_default() > 0);
    assert!(breakdown["escape_or_control_bytes"].as_u64().is_some());
    assert!(breakdown["parser_advance_micros"].as_u64().is_some());
    assert!(breakdown["scroll_micros"].as_u64().is_some());

    session::close_session(session_id).unwrap();
}

#[test]
fn diagnostics_export_returns_privacy_preserving_evidence_package() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(1100));

    let request = serde_json::json!({
        "kind": "terminal.export_diagnostics",
        "maxSamples": 4,
        "includeContent": true,
        "redactionMode": "basic",
    });
    let response = session::request_session_json(session_id, &request.to_string())
        .unwrap()
        .expect("expected diagnostics export response");
    let parsed: serde_json::Value = serde_json::from_str(&response).unwrap();

    assert_eq!(
        parsed["manifest"]["schema_version"].as_str(),
        Some("terminal-diagnostics-session-v1")
    );
    assert_eq!(parsed["manifest"]["session_id"].as_u64(), Some(session_id));
    assert_eq!(
        parsed["manifest"]["content_included"].as_bool(),
        Some(false)
    );
    assert_eq!(
        parsed["manifest"]["include_content_requested"].as_bool(),
        Some(true)
    );
    assert_eq!(parsed["manifest"]["redaction_mode"].as_str(), Some("basic"));
    assert!(
        parsed["manifest"]["child_pid"].is_u64(),
        "expected captured child pid: {parsed}"
    );

    let samples = parsed["resource_samples"]
        .as_array()
        .expect("expected resource samples");
    assert!(!samples.is_empty());
    assert!(samples.len() <= 4);
    assert!(samples.windows(2).all(|window| {
        window[0]["timestamp_micros"].as_u64().unwrap_or_default()
            <= window[1]["timestamp_micros"].as_u64().unwrap_or_default()
    }));
    assert!(parsed["terminal_stats"]["session"].is_object());
    assert!(parsed["events"].as_array().is_some());
    assert_eq!(
        parsed["summary"]["conclusion"].as_str(),
        Some("insufficient-evidence")
    );
    assert!(
        parsed["summary"]["markdown"]
            .as_str()
            .unwrap_or_default()
            .contains("Privacy handling")
    );
    assert!(
        !response.contains("USER="),
        "diagnostics response should not include raw env"
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn diagnostics_export_reports_shell_integration_gate_status() {
    let mut profile = interactive_profile();
    profile.shell_integration.enabled = false;
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();

    let request = serde_json::json!({
        "kind": "terminal.export_diagnostics",
        "maxSamples": 1,
    });
    let response = session::request_session_json(session_id, &request.to_string())
        .unwrap()
        .expect("expected diagnostics export response");
    let parsed: serde_json::Value = serde_json::from_str(&response).unwrap();
    let started = parsed["events"]
        .as_array()
        .expect("expected diagnostics events")
        .iter()
        .find(|entry| entry["kind"] == "started")
        .expect("expected started diagnostics event");

    assert_eq!(
        started["payload"]["shell_integration"]["status"].as_str(),
        Some("disabled")
    );
    assert_eq!(
        started["payload"]["shell_integration"]["reason"].as_str(),
        Some("disabled_by_profile")
    );

    session::close_session(session_id).unwrap();
}

#[test]
fn diagnostics_export_after_session_close_fails_stably() {
    let session_id =
        session::create_session(&serde_json::to_string(&interactive_profile()).unwrap()).unwrap();
    session::close_session(session_id).unwrap();

    let request = serde_json::json!({
        "kind": "terminal.export_diagnostics",
    });

    assert!(session::request_session_json(session_id, &request.to_string()).is_err());
}

#[test]
fn pending_event_queue_reports_overflow_and_retains_critical_events_under_bell_spam() {
    let profile = local_profile(
        "pending-event-bell-spam",
        "Pending Event Bell Spam",
        "/bin/sh",
        vec![
            "-lc".to_string(),
            r#"python3 - <<'PY'
import sys
sys.stdout.write('\x1b]52;c;?\x1b\\' + '\a' * 5000 + 'DONE\n')
sys.stdout.flush()
PY"#
            .to_string(),
        ],
        BTreeMap::new(),
        TerminalEmulation::Xterm256,
    );
    let session_id = session::create_session(&serde_json::to_string(&profile).unwrap()).unwrap();
    let _ = wait_for_frame_containing(session_id, "DONE");

    let stats = loop {
        let stats = session::take_session_debug_stats_json(session_id)
            .unwrap()
            .expect("expected session debug stats");
        let parsed: serde_json::Value = serde_json::from_str(&stats).unwrap();
        if parsed["pending_event_overflowed"].as_bool() == Some(true) {
            break parsed;
        }
        thread::sleep(Duration::from_millis(10));
    };
    assert!(stats["pending_event_count"].as_u64().unwrap_or_default() <= 1024);
    assert!(stats["pending_event_bytes"].as_u64().unwrap_or_default() <= 8 * 1024 * 1024);
    assert!(
        stats["pending_event_dropped_count"]
            .as_u64()
            .unwrap_or_default()
            > 0
    );

    let diagnostics_request = serde_json::json!({
        "kind": "terminal.export_diagnostics",
        "maxSamples": 1,
    });
    let diagnostics = session::request_session_json(session_id, &diagnostics_request.to_string())
        .unwrap()
        .expect("expected diagnostics response");
    let diagnostics: serde_json::Value = serde_json::from_str(&diagnostics).unwrap();
    let overflow_diagnostics = diagnostics["events"]
        .as_array()
        .expect("expected diagnostic events")
        .iter()
        .filter(|event| event["kind"] == "event_queue_overflow")
        .collect::<Vec<_>>();
    assert_eq!(overflow_diagnostics.len(), 1);
    assert!(overflow_diagnostics[0]["payload"].is_null());

    let deadline = Instant::now() + Duration::from_secs(3);
    let mut events = Vec::new();
    while Instant::now() < deadline {
        events.extend(session::take_events(session_id).unwrap());
        if events.iter().any(|event| event.kind == "exit") {
            break;
        }
        thread::sleep(Duration::from_millis(10));
    }
    assert!(
        events
            .iter()
            .any(|event| event.kind == "clipboard_paste_request")
    );
    assert!(events.iter().any(|event| event.kind == "exit"));

    session::close_session(session_id).unwrap();
}

#[test]
fn scrollback_heavy_transcript_is_bounded_and_resize_still_returns_snapshot() {
    let session_id =
        session::create_session(&serde_json::to_string(&large_transcript_profile()).unwrap())
            .unwrap();
    let _ = wait_for_frame_containing(session_id, "line-08999");

    let stats = session::take_session_debug_stats_json(session_id)
        .unwrap()
        .expect("expected session debug stats");
    let parsed: serde_json::Value = serde_json::from_str(&stats).unwrap();
    assert_eq!(parsed["transcript_truncated"].as_bool(), Some(true));
    assert!(parsed["transcript_bytes"].as_u64().unwrap_or_default() <= 262_144);

    session::resize_session(session_id, 100, 20, 1000, 400).unwrap();
    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame after resize");
    let parsed_frame: serde_json::Value = serde_json::from_str(&frame).unwrap();
    assert_eq!(parsed_frame["frame_kind"].as_str(), Some("snapshot"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_preserves_trailing_spaces_in_row_text() {
    let session_id =
        session::create_session(&serde_json::to_string(&prompt_like_profile()).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let rows = parsed["rows"].as_array().expect("expected rows");
    let text = rows[0]["text"].as_str().expect("expected row text");

    assert!(text.starts_with("abc   "));
    assert!(text.ends_with(' '));
    assert!(text.len() > 6);
    let style_runs = rows[0]["style_runs"]
        .as_array()
        .expect("expected style runs");
    let first_run = &style_runs[0];
    assert_eq!(first_run["background"].as_str(), Some("#00ff00"));
    assert_eq!(first_run["foreground"].as_str(), Some("#ff0000"));

    session::close_session(session_id).unwrap();
}

#[test]
fn session_sgr_colon_truecolor_skips_empty_color_space_id() {
    let session_id =
        session::create_session(&serde_json::to_string(&sgr_colon_truecolor_profile()).unwrap())
            .unwrap();
    thread::sleep(Duration::from_millis(250));

    let frame = session::take_frame_diff(session_id)
        .unwrap()
        .expect("expected frame diff");
    let parsed: serde_json::Value = serde_json::from_str(&frame).unwrap();
    let rows = parsed["rows"].as_array().expect("expected rows");
    assert!(
        rows[0]["text"]
            .as_str()
            .expect("expected row text")
            .starts_with("RB"),
        "expected row to start with styled cells: {frame}"
    );

    let style_runs = rows[0]["style_runs"]
        .as_array()
        .expect("expected style runs");
    assert_eq!(style_runs[0]["foreground"].as_str(), Some("#ff0000"));
    assert_eq!(style_runs[1]["background"].as_str(), Some("#0000ff"));

    session::close_session(session_id).unwrap();
}

#[test]
fn parser_sgr_reset_cases_clear_individual_attributes() {
    let mut terminal = ParserTerminal::new(80, 24);
    terminal.process(b"\x1b[1;2;3;4;5;7;8;9;53m\x1b[38;5;1m\x1b[48;5;2m\x1b[58:5:3mA");
    terminal.process(b"\x1b[22;23;24;25;27;28;29;39;49;55;59mB");

    let rows = terminal.get_row_range(0, 1);
    let styled = &rows[0][0];
    assert!(styled.flags.bold());
    assert!(styled.flags.dim());
    assert!(styled.flags.italic());
    assert!(styled.flags.underline());
    assert!(styled.flags.blink());
    assert!(styled.flags.reverse());
    assert!(styled.flags.hidden());
    assert!(styled.flags.strikethrough());
    assert!(styled.flags.overline());
    assert_eq!(styled.fg, Color::Named(NamedColor::Red));
    assert_eq!(styled.bg, Color::Named(NamedColor::Green));
    assert_eq!(
        styled.underline_color,
        Some(Color::Named(NamedColor::Yellow))
    );

    let reset = &rows[0][1];
    assert!(!reset.flags.bold());
    assert!(!reset.flags.dim());
    assert!(!reset.flags.italic());
    assert!(!reset.flags.underline());
    assert!(!reset.flags.blink());
    assert!(!reset.flags.reverse());
    assert!(!reset.flags.hidden());
    assert!(!reset.flags.strikethrough());
    assert!(!reset.flags.overline());
    assert_eq!(reset.fg, Color::Named(NamedColor::White));
    assert_eq!(reset.bg, Color::Named(NamedColor::Black));
    assert_eq!(reset.underline_color, None);
}

#[test]
fn parser_sgr_underline_color_accepts_semicolon_indexed_and_truecolor() {
    let mut terminal = ParserTerminal::new(80, 24);

    terminal.process(b"\x1b[58;5;3mA\x1b[58;2;0;0;4mB\x1b[59mC");

    let rows = terminal.get_row_range(0, 1);
    assert_eq!(
        rows[0][0].underline_color,
        Some(Color::Named(NamedColor::Yellow))
    );
    assert_eq!(rows[0][1].underline_color, Some(Color::Rgb(0, 0, 4)));
    assert_eq!(rows[0][2].underline_color, None);
}

fn snapshot_test_kitty_graphic() -> TerminalGraphic {
    let mut graphic = TerminalGraphic::new(
        next_graphic_id(),
        GraphicProtocol::Kitty,
        (5, 2),
        2,
        1,
        vec![255, 0, 0, 255, 0, 255, 0, 255],
    );
    graphic.kitty_image_id = Some(77);
    graphic.kitty_placement_id = Some(1);
    graphic
}

fn animation_virtual_placement(image_id: u32, placement_id: u32) -> TerminalGraphic {
    let mut graphic = TerminalGraphic::new(
        next_graphic_id(),
        GraphicProtocol::Kitty,
        (3, 4),
        1,
        1,
        vec![255, 0, 0, 255],
    );
    graphic.kitty_image_id = Some(image_id);
    graphic.kitty_placement_id = Some(placement_id);
    graphic
}

#[test]
fn graphics_animation_current_frame_updates_virtual_placements() {
    let mut store = GraphicsStore::new();
    store.add_virtual_placement(animation_virtual_placement(90, 1));
    let initial_asset_version = store.get_virtual_placement(90, 1).unwrap().asset_version;
    store.add_animation_frame(90, AnimationFrame::new(1, vec![255, 0, 0, 255], 1, 1));
    store.add_animation_frame(90, AnimationFrame::new(2, vec![0, 255, 0, 255], 1, 1));

    assert!(store.set_animation_current_frame(90, 2));

    let restored = store
        .get_virtual_placement(90, 1)
        .expect("expected Kitty virtual placement");
    assert_eq!(restored.pixels.as_ref().as_slice(), &[0, 255, 0, 255]);
    assert_eq!(restored.width, 1);
    assert_eq!(restored.height, 1);
    assert_ne!(restored.asset_version, initial_asset_version);
}

#[test]
fn graphics_animation_tick_updates_virtual_placements() {
    let mut store = GraphicsStore::new();
    store.add_virtual_placement(animation_virtual_placement(91, 1));
    store.add_animation_frame(
        91,
        AnimationFrame::new(1, vec![255, 0, 0, 255], 1, 1).with_delay(1),
    );
    store.add_animation_frame(
        91,
        AnimationFrame::new(2, vec![0, 255, 0, 255], 1, 1).with_delay(1),
    );
    store.control_animation(91, AnimationControl::EnableLooping);
    thread::sleep(Duration::from_millis(2));

    let changed = store.update_animations();

    assert_eq!(changed, vec![91]);
    let restored = store
        .get_virtual_placement(91, 1)
        .expect("expected Kitty virtual placement");
    assert_eq!(restored.pixels.as_ref().as_slice(), &[0, 255, 0, 255]);
}

#[test]
fn graphics_animation_current_frame_updates_shared_image_reuse() {
    let mut store = GraphicsStore::new();
    store.store_kitty_image(92, 1, 1, vec![255, 0, 0, 255]);
    store.add_animation_frame(92, AnimationFrame::new(1, vec![255, 0, 0, 255], 1, 1));
    store.add_animation_frame(92, AnimationFrame::new(2, vec![0, 255, 0, 255], 1, 1));

    assert!(store.set_animation_current_frame(92, 2));

    let restored = store
        .get_kitty_image(92)
        .expect("expected Kitty shared image");
    assert_eq!(restored.0, 1);
    assert_eq!(restored.1, 1);
    assert_eq!(restored.2.as_ref().as_slice(), &[0, 255, 0, 255]);
}

#[test]
fn graphics_animation_stop_resets_active_virtual_and_shared_images() {
    let mut store = GraphicsStore::new();
    let mut active_graphic = animation_virtual_placement(93, 1);
    active_graphic.is_virtual = false;
    store.add_graphic(active_graphic);
    store.add_virtual_placement(animation_virtual_placement(93, 2));
    store.store_kitty_image(93, 1, 1, vec![255, 0, 0, 255]);
    store.add_animation_frame(93, AnimationFrame::new(1, vec![255, 0, 0, 255], 1, 1));
    store.add_animation_frame(93, AnimationFrame::new(2, vec![0, 255, 0, 255], 1, 1));
    assert!(store.set_animation_current_frame(93, 2));
    assert_eq!(
        store.all_graphics()[0].pixels.as_ref().as_slice(),
        &[0, 255, 0, 255]
    );

    store.control_animation(93, AnimationControl::Stop);

    assert_eq!(
        store.all_graphics()[0].pixels.as_ref().as_slice(),
        &[255, 0, 0, 255]
    );
    assert_eq!(
        store
            .get_virtual_placement(93, 2)
            .expect("expected Kitty virtual placement")
            .pixels
            .as_ref()
            .as_slice(),
        &[255, 0, 0, 255]
    );
    assert_eq!(
        store
            .get_kitty_image(93)
            .expect("expected Kitty shared image")
            .2
            .as_ref()
            .as_slice(),
        &[255, 0, 0, 255]
    );
}

#[test]
fn graphics_snapshot_round_trip_preserves_kitty_shared_images() {
    let mut store = GraphicsStore::new();
    store.store_kitty_image(77, 2, 1, vec![10, 20, 30, 40, 50, 60, 70, 80]);

    let snapshot = store.export_snapshot();
    assert_eq!(snapshot.shared_images.len(), 1);
    assert_eq!(snapshot.shared_images[0].image_id, 77);

    let mut restored_store = GraphicsStore::new();
    let count = restored_store.import_snapshot(&snapshot).unwrap();

    assert_eq!(count, 0);
    let restored = restored_store
        .get_kitty_image(77)
        .expect("expected restored Kitty shared image");
    assert_eq!(restored.0, 2);
    assert_eq!(restored.1, 1);
    assert_eq!(
        restored.2.as_ref().as_slice(),
        &[10, 20, 30, 40, 50, 60, 70, 80]
    );
}

#[test]
fn graphics_snapshot_round_trip_preserves_virtual_placements() {
    let mut store = GraphicsStore::new();
    let mut virtual_graphic = snapshot_test_kitty_graphic();
    virtual_graphic.kitty_image_id = Some(88);
    virtual_graphic.kitty_placement_id = Some(3);
    virtual_graphic.position = (12, 7);
    virtual_graphic.parent_image_id = Some(77);
    virtual_graphic.parent_placement_id = Some(1);
    virtual_graphic.relative_x_offset = 4;
    virtual_graphic.relative_y_offset = -1;
    store.add_virtual_placement(virtual_graphic.clone());

    let snapshot = store.export_snapshot();
    assert_eq!(snapshot.virtual_placements.len(), 1);

    let mut restored_store = GraphicsStore::new();
    let count = restored_store.import_snapshot(&snapshot).unwrap();

    assert_eq!(count, 0);
    let restored = restored_store
        .get_virtual_placement(88, 3)
        .expect("expected restored Kitty virtual placement");
    assert!(restored.is_virtual);
    assert_eq!(restored.position, (12, 7));
    assert_eq!(restored.parent_image_id, Some(77));
    assert_eq!(restored.parent_placement_id, Some(1));
    assert_eq!(restored.relative_x_offset, 4);
    assert_eq!(restored.relative_y_offset, -1);
    assert_eq!(restored.pixels.as_ref(), virtual_graphic.pixels.as_ref());
}

#[test]
fn graphics_snapshot_import_accepts_json_without_additive_fields() {
    let mut store = GraphicsStore::new();

    let count = store
        .import_json(r#"{"version":1,"placements":[],"scrollback":[],"animations":[]}"#)
        .unwrap();

    assert_eq!(count, 0);
    assert_eq!(store.graphics_count(), 0);
    assert!(store.all_virtual_placements().is_empty());
}
