# Protobuf Frame Diff Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an experimental protobuf frame diff transport that can run beside the current JSON path, with JSON remaining the default.

**Architecture:** Rust keeps producing the same `TerminalFrameDiff` semantic object, then encodes it either as JSON or protobuf bytes. `ianvs_pty` only carries bytes across FFI; `ianvs_terminal` decodes protobuf bytes and maps them back to the existing `TerminalFrameDiff`, so viewport merge and Flutter rendering stay unchanged.

**Tech Stack:** Rust 2024, `prost` protobuf runtime, Dart/Flutter, `package:protobuf`, FFI, existing benchmark/profile harnesses.

---

## File Structure

- Create `native/core/proto/frame_diff.proto`
  - Single schema source for local FFI frame diff protobuf.
- Create `native/core/src/proto/mod.rs`
  - Exposes generated Rust protobuf module.
- Create `native/core/src/proto/frame_diff.rs`
  - Generated Rust protobuf code committed to the repo.
- Create `native/core/src/frame_diff_proto.rs`
  - Converts `model::TerminalFrameDiff` to protobuf bytes and debug stats.
- Create `native/core/build.rs`
  - Regenerates Rust protobuf only when `regenerate-proto` feature is enabled.
- Modify `native/core/Cargo.toml`
  - Adds `prost` and optional `prost-build`.
- Modify `native/core/src/lib.rs`
  - Exports `proto` and `frame_diff_proto`.
- Modify `native/core/src/session.rs`
  - Adds protobuf encode path and `protobuf_encode_micros` stats.
- Modify `native/core/src/ffi.rs`
  - Adds bytes-returning FFI function and bytes free function.
- Modify `native/core/tests/session_test.rs`
  - Adds Rust encode and FFI protobuf tests.
- Create `tools/gen_frame_diff_proto.sh`
  - Regenerates Rust and Dart protobuf files.
- Modify `packages/ianvs_terminal/pubspec.yaml`
  - Adds protobuf runtime dependency.
- Create `packages/ianvs_terminal/lib/src/proto/frame_diff.pb.dart`
  - Generated Dart protobuf code committed to the repo.
- Create `packages/ianvs_terminal/lib/src/runtime/terminal_frame_transport.dart`
  - Defines `TerminalFrameTransport` and fallback reasons.
- Create `packages/ianvs_terminal/lib/src/runtime/terminal_frame_protobuf_codec.dart`
  - Decodes protobuf bytes into `TerminalFrameDiff`.
- Modify `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
  - Adds transport switch, protobuf decode path, fallback metrics.
- Modify `packages/ianvs_terminal/lib/ianvs_terminal.dart`
  - Exports public transport enum.
- Modify `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
  - Adds runtime transport tests.
- Create `packages/ianvs_terminal/test/terminal_frame_protobuf_codec_test.dart`
  - Adds decoder fixture tests.
- Modify `packages/ianvs_pty/lib/src/native_pty_backend.dart`
  - Adds optional protobuf bytes lookup and transport interface.
- Modify `example/test/support/fake_pty_backend.dart`
  - Adds protobuf fake support for tests/profile harness.
- Modify `example/test/support/test_runtime.dart`
  - Accepts `frameTransport`.
- Modify `example/lib/features/sessions/session_controller.dart`
  - Reads a provider-backed transport setting.
- Modify `example/lib/app_bootstrap.dart`
  - Lets app/profile harness inject frame transport.
- Modify `example/integration_test/terminal_render_profile_test.dart`
  - Adds `IANVS_FRAME_TRANSPORT` and writes runtime stats for transport runs.
- Modify `example/lib/benchmarks/terminal_render_profile_report.dart`
  - Writes `dart_runtime.ndjson`, native frame stats, and transport summary fields.
- Modify `tools/bench/src/replay_terminal.dart`
  - Emits synthetic JSON/protobuf transport fields.
- Modify `tools/bench/src/summary_analyzer.dart`
  - Summarizes transport fields.
- Modify `tools/bench/README.md`, `docs/FRAME_DIFF.md`, `docs/TESTING.md`
  - Documents protobuf transport and release gate commands.

## Implementation Notes

- JSON stays the default everywhere.
- `decode_error`, `schema_mismatch`, and `missing_required_field` are experiment failures. Do not silently apply a stale frame.
- `unsupported_backend` is the only fallback reason allowed for compatibility tests. It must not occur in a real protobuf release-gate run.
- The existing render profile currently updates `TerminalViewportController` directly. The protobuf release-gate work must add a runtime-transport profile path instead of assuming the current render-only harness proves FFI transport.
- Native baseline note from 2026-07-02 investigation: default-parallel `cargo test --test session_test` can flake in graphics + alternate-screen frame-diff tests because they depend on transient frames emitted by real child-process scripts with fixed sleeps. Focused tests and full serial `cargo test --test session_test -- --test-threads=1` passed on the clean worktree. Use the serial full `session_test` command as the native baseline gate unless the test synchronization is fixed separately.

---

### Task 1: Add Protobuf Schema And Generation Tooling

**Files:**
- Create: `native/core/proto/frame_diff.proto`
- Create: `native/core/build.rs`
- Create: `native/core/src/proto/mod.rs`
- Create generated: `native/core/src/proto/frame_diff.rs`
- Create generated: `packages/ianvs_terminal/lib/src/proto/frame_diff.pb.dart`
- Create generated: `packages/ianvs_terminal/lib/src/proto/frame_diff.pbenum.dart`
- Create: `tools/gen_frame_diff_proto.sh`
- Modify: `native/core/Cargo.toml`
- Modify: `native/core/src/lib.rs`
- Modify: `packages/ianvs_terminal/pubspec.yaml`

- [ ] **Step 1: Add the schema**

Create `native/core/proto/frame_diff.proto` with this content:

```protobuf
syntax = "proto3";

package frame_diff;

message TerminalFrameDiff {
  string frame_schema_version = 1;
  TerminalFrameKind frame_kind = 2;
  repeated TerminalRow rows = 3;
  TerminalCursor cursor = 4;
  TerminalSelection selection = 5;
  uint32 viewport_rows = 6;
  uint32 viewport_cols = 7;
  repeated TerminalDirtyRange dirty_ranges = 8;
  uint32 scrollback_offset = 9;
  uint32 scrollback_max_offset = 10;
  uint32 viewport_start_row = 11;
  int32 viewport_row_shift = 12;
  ColorRgb default_foreground = 13;
  ColorRgb default_background = 14;
  ColorRgb cursor_color = 15;
  TerminalFrameModes modes = 16;
  string window_title = 17;
  string window_icon_name = 18;
  repeated TerminalHyperlinkRange hyperlinks = 19;
  repeated TerminalInlineImage inline_images = 20;
  repeated TerminalGraphicPlacement graphics = 21;
}

enum TerminalFrameKind {
  TERMINAL_FRAME_KIND_UNSPECIFIED = 0;
  TERMINAL_FRAME_KIND_SNAPSHOT = 1;
  TERMINAL_FRAME_KIND_DELTA = 2;
}

message TerminalRow {
  uint32 index = 1;
  string text = 2;
  bool wrapped = 3;
  int64 modified_at_micros = 4;
  repeated TerminalStyleRun style_runs = 5;
}

message TerminalStyleRun {
  uint32 start = 1;
  uint32 end = 2;
  ColorRgb foreground = 3;
  ColorRgb background = 4;
  bool bold = 5;
  bool dim = 6;
  bool italic = 7;
  bool underline = 8;
  bool blink = 9;
  bool inverse = 10;
}

message ColorRgb {
  bool present = 1;
  uint32 rgb = 2;
}

message TerminalCursor {
  uint32 row = 1;
  uint32 col = 2;
  bool visible = 3;
}

message TerminalSelection {
  bool present = 1;
  uint32 start_row = 2;
  uint32 start_col = 3;
  uint32 end_row = 4;
  uint32 end_col = 5;
}

message TerminalDirtyRange {
  uint32 start = 1;
  uint32 end = 2;
}

message TerminalFrameModes {
  bool alternate_screen = 1;
  bool alternate_scroll = 2;
  bool application_cursor = 3;
  bool application_keypad = 4;
  bool insert_mode = 5;
  bool origin_mode = 6;
  bool line_feed_new_line_mode = 7;
  bool hide_cursor = 8;
  bool bracketed_paste = 9;
  bool focus_tracking = 10;
  bool char_protected = 11;
  string mouse_mode = 12;
  string mouse_encoding = 13;
  uint32 kitty_keyboard_flags = 14;
  bool synchronized_output = 15;
}

message TerminalHyperlinkRange {
  uint32 row = 1;
  uint32 start_col = 2;
  uint32 end_col = 3;
  string uri = 4;
}

message TerminalInlineImage {
  string data = 1;
  string mime_type = 2;
  uint32 row = 3;
  uint32 col = 4;
  uint32 width_cells = 5;
  uint32 height_cells = 6;
  string alt_text = 7;
}

message TerminalGraphicAssetKey {
  uint32 asset_id = 1;
  uint32 asset_version = 2;
}

message TerminalGraphicPlacement {
  uint32 placement_id = 1;
  uint32 render_id = 2;
  TerminalGraphicAssetKey asset_key = 3;
  string protocol = 4;
  uint32 row = 5;
  uint32 col = 6;
  uint32 width_px = 7;
  uint32 height_px = 8;
  uint32 width_cells = 9;
  uint32 height_cells = 10;
  uint32 source_x_offset_px = 11;
  uint32 visible_width_px = 12;
  uint32 source_y_offset_px = 13;
  uint32 visible_height_px = 14;
  int32 z_index = 15;
  int32 x_offset_px = 16;
  int32 y_offset_px = 17;
  bool preserve_aspect_ratio = 18;
}
```

