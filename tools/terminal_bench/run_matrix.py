#!/usr/bin/env python3
"""Run/resume every TB4 task for the requested models, retaining missing resources."""
from __future__ import annotations

import argparse
import asyncio
import fcntl
import shlex
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import tomllib
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parents[2]
DATASET_SHA = "452bf305c6daa62fc59061d22133a7cbc7c1572e"
CONTEXT = "colima-trail-tbench"


def command(*args: str, **kwargs) -> str:
    return subprocess.check_output(args, text=True, **kwargs).strip()


def manifest(dataset: Path) -> list[dict]:
    if command("git", "-C", str(dataset), "rev-parse", "HEAD") != DATASET_SHA:
        raise ValueError("Dataset checkout must be the pinned v4.0.0 commit")
    if command("git", "-C", str(dataset), "status", "--porcelain"):
        raise ValueError("Dataset checkout must be unmodified")
    tasks = []
    for folder in sorted((dataset / "tasks").iterdir()):
        if not (folder / "task.toml").is_file():
            continue
        config = tomllib.loads((folder / "task.toml").read_text())
        resources = config["environment"]
        tasks.append({"name": folder.name, "category": config["metadata"]["category"],
                      **{key: resources.get(key, 0) for key in
                         ("cpus", "memory_mb", "storage_mb", "gpus")},
                      "gpu_types": resources.get("gpu_types", []),
                      "timeout_sec": config["agent"]["timeout_sec"]})
    if len(tasks) != 66:
        raise ValueError(f"Expected 66 tasks, found {len(tasks)}")
    return tasks


def unavailable(task: dict) -> list[str]:
    reasons = []
    if task["gpus"]:
        reasons.append("requires_H100")
    if task["cpus"] > 10:
        reasons.append("requires_more_than_10_cpus")
    if task["memory_mb"] > 28 * 1024:
        reasons.append("requires_more_than_28_GiB_memory")
    if task["storage_mb"] > 80 * 1024:
        reasons.append("requires_more_than_80_GiB_disk")
    return reasons


def atomic_json(path: Path, data: object) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2))
    temporary.replace(path)


def agent_source_hash() -> str:
    return hashlib.sha256(b"".join(p.read_bytes() for p in sorted([
        *ROOT.glob("example/lib/features/ai/*.dart"),
        ROOT / "example/tool/terminal_bench_test.dart",
        ROOT / "tools/terminal_bench/trail_agent.py",
    ]))).hexdigest()


def recover_completed(saved: dict) -> dict:
    """A queue process can exit after Harbor writes results but before indexing."""
    if not saved.get("job"):
        return saved
    job = Path(saved["job"])
    paths = list(job.glob("*/result.json"))
    if len(paths) != 1:
        return saved
    raw = json.loads(paths[0].read_text())
    if not raw.get("finished_at"):
        return saved
    elapsed = (datetime.fromisoformat(raw["finished_at"]) -
               datetime.fromisoformat(raw["started_at"])).total_seconds()
    return {**saved, **collect(job), "elapsed_sec": elapsed, "recovered": True}


