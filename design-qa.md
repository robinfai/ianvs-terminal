# UI design QA

## IDE presentation and icon redesign — 2026-10-31

Scope: restyle the application with JetBrains IDEA as the core reference while
preserving business logic. Apply a shared light/dark presentation layer, revise
settings/Profile/SSH/AI dialog hierarchy and form styling, and assess the actual
production icon font. Network, persistence, command execution, validation and
save/cancel handlers are unchanged.

Design decisions:

- Centralize neutral surfaces, muted separators, blue selection/focus, 4 px
  controls, 6 px panels and 8 px dialogs in `ide_theme.dart`. Keep existing body
  typography, font fallback, control density and hit targets. Mobile remains
  fixed-size; desktop scaling remains supported.
- Use compact title bars and footers, a 208 px settings sidebar, neutral selected
  text, and section headings without nested card borders. Existing responsive
  configuration rows retain aligned labels on desktop and stack when narrow.
  The AI provider dialog is wider to accommodate its existing form layout.
- The production font was already Material Symbols Outlined at weight 300;
  Flutter icon suffixes did not indicate mixed rendered families. Comparison of
  weights 300 and 400 at 16/20/24 px in both themes selected 400 for clearer small
  controls. Desktop toolbar glyphs use 16 px and navigation/touch glyphs 20 px.
  `AppIcons` gives configuration actions consistent semantic names. Launch,
  terminal and advanced sections now have distinct, relevant glyphs.
- Keep the bundled font's existing codepoint contract and license files. The
  regeneration script exposes weight and optical size; the font README records
  pinned upstream provenance and hashes. Font inspection found 8,667 codepoints
  and no missing/empty glyphs or invalid side bearings among 244 actual Material
  icon references in the app and terminal package.
- All visual captures now default to the production icon asset. The previous
  SDK substitute concealed the app's actual icon appearance.

