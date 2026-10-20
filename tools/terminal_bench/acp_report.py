"""Summarize official rewards and observable Trail facts, never hidden tests."""
import argparse
import hashlib
import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def report(directory: Path):
    directory = directory.resolve()
    manifest = json.loads((directory / "manifest.json").read_text())
    rows = []
    for task in manifest["tasks"]:
        name = task["name"]
        trials = list((directory / "jobs" / name).glob("*/result.json"))
        if len(trials) != 1:
            rows.append({"task": name, "state": "pending"})
            continue
        trial = trials[0].parent
        official = json.loads(trials[0].read_text())
        path = trial / "agent/acp-result.json"
        agent = json.loads(path.read_text()) if path.exists() else {}
        events_path = trial / "agent/trajectory.jsonl"
        events = []
        if events_path.exists():
            for line in events_path.read_text().splitlines():
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    # A live writer can leave its final line incomplete.
                    continue
        rewards = (official.get("verifier_result") or {}).get("rewards")
        exception = official.get("exception_info")
        score = (rewards or {}).get("reward")
        # Harbor may terminate the agent at its official deadline before the
        # final summary is written. Preserve facts already observed on the
        # protocol stream without inventing missing action/block summaries.
        connection = agent.get("connection") or next(
            (e for e in reversed(events)
             if e.get("sessionUpdate") == "trail_connection"), {}
        )
        negotiated_blocks = agent.get(
            "negotiated_blocks", any(e.get("kind") == "ready" for e in events)
        )
        outside = [
            {"id": e.get("toolCallId"), "kind": e.get("kind"), "title": e.get("title")}
            for e in events if e.get("sessionUpdate") == "tool_call"
            and e.get("kind") in ("execute", "edit", "delete", "move")
            and (e.get("rawInput") or {}).get("server") != "trail_terminal"
        ]
        state = ("running" if not official.get("finished_at") else
                 "passed" if score == 1 else
                 "failed" if score is not None else
                 "error" if exception else "unscored")
        elapsed = None
        if official.get("started_at") and official.get("finished_at"):
            elapsed = (datetime.fromisoformat(official["finished_at"]) -
                       datetime.fromisoformat(official["started_at"])).total_seconds()
        actions = agent.get("actions") or []
        rows.append({
            "task": name, "state": state, "reward": score,
            "exception_type": (exception or {}).get("exception_type"),
            "wall_seconds": elapsed,
            "negotiated_blocks": negotiated_blocks,
            "approvals": agent.get("approvals", sum(e.get("kind") == "approval" for e in events)),
            "linked_blocks": (sum(bool(a.get("block_id")) for a in actions)
                              if "actions" in agent else None),
            "configured_model": connection.get("model"),
            "outside_terminal_tool_calls": outside,
            "agent_error": agent.get("error"),
            "usage_scope": "Total task tokens unavailable from ACP adapter 2.1.1",
            "evidence": str(trial.relative_to(ROOT)),
        })
    current = {
        path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
        for path in manifest["source_hashes"]
    }
    result = {
        "model": manifest["model"], "dataset": manifest["dataset"],
        "scope": manifest["scope"], "tasks": rows,
        "passed": sum(r.get("reward") == 1 for r in rows),
        "failed": sum(r.get("reward") == 0 for r in rows),
        "unscored_or_pending": sum(r.get("reward") is None for r in rows),
        "sources_unchanged": current == manifest["source_hashes"],
    }
    (directory / "report.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
    lines = [
        "# Trail ACP / Terminal-Bench 2.1",
        "",
        "Model: gpt-5.6-sol; reasoning: high; adapter: codex-acp@2.1.1.",
        "Fixed 12-task selection, one attempt each, original instructions and official verifiers.",
        "Production controller + ACP + authenticated MCP + native SSH/Command Blocks.",
        "Harness approvals are confined to disposable containers. This is not real-UI acceptance or a full-dataset leaderboard score.",
        "",
        "| Task | State | Reward | Approvals | Linked blocks |",
        "|---|---|---:|---:|---:|",
        *[f"| {r['task']} | {r['state']} | {r.get('reward') if r.get('reward') is not None else '—'} | {r.get('approvals', '—')} | {r.get('linked_blocks') if r.get('linked_blocks') is not None else '—'} |" for r in rows],
        "",
        f"Passed: {result['passed']}/12. Failed: {result['failed']}. Unscored or pending: {result['unscored_or_pending']}.",
        "",
        "Model provenance: exact model requested and confirmed by ACP config; adapter model metadata is derived from that session selection, not an independent provider response-model echo.",
        "Token accounting: adapter 2.1.1 returns its last inference usage, not task totals. Total task tokens remain unavailable; no misleading sum is published.",
        "Historical API/UI results use different models and execution boundaries; they are not a controlled causal comparison.",
    ]
    (directory / "report.md").write_text("\n".join(lines) + "\n")
    print(json.dumps({k: result[k] for k in ("passed", "failed", "unscored_or_pending", "sources_unchanged")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    report(parser.parse_args().directory)
