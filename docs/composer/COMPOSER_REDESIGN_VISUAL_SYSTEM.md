# Composer visual system audit and implementation brief

Date: 2026-09-29. Baseline: `5f164bea` on `composer`.

This document records source-based findings and a proposed system. It does not claim that the proposals have been implemented or visually verified. The user requested a comprehensive Composer redesign, including icons, purposes, state expression and interaction. Image generation is for direction exploration; runtime text and icons remain semantic Flutter/vector content. No native Warp access was used.

## Evidence and existing strengths

- `packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart` owns the surface, toolbar, environment chips, ownership indicator, focus border, keyboard routing and overlay anchoring. Its `ComposerTheme` derives seven colors from the host `ColorScheme` but keeps typography and several shape/spacing values in the widget.
- `composer_suggestions.dart` owns history, completion rows, split details, empty results and the keyboard legend. It correctly uses a lazy list, scales row height, keeps list focus in the editor and separates deliberate keyboard reveal from pointer scrolling. Preserve the scrolling fix from `5f164bea`.
- `composer_editor.dart` measures ghost text using actual editor metrics. Predictions stay outside the editable document, clipboard and selection. Preserve this architecture.
- `example/lib/ui/foundation/app_theme.dart` adapts the shared `ianvs_design` theme into terminal surfaces. It already supplies semantic colors, typography, controls, density and light/dark themes. The package must remain independently usable; it must not import app-private tokens.
- The host already registers `example/assets/fonts/TrailLightIcons.ttf` as `MaterialIcons`. Its README documents Google Material Symbols Outlined, weight 300, optical size 20, fill 0, grade 0, source hashes and upstream licenses. Flutter icon constant suffixes therefore do not imply mixed strokes in this host. All Composer glyph names examined are absent from the fallback list. The package itself has Flutter only; `cupertino_icons` is an example dependency, not a package dependency.
- `example/lib/ui/previews/composer_preview.dart` currently covers light, dark, 2× compact, history and inline suggestions. Current tests exercise keyboard acceptance and scrolling. Source presence proves coverage intent, not a new visual pass.

## Findings to resolve

| Current detail | User cost | Design resolution |
| --- | --- | --- |
| `Terminal`/`命令` appears as an accented chip but performs no action. | Looks like a mode selector. | Make it a quiet mode label, or replace it with a real, clearly labelled terminal-input action. Do not invent unavailable modes. |
| Folder icon toggles automatic candidates. | It reads as “open folder”, obscuring what the switch enables. | Reserve folder for cwd/directory results. Use a dedicated completion glyph plus label and explicit on/off state. |
| Shell ownership is a 14 px check/edit icon; completion loading replaces it. | Shell readiness and completion work become indistinguishable. | Persistent icon + short text for ownership; local loading belongs in the candidates surface or completion control. |
| Sending, running, suspended and draft reuse an edit-note glyph. | Different execution/input states look equivalent. | Use separate action/status semantics and copy; never imply successful execution with the readiness check. |
| Copy and undo disappear below a fixed width. | Narrow windows lose discoverability/access to functions. | Put secondary edit actions in a labelled More menu with keyboard shortcuts; never remove their entry points. |
| Run is another small filled icon in a row of small icons. | The primary action has weak hierarchy. | Reserve the strong filled treatment for Run. Give the action a text label when space allows and a complete tooltip/semantic name always. |
| Ready border and active fills use multiple ColorScheme families. | Pairing foreground and container colors becomes inconsistent. | Use paired tokens for each surface, selection and primary action. |
| History and completion use unrelated sizes, inline constants and border radii. | Refinements drift between surfaces. | Shared theme/geometry and vector glyph modules. |
| Footer legend truncates at large text or narrow widths. | Instructions disappear precisely when users need accessible layout. | Structured keyboard hints that wrap or reduce to the highest-priority actions; all actions remain in tooltips/menus. |
| Empty history uses “No matching commands” for both an empty collection and a filter with no match. | User cannot tell whether history exists. | Separate “No commands yet” from “No matches”, with filter-specific recovery. |
| Overlay height uses a fraction of the entire screen rather than actual space above its anchor. | A short window or tall editor can place content outside the visible area. | Derive maximum overlay height from the anchor-to-safe-area gap and viewport insets; retain a bounded scroll area. |
| Foreground, metadata and focus borders are ColorScheme-derived, but `MediaQuery.highContrast` is not consumed. | Higher contrast is not assured for custom chrome. | Resolve contrast-aware semantic tokens centrally, then verify actual rendered color pairs. |

## Proposed visual hierarchy

The Composer should read as a compact command workbench with three aligned regions:

