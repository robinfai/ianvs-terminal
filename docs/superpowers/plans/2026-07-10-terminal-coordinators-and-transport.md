# Terminal Coordinators and Frame Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变公开 terminal API、刷新时序、IME 行为和 wire schema 的前提下，完成 Phase 6 的低风险职责边界整理，并让 Phase 7 的 JSON/protobuf frame transport 统一经过 `TerminalFrameDecoder` facade 和共享校验规则。

**Architecture:** Phase 6 只整理前序 Phase 已形成的 frame-pump 决策边界，并新增两个不拥有 Widget 的小型状态对象：`TerminalFocusReporter` 与 `TerminalGraphicsSync`；完整 IME 仍留在 viewport。Phase 7 在 `lib/src/transport/` 放置 JSON/protobuf codec、校验上限和 wire 兼容规则，由 internal transport coordinator 完成 backend 选择与拉取，`TerminalFrameDecoder` 保持 runtime facade；公开 `TerminalFrameDiff` factories 继续作为兼容接缝，因此本阶段不宣称 domain models 已完全移除 protobuf 依赖。

**Tech Stack:** Dart 3.11、Flutter 3.44、`package:protobuf` 6、`package:fixnum`、`flutter_test`、现有 `ianvs_pty` backend interfaces、Git。

---

## Scope and sequencing

本计划只执行设计稿的 Phase 6 和 Phase 7，并假定 Phase 1–5 已各自完成且通过门禁。执行 Phase 6 前必须确认前序提交已经提供：基于单调时钟的 `TerminalFramePumpPolicy`、refresh hint、`TerminalRefreshPolicy`、`TerminalViewportController.graphicsAssetRevision` 和 `graphicsRevision`。Phase 6 才创建组合这些既有决策的 `TerminalFramePumpController`。若任一前置符号缺失，停止执行本计划并回到对应前序 Phase；不要在 Phase 6 重写其行为。

明确不在本计划内：

- 不抽取完整 `TerminalImeCoordinator`。
- 不移动 `TextInputConnection`、composition state、deferred key state、selection 或 caret geometry。
- 不改变 polling、cooldown、queued refresh、resize-before-frame 或 exit/frame 顺序。
- 不改变 `native/core/proto/frame_diff.proto`、生成代码字段号、enum 数值或 JSON schema。
- 不删除 JSON compatibility path，不改变 `TerminalFrameWireFormatPreference.automatic` 的含义。
- 不修改 viewport hash 算法；逐字段 parity 是新增的更强门禁。
- 不把 coordinator 或 transport codec 加入 `ianvs_terminal.dart` 公共导出。

## File Structure

### Phase 6

- Create: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump_controller.dart`
  - 组合前序 Phase 已实现的 deadline policy、hint probe、refresh class state 和 counters；不读取 Widget。
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart`
  - 保留 Phase 1 的 deadline policy，不承担 backend 调用或 Widget 状态。
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
  - 删除与 frame-pump 决策重复的散落状态，保留 timer、backend operation、frame/event 顺序和公开 facade。
- Create: `packages/ianvs_terminal/lib/src/terminal/terminal_focus_reporter.dart`
  - 只记录上次 focus report 并计算 attach/sync/detach 是否需要发送 focus-in/focus-out。
- Create: `packages/ianvs_terminal/lib/src/terminal/terminal_graphics_sync.dart`
  - 根据 controller/cache identity 和 `graphicsAssetRevision` 决定是否执行 asset eviction，复用 live-key scratch set。
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
  - 委托 focus report 与 graphics cache sync；IME、FocusNode 监听和 Widget 生命周期保持原位。
- Modify: `packages/ianvs_terminal/test/terminal_frame_pump_test.dart`
  - 固化前序 Phase 的 deadline policy 行为不变。
- Create: `packages/ianvs_terminal/test/terminal_frame_pump_controller_test.dart`
  - 固化 hint/class/deadline 组合决策、counters、reset/remove 行为在新边界内不变。
- Create: `packages/ianvs_terminal/test/terminal_focus_reporter_test.dart`
  - 覆盖 disabled、dedupe、focus-in/out、detach 和 owner reset。
