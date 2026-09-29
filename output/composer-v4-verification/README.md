# Composer V4 implementation verification

Implemented the approved caret-only design in the canonical Flutter component and synchronized the standalone package.

- Clean theme-derived editing surface, identical border before and after focus.
- No input underline or colored strip beside the composer.
- Split-pane focus border is confined to the terminal viewport.
- Rounded command capsule, filled enabled suggestion indicator, and muted dot with “Shell ready” / “Shell 就绪”.
- Existing command handling, suggestion defaults, keyboard routes, IME, and submission lifecycle preserved.

## Validation

Host: macOS 27.0 (26A428).

| Check | Result |
| --- | --- |
| Static analysis of changed component, host, previews, and capture code | No errors |
| Canonical Composer component/controller/theme tests | 76 passed |
| Render matrix, interaction/layout, app theme, and pane callback tests | 146 passed |
| Composer and terminal-layout golden comparisons after updating this host's baselines | 12 passed |
| Real macOS app Composer acceptance with local zsh | 1 passed |

The render matrix includes default and focused states, light/dark themes, high contrast, 320 px width, 2× text, short windows, loading/empty/error states, and history/completion overlays. Screenshot fixtures use the repository's deterministic fonts; the native acceptance test also checks real fixed-width command text.

Selected renders:

- [Focused light](reference-light-empty.png)
- [Focused dark](reference-dark-empty.png)
- [Default light](idle-light-empty.png)
- [Enabled suggestions](light-automaticSuggestions.png)
- [High contrast](contrast-light-empty.png)
- [Narrow window, 2× text, unknown result](narrow-2x-unknown.png)

Only macOS 27 screenshot baselines were updated. Other supported OS versions, their separate baselines, and a full VoiceOver/physical IME matrix were not validated in this change. No release package was installed or published.
