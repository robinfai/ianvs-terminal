## Flutter AI Skills

This repository uses project-local Agent Skills in `.agents/skills`.

For Flutter UI work, prefer these workflows:
- Use Flutter skills for responsive layout, widget previews, widget tests, routing, serialization, layout fixes, and Flutter architecture.
- Use Dart skills for dependency resolution, static analysis, unit tests, and Dart best practices.
- Use `material-3` and `vgv-material-theming` for Material 3 theme audits, token decisions, component themes, and ColorScheme usage.
- Use `flutter-ai-ui-skill` for Flutter UI/UX ideation, design-system checklists, accessibility checks, and responsive UI review.
- Use platform design skills for Android, iOS, iPadOS, macOS, and web platform expectations when targeting those platforms.
- Use `vgv-accessibility`, `vgv-ui-package`, `vgv-testing`, `vgv-navigation`, and `vgv-internationalization` when those topics are part of the task.
- For UI generation, first define design tokens: ColorScheme, typography, spacing, shape, elevation, motion, and accessibility states.
- For Material 3 UI, prefer `ThemeData(useMaterial3: true)`, `ColorScheme`, component themes, and adaptive layout.
- For responsive UI, prefer `LayoutBuilder`, `MediaQuery.sizeOf`, `Expanded`, `Flexible`, and constraint-based decisions instead of hard-coding device classes.
- Before finalizing generated UI, check dark mode, text scaling, semantic labels, keyboard/scroll behavior, overflow, tap target size, loading/empty/error states, and widget previews.
- Do not hard-code colors directly inside widgets unless there is a documented reason; use theme tokens or ThemeExtension.

## Apple platform compatibility

- macOS and iOS support the latest four publicly released major OS versions by default. Count actual releases, not version-number subtraction; beta and RC releases do not advance the window.
- The current baseline and update procedure are in `docs/APPLE_PLATFORM_COMPATIBILITY.md`. Keep Xcode deployment targets, package requirements, release metadata, and documentation aligned with that baseline.
- Do not add compatibility work for older releases unless explicitly requested. Newer APIs still need availability guards within the supported window.
- A supported version is a requirement, not a claim that it has been tested. Record the actual OS versions used for validation and any gaps.
