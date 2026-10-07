"""Read-only UI coverage/report generation; never examines hidden test contents."""
import csv
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "tmp/terminal-bench/ui-2-1"


def main():
    selection = json.loads((ROOT / "tools/terminal_bench/tb21-selection.json").read_text())
    audit_path = BASE / "inference.jsonl"
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()] if audit_path.exists() else []
    attempts = []
    for config_path in sorted((BASE / "jobs").glob("*/config.json")):
        job = config_path.parent
        config = json.loads(config_path.read_text())
        task = Path(config["tasks"][0]["path"]).name
        model = config["agents"][0]["model_name"]
        for ready_path in job.glob("*/agent/ui-ready.json"):
            directory = ready_path.parent
            complete_path = directory / "ui-complete.json"
            result_path = directory.parent / "result.json"
            complete = json.loads(complete_path.read_text()) if complete_path.exists() else {}
            result = json.loads(result_path.read_text()) if result_path.exists() else {}
            assessment_path = BASE / 'evidence' / job.name / 'assessment.json'
            assessment = json.loads(assessment_path.read_text()) if assessment_path.exists() else {}
            rewards = (result.get("verifier_result") or {}).get("rewards")
            status = (assessment.get("classification") or complete.get("classification") or
                      ("evaluation_or_environment_error" if result.get("exception_info") else
                       "passed" if rewards and rewards.get("reward") == 1 else
                       "official_fail_attribution_pending" if rewards is not None else
                       "verifier_pending" if complete else "running"))
            start, end = complete.get("ui_started_at"), complete.get("completed_at")
            seconds = ((datetime.fromisoformat(end) - datetime.fromisoformat(start)).total_seconds()
                       if start and end else None)
            # A request can finish upstream after the UI has timed out or the
            # attempt was recorded. Reconcile by request start time without
            # overwriting the immutable UI completion record.
            inference = [r for r in audit if start and end and
                         datetime.fromisoformat(start) <= datetime.fromisoformat(r["started_at"]) <= datetime.fromisoformat(end) and
                         r.get("requested_model") == model]
            responses = [r for r in inference if r.get("http_status") == 200]
            accounting = {}
            if inference:
                accounting = {
                    "input_tokens": sum((r.get("usage") or {}).get("prompt_tokens", 0) for r in inference),
                    "output_tokens": sum((r.get("usage") or {}).get("completion_tokens", 0) for r in inference),
                    "cached_tokens": sum(((r.get("usage") or {}).get("prompt_tokens_details") or {}).get("cached_tokens", 0) for r in inference),
                    "response_models": sorted({r.get("response_model") or "unknown" for r in responses}),
                    "model_identity_verified": bool(responses) and all(r.get("response_model") == model for r in responses),
                }
            attempts.append({
                "task": task, "model": model, "platform": complete.get("platform", "macos"),
                "mode": complete.get("terminal_mode") or (
                    "blocks" if job.name.startswith("macos-block") else "normal"
                ), "job": job.name,
                "status": status, "official_reward": (rewards or {}).get("reward"),
                "ui_wall_seconds": seconds, "input_tokens": complete.get("input_tokens"),
                "output_tokens": complete.get("output_tokens"), "cached_tokens": complete.get("cached_tokens"),
                "model_identity_verified": complete.get("model_identity_verified", False),
                "response_models": complete.get("response_models", []),
                "approvals": complete.get("approvals"), "evidence": complete.get("evidence"),
                "ui_result": complete.get("ui_result"),
                "reason": assessment.get("reason") or complete.get("reason"),
                "assessment_evidence": assessment.get("evidence", []),
                "exception": result.get("exception_info"),
                "audited_requests": len(inference),
                "audit_http_failures": sum(r.get("http_status") != 200 for r in inference),
                "audit_usage_missing": sum(not r.get("usage") for r in inference),
                **accounting,
            })
    references = []
    reference_audit_path = BASE / "reference/inference.jsonl"
    reference_audit = [json.loads(line) for line in reference_audit_path.read_text().splitlines()] if reference_audit_path.exists() else []
    for config_path in sorted((BASE / "reference").glob("*/config.json")):
        config = json.loads(config_path.read_text())
        assessment_path = config_path.parent / "assessment.json"
        assessment = json.loads(assessment_path.read_text()) if assessment_path.exists() else {}
        for result_path in config_path.parent.glob("*/result.json"):
            result = json.loads(result_path.read_text())
            usage = result.get("agent_result") or {}
            start, end = result.get("started_at"), result.get("finished_at")
            model = config["agents"][0]["model_name"].removeprefix("openai/")
            responses = [row for row in reference_audit if start and end and
                         datetime.fromisoformat(start) <= datetime.fromisoformat(row["started_at"]) <= datetime.fromisoformat(end) and
                         row.get("requested_model") == model and row.get("http_status") == 200]
            references.append({
                "job": config_path.parent.name,
                "task": Path(config["tasks"][0]["path"]).name,
                "agent": config["agents"][0]["name"],
                "requested_model": config["agents"][0]["model_name"],
                "official_reward": ((result.get("verifier_result") or {}).get("rewards") or {}).get("reward"),
                "wall_seconds": ((datetime.fromisoformat(end) - datetime.fromisoformat(start)).total_seconds()
                                 if start and end else None),
                "input_tokens": usage.get("n_input_tokens"),
                "output_tokens": usage.get("n_output_tokens"),
                "cached_tokens": usage.get("n_cache_tokens"),
                "exception": result.get("exception_info"),
                "diagnostic": assessment.get("diagnostic", False),
                "classification": assessment.get("classification"),
                "reason": assessment.get("reason"),
                "setup_overrides": assessment.get("setup_overrides"),
                "response_models": sorted({row.get("response_model") or "unknown" for row in responses}),
                "model_identity_verified": bool(responses) and all(row.get("response_model") == model for row in responses),
                "audited_responses": len(responses),
            })
    coverage = []
    for task in selection["tasks"]:
        for model in selection["models"]:
            for mode in ("normal", "blocks"):
                if model == "gpt-6-luna" and not task["representative"]:
                    continue
                if mode == "blocks" and not task["representative"]:
                    continue
                matches = [a for a in attempts if a["task"] == task["name"] and
                           a["model"] == model and a["mode"] == mode]
                coverage.append({"task": task["name"], "model": model, "mode": mode,
                                 "status": matches[-1]["status"] if matches else "pending",
                                 "selected_attempt": matches[-1]["job"] if matches else None,
                                 "official_reward": matches[-1]["official_reward"] if matches else None,
                                 "attempts": [a["job"] for a in matches]})
    summary = []
    for model in selection["models"]:
        for mode in ("normal", "blocks"):
            cells = [c for c in coverage if c["model"] == model and c["mode"] == mode]
            summary.append({
                "model": model, "mode": mode, "planned": len(cells),
                "reward_one": sum(c["official_reward"] == 1 for c in cells),
                "reward_zero": sum(c["official_reward"] == 0 for c in cells),
                "unscored": sum(c["official_reward"] is None for c in cells),
                "qualified_passes": [c["task"] for c in cells
                                     if c["official_reward"] == 1 and c["status"] != "passed"],
            })
    regression_path = BASE / "product-regression/status.json"
    regression = json.loads(regression_path.read_text()) if regression_path.exists() else {}
    report = {"updated_at": datetime.now(timezone.utc).isoformat(),
              "dataset_commit": selection["commit"], "phone_testing": "cancelled_by_user",
              "coverage": coverage, "summary": summary,
              "attempts": attempts, "references": references,
              "product_regressions": regression}
    BASE.mkdir(parents=True, exist_ok=True)
    (BASE / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    if attempts:
        with (BASE / "attempts.csv").open("w") as file:
            writer = csv.DictWriter(file, fieldnames=attempts[0].keys())
            writer.writeheader()
            writer.writerows(attempts)
    lines = ["# Trail / Terminal-Bench 2.1 UI acceptance", "",
             f"Dataset: `{selection['commit']}` · Updated: {report['updated_at']}", "",
             "Fixed 12 tasks. macOS Normal: Luna 3, Sol 12, Astra 12; Block: the same 3 representatives per model.",
             "Phone testing was cancelled by the user. Pending entries are untested, not failures.", "",
             "## Fixed coverage results", "",
             "Each cell uses its latest recorded attempt, including repeats after product fixes or evaluation interruptions. All original attempts remain below; this is not a leaderboard score.", "",
             "| Model | Mode | Planned | Reward 1 | Reward 0 | Unscored | Qualified passes |",
             "|---|---|---:|---:|---:|---:|---|"]
    for s in summary:
        qualified = ", ".join(s["qualified_passes"]) or "none"
        lines.append(f"| {s['model']} | {s['mode']} | {s['planned']} | {s['reward_one']} | {s['reward_zero']} | {s['unscored']} | {qualified} |")
    lines += ["", "Astra Normal pMARS has reward 1 with a retained adapter timeout caused by completion-recording delay. Sol Normal data-merger has no score because the official verifier timed out.", "",
             "## Every UI attempt", "",
             "| Task | Model | Mode | Status | Official reward | UI seconds | Input/output/cache tokens |",
             "|---|---|---|---|---:|---:|---|"]
    for a in attempts:
        tokens = "/".join(str(a[k]) if a[k] is not None else "unknown" for k in
                          ("input_tokens", "output_tokens", "cached_tokens"))
        lines.append(f"| {a['task']} | {a['model']} | {a['mode']} | {a['status']} | {a['official_reward']} | {a['ui_wall_seconds']} | {tokens} |")
    lines += ["", "## Same-model reference agents", "",
              "Reference results are separate from Trail product acceptance.", "",
              "| Job | Task | Agent | Model | Type | Official reward | Seconds | Input/output/cache tokens |",
              "|---|---|---|---|---|---:|---:|---|"]
    for ref in references:
        tokens = "/".join(str(ref[k]) for k in ("input_tokens", "output_tokens", "cached_tokens"))
        kind = "Setup diagnostic" if ref["diagnostic"] else "Reference"
        lines.append(f"| {ref['job']} | {ref['task']} | {ref['agent']} | {ref['requested_model']} | {kind} | {ref['official_reward']} | {ref['wall_seconds']} | {tokens} |")
    lines += ["", "## Separate product regressions", "",
              "These checks are not included in benchmark scores.", "",
              "| Scenario | Status |", "|---|---|"]
    for case in regression.get("cases", []):
        lines.append(f"| {case['name']} | {case['status']} |")
    if regression.get("open_findings"):
        lines += ["", "## Unresolved product findings", ""]
        for finding in regression["open_findings"]:
            lines.append(f"- {finding['name']} ({finding['status']}): {finding['notes']} Evidence: `{finding['evidence']}`.")
    if regression.get("execution_blocker"):
        lines += ["", regression["execution_blocker"]["reason"]]
    lines += ["", "Full fixed coverage and every attempt are retained in report.json and attempts.csv.",
              "Reference-agent runs are separate under reference/. A completion message is not a pass.", ""]
    (BASE / "report.md").write_text("\n".join(lines))
    print(BASE / "report.md")


if __name__ == "__main__":
    main()