- Create: `packages/ianvs_terminal/test/terminal_graphics_sync_test.dart`
  - 覆盖初次同步、revision 去重、空权威列表、controller/cache 替换和 scratch-set 复用。
- Modify: `packages/ianvs_terminal/test/terminal_viewport_render_test.dart`
  - 保留 pane focus、graphics initial mount/cache replacement 的 widget-level 契约。

### Phase 7

- Create: `packages/ianvs_terminal/lib/src/transport/terminal_frame_validation_limits.dart`
  - 集中声明现有 dimension、collection scan、style、hyperlink、inline-image 上限。
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_wire_compatibility.dart`
  - 集中声明 schema fallback、frame-kind fallback 和 JSON legacy token 规则；不依赖 Flutter Widget。
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_json_frame_decoder.dart`
  - 解析 JSON object 并调用公开 factory compatibility seam。
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_protobuf_frame_decoder.dart`
  - 唯一新的 runtime codec import generated protobuf；坏 payload 返回 null。
- Create: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_transport_coordinator.dart`
  - 负责 forced JSON/automatic backend 探测、wire 拉取、错误回调和调用 decoder facade；不接触 viewport 或 refresh scheduler。
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_decoder.dart`
  - 保留 `decode(String)`，新增显式 `decodeJson` 与 `decodeProtobuf`，统一 metrics。
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
  - 使用 transport coordinator；保留 apply、event ordering、benchmark emission 和 public constructor。
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
  - 公开 factories 保留；使用共享 limits/compatibility，并让 protobuf collection normalization 与 JSON 一致。
- Modify: `packages/ianvs_terminal/lib/ianvs_terminal.dart`
  - 不新增 codec/coordinator 导出；现有 public names 保持可见。
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
  - 继续从旧 source URI re-export clipboard/diagnostics，并只 re-export wire preference enum。
- Create: `packages/ianvs_terminal/test/support/terminal_frame_wire_fixture.dart`
  - 提供同一语义的 JSON/protobuf paired fixture 和完整 frame projection。
- Modify: `packages/ianvs_terminal/test/terminal_frame_decoder_test.dart`
  - 覆盖 facade API、metrics、malformed payload 和 UTF-8 byte count。
- Create: `packages/ianvs_terminal/test/terminal_frame_codec_parity_test.dart`
  - 逐字段 parity、validation limits、unknown field/enum 和 hash parity。
- Modify: `packages/ianvs_terminal/test/terminal_frame_diff_corpus_test.dart`
  - 保留 JSON corpus 兼容并补 public factory/facade 等价断言。
- Modify: `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`
  - 保留 protobuf preferred、forced JSON、unsupported fallback、idle PB stream 和 malformed PB 契约。
- Modify: `docs/FRAME_DIFF.md`
  - 把 JSON-only 描述更新为 automatic protobuf + forced/unsupported JSON compatibility path，并记录 public factory seam。

## Phase 6: Low-risk coordinator boundaries

### Task 1: Establish Phase 6 characterization and failing boundary tests

**Files:**
- Modify: `packages/ianvs_terminal/test/terminal_frame_pump_test.dart`
- Create: `packages/ianvs_terminal/test/terminal_frame_pump_controller_test.dart`
- Create: `packages/ianvs_terminal/test/terminal_focus_reporter_test.dart`
- Create: `packages/ianvs_terminal/test/terminal_graphics_sync_test.dart`

- [ ] **Step 1: Verify Phase 1–5 prerequisites**

Run from repository root:

```bash
rg -n "final class TerminalFramePumpPolicy|final class TerminalRefreshPolicy|abstract interface class PtySessionRefreshHintBackend|graphicsAssetRevision|graphicsRevision" \
  packages/ianvs_terminal packages/ianvs_pty
```

Expected: each of the five prerequisite symbols is found in its focused production file, and no definition appears only in a test. `TerminalFramePumpController` is intentionally absent before Phase 6. If the output is incomplete, stop before editing Phase 6.

- [ ] **Step 2: Run existing characterization tests before moving boundaries**

Run:

```bash
cd packages/ianvs_terminal
flutter test \
  test/terminal_frame_pump_test.dart \
  test/terminal_runtime_controller_test.dart \
  test/terminal_viewport_render_test.dart
