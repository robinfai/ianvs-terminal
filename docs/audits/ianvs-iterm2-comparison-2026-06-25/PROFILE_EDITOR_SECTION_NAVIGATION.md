# Ianvs Terminal Profile Editor Section Navigation

Date: 2026-06-25

Scope: implementation and automated proof for `T-UX-006`.

## Evidence Commands

```sh
cd example && flutter test test/profiles/profile_editor_test.dart
cd example && flutter test test/profiles
cd example && flutter test test/shell/shell_screen_phase3_test.dart --plain-name "profile"
cd example && flutter analyze lib/features/profiles test/profiles
```

Latest results in this worktree:

- `flutter test test/profiles/profile_editor_test.dart`: passed.
- `flutter test test/profiles`: passed.
- `flutter test test/shell/shell_screen_phase3_test.dart --plain-name "profile"`: passed.
- `flutter analyze lib/features/profiles test/profiles`: passed.

2026-06-28 rerun:

- `cd example && flutter test test/profiles test/shell/shell_screen_phase3_test.dart --plain-name "profile"`: passed, 41 tests. This includes the section-navigation jump test and profile/defaults shell entry points.

## Matrix

| Requirement | Result | Automated proof |
| --- | --- | --- |
| Split profile editing into navigable sections | Added General, Startup, Terminal, Appearance, Keys, Automation, and Advanced navigation entries. | `profile editor groups controls under the profile hierarchy` asserts all section nav keys exist. |
| Preserve existing field hierarchy and save behavior | Existing section keys remain as compatibility wrappers where names changed. | Existing structured-save, validation, color, trigger, and preset tests still pass. |
| Make deep settings reachable without scanning the full form | Section navigation calls `Scrollable.ensureVisible` for each anchored section. | `profile editor section navigation jumps to deep sections` taps Appearance and Advanced and asserts each section scrolls into the visible body. |
| Keep shell entry points working | Profile editor still opens and saves from Profiles and Defaults flows. | `shell_screen_phase3_test.dart --plain-name "profile"` covers Defaults handoff, Profiles sheet open/create/edit, and new-session-only behavior. |

## Remaining Scope

This completes the section-navigation pass. It does not add full per-profile keybinding editing, import diff/rollback, or per-section dirty-state reset; those remain broader P3 profile-architecture work beyond `T-UX-006`.
