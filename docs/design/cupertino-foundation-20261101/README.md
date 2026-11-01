# Cupertino / Material foundation — implementation handoff

Status: source implementation prepared; **not runtime-validated or deployed**.
Base: `967bd3a0cd2c262a85aae8ac86f7b73e933fa058`.
Branch: `feature/cupertino-material-foundation`.
No Flutter source push, PR, merge, design package publication, or product deployment was performed.

## Design contract

Retain MaterialApp, ThemeData, Form/TextFormField editing and Material's menu machinery. Use the existing Ianvs neutral palette and accessible focus tint. Rounded control geometry is 8 desktop / 10 touch; panels 12; dialogs 16 desktop / 20 touch. Text metrics and font fallbacks remain unchanged. Touch action targets are at least 44 (new AppActionButton/AppSwitch/menu rows use 48); desktop actions use 28/32/36 minimum heights. Height constraints are minimums, allowing desktop text growth.

Primary, secondary, ghost and destructive actions remain distinct. Disabled/loading controls cannot execute. Selected menu items use a leading check, submenu items a chevron, and destructive commands a danger role. Important commands precede related grouped options. Submenu depth should normally stay at one level.

References consulted:
- https://developer.apple.com/design/human-interface-guidelines/menus
- https://api.flutter.dev/flutter/material/MenuAnchor-class.html
- https://api.flutter.dev/flutter/material/SubmenuButton-class.html
- Repository `.agents/skills/platform-ios-design`, `platform-macos-design`, `vgv-material-theming`, `flutter-add-widget-test`.

Phone text scaling follows the existing AGENTS.md fixed-size requirement. PhoneTextScalePolicy and terminal/Composer input behavior were not changed. The isolated preview keeps browser text-scaling behavior; it does not claim to replicate the phone app's text-scale policy.

## Components and real-page adoption

| Component | Change | Adoption |
|---|---|---|
| Theme / navigation / list rows | Shared surface, radius, menu, dialog and state styling | All existing users of buildIanvsTerminalTheme |
| AppActionButton | Effective size variants, loading guard, focus node, reduced-motion progress | Existing button callers throughout app |
| AppDropdownFormField | Shared menu treatment, leading check, field chevron, Form validation/save/autovalidation | Existing SSH, appearance, profile and AI settings dropdowns |
| AppMenuButton / AppMenuEntry | Desktop anchored/secondary-click menus, submenus; touch action sheet with drill-down/back | Imported SSH profile action menu; complex submenu demonstrations in showcase |
| AppTextFormField | Material editing with inline validation and optional password reveal | SSH timeout/keepalive inputs; password version currently showcase only |
| AppSwitch | Cupertino geometry with Ianvs tint and focus/contrast outline | Shared ToggleSettingRow used by profile settings |
| AppCompactRadioTile | Exposes shared enabled/focus contracts | Existing consumers; disabled example in showcase |
| AppSegmentedControl | Neutral track, selected surface/weight, Material keyboard semantics | Showcase only; existing segmented buttons retain shared theme |
| AppDialogScaffold | Rounded shared surface and unified header/footer | Existing dialogs |
| showAppConfirmation | Explicit destructive confirmation, cancel autofocus, scrollable body, reduced motion | Showcase only |
| AppStatus | Inline loading/success/error with live-region label and retry slot | Showcase only |
| AppEmptyState / AppNotifications | Existing behavior retained; updated shared theme | Existing pages plus showcase |

This is a first foundation version, not a claim that every PopupMenuButton, TextFormField, SwitchListTile, confirmation or navigation surface in the application has been migrated. Existing controls receive global styling where they use shared ThemeData. No changes to another ianvs-design repository are required.

## Menu behavior

Desktop uses MenuAnchor, MenuItemButton and SubmenuButton: framework layout handles viewport avoidance, scrolling, sibling/submenu dismissal, pointer transfer, arrow traversal, Tab/Shift-Tab, Enter and Esc. A 120ms submenu hover delay avoids instantaneous fly-outs. The initial available root item receives focus after opening; childFocusNode provides focus restoration. Outside taps are consumed to avoid accidentally activating underlying controls. Secondary click and long press supplement a visible keyboard-accessible trigger.

Touch uses a modal action sheet with a bounded scrollable list. A submenu replaces the list, with explicit Back and Close controls; system Back and Escape return one level before dismissing. Disabled leaf commands cannot execute. Commands run after the sheet closes so navigation/dialog actions do not overlap its route. Selection checkmarks and destructive styling are shared with desktop. Shortcut labels are hints; owners register their actual shortcut actions (the showcase registers Cmd+N).

