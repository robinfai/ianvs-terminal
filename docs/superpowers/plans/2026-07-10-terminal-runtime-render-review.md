# Terminal Runtime And Render Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure and fix terminal idle wake, refresh, paint, graphics-cache, cursor, responsibility, and wire-decoder risks without breaking JSON compatibility or existing correctness gates.

**Architecture:** Keep the existing native frame, runtime, viewport, and row-picture pipeline. Add an advisory native refresh hint beside bounded full polling, isolate scheduling policy in pure Dart, reduce render hot-path allocation, derive graphics revisions in the viewport controller, and move runtime wire selection behind a decoder/coordinator facade. Cursor separation remains evidence-gated.

**Tech Stack:** Rust 2024, Dart 3.11, Flutter 3.44, FFI, JSON/protobuf frame diff, `package:test`, `flutter_test`, `integration_test`, existing benchmark/profile runners.

---

## Execution Order And Commit Boundaries

Implement tasks in order. Phase commits must remain separate:

1. Phase 1: bounded idle fallback, metrics, and real-PTY baseline.
2. Phase 2: optional native refresh hint and adaptive refresh policy.
3. Phase 3: render allocation reduction and paint metrics.
4. Phase 4: graphics revisions and revision-driven cache sync.
5. Phase 5: cursor blink profile and conditional overlay experiment.
6. Phase 6: low-risk coordinator extraction only.
7. Phase 7: transport facade/codecs, shared limits, and parity.
8. Final reports and acceptance evidence.

The detailed subsystem plans are:

- `docs/superpowers/plans/2026-07-10-terminal-refresh-and-idle-wake.md`
- `docs/superpowers/plans/2026-07-10-terminal-render-graphics-cursor.md`
- `docs/superpowers/plans/2026-07-10-terminal-coordinators-and-transport.md`

## Global Invariants

- Do not delete or skip the JSON frame path.
- `TerminalFrameWireFormatPreference.automatic` continues preferring protobuf when supported; `json` continues forcing JSON.
- A false refresh hint never suppresses the bounded full-poll fallback.
- Existing refresh/event/resize/exit ordering tests remain unchanged and pass.
- `TerminalFrameDiff.fromJson` and `fromProtobufBytes` remain source compatible.
- Existing debug getters and `ianvs_terminal_debug.dart` exports remain source compatible.
- No production change is accepted without a test observed failing for the intended reason first.

### Task 1: Phase 1 — Bound Idle Full Polling And Add Evidence

**Files:**

- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- Modify: `packages/ianvs_terminal/test/terminal_frame_pump_test.dart`
- Modify: `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- Modify: `example/integration_test/real_pty_acceptance_test.dart`
- Modify: `docs/TESTING.md`

- [ ] **Step 1: Write failing deadline and metrics tests**

Add tests using an explicitly supplied monotonic `Duration now`. The required API shape is:

```dart
final class TerminalFramePumpMetrics {
  const TerminalFramePumpMetrics({
    required this.emptyRefreshCount,
    required this.backoffSkipTicks,
    required this.currentDelay,
  });

