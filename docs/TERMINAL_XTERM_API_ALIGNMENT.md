# Terminal xterm.js API Alignment Review

## Reference Surface

Primary references:

- xterm.js `Terminal` class API: <https://xtermjs.org/docs/api/terminal/classes/terminal/>
- xterm.js `ITerminalOptions`: <https://xtermjs.org/docs/api/terminal/interfaces/iterminaloptions/>
- xterm.js `ITerminalAddon`: <https://xtermjs.org/docs/api/terminal/interfaces/iterminaladdon/>
- xterm.js `IDisposable`: <https://xtermjs.org/docs/api/terminal/interfaces/idisposable/>

The current Dart package cannot map xterm.js DOM APIs 1:1 because rendering is
Flutter widget based and PTY I/O is handled by `TerminalRuntimeController`.
The alignment target is therefore the stable public shape: terminal lifecycle,
options, events, resize/scroll/selection, and addon lifecycle.

## Implemented Alignment

Added a public xterm-style facade in `ianvs_terminal.dart`:

- `Terminal`
- `TerminalOptions`
- `TerminalTheme`
- `TerminalCursorStyle`
- `TerminalAddon`
- `TerminalDisposable`
- `TerminalInputEvent`
- `TerminalRenderEvent`
- `TerminalResizeEvent`
- `TerminalExitEvent`

The facade wraps existing runtime/session/viewport controllers instead of
replacing them. This keeps existing low-level APIs working while offering a
more familiar integration point for xterm.js-style addons and consumers.

## API Matrix

| xterm.js surface | ianvs terminal alignment | Status | Notes |
| --- | --- | --- | --- |
| `new Terminal(options)` | `Terminal(runtime, sessionConfig, options)` | Partial | Dart must receive runtime/backend and launch config explicitly. |
| `terminal.options` | `Terminal.options` | Partial | Supported options map to existing session/display/interaction config. Runtime hot mutation is not fully implemented. |
| `open(element)` | `Terminal.open()` | Partial | Starts a Flutter/PTY session. No DOM element parameter. |
| `dispose()` | `Terminal.dispose()` | Aligned | Closes the active session, disposes loaded addons, and tears down subscriptions. |
| `loadAddon(addon)` | `Terminal.loadAddon(TerminalAddon)` | Aligned | Activates addon and registers it for terminal-owned disposal. |
| `IAddon.activate(terminal)` | `TerminalAddon.activate(Terminal)` | Aligned | Addons receive the facade, not the lower-level runtime. |
| `IDisposable.dispose()` | `TerminalDisposable.dispose()` | Aligned | Event subscriptions and addons use the same disposal contract. |
| `onData` | `Terminal.onData` | Partial | Emits UTF-8 decoded PTY input sent through runtime. Direct emulator output parsing is not exposed. |
| `write`, `writeln`, `paste` | `Terminal.write`, `writeln`, `paste` | Partial | Mapped to PTY input in this package. xterm.js `write` writes emulator output, so this is intentionally documented as a host-session mapping. |
| `onRender` | `Terminal.onRender` | Aligned | Derived from dirty frame ranges. |
| `onResize` | `Terminal.onResize` | Aligned | Runtime now emits resize events for viewport-driven and cell-driven resize. |
| `resize(cols, rows)` | `Terminal.resize(cols, rows)` | Aligned | Runtime now supports cell-size resize without requiring a Flutter viewport size. |
| `onScroll` | `Terminal.onScroll` | Aligned | Emits current scrollback offset from frame state. |
| `scrollLines`, `scrollPages`, `scrollToTop`, `scrollToBottom`, `scrollToLine` | Same method names | Aligned | Backed by native scrollback offset APIs. |
| `onSelectionChange`, `hasSelection`, `getSelection`, `getSelectionPosition` | Same method names | Aligned | Selection text still comes from native selection extraction. |
| `onTitleChange` | `Terminal.onTitleChange` | Aligned | Derived from frame `windowTitle`. |
| `clear`, parser APIs, buffer namespace, marker APIs, Unicode APIs, link providers, decorations, custom key handlers | Not exposed | Gap | These require native emulator support or Flutter-specific design before adding stable public API. |

## Addon Design Review

xterm.js addons are small lifecycle objects activated with a terminal instance
and disposed either manually or by the owning terminal. The new Dart design
matches that core contract:

- Addons implement `TerminalAddon`.
- Addons subscribe through `Terminal.onData`, `onResize`, etc.
- Each subscription returns `TerminalDisposable`.
- `Terminal.dispose()` disposes addons in reverse load order.

Not implemented yet:

- First-party addon packages equivalent to FitAddon, SearchAddon, WebLinksAddon,
  or AttachAddon.
- Proposed/private API gating like xterm.js `allowProposedApi`.
- Addon isolation/version negotiation.

Recommended next addons:

- `TerminalFitAddon`: read measured cell size and container size, then call
  `Terminal.resize`.
- `TerminalSearchAddon`: wrap `TerminalRuntimeController.searchText` and expose
  xterm-style next/previous search navigation.
- `TerminalWebLinksAddon`: adapt existing hyperlink ranges and visible URL
  detection to a stable addon API.

## Remaining Semantic Gaps

- `Terminal.write` currently sends data to the backing PTY. xterm.js uses
  `write` for emulator output. A strict emulator-level write API needs a native
  parser entry point separate from PTY stdin.
- Runtime options are applied at session creation. Post-open option mutation
  needs a native config update path before it can be fully xterm-compatible.
- Flutter rendering has no DOM `open(element)` equivalent. Widget composition
  remains `TerminalViewport`.
- Link providers, decorations, parser hooks, markers, and buffer namespaces need
  explicit Dart data models rather than direct TypeScript shape copying.

## Verification

- `flutter analyze`
- `cd packages/ianvs_terminal && flutter test`
- `cd packages/ianvs_pty && dart test`
- `cd example && flutter test`

The new tests cover:

- options-to-session-config mapping;
- cell-based resize API;
- addon activation/disposal lifecycle;
- `onData`/`onInput`;
- frame-derived render, scroll, title, selection events;
- resize and exit event mapping.