1. **Context and ownership.** Target identity followed by a shortened cwd breadcrumb. Keep the full path in its tooltip/semantics and use actual cwd as the source of truth. Show a short textual ownership badge at the trailing edge. Context metadata is visually quiet, while unknown outcome or unavailable input receives explicit text.
2. **Command document.** A generous, clean editor with a visible caret, monospaced command text and a subdued ghost continuation. Preserve native selection and IME. Editor height follows content up to its configured limit; the document scrolls beyond that limit.
3. **Action rail.** History and Completion are discoverable controls. Less frequent editing actions share a More menu. A short contextual key legend is flexible. The stable trailing primary control is labelled **Accept** while a candidate is active and **Run** when it will execute, so its visual promise agrees with Enter. Context menus must not require the command draft to be cleared.

The popover is part of the same family: a quiet labelled header, results, optional details and a small footer. It aligns with the relevant token/caret where possible and stays inside its usable viewport. Pointer hover and keyboard selection must remain distinguishable from keyboard focus. Selecting a result only edits the draft; executing remains an explicit second action.

## Theme and geometry contract

Introduce `composer_theme.dart` as a package-local semantic adapter or `ThemeExtension`. Resolve defaults from the host `ThemeData`/`ColorScheme`, permit a host extension override, and keep compatibility with independent consumers using only Material. Components read these named roles rather than raw palette values.

| Role | Default source / behavior |
| --- | --- |
| `surface` / `onSurface` | `surfaceContainerLow` / `onSurface` |
| `popover` / `onPopover` | `surfaceContainer` / `onSurface` |
| `contextSurface` / `onContext` | `surfaceContainerHighest` / `onSurfaceVariant`; no transparent text |
| `muted` | `onSurfaceVariant`; do not lower text opacity to simulate hierarchy |
| `border` | `outlineVariant` normally, `outline` for high contrast |
| `focus` | `primary`, opaque; stronger width in high contrast |
| `selected` / `onSelected` | `secondaryContainer` / `onSecondaryContainer` |
| `primaryAction` / `onPrimaryAction` | `primary` / `onPrimary` |
| `error` / `onErrorContainer` | Paired `errorContainer` / `onErrorContainer` for actionable execution errors |
| `hover` | A token computed centrally from foreground/surface; keep it distinct from selected |
| `disabled` | A central role suitable for inactive controls, never reused for useful explanatory text |
| `shadow` | Host `shadow`; subtle at normal contrast, rely on clear border in high contrast |

Suggested geometry (logical pixels) is 4/8/12/16/24 spacing, panel radius 12, popover 10, control 6, row 6. Use 12 panel inset with 8–12 between regions. Desktop icon hit area 32 with a 16–18 glyph; touch density may grow to 44 without growing the glyph proportionally. Keep a 1 px ordinary border and 1.5–2 px focus outline. These are centrally defined defaults, not literals copied into components.

Use host `textTheme` as the base and centralize Composer variants:

| Style | Intended default | Notes |
| --- | --- | --- |
| `command` | 14 px, line height 1.5, monospace | Preserve platform fallback for CJK; do not rasterize strings. |
| `result` | 13 px, line height 1.4, monospace | Match highlighting changes weight, not layout or color family. |
| `context` | 12 px, line height 1.35, system UI | Full content via tooltip and semantics. |
| `action` | 12 px, medium, system UI | Text buttons expand with scaling. |
| `metadata` | 11–12 px, line height 1.4, system UI | Hide optional type metadata before the command label. |
| `status` | 12 px, line height 1.4, system UI | Can wrap; warning/error content must not ellipsize away. |

Never cap `TextScaler` globally. Read the scaled metrics when deciding whether actions fit, sizing result rows and choosing inline versus split detail. Reduce Motion removes decorative state transitions; ordinary pointer and keyboard response remains immediate.

## Coherent icon family

Reuse the project's existing Material Symbols Outlined font at 16–18 logical pixels inside a 32 px desktop target. Its source asset already establishes the stroke family; no hand-drawn imitation, raster glyph sheet or new dependency is needed. A package-local `ComposerIcons` mapping should assign purpose to existing Flutter `IconData`, while `IconTheme`/semantic tokens choose size and color. This keeps canonical and standalone packages usable with normal Material hosts; Trail supplies its lighter font as it does today. Supply control semantics separately and exclude decorative glyph semantics to avoid double announcements.

| Purpose | Glyph meaning | State expression |
| --- | --- | --- |
| Local target | Terminal window with prompt | Quiet context glyph. Remote target can use a server/connection glyph when available. |
| Cwd / directory result | Open folder | Use only for location/content, never for automatic completion. |
| History | Clock with counterclockwise return | Active surface/open state; tooltip says “Command history”. |
| Completion | Prompt plus short suggestion lines | Visible toggle state and explicit “Automatic suggestions” meaning. No AI sparkle unless an AI feature exists. |
| More | Horizontal ellipsis | Opens edit/options menu; stable position in narrow layouts. |
| Copy | Two sheets | Transient check plus text/semantic confirmation after successful copy. |
| Undo / redo | Curved backward/forward arrows | Disabled when unavailable, shortcuts shown in menu. |
| Terminal input | Terminal prompt plus return/focus direction | Text clarifies “Use terminal input”; avoid a generic return key as the only clue. |
| Accept / Run | Return arrow for adopt, play or forward arrow for execute | Stable primary position; label and action both change with candidate versus execution state. |
| Ready | Small check in circle | Label “Ready”, never “Succeeded”. |
| Sending | Progress arc | Label “Sending”; prevent duplicate submit. |
| Running | Activity indicator | Label “Running”; route interactive input to terminal. |
| Suspended/unavailable | Terminal/cursor indicator | Text explains who owns input; no disabled-looking editor if drafts remain editable. |
| Unknown outcome | Warning diamond/triangle | Persistent explanation and Recover draft where valid. |
| File / option / alias / script | Sheet / flag or switch / bent link / play-in-document | Same stroke metrics; text kind remains available to assistive technology. |

