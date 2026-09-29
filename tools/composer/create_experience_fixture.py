#!/usr/bin/env python3
"""Create a disposable, repeatable local-command fixture for Warp/Composer."""

import argparse
import json
from pathlib import Path
import shlex
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--parent", type=Path, default=Path(tempfile.gettempdir()),
        help="Existing parent directory; a new unique child is always created.",
    )
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix="composer-experience-", dir=args.parent)).resolve()

    for name in ("documents/nested folder", "downloads", "src", ".config", "中文目录"):
        (root / name).mkdir(parents=True)
    files = {
        "document.txt": "A file, not a directory.\n",
        "hello world.txt": "Composer fixture: spaces are literal.\n",
        "中文.txt": "Composer 中文输入。\n",
        ".config/settings.txt": "fixture=true\n",
        "documents/nested folder/note.txt": "Nested completion fixture.\n",
        "src/main.dart": "void main() => print('fixture');\n",
    }
    for name, text in files.items():
        (root / name).write_text(text, encoding="utf-8")
    (root / "package.json").write_text(json.dumps({
        "name": "composer-experience-fixture",
        "private": True,
        "scripts": {
            "dev": "printf 'fixture dev\\n'",
            "test": "printf 'fixture test\\n'",
            "test:unit": "printf 'fixture unit\\n'",
        },
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # No global config changes, hooks, signing prompts, network, or source repo
    # mutations. The empty commit is enough to create deterministic branches.
    git = [
        "git", "-C", str(root), "-c", "core.hooksPath=/dev/null",
        "-c", "init.templateDir=", "-c", "commit.gpgSign=false",
        "-c", "user.name=Composer Fixture", "-c", "user.email=fixture@example.invalid",
    ]
    for command in (
        ["init", "--initial-branch=main"],
        ["commit", "--allow-empty", "-m", "Create local experience fixture"],
        ["branch", "feature/composer-demo"],
        ["branch", "fix/completion-demo"],
    ):
        subprocess.run(git + command, check=True, capture_output=True, text=True)

    manifest = {
        "root": str(root),
        "enter_command": "cd " + shlex.quote(str(root)),
        "branches": ["main", "feature/composer-demo", "fix/completion-demo"],
        "scripts": ["dev", "test", "test:unit"],
        "files": sorted(files),
        "status": "fixture prepared; no Warp or Composer interaction recorded",
    }
    (root / ".experience-fixture.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
