# Desktop PRD manual fixture

Launch from the repository root with a new fixture directory:

```sh
python3 tools/desktop_prd/run_manual.py --flutter /path/to/flutter/bin/flutter
```

The launcher prints the directory. Reuse it with `--fixture-dir /absolute/path`
to keep settings manually entered in this fixture. A nonempty directory is
rejected unless its versioned marker matches its canonical path. The launcher
does not create that marker: the Dart entrypoint writes it only after completing
initial setup. An interrupted setup should use a fresh empty directory.

`--dry-run` prints the exact command and environment key names without running
Flutter. It may allocate an empty temporary directory when no directory was
given. The ordinary Debug app is built in `example/build`, never installed in
`/Applications`. Close another checkout's **Trail Development** window before
manual acceptance, and capture only the newly launched PID at this build path.
The bundle identity is the existing development identity, not a new product.
Native macOS window frame autosave therefore shares the development app's
UserDefaults domain; resizing this fixture can change that development app's
saved window position/size. The release app has a different identity. The data
isolation below does not claim to isolate this native preference.

## Isolation boundary

- `tool/desktop_prd_acceptance.dart` uses the real production startup coordinator,
  runtime graph, native PTY, repositories, shutdown handling and widgets.
- AI settings use a development file store inside this fixture. Its development
  master key also stays in the fixture and disables legacy/keychain migration.
  Both stores contain plaintext development secrets in owner-only storage; use
  a dedicated test key. This exception belongs only to this opt-in entrypoint.
- Profiles, layout, preferences, recordings and the local data service use
  `app-support/development-file-v1` below the fixture root. No production profile,
  SSH private key or AI configuration is copied or imported. The initial profile
  is a real `/bin/zsh -l` shell with a fixture working directory and `.zshrc`.
- Every local PTY receives the fixture HOME, ZDOTDIR, XDG paths and TMPDIR through
  the existing session environment override. Reuse leaves manual profile and AI
  edits intact. This is **data isolation, not a shell sandbox**: explicit commands
  still have the logged-in user's filesystem permissions. An explicitly edited
  profile may choose another working directory; SSH uses the manually configured
  remote environment.
- The launcher forwards a small environment allowlist. API keys, SSH agent
  sockets, CODEX_HOME and runtime injection variables are not inherited. Host
  HOME remains available to build tools. After selecting/configuring ACP in the
  normal UI, the existing ACP auth loader may use the user's Codex login. The
  existing ACP process allowlist also includes host HOME, while CODEX_HOME is a
  separate private temporary directory; this tool does not claim to sandbox ACP
  against the host home. The fixture scripts never read or copy auth.

No model backend is preconfigured. Configure a dedicated model endpoint/key, or
explicitly select ACP, using the normal AI connection UI. Approvals, task creation
and execution follow the normal controls. A local deterministic model server can
be configured manually, but its evidence must be labeled as a fixture rather
than a real-model result.

## UI driver and evidence

The entrypoint composes Flutter's standard driver extension with the fixture
startup. There is no requestData handler, acceptance probe, controller injection
or automatic approval path. Native keyboard input is the default for manual
IME/shortcut checks. `--text-entry-emulation` enables standard driver `enterText`
for ordinary UI flows; results in that mode do not prove native IME behavior.

Use standard taps, text input, scrolling and screenshots (or native mouse and
keyboard actions). Capture the isolated app window by its exact build path and
new PID. Full-window capture is needed for traffic lights and chrome; native
close-alert windows need their own same-PID capture. A fixed main-window movie
does not prove window movement; record its before/after screen bounds as well.
Widget screenshots alone do not establish these native behaviors.

Record source commit, actual app/native library hashes, OS/build, locale/theme,
window dimensions/DPR, fixture path, keyboard mode and exact steps with each
result. Keep test credentials and secret files out of logs and evidence. Keep
the fixture while follow-up acceptance needs its manually configured settings;
remove that explicitly chosen directory only when the run is finished.
