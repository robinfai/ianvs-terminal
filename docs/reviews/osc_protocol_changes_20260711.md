# OSC protocol changes and phase evidence — 2026-07-11

Branch: `codex/osc-capability-completion-20260711`

## Commit map

| Commit | Scope |
|---|---|
| `6303515` | Phases 0–2: preflight, OSC 21/22 side effects, OSC 8 identity, dynamic baseline reset |
| `66016b4` | Phases 3–7 native/vendor engine, security bounds, shared corpus and semantic probe |
| `189dee9` | Phases 3–7 Dart/Flutter product integration, render/UI tests and verification gate |
| documentation commit containing this file | final matrix, protocol specification and evidence record |

The second pass uses two logical commits (native protocol engine and product
integration) because the streaming security boundary, semantic event identity
and wire schema are shared invariants across Phases 3–7. Each phase remains
independently identified below with a scoped rollback path.

## Phase 0–2 report

- **Start SHA:** `7635bac099dd6121af1405562ff42db933379b1c`.
- **End SHA:** `63035153d41703f78487a994feb8014cd52e6a76`.
- **Modified files:** preflight/review docs; vendored OSC title/color/hyperlink
  parser and state; native frame/protobuf; Dart frame/link/render models/tests.
- **Confirmed issues:** OSC 21/22 title side effects; OSC 8 ID loss; hard-coded
  reset colors; strict vendored Clippy failures.
- **Fixes:** safe bounded 21/22 consume; nullable OSC 8 protocol ID through all
  wire/product layers; immutable custom color baseline; strict lint cleanup.
- **Unfixed at phase end:** 256-color palette, robust OSC 133, OSC 9;9/633,
  protocol-level policy and OSC 934 governance; completed in later phases.
- **Tests/results:** repository verifier passed; vendored fmt/Clippy/targeted
  tests passed; Dart analysis/codec/runtime passed; macOS smoke 4/4, real PTY
  16/16 and prior Ianvs GUI smoke passed.
- **Not run/reason:** no protected reference-terminal semantic probe was
  captured in this phase.
- **Compatibility:** additive protobuf field 5 and optional JSON field; legacy
  payloads without ID remain valid.
- **Security:** no new host authority; OSC 8 ID is sanitized and bounded.
- **Rollback:** revert `6303515`.

## Phase 3 report — palette and dynamic resets

- **Start SHA:** `63035153d41703f78487a994feb8014cd52e6a76`.
- **End SHAs:** `66016b4` (engine), `189dee9` (product integration).
- **Modified files:** terminal palette/color/snapshot/render state; native frame
  model/protobuf; Dart frame decoder and renderer; boundary/parity/widget tests.
- **Confirmed issues:** OSC 4/104 could not address 16–255; palette/reset state
  was not fully preserved by snapshot/resize reconstruction.
- **Fixes:** full 0–255 set/query/reset, multi-index reset, immutable palette and
  fg/bg/cursor baselines, resize/snapshot preservation and visible render state.
- **Unfixed:** xterm special resource colors 5/105 and 13–19/113–119 remain
  explicitly unsupported.
- **Tests/results:** parser boundaries 0/15/16/255, invalid/multi-pair/query;
  native JSON/protobuf parity; Dart codec and index-196 widget render passed.
- **Not run/reason:** reference-terminal palette visual comparison is blocked by
  protected terminal-app UI access.
- **Compatibility:** protobuf fields are additive; old JSON may omit palette
  metadata; baseline behavior is corrected rather than reinterpreted.
- **Security:** appearance-only capability; bounded indices and replies.
- **Rollback:** revert the Phase 3 hunks in `66016b4` and `189dee9`, or revert
  both commits together.

## Phase 4 report — OSC 133 state machine

- **Start SHA:** `63035153d41703f78487a994feb8014cd52e6a76`.
- **End SHAs:** `66016b4`, `189dee9`.
- **Modified files:** vendored shell integration/zones/snapshots; native typed
  session events; Dart session/controller/prompt navigation and tests.
- **Confirmed issues:** abort, duplicate and out-of-order input could contaminate
  later command state; nested-shell and zone invalidation evidence was missing.
- **Fixes:** explicit transition recovery, abort semantics, alt-screen gate,
  nested-shell ownership, bounded prompt/zone state, scrollback/reflow/reset
  invalidation and stable global prompt coordinates.
- **Unfixed:** iTerm2 Blocks/UpdateBlock UI remains deferred.
- **Tests/results:** normal/abort/out-of-order/duplicate/alt-screen/nested shell,
  resize/reflow/scrollback clear, native event, controller and widget tests pass.
- **Not run/reason:** iTerm2 visual comparison is blocked by Computer Use policy.
- **Compatibility:** OSC 133 A–D valid ordering is preserved; malformed ordering
  now fails closed without synthesizing completion.
- **Security:** typed metadata only, bounded histories, no execution authority.
- **Rollback:** revert Phase 4 hunks in `66016b4`/`189dee9` together.

## Phase 5 report — OSC 9;9 and OSC 633 adapters

- **Start SHA:** `63035153d41703f78487a994feb8014cd52e6a76`.
- **End SHAs:** `66016b4`, `189dee9`.
- **Modified files:** OSC shell dispatcher/state; native typed bridge; Dart
  event router/controller and shell UI tests.
- **Confirmed issues:** both adapters were absent.
- **Fixes:** absolute-path-only OSC 9;9; OSC 633 A–D/E/P mapping into shared
  semantics; escaping, optional strict nonce and redacted source identity.
- **Unfixed:** VS Code-specific decorations outside shared command semantics are
  not claimed.
