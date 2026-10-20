#!/usr/bin/env python3
"""Read-only native ownership check for the accessibility integration fixture.

This does not enable VoiceOver, read speech, activate windows, or authorize any
later read. A speech reviewer must recheck ownership before every observation.
"""

import argparse
import json
from pathlib import Path
import subprocess
import time


APPLESCRIPT = '''on run argv
set fixturePID to (item 1 of argv) as integer
set expectedTitle to item 2 of argv
tell application "System Events"
if (count of (every application process whose unix id is fixturePID)) is not 1 then return "not-ready"
set actualPID to unix id of (first application process whose unix id is fixturePID)
if actualPID is not fixturePID then error "Fixture PID does not match"
set fixtureTitles to name of every window of (first application process whose unix id is fixturePID)
if fixtureTitles does not contain expectedTitle then return "not-ready"
set isForeground to frontmost of (first application process whose unix id is fixturePID)
return "verified|" & actualPID & "|" & isForeground
end tell
end run'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('scope', type=Path, help='Fresh fixture scope.json')
    parser.add_argument('--timeout', type=float, default=30)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    executable = root / (
        'example/build/macos/Build/Products/Debug/'
        'Trail Development.app/Contents/MacOS/Trail Development'
    )
    deadline = time.monotonic() + min(max(args.timeout, 0), 60)
    fixture_pid = None
    while time.monotonic() < deadline:
        try:
            scope = json.loads(args.scope.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            time.sleep(0.25)
            continue
        if time.time() - args.scope.stat().st_mtime > 120:
            raise SystemExit('Stale scope; no native UI read attempted')
        pid = scope.get('pid')
        if type(pid) is not int or pid <= 0:
            raise SystemExit('Invalid fixture PID; no native UI read attempted')
        if fixture_pid is not None and fixture_pid != pid:
            raise SystemExit('Fixture PID changed; stopping ownership check')
        fixture_pid = pid
        title = f'Trail Accessibility Fixture · {pid}'
        if scope.get('window_title') != title:
            raise SystemExit('Unexpected title; no native UI read attempted')
        process = subprocess.run(
            ['/bin/ps', '-p', str(pid), '-o', 'comm='],
            capture_output=True, text=True, timeout=5,
        )
        if process.returncode != 0 or process.stdout.strip() != str(executable):
            raise SystemExit('Fixture process is absent or changed; stopping')
        native = subprocess.run(
            ['/usr/bin/osascript', '-e', APPLESCRIPT, str(pid), title],
            capture_output=True, text=True, timeout=5,
        )
        if native.returncode != 0:
            raise SystemExit('Native ownership read failed; stopping')
        value = native.stdout.strip()
        # Do not save an AppleScript process object: System Events can turn it
        # into a name-based reference and resolve another same-named app. Each
        # native property above retains its PID filter, and the result checks
        # both that PID and the fixture's unique native title.
        if value in (f'verified|{pid}|true', f'verified|{pid}|false'):
            print(json.dumps({
                'pid': pid,
                'expected_title': title,
                'native_title_verified': True,
                'foreground': value == f'verified|{pid}|true',
                'stage': scope.get('stage'),
                'verified_at_epoch': time.time(),
                'voiceover_accessed': False,
                'speech_verified': False,
            }, ensure_ascii=False, indent=2))
            return
        if value != 'not-ready':
            raise SystemExit('Unexpected native ownership result; stopping')
        time.sleep(0.25)
    raise SystemExit('Native title did not become ready; no speech read attempted')


if __name__ == '__main__':
    main()
