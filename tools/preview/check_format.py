"""Check task Dart files; retain formatter suggestions without changing CI source."""
from pathlib import Path
import subprocess

BASE = '967bd3a0cd2c262a85aae8ac86f7b73e933fa058'
files = subprocess.check_output(
    ['git', 'diff', '--name-only', '--diff-filter=ACMR', BASE, 'HEAD', '--', '*.dart'],
    text=True,
).splitlines()
output = Path('build/foundation-format.patch')
output.parent.mkdir(exist_ok=True)
if not files:
    output.write_text('')
else:
    # The next steps analyze/test/build HEAD, not a silently formatted variant.
    try:
        subprocess.run(['dart', 'format', *files], check=True)
        patch = subprocess.check_output(['git', 'diff', '--binary', '--', *files])
        output.write_bytes(patch)
    finally:
        subprocess.run(['git', 'restore', '--source=HEAD', '--worktree', '--', *files], check=True)
    if patch:
        raise SystemExit('Formatting differs. Apply the saved formatter patch and rerun CI.')