- **Tests/results:** BEL/ST, chunks, escaping, malformed values, nonce mismatch,
  coexistence with OSC 133, resize replay, VT220 and Dart source tests pass.
- **Not run/reason:** VS Code integrated-terminal manual probe unavailable on
  this host.
- **Compatibility:** adapter events are additive and preserve existing OSC 133.
- **Security:** remote cwd cannot become process cwd; nonce is correlation only
  and is never logged or treated as authorization.
- **Rollback:** revert Phase 5 hunks in `66016b4`/`189dee9` together.

## Phase 6 report — streaming policy and resource bounds

- **Start SHA:** `63035153d41703f78487a994feb8014cd52e6a76`.
- **End SHAs:** `66016b4`, `189dee9`.
- **Modified files:** streaming OSC gate, terminal/snapshot/recording/event/file
  transfer/tmux/DCS paths; native queue/diagnostics; shared corpus and verifier.
- **Confirmed issues:** generic buffering and coarse insecure-sequence switch did
  not prove per-capability allocation limits or payload-free diagnostics.
- **Fixes:** incremental per-protocol admission/discard, capability policy,
  tmux/screen unwrap, 15-case mirrored corpus, queue/buffer/history/file/recording
  limits, diagnostic counters and debug redaction.
- **Unfixed:** deferred host-action protocols remain denied rather than partially
  exposed.
- **Tests/results:** corpus 15/15, semantic-probe self-test 10/10, oversized and
  split framing, policy allow/deny, VT220, snapshot restore, tmux/screen and
  diagnostic redaction tests pass. Vendored tests: 1,573 passed, 1 ignored;
  native session tests: 447 passed.
- **Not run/reason:** nightly resource benchmark is optional and was not enabled;
  CI smoke benchmark is part of the final verifier.
- **Compatibility:** JSON path retained; protobuf tags appended only; older
  backends without capabilities retain safe defaults.
- **Security:** host action defaults remain deny/ask; diagnostics never include
  raw terminal payloads.
- **Rollback:** revert Phase 6 hunks in `66016b4`, `189dee9` and the verifier
  update together.

## Phase 7 report — Ianvs OSC 934 governance

- **Start SHA:** `63035153d41703f78487a994feb8014cd52e6a76`.
- **End SHAs:** `66016b4`, `189dee9`.
- **Modified files:** progress parser/state/event bridge, native diagnostics,
  Dart source routing/controller, normative protocol and matrix docs.
- **Confirmed issues:** implicit grammar/version, no query, provisional source
  string and insufficient protocol-local bounds.
- **Fixes:** `ianvs-osc934/1`, canonical static query reply, 8 KiB payload,
  128-byte ID, 1,024-byte label, 64 active IDs and `source=ianvs_osc934`.
- **Unfixed:** no interoperability is claimed for terminals that do not implement
  this private extension.
- **Tests/results:** query/no-loop, 65th-ID rejection with retained-ID update,
  canonical native/Dart source, streaming overflow and redacted Debug pass.
- **Not run/reason:** external-terminal consume/echo/reply is unproven because
  Computer Use blocks iTerm2/Ghostty UI control.
- **Compatibility:** legacy OSC 934 set/remove/remove-all remains accepted;
  consumers may temporarily accept the provisional source during migration.
- **Security:** presentation-only; query is static and leaks no session state.
- **Rollback:** revert Phase 7 hunks in `66016b4`/`189dee9` and the protocol doc.

## Deferred phases

Phase 8 Kitty OSC 99 and Phase 9 OSC 3008 remain product-decision deferrals.
Kitty OSC 66/72, unsafe iTerm2 upload/download/actions, arbitrary URL/profile/
command actions, notification buttons/sounds/icons and shell-provided execution
are also deferred. Unknown/deferred sequences remain bounded and cannot gain
host authority.

## Final verification record

Before the final repository gate, focused evidence is green:

- vendored fmt, strict Clippy and tests: 1,573 passed, 1 ignored; doc tests 11
  passed, 1 ignored;
- native fmt/Clippy; lib 71/71, corpus 1/1, session 447/447, vttest 3/3;
- corpus validator 15/15 and semantic probe self-test 10/10;
- Dart/Flutter analysis and protocol/runtime/controller/widget focused suites;
- macOS smoke 4/4, real PTY 16/16 and native RunnerTests 10/10.

Final committed-tree command:

```bash
VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 \
  ./tools/verify_flutter_terminal.sh
```

Result: passed with exit code 0. This includes vendored/core format, strict
Clippy and tests; PTY/Dart/Flutter analysis and tests; docs contract; CI smoke
benchmark; 910 example grouped tests; complete example Widget tests 125/125;
macOS smoke 4/4; and macOS real PTY acceptance 16/16. The optional nightly
resource benchmark was not enabled because it is not a release gate. The
verifier also rebuilds the standalone macOS app after Flutter integration tests
and runs native RunnerTests 10/10.

Computer Use exposed one additional cold-launch defect after the first green
automation pass: `AppDelegate.applicationDidFinishLaunching` called an absent
superclass selector and the standalone app rendered a black window. The
superclass call was removed in `8a89afd`; `d2758a5` adds the native regression
gate and isolates its test host from Flutter integration targets. The final
repository verifier passed again after both fixes.

The final Ianvs GUI Computer Use gate passed on a clean standalone cold launch:
the shell rendered, command-menu filtering worked, Profiles opened and closed,
a second tab opened, and a real `printf` command produced `SHELL ACTIVE` in both
the terminal and accessibility semantics. Reference-terminal evidence remains
separately unproven for the safety-policy reason documented in
`osc_cross_terminal_probe_20260711.md`.