- [ ] **Step 2: Add Rust dependencies and generation feature**

Modify `native/core/Cargo.toml` so the relevant sections contain:

```toml
[package]
name = "ianvs_core"
version = "0.1.0"
edition = "2024"
build = "build.rs"

[features]
regenerate-proto = ["prost-build"]

[dependencies]
anyhow = "1.0"
libc = "0.2"
parking_lot = "0.12"
portable-pty = "0.9.0"
par-term-emu-core-rust = { path = "../vendor/par-term-emu-core-rust", default-features = false, features = ["rust-only"] }
prost = "0.14.3"
regex = "1.12.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
strip-ansi-escapes = "0.2.1"
thiserror = "2.0"

[dev-dependencies]
cbindgen = "0.29.2"
tempfile = "3.23.0"

[build-dependencies.prost-build]
version = "0.14.3"
optional = true
```

- [ ] **Step 3: Add Rust build script**

Create `native/core/build.rs`:

```rust
fn main() {
    #[cfg(feature = "regenerate-proto")]
    {
        println!("cargo:rerun-if-changed=proto/frame_diff.proto");
        prost_build::Config::new()
            .out_dir("src/proto")
            .compile_protos(&["proto/frame_diff.proto"], &["proto"])
            .expect("failed to compile frame_diff.proto");
    }
}
```

- [ ] **Step 4: Add Rust proto module**

Create `native/core/src/proto/mod.rs`:

```rust
pub mod frame_diff {
    include!("frame_diff.rs");
}
```

Modify `native/core/src/lib.rs`:

```rust
pub mod ffi;
pub mod frame_diff_proto;
pub mod model;
pub mod platform;
pub mod proto;
pub mod pty;
pub mod session;

pub use ffi::*;
```

- [ ] **Step 5: Add Dart protobuf dependency**

Modify `packages/ianvs_terminal/pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  fixnum: ^1.1.1
  ianvs_pty:
    path: ../ianvs_pty
  protobuf: ^6.0.0
```

Run:

```bash
dart pub get
```

Expected: `pubspec.lock` updates and `packages/ianvs_terminal` can resolve `package:fixnum/fixnum.dart` and `package:protobuf/protobuf.dart`.

- [ ] **Step 6: Add generation script**

Create `tools/gen_frame_diff_proto.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
proto_file="$repo_root/native/core/proto/frame_diff.proto"
rust_out="$repo_root/native/core/src/proto"
dart_out="$repo_root/packages/ianvs_terminal/lib/src/proto"

if ! command -v protoc >/dev/null 2>&1; then
  echo "protoc is required to regenerate frame diff protobuf files." >&2
  exit 1
fi

mkdir -p "$rust_out" "$dart_out"

(
  cd "$repo_root/native/core"
  cargo build --features regenerate-proto
)

if ! command -v protoc-gen-dart >/dev/null 2>&1; then
  echo "protoc-gen-dart is required. Install it with: dart pub global activate protoc_plugin" >&2
  exit 1
fi

protoc \
  --proto_path="$repo_root/native/core/proto" \
  --dart_out="$dart_out" \
  "$proto_file"
```

Run:

```bash
chmod +x tools/gen_frame_diff_proto.sh
./tools/gen_frame_diff_proto.sh
```

Expected generated files:

```text
native/core/src/proto/frame_diff.rs
packages/ianvs_terminal/lib/src/proto/frame_diff.pb.dart
packages/ianvs_terminal/lib/src/proto/frame_diff.pbenum.dart
```

- [ ] **Step 7: Verify generation artifacts compile**

Run:

```bash
cd native/core
cargo test --no-run
```

Expected: compile succeeds.

Run:

```bash
cd packages/ianvs_terminal
dart analyze lib/src/proto/frame_diff.pb.dart lib/src/proto/frame_diff.pbenum.dart
```

Expected: generated Dart files analyze without import or dependency errors.

- [ ] **Step 8: Commit**

```bash
git add native/core/Cargo.lock native/core/Cargo.toml native/core/build.rs native/core/proto/frame_diff.proto native/core/src/lib.rs native/core/src/proto/mod.rs native/core/src/proto/frame_diff.rs packages/ianvs_terminal/pubspec.yaml pubspec.lock packages/ianvs_terminal/lib/src/proto/frame_diff.pb.dart packages/ianvs_terminal/lib/src/proto/frame_diff.pbenum.dart tools/gen_frame_diff_proto.sh docs/superpowers/plans/2026-07-02-protobuf-frame-diff-transport.md
git commit -m "build: add frame diff protobuf schema"
```

---

### Task 2: Add Rust Protobuf Encoding And Debug Stats

**Files:**
- Create: `native/core/src/frame_diff_proto.rs`
- Modify: `native/core/src/session.rs`
- Modify: `native/core/tests/session_test.rs`

- [ ] **Step 1: Write failing Rust unit test for protobuf encode**

Add to `native/core/tests/session_test.rs`:

```rust
#[test]
fn session_frame_diff_protobuf_exposes_core_fields() {
    let session_id = session::create_session(&serde_json::to_string(&test_profile()).unwrap())
        .expect("session");
    wait_for_frame(session_id);

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
}
```

Run:

```bash
cd native/core
cargo test session_frame_diff_protobuf_exposes_core_fields --test session_test
```

Expected: fail because `take_frame_diff_protobuf` and `frame_diff_proto` do not exist.

- [ ] **Step 2: Add encoder module**

Create `native/core/src/frame_diff_proto.rs` with conversion helpers:

