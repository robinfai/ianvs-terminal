#!/usr/bin/env python3
"""Private localhost CLIProxyAPI configuration and exact-model preflight.

Build the pinned source into tmp/terminal-bench/bin/cliproxyapi first. This helper
never prints credentials, stores them in git, or passes them to task containers.
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "tmp/terminal-bench"
PRIVATE = RUNTIME / "proxy"
MODELS = ("gpt-6-luna", "gpt-6-sol", "gpt-6-astra")


def initialize() -> None:
    PRIVATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    PRIVATE.chmod(0o700)
    auth = PRIVATE / "auth"
    auth.mkdir(exist_ok=True, mode=0o700)
    auth.chmod(0o700)
    key = PRIVATE / "client-key"
    if not key.exists():
        with key.open("x") as file:
            file.write(secrets.token_urlsafe(36))
    key.chmod(0o600)
    config = {
        "config-version": 8,
        "server": {"host": "127.0.0.1", "port": 8317, "discovery": {"enabled": False}},
        "management": {"allow-remote": False, "secret-key": "",
                       "disable-control-panel": True, "disable-auto-update-panel": True},
        "access": {"api-keys": [key.read_text().strip()]},
        "oauth": {"auth-dir": str(auth)},
        "routing": {"retry": {"request-retry": 0}},
        "observability": {"logs": {"debug": False, "request-log": False,
                                   "logging-to-file": False},
                          "usage": {"usage-statistics-enabled": True}},
        "multimedia": {"disable-image-generation": True},
        "plugins": {"enabled": False},
    }
    path = PRIVATE / "config.yaml"
    path.write_text(json.dumps(config, indent=2))
    path.chmod(0o600)


def preflight() -> None:
    key = (PRIVATE / "client-key").read_text().strip()
    results = []
    for model in MODELS:
        started = time.monotonic()
        data = {
            "model": model, "messages": [{"role": "user", "content":
                "Call read_screen once to verify terminal tool access."}],
            "tools": [{"type": "function", "function": {"name": "read_screen",
                "description": "Read terminal screen", "parameters": {"type": "object",
                "properties": {"reason": {"type": "string"}}, "required": ["reason"],
                "additionalProperties": False}}}],
            "tool_choice": "required", "parallel_tool_calls": False, "stream": False,
        }
        request = urllib.request.Request("http://127.0.0.1:8317/v1/chat/completions",
            data=json.dumps(data).encode(),
            headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                result = json.load(response)
            call = result["choices"][0]["message"]["tool_calls"][0]
            passed = result.get("model") == model and call["function"]["name"] == "read_screen"
            record = {"requested_model": model, "response_model": result.get("model"),
                      "passed": passed, "usage": result.get("usage")}
        except urllib.error.HTTPError as error:
            record = {"requested_model": model, "passed": False, "http_status": error.code}
        except (OSError, ValueError, KeyError, IndexError) as error:
            record = {"requested_model": model, "passed": False, "error": type(error).__name__}
        record["elapsed_sec"] = round(time.monotonic() - started, 2)
        results.append(record)
        print(json.dumps(record), flush=True)
    (PRIVATE / "preflight.json").write_text(json.dumps(results, indent=2))
    if not all(result["passed"] for result in results):
        raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["init", "login", "start", "preflight"])
    args = parser.parse_args()
    os.umask(0o077)
    if args.action == "init":
        initialize()
        print("Private localhost configuration created; no credentials printed.")
    elif args.action == "preflight":
        preflight()
    else:
        command = [str(RUNTIME / "bin/cliproxyapi"), "--config", str(PRIVATE / "config.yaml")]
        if args.action == "login":
            command.append("--codex-login")
        raise SystemExit(subprocess.call(command, cwd=PRIVATE))


if __name__ == "__main__":
    main()
