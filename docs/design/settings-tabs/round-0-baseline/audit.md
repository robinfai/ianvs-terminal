# Round 0 — baseline audit

## Audit scope

- Surface: macOS “Defaults & appearance” dialog.
- Flow: inspect and move between General, Appearance, Keyboard shortcuts,
  Security & permissions, and Data service.
- Viewport: 1440 × 1024 logical pixels at 1× density, light theme, Chinese
  locale.
- User goal: understand the current setting, compare available choices, change
  it with confidence, and save without losing context.

## Strengths

- The persistent left navigation makes all five categories discoverable.
- Selected navigation and radio states use one consistent blue accent.
- The footer keeps reset actions separate from Cancel and Save.
- Controls already expose stable keys and semantic roles for keyboard and
  widget-test coverage.

## Highest-impact risks

1. **Inconsistent page framing.** Security has a clear page title and intro,
   while General, Appearance, Shortcuts, and Data begin directly with section
   content. Users must infer the page context from the sidebar.
2. **Too many competing surfaces.** Selected radio rows, notices, cards, nested
   panels, and bordered groups all use similar visual weight. This weakens the
   distinction between “current status”, “choice”, and “supporting detail”.
3. **Low scan efficiency in Shortcuts.** Repeated “Add shortcut” buttons and
   metadata on every dense row create noise before the user can identify the
   action or its assigned keys.
4. **Security detail breaks list continuity.** The blue safety-impact panel is
   injected between permission rows, so changing the selected row shifts the
   visual structure and interrupts comparison.
5. **Data service has weak status hierarchy.** The current deployment is a
   small text line inside a large bordered panel; most of the tab remains empty
   and no concise consequence summary is attached to the selected mode.

## Accessibility risks visible from screenshots

- Supporting copy and protocol metadata are small and low-contrast in several
  dense rows.
- Grey dropdown fills can read as disabled even when they are interactive.
- Shortcut rows contain several adjacent icon actions whose purpose depends on
  icon recognition.
- The baseline screenshots cannot prove focus order, focus visibility, screen
  reader announcements, or text-scaling resilience; those require widget and
  keyboard tests after implementation.

## Round 1 priorities

- Give every tab the same title-and-description frame.
- Reduce nested borders and reserve tinted surfaces for status or consequence.
- Stabilize Security detail outside the permission list.
- Rebalance Shortcut row actions and make assigned state easier to scan.
- Turn Data service into a clear current-status plus mode-selection flow.
