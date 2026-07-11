# OSC protocol changes — 2026-07-11

Start SHA: `7635bac099dd6121af1405562ff42db933379b1c`

End SHA: the commit containing this report

Branch: `codex/osc-protocol-hardening-20260711`

## Changed areas

- vendored OSC dispatcher, title, hyperlink and color handling
- terminal baseline color and hyperlink metadata state
- native frame model, protobuf schema and generated bindings
- Dart frame model, viewport link target and codec tests
- strict-clippy cleanup in pre-existing vendored code
- protocol review and support documentation

## Verification

- `./tools/verify_flutter_terminal.sh` — passed
- vendored `cargo fmt` — passed
- vendored targeted OSC 21/22, OSC 8 and color reset tests — passed
- vendored `cargo clippy --all-targets -- -D warnings` — passed
- `packages/ianvs_terminal/flutter analyze` — passed
- Dart codec/runtime focused suite — passed

- macOS smoke integration — 4 passed
- macOS real PTY acceptance — 16 passed
- computer-use final acceptance — passed: command menu/filter, Profiles
  open/close, new tab, real shell input, `SHELL ACTIVE`, and visual inspection

No existing tests or compatibility paths were removed. Five stale vendored
assertions were corrected to match already-implemented boundary behavior:
graphics leaving a scroll region are dropped, and width-growing graphemes at
the final column wrap rather than overlap the next cell. Rollback: revert the
modified files or the eventual OSC commits.
