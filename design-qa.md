# Recording replay direction 2 design QA

## Source of truth and evidence

- Selected product-design reference: `/Users/robinfai/.codex/generated_images/019f802e-929f-71d2-90be-a9b8d9e0dc9f/exec-bea38880-ff77-4203-b6c2-12e853da243b.png` (1448 x 1086).
- Final native implementation capture: `docs/audits/recording-replay-direction-2-final.png` (1225 x 768).
- Normalized full-view comparison, source left and implementation right: `docs/audits/recording-replay-direction-2-comparison.png`.
- Focused Saved Recordings shelf comparison, source left and implementation right: `docs/audits/recording-replay-direction-2-shelf-comparison.png`.

## Audited viewport and state

- macOS dark theme at a 1225 x 768 captured application window.
- Default Workspace is active; the Saved Recordings shelf is open and one real NDJSON recording is selected.
- Replay is at 00:17 / 00:17 with metadata, terminal output, transport controls, speed, search, copy, fit, and close actions visible.
- The generated reference uses a taller 4:3-style canvas while the native product capture is a wider 16:10-style window. Full-view evidence therefore uses contained normalization instead of stretching either image.

## Fidelity review

- Layout and rhythm: the implementation preserves the direction's three-level hierarchy: product chrome, replay theater, and persistent right recording shelf. The metadata strip and elevated bottom playback dock restore the vertical rhythm missing in the first implementation pass.
- Typography: existing application and terminal fonts are retained, with stronger recording titles, restrained metadata, monospace terminal content, and compact macOS desktop labels matching the reference's information hierarchy.
- Color and tokens: all surfaces use the existing dark theme tokens. Blue is reserved for selection and active playback, neutral borders separate chrome layers, green marks the active workspace, and the warning footer keeps low visual priority.
- Assets and image quality: no bespoke raster asset is required by this interface. Material/system icons render natively and remain sharp at the audited viewport.
- Copy and content: `Saved Recordings`, `Import…`, workspace grouping, `Newest`, the sensitive-output warning, recording totals, metadata labels, and playback controls are present. Dynamic recording names, durations, sizes, and terminal output intentionally reflect real local data rather than the generated mock content.
- Responsive behavior: wide windows use a side-by-side 372 px shelf; widths below 960 px use a right-aligned overlay capped at 400 px, preserving terminal readability.

## Focused interaction review

- Top `Recordings` toggles the shelf without changing the live terminal session.
- Search, playable-only filtering, workspace/no-group mode, and newest/oldest/name sorting update the library view.
- Import, rename, reveal in Finder, export, move to Trash, refresh, and independent shelf close are wired.
- Selecting an NDJSON file loads a separate replay backend and displays recording metadata without mutating the live session.
- Play/pause, seek slider, back/forward 10 seconds, 0.25–4x speed, search, copy, fit, and replay close are present and keyboard/accessibility semantics were inspected in the native app.
- The footer reports recording count and bytes and warns that recordings may contain sensitive output.

## Comparison history

1. P2: the first implementation did not expose a recording metadata band above the terminal. Added name, workspace, timestamp, and input-policy metadata; verified in `recording-replay-direction-2-final.png`.
2. P2: the initial playback strip was too compressed to read as the direction's replay dock. Increased vertical padding and promoted the primary play control; verified in the full-view comparison.
3. P2: the first shelf omitted visible grouping, sorting, capacity summary, and a labeled import action. Added all four and verified them in the focused shelf comparison.
4. Final comparison found no remaining P0, P1, or P2 issue. Remaining differences are P3-level integration details: the production window is wider than the generated concept, and the evidence contains one real recording instead of three mock recordings.

## Verification

- `dart analyze`: no issues.
- Recording shelf, lifecycle, repository, and native window-bridge tests: 21 passed.
- Replay scheduler and frame-packet regression tests: 28 passed.
- Native macOS debug build: passed.
- `git diff --check`: passed.

## Final result

passed
