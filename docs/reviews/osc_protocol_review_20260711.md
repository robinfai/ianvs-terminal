# OSC protocol completion review — 2026-07-11–12

## Outcome

- Handoff review baseline: `7635bac099dd6121af1405562ff42db933379b1c`.
- Capability-completion branch baseline: `63035153d41703f78487a994feb8014cd52e6a76`.
- Branch: `codex/osc-capability-completion-20260711`.
- Native/protocol implementation commit: `66016b4`.
- Dart/Flutter product integration commit: `189dee9`.
- Kitty OSC 99 safe-subset commit: `1bb2f3b`.
- UAPI OSC 3008 typed-context commit: `9972758`.
- Kitty OSC 21 color-control commit: `f7d48bb`.
- Kitty OSC 22 pointer-shape commit: `fbf9a37`.
- Kitty OSC 66 sized-text commit: `5442352`.

Phases 0–12 are implemented. Phase 12 adds bounded Kitty OSC 66 fixed/natural
width, integral/fractional scale and alignment, full multicell grid semantics,
typed frame transport and actual Flutter rendering. No unsupported opcode or
host action is advertised as a product capability.

## Final classification

| Classification | Finding | Resolution |
|---|---|---|
| confirmed defect | OSC 21/22 mutated title-stack state | side effect fixed in `6303515`; neither opcode owns title state |
| confirmed compatibility gap | Kitty OSC 21 color control was absent | bounded ordered palette/core-color set/query/reset implemented in `f7d48bb`; non-rendered special slots remain explicit state only |
| confirmed compatibility gap | Kitty OSC 22 pointer shapes were absent | all 30 canonical shapes, bounded stacks, queries, frame transport and product cursor mapping implemented in `fbf9a37` |
| confirmed compatibility gap | Kitty OSC 66 sized text was absent | bounded multicell parser/state, edit/scroll/reflow semantics, typed frame transport and Flutter rendering implemented in Phase 12 |
| confirmed defect | OSC 23 popped the CSI title stack | removed in `f7d48bb`; OSC 23 is a bounded no-op and CSI 22/23 t remains authoritative |
| confirmed compatibility gap | OSC 8 lost `id=` identity | fixed end to end in `6303515` with additive JSON/protobuf fields |
| confirmed defect | OSC 110/111/112 restored hard-coded colors | fixed in `6303515`; reset restores immutable profile/session baselines |
| confirmed compatibility gap | OSC 4/104 stopped at 16 colors | fixed in `66016b4`; indices 0–255 set/query/reset and render |
| implemented but incomplete | OSC 133 ordering, abort and nested-shell recovery | completed for the Phase 4 contract in `66016b4`/`189dee9` |
| confirmed compatibility gap | OSC 9;9 and OSC 633 absent | adapters completed in `66016b4`/`189dee9` |
| confirmed macOS launch defect | standalone cold launch called an absent `NSApplicationDelegate` superclass selector | fixed in `8a89afd`; native regression and isolated CI ordering added in `d2758a5` |
| documented private extension | OSC 934 identity/version/query were implicit | governed as `ianvs-osc934/1`; bounded query and canonical source implemented |
| confirmed compatibility gap | Kitty OSC 99 rich notification lifecycle absent | safe ID/title/body/Base64/update/close/application/type/query/expiry subset implemented; actions, buttons, sound, icons and commands remain denied |
| confirmed compatibility gap | UAPI OSC 3008 hierarchical context metadata absent | bounded v1.0 hierarchy, lifecycle recovery, snapshot/RIS and typed events implemented; no UI/authority |
| deferred by product decision | unsafe iTerm2 actions and Kitty OSC 72 | still deferred; bounded no-op/no product authorization |
| hypothesis requiring manual evidence | reference-terminal semantic consumption/echo/reply | not proven: Computer Use denies terminal-emulator UI control; see `osc_cross_terminal_probe_20260711.md` |

## Architecture and security result

The production path is now tested across parser, native session, JSON/protobuf,
Dart runtime, session controller, widget/render and real PTY layers. Streaming
OSC admission applies protocol-specific capability and size limits before
unbounded allocation. tmux and screen wrapping is decoded incrementally.

Host actions remain explicit requests. Clipboard read/write, notification,
media and file-transfer policies are independent; VT220 disables modern OSC.
Remote cwd is metadata only. Rejection and overflow diagnostics contain counts,
reason codes and sizes, never OSC bodies, progress labels, recording output,
nonce values or terminal contents.

Additional resource bounds cover synchronized updates, non-sixel DCS, response
buffers, native/vendor event queues, tmux lines and notifications, trigger
history, file-transfer bytes, title stack, recordings and debug output.

## Evidence status

Strict Rust gates, corpus validation, Dart/Flutter analysis, docs, benchmark and
all test suites are green. The Phase 12 repository-wide verifier passed with
complete example Widget tests enabled: corpus 20 cases/24 edge classes, probes
16, vendored 1,622 passed/1 ignored, native lib 74/74 and session 457/457,
example grouped 914/914, Widget 125/125, macOS smoke 4/4 and real PTY 21/21. A
standalone rebuild and native RunnerTests 10/10 protect the macOS launch path.

The Phase 11 Ianvs GUI Computer Use gate passed on a clean cold launch. Real
PTY OSC 22 `wait` set and empty reset sequences were consumed with visible
markers and an interactive prompt; the command menu, Profiles, second-tab
creation/input and `SHELL ACTIVE` semantics also passed. Automated frame and
mouse-tracker tests provide the authoritative system-cursor selection evidence
because Computer Use screenshots omit the host cursor bitmap.

The Phase 12 Computer Use gate passed on a cold-launched standalone Debug app.
A live real-PTY probe visibly rendered red scaled `OSC66-GATE` text plus an
adjacent marker, then zsh prompt EL erased the intersecting multicell block as
specified. Clear/reset, command menu, Local Shell and Strict VT220 Profiles,
second-tab input/output and `SHELL ACTIVE` semantics also passed.

The reference-terminal comparison is deliberately not marked passed. Computer
Use rejected both iTerm2 3.6.11 and Ghostty 1.2.3 as protected terminal apps.
No alternate UI automation was used to bypass that safety boundary.
