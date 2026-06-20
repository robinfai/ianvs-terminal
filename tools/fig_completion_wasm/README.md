# Ianvs Fig Completion WASM Core

This directory contains the Rust WebAssembly completion core used for portable
Fig-style command matching. The desktop Flutter app does not run completion
through Node.js or HTTP; desktop completion is provided by `libianvs_core`
through Dart FFI.

The WASM core remains useful for future web or sandboxed runtimes. Build it
directly with Cargo:

```bash
rustup target add wasm32-unknown-unknown
cargo build --manifest-path tools/fig_completion_wasm/rust/Cargo.toml --release --target wasm32-unknown-unknown
```

The native desktop FFI implementation lives in `native/core/src/fig_completion.rs`
and calls the same Rust completion core in-process.