```rust
use crate::model::{
    TerminalCursor, TerminalDirtyRange, TerminalFrameDiff, TerminalFrameKind,
    TerminalFrameModes, TerminalGraphicPlacement, TerminalHyperlinkRange, TerminalRow,
    TerminalSelection, TerminalStyleRun,
};
use crate::proto::frame_diff as pb;
use prost::Message;

pub fn encode_frame_diff(frame: &TerminalFrameDiff) -> Result<Vec<u8>, prost::EncodeError> {
    let message = to_proto_frame(frame);
    let mut bytes = Vec::with_capacity(message.encoded_len());
    message.encode(&mut bytes)?;
    Ok(bytes)
}

#[cfg(test)]
pub fn decode_frame_diff_for_test(bytes: &[u8]) -> Result<pb::TerminalFrameDiff, prost::DecodeError> {
    pb::TerminalFrameDiff::decode(bytes)
}

fn to_proto_frame(frame: &TerminalFrameDiff) -> pb::TerminalFrameDiff {
    pb::TerminalFrameDiff {
        frame_schema_version: frame.frame_schema_version.clone(),
        frame_kind: match frame.frame_kind {
            TerminalFrameKind::Snapshot => pb::TerminalFrameKind::Snapshot as i32,
            TerminalFrameKind::Delta => pb::TerminalFrameKind::Delta as i32,
        },
        rows: frame.rows.iter().map(to_proto_row).collect(),
        cursor: Some(to_proto_cursor(&frame.cursor)),
        selection: frame.selection.as_ref().map(to_proto_selection),
        viewport_rows: frame.viewport_rows as u32,
        viewport_cols: frame.viewport_cols as u32,
        dirty_ranges: frame.dirty_ranges.iter().map(to_proto_dirty_range).collect(),
        scrollback_offset: frame.scrollback_offset as u32,
        scrollback_max_offset: frame.scrollback_max_offset as u32,
        viewport_start_row: frame.viewport_start_row as u32,
        viewport_row_shift: frame.viewport_row_shift,
        default_foreground: color_to_proto(frame.default_foreground.as_deref()),
        default_background: color_to_proto(frame.default_background.as_deref()),
        cursor_color: color_to_proto(frame.cursor_color.as_deref()),
        modes: Some(to_proto_modes(&frame.modes)),
        window_title: frame.window_title.clone().unwrap_or_default(),
        window_icon_name: frame.window_icon_name.clone().unwrap_or_default(),
        hyperlinks: frame.hyperlinks.iter().map(to_proto_hyperlink).collect(),
        // Native core currently emits graphics placements but not inline images.
        // Keep the schema field populated as empty so Dart can still support the
        // full TerminalFrameDiff surface when another producer sends it.
        inline_images: Vec::new(),
        graphics: frame.graphics.iter().map(to_proto_graphic).collect(),
    }
}

fn to_proto_row(row: &TerminalRow) -> pb::TerminalRow {
    pb::TerminalRow {
        index: row.index as u32,
        text: row.text.clone(),
        wrapped: row.wrapped,
        modified_at_micros: 0,
        style_runs: row.style_runs.iter().map(to_proto_style_run).collect(),
    }
}

fn to_proto_style_run(run: &TerminalStyleRun) -> pb::TerminalStyleRun {
    pb::TerminalStyleRun {
        start: run.start as u32,
        end: run.end as u32,
        foreground: color_to_proto(run.foreground.as_deref()),
        background: color_to_proto(run.background.as_deref()),
        bold: run.bold,
        dim: run.dim,
        italic: run.italic,
        underline: run.underline,
        blink: run.blink,
        inverse: run.inverse,
    }
}

fn to_proto_cursor(cursor: &TerminalCursor) -> pb::TerminalCursor {
    pb::TerminalCursor {
        row: cursor.row as u32,
        col: cursor.col as u32,
        visible: cursor.visible,
    }
}

fn to_proto_selection(selection: &TerminalSelection) -> pb::TerminalSelection {
    pb::TerminalSelection {
        present: true,
        start_row: selection.start_row as u32,
        start_col: selection.start_col as u32,
        end_row: selection.end_row as u32,
        end_col: selection.end_col as u32,
    }
}

fn to_proto_dirty_range(range: &TerminalDirtyRange) -> pb::TerminalDirtyRange {
    pb::TerminalDirtyRange {
        start: range.start as u32,
        end: range.end as u32,
    }
}

fn to_proto_modes(modes: &TerminalFrameModes) -> pb::TerminalFrameModes {
    pb::TerminalFrameModes {
        alternate_screen: modes.alternate_screen,
        alternate_scroll: modes.alternate_scroll,
        application_cursor: modes.application_cursor,
        application_keypad: modes.application_keypad,
        insert_mode: modes.insert_mode,
        origin_mode: modes.origin_mode,
        line_feed_new_line_mode: modes.line_feed_new_line_mode,
        hide_cursor: modes.hide_cursor,
        bracketed_paste: modes.bracketed_paste,
        focus_tracking: modes.focus_tracking,
        char_protected: modes.char_protected,
        mouse_mode: modes.mouse_mode.clone(),
        mouse_encoding: modes.mouse_encoding.clone(),
        kitty_keyboard_flags: modes.kitty_keyboard_flags as u32,
        synchronized_output: modes.synchronized_output,
    }
}

fn to_proto_hyperlink(link: &TerminalHyperlinkRange) -> pb::TerminalHyperlinkRange {
    pb::TerminalHyperlinkRange {
        row: link.row as u32,
        start_col: link.start_col as u32,
        end_col: link.end_col as u32,
        uri: link.uri.clone(),
    }
}

fn to_proto_graphic(graphic: &TerminalGraphicPlacement) -> pb::TerminalGraphicPlacement {
    pb::TerminalGraphicPlacement {
        placement_id: graphic.placement_id as u32,
        render_id: graphic.render_id as u32,
        asset_key: Some(pb::TerminalGraphicAssetKey {
            asset_id: graphic.asset_id as u32,
            asset_version: graphic.asset_version as u32,
        }),
        protocol: graphic.protocol.clone(),
        row: graphic.row as u32,
        col: graphic.col as u32,
        width_px: graphic.width_px as u32,
        height_px: graphic.height_px as u32,
        width_cells: graphic.width_cells as u32,
        height_cells: graphic.height_cells as u32,
        source_x_offset_px: graphic.source_x_offset_px as u32,
        visible_width_px: graphic.visible_width_px as u32,
        source_y_offset_px: graphic.source_y_offset_px as u32,
        visible_height_px: graphic.visible_height_px as u32,
        z_index: graphic.z_index,
        x_offset_px: graphic.x_offset_px as i32,
        y_offset_px: graphic.y_offset_px as i32,
        preserve_aspect_ratio: graphic.preserve_aspect_ratio,
    }
}

fn color_to_proto(value: Option<&str>) -> Option<pb::ColorRgb> {
    let value = value?;
    let hex = value.strip_prefix('#')?;
    if hex.len() != 6 {
        return None;
    }
    let rgb = u32::from_str_radix(hex, 16).ok()?;
    Some(pb::ColorRgb { present: true, rgb })
}
```

- [ ] **Step 3: Add session protobuf function and stats**

In `native/core/src/session.rs`, import the encoder near the existing imports:

```rust
use crate::frame_diff_proto;
```

Extend `FrameDebugStats`:

```rust
struct FrameDebugStats {
    rows_scanned: usize,
    rows_emitted: usize,
    frame_build_micros: u64,
    state_lock_wait_micros: u64,
    frame_extract_micros: u64,
    json_encode_micros: u64,
    protobuf_encode_micros: u64,
    full_repaint: bool,
    snapshot_fallback_reason: Option<String>,
    viewport_row_shift: i32,
    damage_generation: u64,
    active_graphics_count: usize,
    scrollback_graphics_count: usize,
    graphic_placements_count: usize,
}
```

When constructing `FrameDebugStats`, set:

```rust
json_encode_micros: 0,
protobuf_encode_micros: 0,
```

Add methods near `record_frame_json_encode_micros`:

```rust
fn record_frame_protobuf_encode_micros(&self, micros: u64) {
    if let Some(stats) = self.last_frame_debug_stats.lock().as_mut() {
        stats.protobuf_encode_micros = micros;
    }
}
```

Add a public session function near `take_frame_diff`:

```rust
pub fn take_frame_diff_protobuf(session_id: u64) -> Result<Option<Vec<u8>>, SessionError> {
    let session = STORE.get(session_id)?;
    let Some(diff) = session.take_frame_diff()? else {
        return Ok(None);
    };
    let encode_started_at = Instant::now();
    let bytes = frame_diff_proto::encode_frame_diff(&diff)
        .map_err(|error| SessionError::Serialize(error.to_string()))?;
    session.record_frame_protobuf_encode_micros(
        encode_started_at.elapsed().as_micros() as u64,
    );
    Ok(Some(bytes))
}
```

- [ ] **Step 4: Run the Rust test**

```bash
cd native/core
cargo test session_frame_diff_protobuf_exposes_core_fields --test session_test
```

Expected: pass.

- [ ] **Step 5: Add debug stats assertion**

Add to `native/core/tests/session_test.rs`:

```rust
#[test]
fn session_frame_debug_stats_include_protobuf_encode_micros() {
    let session_id = session::create_session(&serde_json::to_string(&test_profile()).unwrap())
        .expect("session");
    wait_for_frame(session_id);
    let _ = session::take_frame_diff_protobuf(session_id)
        .expect("protobuf result")
        .expect("protobuf frame");

    let debug_stats = session::take_frame_debug_stats_json(session_id)
        .expect("debug stats result")
        .expect("debug stats");
    let parsed: serde_json::Value = serde_json::from_str(&debug_stats).unwrap();
    assert!(parsed["protobuf_encode_micros"].as_u64().is_some());
}
```

Run:

```bash
cd native/core
cargo test session_frame_debug_stats_include_protobuf_encode_micros --test session_test
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add native/core/src/frame_diff_proto.rs native/core/src/session.rs native/core/tests/session_test.rs
git commit -m "feat: encode frame diffs as protobuf"
```

---

### Task 3: Add Native FFI Bytes Transport

**Files:**
- Modify: `native/core/src/ffi.rs`
- Modify: `native/core/tests/session_test.rs`
- Modify: `packages/ianvs_pty/lib/src/native_pty_backend.dart`

- [ ] **Step 1: Write failing Rust FFI test**

Add to `native/core/tests/session_test.rs`:

```rust
#[test]
fn ffi_take_frame_diff_protobuf_returns_bytes_and_len() {
    let session_id = session::create_session(&serde_json::to_string(&test_profile()).unwrap())
        .expect("session");
    wait_for_frame(session_id);

    let mut len = 0usize;
    let ptr = ianvs_core::ffi::ianvs_session_take_frame_diff_protobuf(session_id, &mut len);
    assert!(!ptr.is_null());
    assert!(len > 0);
    unsafe {
        let bytes = std::slice::from_raw_parts(ptr, len);
        assert!(!bytes.is_empty());
        ianvs_core::ffi::ianvs_bytes_free(ptr, len);
    }
}
```

Run:

```bash
cd native/core
cargo test ffi_take_frame_diff_protobuf_returns_bytes_and_len --test session_test
```

Expected: fail because FFI symbols do not exist.

- [ ] **Step 2: Add FFI bytes functions**

Add to `native/core/src/ffi.rs`:

```rust
#[unsafe(no_mangle)]
/// # Safety
///
/// `out_len` must point to writable memory for one `usize`.
pub unsafe extern "C" fn ianvs_session_take_frame_diff_protobuf(
    session_id: u64,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    match session::take_frame_diff_protobuf(session_id).ok().flatten() {
        Some(bytes) => {
            let mut boxed = bytes.into_boxed_slice();
            let len = boxed.len();
            let ptr = boxed.as_mut_ptr();
            unsafe {
                *out_len = len;
            }
            std::mem::forget(boxed);
            ptr
        }
        None => {
            unsafe {
                *out_len = 0;
            }
            std::ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
/// # Safety
///
/// `ptr` must be a pointer returned by `ianvs_session_take_frame_diff_protobuf`
/// with the same `len`.
pub unsafe extern "C" fn ianvs_bytes_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    let slice = std::ptr::slice_from_raw_parts_mut(ptr, len);
    unsafe {
        drop(Box::from_raw(slice));
    }
}
```

- [ ] **Step 3: Run Rust FFI test**

```bash
cd native/core
cargo test ffi_take_frame_diff_protobuf_returns_bytes_and_len --test session_test
```

Expected: pass.

- [ ] **Step 4: Write failing Dart PTY bindings test**

Add a test to `packages/ianvs_pty/test/native_pty_backend_test.dart` using a fake `PtyBindings` implementation that returns bytes:

```dart
test('native pty backend forwards protobuf frame bytes when supported', () {
  final bindings = _FakePtyBindings()
    ..frameDiffProtobufBytes = Uint8List.fromList(<int>[8, 1, 18, 4]);
  final backend = NativePtyBackend.fromBindings(bindings);

  final sessionId = backend.createSession('{}');
  final bytes = backend.takeFrameDiffProtobuf(sessionId);

  expect(bytes, <int>[8, 1, 18, 4]);
});
```

Run:

```bash
cd packages/ianvs_pty
dart test test/native_pty_backend_test.dart --plain-name "native pty backend forwards protobuf frame bytes when supported"
```

Expected: fail because protobuf bytes transport is not defined.

- [ ] **Step 5: Add Dart bytes transport interfaces**

In `packages/ianvs_pty/lib/src/native_pty_backend.dart`, add typedefs near `_StringReturningNative`:

```dart
typedef _BytesReturningNative =
    ffi.Pointer<ffi.Uint8> Function(ffi.Uint64, ffi.Pointer<ffi.Size>);
typedef _BytesReturningDart =
    ffi.Pointer<ffi.Uint8> Function(int, ffi.Pointer<ffi.Size>);
typedef _FreeBytesNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _FreeBytesDart = void Function(ffi.Pointer<ffi.Uint8>, int);
```

Add optional lookup:

```dart
_BytesReturningDart? _lookupOptionalBytesReturning(
  ffi.DynamicLibrary library,
  String symbolName,
) {
  try {
    return library.lookupFunction<_BytesReturningNative, _BytesReturningDart>(
      symbolName,
    );
  } on ArgumentError {
    return null;
  }
}
```

Extend `PtyBindings`:

```dart
Uint8List? sessionTakeFrameDiffProtobuf(int sessionId);
```

Extend `NativePtyBindings` fields and constructor:

```dart
      _takeFrameDiffProtobuf = _lookupOptionalBytesReturning(
        library,
        'ianvs_session_take_frame_diff_protobuf',
      ),
      _bytesFree = library.lookupFunction<_FreeBytesNative, _FreeBytesDart>(
        'ianvs_bytes_free',
      );

final _BytesReturningDart? _takeFrameDiffProtobuf;
final _FreeBytesDart _bytesFree;
```

Add implementation:

```dart
@override
Uint8List? sessionTakeFrameDiffProtobuf(int sessionId) {
  final binding = _takeFrameDiffProtobuf;
  if (binding == null) {
    return null;
  }
  final lenPointer = calloc<ffi.Size>();
  ffi.Pointer<ffi.Uint8> resultPointer = ffi.nullptr;
  try {
    resultPointer = binding(sessionId, lenPointer);
    final len = lenPointer.value;
    if (resultPointer == ffi.nullptr || len <= 0) {
      return null;
    }
    return Uint8List.fromList(resultPointer.asTypedList(len));
  } finally {
    if (resultPointer != ffi.nullptr) {
      _bytesFree(resultPointer, lenPointer.value);
    }
    calloc.free(lenPointer);
  }
}
```

Add backend capability:

```dart
abstract class PtySessionProtobufFrameBackend {
  Uint8List? takeFrameDiffProtobuf(String sessionId);
}
```

Implement it in `NativePtyBackend`:

```dart
@override
Uint8List? takeFrameDiffProtobuf(String sessionId) {
  return _bindings.sessionTakeFrameDiffProtobuf(_nativeSessionId(sessionId));
}
```

Update class declaration:

```dart
class NativePtyBackend
    implements
        PtySessionBackend,
        PtySessionJsonRequestBackend,
        PtySessionDiagnosticsBackend,
        PtySessionGraphicAssetBackend,
        PtySessionProtobufFrameBackend {
```

- [ ] **Step 6: Run PTY test**

```bash
cd packages/ianvs_pty
dart test test/native_pty_backend_test.dart --plain-name "native pty backend forwards protobuf frame bytes when supported"
```

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add native/core/src/ffi.rs native/core/tests/session_test.rs packages/ianvs_pty/lib/src/native_pty_backend.dart packages/ianvs_pty/test/native_pty_backend_test.dart
git commit -m "feat: expose protobuf frame bytes over ffi"
```

---

### Task 4: Add Dart Protobuf Decoder

**Files:**
- Create: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_protobuf_codec.dart`
- Create: `packages/ianvs_terminal/test/terminal_frame_protobuf_codec_test.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_transport.dart`

- [ ] **Step 1: Create transport model**

Create `packages/ianvs_terminal/lib/src/runtime/terminal_frame_transport.dart`:

```dart
enum TerminalFrameTransport { json, protobuf }

enum TerminalFrameTransportFallbackReason {
  unsupportedBackend('unsupported_backend'),
  decodeError('decode_error'),
  schemaMismatch('schema_mismatch'),
  missingRequiredField('missing_required_field'),
  emptyProtobufWithJsonFrame('empty_protobuf_with_json_frame');

  const TerminalFrameTransportFallbackReason(this.wireName);

  final String wireName;
}

final class TerminalFrameDecodeResult {
  const TerminalFrameDecodeResult({
    required this.frame,
    required this.rawFrameBytes,
    required this.transportKind,
    required this.decodeMicros,
    this.fallbackReason,
  });

  final TerminalFrameDiff frame;
  final int rawFrameBytes;
  final String transportKind;
  final int decodeMicros;
  final TerminalFrameTransportFallbackReason? fallbackReason;
}
```

Add import at the top of that file:

```dart
import '../terminal/terminal_models.dart';
```

- [ ] **Step 2: Write failing decoder tests**

Create `packages/ianvs_terminal/test/terminal_frame_protobuf_codec_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/proto/frame_diff.pb.dart' as pb;
import 'package:ianvs_terminal/src/runtime/terminal_frame_protobuf_codec.dart';
import 'package:ianvs_terminal/src/terminal/terminal_models.dart';

void main() {
  test('protobuf decoder maps a complete frame to TerminalFrameDiff', () {
    final message = pb.TerminalFrameDiff(
      frameSchemaVersion: TerminalFrameDiff.currentFrameSchemaVersion,
      frameKind: pb.TerminalFrameKind.TERMINAL_FRAME_KIND_SNAPSHOT,
      viewportRows: 2,
      viewportCols: 80,
      scrollbackOffset: 0,
      scrollbackMaxOffset: 4,
      cursor: pb.TerminalCursor(row: 1, col: 3, visible: true),
      rows: [
        pb.TerminalRow(
          index: 0,
          text: 'alpha',
          wrapped: false,
          styleRuns: [
            pb.TerminalStyleRun(
              start: 0,
              end: 5,
              foreground: pb.ColorRgb(present: true, rgb: 0xff0000),
              bold: true,
            ),
          ],
        ),
        pb.TerminalRow(index: 1, text: 'beta', wrapped: true),
      ],
      dirtyRanges: [pb.TerminalDirtyRange(start: 0, end: 2)],
      modes: pb.TerminalFrameModes(bracketedPaste: true),
      hyperlinks: [
        pb.TerminalHyperlinkRange(
          row: 1,
          startCol: 0,
          endCol: 4,
          uri: 'https://example.test',
        ),
      ],
      graphics: [
        pb.TerminalGraphicPlacement(
          placementId: 9,
          renderId: 9,
          assetKey: pb.TerminalGraphicAssetKey(assetId: 7, assetVersion: 3),
          protocol: 'kitty',
          row: 1,
          col: 2,
          widthPx: 8,
          heightPx: 4,
          widthCells: 4,
          heightCells: 2,
          visibleWidthPx: 8,
          visibleHeightPx: 4,
          preserveAspectRatio: true,
        ),
      ],
    );

    final frame = decodeTerminalFrameDiffProtobuf(message.writeToBuffer());

    expect(frame.frameKind, TerminalFrameKind.snapshot);
    expect(frame.viewportRows, 2);
    expect(frame.cursor, const TerminalCursor(row: 1, col: 3, visible: true));
    expect(frame.rows.map((row) => row.text), <String>['alpha', 'beta']);
    expect(frame.rows.first.styleRuns.single.bold, isTrue);
    expect(frame.rows.first.styleRuns.single.foreground?.value, 0xffff0000);
    expect(frame.hyperlinks.single.uri, 'https://example.test');
    expect(frame.graphics.single.assetKey.id, 7);
  });

  test('protobuf decoder rejects schema mismatches', () {
    final message = pb.TerminalFrameDiff(
      frameSchemaVersion: 'unknown-schema',
      frameKind: pb.TerminalFrameKind.TERMINAL_FRAME_KIND_SNAPSHOT,
      viewportRows: 1,
      viewportCols: 80,
      cursor: pb.TerminalCursor(row: 0, col: 0, visible: true),
    );

    expect(
      () => decodeTerminalFrameDiffProtobuf(message.writeToBuffer()),
      throwsA(isA<TerminalFrameProtobufSchemaException>()),
    );
  });
}
```

