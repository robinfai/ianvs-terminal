# Profile editor Round 1 — ImageGen prompt set

Mode: built-in ImageGen image edit. Each `current/*.png` file was supplied as
the edit target in a separate call.

## Shared prompt

```text
Use case: precise-object-edit
Asset type: shippable macOS Flutter Profile editor UI design target, round 1
Style/medium: high-fidelity practical macOS desktop product UI; restrained
Material 3 tokens compatible with macOS conventions; system-like typography;
compact pointer-oriented controls; subtle semantic surfaces.
Preserve: the full dialog shell, seven-item sidebar and order, selected section,
header, footer actions, light appearance, current values, functionality, and
960 x 720 dialog proportions.
Annotations: add 3–4 small numbered blue callouts at the right edge with short
Chinese labels; leader lines must not cover controls.
Avoid: new features, bottom tab bars, hamburger menus, floating action buttons,
decorative illustration, watermark, concept-art styling, fake controls, and
clipped text.
```

## Per-section directives

- **General:** reduce the oversized card/field feeling; make Name primary;
  present Tags as a useful token-entry pattern with concise nearby help.
- **Startup:** divide the pane into Command and Arguments & Environment;
  expose compact add/reorder/delete actions and keep representative rows clear
  of the footer.
- **Terminal:** use a compact two-column label/control grid for Emulation and
  Scrollback Lines, with concise helper/unit presentation.
- **Appearance:** make the Typography group denser; align fallback-font
  reorder/delete columns; make continuation below the bounded list deliberate.
- **Keys:** convert the heavy nested radio cards into a toggle row and compact
  two-choice Option-drag selector with a non-color selected-state cue.
- **Automation:** separate Triggers and Automatic Profile Switching into two
  aligned groups with help close to fixed-height multiline editors.
- **Advanced:** turn Shell Integration into one intentional compact setting
  row with a trailing switch and an explicit enabled-state cue.

Generated text is directional. Existing localized product copy remains the
source of truth.
