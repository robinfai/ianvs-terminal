# T-329 Replay Graphic Asset Bundle

## Goal

Persist the decoded RGBA needed by recorded graphic placements in a bounded,
deterministic Recording v2 bundle, then let ReplayBackend resolve an exact recorded
asset before falling back to the native cache.

## Scope

- Add immutable public Recording graphic-asset values keyed by positive
  `(asset_id, asset_version)`.
- Add explicit v1/v2-to-v2 bundling without changing live native v1 capture.
- Store unique decoded RGBA in content-addressed `graphic_asset_blob` records and
  separate canonical identity references.
- Bound one recording to 128 identities, 128 unique blobs and 32 MiB of unique
  decoded RGBA.
- Validate dimensions, RGBA length, SHA-256, session/schema identity, ordering,
  duplicate identities, missing references and unreferenced blobs.
- Preserve bundled assets when a checkpoint plan is added or replaced.
- Resolve bundled assets through `TerminalReplayBackend.loadGraphicAsset` before
  the optional native delegate, while retaining fallback for absent identities.

## Non-goals

- Do not change Recording v1 bytes, the live native recorder or Frame wire.
- Do not capture assets continuously from the product runtime in this slice.
- Do not serialize native `TerminalSnapshot`, parser internals or pending graphic
  downloads.
- Do not manufacture graphic placements from blobs; placement remains part of
  replayed output/Frame state.
- Do not record full Host Request/Response traffic or replay historical Host
  effects.
- Do not add pause, scrubber, Replay UI, recording-library UI or product wiring.
- Do not claim the SHA-256 content address provides authenticity.

## Files In Scope

- `packages/ianvs_terminal/pubspec.yaml`
- `packages/ianvs_terminal/lib/src/recording/terminal_recording.dart`
- `packages/ianvs_terminal/lib/src/recording/terminal_replay_backend.dart`
- `packages/ianvs_terminal/test/fixtures/recording/graphics_v2.ndjson`
- `packages/ianvs_terminal/test/terminal_recording_codec_test.dart`
- `packages/ianvs_terminal/test/terminal_replay_backend_test.dart`
- `docs/recording/FORMAT_V2.md`
- `docs/tasks/runtime-pty/T-329-replay-graphic-asset-bundle.md`
- `docs/tasks/README.md`
- `docs/ROADMAP.md`
- `docs/CURRENT_EXECUTION_TARGET.md`
- `docs/CURRENT_EXECUTION_TARGETS.json`

## Format And Compatibility Contract

- A canonical v2 file orders metadata, SHA-256-sorted blobs, identity-sorted
  references and then ordered events.
- SHA-256 covers UTF-8 `width:height:` followed by decoded RGBA. Equal dimensions
  and bytes therefore share one blob across multiple identities.
- V1 cannot directly contain asset records. The explicit bundler upgrades all
  metadata and events to v2, preserving event kinds, payloads, offsets and order.
- Decode is all-or-error. Corrupt, missing, duplicate, oversized and out-of-order
  asset records never produce a plausible partial recording.
- Replay returns a defensive byte copy for an exact bundled identity. An absent
  identity still calls the native asset delegate when available.

## Functional Acceptance

- The fixed v2 fixture re-encodes byte-for-byte and stores identical RGBA once for
  two asset identities.
- The bundler upgrades a validated v1 file explicitly and checkpoint planning
  retains its assets.
- V1 remains byte-stable and rejects direct asset insertion.
- Caller and replay consumers cannot mutate the stored bundle bytes.
- Same-length corruption, missing references, identity overflow and RGBA size
  drift return structured errors.
- Replay serves an exact bundled asset before native fallback and delegates an
  absent identity unchanged.
- The complete terminal package and repository verification entrypoint pass.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cd packages/ianvs_terminal
flutter analyze --fatal-infos
flutter test test/terminal_recording_codec_test.dart \
  test/terminal_recording_checkpoint_test.dart \
  test/terminal_replay_backend_test.dart
flutter test

cd ../..
dart test test/docs_contract_test.dart
make format-check
make verify
```

## Result

T-329 is closed. The focused recording, checkpoint and replay set passes 39 tests,
strict analysis has no findings, and the terminal package passes 549 tests with one
intentional skip. The complete repository gate passes 1,733 vendor Rust tests with
one ignored case, 131 native-core unit tests, 518 native session tests, 3 `vttest`
regressions, 57 PTY tests, 12 documentation contracts, 1,100 example tests, 4 macOS
smoke tests, 46 real PTY tests and all 17 XCTest cases. All six benchmark rows report
`hash_match=true` in `build/bench-results-ci/20260721T122846Z`.

## Risks / Follow-ups

- The bundler is a post-capture seam. Product recording lifecycle integration must
  separately decide which referenced asset keys to fetch and when to persist them.
- Bundles restore decoded asset bytes, not placement or native cache lifetime.
- Full Host effect recording, pause and Replay UI require independent contracts.
