"""One frozen TB2.1 pass. Never reads solutions or verifier source."""
import argparse
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATASET = Path("/private/tmp/trail-terminal-bench/dataset-2-1")
OUTPUT = ROOT / "tmp/terminal-bench/acp-2-1"


def source_hashes():
    files = [*ROOT.glob("example/lib/features/ai/**/*.dart"),
             ROOT / "example/tool/acp_terminal_bench_test.dart",
             ROOT / "tools/terminal_bench/acp_agent.py",
             ROOT / "native/core/target/debug/libianvs_core.dylib"]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(files)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()
    selection = json.loads((ROOT / "tools/terminal_bench/tb21-selection.json").read_text())
    revision = subprocess.check_output(["git", "-C", str(DATASET), "rev-parse", "HEAD"], text=True).strip()
    if revision != selection["commit"]:
        raise ValueError("Dataset revision differs from the fixed selection")
    dirty = subprocess.check_output(["git", "-C", str(DATASET), "status", "--porcelain"], text=True)
    if dirty:
        raise ValueError("Dataset must be unmodified")
    destination = OUTPUT / args.run_id
    destination.mkdir(parents=True, exist_ok=False)
    hashes = source_hashes()
    frozen = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "dataset": selection["dataset"], "commit": revision,
        "tasks": selection["tasks"], "model": "gpt-5.6-sol",
        "attempts_per_task": 1, "reasoning_effort": "high",
        "adapter": "@agentclientprotocol/codex-acp@2.1.1",
        "scope": "production controller / ACP / MCP / native SSH command blocks",
        "approvals": "harness approves each request inside the pinned disposable container",
        "source_hashes": hashes,
    }
    (destination / "manifest.json").write_text(json.dumps(frozen, indent=2))
    env = {**os.environ, "DOCKER_CONTEXT": "colima-trail-tbench",
           "TRAIL_FLUTTER": "/Users/robinfai/development/flutter/bin/flutter",
           "PYTHONPATH": str(ROOT)}
    results = []
    for task in selection["tasks"]:
        if source_hashes() != hashes:
            raise RuntimeError("Implementation changed after this round was frozen")
        name = task["name"]
        path = DATASET / "tasks" / name
        if hashlib.sha256((path / "instruction.md").read_bytes()).hexdigest() != task["instruction_sha256"]:
            raise ValueError("Official instruction hash changed: " + name)
        config = {
            "job_name": name, "jobs_dir": str(destination / "jobs"),
            "n_concurrent_trials": 1, "n_attempts": 1,
            "agents": [{"import_path": "tools.terminal_bench.acp_agent:TrailAcpAgent",
                        "model_name": "gpt-5.6-sol"}],
            "tasks": [{"path": str(path)}],
        }
        config_path = destination / (name + ".json")
        config_path.write_text(json.dumps(config, indent=2))
        print(json.dumps({"started": name}), flush=True)
        with (destination / (name + ".log")).open("w") as log:
            process = subprocess.run(
                [str(ROOT / "tmp/terminal-bench/venv/bin/harbor"), "run", "-c", str(config_path)],
                cwd=ROOT, env=env, stdout=log, stderr=log,
            )
        rows = list((destination / "jobs" / name).glob("*/result.json"))
        record = {"task": name, "runner_exit": process.returncode}
        if len(rows) == 1:
            raw = json.loads(rows[0].read_text())
            record.update({
                "rewards": (raw.get("verifier_result") or {}).get("rewards"),
                "exception": raw.get("exception_info"),
                "started_at": raw.get("started_at"), "finished_at": raw.get("finished_at"),
                "result_file": str(rows[0].relative_to(ROOT)),
            })
        results.append(record)
        (destination / "results.json").write_text(json.dumps(results, indent=2))
        print(json.dumps(record), flush=True)


if __name__ == "__main__":
    main()
