# Terminal Render, Graphics Cache, and Cursor Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce steady-state terminal paint allocation churn, stop redundant graphics-cache synchronization, and use a measured A/B experiment to decide whether cursor blinking should move to an isolated production overlay.

**Architecture:** Phase 3 keeps the current renderer and row-picture cache, reuses mutable paint/scratch objects, emits the required operation counters, and evaluates before/after profiles with an automated immutable gate. Phase 4 derives ordered graphics and live-asset revisions in `TerminalViewportController`, then uses only viewport-private identity/revision state to skip redundant cache synchronization; the standalone `TerminalGraphicsSync` boundary remains Phase 6 work. Phase 5 first adds the `cursor_blink_idle_profile` classification, then uses an internal test/profile-only mode seam for an A/B experiment; a failed gate removes every overlay production change before commit, while a passing gate may enable the overlay without adding any public constructor parameter or export.

**Tech Stack:** Dart 3, Flutter render objects and widget tests, `dart:ui` pictures, `ChangeNotifier`/`ValueNotifier`, existing terminal graphics cache, Flutter profile integration tests, existing NDJSON/CSV benchmark reports.

---

## File Structure

### Phase 3: paint reuse, debug gating, and paint metrics

- Modify `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`
  - Reuse `Paint` and scratch collections, avoid row-cache pruning on non-frame paints, gate debug snapshots with `kDebugMode`, and emit paint-cause metrics without depending on debug collections.
- Modify `packages/ianvs_terminal/test/terminal_viewport_render_test.dart`
  - Add deterministic red/green coverage for non-frame paint metrics and preserve existing debug getter behavior in debug tests.
- Create `tools/bench/src/terminal_render_phase3_gate.dart`
  - Compare paired target-label/repeat summaries and apply the fixed Phase 3 median thresholds.
- Create `tools/bench/analysis/terminal_render_phase3_gate.dart`
  - Scan `$inputRoot/${device.targetLabel}` directories, write machine-readable gate output, and return non-zero when the gate fails.
- Create `tools/bench/test/terminal_render_phase3_gate_test.dart`
  - Cover passing, timing-regression, missing-metric, hash-mismatch, target-mismatch, and repeat-count failures.

### Phase 4: graphics revisions and cache synchronization

- Modify `packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
  - Give `TerminalGraphicPlacement` value equality across every render-affecting field.
- Modify `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
  - Add `graphicsRevision`, `graphicsAssetRevision`, cached live asset keys, and revision-driven `_syncGraphicsCache` using viewport-private identity/revision fields only.
- Modify `packages/ianvs_terminal/lib/src/terminal/terminal_graphics_cache.dart`
  - Emit a benchmark-only `cache_sync` diagnostic when a sink is present.
- Modify `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
  - Test ordered placement revisions, live-asset revisions, authoritative empty delta behavior, duplicate assets, and every placement field.
- Modify `packages/ianvs_terminal/test/terminal_viewport_render_test.dart`
  - Test initial/cache/controller forced sync and skipped sync for unchanged live assets.

### Phase 5: cursor overlay experiment and production decision

- Create conditionally `packages/ianvs_terminal/lib/src/terminal/render_terminal_cursor_overlay.dart`
  - Own the cached cursor picture source and isolated repaint-boundary render object during the experiment; retain it only when the fixed gate passes.
- Create conditionally `packages/ianvs_terminal/lib/src/terminal/terminal_cursor_overlay_experiment.dart`
  - Provide a package-internal, non-exported `InheritedWidget` mode seam used only by package tests and the profile harness; delete it on a no-go result.
- Modify `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`
  - Publish a cached cursor visual, draw it in the legacy surface when selected, and retain current cursor geometry/debug contracts.
- Modify `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
  - Keep the public constructor unchanged, read only the internal experiment scope, switch blink ticks from viewport `setState` to a notifier in overlay mode, and place the overlay at the current cursor z-order.
- Modify `packages/ianvs_terminal/test/terminal_viewport_render_test.dart`
  - Add surface-versus-overlay repaint isolation, pixel parity, wide-cell, DPR, and graphics-layer tests.
- Modify `example/test/terminal/render_terminal_viewport_test.dart`
  - Run focused blink/focus/scrollback/out-of-bounds/disposal lifecycle checks against overlay mode.
- Modify `example/test/terminal_input_controller_test.dart`
  - Verify IME composing text and caret geometry across overlay blink frames.
- Modify `example/integration_test/terminal_render_profile_test.dart`
  - Add the base `cursor_blink_idle_profile` classification, plus internal paired surface/overlay variants used only for the experiment.
- Modify `example/lib/benchmarks/terminal_render_profile_report.dart`
  - Separate terminal-surface paint events from cursor-overlay paint events and summarize non-frame repaint counts.
- Create `example/lib/benchmarks/terminal_cursor_overlay_gate.dart`
  - Evaluate exact repeat-count, repaint-isolation, p50/p95 timing, layer-count, cursor-picture memory, paint-bounds, and missed-vsync thresholds and write `cursor_overlay_gate.json`.
- Modify `example/test/benchmarks/terminal_render_profile_report_test.dart`
  - Cover the new cursor event summary fields.