Imagegen concepts may establish silhouette, spacing and emphasis. Product icons use the existing licensed native/vector icon family; generated labels and glyph pixels are not shipped as UI. Do not hand-author replacement assets that imitate the source icons.

## Responsive and accessibility behavior

- **Wide:** target + cwd + state on one line; complete action rail; completion details may sit beside the list only when both columns retain useful minimum widths after text scaling.
- **Medium:** retain History, Completion, More and Run; move the keyboard legend to a second line before removing labels. Cwd truncates in the middle or preserves the last directory segment; target keeps its readable identity.
- **Narrow / 2× text:** use a wrapped or two-row context region, then editor, then actions. Menu actions remain available. Optional result type and inline detail can move into a selected-detail region; command names have first priority. At 320 px, all controls must remain operable without horizontal clipping.
- **Short viewport:** compute popup space from actual anchor geometry. Header/footer should not consume all available height. Keep at least one usable result row or a recoverable empty/loading state; scroll within the surface.
- **Light and dark:** derive colors from the active host scheme. Avoid absolute white/black surfaces and photographic backgrounds under command text.
- **High contrast:** opaque focus outline, stronger boundary, selected-row leading marker/check as well as fill; retain paired foreground. Text contrast target 4.5:1; boundaries and meaningful icons 3:1. Verify against actual host themes rather than assuming `ColorScheme` guarantees every custom pairing.
- **Keyboard:** preserve completion Tab semantics and Esc hierarchy. Provide a discoverable focus escape from the editor (existing Shift+Tab route plus an explicit toolbar shortcut if adopted). Focus indication must be visible on toolbar/menu controls. Do not regress IME, undo, multiline navigation, terminal handoff or acceptance-without-execution.
- **Screen reader:** names describe actions, not glyphs. Toggle has `toggled` state; result has selected state, kind, ordinal and label. Ownership/feedback uses a polite live region when meaningful, avoiding a stream of completion-loading announcements. Hidden ghost text stays outside editable semantics.
- **Touchpad:** hover must not force scroll reveal. Only opening or explicit keyboard navigation requests reveal. Rebuilds and native shell updates must not replace the scroll controller or cancel inertia.

## Minimal reusable file boundaries

1. `composer_theme.dart`: semantic colors, typography, geometry, adaptive metrics and reduced-motion resolution; independent from app-private theme classes.
2. `composer_icons.dart`: semantic names mapping to existing outline `IconData`, with no strings or controller state.
3. `terminal_composer_view.dart`: layout composition, focus/key routing, overlay position and user actions; extract only cohesive small components when complexity warrants it.
4. `composer_suggestions.dart`: result/history presentation using the same tokens/icons and existing navigation revision contract.
5. `composer_editor.dart`: preserve editing/ghost painter internals; consume the new typography roles without duplicating them.
6. `example/lib/features/terminal_composer/composer_pane.dart`: host lifecycle and terminal handoff/collapsed ownership presentation; no duplicated theme palette.
7. Preview fixtures and tests: include meaningful content/state examples rather than theme-only screenshots.

Canonical changes must be generated into `packages/ianvs_terminal_core` with `dart run tools/sync_terminal_core.dart`, never independently edited in the mirror.

## Verification matrix for the final implementation

Capture/inspect real rendered previews for both themes at 820 px, 480 px and 320–360 px, plus 2× text, increased contrast and a short viewport. Cover empty ready, entered command, inline ghost, loading candidates, completion with descriptions, long filtered history, empty history, no matches, draft/unavailable, submitting, unknown outcome and recover draft. Include long CJK paths, spaces and a multi-line draft.

Behavioral checks must prove: copy contains only the draft, completion/history acceptance does not execute, enabled toggles are discoverable and reversible, menu actions survive compact layout, tooltip/semantics match each state, selection/focus remains stable, pointer and trackpad scrolling remain uninterrupted, keyboard reveal works, and execution remains bound to the ready shell lease. Re-run the existing macOS real application acceptance test after the UI integration.

A passing test alone is not proof of every visual state. Record actual screenshot review, contrast evidence and the exact OS used for application verification separately from the implementation proposal.
