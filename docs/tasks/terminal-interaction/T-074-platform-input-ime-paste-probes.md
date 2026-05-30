# T-074 Platform Input, IME, and Paste Probes

## Goal

Close the recent xterm.js input/IME/paste probe gaps with platform-specific manual or automated checks before product changes.

## Scope

- Windows Ctrl-letter/CapsLock behavior.
- Exact control-key escape-sequence parity.
- Ctrl-C behavior under fish when kitty mode is not active and when T-070 enables it.
- Bracketed-paste sanitization.
- IME composition in the middle of text, after resize, at high DPI, long composition overflow, and RTL composition.
- Android physical keyboard duplication.

## Non-goals

- Do not implement kitty keyboard protocol here; T-070 owns that scope.
- Do not change app-level shortcut routing outside terminal input.
- Do not add a full cross-platform release matrix; use the smallest probes that prove these rows.

## Files In Scope

- `packages/ianvs_terminal/lib/src/terminal/terminal_input_controller.dart`
- `packages/ianvs_terminal/test/terminal_input_controller_test.dart`
- `example/test/terminal_input_controller_test.dart`
- `example/lib/features/terminal/terminal_viewport.dart`
- `example/lib/features/terminal/render_terminal_viewport.dart`
- `docs/TERMINAL_XTERM_RECENT_FIX_AUDIT.md`

## Probe Evidence

- `cd packages/ianvs_terminal && flutter test test/terminal_input_controller_test.dart --plain-name "Control letters"` passes and covers local Control A-Z to C0-byte mapping, including Ctrl-C.
- `flutter test test/terminal_input_controller_test.dart --plain-name Control` passes existing macOS Control+V, Control+T, and Control+C tests, but it does not cover Windows win32 input mode, CapsLock, fish under kitty mode, or Android hardware keyboards.
- `TerminalInputController.clipboardPasteBytesFor` now removes embedded `ESC [ 200 ~`, `ESC [ 201 ~`, `CSI 200 ~`, and `CSI 201 ~` bracketed-paste markers before adding the outer xterm bracketed-paste wrapper.
- Existing IME tests cover composition visibility before commit. `flutter test test/terminal_input_controller_test.dart --plain-name "middle composition"` passed on 2026-05-30 and covers committing only the replacement segment when an IME composition resolves in the middle of helper text. `flutter test test/terminal_input_controller_test.dart --plain-name "RTL IME"` passed on 2026-05-30 and covers RTL active composition visibility, terminal-bound clipping, and UTF-8 commit. `flutter test test/terminal_input_controller_test.dart --plain-name "terminal viewport clips long composing text to the terminal bounds"` passed on 2026-05-30 and covers long composition clipping near the right terminal edge. `flutter test test/terminal_input_controller_test.dart --plain-name "composing overlay anchored"` passed on 2026-05-30 and covers the visible composing overlay staying attached after an active composition frame/size update. `flutter test test/terminal_input_controller_test.dart --plain-name "IME geometry"` passed on 2026-05-30 and covers non-zero-DPR `TextInputControl` editable-size, caret-rect, and composing-rect sync before and after active-composition resize.
- Computer Use manual pass on 2026-05-29, macOS 15.7.7: in fish normal mode, `sleep 10` was interrupted by ETX and the terminal showed `^C` plus `[SIGINT]`.
- Computer Use could not confirm Windows/CapsLock or Android hardware keyboard behavior on this macOS host.
- Platform-only checks are queued in [../../XTERM_MANUAL_CONFIRMATION_QUEUE.md](../../XTERM_MANUAL_CONFIRMATION_QUEUE.md): Windows/CapsLock (M-009) and Android physical keyboard duplication (M-012). Fish normal-mode Ctrl-C, mid-text IME commit extraction, RTL composition, high-DPI/resize geometry sync, and long composition clipping are covered; kitty-mode Ctrl-C remains deferred through T-070/M-010 because kitty keyboard protocol support is not currently in scope.

## Functional Acceptance

- Add table-driven control-key tests for the xterm upstream key set.
- Add Windows and Android manual probe records, or automated platform tests if Flutter exposes the needed event data.
- Add a bracketed-paste sanitizer fixture with malicious embedded markers before any sanitizer implementation. Done for package-level `clipboardPasteBytesFor`.
- Add an IME probe checklist covering mid-composition, resize, high-DPI, long text, and RTL. Mid-text commit extraction, RTL composition, resize/high-DPI geometry sync, and long text clipping now have widget regression coverage.
- Link any confirmed product failures to smaller implementation tasks.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/terminal_input_controller_test.dart
flutter test test/terminal_input_controller_test.dart --plain-name "middle composition"
flutter test test/terminal_input_controller_test.dart --plain-name "RTL IME"
flutter test test/terminal_input_controller_test.dart --plain-name "composing overlay anchored"
flutter test test/terminal_input_controller_test.dart --plain-name "IME geometry"
flutter test test/terminal_input_controller_test.dart --plain-name "terminal viewport clips long composing text to the terminal bounds"

cd packages/ianvs_terminal
flutter test test/terminal_input_controller_test.dart --plain-name "Control letters"
flutter test test/terminal_input_controller_test.dart --plain-name bracketed
flutter test test/terminal_input_controller_test.dart
```

## Manual QA

1. On Windows, test Ctrl-letter combinations with CapsLock on and off in PowerShell and WSL.
2. In fish, verify Ctrl-C interrupts while terminal input focus is active.
3. On Android with a physical keyboard, type repeated keys and shortcuts and confirm no duplicated input.
4. Optional smoke: with a Chinese/Japanese IME or another RTL-capable native IME, test RTL composition text after platform input changes.

## Done When

- Every row in this cluster has a probe command or manual evidence note.
- Confirmed failures have smaller implementation cards.
- The audit table links this task and records the latest probe evidence.

## Risks / Follow-ups

- Some key states may not be representable in Flutter widget tests and will require platform manual QA.