- Create `example/test/benchmarks/terminal_cursor_overlay_gate_test.dart`
  - Cover eligible and ineligible A/B result sets.
- Create `docs/evidence/2026-07-10-cursor-overlay/decision.md`
  - Record the locked thresholds, evaluator hash, target labels, command, result, reason codes, layer/memory cost, and go/no-go decision.
- Create `docs/evidence/2026-07-10-cursor-overlay/cursor_overlay_gate.json`
  - Commit the exact machine-readable result copied from the dynamically discovered target-label directory.

## Fixed Decisions and Invariants

- Rust and protobuf schemas remain unchanged. Every incoming snapshot or delta already carries an authoritative complete `graphics` list; an empty delta list clears graphics.
- `graphicsRevision` compares the ordered normalized placements. Order remains significant because equal-z placements are painted in list order.
- `graphicsAssetRevision` compares the deduplicated `TerminalGraphicAssetKey(id, version)` set. Geometry-only changes increment `graphicsRevision` but do not synchronize the cache.
- Initial mount, controller replacement, and cache replacement always force one cache sync, even when revisions are both zero.
- Debug getters keep their current behavior in debug-mode tests. In profile/release mode, debug-only row text/index/resolved-cell snapshots are not maintained; benchmark events use independent integer counters.
- Every render benchmark event contains `rows_visited`, `picture_draw_count`, and `debug_collection_enabled`. Extra metrics may be added, but these exact names are never replaced by aliases.
- Paint instrumentation remains disabled when `benchmarkEventSink` is null. Allocation measurements and timing measurements are separate runs because `Stopwatch` and event maps perturb allocation counts.
- Cursor overlay mode preserves the complete current layer order: negative-z graphics, terminal text surface, cursor, inline images, non-negative-z graphics, timestamps, scrollbar, composing overlay, link tooltip.
- Phase 4 does not create or reference a standalone `TerminalGraphicsSync`; only `_TerminalViewportState` private controller identity, cache identity, and last asset revision drive synchronization. The standalone object belongs to Phase 6.
- Phase 5 adds no parameter to `TerminalViewport`, no public render-mode enum, and no export from `ianvs_terminal.dart` or `ianvs_terminal_debug.dart`. The experiment selector is package-internal and profile/test-only.
- Phase 5 thresholds are fixed before the first A/B profile. Once profile output exists, changing a threshold or its evaluator invalidates that output; the result may not be made eligible by editing the gate.
- The 650 ms blink interval and existing focus/hide/show/scrollback semantics do not change in these phases.
- No phase starts until the preceding phase has a clean focused test result and its own commit.

---

### Task 1 / Phase 3: Reuse Main Paint State and Separate Debug From Metrics

**Files:**
- Modify: `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart:119-530`
- Modify: `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart:577-727`
- Modify: `packages/ianvs_terminal/test/terminal_viewport_render_test.dart:70-103`
- Modify: `packages/ianvs_terminal/test/terminal_viewport_render_test.dart:2280-2442`

- [ ] **Step 1: Capture the pre-change profile baseline**

Run from repository root:

```bash
dart run tools/bench/runner/flutter_profile_matrix_runner.dart \
  --output /tmp/ianvs-terminal-render-phase3-before \
  --workloads scrollback_heavy_profile \
  --repeats 3 \
  --frame-count 96 \
  --device macos \
  --require-target-count 1
```

Expected: exit 0; all `correctness.json` files contain `"hash_match": true`; each repeat contains `flutter_render.ndjson`, `flutter_frame_timing.ndjson`, and `summary.csv`.

- [ ] **Step 2: Write the failing non-frame paint metric test**

Add a widget test named `render viewport reports non-frame paints without stale dirty rows`. Build a two-row snapshot through the existing `_RenderViewportHarness`, clear the event sink after the initial paint, repump the same controller with only `cursorVisible` changed, and assert exactly one `ianvs-bench-flutter-render-v1` event with:

```dart
expect(event['paint_kind'], 'non_frame');
expect(event['has_new_frame'], isFalse);
expect(event['dirty_row_count'], 0);
expect(event['rows_visited'], 2);
expect(event['picture_draw_count'], 2);
expect(event['row_visual_rebuild_count'], 0);
expect(event['row_cache_hits'], 2);
expect(event['row_cache_misses'], 0);
expect(event['debug_collection_enabled'], isTrue);
```

Also assert `debugLastPaintedRowTexts == <String>['alpha', 'beta']` and `debugLastRebuiltRowIndexes` is empty so debug-mode diagnostics remain intact.

- [ ] **Step 3: Run the test and verify red**

Run:

```bash
cd packages/ianvs_terminal && flutter test test/terminal_viewport_render_test.dart --plain-name "render viewport reports non-frame paints without stale dirty rows"
```

Expected: FAIL because `paint_kind`, `has_new_frame`, `rows_visited`, `picture_draw_count`, and `debug_collection_enabled` are absent, and the old dirty-row calculation reports the prior frame's dirty range.

- [ ] **Step 4: Add reusable paint and scratch state**

Add `package:flutter/foundation.dart` and these exact responsibilities to `RenderTerminalViewport`:

```dart
final Paint _canvasPaint = Paint()..isAntiAlias = false;
final Paint _rowBackgroundPaint = Paint()..isAntiAlias = false;
final Paint _selectionPaint = Paint()..isAntiAlias = false;
final Paint _cursorPaint = Paint()..isAntiAlias = false;
final Paint _searchFillPaint = Paint()..isAntiAlias = true;
final Paint _searchBorderPaint = Paint()
  ..style = PaintingStyle.stroke
  ..isAntiAlias = true;
final Paint _hyperlinkPaint = Paint()..isAntiAlias = true;
final Set<int> _activeRowIndexesScratch = <int>{};
final List<String> _debugPaintedRowTextsScratch = <String>[];
final List<int> _debugRebuiltRowIndexesScratch = <int>[];
Rect _localPaintBounds = Rect.zero;
```

Update `performLayout` to assign `_localPaintBounds = Offset.zero & size`. In `paint`, mutate paint colors immediately before each draw instead of constructing new `Paint` objects. Keep custom-geometry paints inside row-picture rebuilds because they are not steady-state paint allocations.

- [ ] **Step 5: Gate debug state and remove non-frame cache pruning**

Use `kDebugMode` as the only debug snapshot gate. Clear/fill `_debugPaintedRowTextsScratch`, `_debugRebuiltRowIndexesScratch`, resolved-style/cell maps, search rects, hyperlink rects, and `_rowPictureBuildCounts` only when debug collection is enabled. Keep integer `rowsVisited`, `pictureDrawCount`, `rowCacheHits`, and `rowCacheMisses` for all benchmarked paints. Increment `rowsVisited` once for every row reached by the main paint loop and increment `pictureDrawCount` only when `canvas.drawPicture(rowVisual.picture)` executes.

Compute `hasNewFrame` before scratch setup. Populate `_activeRowIndexesScratch` and call `_pruneInactiveRowCaches` only when `hasNewFrame` is true. Reuse the scratch set and remove inactive visual rows with `Map.removeWhere`, disposing each removed `ui.Picture` before returning `true`.

Change `cursorVisible` to return without `markNeedsPaint` when the value is unchanged.

- [ ] **Step 6: Emit corrected paint metrics**

Extend `_emitBenchmarkPaintEvent` with these parameters and fields:

```dart
required bool hasNewFrame,
required int rowsVisited,
required int pictureDrawCount,

'paint_kind': hasNewFrame ? 'frame' : 'non_frame',
'has_new_frame': hasNewFrame,
'rows_visited': rowsVisited,
'picture_draw_count': pictureDrawCount,
'debug_collection_enabled': kDebugMode,
```

Change `_benchmarkDirtyRowCount` to accept `hasNewFrame` and return `0` immediately when false. Do not read debug lists to construct benchmark counts.

- [ ] **Step 7: Write and implement the automated Phase 3 gate**

Write `tools/bench/test/terminal_render_phase3_gate_test.dart` first. Its fixtures use target labels `macos-darwin-arm64` and `macos-darwin-x64`, three repeats each, and assert these immutable rules:

```text
all before/after repeats have hash_match == true
all after render events contain rows_visited, picture_draw_count, debug_collection_enabled
after median(p95_total_span_micros) <= before median * 1.05
after median(p95_paint_micros) <= before median * 1.00
before and after target-label sets and repeat counts are identical
```

Run:

```bash
dart test tools/bench/test/terminal_render_phase3_gate_test.dart
```

Expected red: FAIL because `TerminalRenderPhase3Gate` and the CLI do not exist.

Implement `TerminalRenderPhase3Gate.evaluate`, JSON serialization with schema `ianvs-terminal-render-phase3-gate-v1`, and CLI options `--before`, `--after`, `--output`, `--workload`, and `--repeats`. The CLI scans every immediate child of both roots as a target-label directory; it never assumes a directory named `macos`. It exits 0 only when `passed == true`, otherwise 1.

Rerun the test. Expected green: PASS for the valid fixture and stable failure codes for each invalid fixture.

- [ ] **Step 8: Run focused tests and verify green**

Run:

```bash
cd packages/ianvs_terminal && flutter test test/terminal_viewport_render_test.dart
```

Expected: PASS, including the new metric test and all existing cursor, style, search, hyperlink, row-cache, and graphics overlay tests.

Run:

```bash
cd packages/ianvs_terminal && dart analyze lib/src/terminal/render_terminal_viewport.dart test/terminal_viewport_render_test.dart
```

Expected: `No issues found!`

- [ ] **Step 9: Capture the post-change profile and apply the Phase 3 gate**

Run:

```bash
dart run tools/bench/runner/flutter_profile_matrix_runner.dart \
  --output /tmp/ianvs-terminal-render-phase3-after \
  --workloads scrollback_heavy_profile \
  --repeats 3 \
  --frame-count 96 \
  --device macos \
  --require-target-count 1
```

