# Terminal Refresh and Idle Wake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bound idle terminal wake latency, measure every refresh stage, and add a backward-compatible adaptive refresh policy plus optional native output hint without changing frame JSON/protobuf contracts or the required backend interface.

**Architecture:** Phase 1 replaces callback-count backoff with monotonic per-session deadlines of 132/264/396ms, adds full refresh lifecycle diagnostics, and proves a real PTY fallback bound after four seconds of genuine child-process idle. Phase 2 introduces an independent `terminal_refresh_policy.dart` classifier for interactive, streaming, background, and idle sessions, then adds a non-consuming optional Rust/FFI dirty hint that can wake an idle terminal while the Phase 1 full-poll fallback remains mandatory.

**Tech Stack:** Dart 3, Flutter widget and macOS integration tests, Riverpod provider overrides, `dart:ffi`, Rust atomics and C ABI exports, JSON diagnostics, existing JSON/protobuf terminal frame transports.

---

## Fixed design decisions

- The existing 33ms frame cooldown, refresh queue/deduplication, frame-before-event decision, and event processing order do not change.
- Phase 1 idle deadlines are exactly 132ms, 264ms, then 396ms forever. At a 33ms base tick these correspond to 3, 7, and 11 skipped ticks.
- Phase 2 refresh classes are exactly:

  ```dart
  enum TerminalRefreshClass { interactive, streaming, background, idle }
  ```

- A session with no activation information is treated as active. Unknown does not mean background.
- The optional native hint is advisory. A false hint never postpones a due full poll.
- The hint only reports pending reader-driven frame work. Full polling remains responsible for process exit discovery, synchronized-output timeouts, and time-driven graphics animation.
- Timing budgets distinguish deterministic policy from host-sensitive integration:
  - native hint nominal target: no more than 100ms;
  - real-PTY hint hard ceiling in debug and release: no more than 250ms;
  - no-hint policy cap in deterministic tests: exactly 396ms;
  - real-PTY no-hint hard ceiling in debug and release: no more than 750ms.
- Every real-PTY timing assertion prints the raw elapsed microseconds in the test log and repeats it in the assertion reason; the nominal target is reported separately from the hard ceiling.
- Phase 1 captures separate active, background-deadline, and maximum-backoff baselines. Phase 2 repeats the same three scenarios with explicit refresh classes and both hint-enabled and hint-masked paths.
- No fields are added to frame JSON, `native/core/proto/frame_diff.proto`, or generated protobuf sources.
- No required method is added to `PtySessionBackend` or `PtyBindings`.
- Phase 1 and Phase 2 each end in a separate commit.

## Refresh class rules

Classification priority is `interactive > streaming > background > idle`.

| Class | Exact entry rule | Full-poll scheduling | Exit rule |
|---|---|---|---|
| `interactive` | Effective active session and any of: focused, within 500ms of input/focus/resize/activation, alternate screen enabled, or mouse mode not `off` | 33ms | Grace expires, focus is false, and alternate-screen/mouse conditions are absent |
| `streaming` | Two consecutive frame-bearing refreshes no more than 100ms apart; valid for 250ms after the latest frame | 33ms | A frame gap exceeds 100ms or the 250ms streaming grace expires |
| `background` | Explicitly inactive and not currently streaming | Cheap hint every 33ms; full poll follows 132/264/396ms deadlines | Activation or streaming activity |
| `idle` | Effective active, not interactive, and not streaming | Cheap hint every 33ms; full poll follows 132/264/396ms deadlines | Interaction, streaming activity, alternate screen, mouse tracking, or explicit backgrounding |

Additional rules:

- `effectiveActive = explicitActive ?? true`.
- A background stream may enter `streaming`; after the streaming grace it returns to `background`.
- Alternate screen and mouse tracking force `interactive` only for an effective active session.
- Focus loss does not itself mark a session background; activation state is controlled separately by `SessionController`.
- Input, focus gain, successful resize, and activation all reset idle deadlines and start the 500ms interactive grace.
- Frame activity confirms streaming; a hint alone does not change class until the subsequent full refresh observes activity.

## Diagnostic schema

All refresh diagnostics use `schema_version: ianvs-terminal-refresh-policy-v1` and the existing optional `TerminalBenchmarkEventSink`. They never enter frame JSON/protobuf payloads.

Required event names:

```text
poll_tick_skipped
full_poll_requested
refresh_started
frame_taken
frame_applied
refresh_result
```

Every event contains:

```text
schema_version
event
monotonic_micros
session_id
refresh_id
refresh_class
empty_refresh_count
backoff_skip_ticks
current_delay_micros
hint_poll_count
full_poll_count
```

Lifecycle events additionally carry these nullable monotonic timestamps:

```text
refresh_requested_micros
refresh_started_micros
frame_taken_micros
frame_applied_micros
```

Semantics:

- `poll_tick_skipped`: emitted when a 33ms tick does not request a full poll; `refresh_id` and lifecycle timestamps are null.
- `full_poll_requested`: allocates the per-session increasing `refresh_id`, increments `full_poll_count`, records the first request time and request reason, and survives cooldown/in-flight coalescing as pending trace metadata.
- `refresh_started`: records when the existing scheduler actually enters `_refreshSessionOnce`.
- `frame_taken`: records immediately after `_takeFrameDiff`, including null-frame pulls.
- `frame_applied`: records in `_applyFrame` after viewport update and before the existing `TerminalSessionFrameEvent` emission.
- `refresh_result`: closes the trace and includes `had_activity`, `received_frame`, `event_count`, the next deadline, and all known lifecycle timestamps.
- For a frame-bearing refresh, tests require:

  ```text
  refresh_requested_micros <= refresh_started_micros
  refresh_started_micros <= frame_taken_micros
  frame_taken_micros <= frame_applied_micros
  ```