```

Expected: PASS. Save the command and result in the Phase 6 commit message body or handoff evidence.

- [ ] **Step 3: Add the focus reporter red tests**

Create tests against this exact interface:

```dart
final class TerminalFocusReportDecision {
  const TerminalFocusReportDecision({required this.focused});
  final bool focused;
}

final class TerminalFocusReporter {
  TerminalFocusReportDecision? synchronize({
    required bool focusTrackingEnabled,
    required bool hasFocus,
  });

  TerminalFocusReportDecision? detach({
    required bool focusTrackingEnabled,
    required bool focusNodeHasFocus,
  });

  void reset();
}
```

Required assertions in `terminal_focus_reporter_test.dart`:

- disabled tracking returns null and clears dedupe state;
- first focused sync returns `focused == true`, repeated focused sync returns null;
- focused-to-unfocused sync returns `focused == false` exactly once;
- detach returns focus-out when the last reported state or detached node was focused;
- `reset()` allows a new owner to emit focus-in again.

- [ ] **Step 4: Add the graphics sync red tests**

Create tests against this exact interface:

```dart
final class TerminalGraphicsSync {
  bool synchronize({
    required Object controllerIdentity,
    required TerminalGraphicsCache? cache,
    required int assetRevision,
    required Iterable<TerminalGraphicAssetKey> liveAssetKeys,
  });

  Set<TerminalGraphicAssetKey> get debugLiveAssetKeys;
  void reset();
}
```

Required assertions in `terminal_graphics_sync_test.dart`:

- first non-null cache sync returns true;
- same controller, same cache and same revision returns false;
- a higher revision returns true and exposes the supplied deduplicated live asset keys;
- an authoritative empty live-key set returns true and exposes an empty key set;
- controller replacement and cache replacement force sync even when revision is unchanged;
- repeated sync keeps the same internal scratch-set identity, observed through an internal debug identity getter used only by the `src` test.

- [ ] **Step 5: Run the new tests and verify the red state**

Run:

```bash
cd packages/ianvs_terminal
flutter test \
  test/terminal_frame_pump_controller_test.dart \
  test/terminal_focus_reporter_test.dart \
  test/terminal_graphics_sync_test.dart
```

Expected: FAIL at compile time because `terminal_frame_pump_controller.dart`, `terminal_focus_reporter.dart`, and `terminal_graphics_sync.dart` do not exist.

### Task 2: Implement and wire the Phase 6 boundaries

**Files:**
- Create: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump_controller.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- Create: `packages/ianvs_terminal/lib/src/terminal/terminal_focus_reporter.dart`
- Create: `packages/ianvs_terminal/lib/src/terminal/terminal_graphics_sync.dart`
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart`
- Modify: `packages/ianvs_terminal/test/terminal_viewport_render_test.dart`

- [ ] **Step 1: Finish the frame-pump boundary without changing policy**

Keep the exact Phase 1–3 deadline, hint and refresh-class decisions, but enforce these ownership rules:

- the new `TerminalFramePumpController` composes `TerminalFramePumpPolicy` and `TerminalRefreshPolicy`, and owns per-session hint counters, full-poll counters and reset/remove orchestration;
- `TerminalRuntimeController` owns the periodic timer, backend calls, refresh scheduler and frame/event order;
- controller methods return decisions/data and never call `Timer`, `TerminalViewport`, or `BuildContext`;
- `closeSession`, exit handling and `dispose` call one `remove(sessionId)` boundary;
- input, activation, focus gain and resize call one `reset(sessionId)` boundary supplied by the preceding policy Phase.

Keep deadline-only assertions in `terminal_frame_pump_test.dart`. Add `terminal_frame_pump_controller_test.dart` assertions for an overdue deadline, hint-ready bypass, false-hint bounded fallback, refresh-class preservation, counter snapshots and complete state removal. This is a behavior-preserving refactor: characterization is green before the move, the new boundary test is RED until the class exists, and both are green after the move.