Run:

```bash
cd packages/ianvs_terminal
flutter test test/terminal_frame_protobuf_codec_test.dart
```

Expected: fail because codec does not exist.

- [ ] **Step 3: Implement decoder**

Create `packages/ianvs_terminal/lib/src/runtime/terminal_frame_protobuf_codec.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui';

import '../proto/frame_diff.pb.dart' as pb;
import '../terminal/terminal_models.dart';

class TerminalFrameProtobufDecodeException implements Exception {
  const TerminalFrameProtobufDecodeException(this.message);

  final String message;

  @override
  String toString() => 'TerminalFrameProtobufDecodeException: $message';
}

class TerminalFrameProtobufSchemaException
    extends TerminalFrameProtobufDecodeException {
  const TerminalFrameProtobufSchemaException(super.message);
}

TerminalFrameDiff decodeTerminalFrameDiffProtobuf(Uint8List bytes) {
  final message = pb.TerminalFrameDiff.fromBuffer(bytes);
  final schema = message.frameSchemaVersion.isEmpty
      ? TerminalFrameDiff.currentFrameSchemaVersion
      : message.frameSchemaVersion;
  if (schema != TerminalFrameDiff.currentFrameSchemaVersion) {
    throw TerminalFrameProtobufSchemaException('Unsupported schema: $schema');
  }
  return TerminalFrameDiff(
    frameSchemaVersion: schema,
    frameKind: _frameKind(message.frameKind),
    rows: message.rows.map(_row).toList(growable: false),
    cursor: _cursor(message.cursor),
    selection: message.hasSelection() && message.selection.present
        ? _selection(message.selection)
        : null,
    viewportRows: message.viewportRows,
    viewportCols: message.viewportCols,
    dirtyRanges: message.dirtyRanges.map(_dirtyRange).toList(growable: false),
    scrollbackOffset: message.scrollbackOffset.toInt(),
    scrollbackMaxOffset: message.scrollbackMaxOffset.toInt(),
    viewportStartRow: message.viewportStartRow.toInt(),
    viewportRowShift: message.viewportRowShift,
    defaultForeground: _color(message.defaultForeground),
    defaultBackground: _color(message.defaultBackground),
    cursorColor: _color(message.cursorColor),
    modes: message.hasModes() ? _modes(message.modes) : TerminalFrameModes.empty,
    windowTitle: message.windowTitle.isEmpty ? null : message.windowTitle,
    windowIconName: message.windowIconName.isEmpty
        ? null
        : message.windowIconName,
    hyperlinks: message.hyperlinks.map(_hyperlink).toList(growable: false),
    inlineImages: message.inlineImages.map(_inlineImage).toList(growable: false),
    graphics: message.graphics.map(_graphic).toList(growable: false),
  );
}

TerminalFrameKind _frameKind(pb.TerminalFrameKind value) {
  return switch (value) {
    pb.TerminalFrameKind.TERMINAL_FRAME_KIND_DELTA => TerminalFrameKind.delta,
    _ => TerminalFrameKind.snapshot,
  };
}

TerminalRow _row(pb.TerminalRow row) {
  return TerminalRow(
    index: row.index,
    text: row.text,
    wrapped: row.wrapped,
    styleRuns: row.styleRuns.map(_styleRun).toList(growable: false),
  );
}

TerminalStyleRun _styleRun(pb.TerminalStyleRun run) {
  return TerminalStyleRun(
    start: run.start,
    end: run.end,
    foreground: _color(run.foreground),
    background: _color(run.background),
    bold: run.bold,
    dim: run.dim,
    italic: run.italic,
    underline: run.underline,
    blink: run.blink,
    inverse: run.inverse,
  );
}

TerminalCursor _cursor(pb.TerminalCursor cursor) {
  return TerminalCursor(
    row: cursor.row,
    col: cursor.col,
    visible: cursor.visible,
  );
}

TerminalSelection _selection(pb.TerminalSelection selection) {
  return TerminalSelection(
    startRow: selection.startRow.toInt(),
    startCol: selection.startCol,
    endRow: selection.endRow.toInt(),
    endCol: selection.endCol,
  );
}

TerminalDirtyRange _dirtyRange(pb.TerminalDirtyRange range) {
  return TerminalDirtyRange(start: range.start, end: range.end);
}

TerminalFrameModes _modes(pb.TerminalFrameModes modes) {
  return TerminalFrameModes(
    alternateScreen: modes.alternateScreen,
    alternateScroll: modes.alternateScroll,
    applicationCursor: modes.applicationCursor,
    applicationKeypad: modes.applicationKeypad,
    insertMode: modes.insertMode,
    originMode: modes.originMode,
    lineFeedNewLineMode: modes.lineFeedNewLineMode,
    hideCursor: modes.hideCursor,
    bracketedPaste: modes.bracketedPaste,
    focusTracking: modes.focusTracking,
    charProtected: modes.charProtected,
    mouseMode: _mouseMode(modes.mouseMode),
    mouseEncoding: _mouseEncoding(modes.mouseEncoding),
    kittyKeyboardFlags: modes.kittyKeyboardFlags,
    synchronizedOutput: modes.synchronizedOutput,
  );
}

TerminalHyperlinkRange _hyperlink(pb.TerminalHyperlinkRange link) {
  return TerminalHyperlinkRange(
    row: link.row,
    startCol: link.startCol,
    endCol: link.endCol,
    uri: link.uri,
  );
}

TerminalInlineImage _inlineImage(pb.TerminalInlineImage image) {
  return TerminalInlineImage(
    data: image.data,
    mimeType: image.mimeType.isEmpty ? null : image.mimeType,
    row: image.row,
    col: image.col,
    widthCells: image.widthCells,
    heightCells: image.heightCells,
    altText: image.altText.isEmpty ? null : image.altText,
  );
}

TerminalGraphicPlacement _graphic(pb.TerminalGraphicPlacement graphic) {
  return TerminalGraphicPlacement(
    placementId: graphic.placementId.toInt(),
    renderId: graphic.renderId.toInt(),
    assetKey: TerminalGraphicAssetKey(
      id: graphic.assetKey.assetId.toInt(),
      version: graphic.assetKey.assetVersion.toInt(),
    ),
    protocol: graphic.protocol,
    row: graphic.row,
    col: graphic.col,
    widthPx: graphic.widthPx,
    heightPx: graphic.heightPx,
    widthCells: graphic.widthCells,
    heightCells: graphic.heightCells,
    sourceXOffsetPx: graphic.sourceXOffsetPx,
    visibleWidthPx: graphic.visibleWidthPx,
    sourceYOffsetPx: graphic.sourceYOffsetPx,
    visibleHeightPx: graphic.visibleHeightPx,
    zIndex: graphic.zIndex,
    xOffsetPx: graphic.xOffsetPx,
    yOffsetPx: graphic.yOffsetPx,
    preserveAspectRatio: graphic.preserveAspectRatio,
  );
}

Color? _color(pb.ColorRgb color) {
  if (!color.present) {
    return null;
  }
  return Color(0xff000000 | color.rgb);
}

TerminalMouseMode _mouseMode(String value) {
  return switch (value) {
    'x10' => TerminalMouseMode.x10,
    'normal' => TerminalMouseMode.normal,
    'button' => TerminalMouseMode.button,
    'any' => TerminalMouseMode.any,
    _ => TerminalMouseMode.off,
  };
}

TerminalMouseEncoding _mouseEncoding(String value) {
  return switch (value) {
    'utf8' => TerminalMouseEncoding.utf8,
    'sgr' => TerminalMouseEncoding.sgr,
    'urxvt' => TerminalMouseEncoding.urxvt,
    _ => TerminalMouseEncoding.defaultEncoding,
  };
}
```

