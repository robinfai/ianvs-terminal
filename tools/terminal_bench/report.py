#!/usr/bin/env python3
"""Create a compact, credential-free report from the matrix's raw Harbor results."""
from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from run_matrix import collect


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    directory = args.directory.resolve()
    matrix = json.loads((directory / "results.json").read_text())
    provenance = json.loads((directory / "provenance.json").read_text())
    manifest = json.loads((directory / "manifest.json").read_text())
    rows = []
    for key, saved in matrix.items():
        value = saved
        if saved.get("job") and saved["status"] != "running":
            value = {**saved, **collect(Path(saved["job"]))}
        task, model = key.split("/", 1)
        agent = value.get("agent_result") or {}
        exception = value.get("exception") or {}
        rows.append({"task": task, "model": model, "status": value["status"],
                     "reward": (value.get("rewards") or {}).get("reward"),
                     "attempt": value.get("attempt"), "elapsed_sec": value.get("elapsed_sec"),
                     "input_tokens": agent.get("n_input_tokens"),
                     "output_tokens": agent.get("n_output_tokens"),
                     "cache_tokens": agent.get("n_cache_tokens"),
                     "exception_type": exception.get("exception_type"),
                     "resource_reasons": ",".join(value.get("reasons", [])),
                     "job": value.get("job")})
    with (directory / "report.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = {model: dict(Counter(r["status"] for r in rows if r["model"] == model))
               for model in provenance["models"]}
    output = {"generated_at": datetime.now(timezone.utc).isoformat(),
              "provenance": provenance, "counts": summary, "results": rows}
    (directory / "report.json").write_text(json.dumps(output, indent=2))
    lines = ["# Trail / Terminal-Bench 4.0 local evaluation", "",
             f"Updated: {output['generated_at']}", "",
             "Resource constraints, architecture/emulation and unenforced storage quotas",
             "prevent claiming a leaderboard-comparable score. Pending entries are not failures.", "",
             "| Model | Pass | Task fail | Environment error | Harness error | Timeout | Running | Pending | Resource unavailable | Other errors |",
             "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for model, counts in summary.items():
        cells = [str(counts.get(k, 0)) for k in ["passed", "failed", "environment_error",
                 "harness_error", "timeout", "running", "pending", "resource_unavailable"]]
        cells.append(str(sum(counts.values()) - sum(int(v) for v in cells)))
        lines.append("| " + model + " | " + " | ".join(cells) + " |")
    lines += ["", "All statuses and token accounting are retained in report.json and report.csv.", "",
              "| Task | Category | " + " | ".join(provenance["models"]) + " |",
              "|---|---|" + "---|" * len(provenance["models"])]
    by_key = {(r["task"], r["model"]): r for r in rows}
    for task in manifest:
        lines.append("| " + task["name"] + " | " + task["category"] + " | " + " | ".join(
            by_key[(task["name"], model)]["status"] for model in provenance["models"]) + " |")
    (directory / "report.md").write_text("\n".join(lines) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
