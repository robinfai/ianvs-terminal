# Task Completion

- Choose verification by touched boundary, per `docs/TESTING.md`.
- Native/PTY changes: run `cd native/core && cargo fmt --check && cargo test`; run `cd packages/ianvs_pty && dart test` when Dart FFI/backend code is touched.
- `packages/ianvs_terminal` changes: run `cd packages/ianvs_terminal && flutter test`.
- `example` changes: run `cd example && flutter analyze`; run `cd example && flutter test`.
- Cross-boundary FFI/runtime/viewport/shell changes: run native fmt/test, PTY package tests, terminal package tests, example analyze, and example tests.
- macOS smoke currently needs explicit device: `cd example && flutter test -d macos integration_test/ianvs_smoke_test.dart`; unspecified device discovery may hang on Android adb discovery.
- Changes touching terminal emulation, shortcut routing, trackpad scrollback, viewport scroll, or host-GUI behavior may also require the T-059/manual lane referenced by `docs/TESTING.md`.
- `./tools/verify_flutter_terminal.sh` is the broad helper; note it includes native build/checks, package tests, example analyze/tests, and grep guards for Phase 3 defaults write path constraints.
- Before final completion, report commands actually run and any commands skipped or blocked.