- [ ] **Step 2: Implement `TerminalFocusReporter`**

The implementation must contain only one mutable field, `bool? _lastReportedFocus`. `synchronize` clears it when tracking is disabled, deduplicates equal reports, and otherwise returns the new state. `detach` returns focus-out only when tracking is enabled and either the previous report or detached FocusNode was focused. `reset` sets the field to null.

- [ ] **Step 3: Wire focus reporting without moving IME**

In `terminal_viewport.dart`:

- replace `_lastReportedFocusTrackingFocus` with one `TerminalFocusReporter`;
- keep `_bindFocusNodeListener`, `_unbindFocusNodeListener`, `_syncTextInputConnection`, all `TextInputClient` methods and caret geometry unchanged;
- make `_syncFocusTrackingReport` obtain a decision and call `widget.inputController.sendFocusReport` only when non-null;
- make detached-focus handling obtain a decision and send it through the old or current `TerminalInputController` exactly as today;
- call `reset()` only after a focus-report owner change has emitted the required detach report.

The existing pane-scoping and unmount widget tests must remain unchanged and pass.

- [ ] **Step 4: Implement `TerminalGraphicsSync`**

Use one reusable `Set<TerminalGraphicAssetKey>` scratch set. Sync is required when controller identity changes, cache identity changes, or asset revision changes. On sync, clear and refill the set from the controller's already-deduplicated `graphicsAssetKeys`, call `cache.evictExcept` synchronously, record identities/revision, and return true. A null cache clears the cache binding so a later non-null cache is forced to sync. `reset()` clears identities, revision and keys.

- [ ] **Step 5: Wire graphics sync to revisions**

In `terminal_viewport.dart`, replace `map((graphic) => graphic.assetKey).toSet()` in `_syncGraphicsCache()` with one `_graphicsSync.synchronize` call using:

```dart
controllerIdentity: widget.controller,
cache: widget.graphicsCache,
assetRevision: widget.controller.graphicsAssetRevision,
liveAssetKeys: widget.controller.graphicsAssetKeys,
```

Call it on initial mount, frame update, controller replacement and cache replacement. Call `_graphicsSync.reset()` from `dispose`. Do not key eviction from `graphicsRevision`: placement-only geometry changes must not evict assets.

- [ ] **Step 6: Run focused green tests**

Run:

```bash
cd packages/ianvs_terminal
flutter test \
  test/terminal_frame_pump_test.dart \
  test/terminal_frame_pump_controller_test.dart \
  test/terminal_focus_reporter_test.dart \
  test/terminal_graphics_sync_test.dart \
  test/terminal_viewport_render_test.dart \
  test/terminal_input_controller_test.dart
```

Expected: PASS. Focus-in/out bytes, pane scoping, initial graphics eviction, authoritative empty graphics and cache/controller replacement remain green.

- [ ] **Step 7: Run the Phase 6 package gate**

Run:

```bash
cd packages/ianvs_terminal
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
cd ../..
VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION=1 ./tools/verify_flutter_terminal.sh
git diff --check
```

Expected: every command exits 0. The verification script must report all enabled non-GUI gates passed.

- [ ] **Step 8: Perform Phase 6 manual QA**

Run the macOS example app and verify: switching between two panes sends one focus-out then one focus-in; closing a focused pane sends one focus-out; CJK/IME composition and backspace remain unchanged; adding, replacing and clearing a graphic does not display a stale asset. Record the exact app build and observations in the Phase 6 handoff.

- [ ] **Step 9: Commit Phase 6 alone**

Run:

```bash
git add \
  packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump.dart \
  packages/ianvs_terminal/lib/src/runtime/terminal_frame_pump_controller.dart \
  packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart \
  packages/ianvs_terminal/lib/src/terminal/terminal_focus_reporter.dart \
  packages/ianvs_terminal/lib/src/terminal/terminal_graphics_sync.dart \
  packages/ianvs_terminal/lib/src/terminal/terminal_viewport.dart \
  packages/ianvs_terminal/test/terminal_frame_pump_test.dart \
  packages/ianvs_terminal/test/terminal_frame_pump_controller_test.dart \
  packages/ianvs_terminal/test/terminal_focus_reporter_test.dart \
  packages/ianvs_terminal/test/terminal_graphics_sync_test.dart \
  packages/ianvs_terminal/test/terminal_viewport_render_test.dart
git commit -m "refactor: isolate terminal runtime coordinators"
```