References: [JetBrains layout](https://plugins.jetbrains.com/docs/intellij/layout.html)
and [icon guidance](https://plugins.jetbrains.com/docs/intellij/icons.html).
This is a Trail adaptation, not a pixel-identical clone.

Evidence and validation on macOS 27.0.1:

- 669 targeted widget/theme/settings/Profile/AI and full-UI scenario checks
  passed. Existing focus, error, disabled and primary-button contrast tests pass.
- Complete `test/design` regeneration: 841 passed, one pre-existing conditional
  skip. 53 affected macOS 27 goldens were refreshed, covering settings, Profile,
  SSH forms, shell and Composer. Representative light/dark and compact/scaled
  captures were visually inspected; no unresolved clipping was observed.
- Full application `flutter analyze --no-pub`: no issues. Formatting and
  `git diff --check` pass.
- A normal complete `flutter test --no-pub test/design` comparison also passed:
  841 tests, one conditional skip.
- `flutter build macos --debug --no-pub` succeeded on macOS 27.0.1. The built
  app's FontManifest registers MaterialIcons exactly once, using the new asset;
  its bundled font is byte-identical to the source (SHA-256
  `2547f6988aea023714f6de85db3ed54040e9f1f6194f724b09ab1e621c6eb099`).
  This proves native packaging, not interactive runtime verification. Existing
  Swift/plugin migration warnings remain outside the presentation change.
- Local before/after icon boards are in `tmp/idea-icon-comparison/`; a reusable
  native catalogue and capture test are committed in `ui/previews` and
  `test/design`. Checked-in golden captures provide durable window evidence.

Validation boundary: iOS platform variants are host-rendered widget tests, not
native-device coverage. macOS 26 CI baseline candidates still require generation
and review before this redesign is ready to merge. Baselines are not copied
across OS versions and comparator tolerances are unchanged.

## Earlier AI workspace, Composer and shortcut review

Date: 2026-10-28

## Chosen direction

Use a centered 880 logical-pixel reading column for desktop AI messages, status and Composer. Keep 24-pixel side gutters (12 below 600 pixels). Preserve mobile spacing and full-screen terminal layout. Keep the Composer structure and actions; refine target-label weight, editor breathing room and action spacing. Replace the plain shortcut paragraph with three labeled groups, aligned descriptions and individual keycaps. Narrow layouts stack the description over wrapping shortcut alternatives; the dialog body scrolls independently of its footer.

The user authorized autonomous selection and implementation. Three alternatives were generated for each design task. Selected the balanced reading column and the grouped, description-first shortcut reference.

## Visual evidence

Sources:
- AI direction: `/Users/robinfai/.codex/generated_images/01a1802e-6cce-7732-81ea-5fdbcea61003/exec-86f2a12d-a6f2-4a20-9dee-0fec9e3ed916.png` (1487 × 1058).
- Shortcut direction: `/Users/robinfai/.codex/generated_images/01a1802e-6cce-7732-81ea-5fdbcea61003/exec-2552d569-07a9-40e6-8553-9c0591761d60.png` (1487 × 1058).
- Original Composer: `/var/folders/k2/8qbf3nrs7t1749d198rw0df40000gn/T/codex-clipboard-c1eddd3d-afbd-4c10-827c-f77976921ac6.png` (2016 × 484).

Rendered Flutter implementation:
- `/private/tmp/terminal-ai-width-after/roles-desktop-reference-followup.png`: 1440 × 1024 logical viewport, 2880 × 2048 pixels, 2× capture density; completed Chinese AI conversation.
- `/private/tmp/terminal-composer-after/composer-refined-desktop.png`: 1440 × 1024 logical viewport, 2880 × 2048 pixels, 2×; focused command draft. The fixture's history-storage warning is not part of this UI change.
- `/private/tmp/terminal-shortcuts-after/desktop.png`: 1008 × 994 viewport and pixels, 1×; Chinese shortcut dialog, light theme.
- `/private/tmp/terminal-shortcuts-after/dark.png`: same dimensions, dark theme.
- `/private/tmp/terminal-shortcuts-after/phone.png`: 320 × 568, 1×, fixed mobile text size.
- `/private/tmp/terminal-shortcuts-after/short.png`: 640 × 400, 1×.
- `/private/tmp/terminal-shortcuts-after/scaled.png`: 960 × 850, 1×, desktop text scale 2.

Generated directions and rendered captures were opened together in the same image comparison input. These are design-direction comparisons, not pixel-identical clones: generated mock dimensions, typography, background content and role gutter differ from the existing application. Implementation preserves the production theme, shared role gutter and native dialog scaffold. Capture fonts use the repository's deterministic Roboto/Noto Sans SC/mono fixtures; live system-font rendering is not claimed identical. Logical viewport and capture density are recorded above to avoid treating 2× captures as double-width layouts. The shortcut reference is readable in its full-size component capture; no additional crop was needed for those keycaps and labels. Composer and reading-column details were inspected in the full-resolution capture.

## Findings and comparison history

- Initial desktop dialog evidence used a resized render surface but retained the test's default MediaQuery size. This incorrectly made a tall desktop window appear to require scrolling. Corrected the test to set physicalSize and devicePixelRatio together; recaptured all five scenes. This was an evidence calibration issue. The revised desktop capture shows all three groups and a fixed footer.
- No remaining actionable P0/P1/P2 visual issues in the reviewed scope.
- Intentional differences from the generated shortcut mock: include every existing alternative (first-line up arrow, right arrow, Ctrl+F/E), retain platform-specific modifier labels, separate undo and redo, and clarify Ctrl+C's no-selection behavior. Shared dialog chrome provides a close button and a fixed footer.

Required surfaces:
- Typography: production text styles retained; target label and keycaps use medium weight. Descriptions wrap without clipping. Desktop 2× text remains readable and scrollable.
- Spacing/layout: centered reading column and Composer share a maximum width and axis. Desktop dialog groups and keycap columns align; short/narrow dialog content scrolls with close/done controls available.
- Colors/tokens: all new colors, borders and radii use existing theme tokens. Light/dark captures retain distinguishable keycaps, body text and section labels.
- Assets: no new imagery is required. Keycaps are native UI widgets; shortcut symbols are text with semantic labels. Existing icon assets remain unchanged.
- Copy: shortcut labels match existing handlers. The dialog adds no new keyboard behavior. Chinese and English copy is implemented; Chinese is visually captured.

## Verification

- AI tests: 714 passed, including centered-width geometry, responsive captures and draft/focus ownership across resizing.
- Shortcut dialog: 5 scene tests passed; content can be scrolled to the last shortcut; Done and Escape dismiss it; no overflow exceptions.
- Composer menu: 2 platform tests passed; dismissal preserves draft, does not execute it, restores focus; desktop resize preserves focus and draft.
- Static analysis: original seven changed Dart files checked; two const-literal lint findings corrected and affected files rechecked cleanly.
- Whitespace/diff checks passed.

## Implementation checklist

- [x] Center desktop conversation/status/Composer with a shared 880-pixel limit.
- [x] Preserve mobile and full-screen terminal layout.
- [x] Refine Composer details without replacing input ownership or command handling.
- [x] Group shortcut descriptions and render accessible keycaps.
- [x] Check light/dark, narrow/short windows, desktop text scaling and dismissal/focus behavior.

Residual validation gap: these are rendered Flutter widget tests on the local SDK, not a claim of live-app verification on every supported OS. The remote refactor CI checks the previously pushed commit, not these uncommitted UI edits.

## Previous reviews

- [Header tabs](docs/product/header-tabs-2026-10-17/design-qa.md)
- [Application UI refinement](docs/product/ui-refinement-2026-10-13/README.md)

final result: passed

## Follow-up: accepted draft and inline activity

Selected the inline reply pulse from three generated alternatives. An accepted prompt now publishes its transcript entry and cleared draft together, before waiting for ACP's first event. Later edits remain intact. Desktop activity appears at the end of the conversation, aligned with assistant prose; the bottom retains reachable pause and navigation controls. Streaming prose changes the phase to generating. The empty busy Composer says “补充要求…”.

Selected source: `/Users/robinfai/.codex/generated_images/01a1802e-6cce-7732-81ea-5fdbcea61003/exec-c5eec40d-b549-49c2-a331-cbd03aab3add.png`.

Actual Flutter captures in `/private/tmp/trail-inline-activity-after/`:
- `inline-activity-light.png`: 1728 × 1084 logical, 2× capture.
- `inline-activity-dark.png`: 1100 × 850 logical, 2× capture.
- `inline-activity-narrow.png`: 520 × 800 logical, 2× capture.
- `inline-activity-reduced.png`: 960 × 850 logical, 2× capture.

Compared source and actual light capture together, and inspected dark/narrow captures. Existing production typography, role gutter, icons and theme colors are preserved; the fixture excludes application window chrome. No new image assets. The three dots pulse over 1.2 seconds, use theme primary color, and remain static with reduced motion. Activity text has a live semantic label; decorative dots are excluded. Mobile retains its existing compact task strip above output. No remaining actionable P0/P1/P2 issues in this scope.

Verification: 723 AI tests passed, including delayed first ACP event, newer draft preservation, generating phase, light/dark/narrow layouts and animated versus reduced-motion dots. Targeted static analysis found no issues. Diff whitespace checks passed. These are local widget/native-fixture checks, not live-app or remote CI verification of the uncommitted changes.

Follow-up final result: passed

## UI audit round 1: history recovery and status feedback

Real development-app inspection found that saved manual commands used an empty tool-call object, which the history reader rejected. Manual command snapshots now preserve their command identity explicitly; existing empty-call records recover as read-only commands. No execution approval is restored. Original development history was read without changing its files during diagnosis, then successfully restored in the running app.

History storage notices are separate from AI activity and describe load, save or invalid-record failures, with a retry action. A history error no longer replaces thinking/generating status. Notification permission failures now use Chinese copy in a Chinese UI and give the System Settings path while clarifying that terminal use remains available.

Validation: 726 permanent AI tests plus one temporary read-only local-history diagnostic passed; the temporary diagnostic was removed. Four notification tests passed. Targeted static analysis and diff whitespace checks passed. Live development UI now shows restored read-only history without the storage error. Accessibility labels reported by the independent UI audit remain queued for the next round; this result does not claim those findings resolved.

## UI audit round 2: menu keyboard dismissal and accessible controls

Desktop Composer menus now take focus and return it to the editor on cancellation. One Escape closes the menu in the running development app. Mobile retains its input focus behavior. Two platform Composer menu regression tests pass, including preserving drafts and avoiding command submission on dismissal.

History, Composer actions/expand, task pause and command-block actions/folding now expose explicit icon semantics. Reader back/find controls have names while retaining the original BackButton behavior. Configuration text fields use separately named semantic groups: live macOS inspection confirms executable path, arguments and model groups surrounding their fields. Native text-field nodes themselves remain unnamed in the computer tool output; the enclosing names make their identities available. This does not claim a complete VoiceOver audit.

Validation: 26 AI settings/command-title tests, one configuration-field semantics test and 15 reader host/tools tests passed. Targeted analysis and whitespace checks passed. The new development app was rebuilt and launched independently. Remaining audit findings: replay/terminal view switching can leave stale semantics and intercept input; local-only sync displays misleading readiness; SSH validation errors need accessible announcement. These are tracked for the next round, with replay interaction first.

## UI audit round 3: replay accessibility, search and truthful status

Replay close/refresh controls now provide labels on their icons instead of nesting MergeSemantics around IconButton. Native macOS inspection reproduced Flutter AXTree update rejection with the old controls; the final rebuilt development application now exposes the replay shelf, close, recent activity and refresh actions. A speculative layout semantics wrapper was removed after it caused an iPad resize regression. No workspace remount or draft reset is used.

Terminal search invoked from AI opens the read-only observer with a visible search field and match highlights. The hidden terminal no longer mounts a second search field with the same focus node. AI draft and execution ownership are preserved. Observer back/details actions also have explicit names.

The bundled local data service is presented as local storage instead of cross-device sync readiness. SSH empty submissions show a live error summary and focus the first invalid field; editing clears the summary. SSH fields expose named groups. Testing an unchanged saved AI configuration now reports connection success without falsely claiming it has not been saved.

Validation: 74 existing targeted tests passed; the observer suite with the new AI search regression passed all 21 tests, SSH suite including the new empty-submit live-error regression passed all 5 tests, and the AI replay shelf regression passed. App static analysis and diff whitespace checks passed. Native replay open/close and observer/search navigation were checked on the development macOS app; the final rebuilt app also confirms replay shelf accessibility after removing the speculative wrapper. Independent GUI re-verification is pending. This is not a complete VoiceOver audit or remote CI result.

Independent round-3 review confirmed terminal search, local-only sync presentation, SSH live validation/named groups, and the saved-configuration connection message. Entering recent-activity playback exposed the same nested semantics defect in the shared replay control button; that button now uses its own icon label as well. Twelve player/recording-library tests and targeted analysis passed. The patched development app was rebuilt and restarted for a final player check. Native checks ran on macOS 27.0.1; other supported macOS versions were not exercised in this round.

Independent playback recheck passed: complete player accessibility, progressing playback and button-driven return to AI. Profile recheck found additional field-label gaps in list arguments, scrollback, individual font metrics and rule editors. These now have independent named groups; 22 Profile editor tests and targeted analysis passed. A reported new-task accessibility failure after a long player/Profile navigation sequence did not reproduce in a fresh direct history-to-new-task check; the complete sequence remains under independent recheck with native diagnostics enabled.

Profile field recheck passed all six reported categories. The historical-task switch was then reproduced specifically through the session task menu. Replacing CheckedPopupMenuItem's nested ListTile semantics with a plain task entry (retaining an explicit current-task text marker) preserved the native accessibility tree across history → new task → historical task → new task. The complete AI workspace suite passed 117 tests. Independent repetition of this final switching path remains pending.

Finite end-to-end checks passed explicit AI approval of `pwd` (no execution until confirmation, exit code 0 and cited evidence) and recording start → test output → save → reopen → playback. They exposed a native Cmd-W routing gap: terminal focus was correct, but the keystroke did not reach Flutter HardwareKeyboard. File → Close Tab now bridges Cmd-W to the existing protected tab-close path, with modal guards. The macOS XCTest verifies the selector, modifier and idempotent menu registration; it passed. Two Flutter cases verify both keyboard and native-menu closure restoring the AI draft. The input-intent menu also avoids CheckedPopupMenuItem's nested ListTile semantics while preserving labels and a current-item checkmark. AI workspace/observer suites passed 140 tests; targeted analysis is clean. Final native navigation recheck is pending.

## UI audit round 4: native Slider semantics failure

Incremental macOS AX diagnostics isolated the first failure to opening recent-activity playback, before playback or Profile navigation. The failing node was Material Slider's always-mounted value-indicator OverlayPortal child. Earlier control-label and menu changes improved naming but did not eliminate this root failure. The observed native error matches Flutter issue https://github.com/flutter/flutter/issues/190357; changing value-indicator visibility alone cannot remove that portal.

All three application Material sliders (shared desktop replay timeline, mobile replay transport and default viewport padding) now host their existing slider in a local `Overlay.wrap`, keeping the value-indicator semantics within the same subtree. The original Material keyboard, pointer and accessibility actions are retained. Replay timeline and segment controls have distinct semantic boundaries. The defaults reset/shortcut menus now expose explicit icon names, and the defaults scrim uses the existing localized close label.

Regression checks enable semantics before opening playback and exercise accessibility increase/decrease plus Tab traversal and Left/Right adjustment. This test passed; 13 recording-library/lifecycle/mobile-player checks and 33 defaults/mobile-player checks passed. Native keyboard inspection confirmed Tab twice from the replay viewport reaches the slider, Right advances 0% to 10%, and Left returns to 0%. Mouse clicks do not themselves imply keyboard focus on macOS.

Independent GUI review passed the original long path on the first local-overlay build: recent replay play/pause/drag/close → all Profile pages → cancel → restore the ESC_FOCUS_CHECK read-only task with command blocks → new task → text input. Subsequent inspection found the same native error after opening the previously unwrapped defaults slider despite a temporarily intact GUI; the final build covers that slider too. Final independent verification passed viewport padding 8→19→cancel→AI history→new task/input; replay keyboard 0%→10%→0%; and the complete replay/Profile/history/new-task path. Native logs for this build contained no AXTree errors. Validation platform remains macOS 27.0.1; this is not a claim of full VoiceOver coverage, other OS validation or remote CI success.


## UI audit round 5: distinguish unnamed history

The GUI reviewer found several existing unnamed command histories all labeled “New task · Follow-up ended”. The menu now prefers an existing title, otherwise the first command name (without arguments, paths or environment assignments), otherwise a generic draft/new-task label. A second line adds a session-list ordinal and the existing follow-up/current markers. Old records have no reliable task timestamp, so no timestamp is invented. Raw command arguments and draft contents are not promoted into the menu; no persistence schema or stored content is expanded.

Validation: all 127 history/workspace tests passed, including selection of the correct command task and checks that arguments and private draft contents do not appear in the menu. Targeted analysis and whitespace checks passed. The development app was rebuilt and restarted. Independent GUI review confirmed distinct exit/cd/draft entries with task ordinals and current/follow-up markers, selecting exit task 4 restored the correct read-only unknown receipt, and new-task Chinese input worked. Final runtime logs contained zero AXTree update errors or Flutter exception markers. Screenshot: `/private/tmp/trail-ui-audit-20261028/29-history-distinguishable.png`. The reviewed local basic flows have no remaining reported issues. Real SSH/SFTP, cross-device sync, complete VoiceOver coverage, all themes/sizes, file exports and execution of automation rules were not verified end-to-end.

## Expanded audit: diagnostics and Profile automation (in progress)

The independent reviewer expanded coverage to themes, small windows, exports and automation. Plain-text terminal export passed Chinese/newline/ANSI-removal checks. New findings remain under review; the earlier completed local-flow scope does not imply this expanded scope is complete.

Diagnostic summaries now use the application language and distinguish fewer than two valid samples, missing child-process evidence and scores below attribution thresholds. The reviewed 60-sample capture had zero attribution scores: it did not capture a clear bottleneck, rather than lacking two samples. Readable next steps no longer repeat the misleading generic sampling advice. Machine evidence and codes remain in technical details/JSON. Desktop notification close icons expose a localized accessible name. The diagnostics/notification suites passed 21 tests.

Automation editors now explain trigger regexes, default notify behavior, send-text escaping/no implicit Enter, persistence of response text, and Profile switching syntax/scope/precedence. Invalid rules expose localized line-numbered errors as live semantic nodes. The 23 Profile editor tests passed, including Chinese validation semantics. Actual rule execution uncovered a separate native first-line loss.

Native output observations are subscribed correctly, but zsh bracketed-paste changes, a redundant carriage return on an empty line and DCS shell-hook metadata suppressed the first command-output line. A regression failed with zero observations before the fix. The observer now recognizes only metadata-only hook streams and bracketed-paste input mode without conflating them with screen edits; graphic/unknown control strings, rewrites, alternate screens and overflow remain conservative. Eleven observer tests (including all split points and malformed/control-string cases), a real PTY observation test and three Flutter Profile-trigger tests passed. The native source mirror was updated and checked with the repository synchronization tool. Independent GUI verification then received `RECEIVED:UX_REPLY_OK` immediately from the saved automatic-send rule. Screenshot: `/private/tmp/trail-ui-audit-20261028/32-auto-send-pass.png`. The new diagnostic export also passed Chinese explanation/next-step and notification-close-label checks.

Expanded navigation exposed further native AXTree errors. Flutter's upstream fix https://github.com/flutter/flutter/pull/193372 describes an overlay descendant being serialized while its zero-opacity anchor is hidden. Notification opacity and the command-palette fade now always include their child semantics during transitions. All eleven notification tests passed, including controls remaining accessible on the first fade frame. A fresh process and command-palette opening showed a complete native tree and no AXTree errors.

Profile errors are now sibling live semantic nodes outside TextFormField: putting an error below the native text-field leaf passed widget checks but was invisible in the native tree. Twenty-three Profile tests and a focused ancestor/semantics regression passed. Independent GUI review confirmed separate Chinese error text for an invalid trigger regex and an invalid Profile-switch prefix, save interception, and safe discard of invalid drafts. Runtime diagnostics remained clean through this stage; whole-example static analysis and diff whitespace checks passed. Notification delivery, actual automatic Profile switching and remaining theme/size checks are still pending. The fade change is a targeted application workaround, not a claim that the upstream framework defect is universally resolved.

Notification follow-up: System Settings visibly had Trail Development notifications enabled; the reviewer did not change that setting. A subsequent trigger produced one runtime match, no recorded notification failure and `notificationsBlockedBySystem=false`; Notification Center receipt is not yet independently confirmed. Native authorization API errors previously shared the permission-denied code, which could incorrectly describe a transient API failure as a disabled user setting. They now use a distinct code and localized retry message; explicit denial retains its settings guidance. Both feedback regressions and whole-example analysis passed. This latest native classification change has not yet been rebuilt into the running app. The reviewer confirmed that Notification Center access timed out after 162 seconds; user authorization was already supplied, and no notification preference was changed. Actual receipt remains unverified, while automatic Profile switching and theme review continue without retrying the blocked system surface.

Automatic Profile switching passed entry into the configured directory, entry into its child and restoration after leaving. The reviewer found that selecting Moss Night changed the cursor but left a white canvas, including in a new session. The application color bridge discarded explicit Profile foreground/background colors. It now honors those colors, keeps unspecified colors following the app theme, and derives scrollbar contrast from the terminal canvas. Application titlebar surfaces continue following the app theme. Fifty-eight theme, contrast, fade and shell-window checks passed, as did whole-example analysis. The rebuilt native application includes both this fix and the notification-error classification above. Initial native inspection shows the Moss Night dark canvas, complete AX controls and no AXTree/exception markers; independent visual theme and transition review is in progress.

Independent review passed Moss Night in a new session and simultaneous Profile-name/palette changes on directory entry and restoration. Further visual review found excessive fixed header space at the minimum desktop window, English color guidance in Chinese UI, no useful terminal preset preview, and a color-picker error hidden below the native text-field leaf. Short desktop windows now use a compact header, combined search/section selector and inline modified-section summary; the 640×502 layout keeps over 260 logical pixels for scrollable settings. Draft colors render a local text/cursor/selection/ANSI preview before saving. Color guidance and swatch labels are localized, with “选区颜色” distinguishing selection color from a pick action. Color-picker errors use sibling live semantics while retaining invalid-input styling and disabled Apply. Profile tests passed all 24 cases before expanding the semantic assertion; the expanded suite passed 23 cases and exposed only a test-handle cleanup error, then the corrected color-picker case passed separately. Whole-example analysis and native build passed. Startup AX is complete and clean; independent visual recheck of these refinements is pending.

The reviewer confirmed expanded field space, immediate draft previews across four presets, Chinese color copy and a separately readable invalid-hex message. Follow-up polish retains the Profile name in a one-line compact title, moves modification counts into a quieter adjacent label, makes search and section controls equal-height with text-scaling allowance, and explicitly names the reset icon. A focused layout regression and whole-example analysis passed; the native app was rebuilt for final compact/medium/large-window and global-theme verification. Logs remained free of AXTree/exception markers through the preceding review stage.

Further review passed the compact title and reset behavior, the 3456×2168 large window and 1730×1086 system-tiled window, dark AI workspace and Profile layout. Global appearance was restored to Follow system, and both automation rule fields in the test Profile were cleared and saved. The last alignment refinements center dropdown content using the same density as search and give sidebar labels more space in modified state.

Native diagnostics then identified a later AX failure despite usable visible controls. A fresh process isolated it: opening the Profile editor and entering a temporary tag produced no errors; clicking the sidebar reset immediately produced two AXTree errors. The section-selection semantics excluded its entire subtree, including the nested reset button and tooltip. Selection and reset are now sibling controls with independent semantic nodes; dynamic reset tooltips are contained in a local overlay so removal cannot leave an orphan. All 24 Profile tests and six dropdown tests passed; a focused regression additionally confirms the reset label and separate semantic identity. Whole-example analysis and build passed. The final independent native recheck is pending; earlier visually passed stages do not close this newly isolated failure.

Final native recheck passed the exact former failure path (temporary tag → independently named Reset General → reset disappearance → cancel) with zero AXTree errors. The reviewer also confirmed the full automation section name in modified state, independent reset, and Dark → Follow system round-trip; logs stayed clean. The final narrow-window internal alignment check remains pending because CUA edge drags did not resize the native window. System tiling and Return to Previous Size work, but do not reach the target minimum width. User assistance was requested to manually shrink the development window; no preferences were changed during this attempt. Notification Center receipt remains separately unverified because the system surface timed out.

Subsequent log check found four new AXTree errors for node 403 after the window-menu/edge-drag/Zoom attempts (the earlier reviewer stage had zero). The dynamic-reset reproduction remains fixed, but this additional window/tooltip path is not yet isolated. GUI operations stopped and the development process remains running for diagnosis. Do not interpret the successful earlier checks as a clean final long-session result.

## Expanded audit final result

The status-bar tooltip used the same problematic structure: its portal was inside flattened/excluded status semantics. Moving the tooltip outside that semantic boundary preserves the accessible status label and keeps the overlay attached correctly. Twelve status-bar tests and whole-example analysis passed. Independent native review explicitly showed the tooltip, moved away and invoked system Zoom twice; the resulting log had no AXTree errors.

The user manually shrank the window to 1280×800 physical pixels (640×400 logical), enabling the final narrow-window review. The dropdown now gives its content a definite height with collapsed decoration; a regression compares the actual search/section text centers (within one logical pixel) as well as control height. Independent screenshot review confirmed equal borders and aligned text, and successfully changed sections. Evidence: `/private/tmp/trail-ui-audit-20261028/43-small-alignment-pass.png`. The reviewer then cancelled the editor and restored the large window through system Zoom. Final runtime `/private/tmp/trail-final-alignment-runtime.log` contains no AXTree/error/exception markers; diff whitespace checks pass.

All findings reported in this finite theme/window/export/automation audit are resolved and independently rechecked. Global appearance is Follow system; the test Profile's automation rules are cleared. System notification preferences were never changed. Actual Notification Center receipt remains unverified because system UI access timed out, despite a matched trigger and no API failure. This is local macOS 27.0.1 validation, not complete VoiceOver coverage, other-platform validation, remote CI, or a claim that the entire application has no defects. Changes remain uncommitted and unpushed.

## Split-pane audit follow-up

Expanded split-pane review found that reopening a closed pane always split the active pane, losing its prior nested position. Closed-pane history now retains the prior layout and restores beside the nearest surviving original neighbour, preserving direction and ratio without resetting unrelated current splits. Reopened runtime IDs are remapped in remaining history for consecutive reopen operations. If no original anchor survives, the existing active-pane fallback is explicitly explained in a localized notification. Inactive pane dimming is reduced to a subtle theme token rather than a disabled-looking dark overlay.

All 125 session state/controller tests and whole-example analysis pass, including asymmetric nested restoration, current ratio preservation, missing anchors and consecutive closes/reopens with new runtime IDs. A no-intermediate-frame native-paste regression passes; the reviewer’s single rapid-click/paste incident has not been reproduced, so input routing was not changed. The macOS debug build succeeds; independent visual recheck of this latest build is pending. The delayed user reply about shrinking the window refers to the earlier completed narrow-window pass; the current GUI is restored large for SSH/SFTP review.

## SSH/SFTP follow-up (open)

Independent GUI review connected to a disposable local SSH server and verified SFTP empty directories, parent navigation and download of a Chinese filename under a path containing spaces; the downloaded sample matched the remote SHA256. Toolbar close/root/up/refresh icons lacked native AX names and desktop rows exposed a non-actionable outer button plus an actionable inner button. The toolbar now names its icons explicitly, desktop rows merge their label and tap action, and download success is localized at the presentation boundary. Twenty SFTP operation/race tests and four desktop/mobile layout/semantics tests pass.

Unsaved SSH sessions were being recorded as restart intent with an unresolvable temporary Profile ID. Layout capture now omits unsaved SSH profiles, while saved profiles remain restorable; all nine layout codec tests pass. This prevents new invalid restart intent; it does not reinterpret genuinely missing saved profiles in existing snapshots. Whole-example analysis and macOS debug build pass. These latest SFTP/persistence changes still need independent native review.

OPEN: Sequential editing of SSH fields reproduces incorrect native AX values with pure fake data. After entering a fake password, the password AX node is obscured but the previously focused host node reports the fake password text. Rebinding CUA and requesting a full AX tree does not remove the mismatch. Flutter semantic-node regression confirms independent ordinary field values and masked password values; there are no AXTree errors in the runtime log. Local SDK source shows FlutterTextInputPlugin updates text through its retained native client during editing-state changes; this is a suspect, not yet a proven root cause. No SDK files were changed, no real QA credentials were read, and the fake-data form was cancelled without saving. SDK scope was raised with the user; do not treat this as resolved or claim complete accessibility/security acceptance.

Independent split-pane recheck passed: reopening restores the left vertical pair beside the full-height right pane. Keyboard adjustment changed the upper share to 45%; closing/reopening the lower pane retained 45% internally and 50% externally. The inactive scrim is now light and readable (reviewer screenshot 51). Runtime `/private/tmp/trail-pane-runtime.log` contains no AXTree/ERROR/Exception markers through this stage. The separate native text-field AX value mismatch remains open despite clean logs.

SFTP second GUI round passed the four toolbar names, a single desktop row semantic node, Chinese/space directory creation and local-edit automatic upload verified by remote file contents. Further findings: row blank-space clicks were ignored; double clicks could descend through two directories; upload notifications were English and the listing stayed stale; directory creation discarded input on failure; disconnect feedback/reconnect discovery remains unresolved. The row now handles primary clicks across its opaque hit region and directory activation has a 500 ms guard. Upload success refreshes the currently matching directory and edit/upload toasts are localized. The initial listing uses a known absolute shell cwd, with root fallback when cwd is unavailable. Directory-read failures name the path with localized permission/path/connection checks; native failures currently lack typed reason evidence, so the UI does not falsely assert a permission or existence error. Create disables blank submission, shows independent live error text, and retains the name/dialog after failure for retry. Existing SFTP/race tests pass; explicit blank-area/double-click and create-failure/retry regressions pass; whole-example analysis is clean. Native recheck of this latest round is pending. Root navigation remains explicitly root, not a claimed remote-home lookup.

SFTP second-round independent GUI recheck passed known shell cwd initialization, full-row AX activation, double-click navigation protection, disabled blank creation, retained failed-create input/dialog, localized read/download/edit/upload messages, and automatic size refresh from 100 B to 118 B after editor save. Empty-create native AX disabled-state reporting remains a separate platform-level observation; visual disabling and widget behavior pass. Runtime `/private/tmp/trail-sftp-round2-runtime.log` has no AXTree/ERROR/Exception markers.

Repeated old-layout errors were traced to intentional persistence blocking after any relaunch failure: merely omitting newly created temporary SSH panes could not replace the legacy snapshot. Old snapshots cannot distinguish a deleted saved Profile from an unsaved temporary Profile, so no ID-based deletion heuristic was added. A localized partial-restore message now offers an explicit use-current-layout action, preserves technical details, and clears the restore prompt only after the current layout is actually saved. All 107 controller tests and a focused protection/replacement regression pass. Desktop SSH now exposes the existing persistent disconnected notice/reconnect path above retained output; a desktop widget regression passes. Whole-example analysis passes. Real restart recovery and reconnect verification are pending. Long SSH error presentation, user-lock vs ended-session read-only distinction, and native AX field-value leakage remain open; cross-device sync is unverified because no second device is available.

The explicit use-current-layout action cleared the partial-restore notice. Independent first-restart verification retained the three local tabs and split panes without the old restoration error. Its runtime log contained no AXTree/ERROR/Exception markers. A second restart has been dispatched for stability verification; SSH reconnect remains pending. The details icon now has an explicit semantic label in source, awaiting the next build.

Independent second restart passed: no old-layout error, with three local tabs and the three-pane layout retained. Real local SSH recovery also passed: after stopping and restarting the disposable server, the reconnect action opened a live replacement without re-entering parameters; a command succeeded on the new connection. The old tab retained its marker/history and offered a link to the live replacement. Reviewer screenshots 57/58 record this round.

Residual presentation refinements now label fully disconnected tabs visibly and in accessibility text, show a localized SSH-disconnection summary with separately accessible technical details, and disable user read-only toggling on ended sessions with an explanation. The desktop retained-history/details regression and whole-example analysis pass. Native visual recheck is pending. Native AX field-value leakage remains unresolved and SDK scope is awaiting the user's response; this is not a complete-accessibility signoff.

Native AX isolation: a separate application under `/private/tmp/trail-ax-isolation`, using only standard Flutter TextFields and fake values with the Trail wrapper switched off, reproduced stale cross-field native values. A fake password was exposed by its native AX field and a previous ordinary field retained a character. This rules out Trail-specific form wrapping as a necessary condition; it does not by itself distinguish every engine/AppKit/tool contribution. The reproducible fixture is preserved in `docs/qa/macos_ax_text_input_probe.dart`. Build it in a disposable Flutter macOS project (deployment target 14.0); type fake ordinary text, focus the password field, type fake secret text, and compare visible content to the full native AX tree. Do not use real credentials.

The user authorized SDK scope with the condition of validating an upstream fix first. The official master FlutterTextInputSemanticsObject.mm fetched for comparison is identical to the local 3.44.8 file; no upstream fix has been verified. No shared SDK was modified and no upgrade is claimed to resolve the issue. The independent application has its own bundle/build and does not save or transmit values. Current original SDK commit: 058e0af2c2b57e369d905a03ac9748b0ebf543c6.

The final label/summary review passed long-name disconnected status visibility and direct disconnected summary (screenshot 60), but exposed a distinct initial SSH connection failure: exit 255 before any terminal frame left the main surface permanently loading. The surface selector previously recognized only frame content. It now treats exited sessions as renderable recovery state, and the unavailable-viewport fallback also exposes the SSH reconnect notice. A focused zero-frame → exit 255 → no loading indicator → reconnect into session 2 regression passes. Related analysis, loading/SSH tests and a new build are in progress; native failure-before-connect recheck remains pending.

### 2026-10-29 — SDK scope authorization and upstream verification

User authorized SDK adjustments only after verifying an upstream fix. Shared Flutter SDK remains unchanged. First-connection SSH recovery: static analysis clean, all 4 related widget tests passed, debug macOS build succeeded; rebuilt app handed to independent GUI reviewer, runtime log `/private/tmp/trail-initial-ssh-runtime.log`.

Upstream source review has not established a suitable macOS fix. Commit `dec795bfcc6d2e867af8bde4579d3961a518bf94` / Flutter #192851 changes iOS password-field announcement only; it does not address this macOS field-value case. Flutter #191503 is an open related macOS native accessibility input issue, not evidence that this defect is fixed. Current upstream macOS text bridge still calls `startEditing` on the retained client before updating its string; this is a hypothesis, not a verified root cause.

The isolated fake-data app reproduces anomalous values through CUA without Trail's semantics wrapper, but both observations use the same tool. Independent verification with system Accessibility Inspector was requested before assigning the defect definitively to Flutter or changing SDK. No real credentials are used, no upstream report published, no SDK upgrade performed.

Sources: https://github.com/flutter/flutter/issues/191503 ; https://dart.googlesource.com/external/github.com/flutter/flutter/+/dec795bfcc6d2e867af8bde4579d3961a518bf94

Independent GUI review passed the complete first-SSH-failure recovery path: stopped test container → new temporary SSH exits 255 without persistent loading → restart container → reconnect without re-entering parameters → new session 7 executes `printf FIRST_FAILURE_RETRY_OK`. Reviewer screenshot 62; test container left running. Native AX independent observation remains in progress.

### Native AX independent inspection result

Reviewer opened Apple Accessibility Inspector (`com.apple.AccessibilityInspector`), selected fake-data `trail_ax_probe` process 60833, and tried inspection pointer selection and Audit. Inspector remained at “Select an element to inspect”; no Value/role or audit result was obtained, and no permission prompt appeared. No system permissions were changed. This is inconclusive, not confirmation of an SDK defect. The probe used fake values only and its Trail semantics wrapper was off. GUI handed back to root. Shared SDK remains unchanged; native AX value mismatch remains open pending independent evidence and a verified upstream fix.

Runtime log check: `trail-initial-ssh-runtime.log` (19 lines) has zero AXTree, Exception, ERROR or overflow matches. Previous `trail-label-final-runtime.log` (22 lines) has zero AXTree/Exception/overflow, but two Flutter frame-time clamping ERROR entries; do not describe all prior logs as error-free. Absence of log errors does not validate native AX field values. Reviewer coordinating manual fake-data Inspector cross-check; notification delivery remains awaiting manual verification and cross-device sync remains unverified without a second device.

2026-10-29 scope supersession: user explicitly excluded accessibility from functional support and all subsequent dedicated validation. Stop AX investigation, isolated diagnostics and related SDK candidate verification; do not block acceptance or claim fixed. Shared SDK unchanged. Temporary read-only diagnostic copy `/private/tmp/trail-ax-diagnostics` compiled successfully but was never launched; no further diagnostic work is planned. This supersedes prior pending Inspector/AX action items.

### Notification follow-up after user screenshot

System notification delivery is confirmed by user Notification Center screenshot; the specific `UX_NOTIFY_20261029` custom trigger was not visible, so that case remains unverified. Confirmed source defects: raw output activity notified per pane; 30-second rate limit was bypassed by a 200ms trailing timer; notification pane titles hard-coded English `pane` and runtime IDs. Changed raw activity to one 200ms coalesced delivery per tab, real 30-second trailing throttle, stable tab identifier, localized pane labels without runtime IDs. Explicit OSC notifications retain their separate behavior. Six targeted notification tests pass, including simultaneous split-pane aggregation, cooldown and redacted message bodies; analysis passed before the final cleanup/test addition. Native build and GUI verification pending. Startup prompt causality is still a hypothesis; no arbitrary startup suppression added. SSH failure/interruption wording remains a follow-up.

Custom notification recheck: read-only Dart VM object inspection on the current app found the exact `^UX_NOTIFY_RECHECK_20261029$` pattern in session 8 trigger-match history. Thus split output and regex anchoring matched in this run. No source evaluation succeeded (runtime has no compilation service); evidence came from getObject only. No notification-send failure appeared in the runtime log, but the app does not persist per-request success evidence, so OS delivery of this unique marker remains pending user verification. No restart performed.

Notification native-run scheduling evidence: reviewer scheduled simultaneous output in tab 3 panes/sessions 3, 4, 5, then a second wave 5 seconds later. Read-only VM inspection showed one activity-tab.3 first dispatch timestamp 1793246109219988µs (about 220ms after target output), one trailing timer with 25184ms interval and tick 0, and pending session set {3,4,5}. After expiry, timestamp was 1793246139220921µs: exactly 30.000933 seconds later; both timer and pending set removed. This confirms aggregate/cooldown scheduling in the running app, separate from command-finished notifications. No per-call OS API counter is retained, so exact API call counts and Notification Center presentation are not claimed from this evidence.

SSH notification classification now uses native `ssh_session_established` exit metadata, set after actual transport/authentication/session-channel preparation; code 255 produces connection-failed or connection-interrupted localized titles according to false/true. Missing/non-SSH metadata keeps generic session-ended wording; exit code remains in body. Protocol documented. Native SSH suite 45 tests and notification suite 9 tests pass; example analysis clean. Build and real SSH GUI verification pending. Startup activity source remains unproven; no heuristic suppression introduced.

SFTP follow-up: reviewer screenshot 66 confirmed desktop empty directory had no creation entry. Desktop header now always exposes create-folder when mutations are supported; empty state has a direct Create directory action using the existing validated dialog/retry flow. Twelve SFTP layout/location tests passed, including successful creation from empty state. Screenshot 67 confirmed copying a Chinese/spaced remote path preserves all characters. Command palette now omits groups with zero matching actions and displays localized no-match feedback immediately, restoring results when cleared; 17 focused menu/notification tests passed. Final analysis/build and independent native GUI verification pending.

User Notification Center screenshot `codex-clipboard-1e10ff40-0fb3-4940-a4f1-b890a95ba097.png` independently confirms exact custom marker UX_NOTIFY_RECHECK_20261029 delivered; custom notify end-to-end is now passed. Localized pane labels also visible; command-complete entries are not counted as duplicate activity notifications. Rules-notify title localized. Zero-input restart at 12:06:55.829 produced activity notifications on tabs 2/3/1 at approximately +2.23/+2.33s, establishing startup-origin noise. Fixed empty-baseline handling both on frame arrival and tab activation changes: placeholder frames no longer count as first meaningful content. Thirteen activity/notification/trigger tests passed, including empty-frame→inactive first content (silent)→subsequent real output (notified). Fresh no-input GUI restart still required. SSH session7 event was already released when VM queried, so no retrospective native-phase claim; debug-only ID/boolean/code log added for subsequent live phase validation, with no host/command/credential logging.

Startup-noise fix native recheck passed: process 22319 launched at 2026-10-29 12:13:20.855 local time; no input or tab switching for over 12 seconds. All 6 restored sessions established meaningful frame baselines. Activity notification timestamp map, trailing timers and pending sets were all empty; runtime log had zero Exception/ERROR markers. Before fix, identical no-input startup dispatched 3 tab notifications after about 2.3s. This validates the reproduced startup case without time-based or text-based suppression. Build and analysis succeeded. GUI handed back for independent screenshot/SSH phase follow-up.

Post-startup real-output check: reviewer screenshot 70 captured idle restored homepage, then created session7 (visual tab position5), emitted split `UX_NOTIFY_FINAL_20261029` after delay and switched to another tab. Read-only VM inspection found the exact anchored rule in session7 match history and the sole activity key `activity-tab.7` at 1793247319604305µs. Keys use stable tab/session identity, not visual tab position. Together with empty activity state during no-input restoration, this demonstrates subsequent real background output still schedules activity and rules still match. No notification-send failure logged; system display of this new marker is not inferred from internal dispatch evidence.

### Current audit closeout — 2026-10-29

Reviewer verified the SFTP named delete confirmation includes a permanent-deletion explanation; Cancel leaves the file present. No destructive delete was performed. Temporary notification test rule was cleared and saved. Reported visible UI fixes in this round have passed independent review; startup silence and subsequent real-output notification scheduling have direct runtime evidence.

Latest runtime `/private/tmp/trail-startup-activity-runtime.log` (20 lines) has zero ERROR, Exception, overflow, notification-send-failure or delivery-failure matches. It contains no SSH phase records: the earlier SSH test events predated this diagnostic build, so do not infer their boolean phase from this log. `git diff --check` passed.

System-presentation verification completed by the final user screenshot: (1) “SSH 连接失败” and “SSH 连接中断” both appear; (2) “UX Audit 20261029 · 规则已触发” appears with the exact body UX_NOTIFY_FINAL_20261029. These two previously pending notification checks are passed by screenshot evidence. Earlier UX_NOTIFY_RECHECK_20261029 OS delivery was independently confirmed and must not be conflated with this newer title check. Cross-device sync remains unverified without a second device. Accessibility is excluded by explicit user direction and is not an acceptance blocker. No commit, push, package publication or shared-SDK change performed.

### Final user screenshot verification — 2026-10-29

Independent GUI reviewer directly inspected the user-provided screenshot `/var/folders/k2/8qbf3nrs7t1749d198rw0df40000gn/T/codex-clipboard-1ef1523a-c5ac-4123-a2f9-cafb3799255e.png`. It confirms both SSH notification classifications and the final localized custom-rule notification with exact marker UX_NOTIFY_FINAL_20261029. This closes the two pending system-display checks above; earlier pending entries are historical, superseded by this evidence. Older activity notifications visible in Notification Center are historical entries, not evidence of a recurrence after the startup fix.

All reported issues within the user's current support scope are now closed. Accessibility remains explicitly excluded, not repaired/passed; cross-device sync remains unverified because a second device is unavailable, not passed. No further fix, commit, push, publication, or SDK change was performed for this closeout.

### Final pre-commit regression validation

Full example regression: 3,916 passed / 2 skipped; standalone terminal_core: 1,109 passed / 1 skipped. Native core full cargo test passed. Example analysis and source mirror check passed. Updated obsolete assertions to match visible validation and task/menu structure without relaxing behavioral outcomes. Full regression exposed native launch colors ignoring Profile overrides; session creation now resolves the same Profile appearance as the viewport, with the existing new-session/old-session isolation assertion passing. Twelve intentional visual changes were inspected individually before refreshing macOS 27 baselines; macOS 26 remains subject to its own CI capture.
