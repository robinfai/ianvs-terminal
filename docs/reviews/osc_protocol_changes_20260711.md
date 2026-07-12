# OSC protocol changes and phase evidence — 2026-07-11–12

Branch: `codex/osc-capability-completion-20260711`

## Commit map

| Commit | Scope |
|---|---|
| `6303515` | Phases 0–2: preflight, OSC 21/22 side effects, OSC 8 identity, dynamic baseline reset |
| `66016b4` | Phases 3–7 native/vendor engine, security bounds, shared corpus and semantic probe |
| `189dee9` | Phases 3–7 Dart/Flutter product integration, render/UI tests and verification gate |
| `1bb2f3b` | Phase 8 Kitty OSC 99 safe notification subset and end-to-end evidence |
| `9972758` | Phase 9 UAPI OSC 3008 bounded typed context hierarchy and end-to-end evidence |
| `f7d48bb` | Phase 10 Kitty OSC 21 bounded color control and OSC 23 title-side-effect removal |
| `fbf9a37` | Phase 11 Kitty OSC 22 pointer-shape stacks, frame transport and system-cursor integration |
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

## Phase 8 report — Kitty OSC 99 safe subset

- **Start SHA:** `a4925b27215ce3454e7e3413d53d219cf6e90de5`.
- **End SHA:** `1bb2f3b6c27a7095024ce339af033d80bbcec85a`.
- **Modified files:** notification parser/state/snapshot/streaming policy; native
  session event bridge and diagnostics; Dart runtime and product state; macOS
  delivery bridge; corpus/probe/docs and layered tests.
- **Confirmed issue:** OSC 99 was only a generic unknown-OSC no-op, so Kitty
  notification identity, chunking and lifecycle were unavailable.
- **Fixes:** safe ID/title/body/Base64 chunks, application/type metadata,
  update/close, static query, expiry, stable macOS identity and explicit close.
- **Unfixed by design:** buttons, activation/focus callbacks, close reports,
  sound selection, icons, urgency and commands remain unsupported.
- **Tests/results:** focused parser, native real-PTY, corpus, Dart runtime,
  controller, ShellScreen and macOS real-PTY tests pass. Full repository gate is
  recorded after it runs on the final tree.
- **Compatibility:** OSC 9/777 remain source compatible; typed JSON event fields
  are additive and no protobuf tag changes are required.
- **Security:** 8 KiB streaming admission, 1/2/4 KiB metadata/plain/Base64 chunk
  bounds, 64 pending/active IDs, payload-free diagnostics and no new execution
  authority.
- **Rollback:** revert the Phase 8 commit; OSC 99 returns to bounded unsupported
  behavior without affecting OSC 9/777.

## Phase 9 report — UAPI OSC 3008 typed contexts

- **Start SHA:** `f9965084d91a74a55a05c575d5325684067f818a`.
- **Modified files:** context parser/state/event/snapshot/streaming policy;
  native typed bridge and diagnostics; Dart typed runtime route; corpus/probe,
  real-PTY acceptance and protocol evidence.
- **Confirmed issue:** OSC 3008 was only a generic unknown-OSC no-op, so UAPI
  hierarchy and lifecycle metadata were unavailable.
- **Fixes:** all v1.0 context types/fields, bounded nesting, repeat-start return
  semantics, descendant closure, malformed-close recovery, textual escapes,
  snapshot/RIS persistence and additive typed events.
- **Unfixed by design:** no context-driven UI, navigation, profile switching,
  privilege decision, execution, or other host action.
- **Security:** metadata capability gate, 16 KiB ingress, depth 32, ID 64 bytes,
  field 255 bytes, bounded queues and raw-text-free diagnostics.
- **Tests/results:** corpus 17/17 and semantic probes 12/12; vendored 1,592
  passed/1 ignored; native lib 73/73, corpus 1/1, session 451/451, vttest 3/3;
  terminal package 441 passed, example grouped 913/913, Widget 125/125, macOS
  smoke 4/4, real PTY 18/18 and RunnerTests 10/10.
