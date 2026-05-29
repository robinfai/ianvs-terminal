# Technical-blog feedback project action plan

This is a project execution record, not an article-editing checklist. It turns the technical-blog feedback into engineering and product evidence gates for Ianvs Terminal.

## Current review status

Automated review covers the article-feedback engineering risks. Release-host benchmark evidence has been captured, and product-app paste observation found a shortcut/menu safety gap that is now fixed in code and covered by focused widget tests.

| Feedback item | Current status | Evidence |
| --- | --- | --- |
| Frame Diff benchmark | Release-host evidence captured and archived; keep machine/build context attached before quoting externally. | `docs/evidence/2026-05-29-benchmark`, `tools/technical_blog_action_benchmark.sh`, manual release summary below. |
| Required metrics | Covered, including snapshot/delta ratio, JSON bytes, rows emitted, dirty rows, rebuilt rows, viewport shift, fallback reasons, and input-to-display timing. | Per-scenario `cat-log-benchmark.metrics.json`; `input-echo` records `inputToDisplayMicros`. |
| Instant Replay boundary | Closed as v1 lightweight text-frame replay, not diagnostic replay. | `InstantReplayStore` default retention test and v1 decision below. |
| Paste safety | Closed. Command menu paste, `Cmd+V`, and macOS `Edit > Paste` now route through the same paste confirmation policy. | `_pasteToSession`, `_confirmPaste`, `WindowBridge.setNativePasteHandler`, macOS `nativePaste` bridge, focused paste widget tests, manual record below. |
| Shell Hook support | Closed for zsh/bash/fish real pty evidence on this host. | `docs/evidence/2026-05-29-shell-hook`, `cargo test shell_hook_integration --manifest-path native/core/Cargo.toml` |
| Visual correctness | Added row-cache test for unrelated delta rebuilds preserving selection and wide glyph text; broader existing viewport tests cover scroll shift, theme/font, cursor, scrollback, and glyph cases. | `example/test/terminal/render_terminal_viewport_test.dart` |

## P0 evidence gates

| Gate | Project action | Acceptance evidence |
| --- | --- | --- |
| Frame Diff and row-cache benchmark | Run `tools/technical_blog_action_benchmark.sh --out-dir <absolute-dir> --profile release --include-raw-frames` on a quiet machine. | Archived result directory `docs/evidence/2026-05-29-benchmark` contains `commands.txt`, `environment.txt`, `benchmark-summary.md`, and one subdirectory each for `bulk-output`, `streaming-scroll`, `resize`, `alternate-screen`, and `input-echo`, with trace, metrics, and timing JSON. |
| Metrics coverage | Confirm metrics include `snapshotRatio`, `deltaRatio`, total JSON bytes, `totalRowsEmitted`, dirty row distribution, rebuilt row distribution, `viewportRowShiftAbs`, fallback reasons, and input-to-display timing for `input-echo`. | `cat-log-benchmark.metrics.json` in every scenario subdirectory. |
| Paste safety | Verify current macOS product app routes command menu, shortcut, and visible paste entry points through the same paste policy. | Manual record with clipboard payload, entry point, expected confirmation dialog, observed result, and pass/fail; `Command+V` widget regression test passes. |
| Instant Replay v1 boundary | Treat v1 as recent terminal text-frame replay, not diagnostic replay. | Product note states: keeps recent text frames, supports clear/copy, does not claim command/cwd/exit-code export or privacy-redacted diagnostic replay. |

## P1 evidence gates

| Gate | Project action | Acceptance evidence |
| --- | --- | --- |
| Shell Hook productization | Verify zsh, bash, and fish emit command, cwd/pwd, and exit_code where supported; document unsupported shell fallback. | `docs/evidence/2026-05-29-shell-hook` records zsh/bash/fish real pty pass plus proxy/plan/degrade coverage. |
| Visual correctness | Keep row-cache tests tied to correctness, not only cache hit rate. | Widget tests cover dirty-row rebuild, scroll-shift reuse, selection/copy, search highlight, cursor, wide glyphs, theme/font changes, and scrollback. |