- For an empty refresh, `frame_applied_micros` is null.
- Phase 1 always reports `hint_poll_count == 0`. Phase 2 increments it once per successful optional-hint read; unsupported, disabled, and throwing calls do not increment it.
- `current_delay_micros` and `backoff_skip_ticks` are exactly 132000/3, 264000/7, or 396000/11 at the three fallback levels.
- Before the four-class policy exists, Phase 1 diagnostics map the 33ms active state to `refresh_class: interactive`, the 264ms baseline scenario to `refresh_class: background`, and the saturated 396ms state to `refresh_class: idle`. These are measurement labels; Phase 2 replaces their derivation with `TerminalRefreshPolicy`.

## File Structure

### Phase 1

- Modify `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart`
  - Keep this file focused on monotonic deadline/backoff state only.
- Modify `packages/ianvs_terminal/test/terminal_frame_pump_test.dart`
  - Prove 132/264/396ms and late-timer behavior without wall-clock waiting.
- Modify `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
  - Integrate the deadline primitive and lifecycle trace timestamps around existing calls.
- Modify `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
  - Prove diagnostics, counts, monotonic ordering, interaction reset, and unchanged scheduling order.
- Modify `example/integration_test/real_pty_acceptance_test.dart`
  - Add four-second-idle FIFO baselines for active, background-deadline, and maximum-backoff states with condition-driven observation.

### Phase 2

- Create `packages/ianvs_terminal/lib/src/runtime/terminal_refresh_policy.dart`
  - Own classification, grace periods, activation/focus state, frame-stream detection, hint/full-poll decisions, and counters.
- Create `packages/ianvs_terminal/test/terminal_refresh_policy_test.dart`
  - Exhaustively test all four classes and every reset signal.
- Modify `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart`
  - Remain the deadline primitive used by the new policy.
- Modify `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
  - Delegate class decisions to `TerminalRefreshPolicy`, read optional hints, and preserve the scheduler/cooldown/event sequence.
- Modify `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
  - Prove policy/runtime wiring, hint fallback, diagnostics, alternate screen, mouse tracking, and protobuf transport stability.
- Modify `native/core/src/session.rs`
  - Expose a non-consuming dirty flag hint.
- Modify `native/core/src/ffi.rs`
  - Export an allocation-free optional `u32` hint symbol.
- Modify `native/core/tests/session_test.rs`
  - Prove non-consumption and reader-driven dirty transitions.
- Modify `packages/ianvs_pty/lib/src/native_pty_backend.dart`
  - Add optional capability interfaces without changing base interfaces.
- Modify `packages/ianvs_pty/test/native_pty_backend_test.dart`
  - Prove supported, missing-symbol, and original-interface behavior.
- Modify `example/lib/features/sessions/session_controller.dart:22-50,489-573,625-651`
  - Wire explicit active/background transitions through the existing `ptySessionBackendProvider` and runtime provider.
- Modify `example/test/sessions/session_controller_test.dart`
  - Prove old/new session activation updates refresh classification.
- Modify `example/lib/features/shell/shell_screen_state_sessions.dart:175-220`
  - Wire terminal focus gain/loss to the runtime.
- Modify `example/test/widget_test.dart`
  - Prove the real shell focus listener reaches refresh diagnostics.
- Modify `example/integration_test/real_pty_acceptance_test.dart`
  - Add native-hint and hint-masked FIFO paths.

## Preflight: verify paths, providers, and command roots

- [ ] **Step 1: Verify all planned files and providers exist**

Run from the repository root:

```bash
test -f packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart
test -f packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart
test -f packages/ianvs_pty/lib/src/native_pty_backend.dart
test -f native/core/src/session.rs
test -f native/core/src/ffi.rs
test -f example/integration_test/real_pty_acceptance_test.dart
test -x tools/build_core.sh
rg -n "final ptySessionBackendProvider|final terminalGraphicsTraceSinkProvider" example/lib/features/sessions/session_controller.dart
```

Expected: every `test` exits 0; `rg` reports `ptySessionBackendProvider` near line 22 and `terminalGraphicsTraceSinkProvider` near line 26.

- [ ] **Step 2: Confirm package command roots**

```bash
test -f packages/ianvs_terminal/pubspec.yaml
test -f packages/ianvs_pty/pubspec.yaml
test -f example/pubspec.yaml
test -f native/core/Cargo.toml
```

Expected: all commands exit 0. Flutter package tests below run from `packages/ianvs_terminal/`; PTY Dart tests run from `packages/ianvs_pty/`; macOS integration tests run from `example/`.

## Phase 1 — Monotonic bounded fallback and full lifecycle diagnostics

### Task 1: Write Phase 1 failing tests

**Files:**
- Test: `packages/ianvs_terminal/test/terminal_frame_pump_test.dart`
- Test: `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- Test: `example/integration_test/real_pty_acceptance_test.dart`

- [ ] **Step 1: Replace skip-counter assertions with exact deadline assertions**

Tests target this interface:

```dart
final class TerminalFramePumpPolicy {
  TerminalFramePumpPolicy({
    required Duration activeInterval,
    required int emptyRefreshesBeforeBackoff,
    required List<Duration> idleIntervals,
  });

  bool shouldSkipPollingRefresh(
    String sessionId, {
    required Duration now,
  });

  void recordRefreshResult(
    String sessionId, {
    required Duration now,
    required bool hadActivity,
  });

  void reset(
    String sessionId, {
    required Duration now,
  });

  void remove(String sessionId);

  TerminalFramePumpMetrics metricsFor(String sessionId);
}

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

Assert:

- first empty refresh remains at 33ms;
- second empty refresh schedules 132ms with 3 skip ticks;
- next empty refreshes schedule 264ms/7 and 396ms/11;
- all later empty refreshes stay at 396ms/11;
- `due - 1 microsecond` skips and `due` requests;
- jumping directly two seconds past due requests immediately rather than decrementing stale callback debt;
- after every result, `metricsFor` reports the exact empty count, 3/7/11 skip count, and 132/264/396ms current delay without mutating state;
- activity, reset, remove, and two session IDs remain isolated; removed/unknown sessions report zeroed metrics.

