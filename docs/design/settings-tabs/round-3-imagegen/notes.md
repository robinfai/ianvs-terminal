# Round 3 — ImageGen directions and implementation mapping

ImageGen mode: built-in image generation, image-to-image edits from the five
Round 2 implementation screenshots. The prompts preserved the dialog shell,
left-tab information architecture, Material 3 tokens, Chinese locale, selected
settings, and 1440 × 1024 viewport. Only the remaining Round 2 findings were
annotated for the final implementation pass.

## Marker mapping

- **General:** shortened the persistent Profile action to “编辑 Profile” while
  retaining a tooltip with the full intent, and aligned the two setting groups.
- **Appearance:** completed the vertical-fit pass so all theme choices remain
  visible with consistent card padding and interaction targets.
- **Keyboard shortcuts:** added a quiet “操作 / 快捷键” header, reserved stable
  action slots, and aligned assigned and unassigned values into one column.
- **Security:** added an explicit “推荐设置” badge when the current policy is
  recommended, and paired every risk level with a non-color icon cue.
- **Data:** preserved the API/storage/sync comparison at wide widths and the
  concise consequence description at compact widths; selected and running
  states remain distinguishable without relying on color alone.

The marker annotations are design-review artifacts, not UI assets. The Flutter
implementation uses real localized text, theme tokens, and existing iconography.
