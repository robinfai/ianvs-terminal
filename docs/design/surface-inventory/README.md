# Cross-surface ImageGen inventory

`round-1-imagegen/` records ImageGen annotations for representative mobile,
Replay, startup, Defaults, shortcut-recorder, SSH, authentication, terminal,
profile-management, and destructive-confirmation states already present in the
repository's visual audit evidence.

Each annotation was checked against current Flutter code before accepting it.
This matters because screenshots can be scaled and ImageGen cannot infer the
logical control size or distinguish system keyboard UI from application UI.

## Accepted finding

- The long SSH editor now shows both a persistent scrollbar thumb and track,
  with a 5 px rounded indicator.

## Findings rejected after code verification

- Mobile Replay controls are 44 logical pixels.
- iOS terminal accessory keys are 44 × 44 logical pixels inside a 52 px bar.
- Startup primary actions are 48 px high in compact landscape.
- Shared app actions adapt to at least 48 px on touch platforms.
- Desktop 28–36 px compact controls follow the repository's pointer-density
  contract and are not mobile touch targets.
- System keyboard keys, simulator chrome, mouse halos, and invalid source
  screenshots are outside the app UI.
- Dark and light secondary text colors come from theme tokens covered by the
  theme contract tests.

The reproducible Profile, Settings, and core app surfaces received separate
final ImageGen acceptance passes in their respective `final-imagegen/` folders.