- [ ] **Step 2: Run the deadline test and verify red**

Run from `packages/ianvs_terminal/`:

```bash
flutter test test/terminal_frame_pump_test.dart
```

Expected: compile failure because `TerminalFramePumpPolicy`, `TerminalFramePumpMetrics`, and the deadline-aware method signatures do not exist.

- [ ] **Step 3: Add controller diagnostic tests**

Add focused tests named:

```text
terminal runtime traces skipped ticks and full refresh lifecycle monotonically
terminal runtime resets deadline state after input and resize
```

The first test must observe this event order for a frame-bearing full poll:

```text
poll_tick_skipped
full_poll_requested
refresh_started
frame_taken
frame_applied
refresh_result
```

Assert:

- `refresh_id` is stable across request/start/take/apply/result;
- requested ≤ started ≤ taken ≤ applied;
- `empty_refresh_count`, `backoff_skip_ticks`, `current_delay_micros`, `full_poll_count`, and `hint_poll_count` are present on every event;
- the maximum empty result reports 396000µs, 11 skips, and `hint_poll_count == 0`;
- an empty pull emits take/result but no apply;
- existing frame-before-event behavior and the input-burst cooldown call counts stay unchanged.

The second test covers input and resize, which runtime already owns. Phase 2 adds separate focus and activation wiring coverage.

- [ ] **Step 4: Run controller diagnostics and verify red**

Run from `packages/ianvs_terminal/`:

```bash
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime traces skipped ticks and full refresh lifecycle monotonically"
```

Expected: FAIL because none of the lifecycle diagnostic events or monotonic trace fields exist.

- [ ] **Step 5: Add real PTY four-second-idle FIFO baselines for three states**

Add three tests using one shared FIFO helper:

```text
real PTY active wake baseline after four seconds child idle
real PTY background deadline wake baseline after four seconds child idle
real PTY maximum backoff wake baseline after four seconds child idle
```

Child script contract:

```sh
printf 'idle-ready\n'
sleep 4
: > "$IDLE_DONE_FILE"
IFS= read -r token < "$WAKE_FIFO"
printf 'idle-wake:%s\n' "$token"
```

Rules:

- The fixed four-second child sleep exists only to manufacture real PTY idle.
- The test does not sleep to trigger or observe output.
- Every test first condition-polls `IDLE_DONE_FILE`, records the latest session `refresh_id` as a history marker, and then accepts only a newer diagnostic that is still the latest event for that session. Historical 132/264/396ms events never satisfy state preparation.
- The active case calls `runtime.sendInput(sessionId, Uint8List(0))` after the four-second idle, then waits for a newer latest result whose current delay is 33ms and whose skip count is zero before signaling FIFO. Its 33ms nominal target is reported and its real-PTY hard ceiling is ≤250ms.
- The background-deadline case also performs the empty synthetic reset after the four-second idle, then waits through the new schedule until the newer latest result reports current delay 264ms and 7 skips. It signals FIFO immediately inside that current 264ms window, records the raw elapsed value, and asserts the real-PTY hard ceiling of ≤750ms.
- The maximum-backoff case does not reset. After recording the post-idle history marker, it waits for a still-current newer result with delay 396ms and 11 skips, then signals FIFO. It records the raw elapsed value, separately verifies the deterministic policy cap is 396ms, and asserts the real-PTY hard ceiling of ≤750ms.
- Only after the state condition is true does each test start a `Stopwatch` and write a unique token to the FIFO.
- It condition-pumps the frame at 5ms until the token appears.
- The existing 20-second deadline remains only the total failure guard.
- `_pumpRealPtyApp` receives optional `runtimeEvents` and overrides the verified `terminalGraphicsTraceSinkProvider`.

- [ ] **Step 6: Run the real PTY test and verify red**

Run from the repository root:

```bash
PROFILE=debug tools/build_core.sh
```

Run from `example/`:

```bash
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/real_pty_acceptance_test.dart --plain-name "real PTY active wake baseline after four seconds child idle"
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/real_pty_acceptance_test.dart --plain-name "real PTY background deadline wake baseline after four seconds child idle"
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/real_pty_acceptance_test.dart --plain-name "real PTY maximum backoff wake baseline after four seconds child idle"
```

Expected: FAIL while waiting for missing state diagnostics; no test-side settling sleep is added.

### Task 2: Implement Phase 1 and commit it independently