- [ ] **Step 4: Run decoder tests**

```bash
cd packages/ianvs_terminal
flutter test test/terminal_frame_protobuf_codec_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add packages/ianvs_terminal/lib/src/runtime/terminal_frame_transport.dart packages/ianvs_terminal/lib/src/runtime/terminal_frame_protobuf_codec.dart packages/ianvs_terminal/test/terminal_frame_protobuf_codec_test.dart
git commit -m "feat: decode protobuf terminal frame diffs"
```

---

### Task 5: Wire Protobuf Transport Into Runtime Controller

**Files:**
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- Modify: `packages/ianvs_terminal/lib/ianvs_terminal.dart`
- Modify: `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`

- [ ] **Step 1: Write failing runtime test for protobuf path**

Add to `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`:

```dart
test('terminal runtime can decode frames from protobuf transport', () async {
  final runtimeBackend = _FakePtyBackend();
  runtimeBackend.frameDiffProtobufBytesForJson = true;
  final benchmarkEvents = <Map<String, Object?>>[];
  final runtime = TerminalRuntimeController(
    backend: runtimeBackend,
    copyToClipboard: (_) async {},
    readClipboard: () async => '',
    enableSessionPolling: false,
    frameTransport: TerminalFrameTransport.protobuf,
    benchmarkEventSink: benchmarkEvents.add,
  );
  addTearDown(runtime.dispose);

  final sessionId = runtime.createSession(
    const TerminalSessionConfig(
      launch: TerminalLaunchConfig(program: '/bin/sh'),
    ),
  );
  await Future<void>.delayed(Duration.zero);

  expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');
  final event = benchmarkEvents.singleWhere(
    (event) => event['schema_version'] == 'ianvs-bench-dart-runtime-v1',
  );
  expect(event['transport_kind'], 'protobuf');
  expect(event['transport_fallback_reason'], isNull);
  expect(event['protobuf_decode_micros'], isA<int>());
});
```

Run:

```bash
cd packages/ianvs_terminal
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime can decode frames from protobuf transport"
```

Expected: fail because runtime transport switch is not implemented.

- [ ] **Step 2: Extend decoded metrics**

In `terminal_runtime_controller.dart`, replace `_DecodedFrameBenchmarkMetrics` with:

```dart
final class _DecodedFrameBenchmarkMetrics {
  const _DecodedFrameBenchmarkMetrics({
    required this.rawFrameBytes,
    required this.transportKind,
    required this.wireDecodeMicros,
    this.fallbackReason,
  });

  final int rawFrameBytes;
  final String transportKind;
  final int wireDecodeMicros;
  final TerminalFrameTransportFallbackReason? fallbackReason;
}
```

Import:

```dart
import 'terminal_frame_protobuf_codec.dart';
import 'terminal_frame_transport.dart';
```

- [ ] **Step 3: Add constructor parameter**

Update constructor:

```dart
    this.enableWarmUpRefresh = false,
    this.frameTransport = TerminalFrameTransport.json,
    this.benchmarkEventSink,
```

Add field:

```dart
final TerminalFrameTransport frameTransport;
```

- [ ] **Step 4: Add decode helper**

Add helper:

```dart
TerminalFrameDiff? _takeAndDecodeFrame(String sessionId) {
  if (frameTransport == TerminalFrameTransport.protobuf) {
    final protobufBackend = _backend is PtySessionProtobufFrameBackend
        ? _backend as PtySessionProtobufFrameBackend
        : null;
    if (protobufBackend == null) {
      return _takeAndDecodeJsonFrame(
        sessionId,
        fallbackReason: TerminalFrameTransportFallbackReason.unsupportedBackend,
      );
    }
    final bytes = protobufBackend.takeFrameDiffProtobuf(sessionId);
    if (bytes != null && bytes.isNotEmpty) {
      return _decodeProtobufFrame(bytes);
    }
    return null;
  }
  return _takeAndDecodeJsonFrame(sessionId);
}

TerminalFrameDiff? _takeAndDecodeJsonFrame(
  String sessionId, {
  TerminalFrameTransportFallbackReason? fallbackReason,
}) {
  final rawFrame = _backend.takeFrameDiffJson(sessionId);
  if (rawFrame == null || rawFrame.isEmpty) {
    return null;
  }
  return _decodeJsonFrame(rawFrame, fallbackReason: fallbackReason);
}
```

Rename `_decodeFrame` to `_decodeJsonFrame` and update metrics assignment:

```dart
_decodedFrameBenchmarkMetrics[frame] = _DecodedFrameBenchmarkMetrics(
  rawFrameBytes: utf8.encode(rawFrame).length,
  transportKind: fallbackReason == null ? 'json' : 'json',
  wireDecodeMicros: decodeWatch?.elapsedMicroseconds ?? 0,
  fallbackReason: fallbackReason,
);
```

Add protobuf decoder:

```dart
TerminalFrameDiff? _decodeProtobufFrame(Uint8List bytes) {
  final decodeWatch = benchmarkEventSink == null
      ? null
      : (Stopwatch()..start());
  try {
    final frame = decodeTerminalFrameDiffProtobuf(bytes);
    decodeWatch?.stop();
    if (benchmarkEventSink != null) {
      _decodedFrameBenchmarkMetrics[frame] = _DecodedFrameBenchmarkMetrics(
        rawFrameBytes: bytes.length,
        transportKind: 'protobuf',
        wireDecodeMicros: decodeWatch?.elapsedMicroseconds ?? 0,
      );
    }
    return frame;
  } on TerminalFrameProtobufSchemaException {
    decodeWatch?.stop();
    _emitTransportDecodeFailure(
      TerminalFrameTransportFallbackReason.schemaMismatch,
      bytes.length,
      decodeWatch?.elapsedMicroseconds ?? 0,
    );
    return null;
  } on Object {
    decodeWatch?.stop();
    _emitTransportDecodeFailure(
      TerminalFrameTransportFallbackReason.decodeError,
      bytes.length,
      decodeWatch?.elapsedMicroseconds ?? 0,
    );
    return null;
  }
}
```

Add failure event:

```dart
void _emitTransportDecodeFailure(
  TerminalFrameTransportFallbackReason reason,
  int rawFrameBytes,
  int wireDecodeMicros,
) {
  final sink = benchmarkEventSink;
  if (sink == null) {
    return;
  }
  sink(<String, Object?>{
    'schema_version': 'ianvs-bench-dart-runtime-v1',
    'timestamp_micros': DateTime.now().microsecondsSinceEpoch,
    'session_id': '',
    'frame_id': _benchmarkFrameId,
    'transport_kind': 'protobuf',
    'transport_fallback_reason': reason.wireName,
    'raw_frame_bytes': rawFrameBytes,
    'wire_decode_micros': wireDecodeMicros,
    'protobuf_decode_micros': wireDecodeMicros,
    'apply_frame_micros': 0,
    'pending_frames_before': 0,
    'pending_frames_after': 0,
    'queued_refresh_count': 0,
    'events_processed': 0,
    'viewport_hash_after_apply': '',
  });
}
```

Replace both direct frame pulls in `_refreshSessionOnce` and `_refreshSessionDraining`:

```dart
final frame = _takeAndDecodeFrame(sessionId);
if (frame != null) {
  receivedFrame = true;
  _queuePendingFrame(pendingFrames, frame);
}
```

and in draining:

```dart
final frame = _takeAndDecodeFrame(sessionId);
if (frame != null) {
  _queuePendingFrame(pendingFrames, frame);
}
```

- [ ] **Step 5: Emit transport benchmark fields**

Update `_emitRuntimeBenchmarkEvent` map:

```dart
'transport_kind': decodedMetrics?.transportKind ?? frameTransport.name,
'transport_fallback_reason': decodedMetrics?.fallbackReason?.wireName,
'raw_frame_bytes': decodedMetrics?.rawFrameBytes ?? 0,
'wire_decode_micros': decodedMetrics?.wireDecodeMicros ?? 0,
'json_decode_micros': decodedMetrics?.transportKind == 'json'
    ? decodedMetrics?.wireDecodeMicros ?? 0
    : 0,
'protobuf_decode_micros': decodedMetrics?.transportKind == 'protobuf'
    ? decodedMetrics?.wireDecodeMicros ?? 0
    : 0,
'polling_interval_ms': _pollingFrameInterval.inMilliseconds,
'refresh_strategy': enableSessionPolling ? 'polling' : 'draining',
```

- [ ] **Step 6: Export transport enum**

Modify `packages/ianvs_terminal/lib/ianvs_terminal.dart`:

```dart
export 'src/runtime/terminal_frame_transport.dart';
```

- [ ] **Step 7: Update fake backend for protobuf tests**

In `_FakePtyBackend`, implement `PtySessionProtobufFrameBackend` and add:

```dart
bool frameDiffProtobufBytesForJson = false;
Uint8List? rawProtobufFrame;

@override
Uint8List? takeFrameDiffProtobuf(String sessionId) {
  if (rawProtobufFrame != null) {
    return rawProtobufFrame;
  }
  if (!frameDiffProtobufBytesForJson) {
    return null;
  }
  final raw = takeFrameDiffJson(sessionId);
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return _protobufBytesFromJsonForTest(raw);
}
```

Add `_protobufBytesFromJsonForTest` in the test file by constructing `pb.TerminalFrameDiff` for the minimal fake frame. This helper must set schema, kind, rows, cursor, viewport rows/cols, scrollback offsets, and dirty ranges.

- [ ] **Step 8: Run runtime tests**

```bash
cd packages/ianvs_terminal
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime can decode frames from protobuf transport"
```

Expected: pass.

- [ ] **Step 9: Commit**

```bash
git add packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart packages/ianvs_terminal/lib/src/runtime/terminal_frame_transport.dart packages/ianvs_terminal/lib/ianvs_terminal.dart packages/ianvs_terminal/test/terminal_runtime_controller_test.dart
git commit -m "feat: add runtime protobuf frame transport"
```

---

### Task 6: Add App And Test Harness Transport Configuration

**Files:**
- Modify: `example/test/support/test_runtime.dart`
- Modify: `example/test/support/fake_pty_backend.dart`
- Modify: `example/lib/features/sessions/session_controller.dart`
- Modify: `example/lib/app_bootstrap.dart`

- [ ] **Step 1: Update test runtime helper**

Modify `example/test/support/test_runtime.dart` signature:

```dart
TerminalRuntimeController testRuntime(
  PtySessionBackend backend, {
  Future<void> Function(String text)? copyToClipboard,
  Future<String> Function()? readClipboard,
  bool enableSessionPolling = false,
  bool enableWarmUpRefresh = false,
  TerminalFrameTransport frameTransport = TerminalFrameTransport.json,
  TerminalWindowResizeCallback? resizeWindowBy,
  bool seedDefaultSession = true,
}) {
```

Pass it to the runtime:

```dart
frameTransport: frameTransport,
```

- [ ] **Step 2: Add app provider**

In `example/lib/features/sessions/session_controller.dart`, add:

```dart
final terminalFrameTransportProvider = Provider<TerminalFrameTransport>((ref) {
  return TerminalFrameTransport.json;
});
```

Pass it into `TerminalRuntimeController`:

```dart
frameTransport: ref.read(terminalFrameTransportProvider),
```

- [ ] **Step 3: Add bootstrap parameter**

In `example/lib/app_bootstrap.dart`, add parameter to `buildIanvsTerminalRoot` and `runIanvsTerminalApp`:

```dart
TerminalFrameTransport frameTransport = TerminalFrameTransport.json,
```

Add provider override:

```dart
terminalFrameTransportProvider.overrideWithValue(frameTransport),
```

Import the enum if needed:

```dart
import 'package:ianvs_terminal/ianvs_terminal.dart';
```

- [ ] **Step 4: Run example unit tests that build providers**

```bash
cd example
flutter test test/sessions/session_controller_phase3_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add example/test/support/test_runtime.dart example/test/support/fake_pty_backend.dart example/lib/features/sessions/session_controller.dart example/lib/app_bootstrap.dart
git commit -m "feat: configure frame transport in app runtime"
```

---

### Task 7: Extend Benchmark Metrics And Summary

**Files:**
- Modify: `tools/bench/src/replay_terminal.dart`
- Modify: `tools/bench/src/summary_analyzer.dart`
- Modify: `tools/bench/test/bench_tools_test.dart`

- [ ] **Step 1: Write failing summary analyzer test**

Add to `tools/bench/test/bench_tools_test.dart`:

```dart
test('summary analyzer reports transport metrics', () {
  final sandbox = Directory.systemTemp.createTempSync('ianvs-bench-summary-');
  addTearDown(() => sandbox.deleteSync(recursive: true));
  final runDir = Directory('${sandbox.path}/run')..createSync(recursive: true);
  File('${runDir.path}/metadata.json').writeAsStringSync(jsonEncode({
    'schema_version': 'ianvs-bench-metadata-v1',
    'workload': 'burst_stdout.seq_1000',
    'repeat_index': 1,
    'mode': {'frame_policy': 'delta_coalesced'},
  }));
  File('${runDir.path}/correctness.json').writeAsStringSync(jsonEncode({
    'hash_match': true,
  }));
  File('${runDir.path}/rust_frame.ndjson').writeAsStringSync(
    '${jsonEncode({
          'frame_id': 1,
          'semantic_generation': 32,
          'frame_kind': 'delta',
          'rows_emitted': 1,
          'viewport_rows': 24,
          'frame_build_micros': 100,
          'wire_encode_micros': 12,
          'transport_kind': 'protobuf',
        })}\n',
  );
  File('${runDir.path}/dart_runtime.ndjson').writeAsStringSync(
    '${jsonEncode({
          'schema_version': 'ianvs-bench-dart-runtime-v1',
          'frame_id': 1,
          'transport_kind': 'protobuf',
          'raw_frame_bytes': 44,
          'wire_decode_micros': 7,
          'apply_frame_micros': 11,
          'queued_refresh_count': 0,
          'polling_interval_ms': 33,
        })}\n',
  );

  final summary = const SummaryAnalyzer().summarizeRunDirectory(runDir);

  expect(summary['transport_kind'], 'protobuf');
  expect(summary['p95_wire_encode_micros'], 12);
  expect(summary['p95_wire_decode_micros'], 7);
  expect(summary['avg_raw_frame_bytes'], 44.0);
  expect(summary['polling_interval_ms'], 33);
});
```

Run:

```bash
dart test tools/bench/test/bench_tools_test.dart --plain-name "summary analyzer reports transport metrics"
```

Expected: fail because summary fields do not exist.

- [ ] **Step 2: Update replay synthetic events**

In `tools/bench/src/replay_terminal.dart`, add fields to `rustEvents`:

```dart
'transport_kind': framePolicy == BenchFramePolicy.snapshotOnly ? 'json' : 'json',
'wire_encode_micros': jsonEncodeMicros,
'json_encode_micros': jsonEncodeMicros,
'protobuf_encode_micros': 0,
```

Add fields to `dartEvents`:

```dart
'transport_kind': 'json',
'transport_fallback_reason': null,
'wire_decode_micros': 18 + rowsEmitted,
'json_decode_micros': 18 + rowsEmitted,
'protobuf_decode_micros': 0,
'polling_interval_ms': 33,
'refresh_strategy': 'synthetic_coalesced',
```

- [ ] **Step 3: Update summary analyzer**

In `tools/bench/src/summary_analyzer.dart`, add values to `summary`:

```dart
'transport_kind': _dominantString(dartEvents, 'transport_kind'),
'transport_fallback_count': dartEvents
    .where((event) => _stringValue(event['transport_fallback_reason']) != null)
    .length,
'avg_raw_frame_bytes': _averageOrNa(_intValues(dartEvents, 'raw_frame_bytes')),
'p95_wire_encode_micros': _percentile(
  _intValues(rustFrames, 'wire_encode_micros'),
  95,
),
'p95_wire_decode_micros': _percentile(
  _intValues(dartEvents, 'wire_decode_micros'),
  95,
),
'polling_interval_ms': _firstInt(dartEvents, 'polling_interval_ms'),
```

Add helpers:

```dart
Object _averageOrNa(List<int> values) {
  return values.isEmpty ? 'N/A' : _average(values);
}

Object _firstInt(List<Map<String, Object?>> events, String key) {
  for (final event in events) {
    final value = _intValue(event[key]);
    if (value != null) {
      return value;
    }
  }
  return 'N/A';
}

String _dominantString(List<Map<String, Object?>> events, String key) {
  final counts = <String, int>{};
  for (final event in events) {
    final value = _stringValue(event[key]);
    if (value != null && value.isNotEmpty) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) {
    return 'unknown';
  }
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}
```

Extend `_summaryCsvHeader` and `_summaryCsvRow` with:

```dart
'transport_kind',
'transport_fallback_count',
'avg_raw_frame_bytes',
'p95_wire_encode_micros',
'p95_wire_decode_micros',
'polling_interval_ms',
```

- [ ] **Step 4: Run benchmark tests**

```bash
dart test tools/bench/test/bench_tools_test.dart --plain-name "summary analyzer reports transport metrics"
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add tools/bench/src/replay_terminal.dart tools/bench/src/summary_analyzer.dart tools/bench/test/bench_tools_test.dart
git commit -m "bench: summarize frame transport metrics"
```

---

### Task 8: Add Runtime Transport Profile Harness

**Files:**
- Modify: `example/integration_test/terminal_render_profile_test.dart`
- Modify: `example/lib/benchmarks/terminal_render_profile_report.dart`
- Modify: `tools/bench/src/flutter_profile_report_audit.dart`
- Modify: `tools/bench/test/bench_tools_test.dart`

- [ ] **Step 1: Add profile transport dart-define parsing**

