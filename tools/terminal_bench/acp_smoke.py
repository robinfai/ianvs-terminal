"""Disposable end-to-end smoke; no benchmark instruction or verifier involved."""
import asyncio
import argparse
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from harbor.models.agent.context import AgentContext
from tools.terminal_bench.acp_agent import TrailAcpAgent, ROOT


async def main(scenario):
    output = ROOT / "tmp/terminal-bench/acp-2-1" / ("smoke-" + scenario + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S"))
    output.mkdir(parents=True, exist_ok=True)
    container = subprocess.check_output([
        "docker", "--context", "colima-trail-tbench", "run", "-d",
        "debian:bookworm-slim", "sleep", "900",
    ], text=True).strip()
    agent = TrailAcpAgent(logs_dir=output, model_name="gpt-5.6-sol")
    agent.container = container
    agent.user, agent.cwd = "root", "/tmp"
    agent.image = "debian:bookworm-slim"
    agent.provenance = {"scope": "non-benchmark smoke"}
    directory_command = "mkdir -p /tmp/trail-acp-cwd && cd /tmp/trail-acp-cwd && sleep 3"
    prompts = {
        "basic": "Run printf 'TRAIL_ACP_OK\\n' in the terminal. Read its command block "
                 "and report the marker and actual exit status. Do not perform other work.",
        "interactive": "Run this exact command in the terminal: "
                       "read -rp 'Choice: ' answer; printf 'TRAIL_ACP_%s\\n' \"$answer\". "
                       "Observe its interactive prompt, enter OK and Enter using send_keys. "
                       "Read the resulting block and report its output and exit status. "
                       "Do not perform other work.",
        "exit": "This is an explicit shell-exit lifecycle test in a disposable container. "
                "Run exactly exit in the bound terminal, not in a child shell. "
                "Then report the observed session state; do not retry or reconnect the terminal.",
        "directory": "This tests a delayed directory update in the persistent shell. "
                     f"First run exactly: {directory_command}. "
                     "Wait for it to finish, then observe get_terminal_state. "
                     "Submit a separate approved command: pwd && printf 'TRAIL_ACP_OK\\n'. "
                     "Report the directory and final command's real exit status. "
                     "Do not use a subshell or combine the two submissions; do not perform other work.",
    }
    try:
        await asyncio.wait_for(agent.run(prompts[scenario], None, AgentContext()), 180)
        result = json.loads((output / "acp-result.json").read_text())
        if result.get("approvals", 0) < 1:
            raise RuntimeError("Smoke did not execute terminal input")
        if scenario == "exit":
            if result.get("terminal_read_error") != "session_unavailable":
                raise RuntimeError("Shell exit did not retain the disconnected result")
            print(json.dumps({"smoke": str(output), "scenario": scenario, "completed": True}))
            return
        if not any(a.get("block_id") for a in result.get("actions", [])):
            raise RuntimeError("Smoke did not execute and retain a command block")
        block = (result.get("terminal") or {}).get("last_command") or {}
        if "TRAIL_ACP_OK" not in block.get("output", "") or block.get("exit_code") != 0 or block.get("running"):
            raise RuntimeError("Smoke block did not finish successfully with the output marker")
        if scenario == "interactive":
            events = [json.loads(line) for line in (output / "trajectory.jsonl").read_text().splitlines()]
            if not any(e.get("kind") == "approval" and
                       e.get("action", {}).get("function", {}).get("name") == "send_keys" for e in events):
                raise RuntimeError("Interactive smoke never used send_keys")
        if scenario == "directory":
            events = [json.loads(line) for line in (output / "trajectory.jsonl").read_text().splitlines()]
            approvals = [e for e in events if e.get("kind") == "approval"]
            first = json.loads(approvals[0]["action"]["function"]["arguments"])
            if first.get("command") != directory_command or len(approvals) < 2:
                raise RuntimeError("Directory smoke did not execute separate approved commands")
            if result.get("error") or result["terminal"]["cwd"] != "/tmp/trail-acp-cwd":
                raise RuntimeError("Directory smoke did not preserve the approved shell directory")
            if len({a.get("block_id") for a in result["actions"] if a.get("block_id")}) < 2:
                raise RuntimeError("Directory smoke did not retain two distinct command blocks")
        print(json.dumps({"smoke": str(output), "scenario": scenario, "completed": True}))
    finally:
        subprocess.run(["docker", "--context", "colima-trail-tbench", "rm", "-f", container],
                       check=True, stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", choices=["basic", "interactive", "exit", "directory"], default="basic")
    asyncio.run(main(parser.parse_args().scenario))
