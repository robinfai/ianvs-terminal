# Core

- Workspace roots are declared in root `pubspec.yaml`: `example`, `packages/flutterm_pty`, `packages/flutterm_terminal`.
- Architecture entrypoints: `docs/ARCHITECTURE.md`, `docs/TESTING.md`, root `README.md`.
- Read `mem:tech_stack` for language/toolchain pins and package dependencies.
- Read `mem:conventions` for durable ownership boundaries and import constraints.
- Read `mem:suggested_commands` for common dev/test commands.
- Read `mem:task_completion` before claiming a coding task is done.
- Primary runtime stack flows downward: `example` app shell -> `flutterm_terminal` Dart runtime/viewport -> `flutterm_pty` Dart FFI backend -> `native/core` Rust PTY/VT core.
- `native/vendor/par-term-emu-core-rust` is an intentional local fork used by `native/core`; see `docs/DECISIONS/ADR-0002-terminal-core-fork-rationale.md` before changing it.
- `.agents/skills` contains project-local Flutter/Dart skills referenced by `AGENTS.md`; prefer them for UI, testing, routing, theming, accessibility, and architecture work.