# Phase 16 Review — xterm Special and Dynamic Colors

## Scope

- Start SHA: `f4a9e9b2c3857ca1811cf4e80178bff1e7cfa03c`
- Implementation SHA: `e2f90be`
- Supported commands: OSC 5/6/105/106, OSC 13–19/113–119, OSC 4 aliases
  256–260, and sequential OSC 10–19 parameters.
- Product effect: special attribute colors, `colorAttrMode`, dynamic selection
  colors, default/cursor colors and retained pointer/Tek resources.

## Review findings and fixes

1. The first implementation treated OSC 106 as a reset. xterm defines OSC 106
   as an exact OSC 6 alias, including mode 5 (`colorAttrMode`); parser, tests,
   corpus and docs were corrected.
2. OSC 4 indices 256–260 were initially rejected. xterm aliases them to its
   five special colors; set/query/reset coverage now enforces that behavior.
3. Attribute colors originally lacked xterm's default-color provenance rule.
   Explicit ANSI/RGB colors are now preserved unless mode 5 is enabled.
4. The default `veryBoldColors=0` behavior was missing. A chosen special color
   now replaces its visual attribute, with deterministic reverse, blink, bold,
   underline and italic priority.
5. RIS could retain runtime OSC selection mutations. Baseline restoration now
   covers special resources, modes, dynamic resources and selection activation.
6. Selection color state reached the core but was absent from the frame/render
   contract. Optional JSON/protobuf fields, delta inheritance and clipped
   selected-glyph repaint make background and foreground visible end to end.
7. Application-level real PTY coverage was missing after the first green run.
   A 25th acceptance test now validates the special-color style and both
   selection fields through the complete product stack.
8. The first Computer Use inspection attached to a Phase 15 resident process.
   The old instance was isolated, the current build was launched, and the gate
   was repeated against the correct binary.

## Final verification

The final repository command passed with exit code 0:

```bash
VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 \
  ./tools/verify_flutter_terminal.sh
```

Recorded results:

- corpus validator: 24 cases and 33 required edge classes;
- semantic probes: 20 intents;
- vendored terminal: 1,641 passed and 1 ignored;
- native core: 76/76; native session: 467/467; vttest: 3/3;
- Dart/Flutter analysis and package suites: passed;
- example grouped tests: 925/925; Widget tests: 125/125;
- macOS smoke: 4/4; application real PTY: 25/25;
- native macOS RunnerTests: 12/12;
- `git diff --check`: passed.

One pre-existing readline resize test timed out once during an intermediate full
run, passed immediately in isolation, and passed in both subsequent full runs.
The final run contains no failures.

## Computer Use acceptance

The standalone Debug application built by the final verifier was exercised in a
real local shell. OSC 5/6 visibly rendered `PHASE16 BOLD SPECIAL COLOR` in the
configured magenta special color. A mouse selection over
`PHASE16 SELECT THIS TEXT` visibly used the OSC 17 red background and OSC 19
black foreground. The terminal remained interactive and displayed the explicit
`PHASE16 VISUAL PASS` marker.

## Compatibility and rollback

Frame fields are additive and optional; absent selection colors retain profile
behavior. VT220 denial remains intact, malformed inputs are bounded, and no new
host, file or process authority is introduced. Reverting `e2f90be` restores the
Phase 15 behavior.
