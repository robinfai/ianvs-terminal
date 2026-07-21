# T-303 vttest GUI Gate Determinism

## Goal

Make the real `vttest` release gate deterministic on macOS hosts where concurrent PTY-heavy VT220
tests can transiently fail during `openpty` and the session can become ready one frame before its
terminal viewport is mounted.

## Scope

- Keep the full `cargo test vt220` coverage.
- Run the VT220-filtered Rust tests with one test thread inside the GUI gate.
- Add a repository contract that preserves the serial execution argument.
- Wait for the real terminal viewport before the GUI test tries to focus it.
- Re-run the real macOS GUI + PTY + `vttest` release gate.

## Non-goals

- Do not hide real VT220 assertion failures.
- Do not retry failed product tests automatically.
- Do not change terminal emulation behavior.
- Do not start the frame-pipeline or recording/replay iterations in this task.

## Files In Scope

- `tools/vttest_gui_nightly.sh`
- `example/integration_test/vttest_gui_test.dart`
- `test/docs_contract_test.dart`
- `docs/TESTING.md`
- `docs/compatibility/KNOWN_ISSUES.md`
- `docs/tasks/verification-gates/T-303-vttest-gui-gate-determinism.md`

## Functional Acceptance

- The gate still executes all tests matching `vt220`.
- PTY-heavy VT220 cases execute serially.
- A Dart contract fails if the serial argument is removed.
- The GUI test synchronizes on `TerminalViewport` without relaxing any terminal-content assertion.
- `./tools/vttest_gui_nightly.sh --release-gate` reaches and passes the real GUI `vttest` step.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
dart test test/docs_contract_test.dart \
  --plain-name "vttest GUI gate serializes the PTY-heavy VT220 suite"
./tools/vttest_gui_nightly.sh --release-gate
```

## Result

- Installed Homebrew `vttest` 20251205 at `/opt/homebrew/bin/vttest`.
- The first real gate reached 36/37 VT220 session passes, then failed one concurrent `openpty` call.
  The focused case and the complete serial 37-test VT220 slice both passed, confirming a host PTY
  resource race rather than a terminal assertion failure.
- Added a red-then-green Dart contract and changed only the gate invocation to
  `cargo test vt220 -- --test-threads=1`; no retry or assertion bypass was added.
- A second full gate passed every deterministic stage, then exposed a GUI startup race where the
  session was ready one frame before `TerminalViewport` mounted. `_focusTerminal` now waits for the
  viewport before tapping it; the focused real GUI test passed afterward.
- The final `./tools/vttest_gui_nightly.sh --release-gate` run passed every preflight, Rust,
  Flutter viewport and real GUI `vttest` step. Summary:
  `build/vttest-gui-nightly/20260721T013423+0800/summary.json`.
- Flutter still printed the existing non-fatal `Failed to foreground app; open returned 1` host
  warning while all product assertions passed.
