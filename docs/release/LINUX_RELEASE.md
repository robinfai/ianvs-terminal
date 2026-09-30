# Linux desktop build, package and verification

The Linux runner builds the Trail product with GTK 3 and the Rust PTY/VT/SSH
runtime. Windows still has no product runner. Keep source support, automated
coverage, and actual host acceptance results distinct.

## Toolchain

Use Flutter 3.44.2 / Dart 3.12.2 and Rust 1.88.0, matching the repository CI.
Install the development packages for your distribution; on Debian/Ubuntu:

```sh
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev
flutter pub get
make build-linux
make run-linux
```

The CodeAsset hook compiles `libianvs_core.so` for the host's GNU Linux x64 or
arm64 target and Flutter includes it in `bundle/lib`. Only native host builds
are covered by this entrypoint; cross-compilation needs a complete matching
sysroot and Rust target. A supported architecture is not a claim of having
been tested on that architecture.

## Packaging

```sh
make package-linux
```

Produces a relocatable `trail-<version>-linux-<architecture>.tar.gz`, a Debian
package, and SHA256SUMS under `build/linux-packages`. The tar archive keeps
`trail`, `lib/` and `data/` together; run the executable after extraction.
The Debian package installs into `/opt/trail` and adds a desktop entry. Build
on the oldest distribution you intend to support: its glibc/compiler baseline
can constrain the result. The packaging script computes the glibc requirement
from every packaged ELF; it does not bundle the system GTK or keyring service.
`SKIP_BUILD=1 tools/package_linux.sh` packages an already verified release.

Verify package contents, SHA256, `ldd` dependencies, and a fresh extracted
launch. Re-run with a path containing spaces and an isolated XDG data home.
Only application binaries/assets belong in a package, never user keyrings,
SSH credentials, profiles, recordings, or validation fixture data.

## Desktop behavior and boundaries

- Default shell: explicit `IANVS_DEFAULT_SHELL`, then an executable Linux
  `$SHELL`, then bash/sh fallbacks. Existing saved profile commands are retained.
- Linux shortcuts preserve shell control chords; app defaults use Ctrl+Shift.
  Exact user keybindings remain configurable.
- GTK handles folder/file/recording/ZMODEM pickers, window metrics/title,
  urgency, MIME clipboard, URL/path opening, Trash and drag/drop.
- Clipboard selections `c`, `p`, `s` map to CLIPBOARD, PRIMARY, SECONDARY.
  Apple-specific find/font pasteboards are explicitly unsupported and cannot
  overwrite the regular clipboard. Selection support also depends on the
  window system; Wayland and other compositors require separate acceptance.
- Native close waits for the Dart shutdown coordinator; unsafe, malformed or
  timed-out results keep the window open so recording and session cleanup is
  not abandoned. Retry is allowed after an observation timeout.
- Encrypted local credentials require a running and unlocked freedesktop
  Secret Service such as GNOME Keyring or a compatible KWallet. There is no
  plaintext fallback. Linux keys do not automatically synchronize with Apple
  iCloud Keychain; explicit portable-key transfer remains user controlled.
- Local profiles/settings/layout/recordings and optional remote API sync are
  available. The bundled local Go API sidecar remains a macOS-only delivery;
  Linux does not silently select it or ship it.
- Desktop notifications require the freedesktop notification service.
  Physical input method, cross-monitor HiDPI, GPU/compositor variations and
  platform font appearance require manual acceptance on the target desktop.

## Automated acceptance

```sh
make analyze
# See TESTING.md for the external-trace benchmark exception.
make test
cd example
flutter test -d linux integration_test/linux_platform_bridge_test.dart
flutter test -d linux integration_test/linux_desktop_acceptance_test.dart
flutter test -d linux integration_test/linux_font_rendering_test.dart
flutter test -d linux integration_test/real_pty_acceptance_test.dart
```

The Linux-specific gates use real GTK platform channels and actual encrypted
storage, plus the production startup coordinator and a native shell. The
cross-desktop PTY suite exercises rendering/input/resize, alternate-screen,
Unicode and host-effect lifecycles. An unavailable display/keyring is a blocked
gate, not a pass. `.github/workflows/linux-desktop.yml` provisions Xvfb and an
isolated D-Bus/keyring for CI. Its synthetic fixtures never use real credentials.
The stronger Docker-based SSH/PAM/multihop and pinned GNU lrzsz interoperability
jobs remain independent; a local SSH smoke test does not replace them.

A non-privileged independent-peer network gate is also available:

```sh
python3 -m venv .venv-linux-e2e
.venv-linux-e2e/bin/pip install -r tools/linux_e2e/requirements.txt
# Install the distribution lrzsz package first.
IANVS_LOOPBACK_PYTHON="$PWD/.venv-linux-e2e/bin/python" tools/linux_e2e/run.sh
```

It uses an ephemeral loopback-only AsyncSSH peer and synthetic keys to check
native SSH, real PTY, SFTP, and GNU lrzsz batches. It does not replace the
separate pinned OpenSSH/PAM/OTP/multi-hop/forwarding matrix.

## Bundled default font

The default JetBrainsMono Nerd Font Mono is bundled as four unchanged Regular,
Bold, Italic and BoldItalic faces from Nerd Fonts v3.4.0 / JetBrains Mono 2.304.
The package includes OFL 1.1, upstream and patcher attribution, source URLs and
SHA-256 values. Existing profiles using the default family automatically resolve
to the package font; explicitly selected custom families are preserved. CJK and
color emoji remain system fallbacks. `tools/verify_linux_font_bundle.py` checks
the actual release bundle for all four faces, licenses and their exact hashes.