Expected: exit 0, all hashes match, profile events contain `rows_visited`, `picture_draw_count`, and `debug_collection_enabled`, and `debug_collection_enabled` is false in profile mode. The automated gate, rather than a manual calculation, decides whether median `p95_total_span_micros` is no more than 105% of the before median and median `p95_paint_micros` is no more than 100% of the before median. If host noise violates either timing bound, repeat both before/after runs once on the same quiet host and run the same gate over the paired rerun; do not weaken the bounds.

Run the automated comparison from repository root:

```bash
dart run tools/bench/analysis/terminal_render_phase3_gate.dart \
  --before /tmp/ianvs-terminal-render-phase3-before \
  --after /tmp/ianvs-terminal-render-phase3-after \
  --output /tmp/ianvs-terminal-render-phase3-gate.json \
  --workload scrollback_heavy_profile \
  --repeats 3
```

Expected: exit 0 and `passed: true`. The tool discovers directories such as `/tmp/ianvs-terminal-render-phase3-after/macos-darwin-arm64`; no step reads `/tmp/ianvs-terminal-render-phase3-after/macos`.

Before committing, run the complete affected package gates:

```bash
cd packages/ianvs_terminal
flutter analyze --fatal-infos
flutter test
cd ../..
dart test tools/bench/test/terminal_render_phase3_gate_test.dart
```

Expected: every command exits 0. A focused test or profile gate never replaces the full terminal package suite.

- [ ] **Step 10: Commit Phase 3 independently**

```bash
git add packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart packages/ianvs_terminal/test/terminal_viewport_render_test.dart tools/bench/src/terminal_render_phase3_gate.dart tools/bench/analysis/terminal_render_phase3_gate.dart tools/bench/test/terminal_render_phase3_gate_test.dart
git commit -m "perf: reduce terminal paint allocation churn"
```

Expected: one commit containing only the five Phase 3 files listed in the command.

---

### Task 2 / Phase 4: Derive Graphics Revisions and Skip Redundant Cache Sync

**Files:**
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_models.dart:427-597`
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart:59-100`
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart:217-361`
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_graphics_cache.dart:168-199`
- Modify: `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart:104-151`
- Modify: `packages/ianvs_terminal/test/terminal_viewport_render_test.dart:706-2162`

- [ ] **Step 1: Write failing controller revision tests**

Add `terminal viewport controller tracks graphics and asset revisions independently`. Assert this exact sequence:

1. Empty controller: both revisions are `0` and `graphicsAssetKeys` is empty.
2. Snapshot with one placement: both revisions become `1`.
3. Text/cursor-only delta carrying an equal full placement list: both stay `1`.
4. Geometry-only `col` change with the same asset key: `graphicsRevision == 2`, `graphicsAssetRevision == 1`.
5. Same placement with asset version changed: `graphicsRevision == 3`, `graphicsAssetRevision == 2`.
6. Add a duplicate placement using the same asset key: graphics revision increments, asset revision does not.
7. Authoritative empty delta: both revisions increment and live keys become empty.

Add `terminal graphic placement equality covers every render field`. Use a valid base placement and one mutation for each of: `renderId`, `placementId`, `assetKey.id`, `assetKey.version`, `protocol`, `row`, `col`, `widthPx`, `heightPx`, `widthCells`, `heightCells`, `sourceXOffsetPx`, `visibleWidthPx`, `sourceYOffsetPx`, `visibleHeightPx`, `zIndex`, `xOffsetPx`, `yOffsetPx`, and `preserveAspectRatio`. Assert every mutation is unequal to the base and has a different controller `graphicsRevision` after application.

- [ ] **Step 2: Run controller tests and verify red**

```bash
cd packages/ianvs_terminal && flutter test test/terminal_runtime_controller_test.dart --plain-name "terminal viewport controller tracks graphics and asset revisions independently"
```

Expected: FAIL because the three controller getters do not exist.

- [ ] **Step 3: Add value equality and revision interfaces**

Implement `TerminalGraphicPlacement.operator ==` and `hashCode` from all fields listed in Step 1.

Add these controller interfaces:

```dart
int get graphicsRevision;
int get graphicsAssetRevision;
Set<TerminalGraphicAssetKey> get graphicsAssetKeys;
```

Route `updateFrame`, `applySnapshot`, and `applyDelta` through one private `_replaceState(TerminalViewportState nextState)` method. Its algorithm is fixed:

1. Compare previous and next ordered graphics with `listEquals` and placement value equality.
2. If equal, leave both revisions and the cached asset set unchanged.
3. If unequal, increment `graphicsRevision`, derive a deduplicated asset-key set, compare it with the cached set using `setEquals`, and increment `graphicsAssetRevision` only when the set differs.
4. Store the new state, increment `frameVersion`, and notify listeners.
5. Store the asset set as `Set.unmodifiable`; use `const <TerminalGraphicAssetKey>{}` for empty.

- [ ] **Step 4: Write failing cache-sync widget tests**

Add a private `_RecordingTerminalGraphicsCache` subclass that records immutable copies of every `evictExcept` argument before calling `super`.

Add `terminal viewport synchronizes graphics cache only for live asset revisions` and assert:

```dart
expect(cache.evictCalls, hasLength(1)); // initial forced sync

controller.updateFrame(textOnlyDeltaWithEqualGraphics);
await tester.pump();
expect(cache.evictCalls, hasLength(1));

controller.updateFrame(geometryOnlyDeltaWithSameAsset);
await tester.pump();
expect(cache.evictCalls, hasLength(1));

controller.updateFrame(assetVersionDelta);
await tester.pump();
expect(cache.evictCalls, hasLength(2));

controller.updateFrame(authoritativeEmptyDelta);
await tester.pump();
expect(cache.evictCalls, hasLength(3));
expect(cache.evictCalls.last, isEmpty);
```

Add `terminal viewport forces graphics cache sync after cache or controller replacement`; each identity replacement must add exactly one call even when its numeric revision equals the previous object's revision.

- [ ] **Step 5: Run cache-sync test and verify red**

```bash
cd packages/ianvs_terminal && flutter test test/terminal_viewport_render_test.dart --plain-name "terminal viewport synchronizes graphics cache only for live asset revisions"
```

Expected: FAIL because the current frame listener calls `evictExcept` for all controller notifications.

- [ ] **Step 6: Implement revision-driven synchronization and benchmark diagnostic**

Track this tuple in `_TerminalViewportState`:

```dart
TerminalViewportController? _lastGraphicsSyncController;
TerminalGraphicsCache? _lastGraphicsSyncCache;
int _lastGraphicsAssetRevision = -1;
```

These three viewport-private fields are the complete Phase 4 synchronization boundary. Do not create `terminal_graphics_sync.dart`, `TerminalGraphicsSync`, or another standalone coordinator in this phase; that extraction is reserved for Phase 6 after revision behavior is stable.

Change `_syncGraphicsCache` to accept `bool force = false`. Synchronize only when forced, controller identity changed, cache identity changed, or `graphicsAssetRevision` changed. Pass `widget.controller.graphicsAssetKeys` directly; do not rebuild a set in the widget.

Call with `force: true` from `initState` and from controller/cache identity changes in `didUpdateWidget`; call without force from `_handleFrameUpdate`. Reset all tracking fields when the cache is null.

When `TerminalGraphicsCache.evictExcept` has a diagnostic sink, emit one `cache_sync` event with `live_asset_count`, `cached_images_before`, and `pending_images_before`. Guard event-field map creation with `_diagnosticEventSink != null` so production-null diagnostics allocate nothing.

Add `graphics_revision` and `graphics_asset_revision` to the Phase 3 render benchmark event.

- [ ] **Step 7: Run focused green verification**

```bash
cd packages/ianvs_terminal && flutter test test/terminal_runtime_controller_test.dart --name "graphics|graphic placement equality"
```

Expected: PASS.

```bash
cd packages/ianvs_terminal && flutter test test/terminal_viewport_render_test.dart --name "graphic|graphics cache"
```

Expected: PASS, including existing async replacement, omitted graphic, late decode, initial eviction, and new sync-count tests.

```bash
cd packages/ianvs_terminal && dart analyze lib/src/terminal/terminal_models.dart lib/src/terminal/terminal_viewport.dart lib/src/terminal/terminal_graphics_cache.dart test/terminal_runtime_controller_test.dart test/terminal_viewport_render_test.dart
```

Expected: `No issues found!`

- [ ] **Step 8: Verify the Phase 4 operation-count benchmark**

Run the new cache-sync widget test with expanded output:

```bash
cd packages/ianvs_terminal && flutter test test/terminal_viewport_render_test.dart --plain-name "terminal viewport synchronizes graphics cache only for live asset revisions" --reporter expanded
```

Expected: PASS with the deterministic sync sequence `1, 1, 1, 2, 3`. This operation-count gate is authoritative for Phase 4; wall-clock timing is not used for a three-map/set micro-operation.

Before committing, run the complete terminal package gates:

```bash
cd packages/ianvs_terminal
flutter analyze --fatal-infos
flutter test
```

Expected: every command exits 0; the focused revision/cache tests do not replace the package suite.

- [ ] **Step 9: Commit Phase 4 independently**

```bash
git add packages/ianvs_terminal/lib/src/terminal/terminal_models.dart packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart packages/ianvs_terminal/lib/src/terminal/terminal_graphics_cache.dart packages/ianvs_terminal/test/terminal_runtime_controller_test.dart packages/ianvs_terminal/test/terminal_viewport_render_test.dart
git commit -m "perf: drive terminal graphics cache by revisions"
```

Expected: one commit on top of Phase 3 containing only the five Phase 4 files.

---

### Task 3 / Phase 5: Classify Idle Cursor Blink, Run an Internal A/B, and Commit Go or No-Go

