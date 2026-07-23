# Replay Player Design QA

## Target and implementation

- Design reference: `/Users/luobinghui/.codex/generated_images/019f8f89-028e-7c81-804c-40d62b3d1dd4/call_H8pYqc6GqRxB0cUzmISDc3f6.png`
- Implementation capture: `design-qa-assets/replay-command-review.png`
- Full comparison: `design-qa-assets/replay-command-review-comparison.png`
- Timeline comparison: `design-qa-assets/replay-command-review-timeline-comparison.png`
- Viewport: 1622 × 970 logical pixels at DPR 1
- State: light theme, saved replay, local command segments plus an SSH parent segment with a nested remote command

The implementation capture is produced by a deterministic Flutter widget test. Its
Ahem test font intentionally renders text as blocks, so typography was also checked
in the running macOS application. The comparison focuses on the replay player's
layout, density, hierarchy, controls, and semantic timeline.

## Fidelity review

| Surface | Result | Evidence |
| --- | --- | --- |
| Layout and spacing | Pass | The terminal remains the dominant surface. The semantic timeline, legend, session metadata, transport controls, and utility actions keep the same vertical order and grouping as the reference. Both instant and saved replay use the same shared dock. |
| Typography | Pass | Production uses the app's themed UI and terminal typefaces with the same label hierarchy. The implementation screenshot's block glyphs are a deterministic-test artifact rather than production styling. |
| Colors and tokens | Pass | Light-theme surfaces, borders, primary blue, directory blue, activity gray, and remote amber are derived from `ColorScheme` or shared replay tokens. |
| Shape and surfaces | Pass | Command cards, active outlines, track markers, dividers, and compact toolbar controls match the reference's restrained rounded treatment without adding decorative surfaces. |
| Icons | Pass | Material icons are consistently sized and aligned for playback, search, fit, copy, close, directory, and remote states. No handcrafted SVG or placeholder icon substitutes are used. |
| Image quality | N/A | The target contains no raster product imagery. The implementation uses Flutter text, dividers, and library icons at device resolution. |
| Copy and content | Pass | Command labels, path metadata, remote host context, playback time, speed, frame count, and privacy disclosure are coherent in the standalone replay state. |
| Responsiveness | Pass | The dock switches to a compact control layout below 960 logical pixels; timeline labels truncate instead of colliding, and controls retain usable targets. |
| Accessibility | Pass | Buttons have tooltips/semantic labels, keyboard Escape closes replay, contrast follows the active theme, and controls remain keyboard reachable. |

## Interaction and semantic-state review

- Clicking a command card seeks to that segment.
- Scrubbing, play/pause, previous/next step, speed selection, search, fit, copy,
  and close are covered by widget tests.
- Local shell-hook events produce named command cards and directory changes.
- Prompt-only metadata produces anonymous command ranges without inventing labels.
- With no hook or prompt semantics, the same timeline shows `Activity` fallback
  ranges rather than guessing command boundaries.
- `ssh` or `mosh` is shown as a remote parent segment. Remote commands are nested
  only when remote OSC semantic events exist; otherwise the parent contains one
  `Remote activity` range.
- Overlapping native-hook and OSC events are deduplicated.
- Input privacy is explicit: keystrokes can be redacted while command metadata is
  still included.

## Comparison passes

### Iteration 1

- P1 · Layout: the first implementation compressed commands into thin markers,
  which weakened the command-review hierarchy visible in the target.
- P2 · Content and behavior: the first pass lacked the target's command legend,
  larger command cards, visible remote nesting, and card-to-seek interaction.
- Fix: enlarged the semantic lane, added major/minor/directory/remote states,
  nested SSH children, added the legend, made cards seekable, and moved both
  replay modes onto the same timeline and control dock.

### Iteration 2

- Full-view comparison: `design-qa-assets/replay-command-review-comparison.png`
- Focused timeline comparison:
  `design-qa-assets/replay-command-review-timeline-comparison.png`
- P0: none.
- P1: none.
- P2: none.
- P3: the implementation dock is about 55 pixels more compact vertically than the
  mock. This preserves the intended hierarchy and gives the terminal slightly more
  working space, so no further change is required.
- Intentional content difference: the QA fixture uses fewer local commands and an
  SSH example to verify the remote-session behavior requested after the mock was
  selected.

### Iteration 3 — Actual runtime evidence

- User-supplied runtime capture:
  `design-qa-assets/actual-replay-audit/01-actual-replay.png`
- Source/runtime comparison:
  `design-qa-assets/actual-replay-audit/02-source-actual-comparison.png`
- P1 · Duplicate semantic sources produced overlapping cards for `top` and the
  SSH session.
- P1 · Remote title, status, and time collided inside the SSH card.
- P2 · Anonymous labels exposed raw event numbering and tiny semantic noise.
- Fix: reconcile hook and OSC events into one open command per lane, enrich
  anonymous segments with later named metadata, promote anonymous wrappers into
  SSH parents, discard sub-100 ms anonymous cards, renumber visible anonymous
  commands, and split remote status from the SSH title.
- Fixed deterministic capture:
  `design-qa-assets/actual-replay-audit/03-fixed-replay.png`
- Before/after comparison:
  `design-qa-assets/actual-replay-audit/04-before-after-comparison.png`
- Regression fixture covers overlapping anonymous/named starts, duplicate
  finishes, and anonymous-to-SSH promotion. No remaining P0, P1, or P2 issue was
  found in the corrected reproduction.

final result: passed
