# Compatibility Manual Verification

Automated gates are authoritative for deterministic behavior. Use this checklist only for host,
visual and physical-input behavior that the repository cannot reliably assert.

## Record header

Before running a lane, record:

- date, tester and commit/worktree identifier
- macOS and Flutter versions
- machine/display scale and device pixel ratio
- profile, shell and font family/fallbacks
- exact command, result (`pass`, `fail`, `blocked`) and evidence path

Never record a missing prerequisite as `pass`.

## Prerequisites

```bash
bash tools/check_terminal_manual_matrix_prereqs.sh
command -v vttest
cd example && flutter devices
osascript -e 'tell application "System Events" to get UI elements enabled'
```

The accessibility result may be `false`; record it as a host limitation. The deterministic real PTY
suite does not depend on Accessibility permission.

## Real `vttest` GUI lane

```bash
./tools/vttest_gui_nightly.sh --release-gate
```

Expected:

1. deterministic Rust and Flutter VT regressions pass;
2. the app launches a real VT220 profile backed by `NativePtyBackend`;
3. the test navigates `vttest` reports and screen-features menus;
4. the generated `build/vttest-gui-nightly/<timestamp>/summary.json` says `passed`.

If `vttest`, a GUI session or a macOS Flutter device is missing, record `blocked` plus the summary
path. Do not substitute a visual glance for the automated menu assertions.

## Font, Unicode and DPI lane

1. Run `cd example && flutter run -d macos`.
2. Display ASCII, CJK, combining marks, emoji/ZWJ sequences, Powerline and Nerd Font glyphs.
3. Move the window between displays/scales and resize it repeatedly.
4. Confirm glyphs do not overlap, continuation cells remain aligned, the cursor stays on the logical
   column, and fallback boxes are recorded with the active font profile.
5. Repeat in light/dark mode and at increased text scale when applicable.

## Keyboard, IME, paste and focus lane

1. Exercise the active keyboard layout plus one non-Latin IME.
2. Confirm text composition does not emit partial duplicated input.
3. Confirm arrow/function/Alt/Command shortcuts reach the expected app or terminal owner.
4. Paste single-line, multiline and large content; confirm policy prompts and bracketed-paste behavior.
5. Switch tabs/panes and app focus while focus reporting is enabled; confirm reports stay scoped to
   the originating pane.

## Trackpad, mouse and resize lane

1. Exercise scrollback with wheel and physical trackpad momentum.
2. Confirm mouse-reporting apps receive press, release and motion without scrolling the viewport.
3. Resize during ordinary shell output and an alternate-screen TUI.
4. Confirm return-to-bottom, selection and pointer behavior after resize.
5. Record any truncated-transcript case separately; it cannot claim full historical reflow fidelity.

## macOS host effects lane

1. Grant/deny system notification permission and trigger bell/OSC 99 notifications.
2. Confirm activation, numbered button and dismiss actions route to the originating pane.
3. Verify clipboard, file-save/open-URL prompts and user-attention effects respect policy.
4. Record foreground warnings, permission prompts and any host denial independently from product
   assertions.

## Canonical record

The historical local-only matrix and result format remain in
[T-059](../tasks/verification-gates/T-059-local-terminal-manual-matrix.md). Attach new evidence there
or in a dated task record; this checklist does not itself assert that a manual run occurred.