**Files:**
- Create conditionally: `packages/ianvs_terminal/lib/src/terminal/render_terminal_cursor_overlay.dart`
- Create conditionally: `packages/ianvs_terminal/lib/src/terminal/terminal_cursor_overlay_experiment.dart`
- Modify conditionally: `packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart`
- Modify conditionally: `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
- Modify conditionally: `packages/ianvs_terminal/test/terminal_viewport_render_test.dart`
- Modify conditionally: `example/test/terminal/render_terminal_viewport_test.dart`
- Modify conditionally: `example/test/terminal_input_controller_test.dart`
- Modify: `example/integration_test/terminal_render_profile_test.dart`
- Modify: `example/lib/benchmarks/terminal_render_profile_report.dart`
- Create: `example/lib/benchmarks/terminal_cursor_overlay_gate.dart`
- Modify: `example/test/benchmarks/terminal_render_profile_report_test.dart`
- Create: `example/test/benchmarks/terminal_cursor_overlay_gate_test.dart`
- Create: `docs/evidence/2026-07-10-cursor-overlay/decision.md`
- Create: `docs/evidence/2026-07-10-cursor-overlay/cursor_overlay_gate.json`

- [ ] **Step 1: Verify real runner arguments and referenced paths**

Run from repository root:

```bash
dart run tools/bench/runner/flutter_profile_matrix_runner.dart --help
test -f packages/ianvs_terminal/test/terminal_viewport_render_test.dart
test -f packages/ianvs_terminal/test/terminal_runtime_controller_test.dart
test -f example/test/terminal/render_terminal_viewport_test.dart
test -f example/test/terminal_input_controller_test.dart
test -f example/integration_test/terminal_render_profile_test.dart
test -f example/test/benchmarks/terminal_render_profile_report_test.dart
```

Expected: help lists `--output`, `--workloads`, `--repeats`, `--frame-count`, repeatable `--device`, `--require-target-count`, and `--dry-run`; every `test -f` exits 0. Runner output is always `$output/${device.targetLabel}`, where macOS labels match `macos-darwin-*`; no later command assumes a literal `$output/macos` directory.

- [ ] **Step 2: Add `cursor_blink_idle_profile` before any overlay seam**

First run the target name against the unmodified workload parser:

```bash
dart run tools/bench/runner/flutter_profile_matrix_runner.dart \
  --output /tmp/ianvs-terminal-cursor-idle-red \
  --workloads cursor_blink_idle_profile \
  --repeats 1 \
  --frame-count 20 \
  --device macos \
  --require-target-count 1
