#!/usr/bin/env python3
"""Launch the opt-in desktop PRD fixture using ordinary production UI paths."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


REPOSITORY = Path(__file__).resolve().parents[2]
MARKER = ".trail-desktop-prd-fixture.v1.json"
ENVIRONMENT_KEYS = (
    "HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "TERM",
)


def checked_fixture_root(path):
    root = Path(path).absolute()
    if root.is_symlink() or (root.exists() and not root.is_dir()):
        raise ValueError("Fixture root must be a directory, not a link.")
    root = root.resolve()
    if root.exists() and any(root.iterdir()):
        marker = root / MARKER
        expected = {
            "schema_version": 1,
            "purpose": "trail-desktop-prd-manual",
            "root": str(root),
        }
        try:
            actual = None if marker.is_symlink() else json.loads(marker.read_text())
        except (OSError, ValueError):
            actual = None
        if actual != expected:
            raise ValueError("Refusing a nonempty directory without its matching PRD fixture marker.")
    return root


def launch_environment(source, flutter):
    # HOME remains the host home for build tools and the existing opt-in ACP
    # environment/authentication loader. Every local PTY receives the fixture
    # HOME instead; this does not change production ACP's process allowlist.
    # Never forward API credentials, SSH_AUTH_SOCK, CODEX_HOME or arbitrary
    # build/runtime injection variables from the invoking terminal.
    environment = {key: source[key] for key in ENVIRONMENT_KEYS if key in source}
    home = environment.get("HOME")
    if not home or not Path(home).is_absolute():
        raise ValueError("The host HOME must be an absolute path.")
    environment["PATH"] = os.pathsep.join(dict.fromkeys([
        str(Path(flutter).parent),
        str(Path(home) / ".cargo/bin"),
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        "/usr/sbin", "/sbin",
    ]))
    return environment


def launch_command(flutter, root, *, text_entry_emulation=False):
    return [
        str(flutter), "run", "--debug", "--no-pub", "-d", "macos",
        "-t", "tool/desktop_prd_acceptance.dart",
        f"--dart-define=TRAIL_DESKTOP_PRD_DIRECTORY={root}",
        "--dart-define=TRAIL_UI_NATIVE_KEYBOARD="
        + ("false" if text_entry_emulation else "true"),
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-dir", type=Path,
                        help="Empty directory or a fixture previously created by this entrypoint.")
    parser.add_argument("--flutter", type=Path,
                        help="Flutter executable; defaults to the executable found on PATH.")
    parser.add_argument("--text-entry-emulation", action="store_true",
                        help="Allow FlutterDriver enterText; not valid evidence for native IME.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print the command and environment key names without starting Flutter.")
    args = parser.parse_args(argv)
    try:
        flutter = args.flutter or shutil.which("flutter")
        if flutter is None:
            raise ValueError("Provide --flutter with the Flutter executable path.")
        flutter = Path(flutter).absolute()
        if not flutter.is_file() or not os.access(flutter, os.X_OK):
            raise ValueError("Flutter must be an existing executable file.")
        root = checked_fixture_root(
            args.fixture_dir or Path(tempfile.mkdtemp(prefix="trail-desktop-prd-"))
        )
        environment = launch_environment(os.environ, flutter)
        command = launch_command(
            flutter, root, text_entry_emulation=args.text_entry_emulation,
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(json.dumps({
        "fixture_directory": str(root),
        "working_directory": str(REPOSITORY / "example"),
        "command": command,
        "environment_keys": sorted(environment),
        "fixture_only": ["AI configuration", "master key", "profiles/layout", "local shell home"],
        "native_keyboard": not args.text_entry_emulation,
    }, indent=2), flush=True)
    if args.dry_run:
        return 0
    try:
        return subprocess.run(command, cwd=REPOSITORY / "example", env=environment,
                              check=False).returncode
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