- **Rollback:** revert Phase 9; OSC 3008 returns to a bounded unsupported no-op.

## Phase 10 report — Kitty OSC 21 color control and OSC 23 correction

- **Start SHA:** `a418f51ad85e0f8d6762bc261236490539af3a07`.
- **End SHA:** `f7d48bbda8dbffab0fe637c0b1a306bbd9c4a761`.
- **Modified files:** dedicated color-control state, color/OSC dispatch,
  snapshot/RIS state, native real-PTY tests, mirrored corpus, semantic probe,
  macOS real-PTY acceptance and protocol evidence.
- **Confirmed issues:** published Kitty OSC 21 color control was discarded, and
  the unrelated OSC 23 opcode incorrectly popped the CSI title stack.
- **Fixes:** ordered palette 0–255 and core-color set/query/reset; special-slot,
  dynamic and alpha state; profile baselines; 4 KiB replies; malformed-field
  isolation; OSC 23 bounded no-op.
- **Unfixed by design:** selection text recoloring, cursor-text rendering,
  visual-bell tint and transparent-background compositing remain non-visual;
  OSC 22 pointer-shape state is the next protocol phase.
- **Security:** appearance-only gate, VT220 denial, bounded keys/fields/replies,
  payload-free diagnostics and no host authority.
- **Tests/results:** corpus 18 cases/20 edge classes, probes 14; vendored 1,598
  passed/1 ignored; native lib 73/73, corpus 1/1, session 453/453, vttest 3/3;
  terminal package 441 passed, example grouped 913/913, Widget 125/125, macOS
  smoke 4/4, real PTY 19/19 and RunnerTests 10/10.
- **Rollback:** revert `f7d48bb`; OSC 21 returns to bounded unsupported behavior.

## Phase 11 report — Kitty OSC 22 pointer shapes

- **Start SHA:** `b2527e5f331ac3c60204e11cfcb59caa88e1b1c6`.
- **End SHA:** `fbf9a37f2010035fb0e2a2c59e45f5cff6ac47d7`.
- **Modified files:** pointer parser/state/snapshot and OSC dispatch; native
  frame model/protobuf/session bridge; Dart frame model and viewport; mirrored
  corpus, semantic probe, real-PTY, widget and protocol evidence.
- **Confirmed issue:** published Kitty OSC 22 was discarded, so applications
  could neither control nor query the terminal-surface pointer shape.
- **Fixes:** all 30 canonical shapes plus practical Kitty aliases; direct
  set/reset; bounded push/pop; current/default/grabbed/support queries;
  independent primary/alternate stacks; snapshot/RIS behavior; additive
  JSON/protobuf transport and exhaustive Flutter system-cursor mapping.
- **Unfixed by design:** link hover may temporarily override the requested
  shape; OSC 22 cannot move the host pointer, capture input or authorize a host
  action. Kitty reference-terminal comparison remains pending.
- **Security:** appearance-only gate, VT220 denial, 4 KiB ingress/reply bounds,
  64-byte ASCII names, 32-entry screen-local stacks and payload-free rejection.
- **Tests/results:** corpus 19 cases/22 edge classes, probes 15; vendored 1,606
  passed/1 ignored; native lib 73/73, corpus 1/1, session 455/455, vttest 3/3;
  terminal package 442 passed/1 skipped, example grouped 914/914, Widget
  125/125, macOS smoke 4/4, real PTY 20/20 and RunnerTests 10/10.
- **Computer Use:** standalone Debug app cold launch passed; real-PTY `wait`
  set and empty reset markers rendered, command menu and Profiles opened, a
  second shell tab accepted input, and accessibility returned `SHELL ACTIVE`.
- **Rollback:** revert `fbf9a37`; OSC 22 returns to bounded unsupported behavior.

## Phase 12 report — Kitty OSC 66 sized text

- **Start SHA:** `6a99296406baa7bd042c6c7e70eddd95ad674071`.
- **Implementation SHA:** `54423525c25b42fe886094cd66b476022c98025c`.
- **Modified files:** multicell cell/grid/parser state; reflow/edit/erase/export
  paths; native frame model/protobuf/session bridge; Dart validation/runtime and
  Flutter painter; mirrored corpus, semantic probe, real-PTY and protocol docs.
