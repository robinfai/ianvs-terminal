# Ianvs Fig Completion Sidecar

This sidecar runs a small Fig-style completion service on Node.js and exposes it
to Dart or Rust callers over HTTP.

```bash
cd tools/fig_completion_service
npm test
npm start -- --port 17382
```

The Flutter shell client calls `POST /complete` on
`http://127.0.0.1:17382` by default. Override the endpoint with:

```bash
IANVS_FIG_COMPLETION_URL=http://127.0.0.1:17382 flutter run -d macos
```

Request shape:

```json
{
  "text": "git che",
  "cursorOffset": 7,
  "cwd": "/repo",
  "shell": "/bin/zsh",
  "recentCommands": ["git checkout main"]
}
```

Response shape:

```json
{
  "items": [
    {
      "name": "checkout",
      "insertText": "checkout",
      "replaceStart": 4,
      "replaceEnd": 7,
      "cursorOffset": 12,
      "type": "subcommand",
      "source": "fig:git"
    }
  ]
}
```

The current engine intentionally implements a safe subset of Fig semantics:
static specs, subcommands, options, static argument suggestions, file/folder
templates, and recent command fallback. Dynamic script/custom generators should
be added behind explicit timeout, environment, and cache boundaries.

There is also a WASM backend at `tools/fig_completion_wasm`. It keeps the same
HTTP request/response contract while moving the pure Fig matching core into a
Rust WebAssembly module and leaving filesystem/`kubectl` providers in the host.
