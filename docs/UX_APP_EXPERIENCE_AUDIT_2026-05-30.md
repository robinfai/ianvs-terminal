# App Experience Audit - 2026-05-30

## Scope

- Target: `example` macOS Flutter app.
- Goal: operate the app from a user point of view, fix blocking issues, and record non-blocking findings.
- Tooling: Computer Use, `flutter run -d macos`, `flutter test`, `flutter analyze`.

## Blocking Findings

1. Desktop verification is blocked by the host Mac lock screen.
   - Evidence: a desktop screenshot taken during the Computer Use pass showed the macOS lock screen, and Computer Use could not access the Ianvs Terminal window.
   - Status: superseded by the 19:45 CST desktop iteration below; the desktop was available and visual app testing continued.

2. macOS main window launch visibility was hardened.
   - Evidence: the app process launched, but the main menu XIB did not declare the main `MainFlutterWindow` as visible at launch.
   - Fix: added `visibleAtLaunch="YES"` to `example/macos/Runner/Base.lproj/MainMenu.xib`.
   - Regression check: added `example/test/app/macos_main_menu_test.dart`.

## Non-Blocking Findings

1. `flutter analyze` previously reported five existing `use_null_aware_elements` info items:
   - `example/test/benchmarks/cat_log_benchmark_test.dart:302`
   - `example/test/benchmarks/cat_log_benchmark_test.dart:303`
   - `example/tool/cat_log_trace_capture.dart:270`
   - `example/tool/cat_log_trace_capture.dart:304`
   - `example/tool/cat_log_trace_capture.dart:423`
   Status: resolved by the null-aware map entry follow-up; the latest `flutter analyze` run reports no issues.

## Verification

- `flutter run -d macos`: built and launched the debug app successfully before the lock-screen blocker stopped GUI inspection.
- `flutter test test/widget_test.dart`: passed, 88 tests.
- `flutter analyze`: initially failed only on the five non-blocking info items listed above; the latest follow-up run reports no issues.

## Next Desktop Iteration

Superseded by the 19:45 CST desktop iteration below:

1. Verify first launch shows the terminal window immediately.
2. Exercise terminal input, command menu, new tab, split pane, search, paste history, defaults, profile sheets, and close/reopen flows.
3. Fix any blocking user-facing defects found in those flows.
4. Record remaining non-blocking polish items here.

## Desktop Iteration - 2026-05-30 19:45 CST

### User Flow Coverage

- Launched the rebuilt debug macOS app through LaunchServices with `open -n`.
- Verified the main window is visible on first launch.
- Verified basic terminal input with `echo IANVS_SMOKE`; output rendered and focus returned to the prompt.
- Opened the command menu with `Cmd+Shift+P`; the menu rendered with search, new tab, defaults, toolbelt, and split actions.
- Verified `Cmd+T` creates a second tab.
- Verified `Cmd+Shift+D` splits the active tab into two panes.

### Blocking Findings Fixed

1. `Cmd+F` was intercepted by the native macOS Edit > Find menu instead of opening in-terminal search.
   - User impact: after pressing `Cmd+F`, typing a query inserted text into the shell prompt, so a common search shortcut could accidentally become command input.
   - Fix: added a native Find menu bridge from `MainFlutterWindow.performFindPanelAction(_:)` to Flutter's `WindowBridge`, then opened/moved the existing terminal search UI from `ShellScreen`.
   - Regression check: added a widget test for `nativeFind` opening the search bar without terminal input writes.
   - Manual retest: after rebuild, `Cmd+F` opened the search bar and typing `SMOKE` stayed in the search field.

### Non-Blocking Findings Recorded

1. Computer Use timed out when reading or typing into the Flutter macOS window.
   - Evidence: `get_app_state` and `type_text` calls timed out against `Ianvs Terminal`.
   - Workaround used for this audit: system screenshot plus local GUI keystrokes.
   - Status: not treated as an app blocker in this pass because the visible app was operable, but it should be revisited if Computer Use/Accessibility automation is part of the product acceptance criteria.

2. Wide windows distribute two tabs across very large tab cells.
   - Evidence: after `Cmd+T`, each tab occupied roughly half the tab strip.
   - Status: visual polish only; not fixed in this pass because tab creation and activation remained functional.

### Verification

- `flutter test test/widget_test.dart --plain-name native\ find\ menu\ opens\ search\ without\ leaking\ input`: passed.
- `flutter test test/widget_test.dart`: passed, 89 tests.
- `flutter build macos --debug`: passed.
- `flutter analyze`: passes with no issues after the null-aware map entry cleanup.
- Manual visual retest: LaunchServices launch, `Cmd+F`, search typing, `Cmd+T`, and `Cmd+Shift+D` all behaved correctly.
