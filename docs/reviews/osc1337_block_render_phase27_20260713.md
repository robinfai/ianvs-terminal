# Phase 27 review — OSC 1337 block rendering — 2026-07-13

## Result

Phase 27 closes the `OSC 1337 Block ... attr=end;render=1` gap with a
reversible, cross-platform text-document presentation. Targeted parser,
native real-PTY, JSON/protobuf, Dart, runtime, API and widget checks are green.
The repository-wide verifier and cold-launch Computer Use acceptance are also
green.

## Baseline and scope

- Start SHA: `f96cf73eacf6fb2b6df86e76ca64cd47ec6cccb0`.
- Branch: `codex/osc1337-block-render-phase27-20260713`.
- Supported trigger: completed primary-screen blocks whose end marker contains
  `render=1`.
- Supported presentations: explicit Markdown, JSON, plain-text and generic-code
  type hints, plus bounded visible-text classification when the type is absent.
- Supported lifecycle: render, fold/unfold visibility, close-to-restore and
  preservation of user fold/close choices through transcript-backed resize
  replay.
- No file, clipboard, URL, focus, process, profile, network or other host
  authority is added.

## Official comparison and compatibility boundary

- Compared iTerm2 commit `2c6c17162f5fc979e0933714803f1a4a7f1fffa3`,
  including `VT100Terminal.m`, the screen/session delegates,
  `PTYTextView.swift`, `PortholeFactory.swift`,
  `TextViewPortholeRenderer.swift`, `MarkdownPortholeRenderer.swift` and
  `JSONPortholeRenderer.swift`.
- iTerm2 extracts the terminal text, chooses a renderer from `type` or content,
  installs a selectable/searchable Porthole, saves the original lines and
  restores them when the document closes.
- Ianvs preserves the same protocol lifecycle and type-aware presentation but
  keeps terminal-cell row geometry instead of installing a variable-height
  AppKit view. This maintains deterministic scrollback, selection, graphics and
  frame coordinates on Flutter's macOS, mobile and web targets.
- Frame transport adds optional protobuf block tag `9` (`rendered`). The text is
  not duplicated into metadata; existing bounded rows remain authoritative.
  Older consumers ignore the field and older producers decode as `false`.

## Architecture and review findings

- The vendored terminal retains the protocol render bit and exposes a bounded,
  idempotent presentation-state mutation. Closing only clears that bit; it does
  not rewrite or discard terminal cells.
- Native frame construction includes rendered single-line blocks even though
  they are not foldable. Runtime requests clear cached rows and force a complete
  repaint. Transcript replay reapplies user fold and render choices after it
  reconstructs source ranges at the new width.
- Dart JSON and protobuf models normalize the optional state identically. The
  runtime controller and xterm facade provide exact set/refresh operations and
  surface backend errors through the existing typed error stream.
- The Flutter painter selects the innermost rendered block for overlapping
  ranges, derives all document colors from terminal theme tokens, and replaces
  only paint-time ANSI styling. Search highlights, selection, copy coordinates,
  row text and replay data are unchanged.
- Syntax runs convert Dart UTF-16 match offsets through the terminal's grapheme
  and cell-width map before painting, avoiding CJK, emoji and combining-mark
  column drift.
- The product overlay exposes a bounded type label, optional fold control and
  one actionable `Close terminal text document` semantics node. Narrow layouts
  retain the close action first and drop nonessential label/fold chrome without
  overflow.
- No package dependency was added. Markdown/JSON/code presentation is bounded
  row-local styling and does not evaluate content, load resources or execute
  embedded markup.
- Review added an explicit real-PTY assertion that an open rendered document
  stays rendered through a 80→79→80 transcript-replay resize before the close
  state is tested separately.

## Targeted evidence

- Shared corpus: 33 cases / 49 required edge classes, with explicit iTerm2 text
  document rendering intent mirrored byte-for-byte between Rust and Dart.
- Vendor: render/restore idempotence, unknown ID, snapshot restoration and
  original-grid preservation.
- Native: rendered single-line exposure, real-PTY render state, user close,
  post-close resize replay, runtime request handling and JSON/protobuf parity.
- Dart: JSON/protobuf decoding, explicit and heuristic type classification,
  Markdown/JSON/code token runs, Unicode cell mapping, runtime request/refresh,
  backend error propagation and xterm API request shape.
- Widget/product: theme-derived JSON rows, syntax styles, search highlight
  continuity, type semantics, exactly one close action, callback routing and a
  32-pixel narrow-layout overflow check.
- Complete package regression: 473 tests passed with one existing skip; example
  static analysis reports no issues.

## Final release gates

The complete final-tree command passed with exit code 0:

```bash
VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 \
  tools/verify_flutter_terminal.sh
```

It covered 33 corpus cases / 49 edge classes, 27 semantic intents, vendored
Rust 1,678 passed / 1 ignored plus 11 passed / 1 ignored doc tests, native core
93/93, native real-PTY/session 484/484, VTT 3/3, terminal package 473 passed /
1 existing skip, example grouped tests 930/930, complete example Widget tests
128/128, macOS smoke 4/4, application real PTY 31/31, Debug app rebuild and
RunnerTests 14/14. Formatting, strict Clippy, generated protobuf, mirrored
corpus, docs contracts, analysis and benchmark smoke are part of the same gate.

Cold-launch `@电脑` acceptance used the verifier-built standalone
`Ianvs Terminal Dev.app` and a real zsh child. A byte-exact `application/json`
block visibly rendered a theme-derived panel and syntax runs, retained
`CUA-OSC1337-RENDER-PASS`, and exposed exactly one labeled close action plus
the document type and fold action. Activating that exact close AX node removed
the projection and controls while retaining all original JSON rows.

A second rendered block folded to `{ …3 lines… }`, hid its document controls,
and restored the JSON panel and controls on AX `Unfold terminal block`. In a
fresh transcript-backed tab, macOS window zoom changed 93×21 → 203×43 → 93×21;
the rendered state, type, styling and actions survived both replays.
`CUA-RENDER-INTERACTIVE-PASS` then executed in the same pane with
`SHELL ACTIVE`.

Two initial probe commands were rendered as harmless plain text because the
Computer Use text injector discarded shell metacharacters. A temporary hex
fixture avoided that tool boundary. The first resize attempt also followed a
system `clear` that emitted CSI `3J`, deliberately invalidating the replay
baseline under Phase 26's documented conservative fallback; the clean-tab
repeat proved the claimed transcript-backed resize path, and the new native
assertion permanently covers it.

## Security, compatibility and rollback

The presentation reads only text already admitted to bounded viewport rows.
Type labels remain bounded by the parser and are truncated again for the UI.
Content is never parsed into executable widgets, links, file references or host
requests. VT220, alternate-screen, ingress and retained-block limits remain
unchanged. Reverting Phase 27 returns `render=1` to retained no-op metadata;
Phase 26 folding remains valid and optional protobuf block tag `9` becomes
unused without migration.