**Files:**
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart:297-300,388-405,790-914,1043-1110,1818-1875`
- Modify: the three Phase 1 test files above

- [ ] **Step 1: Implement the deadline primitive**

Use a supplied monotonic `Duration now`; store per-session empty count, next due time, interval index, and skip count. Preserve the existing method names `shouldSkipPollingRefresh`, `recordRefreshResult`, `reset`, and `remove`, and add the read-only `metricsFor`. The only idle interval list is:

```dart
const <Duration>[
  Duration(milliseconds: 132),
  Duration(milliseconds: 264),
  Duration(milliseconds: 396),
];
```

`recordRefreshResult(hadActivity: true)` and `reset` schedule the active 33ms interval and clear the idle interval index. `shouldSkipPollingRefresh` compares `now` with the stored deadline and never decrements skip ticks. `metricsFor` returns a zeroed `TerminalFramePumpMetrics` for unknown/removed sessions.

- [ ] **Step 2: Run deadline tests and verify green**

Run from `packages/ianvs_terminal/`:

```bash
flutter test test/terminal_frame_pump_test.dart
```

Expected: PASS with the exact 132/264/396ms and 3/7/11 sequence.

- [ ] **Step 3: Instrument the existing runtime without reordering work**

Add `Stopwatch()..start()` as the monotonic source. Add per-session trace state and counters. Instrument only around existing boundaries:

- request metadata is captured before calling the existing request scheduler;
- start metadata is captured immediately after `markRefreshing`;
- take metadata is captured immediately after `_takeFrameDiff`;
- apply metadata is captured after `viewport.updateFrame` and before the existing frame event;
- result metadata is emitted where `_recordPollingRefreshResult` already runs.

Pending request metadata must survive cooldown and active-refresh queueing, but it must not change scheduler decisions. The existing `_refreshSessionOnce`, `_refreshSessionDraining`, `_eventsDelayFrame`, and event processing branches retain their current order.

- [ ] **Step 4: Run controller diagnostics and scheduler regressions**

Run from `packages/ianvs_terminal/`:

```bash
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime traces skipped ticks and full refresh lifecycle monotonically"
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime controller coalesces polling input bursts to 30fps"
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime controller schedules queued polling refresh after async events"
flutter test test/terminal_refresh_scheduler_test.dart
```

Expected: all PASS. The existing backend call-count and queued-refresh assertions remain unchanged.

- [ ] **Step 5: Run the three four-second-idle real PTY baselines**

Run from `example/`:

```bash
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/real_pty_acceptance_test.dart --plain-name "real PTY active wake baseline after four seconds child idle"
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/real_pty_acceptance_test.dart --plain-name "real PTY background deadline wake baseline after four seconds child idle"
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/real_pty_acceptance_test.dart --plain-name "real PTY maximum backoff wake baseline after four seconds child idle"
```

Expected: all PASS. The raw elapsed value is present for every case; active is ≤250ms, and both the 264ms background baseline and exact 396ms maximum-backoff policy are ≤750ms in real-PTY integration.

- [ ] **Step 6: Check Phase 1 scope and commit**

Run the full terminal package gate from `packages/ianvs_terminal/`:

```bash
flutter analyze --fatal-infos
flutter test
```

Run the full headless example test gate from `example/`:

```bash
flutter analyze --fatal-infos
flutter test
```

Run the repository's existing non-GUI verification script from the repository root. This deliberately skips only the macOS GUI integration block; the three focused real-PTY tests already ran in Step 5:

```bash
VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION=1 VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 ./tools/verify_flutter_terminal.sh
```

Expected: analysis, all package/example tests, documentation contracts, smoke benchmark, and the non-GUI repository verification PASS.

Run from the repository root:

```bash
git diff --check
git diff --exit-code -- native/core/src native/core/proto packages/ianvs_pty packages/ianvs_terminal/lib/src/proto
```

Expected: both commands succeed and the second prints nothing.

```bash
git add packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart
git add packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart
git add packages/ianvs_terminal/test/terminal_frame_pump_test.dart
git add packages/ianvs_terminal/test/terminal_runtime_controller_test.dart
git add example/integration_test/real_pty_acceptance_test.dart
git commit -m "fix: bound and trace idle terminal refreshes"
```

Expected: a Phase 1-only commit with no native, frame JSON, or protobuf change.

## Phase 2 — Independent adaptive policy and optional refresh hint

### Task 3: Test the independent four-class policy before runtime wiring

**Files:**
- Create: `packages/ianvs_terminal/test/terminal_refresh_policy_test.dart`
- Create: `packages/ianvs_terminal/lib/src/runtime/terminal_refresh_policy.dart`

- [ ] **Step 1: Write failing classification and scheduling tests**

Tests target this exact interface:

```dart
final class TerminalRefreshPolicy {
  TerminalRefreshPolicy({
    required Duration pollInterval,
    required Duration interactiveGrace,
    required Duration streamingGap,
    required Duration streamingGrace,
    required TerminalFramePumpPolicy fallbackPolicy,
  });

  TerminalRefreshDecision decisionForTick(
    String sessionId, {
    required Duration now,
    required bool? hintReady,
  });

  void recordFullPollRequest(String sessionId);
  void recordInput(String sessionId, {required Duration now});
  void recordFocus(String sessionId, {required Duration now, required bool focused});
  void recordResize(String sessionId, {required Duration now});
  void recordActivation(String sessionId, {required Duration now, required bool active});
  TerminalRefreshResult recordRefreshResult(
    String sessionId, {
    required Duration now,
    required bool receivedFrame,
    required int eventCount,
    required TerminalFrameModes modes,
  });
  TerminalRefreshSnapshot snapshot(String sessionId, {required Duration now});
  void remove(String sessionId);
}

final class TerminalRefreshSnapshot {
  const TerminalRefreshSnapshot({
    required this.refreshClass,
    required this.pumpMetrics,
    required this.hintPollCount,
    required this.fullPollCount,
  });