Expected: one Phase 6 commit containing no transport codec or schema changes.

## Phase 7: Frame decoder facade and transport compatibility

### Task 3: Add failing facade, parity and public compatibility tests

**Files:**
- Create: `packages/ianvs_terminal/test/support/terminal_frame_wire_fixture.dart`
- Modify: `packages/ianvs_terminal/test/terminal_frame_decoder_test.dart`
- Create: `packages/ianvs_terminal/test/terminal_frame_codec_parity_test.dart`
- Modify: `packages/ianvs_terminal/test/terminal_frame_diff_corpus_test.dart`
- Modify: `packages/ianvs_terminal/test/terminal_runtime_controller_test.dart`

- [ ] **Step 1: Define the decoder facade contract in tests**

Keep this compatibility contract:

```dart
TerminalDecodedFrame? decode(String rawFrame); // JSON alias retained
TerminalDecodedFrame? decodeJson(String rawFrame);
TerminalDecodedFrame? decodeProtobuf(Uint8List rawFrame);
```

Required assertions:

- `decode(raw)` and `decodeJson(raw)` produce identical complete projections;
- malformed JSON, a JSON array and malformed protobuf return null;
- JSON metrics use UTF-8 byte length and set only `jsonDecodeMicros`;
- protobuf metrics use byte-list length and set only `protobufDecodeMicros`;
- disabling metric collection returns `metrics == null` for both formats.

- [ ] **Step 2: Add a complete paired fixture and projection**

`terminal_frame_wire_fixture.dart` must build matching JSON and generated protobuf payloads containing every current domain field: schema, kind, rows, timestamps, style flags/colors, cursor, selection, dimensions, dirty ranges, scrollback metadata, viewport shift/start, default colors, modes, title/icon, hyperlinks, inline images and graphics.

Its `terminalFrameProjection(TerminalFrameDiff frame)` must return a nested map containing every field, using `Color.toARGB32()`, UTC microseconds for timestamps, byte lists for images and all graphic placement fields. Tests compare this projection recursively; object identity and production viewport hash are not substitutes.

- [ ] **Step 3: Add parity and validation red tests**

Required test cases in `terminal_frame_codec_parity_test.dart`:

- complete JSON/protobuf projections are equal and `terminalBenchmarkViewportHash` is equal;
- dimensions above 65535 clamp equally;
- duplicate/out-of-range rows normalize equally and row text is clipped to complete display columns;
- style runs cap at 1024, hyperlinks at 4096 and inline images at 32 for both formats;
- dirty ranges clamp and merge equally;
- missing schema defaults to `terminal-frame-diff-v1` and unknown frame kind defaults to snapshot;
- explicit JSON/protobuf `preserveAspectRatio` true and false values decode equally in paired fixtures;
- a legacy omitted JSON value remains true while an omitted proto3 scalar remains false; add a characterization test and document this intentional compatibility seam instead of pretending protobuf presence can distinguish an encoded false from omission;
- protobuf unknown field 99 is ignored by appending bytes `0x98, 0x06, 0x01` to a valid payload;
- explicit non-current schema text remains preserved, matching existing public factory behavior;
- `TerminalFrameDiff.fromJson` equals `decodeJson`, and `TerminalFrameDiff.fromProtobufBytes` equals `decodeProtobuf` under the full projection.

- [ ] **Step 4: Add runtime transport boundary tests**

Keep the existing five runtime contracts and add coordinator-level assertions:

- automatic uses protobuf when `supportsProtobufFrameDiffs == true`;
- forced JSON never calls the protobuf backend;
- unsupported protobuf capability falls back to JSON;
- an idle supported protobuf stream does not consume JSON;
- malformed protobuf is dropped and does not consume JSON;
- backend exceptions call the existing backend-error callback with operation `takeFrameDiffJson` or `takeFrameDiffProtobuf`.