  final int emptyRefreshCount;
  final int backoffSkipTicks;
  final Duration currentDelay;
}
```

`TerminalFramePumpPolicy` exposes this immutable snapshot through
`TerminalFramePumpMetrics metricsFor(String sessionId)` for tests and diagnostics.

Tests must prove that the idle deadlines progress through 132ms, 264ms, then cap at 396ms; advancing the fake clock past a deadline permits the next full poll immediately; activity/remove reset all state; metrics count empty refreshes and skipped timer callbacks.

- [ ] **Step 2: Run the RED tests**

Run:

```bash
cd packages/ianvs_terminal
flutter test test/terminal_frame_pump_test.dart
```

Expected: FAIL because deadline/metrics behavior does not exist and current max interval is 1617ms.

- [ ] **Step 3: Implement deadline-based backoff**

Replace remaining-tick state with monotonic deadlines while retaining `shouldSkipPollingRefresh`, `recordRefreshResult`, `reset`, and `remove`, and add `metricsFor`. Each decision receives `Duration now`; production supplies it from one started `Stopwatch`. Use 33ms as the polling quantum, 132ms as the first idle deadline, and 396ms as the full-poll cap.

- [ ] **Step 4: Add refresh diagnostic events**

Emit a separate `ianvs-terminal-refresh-policy-v1` benchmark event for skipped ticks, full-poll requests, refresh start, frame take, and frame apply. Use one injected monotonic clock and include the applicable `refresh_requested_micros`, `refresh_started_micros`, `frame_taken_micros`, and `frame_applied_micros`, plus `empty_refresh_count`, `backoff_skip_ticks`, `refresh_class`, `hint_poll_count`, and `full_poll_count`. Do not change required fields of `ianvs-bench-dart-runtime-v1`.

- [ ] **Step 5: Add real PTY marker measurement**

Use a FIFO/unique marker handshake. The child first prints READY, blocks on the FIFO for 3–5 seconds of actual idle, then immediately prints the marker. The test waits on READY, policy state, the monotonic idle duration, and diagnostic/frame conditions; fixed sleep is not the observation mechanism. Record trigger-to-frame-apply latency for active, background, and maximum-backoff cases. The deterministic policy cap is 396ms; both the debug integration and local release gates use a 750ms hard tolerance and record raw durations in failure messages.

- [ ] **Step 6: Verify Phase 1**

Run:

```bash
cd packages/ianvs_terminal
flutter analyze --fatal-infos
flutter test
```

Run:

```bash
cd example
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/real_pty_acceptance_test.dart
```

Expected: all tests pass; real PTY output contains the measured latency.

- [ ] **Step 7: Commit Phase 1**

```bash
git add packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart packages/ianvs_terminal/test/terminal_frame_pump_test.dart packages/ianvs_terminal/test/terminal_runtime_controller_test.dart example/integration_test/real_pty_acceptance_test.dart docs/TESTING.md
git commit -m "fix: bound and trace idle terminal refreshes"
```

### Task 2: Phase 2 — Add Refresh Hint And Adaptive Policy

**Files:**

- Modify: `native/core/src/session.rs`
- Modify: `native/core/src/ffi.rs`
- Modify: `native/core/tests/session_test.rs`
- Modify: `packages/ianvs_pty/lib/src/native_pty_backend.dart`
- Modify: `packages/ianvs_pty/test/native_pty_backend_test.dart`
- Create: `packages/ianvs_terminal/lib/src/runtime/terminal_refresh_policy.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- Create: `packages/ianvs_terminal/test/terminal_refresh_policy_test.dart`
- Modify: `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- Modify: `example/integration_test/real_pty_acceptance_test.dart`

- [ ] **Step 1: Write failing Rust hint tests**

Define bit 0 as pending terminal damage. Tests must prove it is false after a frame is consumed, becomes true after PTY output or resize damage, and does not consume dirty state when read.

- [ ] **Step 2: Run Rust RED test, then implement the advisory FFI**

Run the named new test and confirm it fails. Add `ianvs_session_refresh_hint(session_id) -> u32`; invalid/closed sessions return 0. Do not alter frame JSON/protobuf schemas.

- [ ] **Step 3: Write failing Dart optional-capability tests**

Add:

```dart
abstract interface class PtySessionRefreshHintBackend {
  bool get supportsRefreshHints;
  int refreshHintFlags(String sessionId);
}
```

Tests must prove optional symbol lookup, old-library fallback, bitmask forwarding, invalid session handling, and that existing fake `PtyBindings` implementations are not forced to implement the capability.

- [ ] **Step 4: Implement optional Dart binding/backend support**

Use the existing optional lookup pattern. `NativePtyBackend` advertises the capability only when the symbol exists. Runtime ignores unknown bits and converts hint errors into existing backend-error events before falling back to full polling.

- [ ] **Step 5: Write refresh policy transition tests**

Create `TerminalRefreshClass { interactive, streaming, background, idle }` and a pure policy object. Tests cover recent input, continuous activity, active/background state, alternate screen/mouse tracking, transition grace, idle deadline, input/focus/resize/activation reset, and session removal.

- [ ] **Step 6: Integrate policy and hint**

Hint-ready bypasses idle deadline and requests the existing throttled refresh. Default/unknown sessions are active. Keep refresh scheduler mutual exclusion, queued refresh draining, cooldown, event ordering, and JSON/protobuf selection unchanged.

- [ ] **Step 7: Verify native, PTY, terminal, and real PTY paths**

Run `cargo fmt --check`, clippy, serial cargo test, `ianvs_pty` analyze/test, `ianvs_terminal` analyze/test, and the real PTY acceptance. Expected: hint path has a nominal target under 100ms and a 250ms real-integration hard tolerance; forced unsupported hint uses the bounded fallback and remains under 750ms. Record all raw values.

- [ ] **Step 8: Commit Phase 2**

```bash
git add native/core packages/ianvs_pty packages/ianvs_terminal example/integration_test/real_pty_acceptance_test.dart
git commit -m "feat: adapt terminal refreshes with optional native hints"
```

### Task 3: Phase 3 — Reduce Paint Hot-Path Allocation

**Files:**

- Modify: `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`
- Modify: `packages/ianvs_terminal/test/terminal_viewport_render_test.dart`
- Create: `tools/bench/src/terminal_render_phase3_gate.dart`
- Create: `tools/bench/analysis/terminal_render_phase3_gate.dart`
- Create: `tools/bench/test/terminal_render_phase3_gate_test.dart`

- [ ] **Step 1: Add failing paint instrumentation tests**

Assert benchmark events include `rows_visited`, `picture_draw_count`, and `debug_collection_enabled`; repeated cursor-only paint reports zero row visual rebuilds; identical `cursorVisible` assignment does not schedule another paint.

- [ ] **Step 2: Run RED widget tests**

Run the two viewport render test files with plain-name filters and verify missing metrics/equality short-circuit failures.

- [ ] **Step 3: Reuse paint and scratch objects**

Store background/span/selection/cursor/search `Paint` objects and active/rebuilt/debug scratch collections on the render object. Clear and reuse them. Prune row caches only on a new frame or cache shift/invalidation. Preserve every debug getter in debug builds; release without a benchmark sink skips debug-only collection.

- [ ] **Step 4: Verify Phase 3 and commit**

Run terminal analyze/all tests and example viewport tests, then commit only Phase 3 files with:

```bash
git commit -m "perf: reduce terminal paint allocation churn"
```

### Task 4: Phase 4 — Drive Graphics Cache Sync By Revision

**Files:**

- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_graphics_cache.dart`
- Modify: `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- Modify: `packages/ianvs_terminal/test/terminal_viewport_render_test.dart`

- [ ] **Step 1: Add failing revision/sync tests**

Cover first attach, cache/controller replacement, asset add/remove/version, duplicate placements, geometry-only placement changes, authoritative empty delta, and unchanged text/cursor frames. `frameVersion` grows every frame; `graphicsAssetRevision` grows only when the unique asset-key set changes; `graphicsRevision` grows on any full placement semantic change.

- [ ] **Step 2: Implement deep placement equality and revisions**

Compare all placement fields, not the existing abbreviated diagnostics signature. Derive unique asset-key sets without allocating during widget sync.

- [ ] **Step 3: Implement private revision-driven sync state**

Track controller/cache identity and last asset revision inside the viewport state. Pass the controller's cached live asset-key set directly and call `evictExcept` only for initial/changed sync. Dispose/reset state on widget lifecycle changes. The pure `TerminalGraphicsSync` extraction remains Phase 6 work so Phase 4 stays a measured behavior change rather than mixing in a responsibility refactor.

- [ ] **Step 4: Verify Phase 4 and commit**

Run terminal analyze/all tests plus graphics-focused example tests. Commit with:

```bash
git commit -m "perf: drive terminal graphics cache by revisions"
```

### Task 5: Phase 5 — Profile Cursor Blink And Gate Overlay

**Files:**

- Modify: `example/integration_test/terminal_render_profile_test.dart`
- Modify: `example/lib/benchmarks/terminal_render_profile_report.dart`
- Create: `example/lib/benchmarks/terminal_cursor_overlay_gate.dart`
- Modify: `example/test/benchmarks/terminal_render_profile_report_test.dart`
- Create: `example/test/benchmarks/terminal_cursor_overlay_gate_test.dart`
- Conditional modify: `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
- Conditional modify: `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`
- Conditional create: `packages/ianvs_terminal/lib/src/terminal/render_terminal_cursor_overlay.dart`
- Conditional create: `packages/ianvs_terminal/lib/src/terminal/terminal_cursor_overlay_experiment.dart`
- Conditional modify: `packages/ianvs_terminal/test/terminal_viewport_render_test.dart`
- Conditional modify: `example/test/terminal/render_terminal_viewport_test.dart`
- Conditional modify: `example/test/terminal_input_controller_test.dart`
- Create: `docs/evidence/2026-07-10-cursor-overlay/cursor_overlay_gate.json`
- Create: `docs/evidence/2026-07-10-cursor-overlay/decision.md`

