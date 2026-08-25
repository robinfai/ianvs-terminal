# Profile editor Round 2 — ImageGen prompt set

Mode: built-in ImageGen image edit. Each Round 1 annotated target was supplied
as the edit target in a separate call. The shared instruction was to change
only the named refinement and preserve every Round 1 invariant.

## Shared prompt

```text
Use case: precise-object-edit
Asset type: shippable macOS Flutter Profile editor UI design target, round 2
Preserve: the Round 1 dialog shell, header, footer, seven-item sidebar and order,
selected state, values, existing functionality, dimensions, light appearance,
and compact macOS visual language.
Annotations: replace prior annotations with exactly three small numbered blue
callouts at the right edge; keep leader lines off controls.
Avoid: new functionality, fake controls, invented values, decorative art,
watermarks, concept-art styling, and clipped controls or text.
```

## Targeted refinements

- **General:** remove the nested double border around Tags; use one clean empty
  token-entry field and unify the Name/Tags vertical rhythm.
- **Startup:** use the same compact row editor for arguments and environment
  variables; fix the trailing action column; localize add actions as
  `添加参数` and `添加变量`.
- **Terminal:** align labels, controls, separators, units, and helper baselines
  to one 8-point grid; keep `行` attached to the numeric control.
- **Appearance:** remove the invented `还有更多` row; use a real bounded list
  viewport with a subtle scrollbar and stable action columns.
- **Keys:** localize the choices as `普通选择` and `块选择`; preserve the
  selected block mode; align the two controls to one settings-row grid and keep
  a non-color selection cue.
- **Automation:** remove fake resize handles; use fixed-height Flutter
  multiline fields with monospaced rule text, clear focus borders, and nearby
  helper copy.
- **Advanced:** reduce redundant heading weight; keep `集成` quiet,
  `Shell 集成` primary, and `已启用` concise and aligned with the row.

These images are implementation directions. In particular, any generated text
drift in an annotation or helper line must not replace the repository's
localized strings.