- **Confirmed issue:** published Kitty OSC 66 was discarded, so applications
  could not reserve exact widths or render integral/fractional sized text.
- **Fixes:** bounded metadata and 4 KiB UTF-8 text; fixed/natural widths;
  integral/fractional scale and alignment; complete overwrite/edit/erase,
  scrollback, resize/reflow, snapshot/RIS and cursor behavior; additive typed
  frame transport; clipped Flutter painting.
- **Review fixes:** preserved valid blocks across width reflow; scanned and
  sanitized history-only fragments; removed ED2/ED3 cross-boundary fragments;
  enforced UTF-8 byte bounds in Dart; restored plain-output O(1) hot paths.
- **Unfixed by design:** a renderer may downsize overfull text as allowed by the
  protocol; OSC 72 remains a separate deferred drag-and-drop host action; Kitty
  reference-terminal comparison remains pending.
- **Security:** appearance-only policy, VT220 denial, payload-free rejection,
  4 KiB text, 128-byte metadata, bounded dimensions and additive codecs.
- **Tests/results:** corpus 20 cases/24 edge classes, probes 16; vendored 1,622
  passed/1 ignored; native lib 74/74, corpus 1/1, session 457/457, vttest 3/3;
  example grouped 914/914, Widget 125/125, macOS smoke 4/4, real PTY 21/21 and
  RunnerTests 10/10.
- **Computer Use:** cold-launch visual gate passed: live real-PTY scaled text,
  protocol-defined EL erasure, clear/reset, command menu, Profiles, second-tab
  input/output and `SHELL ACTIVE` all behaved as expected.
- **Rollback:** revert the Phase 12 implementation commit; OSC 66 returns to
  bounded unsupported behavior and protobuf tag 24 becomes unused.

## Deferred phases

Phase 8 Kitty OSC 99 is implemented as the safe subset recorded in
`osc99_phase8_20260711.md`. Phase 9 OSC 3008 is implemented as typed metadata in
`osc3008_phase9_20260711.md`. Phase 10 OSC 21 and Phase 11 OSC 22 are implemented
as recorded in `osc21_phase10_20260712.md` and `osc22_phase11_20260712.md`.
Phase 12 Kitty OSC 66 is implemented as recorded in
`osc66_phase12_20260712.md`.
Phase 13 Kitty OSC 72 implements the target subset recorded in
`osc72_phase13_20260712.md`. Its outgoing/remote-file remainder, unsafe iTerm2
upload/download/actions, arbitrary URL/profile/command actions,
notification buttons/sounds/icons and shell-provided execution are deferred.
Unknown/deferred sequences remain bounded and cannot gain host authority.

## Final verification record

The Phase 12 repository gate is green:

- vendored fmt, strict Clippy and tests: 1,622 passed, 1 ignored; doc tests 11
  passed, 1 ignored;
- native fmt/Clippy; lib 74/74, corpus 1/1, session 457/457, vttest 3/3;
- corpus validator 20 cases (24 edge classes) and semantic probe self-test 16/16;
- Dart/Flutter analysis and protocol/runtime/controller/widget focused suites;
- macOS smoke 4/4, real PTY 21/21 and native RunnerTests 10/10.

Final implementation-tree command:

```bash
VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 \
  ./tools/verify_flutter_terminal.sh
```

Result: passed with exit code 0. This includes vendored/core format, strict
Clippy and tests; PTY/Dart/Flutter analysis and tests; docs contract; CI smoke
benchmark; 914 example grouped tests; complete example Widget tests 125/125;
macOS smoke 4/4; and macOS real PTY acceptance 21/21. The optional nightly
resource benchmark was not enabled because it is not a release gate. The
verifier also rebuilds the standalone macOS app after Flutter integration tests
and runs native RunnerTests 10/10.

