# Ianvs Terminal Next Direct Acceptance Queue

Date: 2026-06-28

Scope: remaining work from the seven re-sorted buckets that can be started without new target hardware, cross-platform hosts, quiet-host performance conditions, or a product-scope decision. Each item must close with automated evidence and may add a local desktop or Computer Use smoke only as supporting evidence.

## Recommended Next Batch

| Priority | Bucket | Item | Why it can proceed now | Acceptance evidence |
| --- | --- | --- | --- | --- |
| 1 | 7. UX optimization follow-ups | Profile editor search inside settings | Profile editor section navigation already exists; search can be added as a local UI behavior without platform dependencies. | `cd example && flutter test test/profiles`; focused widget tests for searching section labels/fields and jumping to the matching section. |
| 2 | 7. UX optimization follow-ups | Profile editor dirty-state summary plus per-section reset/revert | The editor already tracks saved/unsaved form state and section anchors; this is deterministic widget/model behavior. | `cd example && flutter test test/profiles`; tests for dirty section labels, reset one section, revert all, and save behavior. |
| 3 | 7. UX optimization follow-ups | Dynamic profile import preview and conflict handling | Dynamic Profiles already imports iTerm-style JSON. A preview/diff step can be tested with fixture JSON before persistence. | `cd example && flutter test test/profiles`; `cd example && flutter test test/shell/shell_screen_phase3_test.dart --plain-name "profile"`. |
| 4 | 7. UX optimization follow-ups | Ianvs profile/theme export | Profile/theme data is local structured data, so export can use deterministic repository/exporter tests before any native save dialog. | `cd example && flutter test test/profiles`; exporter/repository unit tests; shell entry-point widget test if surfaced in UI. |
| 5 | 7. UX optimization follow-ups | Optional tab color support | The tab strip, profile colors, compact overflow, and active tab rendering are already widget-testable. | `cd example && flutter test test/widget_test.dart --plain-name "tab"` and a focused tab-color widget/model test. |
| 6 | 7. UX optimization follow-ups / 4. Roadmap local workspace | Shell integration health visible in status bar or pane header | Shell integration snapshots and prompt-mark utilities already feed the shell UI; exposing health is local state rendering. | `cd example && flutter test test/widget_test.dart --plain-name "shell integration"`; focused tests for available, degraded, and unavailable states. |
| 7 | 7. UX optimization follow-ups | Setup-guided empty states for annotations and captured output | Both surfaces already exist. Empty-state copy/actions can be accepted by widget tests without runtime changes. | `cd example && flutter test test/widget_test.dart --plain-name "annotations"` and `--plain-name "captured output"`. |
| 8 | 7. UX optimization follow-ups | Instant replay timeline and retention policy display | Instant Replay already opens and is backed by viewport frames; timeline/retention state can be added locally. | `cd example && flutter test test/widget_test.dart --plain-name "instant replay"`; optional desktop smoke for visual timeline density. |
| 9 | 2. Environment / 7. UX follow-ups | Hotkey-window failure UI mapping | The failure-state model and bridge call tests already exist; mapping bridge/permission failures into visible UI is app-level work. | `cd example && flutter test test/widget_test.dart --plain-name "hotkey"`; optional desktop smoke for the visible failure message. Native global hotkey ownership remains out of scope. |
| 10 | 2. Environment / 7. UX follow-ups | Notification permission diagnostics UI | Notification intent and authorization failure feedback already have test coverage; a diagnostics surface can stay app-level. | `cd example && flutter test test/widget_test.dart --plain-name "notification"`; no claim about native banner delivery. |
| 11 | 7. UX optimization follow-ups | Keyboard-only focus traversal for tabs, panes, command menu, search, profile editor, and Toolbelt | Flutter widget tests can drive focus traversal. A desktop smoke can supplement it when host UI automation is available. | Focus traversal widget tests plus targeted `test/widget_test.dart`, `test/profiles`, and optional Computer Use smoke. |
| 12 | 2. Environment | Focused Flutter semantics regression for command menu/search/profile/toolbelt | This can reduce accessibility regression risk, but it does not prove the host `AXTree` log issue. | Widget semantics tests using `SemanticsTester`; keep host AXTree proof open. |

## Not Direct In This Host

| Bucket | Item | Reason |
| --- | --- | --- |
| 1 / 4 | Quiet-host or cross-machine performance baseline | Requires a quiet machine and comparable host metadata. |
| 2 | Foreground ownership / Flutter `open returned 1` cleanup | Current Codex host cannot prove frontmost ownership; standard desktop host proof is required. |
| 2 | Full accessibility-tree stability / `AXTree` bridge log elimination | Needs host-level reproduction and accessibility tooling beyond widget semantics. |
| 3 / 6 | Fractional-display text sharpness | Geometry snapping is automated, but real 125%/150% display sharpness needs matching display scale. |
| 3 / 6 | Windows Ctrl-letter/CapsLock and Android physical-keyboard duplication | Requires target OS/hardware. |
| 3 / 6 | Kitty keyboard protocol implementation | Still a product-scope decision; default xterm behavior is already protected. |
| 4 | M3 row-range annotation renderer implementation | The design is ready, but roadmap sequencing says to start M3 after evidence-lane closure; treat this as next-phase, not immediate cleanup. |
| 5 | Branch-only product line | Removed from `main`; no current-branch work. |

## Suggested Execution Order

Start with profile editor search and dirty-state/reset because they are self-contained, high-user-value, and have clear widget acceptance. Then handle import/export workflow, then the shell/status and diagnostics surfaces. Leave visual polish such as tab color and broader focus/semantics sweeps until after the profile workflow is no longer accumulating structural debt.
