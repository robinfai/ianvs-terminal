# OSC protocol review — 2026-07-11

## Outcome

Starting SHA: `7635bac099dd6121af1405562ff42db933379b1c`.

Confirmed defects fixed in this pass:

1. OSC 21/22 no longer have title-stack side effects. Unknown Kitty payloads
   are safely ignored until their semantics are implemented.
2. OSC 8 `id=` is preserved from parser state through native JSON/protobuf and
   Dart models. Equal URIs with different IDs retain different identities.
3. OSC 104 and OSC 110/111/112 restore the configured session/profile baseline
   instead of built-in colors.
4. The strict vendored Rust `clippy --all-targets -- -D warnings` gate is clean.

## Classification

- confirmed defect: OSC 21/22 title mutation; dynamic reset to hard-coded colors
- confirmed compatibility gap: OSC 8 ID loss — fixed
- implemented but incomplete: OSC 4/104 still exposes the 16 configurable ANSI
  entries; 16–255 requires a wider palette model and renderer/wire review
- documented private extension: OSC 934
- deferred by product decision: Kitty OSC 22 pointer host integration, Kitty
  OSC 99, OSC 3008, unsafe iTerm2 file/action protocols
- hypothesis requiring benchmark/manual evidence: cross-terminal query terminator
  parity and 256-entry palette damage cost

## Compatibility and security

The protobuf change appends field 5 to `TerminalHyperlinkRange`; existing tags
are unchanged. JSON omits `protocol_id` when absent. OSC 8 IDs reject control
characters and values above 1024 bytes. No new host action is authorized.

Rollback is a normal revert of this review's changes. Old JSON/protobuf readers
ignore the additive field; no migration is required.
