# Conventions

- Keep shared terminal capability in packages, not in `example`: `flutterm_pty` owns PTY transport/FFI; `flutterm_terminal` owns runtime config, input, viewport, selection, scroll/focus adapters.
- `example` owns app concerns: tabs, window shell, menus, profiles, defaults/appearance UI, demo fixtures, platform clipboard bridge.
- `example` should consume terminal/pty packages through local boundary files: `example/lib/features/terminal/terminal.dart`, `example/lib/features/pty/pty.dart`, and `example/lib/platform/clipboard_bridge.dart`.
- Do not expose app vocabulary such as Profile/tab/window chrome from `flutterm_pty`; do not expose app `Profile` from `flutterm_terminal`.
- `flutterm_terminal` internally adapts neutral `TerminalSessionConfig` into the older native wire shape needed by `native/core`; do not push that compatibility detail into app code.
- Shell chrome may observe `SessionState`; session metadata mutations should go through `SessionController`. Avoid adding new shell -> core direct write paths without proving controller abstraction is insufficient.
- Protected terminal contracts from `docs/DECISIONS/ADR-0001-hyper-phase0-shell-boundaries.md`: input path, selection semantics, clipboard semantics, focus handoff, resize routing, scroll routing, PTY event delivery.
- UI generation should use project/theme tokens and Material 3 guidance from `AGENTS.md`; do not hard-code widget colors unless documented.