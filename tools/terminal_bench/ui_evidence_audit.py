"""Audit retained UI evidence without reading hidden tests or solver artifacts.

Reads only the frozen selection, job configuration, original instruction,
UI completion record, numbered UI diagnostics and PNG headers. Missing prompt
or model evidence is reported explicitly, including excluded setup attempts.
This does not operate Trail or affect benchmark scoring.
"""
import hashlib
import json
import re
import struct
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "tmp/terminal-bench/ui-2-1"


def contains_prompt(value, prompt):
    if isinstance(value, str):
        return value.strip() == prompt.strip()
    if isinstance(value, dict):
        return any(contains_prompt(item, prompt) for item in value.values())
    if isinstance(value, list):
        return any(contains_prompt(item, prompt) for item in value)
    return False


def png_has_dimensions(path):
    with path.open("rb") as stream:
        header = stream.read(24)
    return (
        len(header) == 24
        and header[:8] == b"\x89PNG\r\n\x1a\n"
        and header[12:16] == b"IHDR"
        and all(struct.unpack(">II", header[16:24]))
    )


def audit(base=BASE):
    selection = json.loads(
        (ROOT / "tools/terminal_bench/tb21-selection.json").read_text()
    )
    hashes = {task["name"]: task["instruction_sha256"] for task in selection["tasks"]}
    attempts = []
    for complete_path in sorted((base / "jobs").glob("*/*/agent/ui-complete.json")):
        job = complete_path.parents[2]
        config = json.loads((job / "config.json").read_text())
        task = Path(config["tasks"][0]["path"]).name
        instruction_bytes = (complete_path.parent / "ui-instruction.txt").read_bytes()
        instruction = instruction_bytes.decode("utf-8")
        complete = json.loads(complete_path.read_text())
        evidence = base / "evidence" / job.name
        prompt_files = []
        invalid_diagnostics = []
        for path in sorted(evidence.glob("*.json")):
            if not re.match(r"^\d", path.name):
                continue
            try:
                if contains_prompt(json.loads(path.read_text()), instruction):
                    prompt_files.append(path.name)
            except (UnicodeError, json.JSONDecodeError):
                invalid_diagnostics.append(path.name)
        screenshots = sorted(evidence.glob("*.png"))
        invalid_screenshots = [path.name for path in screenshots if not png_has_dimensions(path)]
        attempts.append({
            "job": job.name,
            "task": task,
            "instruction_hash_matches_manifest":
                hashlib.sha256(instruction_bytes).hexdigest() == hashes.get(task),
            "screenshot_count": len(screenshots),
            "invalid_png_headers": invalid_screenshots,
            "ui_prompt_text_evidence": bool(prompt_files),
            "prompt_evidence_files": prompt_files,
            "invalid_ui_diagnostics": invalid_diagnostics,
            "model_identity_recorded": complete.get("model_identity_verified", False),
        })
    return {
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "scope": "Frozen selection, original instructions, job metadata, numbered UI text, PNG headers and immutable completion records only; no hidden tests, reference solutions or credentials.",
        "limitations": "PNG headers establish retained image files, not visual correctness. Model identity here reflects the original completion record; ui_report.py separately reconciles passive response metadata.",
        "attempts": attempts,
    }


def main():
    result = audit()
    (BASE / "evidence-integrity.json").write_text(json.dumps(result, indent=2) + "\n")
    attempts = result["attempts"]
    failures = [row["job"] for row in attempts if
                not row["instruction_hash_matches_manifest"] or
                not row["screenshot_count"] or row["invalid_png_headers"] or
                row["invalid_ui_diagnostics"]]
    print(json.dumps({
        "completed_attempts": len(attempts),
        "integrity_failures": failures,
        "missing_exact_ui_prompt": [row["job"] for row in attempts if not row["ui_prompt_text_evidence"]],
        "model_identity_not_recorded": [row["job"] for row in attempts if not row["model_identity_recorded"]],
    }))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