def cleanup_finished_images(directory: Path) -> None:
    """Remove only exact image tags belonging to finished trials in this run."""
    prefixes = []
    for path in directory.glob("*/*/result.json"):
        trial = json.loads(path.read_text())
        if trial.get("finished_at"):
            prefixes.append(re.sub(r"[^a-z0-9_-]", "-", trial["trial_name"].lower()) + "__")
    images = command("docker", "--context", CONTEXT, "image", "ls", "--format",
                     "{{.Repository}}:{{.Tag}}").splitlines()
    for name in images:
        if any(name.startswith(prefix) for prefix in prefixes):
            # No force: images used by any remaining container are preserved.
            subprocess.run(["docker", "--context", CONTEXT, "image", "rm", name],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    volumes = command("docker", "--context", CONTEXT, "volume", "ls", "--format",
                      "{{.Name}}\t{{.Label \"com.docker.compose.project\"}}").splitlines()
    for line in volumes:
        name, _, project = line.partition("\t")
        if any(project.startswith(prefix) for prefix in prefixes):
            subprocess.run(["docker", "--context", CONTEXT, "volume", "rm", name],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def collect(job: Path) -> dict:
    paths = sorted(job.glob("*/result.json"))
    if len(paths) != 1:
        return {"status": "harness_error", "reason": "missing_or_multiple_trial_results"}
    result = json.loads(paths[0].read_text())
    verifier = result.get("verifier_result") or {}
    rewards = verifier.get("rewards")
    exception = result.get("exception_info")
    if exception:
        kind = exception.get("exception_type", "")
        message = exception.get("exception_message", "")
        build_failure = "Docker compose command failed" in message and " build" in message
        status = ("environment_error" if not result.get("agent_setup") or "Environment" in kind or build_failure else
                  "timeout" if "Timeout" in kind else
                  "verifier_error" if "Verifier" in kind or result.get("verifier") else "harness_error")
    elif rewards is None:
        status = "missing_reward"
    elif all(float(value) >= 1 for value in rewards.values()) and rewards:
        status = "passed"
    else:
        status = "failed"
    agent = result.get("agent_result") or {}
    failure = ((agent.get("metadata") or {}).get("trail") or {}).get("error")
    if failure in {"rate_limit", "authentication", "connection", "http_503"}:
        status = "provider_unavailable"
    elif failure == "timeout":
        status = "timeout"
    return {"status": status, "rewards": rewards, "exception": exception,
            "trial_result": str(paths[0]), "agent_result": result.get("agent_result")}


def fits_resources(task: dict, active: list[dict]) -> bool:
    limits = {"cpus": 10, "memory_mb": 24 * 1024, "storage_mb": 50 * 1024}
    return len(active) < 2 and all(
        task[key] + sum(item[key] for item in active) <= limit
        for key, limit in limits.items()
    )


def harbor_pid(job: Path) -> int | None:
    # Process identity, not a stale lock/result file, establishes whether an
    # interrupted queue still owns a live Harbor job that must be adopted.
    listing = command("ps", "-axo", "pid=,command=")
    for line in listing.splitlines():
        pid, _, raw = line.strip().partition(" ")
        try:
            args = shlex.split(raw)
        except ValueError:
            continue
        if not any(Path(arg).name == "harbor" for arg in args):
            continue
        if "--job-name" not in args or "-o" not in args:
            continue
        if (args[args.index("--job-name") + 1] == job.name and
                Path(args[args.index("-o") + 1]).resolve() == job.parent.resolve()):
            return int(pid)
    return None


def job_finished(job: Path) -> bool:
    try:
        return bool(json.loads((job / "result.json").read_text()).get("finished_at"))
    except (OSError, ValueError):
        return False


async def execute_matrix(args, directory: Path, tasks: list[dict]) -> None:
    results_file = directory / "results.json"
    current = json.loads(results_file.read_text()) if results_file.exists() else {}
    current = {key: recover_completed(value) for key, value in current.items()}
    provenance = {"dataset_sha": DATASET_SHA, "models": args.models,
                  "effort": args.effort, "docker_context": CONTEXT,
                  "git_head": command("git", "rev-parse", "HEAD", cwd=ROOT),
                  "source_sha256": agent_source_hash()}
    provenance_file = directory / "provenance.json"
    if provenance_file.exists() and json.loads(provenance_file.read_text()) != provenance:
        raise ValueError("Source/config changed. Use a new run ID to preserve comparability.")
    atomic_json(provenance_file, provenance)
    atomic_json(directory / "manifest.json", tasks)
    atomic_json(directory / "scheduler.json", {
        "version": 2, "max_concurrent": 2, "cpu_budget": 10,
        "memory_budget_mb": 24 * 1024, "storage_budget_mb": 50 * 1024,
        "policy": "adopt live jobs; reuse completed task images; software first; environment retries last",
    })
    for task in tasks:
        for model in args.models:
            key = f"{task['name']}/{model}"
            reasons = unavailable(task)
            current.setdefault(key, {"status": "resource_unavailable", "reasons": reasons}
                               if reasons else {"status": "pending"})
    atomic_json(results_file, current)
    env = {**os.environ, "DOCKER_CONTEXT": CONTEXT, "PYTHONPATH": str(ROOT),
           "TRAIL_FLUTTER": os.environ.get("TRAIL_FLUTTER", "/Users/robinfai/development/flutter/bin/flutter")}
    harbor = ROOT / "tmp/terminal-bench/venv/bin/harbor"

    async def run_one(task: dict, model: str) -> dict:
        key = f"{task['name']}/{model}"
        saved = current[key]
        if saved["status"] == "running" and saved.get("job"):
            existing = Path(saved["job"])
            live_pid = harbor_pid(existing)
            if live_pid is not None:
                print(f"ADOPT {key} pid={live_pid}", flush=True)
                while not job_finished(existing):
                    if harbor_pid(existing) is None:
                        # A terminal process may finish writing just before its
                        # disappearance; check the authoritative result again.
                        await asyncio.sleep(1)
                        break
                    await asyncio.sleep(5)
                recovered = recover_completed(saved)
                if recovered["status"] != "running":
                    return recovered
                return {**saved, **collect(existing), "reason": "adopted_process_ended"}
            if job_finished(existing):
                return recover_completed(saved)
            # Absence of the exact live process confirms this was interrupted.
            # A fresh environment is safe; preserve its old directory as evidence.
        base = f"{task['name']}-{model}"
        attempt = 1
        while (directory / f"{base}-{attempt}").exists():
            attempt += 1
        name = f"{base}-{attempt}"
        job = directory / name
        current[key] = {"status": "running", "job": str(job), "attempt": attempt}
        atomic_json(results_file, current)
        print(f"START {key} attempt={attempt}", flush=True)
        started = time.monotonic()
        with (directory / f"{name}.log").open("w") as log:
            process = await asyncio.create_subprocess_exec(
                str(harbor), "run", "-p", str(args.dataset / "tasks" / task["name"]),
                "-a", "tools.terminal_bench.trail_agent:TrailAgent", "-m", model,
                "--ak", f"reasoning_effort={args.effort}", "-n", "1",
                "-o", str(directory), "--job-name", name,
                cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True,
            )
            current[key]["harbor_pid"] = process.pid
            atomic_json(results_file, current)
            await process.wait()
        return {**collect(job), "job": str(job), "attempt": attempt,
                "elapsed_sec": round(time.monotonic() - started, 2),
                "harbor_exit_code": process.returncode}

    pairs = [(task, model) for task in tasks for model in args.models]
    completed_names = {key.split("/")[0] for key, value in current.items()
                       if value["status"] in {"passed", "failed"}}
    def priority(pair):
        task, model = pair
        status = current[f"{task['name']}/{model}"]["status"]
        return (status != "running", status == "environment_error",
                task["name"] not in completed_names, task["category"] != "Software",
                task["cpus"], task["name"], args.models.index(model))
    queue = sorted([pair for pair in pairs if (
        current[f"{pair[0]['name']}/{pair[1]}"]["status"] in
        {"running", "pending", "provider_unavailable"} or (
            current[f"{pair[0]['name']}/{pair[1]}"]["status"] == "environment_error" and
            current[f"{pair[0]['name']}/{pair[1]}"].get("attempt", 1) < 2
        ))], key=priority)
    active = {}
    stop = False
    while queue or active:
        if not stop:
            for pair in list(queue):
                task, model = pair
                saved = current[f"{task['name']}/{model}"]
                adopting = saved["status"] == "running" and saved.get("job") and harbor_pid(Path(saved["job"])) is not None
                if not adopting and not fits_resources(task, [p[0] for p in active.values()]):
                    continue
                if agent_source_hash() != provenance["source_sha256"] or shutil.disk_usage(ROOT).free < 15 * 1024 ** 3:
                    print("Queue stopped: source changed or host disk below 15 GiB; draining current jobs.", flush=True)
                    stop = True
                    break
                queue.remove(pair)
                active[asyncio.create_task(run_one(task, model))] = pair
                # Let run_one persist ownership before admitting another job.
                await asyncio.sleep(0)
        if not active:
            break
        done, _ = await asyncio.wait(active, return_when=asyncio.FIRST_COMPLETED)
        for future in done:
            task, model = active.pop(future)
            key = f"{task['name']}/{model}"
            try:
                current[key] = future.result()
            except Exception as error:
                current[key] = {**current[key], "status": "harness_error",
                                "runner_error": f"{type(error).__name__}: {error}"}
            agent = current[key].get("agent_result") or {}
            failure = ((agent.get("metadata") or {}).get("trail") or {}).get("error")
            if failure in {"rate_limit", "authentication", "connection", "http_503"}:
                current[key]["status"] = "provider_unavailable"
                stop = True
                print(f"Provider unavailable ({failure}); draining current jobs.", flush=True)
            atomic_json(results_file, current)
            print(f"DONE {key}: {current[key]['status']}", flush=True)
            if current[key]["status"] == "environment_error" and current[key].get("attempt", 1) < 2:
                queue.append((task, model))
        cleanup_finished_images(directory)
        # Pruning never interrupts active Docker build records. Only this
        # dedicated benchmark VM's unused cache is affected.
        subprocess.run(["docker", "--context", CONTEXT, "builder", "prune", "--force",
                        "--keep-storage", "20GB"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([sys.executable, str(ROOT / "tools/terminal_bench/report.py"),
                        str(directory)], stdout=subprocess.DEVNULL, check=True)
        if stop and not active:
            break
    print(f"Results: {results_file}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--run", required=True, help="New run ID; same ID resumes completed entries")
    parser.add_argument("--models", nargs="+", default=["gpt-6-sol", "gpt-6-astra"],
                        choices=["gpt-6-luna", "gpt-6-sol", "gpt-6-astra"])
    parser.add_argument("--effort", default="high", choices=["low", "medium", "high", "xhigh"])
    args = parser.parse_args()
    if not args.run or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-_" for c in args.run):
        parser.error("Use a lowercase alphanumeric run ID")
    args.dataset = args.dataset.resolve()
    tasks = manifest(args.dataset)
    directory = ROOT / "tmp/terminal-bench/matrix" / args.run
    directory.mkdir(parents=True, exist_ok=True)
    # Prevent a recovery helper or second CLI invocation from starting a second
    # scheduler over the same matrix. The kernel releases this lock on exit.
    with (directory / "queue.lock").open("a+") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("This matrix already has a live scheduler.")
        asyncio.run(execute_matrix(args, directory, tasks))


if __name__ == "__main__":
    main()
