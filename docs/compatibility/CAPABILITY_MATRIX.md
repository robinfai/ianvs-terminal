# Compatibility Capability Matrix

这是 Iteration 01 的兼容性基线，不是功能愿望清单。矩阵按协议输入到产品 UI
的六层链路记录证据；没有代码或测试证据时使用 `Unknown`，不根据“看起来应该支持”
推断。

## 状态口径

- `Yes`：该层存在明确实现和自动化证据。
- `Partial`：该层存在实现，但只覆盖部分变体或还缺真实宿主验证。
- `N/A`：该能力不经过这一层。
- `Unknown`：当前没有足够证据。
- `Deferred`：明确不在 Iteration 01 范围内。
- `E2E macOS`：真实 Flutter macOS app、`NativePtyBackend` 和真实子进程链路。
- `Component`：Rust、Dart 或 Flutter 的确定性自动化，但不是完整真实 app 链路。

## Matrix

| Area | Capability | Parse | State | Frame | Runtime | UI | Verified | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Basics | Real shell startup / input / output / exit | N/A | Yes | Yes | Yes | Yes | E2E macOS | `example/integration_test/real_pty_acceptance_test.dart`: `real PTY shell starts, accepts input, emits output, and exits` |
| Basics | Primary / alternate screen (`DECSET 1049`) | Yes | Yes | Yes | Yes | Yes | E2E macOS | `native/core/tests/session_test.rs`: `session_frame_diff_exposes_alternate_screen_mode`; real PTY test: `real PTY alternate-screen TUI starts, resizes, accepts input, and exits` |
| Basics | VT220 screen features and wraparound | Yes | Yes | Yes | Yes | Yes | Component; external GUI gate available | `native/core/tests/vttest_regression_test.rs`; `example/integration_test/vttest_gui_test.dart`; `tools/vttest_gui_nightly.sh` |
| Basics | Resize and untruncated transcript reflow | N/A | Yes | Yes | Yes | Yes | Component + E2E macOS | `session_reflows_single_long_line_across_resize`; alternate-screen real PTY resize test; debug stats expose `resize_replay_count`, `resize_replay_bytes` and `resize_replay_micros` |
| Basics | Resize after transcript truncation | N/A | Partial | Yes | Yes | Yes | Component | `scrollback_heavy_transcript_is_bounded_and_resize_still_returns_snapshot`; replay is intentionally skipped and `resize_replay_skipped_truncated_count` increments |
| Basics | Unicode width / combining / emoji / cursor columns | Yes | Yes | Yes | Yes | Yes | E2E macOS | `real PTY OSC 1337 UnicodeVersion changes visible columns and survives resize input`; `packages/ianvs_terminal/test/terminal_text_cells_test.dart` |
| Basics | Synchronized output (`DECSET 2026`) | Yes | Yes | Yes | Yes | Yes | Component | `session_synchronized_output_defers_intermediate_frames_until_disable`; `session_synchronized_output_timeout_flushes_stuck_frame` |
| Input | UTF-8 text, navigation and modified keys | N/A | Partial | Yes | Yes | Yes | Component | `packages/ianvs_terminal/test/terminal_input_controller_test.dart`; `example/test/terminal_input_controller_test.dart`; true hardware/layout matrix remains manual |
| Input | Kitty keyboard protocol | Yes | Yes | Yes | Yes | Yes | Component | `native/core/tests/session_test.rs`: kitty keyboard mode/stack tests; `packages/ianvs_terminal/test/terminal_input_controller_test.dart`: kitty keyboard encoding tests |
| Input | Bracketed paste and paste safety | Yes | Yes | Yes | Yes | Yes | Component | `session_frame_diff_exposes_bracketed_paste_mode_for_xterm_profiles`; `terminal_input_controller_test.dart`; `example/test/shell/shell_screen_phase4_test.dart` |
| Input | Focus reporting | Yes | Yes | Yes | Yes | Yes | Component | `session_frame_diff_exposes_focus_tracking_mode`; `packages/ianvs_terminal/test/terminal_focus_reporter_test.dart`; pane-scoped viewport tests |
| Input | X10 / SGR / SGR-pixel mouse reporting | Yes | Yes | Yes | Yes | Yes | Component; physical device manual | `session_frame_diff_exposes_sgr_pixel_mouse_encoding`; `packages/ianvs_terminal/test/terminal_input_controller_test.dart`; real trackpad remains manual |
| OSC | Window title / icon title | Yes | Yes | Yes | Yes | Yes | Component | title fields are covered by native frame tests and `example/test/sessions/session_controller_test.dart` |
| OSC | OSC 8 hyperlinks and protocol IDs | Yes | Yes | Yes | Yes | Yes | Component | `xterm_sessions_surface_osc8_hyperlink_ranges`; `terminal_frame_codec_parity_test.dart`; `render_terminal_viewport_test.dart` |
| OSC | OSC 52 clipboard query / policy | Yes | Yes | N/A | Yes | Yes | Component | `session_emits_clipboard_paste_requests_from_osc_52_queries`; `example/test/sessions/session_controller_test.dart`; `shell_screen_phase4_test.dart` |
| OSC | OSC 5522 MIME paste mode | Yes | Yes | Yes | Yes | Yes | Component | `session_frame_diff_exposes_osc5522_mime_paste_mode`; terminal input/controller coverage |
| OSC | OSC 99 notification lifecycle and reports | Yes | Yes | Yes | Yes | Yes | E2E macOS | `real PTY OSC 99 assembles, updates, expires and closes by stable ID`; `real PTY OSC 99 reports explicit menu interactions to its source child` |
| OSC | iTerm2 OSC 1337 copy, download, URL, attention, annotations, blocks, UnicodeVersion | Yes | Yes | Yes | Yes | Yes | E2E macOS | OSC 1337 cases in `example/integration_test/real_pty_acceptance_test.dart` |
| Graphics | iTerm2 inline images | Yes | Yes | Yes | Yes | Yes | Component | `session_frame_diff_scopes_iterm_graphics_to_alternate_screen`; `packages/ianvs_terminal/test/terminal_viewport_render_test.dart` |
| Graphics | Sixel graphics | Yes | Yes | Yes | Yes | Yes | Component | `session_frame_diff_exports_sixel_placements_and_asset_bytes`; Sixel viewport/asset tests |
| Graphics | Kitty graphics, animation and shared memory | Yes | Yes | Yes | Yes | Yes | Partial component | core/session and viewport tests cover direct/file paths; POSIX shared-memory cases can skip unless `IANVS_REQUIRE_POSIX_SHM_TESTS=1` |
| Graphics | Font fallback, DPI and cross-display visual fidelity | N/A | Partial | Yes | Yes | Partial | Manual only | [MANUAL_VERIFICATION.md](MANUAL_VERIFICATION.md); no cross-host golden baseline |
| Shell integration | DCS hook parse and command lifecycle | Yes | Yes | N/A | Yes | Yes | Component + E2E macOS | zsh/bash/fish lifecycle tests in `native/core/tests/session_test.rs`; real PTY automatic profile switching test |
| Shell integration | Prompt marks, cwd/user/context and profile switching | Yes | Yes | Yes | Yes | Yes | E2E macOS | `real PTY shell hooks restore automatic profile switching baselines`; session controller shell-context tests |
| Shell integration | SSH / remote shell lifecycle | Unknown | Unknown | Unknown | Unknown | Unknown | Deferred | Current product is local-shell only; see [KNOWN_ISSUES.md](KNOWN_ISSUES.md) |
| File transfer | ZMODEM receive over a live PTY (native core on macOS/Linux; example picker UI on macOS) | Yes | Yes | N/A | Yes | Partial | Component + CI real OpenSSH PTY | `zmodem.receive.v1` is emitted by the native core only on macOS/Linux; the current example product supplies file dialogs only in its macOS runner. `native/core/tests/zmodem_ssh_test.rs` and the Docker/Colima fixture verify GNU `lrzsz` `sz -e`, independent MD5, byte size and exact whole-second mtime in CI; the Windows CI job asserts capability omission and `unsupported_platform`; see [protocol](../protocols/ZMODEM_V1.md) |
| File transfer | ZMODEM send over a live PTY (native core on macOS/Linux; example picker UI on macOS) | Yes | Yes | N/A | Yes | Partial | Component + CI real OpenSSH PTY | `zmodem.send.v1` is emitted by the native core only on macOS/Linux; the current example product supplies file dialogs only in its macOS runner. The Docker/Colima fixture verifies GNU `lrzsz` `rz -bye`, independent MD5, byte size and exact whole-second mtime in CI and in the checked [Colima evidence](../evidence/ZMODEM_COLIMA_OPENSSH_2026-08-07.md); the Windows CI job asserts capability omission and `unsupported_platform`; see [protocol](../protocols/ZMODEM_V1.md) |
| Platform | macOS app bundle and real PTY | N/A | Yes | Yes | Yes | Yes | E2E macOS | `make verify`, macOS smoke, real PTY acceptance and Runner XCTest |
| Platform | Linux / Windows app and PTY | Unknown | Unknown | Unknown | Unknown | Unknown | Deferred | No Linux/Windows runner directories or current device evidence |

## Baseline commands

The authoritative command descriptions are in [TESTING.md](../TESTING.md).

```bash
make bootstrap
make analyze
make test
make verify
```

Focused Iteration 01 evidence:

```bash
cd native/core
cargo test --test session_test session_reflows_single_long_line_across_resize -- --exact
cargo test --test session_test scrollback_heavy_transcript_is_bounded_and_resize_still_returns_snapshot -- --exact

cd ../../example
flutter test -d macos integration_test/real_pty_acceptance_test.dart \
  --plain-name "real PTY shell starts, accepts input, emits output, and exits"
flutter test -d macos integration_test/real_pty_acceptance_test.dart \
  --plain-name "real PTY alternate-screen TUI starts, resizes, accepts input, and exits"
flutter test -d macos integration_test/real_pty_acceptance_test.dart \
  --plain-name "real PTY OSC 1337 UnicodeVersion changes visible columns and survives resize input"
```

## Interpretation boundary

`Yes` does not mean every application or host combination is proven. It means the named layer has
repository evidence. Platform, visual, font, physical input-device and external `vttest` gaps remain
visible in [KNOWN_ISSUES.md](KNOWN_ISSUES.md) and [MANUAL_VERIFICATION.md](MANUAL_VERIFICATION.md).