  final TerminalRefreshClass refreshClass;
  final TerminalFramePumpMetrics pumpMetrics;
  final int hintPollCount;
  final int fullPollCount;
}
```

Assert all cases:

- unknown activation defaults to active and eventually becomes `idle`, never `background`;
- recent input enters `interactive` for exactly 500ms and resets fallback;
- focus gain enters `interactive`; focus loss allows grace expiry but does not background the session;
- resize and activation each reset grace/deadline;
- explicit inactive enters `background`, explicit active re-enters `interactive`;
- two frame results ≤100ms apart enter `streaming` for 250ms;
- a background stream becomes `streaming` then returns to `background`;
- active alternate screen stays `interactive`;
- active `mouseMode != 'off'` stays `interactive`;
- background alternate screen/mouse remains `background` unless frame cadence independently qualifies as streaming;
- `interactive` and `streaming` request every 33ms;
- `background` and `idle` still honor 132/264/396ms fallback;
- `hintReady: null` means no hint read occurred because the capability is unsupported or disabled; `false` means a supported hint was actually read and was clean; only non-null values increment `hintPollCount`;
- `hintReady: true` requests immediately in every class but does not itself change class.

- [ ] **Step 2: Run the new policy test and verify red**

Run from `packages/ianvs_terminal/`:

```bash
flutter test test/terminal_refresh_policy_test.dart
```

Expected: compile failure because `terminal_refresh_policy.dart` and its types do not exist.

- [ ] **Step 3: Implement only the policy and verify green**

Implement the priority table and exact durations:

```dart
pollInterval: Duration(milliseconds: 33)
interactiveGrace: Duration(milliseconds: 500)
streamingGap: Duration(milliseconds: 100)
streamingGrace: Duration(milliseconds: 250)
```

The policy owns classification state and delegates background/idle due checks to `TerminalFramePumpPolicy.shouldSkipPollingRefresh`, then includes `metricsFor` in `TerminalRefreshSnapshot`. The snapshot extends Phase 1 metrics with `hintPollCount` and `fullPollCount`; it is read-only and is the sole source for those diagnostic fields. The policy does not call timers, backend methods, scheduler methods, or event handlers.

When a supported backend is present, the runtime reads the advisory hint on the existing 33ms tick and passes `true` or `false`; otherwise it passes `null`. A true hint selects `native_hint` as the request reason even when a full deadline is simultaneously due. A false hint never postpones that due full poll. Both outcomes feed the existing cooldown, queue/deduplication, frame-before-event decision, and event-processing path without adding a second scheduler or changing order.

Run from `packages/ianvs_terminal/`:

```bash
flutter test test/terminal_refresh_policy_test.dart
```

Expected: PASS for every class, mode, grace, and reset assertion.

### Task 4: Test and implement the optional native hint

**Files:**
- Modify: `native/core/src/session.rs:1057-1085,1174-1275,1592-1621,4742-4781`
- Modify: `native/core/src/ffi.rs:194-271`
- Test: `native/core/tests/session_test.rs`
- Modify: `packages/ianvs_pty/lib/src/native_pty_backend.dart:8-185,320-430,646-845`
- Test: `packages/ianvs_pty/test/native_pty_backend_test.dart`

- [ ] **Step 1: Write failing Rust tests**

Reserve `1 << 0` as `REFRESH_HINT_FRAME_DIRTY`. Assert:

- new session dirty bit is set;
- two reads return the same bit and do not consume a frame;
- after frame drain, condition-poll until clear;
- after real PTY bytes, condition-poll until set;
- invalid session FFI returns zero.

The condition loop has a two-second deadline and a short poll step; no assertion depends on a fixed settling sleep.

- [ ] **Step 2: Run Rust tests and verify red**

Run from the repository root:

```bash
cargo test --manifest-path native/core/Cargo.toml refresh_hint -- --nocapture
```

Expected: compile failure because the constant, session function, and FFI symbol are absent.

- [ ] **Step 3: Implement the allocation-free hint**

Add:

```rust
pub const REFRESH_HINT_FRAME_DIRTY: u32 = 1 << 0;
pub fn refresh_hint_flags(&self) -> u32;
pub fn refresh_hint_flags(session_id: u64) -> Result<u32, SessionError>;

#[unsafe(no_mangle)]
pub extern "C" fn ianvs_session_refresh_hint(session_id: u64) -> u32;
```

The instance method only performs `dirty.load(Ordering::SeqCst)`. It does not swap, lock state, advance animations, poll a child, drain events, or allocate.

- [ ] **Step 4: Run Rust tests and verify green**

```bash
cargo test --manifest-path native/core/Cargo.toml refresh_hint -- --nocapture
```

Expected: all refresh-hint tests PASS.

- [ ] **Step 5: Write failing Dart optional-capability tests**

Target additive interfaces:

```dart
abstract interface class PtyRefreshHintBindings {
  bool get supportsRefreshHints;
  int sessionRefreshHintFlags(int sessionId);
}

abstract interface class PtySessionRefreshHintBackend {
  bool get supportsRefreshHints;
  int refreshHintFlags(String sessionId);
}

abstract final class PtyRefreshHintFlags {
  static const int none = 0;
  static const int frameDirty = 1 << 0;
}
```

Assert an optional binding forwards bit 0; existing `_NoopPtyBindings implements PtyBindings` still compiles; missing symbol reports unsupported and zero flags.

- [ ] **Step 6: Run Dart backend tests and verify red**

Run from `packages/ianvs_pty/`:

```bash
dart test test/native_pty_backend_test.dart -n "refresh hint"
```

Expected: compile failure because the optional interfaces do not exist.

- [ ] **Step 7: Implement optional lookup and verify green**

Use optional lookup for `ffi.Uint32 Function(ffi.Uint64)`. `NativePtyBindings` implements the optional binding interface and `NativePtyBackend` implements the optional backend interface. Do not edit required members of `PtyBindings` or `PtySessionBackend`.

Run from `packages/ianvs_pty/`:

```bash
dart test test/native_pty_backend_test.dart -n "refresh hint"
dart test test/native_pty_backend_test.dart -n "planned low-level API"
```

Expected: PASS; the original low-level API fake requires no new method.

### Task 5: Wire class signals, hints, and diagnostics without scheduling reorder

**Files:**
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- Test: `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
- Modify: `example/lib/features/sessions/session_controller.dart:489-573,625-651`
- Test: `example/test/sessions/session_controller_test.dart`
- Modify: `example/lib/features/shell/shell_screen_state_sessions.dart:175-220`
- Test: `example/test/widget_test.dart`

- [ ] **Step 1: Write failing runtime policy-wiring tests**

Add tests named:

```text
terminal runtime classifies recent input and continuous frames
terminal runtime classifies active alternate screen and mouse tracking
terminal runtime records focus resize and activation resets
terminal runtime wakes idle output from a refresh hint
terminal runtime disables a failing hint and keeps full fallback
```

Assert:

- `sendInput` reports `interactive`;
- two frame-bearing refreshes within 100ms report `streaming`;
- active alternate-screen and mouse frames report `interactive`;
- input, focus gain, resize, and activation reset empty count to zero and skip ticks to zero;
- idle hint request occurs on the next 33ms tick and reports `request_reason == native_hint`;
- unsupported hint still reaches a 396ms full poll;
- throwing hint emits one backend error, does not count the failed sample or perform later hint reads, and falls back;
- diagnostics include all six event names, all counters, class, and ordered lifecycle timestamps;
- protobuf-capable backend still calls protobuf and does not read JSON.

- [ ] **Step 2: Run focused runtime tests and verify red**

Run from `packages/ianvs_terminal/`:

```bash
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime classifies recent input and continuous frames"
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime wakes idle output from a refresh hint"
```

Expected: FAIL because runtime does not own `TerminalRefreshPolicy` or read optional hints.

- [ ] **Step 3: Integrate the policy in place of direct deadline decisions**

Add public runtime signals:

```dart
void setSessionActive(String sessionId, {required bool active});
void setSessionFocused(String sessionId, {required bool focused});
```

Wire existing methods:

- every successful `sendInput` call → `recordInput` (unit coverage uses non-empty input; the real-PTY baseline may use an empty synthetic reset without writing child input);
- successful resize → `recordResize`;
- frame result and modes → `recordRefreshResult`;
- close → policy removal.

On every existing 33ms tick:

1. when supported and enabled, read `refreshHintFlags(sessionId)` and pass a non-null `hintReady`; otherwise pass null;
2. ask `TerminalRefreshPolicy.decisionForTick`, which decides whether a full poll is needed and increments `hint_poll_count` only for a non-null hint input;
3. emit `poll_tick_skipped` or retain the first accepted `full_poll_requested` trace; the deduplicated accepted-request boundary calls `recordFullPollRequest(sessionId)` exactly once, so creation, explicit requests, cooldown, and in-flight coalescing increment `full_poll_count` without double-counting queued work;
4. call the existing `_requestRefreshSession` path unchanged.

On first hint exception, emit one `TerminalSessionBackendErrorEvent(operation: 'refreshHintFlags')`, disable hint reads for that session, and continue deadline fallback.

- [ ] **Step 4: Wire actual activation and focus providers**

In `SessionController.createSession`, `splitSession`, and `activateSession`, capture the previous active session. After state changes:

- call `setSessionActive(previous, active: false)` when it differs from the next session;
- call `setSessionActive(next, active: true)`.

In `_handleTerminalFocusChanged`, after verifying the session is active and before the existing UI early return, call:

```dart
ref
    .read(terminalRuntimeControllerProvider)
    .setSessionFocused(sessionId, focused: focusNode.hasFocus);
```

These are the verified production providers; no new provider is introduced.

- [ ] **Step 5: Add activation and focus wiring assertions**

In `example/test/sessions/session_controller_test.dart`, activate two real fake-backend sessions and assert diagnostics transition the old session to `background` and the new session to `interactive`.

In `example/test/widget_test.dart`, focus the active terminal, move focus to an existing shell control, and assert refresh diagnostics first show `interactive`, then allow grace expiry without misclassifying the still-active session as `background`.

- [ ] **Step 6: Run package and example focused tests**

Run from `packages/ianvs_terminal/`:

```bash
flutter test test/terminal_refresh_policy_test.dart
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime classifies recent input and continuous frames"
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime classifies active alternate screen and mouse tracking"
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime records focus resize and activation resets"
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime wakes idle output from a refresh hint"
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime disables a failing hint and keeps full fallback"
flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal runtime prefers protobuf frame bytes when available"
flutter test test/terminal_refresh_scheduler_test.dart
```

Expected: all PASS; existing cooldown, queue, frame/event order, and protobuf call-count tests remain unchanged.

Run from `example/`:

```bash
flutter test test/sessions/session_controller_test.dart --plain-name "activation updates terminal refresh foreground classes"
flutter test test/widget_test.dart --plain-name "terminal focus updates refresh policy without backgrounding the active session"
```

Expected: both PASS using the existing providers.

### Task 6: Repeat active, background, and maximum-idle real PTY cases with hint and masked fallback

**Files:**
- Modify: `example/integration_test/real_pty_acceptance_test.dart`

- [ ] **Step 1: Define the Phase 2 real PTY matrix**

Use the same child script:

```sh
printf 'idle-ready\n'
sleep 4
: > "$IDLE_DONE_FILE"
IFS= read -r token < "$WAKE_FIFO"
printf 'idle-wake:%s\n' "$token"
```

Create six named cases from one helper; every child executes the four-second script before the test conditionally signals FIFO:

```text
real PTY interactive hint path after four seconds idle
real PTY background hint path after four seconds idle
real PTY maximum idle hint path after four seconds idle
real PTY interactive masked-hint path after four seconds idle
real PTY background masked-hint path after four seconds idle
real PTY maximum idle masked-hint path after four seconds idle
```

Prepare each state only after `IDLE_DONE_FILE` exists:

- record the latest session `refresh_id` as a history marker before changing or observing state; the shared helper must match only a newer event that is still the latest event and whose embedded `TerminalRefreshSnapshot` fields match the requested class/delay;
- interactive: call `runtime.setSessionFocused(sessionId, focused: true)`, wait for a newer current snapshot with `refresh_class == interactive`, 33ms current delay, and zero skips, then signal;
- background: call `runtime.setSessionActive(sessionId, active: false)`, wait for a newer current snapshot with `refresh_class == background`, 264ms current delay, and 7 skips, then signal;
- maximum idle: leave the default-active session quiet and wait for a newer current snapshot with `refresh_class == idle`, 396ms current delay, and 11 skip ticks, then signal.

For all hint-enabled cases assert:

- the test log records the raw elapsed microseconds and whether the nominal ≤100ms target was met;
- token appears within the debug/release real-PTY hard ceiling of 250ms;
- the request carries `request_reason == native_hint` (hint takes precedence when an active deadline is simultaneously due);
- `hint_poll_count > 0` and `full_poll_count` increments once;
- diagnostics retain the prepared `refresh_class` at request time;
- requested ≤ started ≤ taken ≤ applied;
- `idle-ready` is observed before `IDLE_DONE_FILE`; the child script's fixed `sleep 4` is the source of the genuine idle interval, so delayed UI observation is not misused as a four-second stopwatch assertion.

- [ ] **Step 2: Add the three hint-masked cases**

Override the verified `ptySessionBackendProvider` with a test-only delegating backend that forwards the real Native backend's base and protobuf methods but does not implement `PtySessionRefreshHintBackend`.

Assert:

- interactive masked path records raw elapsed time and remains ≤250ms through its 33ms full polling;
- background masked path reaches the nominal fallback, records raw elapsed time, and is ≤750ms in debug and release integration;
- maximum-idle masked path reports `idle_deadline`, 396ms, 11 skips, records raw elapsed time, and is ≤750ms in debug and release integration;
- all three have `hint_poll_count == 0` and no `native_hint` request;
- debug and final release-gate invocations both use the same configured 750ms ceiling for background and maximum-idle fallback.

Define integration hard ceilings as:

```dart
const _refreshHintTargetMs = 100;
const _refreshHintLimitMs = int.fromEnvironment(
  'IANVS_REFRESH_HINT_LIMIT_MS',
  defaultValue: 250,
);
const _refreshFallbackLimitMs = int.fromEnvironment(
  'IANVS_REFRESH_FALLBACK_LIMIT_MS',
  defaultValue: 750,
);
```

The shared assertion helper prints `elapsedMicroseconds`, target, and hard limit for passing runs, and repeats those raw values in `expect(..., reason: ...)` for failures.

- [ ] **Step 3: Run both cases red before rebuilding the new native library**

Run from `example/` against the Phase 1 library:

```bash
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/real_pty_acceptance_test.dart --plain-name "real PTY maximum idle hint path after four seconds idle"
```

Expected: FAIL because the Phase 1 library has no hint symbol and cannot emit `native_hint`.

- [ ] **Step 4: Rebuild and run both cases green**

Run from the repository root:

```bash
PROFILE=debug tools/build_core.sh
```

Run the six named cases from `example/`; these two commands exercise the strictest hint and fallback paths, while the four class variants run in the focused example verification from Task 7:

```bash
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/real_pty_acceptance_test.dart --plain-name "real PTY maximum idle hint path after four seconds idle"
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos integration_test/real_pty_acceptance_test.dart --plain-name "real PTY maximum idle masked-hint path after four seconds idle"
```

Expected: both PASS with a recorded raw value, a ≤250ms hint hard ceiling, and a ≤750ms fallback hard ceiling. Trigger and observation are condition-driven; the only fixed four-second wait is inside the child to manufacture idle.

### Task 7: Verify compatibility and commit Phase 2 independently

**Files:**
- All Phase 2 files listed above
- Create: `tools/run_process_group_with_timeout.py`
- Create: `tools/run_release_real_pty_refresh_gate.sh`
- Modify: `test/docs_contract_test.dart`

- [ ] **Step 1: Run full cross-layer verification**

Run the complete native gate from `native/core/`:

```bash
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test -- --test-threads=1
```

Run compatibility diff checks from the repository root:

```bash
git diff --check
git diff --exit-code HEAD^ -- native/core/proto/frame_diff.proto packages/ianvs_terminal/lib/src/proto tools/bench/schemas/terminal_frame_diff.schema.json
```

Run from `packages/ianvs_pty/`:

```bash
dart analyze --fatal-infos
dart test test/native_pty_backend_test.dart
dart test
```

Run from `packages/ianvs_terminal/`:

```bash
flutter analyze --fatal-infos
flutter test test/terminal_frame_pump_test.dart
flutter test test/terminal_frame_diff_corpus_test.dart
flutter test test/terminal_refresh_policy_test.dart
flutter test test/terminal_refresh_scheduler_test.dart
flutter test test/terminal_runtime_controller_test.dart
flutter test
```

Run the changed example modules and then the full headless example suite from `example/`:

```bash
flutter analyze --fatal-infos
flutter test test/sessions/session_controller_test.dart
flutter test test/widget_test.dart
flutter test
```

Run the repository's existing non-GUI verification script from the repository root:

```bash
VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION=1 VERIFY_FLUTTER_TERMINAL_RUN_EXAMPLE_WIDGET_TESTS=1 ./tools/verify_flutter_terminal.sh
```

Expected: Rust format/lint/serial full tests, both Dart/Flutter package analyses and full tests, changed example modules, the full headless example suite, and the non-GUI repository verification all PASS. Diff checks report no whitespace errors and no frame JSON/protobuf schema or generated protobuf changes.

Build and run the complete six-case real-PTY matrix in debug from the repository root and then `example/`:

```bash
PROFILE=debug tools/build_core.sh
```