- [ ] **Step 5: Run the new tests and verify the red state**

Run:

```bash
cd packages/ianvs_terminal
flutter test \
  test/terminal_frame_decoder_test.dart \
  test/terminal_frame_codec_parity_test.dart \
  test/terminal_frame_diff_corpus_test.dart
```

Expected: FAIL because the explicit decoder methods and transport files do not exist; parity limit cases also expose the current protobuf normalization differences.

### Task 4: Implement codecs, shared rules and runtime transport delegation

**Files:**
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_frame_validation_limits.dart`
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_wire_compatibility.dart`
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_json_frame_decoder.dart`
- Create: `packages/ianvs_terminal/lib/src/transport/terminal_protobuf_frame_decoder.dart`
- Create: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_transport_coordinator.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_frame_decoder.dart`
- Modify: `packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- Modify: `packages/ianvs_terminal/lib/src/terminal/terminal_models.dart`
- Modify: `packages/ianvs_terminal/lib/ianvs_terminal.dart`
- Modify: `docs/FRAME_DIFF.md`

- [ ] **Step 1: Add shared validation limits**

Define `TerminalFrameValidationLimits` with these exact constants and helpers:

```dart
abstract final class TerminalFrameValidationLimits {
  static const int maxNativeDimension = 0xffff;
  static const int maxStyleRunsPerRow = 1024;
  static const int maxHyperlinksPerFrame = 4096;
  static const int maxInlineImagesPerFrame = 32;
  static const int maxInlineImageDecodedBytes = 4 * 1024 * 1024;
  static const int malformedCollectionSlack = 64;
  static const int malformedCollectionScanMultiplier = 4;

  static int maxViewportBoundedEntries(int viewportRows);
  static int maxEntriesToScan(int maxEntries);
}
```

The helpers must preserve the existing clamp to `maxNativeDimension`. Replace private duplicate numeric constants in `terminal_models.dart` with these names; do not add a new raw-frame byte cap in this refactor.

- [ ] **Step 2: Add wire compatibility rules**

Define a wire-neutral enum `TerminalWireFrameKind { snapshot, delta }` and `TerminalWireCompatibility` methods that:

- trim a non-empty schema string and otherwise return `terminal-frame-diff-v1`;
- map case-insensitive JSON token `delta` and protobuf numeric value 2 to delta;
- map missing, malformed and unknown kinds to snapshot;
- preserve the existing JSON field aliases already accepted by the public factories.

Do not reject `terminal-frame-diff-v2`; current tests intentionally preserve explicit schema text.

- [ ] **Step 3: Add JSON and protobuf codecs**

Use these exact interfaces:

```dart
final class TerminalJsonFrameDecoder {
  const TerminalJsonFrameDecoder();
  TerminalFrameDiff? decode(String rawFrame);
}

