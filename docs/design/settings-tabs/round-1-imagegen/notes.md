# Round 1 — ImageGen directions and implementation mapping

ImageGen mode: built-in image generation, image-to-image edits from the five
Round 0 baseline screenshots. The prompts preserved the existing macOS dialog,
navigation, type, neutral palette, Chinese locale, and 1440 × 1024 viewport,
then asked for a production-feasible layout proposal with four numbered blue
callouts.

## General

1. Add the missing page title and task description.
2. Reduce the status notice to a quiet supporting surface.
3. Use the same row and selection treatment for Profile and language choices.
4. Reserve the blue tint for the selected option and use a slim leading accent.

Implemented in `01-general.png`: shared section intro, compact profile notice,
consistent radio panels, and lighter selected-state tint.

## Appearance

1. Use the same page frame as the other tabs.
2. Make the preset filter read as an editable search field.
3. Increase color-swatch legibility while keeping the preset grid compact.
4. Group startup and theme settings as related controls.

Implemented in `02-appearance.png`: shared section intro, explicit search-field
surface, larger swatches, quieter selected preset, and aligned section rhythm.

## Keyboard shortcuts

1. State the page task before the editor controls.
2. Align search, category filter, and restore action on one toolbar.
3. Keep the shortcut value/action column at a stable width.
4. De-emphasize repeated metadata and secondary actions.

Implemented in `03-shortcuts.png`: shared section intro, aligned panel toolbar,
fixed 132 px binding-action column, and a denser scan-oriented list.

## Security and permissions

1. Use a stable list/detail composition.
2. Keep the selected permission and its current policy in focus.
3. Persist the risk explanation instead of inserting it between rows.
4. Keep the remembered-decision manager as a separate list action.

Implemented in `04-security.png`: responsive two-column list/detail layout,
selected row accent, persistent security-impact panel, and separate decision
management row.

## Data service

1. Give the current deployment a prominent status banner.
2. Present service modes as comparable choices.
3. Use a lighter selected state.
4. Keep the restart/apply consequence close to the choice group.

Implemented in `05-data.png`: current-status banner, aligned radio choices,
lighter selection styling, and the apply-on-save note inside the choice panel.
