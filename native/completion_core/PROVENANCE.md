# Composer completion catalog

Migrated from this repository's `codex/wasm-completion` branch, commit `56cb8a9f38cb7cb45fcf6545ac46647101673935`.

Matcher: `tools/fig_completion_wasm/rust/src/lib.rs`; catalog: `native/core/src/fig_specs.json`.
Catalog SHA-256: `5986a2f933c6b1e40104b44ff330efcaf8f9f0fa7cd0735ac191f0d922e1022c`.

The catalog is the repository-authored Fig-style declarative subset, not an import of the Fig JavaScript ecosystem. Existing repository licensing applies. No upstream third-party catalog or runtime is downloaded.

Supported: commands, subcommands, options, descriptions, priorities, static argument suggestions, variadic arguments. Declared templates are inert unless a separately authorized host provider supplies them. JS `custom`, `script`, and `postProcess` are unsupported and never evaluated. Short-option grouping, nested shell expressions, redirects and shell expansion are not advertised. The v1 wrapper rejects ambiguous contexts rather than guessing.

The matcher has no filesystem, process, network, FFI, or UI dependencies. Native builds expose no WASM pointer ABI. A WASM wrapper is a separate future target.
