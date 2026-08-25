# Round 2 — ImageGen directions and implementation mapping

ImageGen mode: built-in image generation, image-to-image edits from the five
Round 1 implementation screenshots. The prompts kept the established dialog,
tabs, tokens, Chinese locale, settings values, and viewport fixed, and only
annotated the remaining Round 1 QA findings.

## Marker mapping

- **General:** removed the duplicated current-profile summary, aligned Profile
  and language group rhythm, and retained the slim selected-row accent.
- **Appearance:** compacted the preset grid and inter-section spacing so all
  three theme choices are fully visible while preserving 44 px interaction
  targets.
- **Keyboard shortcuts:** promoted filtering, reduced Restore all to a tooltip
  backed icon action, used “Unassigned” as a scannable value, and omitted the
  default-state word from otherwise unchanged row metadata.
- **Security:** expanded the persistent detail panel with current policy, named
  risk level, behavior boundary, and a permission-specific recommendation.
- **Data:** added a running-state indicator and a three-column API/storage/sync
  comparison for every mode, while visually distinguishing selected and active
  modes.

The capture theme was also corrected so Chinese InputDecoration labels use the
same registered screenshot font instead of rendering test-only tofu glyphs.
