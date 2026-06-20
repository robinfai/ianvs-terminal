# Ianvs Fig Completion WASM Sidecar

This is the WebAssembly variant of the Fig-style completion sidecar. The Rust
WASM module owns the command/spec parser, subcommand matching, option matching,
static argument suggestions, sorting, and replacement range calculation. The
Node.js host keeps the platform-bound pieces: HTTP, filesystem path templates,
and bounded `kubectl` calls.

The HTTP contract matches the Node.js sidecar, so Flutter can switch backends by
changing `IANVS_FIG_COMPLETION_URL`.

```bash
rustup target add wasm32-unknown-unknown
cd tools/fig_completion_wasm
npm test
npm start -- --port 17383
```

Then point the app at the WASM service:

```bash
IANVS_FIG_COMPLETION_URL=http://127.0.0.1:17383 flutter run -d macos
```

The built module is generated at `dist/fig_completion_core.wasm`. It is ignored
by git; rebuild it with `npm run build:wasm` after changing the Rust core.

Request shape:

```json
{
  "text": "ls ./",
  "cursorOffset": 5,
  "cwd": "/repo",
  "recentCommands": ["git status"]
}
```

Response shape:

```json
{
  "items": [
    {
      "name": "./example/",
      "insertText": "./example/",
      "replaceStart": 3,
      "replaceEnd": 5,
      "cursorOffset": 13,
      "type": "folder",
      "source": "fig:filepaths"
    }
  ]
}
```