```

Expected red: the integration target rejects `cursor_blink_idle_profile` as an unknown workload.

Add `_ProfileWorkloadKind.cursorBlinkIdle` and the exact name `cursor_blink_idle_profile`. Each repeat builds one static 40x120 snapshot, uses an explicit `FocusNode` and requests focus, warms up two 700 ms blink intervals, clears render/timing events, then traces exactly `_frameCount` 700 ms intervals without a controller update. Write `semanticGenerations: 1` and the ordinary correctness hash. At this point the workload uses the unchanged production surface cursor and introduces no render mode.

Run the command again. Expected green: exit 0, one dynamically labelled target directory exists, 20 blink transitions are sampled, and all hashes match.

- [ ] **Step 3: Write report and fixed-gate red tests**

Extend report fixtures with surface and cursor events. Require both p50 and p95 fields:

```dart
expect(summary['p50_surface_paint_micros'], 60);
expect(summary['p95_surface_paint_micros'], 100);
expect(summary['p50_cursor_paint_micros'], 12);
expect(summary['p95_cursor_paint_micros'], 20);
expect(summary['p50_build_duration_micros'], isA<num>());
expect(summary['p95_build_duration_micros'], isA<num>());
expect(summary['p50_raster_duration_micros'], isA<num>());
expect(summary['p95_raster_duration_micros'], isA<num>());
expect(summary['p50_total_span_micros'], isA<num>());
expect(summary['p95_total_span_micros'], isA<num>());
```

In `terminal_cursor_overlay_gate_test.dart`, use five surface and five overlay repeats with 24 transitions. Mutate each fixed condition independently and assert `eligible == false` with its stable reason code, including layer and memory failures.

Run:

```bash
cd example
flutter test test/benchmarks/terminal_render_profile_report_test.dart test/benchmarks/terminal_cursor_overlay_gate_test.dart
```

Expected red: summary percentile fields and the evaluator are absent.

- [ ] **Step 4: Implement and lock the report/gate contract**

Add p50/p95 surface paint, cursor paint, build, raster and total-span fields. Cursor events also report `paint_bounds_area`, `cell_width_px`, `cell_height_px`, `device_pixel_ratio`, `cursor_picture_live_count`, `cursor_picture_estimated_bytes`, and `overlay_layer_count`; summaries retain their maxima so the layer, paint-bound, and memory gates are reproducible from the recorded result alone.

Define these constants before running the first A/B:

```dart
static const minRepeatsPerVariant = 5;
static const minBlinkTransitionsPerRepeat = 20;
static const maxCursorPaintP95Ratio = 0.80;
static const maxFrameTimingP95Ratio = 1.05;
static const maxAdditionalOverlayLayers = 1;
static const maxLiveCursorPictures = 1;
```

Eligibility requires all correctness suites in Step 6 plus:

- at least five repeats per variant and at least 20 transitions per repeat;
- overlay non-frame surface paints equal 0;
- overlay cursor paints and surface baseline non-frame paints each equal sampled transitions;
- median overlay cursor-paint p95 is at most 80% of median surface-paint p95;
- overlay median p95 build, raster and total span are each at most 105% of surface;
- overlay missed-vsync total is no greater than surface;
- overlay adds at most one layer, retains at most one cursor picture, and every overlay paint bound is no larger than two terminal cells;
- `cursor_picture_estimated_bytes <= ceil(2 * cellWidth * dpr) * ceil(cellHeight * dpr) * 4` for every repeat.

Write threshold values, observed p50/p95 values, layer/memory maxima and stable reason codes to `ianvs-cursor-overlay-gate-v1` JSON. Run the two report/gate tests again; expected green: PASS.

- [ ] **Step 5: Add an internal-only overlay experiment**

Do not add `TerminalCursorRenderMode`, a `TerminalViewport` constructor argument, or a barrel export. Create a non-exported-by-barrel `TerminalCursorExperimentScope` in `src/terminal/terminal_cursor_overlay_experiment.dart` with internal enum values `surface` and `overlay`. Production without a scope initially resolves to surface. Package tests import the `src` file directly; the integration profile uses one explicit `implementation_imports` suppression at that test-only import.

Create `cursor_blink_idle_surface_profile` and `cursor_blink_idle_overlay_profile` as internal variants of the already-working `cursor_blink_idle_profile`; only the variants install the internal scope.

Use a structured immutable `TerminalCursorVisualKey`, never a lone integer hash/signature. Its value equality and `hashCode` cover frame version, cursor row/column/visibility, cursor shape, resolved foreground/background/cursor colors, cell size, DPR, font family/fallback/size/line height, glyph text/custom-geometry inputs, and cursor-enabled/config state. Cache reuse requires `oldKey == newKey`; hash equality alone is insufficient.

`TerminalCursorVisualSnapshot` owns that key, one picture, cursor rect and color. The overlay is a leaf repaint boundary listening to blink visibility. It paints only the cursor rect and emits the cursor timing/layer/memory fields from Step 4 when a sink exists.

- [ ] **Step 6: Write and run repaint, cache-key, pixel and layer-order tests**

Required red/green tests:

- one overlay blink emits one `ianvs-bench-flutter-cursor-v1` event and no `ianvs-bench-flutter-render-v1` event;
- changing each `TerminalCursorVisualKey` field rebuilds the picture, while an equal reconstructed key reuses it;
- block, beam and underline cursor pixels match the surface path at DPR 1 and 2 for ASCII and wide CJK cells;
- block cursor inverse glyph, custom geometry and smart contrast match;
- scrollback, hidden/out-of-bounds cursor, focus loss/gain, controller replacement and disposal remain correct;
- IME composing text and `debugCaretCellRect` remain correct across blink frames;
- exact Stack order is negative-z graphics, terminal surface, cursor overlay, inline images, non-negative-z graphics, timestamps, scrollbar, composing overlay, link tooltip.

Run:

```bash
cd packages/ianvs_terminal
flutter test test/terminal_viewport_render_test.dart --name "cursor|graphic"
cd ../../example
flutter test test/terminal/render_terminal_viewport_test.dart --name "cursor"
flutter test test/terminal_input_controller_test.dart --plain-name "terminal viewport keeps composing text visible across cursor blink frames"
```

Expected: PASS. A missing layer, changed z-order, full-viewport cursor paint bound, stale structured key, pixel difference or IME regression fails Phase 5 before profiling.

- [ ] **Step 7: Freeze the evaluator before collecting results**

Run:

```bash
shasum -a 256 \
  example/lib/benchmarks/terminal_cursor_overlay_gate.dart \
  example/test/benchmarks/terminal_cursor_overlay_gate_test.dart \
  > /tmp/ianvs-cursor-overlay-gate.sha256
```

After this command, do not edit gate thresholds or evaluator logic. An instrumentation correction invalidates all existing A/B output: delete the output root, restore the fixed constants, rerun tests, create a new checksum, and collect from the beginning.

- [ ] **Step 8: Run the real A/B and discover the target-label output**

Run from repository root:

```bash
dart run tools/bench/runner/flutter_profile_matrix_runner.dart \
  --output /tmp/ianvs-terminal-cursor-overlay-ab \
  --workloads cursor_blink_idle_surface_profile,cursor_blink_idle_overlay_profile \
  --repeats 5 \
  --frame-count 24 \
  --device macos \
  --require-target-count 1
