# Profile Editor ImageGen redesign audit

This audit records the screenshot-to-redesign-to-implementation workflow for
all seven Profile Editor forms.

## Generation mode

- Tool: built-in ImageGen (`image_gen.imagegen`)
- Mode: edit the live form screenshot; use the approved General redesign as
  the locked visual reference for the remaining forms
- Output type: shippable Flutter desktop UI mockup

## Shared prompt

> Treat the current form screenshot as the edit target and the approved
> General form as the locked style reference. Preserve the 960x720 desktop
> dialog shell, header, seven-item left navigation, footer, every existing
> field, action, label, and behavior. Redesign as a production-quality macOS
> dark settings UI with deep graphite three-level surfaces, crisp subtle
> borders, rounded 10-12px cards, cobalt-blue accents, an 8-point spacing
> rhythm, clear hierarchy, and accessible contrast. Do not add features or
> change product meaning. Avoid glass, neon, heavy gradients, mobile controls,
> logos, watermarks, or decorative text.

## Per-form evidence

| Form | Live input sent to ImageGen | ImageGen redesign | Implemented runtime |
| --- | --- | --- | --- |
| General | `source-01-general-fixed.png` | `design-01-general.png` | `after-v4-01-general.png` |
| Startup | `source-02-startup-fixed.png` | `design-02-startup.png` | `after-v4-02-startup.png` |
| Terminal | `source-03-terminal-fixed.png` | `design-03-terminal.png` | `after-v4-03-terminal.png` |
| Appearance | `source-04-appearance-{top,mid,bottom}-fixed.png` | `design-04-appearance.png` | `after-v4-04-appearance.png` |
| Keys | `source-05-keys-fixed.png` | `design-05-keys.png` | `after-05-keys.png` |
| Automation | `source-06-automation-fixed.png` | `design-06-automation.png` | `after-06-automation.png` |
| Advanced | `source-07-advanced-fixed.png` | `design-07-advanced.png` | `after-07-advanced.png` |

## Section-specific direction

- General: make the identity fields one contained information card.
- Startup: separate Command from Arguments and environment while keeping the
  list actions compact.
- Terminal: use a focused Emulation card and constrain its fields for easier
  scanning.
- Appearance: compact the fallback-font rows, elevate theme presets into a
  selectable card grid, and keep color groups and Cursor visually distinct.
- Keys: separate Normal selection and Block selection into full-width radio
  cards.
- Automation: replace cramped inline inputs with two large multiline rule
  editors, external labels, helper copy, and a divider.
- Advanced: present shell integration as a contained settings row with a clear
  trailing switch.

## Implementation mapping

- `example/lib/features/profiles/profile_editor.dart`: dialog rhythm, rail
  selection treatment, form cards, section-specific layouts, rule editors,
  compact fallback rows, and option-drag cards.
- `example/lib/features/profiles/widgets/settings_section.dart`: optional
  contained section surface.
- `example/lib/features/profiles/widgets/toggle_setting_row.dart`: aligned
  edge-to-edge row rhythm while retaining compact control sizing.
- `example/lib/features/profiles/widgets/color_setting_row.dart`: consistent
  graphite input surface.

## General / Startup / Terminal / Appearance refinement pass

- Replaced floating labels with persistent external labels and helper copy.
- Raised primary input and dropdown controls to a tested 64px minimum height.
- Added a terminal-dark input surface, stronger semantic outline, and explicit
  focus/error borders without changing the global control theme.
- Moved Startup arguments, environment variables, and Appearance fallback
  fonts into bordered desktop list surfaces with row dividers and compact
  keyboard-accessible actions.
- Kept dense color rows compact so Appearance remains practical when scrolling.
- Updated the canonical `after-01` through `after-04` runtime screenshots after
  the refinement pass.

## Visual comparison pass (v4)

The fourth pass uses the v3 runtime screenshots as the comparison baseline and
labels every structural change directly in the visual comparison.

| # | Visual rule | General | Startup | Terminal | Appearance |
| --- | --- | --- | --- | --- | --- |
| 1 | Keep labels on their own line with visible separation from controls. | Yes | Yes | Yes | Yes |
| 2 | Use one high-contrast input surface with shared focus and error borders. | Yes | Yes | Yes | Yes |
| 3 | Merge sortable content into a continuous table with a fixed action rail. | — | Yes | — | Yes |
| 4 | Separate card title, divider, and content into three hierarchy levels. | Yes | Yes | Yes | Yes |
| 5 | Stack paired numeric fields below 520px instead of squeezing them. | — | — | — | Yes |

Runtime evidence for this pass is stored as `after-v4-01-general.png` through
`after-v4-04-appearance.png`. Full-window captures use the matching
`-window.jpeg` filenames.

## Verification

- `flutter analyze` in `example`: no issues.
- `flutter test test/profiles`: 56 tests passed, including all 20 Profile
  Editor widget tests and the 64px primary-field regression assertion.
- Runtime accessibility tree checked for all seven navigation destinations and
  their controls.
- Runtime screenshots captured from the rebuilt macOS application, including
  top, middle, and bottom Appearance states.