final class TerminalProtobufFrameDecoder {
  const TerminalProtobufFrameDecoder();
  TerminalFrameDiff? decode(Uint8List rawFrame);
}
```

Both catch malformed input and return null. JSON accepts only a top-level object. Protobuf imports `src/proto/frame_diff.pb.dart`. During this compatibility phase, each codec may call the corresponding public factory, but runtime code outside these codec/facade files must not call those factories directly.

- [ ] **Step 4: Make protobuf normalization use the shared rules**

In `terminal_models.dart`, keep both public factory signatures unchanged. Apply the same bounded scan, valid-item cap, row index dedupe/sort, viewport-column clipping, dirty-range normalization, hyperlink cap and inline-image cap to protobuf mapping that JSON mapping already uses. Unknown enum remains snapshot, invalid colors remain null, scrollback offset remains clamped to max, and direct public constructors continue to be normalized by `TerminalViewportState` as before.

Do not use `hasPreserveAspectRatio()` to reinterpret an absent proto3 scalar as true: Rust/prost omits a real false value on the wire, so that would silently change native false into true. Paired parity fixtures must encode the aspect-ratio value explicitly in JSON and compare it with the protobuf scalar value. Add a separate compatibility test proving that omitted legacy JSON still defaults true and omitted protobuf still defaults false, and document this known wire-default seam in `docs/FRAME_DIFF.md`. Changing the field to proto3 `optional` belongs to a future schema migration, not this schema-preserving phase.

This file may continue importing generated protobuf solely for `TerminalFrameDiff.fromProtobufBytes`; document that import as the public compatibility seam. Do not describe the result as full domain/transport separation.

- [ ] **Step 5: Extend `TerminalFrameDecoder` without breaking `decode`**

Inject const JSON/protobuf codecs with defaults. Implement `decode` as a direct alias to `decodeJson`. Start/stop a stopwatch only when metrics are enabled. Set metrics as follows:

| Entry | `wireFormat` | raw bytes | JSON micros | protobuf micros |
| --- | --- | ---: | ---: | ---: |
| `decodeJson` | `json` | `utf8.encode(raw).length` | measured | 0 |
| `decodeProtobuf` | `protobuf` | `raw.length` | 0 | measured |

No codec may apply a partial frame after an exception.

- [ ] **Step 6: Add the internal transport coordinator**

Use this exact behavior boundary:

```dart
final class TerminalFrameTransportCoordinator {
  TerminalFrameTransportCoordinator({
    required PtySessionBackend backend,
    required TerminalFrameDecoder decoder,
    required TerminalFrameWireFormatPreference preference,
    TerminalBackendRequestErrorHandler? onRequestError,
  });

  TerminalDecodedFrame? take(String sessionId);
}
```

Move `TerminalFrameWireFormatPreference` to this source file if needed, then re-export only that enum from `terminal_runtime_controller.dart` so the old source URI and `ianvs_terminal.dart` keep exposing it. Do not export the coordinator class.

`take` must exactly preserve current semantics: forced JSON reads JSON; automatic reads protobuf only when the backend implements and reports support; supported protobuf returning null/empty means idle and does not trigger JSON; unsupported capability uses JSON; malformed payload returns null; read exceptions report the current operation and return null.

- [ ] **Step 7: Delegate runtime transport without touching apply/order**

Construct one coordinator in `TerminalRuntimeController`. Replace `_takeFrameDiff`, `_takeFrameDiffJson`, `_takeFrameDiffProtobuf`, `_decodeJsonFrame` and `_decodeProtobufFrame` with a single coordinator call plus existing benchmark-metric attachment. Keep `_refreshSessionOnce`, `_refreshSessionDraining`, `_queuePendingFrame`, `_processEvents`, `_applyFrame` and cooldown logic behaviorally unchanged.

Do not fold the decoded-metrics side map into this commit; replacing it with a frame envelope changes the pending-frame pipeline and belongs to a separate measured change.

- [ ] **Step 8: Preserve public exports and document the seam**

Verify that these compile from `package:ianvs_terminal/ianvs_terminal.dart`:

```dart
TerminalFrameDiff.fromJson(const <String, Object?>{});
TerminalFrameDiff.fromProtobufBytes(const <int>[]);
TerminalFrameWireFormatPreference.automatic;
TerminalRuntimeController;
TerminalViewportState.empty;
TerminalRenderIntent.none;
```

The empty protobuf call is both a compile-surface assertion and an existing proto3 compatibility case: the public factory returns a normalized default frame rather than throwing. Test that behavior explicitly. Runtime still treats a backend's null/empty byte result as idle before invoking the decoder. Do not export transport codecs, validation helpers, generated protobuf types or coordinators.

Update `docs/FRAME_DIFF.md` to show:

```text
backend JSON/protobuf -> TerminalFrameTransportCoordinator
                      -> TerminalFrameDecoder facade
                      -> compatibility factory + shared normalization
                      -> TerminalFrameDiff -> TerminalViewportState -> render
```

State explicitly that JSON remains the forced/unsupported compatibility path and public factories prevent complete model-layer decoupling in this minor-version refactor.

- [ ] **Step 9: Run focused green tests**

Run:

```bash
cd packages/ianvs_terminal
flutter test \
  test/terminal_frame_decoder_test.dart \
  test/terminal_frame_codec_parity_test.dart \
  test/terminal_frame_diff_corpus_test.dart \
  test/terminal_runtime_controller_test.dart
