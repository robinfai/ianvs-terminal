# Test Spec — Hyper-like Phase 4 Interaction Polish

## Testing Principles
- Existing terminal behavior remains a protected regression contract.
- Phase 4 proves clearer shell/UI expression, not broader terminal state behavior.
- Any focus-sensitive change must carry keyboard-path evidence.
- `T-055` was `forced-closed`, so the unresolved manual terminal matrix remains a known risk; this test spec must not reclassify that missing evidence as a pass.

## Protected Regression Reruns
Minimum regression chain:

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test test/widget_test.dart
flutter test test/shell/shell_screen_phase2a_test.dart
flutter test test/shell/shell_screen_phase2b_test.dart
flutter test integration_test/flutterm_smoke_test.dart
```

If the Phase 4 change directly consumes session lifecycle state, also rerun:

```bash
flutter test test/sessions/session_controller_test.dart
```

## Targeted Automation
- Add or extend shell-level widget tests only for newly exposed lifecycle or focus-visible behavior.
- Prefer `app/test/shell/shell_screen_phase4_test.dart` or an equivalent bounded extension under `app/test/shell/`.
- Reuse `app/test/widget_test.dart` for empty-state, shell-exit, and recovery paths instead of inventing a broader new smoke surface.
- Do not add core / FFI tests unless the implementation genuinely crosses that boundary.
- Do not add new tests for copy-only text changes, spacing-only changes, color-only changes, or light animation tweaks that introduce no new state.

## Manual Smoke
- session start -> active state
- launcher open/close -> focus return
- defaults/dialog close -> terminal viewport regain focus
- tab close / shell exit -> empty-state transition
- empty-state -> `New Tab` recovery
- keyboard-heavy smoke: `pwd`, `echo hello`, `ls`, copy/paste, scroll, resize`
- do not treat this manual smoke as a substitute for the still-missing VT220 / powerline / trackpad / DPI matrix proof

## Phase Gate
- Check the Phase 4 acceptance criteria line-by-line.
- Keep the protected regression baseline green.
- Sync any changed shell-verification wording back into `docs/TESTING.md`.
- Do not downgrade the unresolved manual-matrix risk left by `T-055 forced-closed`.
- If anyone proposes core / PTY work, require explicit proof that Flutter-only is insufficient before widening scope.