Computer Use exposed one additional cold-launch defect after the first green
automation pass: `AppDelegate.applicationDidFinishLaunching` called an absent
superclass selector and the standalone app rendered a black window. The
superclass call was removed in `8a89afd`; `d2758a5` adds the native regression
gate and isolates its test host from Flutter integration targets. The final
repository verifier passed again after both fixes.

The final Phase 12 Computer Use gate passed after manual unlock on a cold-launched
standalone Debug app. A live real-PTY probe visibly rendered red scaled
`OSC66-GATE` text and an adjacent marker; the subsequent prompt EL erased the
entire intersecting block as specified. Clear/reset left no control-code debris,
and the command menu, Profiles, second real-shell tab and `SHELL ACTIVE` state
all passed. Reference-terminal evidence remains separately unproven for the
safety-policy reason documented in `osc_cross_terminal_probe_20260711.md`.

## Phase 13 report — Kitty OSC 72 target subset

- **Start SHA:** `d22f209bb37fd425f26278cf0b1b4f7f1b17f67e`.
- **Implementation SHA:** `260abc8`.
- **Confirmed issue:** OSC 72 was a generic no-op, so a TUI could neither
  negotiate a Finder drop nor receive user-dropped MIME data.
- **Fixes:** default-off typed parser, active-pane target ownership, correlated
  query, move/drop geometry and operation negotiation, bounded native
  pasteboard capture, indexed Base64 data chunks, end markers and cleanup.
- **Review fixes:** empty MIME defaults, remote `y/Y` denial, legacy safety
  switch denial, payload-aware event accounting and exact encoded chunk bound.
- **Unfixed by design:** outgoing drags/images/data offers, remote machine file
  reads, directory handles/traversal and symlinks remain unauthorized.
- **Security:** 1 KiB metadata, 4 KiB encoded packets, 64 MIME entries, 256-byte
  MIME tokens, 64 MiB captured drop budget, 3,072-byte reads, active-pane only,
  user gesture required and no arbitrary path selection.
- **Tests/results:** repository gate passed: corpus 21/26, probes 17, vendored
  1,628, native session 459/459, example grouped 922/922, complete Widget
  125/125, macOS smoke 4/4, real PTY 22/22 and RunnerTests 12/12. Computer Use
  visibly confirmed the production query/register path and exact capability
  response; see `osc72_phase13_20260712.md` for the Finder gesture boundary.
- **Rollback:** revert the Phase 13 implementation commit; OSC 72 returns to a
  bounded generic no-op with no config or wire compatibility break.

## Phase 14 report — iTerm2 OSC 1337 shell metadata

- **Start SHA:** `1e0cd05a8c7c8fe4f7dd71107790a560a10ad031`.
- **Implementation SHA:** `4d080ae`.
- **Confirmed gaps:** SetMark, ShellIntegrationVersion and ReportCellSize were
  absent at the product boundary.
- **Fixes:** typed primary-screen mark, validated version/shell metadata,
  logical cell/DPR retention, bounded pre-layout query queue and exact
  `height;width;scale` replies.
- **Security:** metadata/appearance capabilities remain independent; VT220 and
  explicit fine-grained policy deny while the legacy switch retains its
  historical mapping; 100 product marks, 16 queued geometry queries,
  no new host/file/process authority.
- **Tests/results:** targeted parser, split, policy, corpus, native real PTY,
  VT220, Dart runtime, product, Widget and macOS application real-PTY tests pass.
  The repository-wide verifier passed with corpus 22/28, probes 18, vendored
  1,633, native lib 75/75 and session 461/461, example grouped 923/923, Widget
  125/125, macOS smoke 4/4, real PTY 23/23 and RunnerTests 12/12. Computer Use
  visibly confirmed `P14-MARK`, `ReportCellSize=22.00;8.40;2.00`, `P14-PASS`,
  shell/version state and post-probe interactive input on the standalone build.
- **Compatibility:** additive events/state only; no protobuf/frame changes.
- **Rollback:** revert the Phase 14 implementation commit; existing OSC 1337
  CurrentDir/RemoteHost/UserVar/Badge behavior remains unchanged.
