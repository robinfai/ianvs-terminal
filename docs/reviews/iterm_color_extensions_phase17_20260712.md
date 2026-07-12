# Phase 17 acceptance — iTerm2 color extensions

## Result

- **Start SHA:** `5a9e57289a3cbd7764ead3bbe7c502c678bc7a34`.
- **Implementation SHA:** `37d24239d35a2162cf895543840e2d827cc5c87c`.
- **Branch:** `codex/iterm-color-extensions-20260712`.
- **Status:** accepted. No unresolved issue remains in the defined session-local
  color scope.

Phase 17 implements iTerm2 OSC 4 default-color queries and the safe visual
subset of OSC 1337 `SetColors`. Foreground/background, bold, underline, link,
selection, cursor, tab, and ANSI 0–15 colors cross parser, terminal state,
snapshot/RIS, native frame, JSON/protobuf, Dart state, renderer, shell chrome,
and real PTY boundaries. RGB, sRGB, and Display-P3 input are supported;
`tab=default` restores profile behavior. `preset` and profile mutation remain
unauthorized.

## Review and repair iterations

The first automated pass exposed two evidence defects: the underline pixel
assertion required antialias-aware comparison, and the native shared-corpus
executor lacked the new case dispatch. Both were corrected and re-run green.

The first Computer Use pass then exposed a product defect that unit coverage
had masked: a tab-only frame color change did not rebuild the shell chrome
unless unrelated title/session state also changed. The shell now attaches
per-session viewport listeners that rebuild only when `tabColor` changes,
removes them on session close/dispose, and has a regression test whose frames
deliberately omit `window_title`.

## Final automated gate

The complete command passed after the Computer Use repair:

```bash
VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 \
  tools/verify_flutter_terminal.sh
```

Final counts:

- OSC corpus: 25 cases and 36 required edge classes;
- semantic probes: 21 intents;
- vendored Rust: 1,646 passed, 1 ignored; doc tests 11 passed, 1 ignored;
- native core: 77/77; shared corpus 1/1; session 469/469; vttest 3/3;
- package Flutter suite: 454 passed, 1 skipped;
- example grouped tests: 925/925;
- complete example Widget tests: 126/126;
- macOS smoke: 4/4;
- macOS real PTY: 26/26;
- native RunnerTests: 12/12.

Strict Rust formatting and Clippy, Dart/Flutter analysis, docs contracts,
benchmark smoke, generated protobuf parity, and mirrored-corpus validation are
included in the same successful gate.

## Computer Use gate

A freshly rebuilt, cold-launched standalone Debug app visibly rendered:

- bold magenta text while preserving bold weight;
- green underline decoration and cyan hyperlink decoration;
- the remapped ANSI red entry;
- red selection background with black selected glyphs;
- yellow cursor fill with blue cursor glyph;
- the orange session tab-color indicator after the listener repair.

`SHELL ACTIVE` remained present and `P17-INTERACTIVE-PASS` executed after the
probe. The live check therefore closed both visual fidelity and continued-input
acceptance. iTerm2 reference-terminal comparison remains pending under the
existing protected-terminal Computer Use boundary and is not claimed here.

## Compatibility and rollback

All frame additions are optional: top-level protobuf tags 27–29, style-run tag
11, and sized-text tag 22. Missing fields retain prior profile behavior.
Reverting `37d2423` returns SetColors to unsupported behavior and leaves those
additive tags unused.
