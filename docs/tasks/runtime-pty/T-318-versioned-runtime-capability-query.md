# T-318 Versioned Runtime Capability Query

## Goal

Add one versioned, machine-readable runtime capability query across the native/Dart boundary
without removing or changing any existing wire.

## Scope

- Define Runtime Capabilities v1 with an explicit schema version, contract id, supported Frame and
  Recording schema versions, and a bounded feature list.
- Export the current manifest from native core through an owned JSON string FFI function.
- Load the new symbol optionally in `ianvs_pty` and expose a typed Dart capability model.
- Preserve additive unknown fields and unknown feature ids for forward compatibility.
- Keep old dynamic libraries usable when the new symbol is absent.
- Add native and Dart contract regressions plus real dynamic-library bridge coverage.

## Non-goals

- Do not remove, rename or migrate existing FFI symbols.
- Do not change Frame JSON/Protobuf, Recording v1, diagnostics or session request payloads.
- Do not introduce a general Command/Event/Asset envelope in this slice.
- Do not make product UI, Workspace, replay UI, remote or plugin behavior depend on the manifest.
- Do not claim Linux or Windows desktop support.

## Files In Scope

- `native/core/src/runtime_contract.rs`
- `native/core/src/ffi.rs`
- `native/core/src/lib.rs`
- `native/core/tests/runtime_capabilities_test.rs`
- `packages/ianvs_pty/lib/ianvs_pty.dart`
- `packages/ianvs_pty/lib/src/native_pty_backend.dart`
- `packages/ianvs_pty/lib/src/pty_runtime_capabilities.dart`
- `packages/ianvs_pty/test/native_pty_backend_test.dart`
- `packages/ianvs_pty/test/runtime_capabilities_test.dart`
- `docs/protocols/RUNTIME_CAPABILITIES_V1.md`
- `docs/tasks/runtime-pty/T-318-versioned-runtime-capability-query.md`

## Functional Acceptance

- Native core returns deterministic Runtime Capabilities v1 JSON with sorted, unique features.
- Dart validates the schema, contract id, field types and collection/string bounds.
- Additive unknown object fields are ignored and unknown feature ids are retained.
- Unsupported schema versions produce a typed error instead of being guessed.
- An older binding without `ianvs_runtime_capabilities_json` returns no manifest while all existing
  backend paths remain usable.
- The real Rust dynamic library returns the same typed manifest through Dart FFI.

## Verification Commands

Reference: [TESTING.md](../../TESTING.md).

```bash
cargo fmt --manifest-path native/core/Cargo.toml -- --check
cargo clippy --manifest-path native/core/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path native/core/Cargo.toml --test runtime_capabilities_test

cd packages/ianvs_pty
dart analyze
dart test test/runtime_capabilities_test.dart test/native_pty_backend_test.dart
dart test

cd ../..
dart test test/docs_contract_test.dart
make verify
```

## Result

- Added `RuntimeCapabilities::current` with one deterministic Runtime Capabilities v1 manifest and
  the owned-string `ianvs_runtime_capabilities_json` export. Its feature ids are sorted and unique.
- Added the public `PtyRuntimeCapabilities` decoder with a 64 KiB input ceiling, bounded unique
  collections, immutable decoded values, explicit schema-version errors and additive v1 feature
  retention.
- `NativePtyBindings` resolves the new symbol optionally and frees returned strings through the
  existing allocator boundary. `NativePtyBackend` lazily exposes the typed result; bindings without
  the symbol still create and operate sessions through the old paths.
- One native manifest/FFI regression and six new Dart model/binding regressions pass, including the
  real Rust dynamic-library bridge. Native Clippy and Dart analysis report no issues.
- `make format-check` passed 397 Dart files. The final `make verify` passed vendored Rust 1,733
  tests with 1 ignored; native core 119 unit, 1 OSC corpus, 1 Runtime Capabilities, 515 session and
  3 `vttest` tests; `ianvs_pty` 30 tests; `ianvs_terminal` 499 tests with 1 intentional skip;
  documentation 12 tests; selected example CI 1,100 tests; macOS smoke 4 tests; real PTY 46 tests;
  and Runner XCTest 17 tests.
- Benchmark evidence is in `build/bench-results-ci/20260721T064315Z`; all six correctness rows have
  `hash_match=true`. The fresh XCTest result passed 17/17 at
  `Test-Runner-2026.07.21_14-45-51-+0800.xcresult`.
- T-318 is closed. The Runtime Contract lane remains active, but any command/event envelope or old
  wire migration requires a separate bounded task.

## Risks / Follow-ups

- A later Runtime Contract slice may add versioned command/event envelopes, but must preserve this
  query and use a separate migration task.
- Capability presence describes the compiled native core; product policy and host evidence remain
  separate decisions.