- [ ] **Step 1: Add failing report classification tests**

Add `cursor_blink_idle_profile` and distinguish repeated-frame main-surface paint from cursor-layer paint. The report test must fail until both classes and p50/p95 metrics exist.

- [ ] **Step 2: Run control profile**

Run a profile build with static 40×120 content, explicit focus, no frame updates, at least 20 blinks, and five repeats. Record main paint count, rows visited, picture draws, build/raster/paint p50/p95, missed vsync, and output directory.

- [ ] **Step 3: Implement an experimental overlay only behind an internal test/profile switch**

The experiment uses a tight cursor leaf render object and repaint boundary. Blink notifies only the overlay; cursor visual recomputes on frame/font/colors/DPR/config changes. Maintain main/inline-image/negative-z/cursor/positive-z layering. Do not add a new public constructor parameter or exported render-mode API merely to run the experiment.

- [ ] **Step 4: Run A/B and decide**

Enable production overlay only if each blink produces one overlay paint, zero main-surface paints, zero row rebuilds, correctness tests all pass, and repeated profile p95 improves without unacceptable layer cost. Otherwise remove the experimental production code and its mode seam, and keep only the benchmark/report evidence plus a documented no-go result.

- [ ] **Step 5: Commit Phase 5**

Commit benchmark plus either the validated overlay or the documented no-go result with exactly one of:

```bash
git commit -m "perf: enable measured terminal cursor overlay"
git commit -m "bench: record terminal cursor overlay no-go"
```

The two commands are alternatives, not two commits; use the first only for a passing gate and the second only after removing every overlay production hunk on a no-go result.

### Task 6: Phase 6 — Extract Only Proven Low-Risk Coordinators

**Files:**

- Create: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump_controller.dart`
- Create: `packages/ianvs_terminal/lib/src/terminal/terminal_focus_reporter.dart`
- Create: `packages/ianvs_terminal/lib/src/terminal/terminal_graphics_sync.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
- Modify: `packages/ianvs_terminal/test/terminal_frame_pump_test.dart`
- Create: `packages/ianvs_terminal/test/terminal_frame_pump_controller_test.dart`
- Create: `packages/ianvs_terminal/test/terminal_focus_reporter_test.dart`
- Create: `packages/ianvs_terminal/test/terminal_graphics_sync_test.dart`
- Modify: `packages/ianvs_terminal/test/terminal_viewport_render_test.dart`

- [ ] **Step 1: Write focused behavior tests before moving code**

Capture frame-pump session lifecycle/metrics/hint decisions and focus attach/detach/gain/loss reporting through public behavior. Run and confirm tests pass against the old implementation; then temporarily route one expectation to the planned coordinator and confirm RED because it does not exist.

- [ ] **Step 2: Move frame-pump state without changing refresh ordering**

Move only deadline/policy/hint counters and decisions. Runtime remains responsible for refresh execution, queue draining, frame/event order, warm-up, and session removal calls.

- [ ] **Step 3: Move focus-report state without adding a Widget layer**

Move last-reported focus state and report decisions. The viewport remains responsible for FocusNode/TextInputConnection/IME lifecycle and calls the reporter.

- [ ] **Step 4: Defer full IME extraction unless a small, test-complete boundary emerges**

Do not move key state, selection, caret geometry, and TextInputConnection together in this phase. Record the coupling in the changes report instead of creating a large coordinator.

- [ ] **Step 5: Verify Phase 6 and commit**

Run all terminal tests plus example input/viewport tests. Commit with:

```bash
git commit -m "refactor: isolate terminal runtime coordinators"
```

### Task 7: Phase 7 — Put Wire Handling Behind Facades

**Files:**

- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_decoder.dart`
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_json_frame_decoder.dart`
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_protobuf_frame_decoder.dart`
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_frame_validation_limits.dart`
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_wire_compatibility.dart`
- Create: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_transport_coordinator.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
- Modify: `packages/ianvs_terminal/lib/ianvs_terminal.dart`
- Create: `packages/ianvs_terminal/test/support/terminal_frame_wire_fixture.dart`
- Modify: `packages/ianvs_terminal/test/terminal_frame_decoder_test.dart`
- Create: `packages/ianvs_terminal/test/terminal_frame_codec_parity_test.dart`
- Modify: `packages/ianvs_terminal/test/terminal_frame_diff_corpus_test.dart`
- Modify: `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- Modify: `docs/FRAME_DIFF.md`

- [ ] **Step 1: Add decoder and full-field parity RED tests**

Require `decode`, `decodeJson`, and `decodeProtobuf`; success/bad payload/UTF-8 byte metrics; compatibility factory equality; and field-by-field JSON/PB parity for rows/styles/cursor/selection/dirty/colors/modes/window/hyperlinks/images/graphics. Add limit parity for dimensions, styles, hyperlinks, images, malformed scan caps, unknown enums, missing schema, and unknown protobuf fields.

- [ ] **Step 2: Add shared limits and codecs**

Move numeric limits to one internal file. JSON and protobuf codecs construct the same domain objects and apply equivalent normalization. Keep proto field numbers/default compatibility unchanged.

- [ ] **Step 3: Add transport coordinator and simplify runtime**

The coordinator owns backend capability detection, automatic/forced-JSON selection, raw read error forwarding, decode call, and metrics envelope. It must not access viewport or refresh scheduler. Runtime applies the returned frame/metrics as before.

- [ ] **Step 4: Preserve public compatibility seam**

Keep public `TerminalFrameDiff.fromJson/fromProtobufBytes`. If removing the generated import requires a circular dependency or breaking factory change, keep it as a documented seam; do not trade source compatibility for a cosmetic dependency graph.

- [ ] **Step 5: Verify Phase 7 and commit**

Run decoder/parity/corpus/runtime/all terminal tests, transport benchmark smoke, and the non-GUI total verify. Commit with:

```bash
git commit -m "refactor: isolate terminal frame transport"
```

### Task 8: Final Review, Reports, And Computer Gate

**Files:**

- Create: `docs/reviews/terminal_runtime_render_review_20260710.md`
- Create: `docs/reviews/terminal_runtime_render_changes_20260710.md`
- Modify if facts changed: `docs/TESTING.md`, `docs/KNOWN_ISSUES.md`, `docs/FRAME_DIFF.md`, `tools/bench/README.md`

- [ ] **Step 1: Run the complete automated gate twice**

Run the full `./tools/verify_flutter_terminal.sh` with macOS integrations until it completes successfully twice in succession with no intervening code change. Run JSON/protobuf parity and cursor/refresh profiles. Record exact commands, exit codes, summaries, host caveats, and artifacts.

- [ ] **Step 2: Build Release and inspect signing/hardening**

Run `flutter build macos --release`, inspect app/dylib signatures and hardened runtime build settings, then launch the built app.

- [ ] **Step 3: Use Computer for final acceptance**

Through the local app UI: create a shell session, type and observe output, wait for asynchronous idle marker, resize, switch tab/pane activity, move focus, observe cursor blink, scroll and return to bottom, then close the session. Capture screenshots and accessibility-tree evidence. No external messages or destructive actions are permitted.

- [ ] **Step 4: Repeat review/fix until no reproducible issue remains**

Every new issue receives reproduction evidence, classification, a failing automated regression test where possible, a minimal fix, and focused verification. Any issue found by Computer invalidates the gate: rerun the complete automated gate successfully twice, rebuild and re-inspect Release, then repeat the complete Computer acceptance flow. Stop only when the final Computer pass finds no reproducible issue.

- [ ] **Step 5: Write and verify final reports**

Separate confirmed issues, benchmark inferences, and unverified hypotheses. Include baseline/phase/final commit SHAs, benchmark summary, commands run, commands not run with reason, compatibility status, risks, and follow-ups. Run docs contract and `git diff --check`.

- [ ] **Step 6: Commit reports**

```bash
git add docs/reviews docs/TESTING.md docs/KNOWN_ISSUES.md docs/FRAME_DIFF.md tools/bench/README.md
git commit -m "docs: report terminal runtime render review"
```