Menu lifetime, hover crossing, Tab behavior and screen-reader output are inherited from Flutter but **have not been exercised at runtime in this environment**. They remain acceptance items, not verified claims.

## Preview build

`example/lib/component_preview.dart` imports the actual app components. It has no account, SSH, PTY, API or storage initialization. All data is fictional. A theme-only public export at `packages/ianvs_terminal/lib/composer_theme.dart` avoids importing terminal runtime exports into this showcase.

With Flutter **3.44.2** installed:

```sh
export PATH=/path/to/flutter/bin:$PATH
bash tools/preview/build_foundation.sh
```

The script resolves the lockfile, generates localization, runs the dropdown/theme/new interaction tests, and builds:

```sh
cd example
flutter build web --release --target lib/component_preview.dart --no-web-resources-cdn --base-href /
```

Output: `example/build/web`. Publish that complete directory (including CanvasKit, fonts and bootstrap assets) as a private static Site. Do not publish source or an HTML substitute as if it were the Flutter build. Use root hosting; no route rewrites are required for this single-route app. Flutter JS/CanvasKit build avoids requiring cross-origin-isolated Wasm mode. `--no-web-resources-cdn` keeps renderer assets with the build. Serving `.wasm` requires the appropriate content type. No service credentials or server endpoints are needed.

The phone layout toggle constrains the page and changes density. It is a layout exercise, not an iOS device emulator. On an actual phone viewport, sheets follow viewport geometry.

## Validation evidence

Passed locally:
- Tree-sitter Dart syntax parse of every changed/new Dart source and test (no error/missing nodes).
- `git diff --check`.
- `bash -n tools/preview/build_foundation.sh`.
- Flutter 3.44.2 and ianvs_design 0.4.0 source API checks for new menu, switch, form and theme properties.

Prepared, **not executed**:
- `test/ui/cupertino_foundation_test.dart`: loading prevents duplicate execution; password reveal and validation; dropdown reset; submenu keyboard selection/focus; Escape/outside cancel; touch drill-down/back/disabled; edge positioning; safe destructive default; desktop/mobile/theme smoke.
- Existing `test/ui/app_dropdown_form_field_test.dart` and `test/ui/app_theme_contract_test.dart` (radius expectations updated).
- Existing profile/SSH/widget/full application regression tests.

Not performed: Dart analyzer/formatter, Flutter compilation, widget execution, browser QA/screenshots, VoiceOver/TalkBack, iOS/macOS real-device acceptance, pixel/contrast remeasurement, private deployment. Static parsing does not prove Dart type correctness or runtime behavior.

## Exact blocker

The environment initially had no Flutter/Dart SDK. Flutter source was cloned successfully from GitHub and pinned to the project's 3.44.2 tag. Bootstrapping `/workspace/flutter-sdk/bin/flutter --version` tried to download:

`https://storage.googleapis.com/flutter_infra_release/flutter/77e2e94772b6eb43759e34ed1ad7da4674e19cab/dart-sdk-linux-x64.zip`

The network gateway returned `CONNECT tunnel failed, response 403` (exit 56). The release metadata endpoint also returned 403, including an escalated request. The official regional mirror was unavailable through the same gateway. No automatic approval reviewer rejection was reported; this is a network-access failure. pub.dev and GitHub source reads succeeded.

Consequently there is no built Flutter Web package, verified screenshot or preview URL. Sites registration/publication was deliberately not started without a build. Resume by providing the approved SDK/artifact download access or a preinstalled Flutter 3.44.2 SDK, then run validation and publish the actual output. The source must be compiled and reviewed before application release.

## Acceptance checklist after SDK access

- Run analyzer, format touched Dart files, targeted tests, SSH/profile tests and appropriate existing suite.
- Desktop and 375px mobile in light/dark/system; high contrast, reduced motion; desktop 200% text scale.
- Open/reopen/cancel menu; select disabled/selected/destructive entries; left/right edge and short viewport; long-menu scroll.
- Hover from parent to child and across siblings; arrows/Enter/Esc/Tab/Shift-Tab; focus after action/cancel/outside tap.
- Mobile drill-down, Back/Escape, close, outside dismiss and keyboard viewport changes.
- Password selection/IME preservation, validation announcements, focus order, semantic roles and target size.
- Real SSH/profile screens, then real iOS/macOS acceptance; terminal input/PTY regression checks as appropriate.
- Private static Site deployment, save returned URL and audience; verify actual renderer loads before claiming preview ready.