```bash
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos --dart-define=IANVS_REFRESH_HINT_LIMIT_MS=250 --dart-define=IANVS_REFRESH_FALLBACK_LIMIT_MS=750 integration_test/real_pty_acceptance_test.dart --plain-name "real PTY interactive hint path after four seconds idle"
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos --dart-define=IANVS_REFRESH_HINT_LIMIT_MS=250 --dart-define=IANVS_REFRESH_FALLBACK_LIMIT_MS=750 integration_test/real_pty_acceptance_test.dart --plain-name "real PTY background hint path after four seconds idle"
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos --dart-define=IANVS_REFRESH_HINT_LIMIT_MS=250 --dart-define=IANVS_REFRESH_FALLBACK_LIMIT_MS=750 integration_test/real_pty_acceptance_test.dart --plain-name "real PTY maximum idle hint path after four seconds idle"
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos --dart-define=IANVS_REFRESH_HINT_LIMIT_MS=250 --dart-define=IANVS_REFRESH_FALLBACK_LIMIT_MS=750 integration_test/real_pty_acceptance_test.dart --plain-name "real PTY interactive masked-hint path after four seconds idle"
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos --dart-define=IANVS_REFRESH_HINT_LIMIT_MS=250 --dart-define=IANVS_REFRESH_FALLBACK_LIMIT_MS=750 integration_test/real_pty_acceptance_test.dart --plain-name "real PTY background masked-hint path after four seconds idle"
IANVS_CORE_LIB=../native/core/target/debug/libianvs_core.dylib flutter test -d macos --dart-define=IANVS_REFRESH_HINT_LIMIT_MS=250 --dart-define=IANVS_REFRESH_FALLBACK_LIMIT_MS=750 integration_test/real_pty_acceptance_test.dart --plain-name "real PTY maximum idle masked-hint path after four seconds idle"
```

Expected: all six PASS and print raw elapsed microseconds. Hint cases use a 250ms hard ceiling while reporting the 100ms nominal target; masked fallback cases use a 750ms hard ceiling.

Build the release native library and run the strictest hint plus both delayed fallback release gates:

```bash
PROFILE=release tools/build_core.sh
```

Run from `example/`:

```bash
IANVS_CORE_LIB=../native/core/target/release/libianvs_core.dylib flutter test --release -d macos --dart-define=IANVS_REFRESH_HINT_LIMIT_MS=250 --dart-define=IANVS_REFRESH_FALLBACK_LIMIT_MS=750 integration_test/real_pty_acceptance_test.dart --plain-name "real PTY maximum idle hint path after four seconds idle"
IANVS_CORE_LIB=../native/core/target/release/libianvs_core.dylib flutter test --release -d macos --dart-define=IANVS_REFRESH_HINT_LIMIT_MS=250 --dart-define=IANVS_REFRESH_FALLBACK_LIMIT_MS=750 integration_test/real_pty_acceptance_test.dart --plain-name "real PTY background masked-hint path after four seconds idle"
IANVS_CORE_LIB=../native/core/target/release/libianvs_core.dylib flutter test --release -d macos --dart-define=IANVS_REFRESH_HINT_LIMIT_MS=250 --dart-define=IANVS_REFRESH_FALLBACK_LIMIT_MS=750 integration_test/real_pty_acceptance_test.dart --plain-name "real PTY maximum idle masked-hint path after four seconds idle"
```

Expected: all three PASS, retain the exact 396ms deterministic cap in policy diagnostics, use the same 750ms fallback ceiling as debug, and print raw elapsed microseconds.

- [ ] **Step 2: Verify base interfaces are unchanged**

Run from the repository root:

```bash
git diff HEAD^ -- packages/ianvs_pty/lib/src/native_pty_backend.dart
rg -n "abstract class PtyBindings|abstract class PtySessionBackend|abstract interface class PtyRefreshHintBindings|abstract interface class PtySessionRefreshHintBackend" packages/ianvs_pty/lib/src/native_pty_backend.dart
```

Expected: the diff shows only additive optional interfaces and Native implementation support; the required member lists inside `PtyBindings` and `PtySessionBackend` are unchanged.

- [ ] **Step 3: Commit Phase 2**

```bash
git add docs/superpowers/plans/2026-07-10-terminal-refresh-and-idle-wake.md
git add native/core/src/session.rs
git add native/core/src/ffi.rs
git add native/core/tests/session_test.rs
git add packages/ianvs_pty/lib/src/native_pty_backend.dart
git add packages/ianvs_pty/test/native_pty_backend_test.dart
git add packages/ianvs_terminal/lib/ianvs_terminal.dart
git add packages/ianvs_terminal/lib/src/runtime/terminal_refresh_policy.dart
git add packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart
git add packages/ianvs_terminal/test/terminal_refresh_policy_test.dart
git add packages/ianvs_terminal/test/terminal_runtime_controller_test.dart
git add example/lib/features/sessions/session_controller.dart
git add example/lib/features/shell/shell_screen_state_sessions.dart
git add example/test/sessions/session_controller_test.dart
git add example/test/shell/shell_screen_phase1b_test.dart
git add example/test/shell/shell_screen_phase4_test.dart
git add example/test/support/fake_pty_backend.dart
git add example/test/widget_test.dart
git add example/integration_test/real_pty_acceptance_test.dart
git add test/docs_contract_test.dart
git add tools/run_process_group_with_timeout.py
git add tools/run_release_real_pty_refresh_gate.sh
git commit -m "feat: adapt terminal refreshes with optional native hints"
```

Expected: one Phase 2 commit on top of the Phase 1 commit.

## Final acceptance checklist

- [ ] Phase 1 deadline sequence is exactly 132/264/396ms and 3/7/11 skipped ticks.
- [ ] `terminal_refresh_policy.dart` independently implements all four refresh classes.
- [ ] Unknown activation defaults active.
- [ ] Recent input, continuous frames, explicit active/background, alternate screen, mouse tracking, grace expiry, focus, resize, and activation have direct tests.
- [ ] Hint and full fallback scheduling follow the class table.
- [ ] Cooldown, queueing, frame/event order, and async event tests remain unchanged and green.
- [ ] Diagnostics cover skipped tick, request, start, take, apply, and result with all counters and monotonic timestamps.
- [ ] Real PTY hint and masked-fallback children each experience four seconds of genuine idle before condition-driven FIFO signaling.
- [ ] Deterministic no-hint policy tests cap at exactly 396ms; real-PTY test logs record raw values; hint nominal target is ≤100ms with a ≤250ms hard ceiling; debug and release fallback hard ceilings are both ≤750ms.
- [ ] Frame JSON/protobuf schemas and generated protobuf files are unchanged.
- [ ] `PtySessionBackend` and `PtyBindings` required members are unchanged.
