# Tech Stack

- Root package is a Dart workspace aggregator with `sdk: ^3.11.0`; roots: `example`, `packages/flutterm_pty`, `packages/flutterm_terminal`.
- `example` is a Flutter macOS app currently named `app`; dependencies include `flutter_riverpod`, `flutterm_pty`, `flutterm_terminal`, `path_provider`, `ffi`, and `cupertino_icons`.
- `packages/flutterm_terminal` is a Flutter package with `flutter: >=3.41.0`, `resolution: workspace`, and a path dependency on `flutterm_pty`.
- `packages/flutterm_pty` is a Dart package using `ffi`; it wraps the native dylib through `NativePtyBindings` / `NativePtyBackend`.
- `native/core` is Rust 2024 crate `flutterm_core`, built as `cdylib` and `rlib`; dependencies include `portable-pty`, `parking_lot`, `serde`, `serde_json`, `regex`, `libc`, and the vendored `par-term-emu-core-rust` path dependency.
- Flutter analyzer config currently lives under `example/analysis_options.yaml` and includes `package:flutter_lints/flutter.yaml`; root has no `analysis_options.yaml`.
- Native dylib discovery can be overridden with `FLUTTERM_CORE_LIB`; otherwise `flutterm_pty` searches app Frameworks/Resources and workspace debug build paths.