## Shell Hook support matrix

| Shell | Expected collection | Current project status | Evidence to record |
| --- | --- | --- | --- |
| zsh | `preexec` command, `precmd.pwd` cwd, `command_finished` exit_code | Covered by native proxy-plan tests and real pty session lifecycle tests. | `docs/evidence/2026-05-29-shell-hook/native-real-pty-shell-hook-session-test.log` |
| bash | DEBUG/PROMPT_COMMAND command and cwd, command_finished exit_code | Covered by native proxy-plan tests and real pty session lifecycle tests. | `docs/evidence/2026-05-29-shell-hook/native-real-pty-shell-hook-session-test.log` |
| fish | event-based preexec/precmd command and cwd, command_finished exit_code | Covered by native proxy-plan tests and real pty session lifecycle tests after installing fish through Homebrew. | `docs/evidence/2026-05-29-shell-hook/native-real-pty-fish-shell-hook-session-test.log` |
| unsupported shell | no stable shell-hook contract | Covered by degrade-path native tests for disabled, unsupported, missing helper, and proxy creation failure cases. | `cargo test shell_hook_integration --manifest-path native/core/Cargo.toml` |

## Manual paste verification record template

- Date/time:
- App build or commit:
- macOS version:
- Clipboard payload:
- Entry point: command menu / keyboard shortcut / top-level paste control / macOS Edit > Paste
- Expected result:
- Observed result:
- Confirmation dialog shown: yes/no
- Paste sent only after confirmation: yes/no
- Read-only block checked: yes/no
- Result: pass/fail
- Notes:

## Manual paste verification record, 2026-05-29

- Clipboard payload: multiline command text
- Command menu paste: confirmation dialog shown
- `Cmd+V`: confirmation dialog shown after shortcut policy fix
- macOS `Edit > Paste`: confirmation dialog shown after native menu bridge fix
- Top-level paste control: reported normal where checked
- Fix applied: route `TerminalActionId.paste` through `_pasteToSession` in the focused shortcut path and fallback shortcut switch; route macOS `paste:` and `pasteAsPlainText:` through the `nativePaste` window bridge
- Focused validation:
  - `flutter test test/shell/shell_screen_phase4_test.dart --plain-name 'command-v uses paste confirmation before sending multiline text'`
  - `flutter test test/shell/shell_screen_phase4_test.dart --plain-name 'paste clipboard confirms multiline text before sending'`
- Product-app manual result: pass

## Release benchmark observation, 2026-05-29

| Scenario | Frames | Snapshot ratio | Delta ratio | JSON bytes | Rows emitted | Dirty row mean | Viewport shift max | Fallback reasons |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| bulk-output | 79 | 0.0127 | 0.9873 | 1,119,474 | 3,120 | 39.49 | 2189.0 | `resize: 1` |
| streaming-scroll | 901 | 0.0011 | 0.9989 | 1,201,129 | 1,801 | 2.0 | 1.0 | `resize: 1` |
| resize | 23 | 0.087 | 0.913 | 210,036 | 649 | 28.22 | 432.0 | `resize: 2` |
| alternate-screen | 222 | 0.0135 | 0.9865 | 332,684 | 558 | 2.51 | 0.0 | `resize: 1`, `alternate_screen_switch: 2` |
| input-echo | 3 | 0.3333 | 0.6667 | 16,623 | 43 | 14.33 | 0.0 | `resize: 1` |

`input-echo` observed input-to-display timing: 10,596 microseconds on the local debug/product path used for this run. Treat as a chain-evidence data point, not a cross-machine latency guarantee.

## Instant Replay v1 decision

Default product boundary: Instant Replay v1 is a lightweight recent text-frame replay feature. It is stable only for viewing, clearing, and copying recent terminal frame text. Diagnostic replay that includes command, cwd, exit code, export format, or privacy-redacted bundles remains a separate future capability.

## Remaining manual gates

No required manual gates remain for this action plan.