```

Expected: PASS. The runtime test must still show protobuf preferred, forced JSON, unsupported fallback, no JSON read on idle protobuf, and no JSON read after malformed protobuf.

- [ ] **Step 10: Run the small transport benchmark as a correctness gate**

Run:

```bash
cd packages/ianvs_terminal
flutter test test/benchmarks/frame_diff_transport_benchmark_test.dart \
  --plain-name "frame diff transport benchmark exports metrics" \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_OUT=/tmp/ianvs-frame-diff-phase7.json \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_ITERATIONS=2 \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_FRAMES=12 \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_ROWS=20 \
  --dart-define=FRAME_DIFF_TRANSPORT_BENCH_COLS=80
```

Expected: PASS; `/tmp/ianvs-frame-diff-phase7.json` contains `frame_hashes_match: true`. Performance ratios are evidence only and have no pass threshold in this refactor.

- [ ] **Step 11: Run the Phase 7 package and repository gates**

Run:

```bash
cd packages/ianvs_terminal
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
cd ../ianvs_pty
dart analyze --fatal-infos
dart test
cd ../..
VERIFY_FLUTTER_TERMINAL_SKIP_MACOS_INTEGRATION=1 ./tools/verify_flutter_terminal.sh
git diff --check
```

Expected: all commands exit 0. No protobuf generation command is required because the schema is unchanged.

- [ ] **Step 12: Perform Phase 7 app QA plus forced-JSON automated QA**

The example app currently has no runtime setting or launch argument that injects `TerminalFrameWireFormatPreference.json`, so do not invent one in this refactor. Run the macOS example with its automatic transport path: create a session, type ASCII and CJK text, produce scrollback, resize, switch tabs, display and clear a graphic, and close the session. Exercise forced JSON through the existing backend/controller tests and paired codec fixture, where the preference is directly injectable. Record complete field-projection parity and final viewport hashes; the hash remains an additional, weaker signal.

- [ ] **Step 13: Commit Phase 7 alone**

Run:

```bash
git add \
  packages/ianvs_terminal/lib/src/transport \
  packages/ianvs_terminal/lib/src/runtime/terminal_frame_decoder.dart \
  packages/ianvs_terminal/lib/src/runtime/terminal_frame_transport_coordinator.dart \
  packages/ianvs_terminal/lib/src/runtime/terminal_runtime_controller.dart \
  packages/ianvs_terminal/lib/src/terminal/terminal_models.dart \
  packages/ianvs_terminal/lib/ianvs_terminal.dart \
  packages/ianvs_terminal/test/support/terminal_frame_wire_fixture.dart \
  packages/ianvs_terminal/test/terminal_frame_decoder_test.dart \
  packages/ianvs_terminal/test/terminal_frame_codec_parity_test.dart \
  packages/ianvs_terminal/test/terminal_frame_diff_corpus_test.dart \
  packages/ianvs_terminal/test/terminal_runtime_controller_test.dart \
  docs/FRAME_DIFF.md
git commit -m "refactor: isolate terminal frame transport"
```

Expected: one Phase 7 commit after the Phase 6 commit, with no `.proto` or generated-file changes.

## Final acceptance

- [ ] Phase 6 and Phase 7 are two separate commits in order.
- [ ] `git show --stat` for Phase 6 contains no transport files; Phase 7 contains no IME extraction or refresh-policy behavior change.
- [ ] Existing public imports and constructor/factory signatures compile unchanged.
- [ ] Complete JSON/protobuf projections match for normal and bounded malformed fixtures.
- [ ] Existing viewport hash parity remains green but is not the only correctness assertion.
- [ ] `git diff HEAD~2 -- native/core/proto packages/ianvs_terminal/lib/src/proto` prints no changes.
- [ ] Full package tests, repository non-GUI gate and the recorded manual checks pass.

After these checks, execute no additional cleanup refactor in either commit. Record any desired model-layer factory removal, decoded-frame envelope work, refresh coordinator extraction or IME boundary redesign as separate future work with its own tests and compatibility decision.
