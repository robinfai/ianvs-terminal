# Configuration UI refresh

This pass uses ImageGen as a visual design and review tool for both Settings
and Profile configuration surfaces. The generated targets are directional;
the Flutter implementation preserves the product's existing information
architecture, localization, behavior, and accessibility semantics.

## Design direction

The shared direction is **precision utility**: cool-neutral tonal surfaces,
crisp controls, restrained blue emphasis, and quieter containment. The design
keeps desktop information density while making spacing feel deliberate rather
than sparse.

| Token | Configuration value | Intent |
| --- | --- | --- |
| Spacing | 4 / 6 / 8 / 12 / 16 / 24 | Compact 4 px base rhythm |
| Radius | 6 / 8 / 10 / 14 | Crisp controls, softer dialog shell |
| Controls | 28 / 34 / 40 | Dense desktop actions with 40 px form fields |
| Canvas | Existing app canvas | Preserve app/window continuity |
| Sidebar | Accent-tinted low tonal surface | Separate navigation without a heavy border |
| Selection | Accent blended at 10% light / 20% dark | Clear but quiet active state |
| Borders | On-surface blended at 13–24% light | Reduce box-within-box contrast |
| Elevation | One restrained dialog shadow | Tonal depth remains primary |

## ImageGen review legend

1. Header rhythm and dialog hierarchy
2. Quiet sidebar/search treatment
3. Active navigation state
4. Page intro hierarchy
5. Information/section surface
6. Group and input containment
7. Row/action density
8. Fixed footer and action priority

Round 1 artifacts:

- `round-1-imagegen-targets/`: clean visual targets for representative pages.
- `round-1-imagegen-annotations/`: numbered implementation callouts over the
  current goldens.
- `adaptive/`: dark-mode and compact 1.25× text-scale verification captures.
- `round-2-imagegen-review/`: the first complete 12-page implementation audit.
- `final-imagegen/`: final verdicts for all 12 desktop pages plus four adaptive
  states. Every final image is marked `PASS — no actionable visual issues`.

## ImageGen execution

- Mode: built-in ImageGen (`image_gen`), using each Flutter golden as the edit
  reference image.
- Design-target prompt: preserve the existing Chinese content, dialog footprint,
  information architecture, and behavior; restyle only toward a clean premium
  Material 3 “precision utility” interface with quiet tonal surfaces, 8 px
  alignment rhythm, restrained blue emphasis, crisp 1 px boundaries, and no
  invented features.
- Annotation prompt: preserve the current screenshot and add numbered review
  pins for header rhythm, sidebar/search, active state, page hierarchy, section
  surfaces, input/group containment, action density, and fixed footer priority.
- Final-verdict prompt: check hierarchy, tonal separation, alignment, spacing,
  selection clarity, contrast, density, overflow, responsive behavior, dark
  mode, text scaling, and footer fit; emit either actionable amber callouts or
  the exact green `PASS — no actionable visual issues` verdict.

## Final verification

- ImageGen: 16/16 final reviews passed with no actionable visual issues (five
  Settings pages, seven Profile pages, and four adaptive states).
- Golden tests: all 16 desktop, dark-mode, compact, and 1.25× text-scale
  captures pass without updating their baselines.
- Flutter regressions: 225 relevant UI, configuration, profile, shell, and
  widget tests pass.
- Static analysis: `dart analyze` reports no issues.
- Responsive footer: action groups now use their measured widths to choose a
  single row or a right-aligned overflow row, including iPhone landscape and
  keyboard transitions.
