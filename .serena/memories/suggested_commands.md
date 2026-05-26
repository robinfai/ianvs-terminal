# Suggested Commands

- Install/resolve workspace packages: `dart pub get` from repo root.
- Run app: `cd example && flutter run -d macos`.
- Example app checks: `cd example && flutter analyze`; `cd example && flutter test`; `cd example && flutter test -d macos integration_test/flutterm_smoke_test.dart`.
- Terminal package checks: `cd packages/flutterm_terminal && flutter test`.
- PTY package checks: `cd packages/flutterm_pty && dart test`.
- Native checks: `cd native/core && cargo fmt --check`; `cd native/core && cargo test`.
- Build native core dylib: `./tools/build_core.sh`; set `PROFILE=release` for release build.
- Full default verification helper: `./tools/verify_flutter_terminal.sh`.
- Local-terminal verification status only: `bash tools/local_terminal_verification_status.sh`.
- Print local-terminal automated batches without running: `bash tools/local_terminal_verification_batches.sh print all-automated`.
- Capture local-terminal automated batch output only after explicit approval: `bash tools/local_terminal_verification_capture.sh run all-automated`.
- Serena memory sanity check after onboarding or memory edits: `serena memories check` from repo root.