In `example/integration_test/terminal_render_profile_test.dart`, add:

```dart
const String _frameTransportName = String.fromEnvironment(
  'IANVS_FRAME_TRANSPORT',
  defaultValue: 'json',
);

terminal.TerminalFrameTransport _profileFrameTransport() {
  return switch (_frameTransportName) {
    'protobuf' => terminal.TerminalFrameTransport.protobuf,
    _ => terminal.TerminalFrameTransport.json,
  };
}
```

- [ ] **Step 2: Capture runtime events**

In `_runProfileCase`, add:

```dart
final dartRuntimeEvents = <Map<String, Object?>>[];
```

Create runtime with benchmark sink:

```dart
final runtime = terminal.TerminalRuntimeController(
  backend: backend,
  copyToClipboard: (_) async {},
  readClipboard: () async => '',
  enableSessionPolling: false,
  frameTransport: _profileFrameTransport(),
  benchmarkEventSink: dartRuntimeEvents.add,
);
```

Keep the render-only path for Flutter paint timing, but add a runtime transport pass before render playback:

```dart
final runtimeSessionId = runtime.createSession(
  const terminal.TerminalSessionConfig(
    launch: terminal.TerminalLaunchConfig(program: '/bin/sh'),
  ),
);
for (final frame in frames) {
  backend.enqueueFrame(runtimeSessionId, _frameToJson(frame));
  runtime.refreshSession(runtimeSessionId);
  await tester.pump();
}
```

Add `_frameToJson` helper in the test file using the same keys accepted by `TerminalFrameDiff.fromJson`.

- [ ] **Step 3: Write runtime ndjson in report**

Modify `writeTerminalRenderProfileReport` signature:

```dart
required List<Map<String, Object?>> dartRuntimeEvents,
```

Write file:

```dart
_writeNdjson(
  File('${outputDir.path}/dart_runtime.ndjson'),
  dartRuntimeEvents,
);
```

Add metadata mode field:

```dart
'transport': _frameTransportName,
```

In `_summarize`, add:

```dart
'transport_kind': _dominantString(dartRuntimeEvents, 'transport_kind'),
'transport_fallback_count': dartRuntimeEvents
    .where((event) => event['transport_fallback_reason'] != null)
    .length,
'avg_raw_frame_bytes': _averageOrNa(_intValues(dartRuntimeEvents, 'raw_frame_bytes')),
'p95_wire_decode_micros': _percentile(
  _intValues(dartRuntimeEvents, 'wire_decode_micros'),
  95,
),
'p95_apply_frame_micros': _percentile(
  _intValues(dartRuntimeEvents, 'apply_frame_micros'),
  95,
),
```

Add helper functions matching Task 7.

- [ ] **Step 4: Audit requires runtime stats**

In `tools/bench/src/flutter_profile_report_audit.dart`, change run directory checks to require:

```dart
_requireNonEmptyFile(runDir, 'dart_runtime.ndjson', failures);
```

Add validation that protobuf runs have zero fallback count by reading summary CSV or ndjson.

- [ ] **Step 5: Run targeted tests**

```bash
cd example
flutter test test/benchmarks/terminal_render_profile_report_test.dart
```

Expected: pass after updating expected CSV headers.

Run:

```bash
dart test tools/bench/test/bench_tools_test.dart --plain-name "FlutterProfileReportAudit"
```

Expected: pass after fixtures include `dart_runtime.ndjson`.

- [ ] **Step 6: Commit**

```bash
git add example/integration_test/terminal_render_profile_test.dart example/lib/benchmarks/terminal_render_profile_report.dart example/test/benchmarks/terminal_render_profile_report_test.dart tools/bench/src/flutter_profile_report_audit.dart tools/bench/test/bench_tools_test.dart
git commit -m "bench: profile runtime frame transport"
```

---

### Task 9: Add Documentation And Release Gate Commands

**Files:**
- Modify: `docs/FRAME_DIFF.md`
- Modify: `tools/bench/README.md`
- Modify: `docs/TESTING.md`

- [ ] **Step 1: Update frame diff docs**

In `docs/FRAME_DIFF.md`, add a section:

```markdown
## JSON 与 Protobuf 传输

JSON 仍是默认 frame diff wire format。它用于 debug、兼容和回退。

Protobuf 是实验传输格式，可通过 `TerminalRuntimeController(frameTransport: TerminalFrameTransport.protobuf)` 打开。Rust 仍生成同一份 frame diff 语义对象，protobuf 只替换 Rust 到 Dart 的 wire encoding。Dart 解码后仍映射为 `TerminalFrameDiff`，因此 viewport 合并和 Flutter row cache 渲染不变。

protobuf release gate 必须和 JSON 路径跑同一 workload，并比较 final viewport hash、schema、fallback 和 transport metrics。
```

- [ ] **Step 2: Update bench README**

In `tools/bench/README.md`, add command:

```bash
cd example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/terminal_render_profile_test.dart \
  -d macos \
  --profile \
  --dart-define=IANVS_BENCH_PROFILE_OUTPUT=/absolute/path/to/build/bench-results-profile/json \
  --dart-define=IANVS_FRAME_TRANSPORT=json

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/terminal_render_profile_test.dart \
  -d macos \
  --profile \
  --dart-define=IANVS_BENCH_PROFILE_OUTPUT=/absolute/path/to/build/bench-results-profile/protobuf \
  --dart-define=IANVS_FRAME_TRANSPORT=protobuf
```

Document required files:

```text
dart_runtime.ndjson
flutter_render.ndjson
flutter_frame_timing.ndjson
metadata.json
correctness.json
summary.csv
```

- [ ] **Step 3: Update testing docs**

In `docs/TESTING.md`, add this section:

````markdown
## Protobuf Frame Diff Gate

After changing frame diff transport, run:

```bash
cd native/core
cargo test session_frame_diff_protobuf --test session_test

cd ../../packages/ianvs_pty
dart test

cd ../ianvs_terminal
flutter test test/terminal_frame_protobuf_codec_test.dart
flutter test test/terminal_runtime_controller_test.dart --plain-name protobuf
```

For release-gate profiling, run JSON and protobuf profile passes with `IANVS_FRAME_TRANSPORT=json` and `IANVS_FRAME_TRANSPORT=protobuf`, then run the existing Flutter profile audit over both output roots.
````

- [ ] **Step 4: Commit**

```bash
git add docs/FRAME_DIFF.md tools/bench/README.md docs/TESTING.md
git commit -m "docs: document protobuf frame diff transport"
```

---

### Task 10: Full Verification

**Files:**
- No source edits expected unless a verification failure points to a specific task file.

- [ ] **Step 1: Rust verification**

Run:

```bash
cd native/core
cargo fmt --check
cargo test session_frame_diff_protobuf --test session_test
cargo test ffi_take_frame_diff_protobuf_returns_bytes_and_len --test session_test
cargo test --test session_test -- --test-threads=1
```

Expected: all pass.

- [ ] **Step 2: PTY package verification**

Run:

```bash
cd packages/ianvs_pty
dart test
```

Expected: all pass.

- [ ] **Step 3: Terminal package verification**

Run:

```bash
cd packages/ianvs_terminal
flutter test test/terminal_frame_protobuf_codec_test.dart
flutter test test/terminal_runtime_controller_test.dart --plain-name protobuf
```

Expected: all pass.

- [ ] **Step 4: Benchmark tool verification**

Run:

```bash
dart test tools/bench/test/bench_tools_test.dart
```

Expected: all pass.

- [ ] **Step 5: Example report verification**

Run:

```bash
cd example
flutter test test/benchmarks/terminal_render_profile_report_test.dart
```

Expected: all pass.

- [ ] **Step 6: Regeneration stability check**

Run:

```bash
./tools/gen_frame_diff_proto.sh
git diff --exit-code native/core/src/proto/frame_diff.rs packages/ianvs_terminal/lib/src/proto/frame_diff.pb.dart
```

Expected: no diff after regeneration.

- [ ] **Step 7: Final commit if verification fixes were needed**

If Step 1-6 required small fixes:

```bash
git add native/core packages/ianvs_pty packages/ianvs_terminal example tools/bench docs/FRAME_DIFF.md docs/TESTING.md
git commit -m "test: verify protobuf frame diff transport"
```

If no files changed, do not create an empty commit.

---

## Self-Review Checklist

- Spec coverage:
  - Protobuf schema: Task 1.
  - Rust encode and stats: Task 2.
  - FFI bytes transport: Task 3.
  - Dart decode to `TerminalFrameDiff`: Task 4.
  - Runtime switch and fallback metrics: Task 5.
  - App/test configuration: Task 6.
  - Benchmark metrics: Task 7.
  - Real profile runtime evidence: Task 8.
  - Docs: Task 9.
  - Verification: Task 10.
- No placeholders are intentionally left in the plan.
- JSON remains default in every task.
- Protobuf decode errors are treated as release-gate failures.
- Existing viewport merge and renderer code are not changed.
