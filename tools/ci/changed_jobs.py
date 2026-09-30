"""Select expensive jobs from a complete git diff; unknown paths run all jobs."""

import json
import os
import subprocess
from pathlib import Path

JOBS = frozenset(('flutter', 'native', 'backend', 'macos', 'ios'))
CLIENT = frozenset(('flutter', 'macos', 'ios'))


def jobs_for_paths(paths):
    selected = set()
    for path in paths:
        if path.startswith(('docs/', 'test/')) or path in (
            'README.md', 'CHANGELOG.md', 'LICENSE', 'AGENTS.md',
        ):
            # The always-on contracts job validates docs, formatting and analysis.
            continue
        if path.startswith(('.agents/', '.codex/')):
            continue
        if path.startswith('backend/'):
            # The macOS bundle embeds the Go server; iOS does not.
            selected.update(('backend', 'macos'))
        elif path.startswith(('native/', 'packages/')):
            selected.update(CLIENT)
            selected.add('native')
        elif path.startswith('example/macos/'):
            selected.update(('flutter', 'macos'))
        elif path.startswith('example/ios/'):
            selected.update(('flutter', 'ios'))
        elif path.startswith('example/test/support/'):
            # Integration tests import these helpers on both Apple platforms.
            selected.update(CLIENT)
        elif path.startswith('example/test/'):
            selected.add('flutter')
        elif path.startswith('example/') or path in (
            'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
        ):
            selected.update(CLIENT)
        else:
            # Tooling, workflows and new modules must never silently skip gates.
            selected.update(JOBS)
    return selected


def changed_paths(event_name, event):
    if event_name == 'pull_request':
        base = event['pull_request']['base']['sha']
        head = event['pull_request']['head']['sha']
        base = subprocess.check_output(
            ['git', 'merge-base', base, head], text=True,
        ).strip()
    elif event_name == 'push' and event.get('before', '').strip('0'):
        base, head = event['before'], event['after']
    else:
        return None
    result = subprocess.check_output(
        ['git', 'diff', '--name-only', '--no-renames', '-z', base, head],
    )
    return result.decode('utf-8', errors='surrogateescape').split('\0')[:-1]


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    try:
        paths = changed_paths(os.environ['GITHUB_EVENT_NAME'], event)
    except (KeyError, subprocess.CalledProcessError):
        # Missing bases (e.g. force pushes) expand coverage rather than narrow it.
        paths = None
    selected = JOBS if paths is None else jobs_for_paths(paths)
    output = ''.join(f'{job}={str(job in selected).lower()}\n' for job in sorted(JOBS))
    with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
        stream.write(output)
    print(output, end='')
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
        stream.write('Contracts, formatting and analysis always run.\n\n')
        stream.write('Selected jobs: ' + (', '.join(sorted(selected)) or 'contracts only') + '\n')
        if paths is None:
            stream.write('Manual run or unavailable diff: all platform gates enabled.\n')


if __name__ == '__main__':
    main()