shasum -a 256 -c /tmp/ianvs-cursor-overlay-gate.sha256
find /tmp/ianvs-terminal-cursor-overlay-ab -mindepth 2 -maxdepth 2 -name cursor_overlay_gate.json -print
```

Expected: runner and checksum exit 0; exactly one gate file is printed below a target-label directory such as `macos-darwin-arm64`; ten repeat summaries exist; every correctness hash matches; the gate contains p50/p95 timing, layer/memory costs, `eligible`, and reason codes. Do not edit a threshold after reading this result.

- [ ] **Step 9: Copy immutable evidence and choose exactly one branch**

Copy the discovered gate JSON into `docs/evidence/2026-07-10-cursor-overlay/cursor_overlay_gate.json`. Write `decision.md` with the evaluator checksum, actual target label, commands, threshold table, observed p50/p95 values, layer/memory costs, correctness results and decision.

If `eligible == true` and every Step 6 test passed:

- set the private production default to overlay;
- keep the internal experiment scope for profile/test comparison only;
- keep the public `TerminalViewport` constructor and both public barrel files byte-for-byte unchanged;
- rerun Step 6 without an experiment scope and expect overlay repaint isolation.

If `eligible == false` or any Step 6 test failed:

- remove only the experimental hunks from `render_terminal_viewport.dart`, `terminal_viewport.dart`, package cursor tests and example cursor/IME tests with explicit patches, returning them byte-for-byte to the Phase 4 content; do not use a destructive reset or checkout that could discard unrelated work;
- delete `render_terminal_cursor_overlay.dart` and `terminal_cursor_overlay_experiment.dart`;
- remove the surface/overlay variant parsing and internal import from the integration profile while retaining the base `cursor_blink_idle_profile`;
- retain only the base benchmark classification, report/gate code and tests, and no-go evidence;
- run `rg -n "TerminalCursorExperiment|TerminalCursorRenderMode|cursor_blink_idle_surface_profile|cursor_blink_idle_overlay_profile" packages/ianvs_terminal/lib packages/ianvs_terminal/test example/integration_test` and expect no matches.

Changing a gate threshold is not a valid branch action.

- [ ] **Step 10: Verify public API and branch contents**

Run:

```bash
git diff --exit-code HEAD -- packages/ianvs_terminal/lib/ianvs_terminal.dart packages/ianvs_terminal/lib/ianvs_terminal_debug.dart
git diff --check
cd example
flutter test test/benchmarks/terminal_render_profile_report_test.dart test/benchmarks/terminal_cursor_overlay_gate_test.dart
```

Expected: public barrels are unchanged, diff check exits 0, report/gate tests pass. On go, rerun all Step 6 tests. On no-go, run the base `cursor_blink_idle_profile` once and confirm it still produces a surface baseline and decision evidence without any overlay production class.

Before either branch commit, run the complete affected package gates:

```bash
cd packages/ianvs_terminal
flutter analyze --fatal-infos
flutter test
cd ../../example
flutter analyze --fatal-infos
flutter test
```

Expected: every command exits 0 on the exact go/no-go tree that will be committed.

- [ ] **Step 11: Commit Phase 5 independently**

Go commit:

```bash
git add packages/ianvs_terminal/lib/src/terminal/render_terminal_cursor_overlay.dart packages/ianvs_terminal/lib/src/terminal/terminal_cursor_overlay_experiment.dart packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart packages/ianvs_terminal/test/terminal_viewport_render_test.dart example/test/terminal/render_terminal_viewport_test.dart example/test/terminal_input_controller_test.dart example/integration_test/terminal_render_profile_test.dart example/lib/benchmarks/terminal_render_profile_report.dart example/lib/benchmarks/terminal_cursor_overlay_gate.dart example/test/benchmarks/terminal_render_profile_report_test.dart example/test/benchmarks/terminal_cursor_overlay_gate_test.dart docs/evidence/2026-07-10-cursor-overlay
git commit -m "perf: enable measured terminal cursor overlay"
```

No-go commit:

```bash
git add example/integration_test/terminal_render_profile_test.dart example/lib/benchmarks/terminal_render_profile_report.dart example/lib/benchmarks/terminal_cursor_overlay_gate.dart example/test/benchmarks/terminal_render_profile_report_test.dart example/test/benchmarks/terminal_cursor_overlay_gate_test.dart docs/evidence/2026-07-10-cursor-overlay
git commit -m "bench: record terminal cursor overlay no-go"
```

Expected: the go commit contains the internal overlay implementation but no public API change. The no-go commit contains no production renderer/viewport change and no mode seam; it contains only benchmark/report/gate tests and immutable no-go evidence.

---

## Final Verification

- [ ] Run all package tests touched by the three phases:

```bash
cd packages/ianvs_terminal && flutter test test/terminal_viewport_render_test.dart test/terminal_runtime_controller_test.dart
```

Expected: PASS.

- [ ] Run all example tests touched by cursor rendering and reporting:

```bash
cd example && flutter test test/terminal/render_terminal_viewport_test.dart test/terminal_input_controller_test.dart test/benchmarks/terminal_render_profile_report_test.dart test/benchmarks/terminal_cursor_overlay_gate_test.dart
```

Expected: PASS with no pending timer or disposed-image errors.

- [ ] Run static analysis for both Flutter packages:

```bash
cd packages/ianvs_terminal && dart analyze
```

```bash
cd example && dart analyze
```

Expected: both report `No issues found!`

- [ ] Confirm the chosen Phase 5 branch and commit isolation:

```bash
git log -3 --oneline
git status --short
```

Expected: the latest commit is exactly one of `perf: enable measured terminal cursor overlay` or `bench: record terminal cursor overlay no-go`, followed by `perf: drive terminal graphics cache by revisions` and `perf: reduce terminal paint allocation churn`; the worktree is clean. For a no-go result, `rg -n "TerminalCursorExperiment|TerminalCursorRenderMode|cursor_blink_idle_surface_profile|cursor_blink_idle_overlay_profile" packages/ianvs_terminal/lib packages/ianvs_terminal/test example/integration_test` also returns no matches.
