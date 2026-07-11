# OSC protocol completion review — 2026-07-11

## Outcome

- Handoff review baseline: `7635bac099dd6121af1405562ff42db933379b1c`.
- Capability-completion branch baseline: `63035153d41703f78487a994feb8014cd52e6a76`.
- Branch: `codex/osc-capability-completion-20260711`.
- Native/protocol implementation commit: `66016b4`.
- Dart/Flutter product integration commit: `189dee9`.
- Kitty OSC 99 safe-subset commit: `1bb2f3b`.

Phases 0–9 are implemented. Phase 9 adds bounded UAPI OSC 3008 typed context
metadata without visual UI or host authority. No unsupported opcode or host
action is advertised as a product capability.

## Final classification

| Classification | Finding | Resolution |
|---|---|---|
| confirmed defect | OSC 21/22 mutated title-stack state | fixed in `6303515`; both are bounded safe no-ops with no host action |
| confirmed compatibility gap | OSC 8 lost `id=` identity | fixed end to end in `6303515` with additive JSON/protobuf fields |
| confirmed defect | OSC 110/111/112 restored hard-coded colors | fixed in `6303515`; reset restores immutable profile/session baselines |
| confirmed compatibility gap | OSC 4/104 stopped at 16 colors | fixed in `66016b4`; indices 0–255 set/query/reset and render |
| implemented but incomplete | OSC 133 ordering, abort and nested-shell recovery | completed for the Phase 4 contract in `66016b4`/`189dee9` |
| confirmed compatibility gap | OSC 9;9 and OSC 633 absent | adapters completed in `66016b4`/`189dee9` |
| confirmed macOS launch defect | standalone cold launch called an absent `NSApplicationDelegate` superclass selector | fixed in `8a89afd`; native regression and isolated CI ordering added in `d2758a5` |
| documented private extension | OSC 934 identity/version/query were implicit | governed as `ianvs-osc934/1`; bounded query and canonical source implemented |
| confirmed compatibility gap | Kitty OSC 99 rich notification lifecycle absent | safe ID/title/body/Base64/update/close/application/type/query/expiry subset implemented; actions, buttons, sound, icons and commands remain denied |
| confirmed compatibility gap | UAPI OSC 3008 hierarchical context metadata absent | bounded v1.0 hierarchy, lifecycle recovery, snapshot/RIS and typed events implemented; no UI/authority |
| deferred by product decision | unsafe iTerm2 actions, Kitty OSC 66/72 | still deferred; bounded no-op/no product authorization |
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
all test suites are green. The Phase 9 repository-wide verifier passed with
complete example Widget tests enabled; macOS smoke is 4/4 and real PTY
acceptance is 18/18. A standalone rebuild and native RunnerTests 10/10 protect
the macOS cold-launch path. The Phase 9 Ianvs GUI Computer Use gate passed on a
clean cold launch, including the command menu, Profiles, second-tab creation,
real shell `echo GATEOK` input/output and `SHELL ACTIVE` semantics.

The reference-terminal comparison is deliberately not marked passed. Computer
Use rejected both iTerm2 3.6.11 and Ghostty 1.2.3 as protected terminal apps.
No alternate UI automation was used to bypass that safety boundary.
