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
- `TerminalInputController.clipboardPasteBytesFor` wraps raw paste text inside `ESC [ 200 ~` / `ESC [ 201 ~`; no sanitizer removes embedded bracketed-paste markers before wrapping.
- Existing IME tests cover composition visibility before commit, but the current test set does not cover mid-text composition, resize ordering, high-DPI geometry, long composition clipping, or RTL composition.
- Platform-only checks are queued in [../../XTERM_MANUAL_CONFIRMATION_QUEUE.md](../../XTERM_MANUAL_CONFIRMATION_QUEUE.md): Windows/CapsLock (M-009), fish/kitty Ctrl-C (M-010), IME geometry/overflow/RTL (M-011), and Android physical keyboard duplication (M-012).

## Functional Acceptance

- Add table-driven control-key tests for the xterm upstream key set.
- Add Windows and Android manual probe records, or automated platform tests if Flutter exposes the needed event data.
- Add a bracketed-paste sanitizer fixture with malicious embedded markers before any sanitizer implementation.
- Add an IME probe checklist covering mid-composition, resize, high-DPI, long text, and RTL.
- Link any confirmed product failures to smaller implementation tasks.

## Verification Commands

See [../../TESTING.md](../../TESTING.md).

```bash
cd example
flutter test test/terminal_input_controller_test.dart

cd packages/ianvs_terminal
flutter test test/terminal_input_controller_test.dart --plain-name "Control letters"
flutter test test/terminal_input_controller_test.dart
```

## Manual QA

1. On Windows, test Ctrl-letter combinations with CapsLock on and off in PowerShell and WSL.
2. In fish, verify Ctrl-C interrupts while terminal input focus is active.
3. On Android with a physical keyboard, type repeated keys and shortcuts and confirm no duplicated input.
4. With a Chinese or Japanese IME, compose in the middle of text, resize during composition, test high DPI, long composition text, and RTL text.

## Done When

- Every row in this cluster has a probe command or manual evidence note.
- Confirmed failures have smaller implementation cards.
- The audit table links this task and records the latest probe evidence.

## Risks / Follow-ups

- Some key states may not be representable in Flutter widget tests and will require platform manual QA.
