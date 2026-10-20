#!/usr/bin/env python3
"""Disposable SSH + deterministic model + raw simulator evidence service.

Only a single owned, loopback-published container is created. The mock proposes
commands; it never runs them. /state reads an independent execution counter.
The supplied simulator identifier stays in runtime.private.json, never stdout.
"""

import argparse
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import signal
import socket
import struct
import subprocess
import sys
from threading import Lock
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
IMAGE = "trail-mobile-prd:ssh"
PUBLIC_PASSWORD = "trail-mobile-lab"
MAX_BODY = 1024 * 1024


def now():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    path.chmod(0o600)


def safe_metadata(value, depth=0):
    if depth > 8:
        raise ValueError("metadata_depth")
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        if len(value) > 8192 or any(x in value for x in ("/Users/", "PRIVATE KEY-----", "Bearer ")):
            raise ValueError("unsafe_metadata")
        return value
    if isinstance(value, list) and len(value) <= 100:
        return [safe_metadata(item, depth + 1) for item in value]
    if isinstance(value, dict) and len(value) <= 100:
        result = {}
        for key, item in value.items():
            if not isinstance(key, str) or re.search(r"password|secret|token|api.?key|private.?key|udid|device.?id|serial.?number", key, re.I):
                raise ValueError("unsafe_metadata_key")
            result[key] = safe_metadata(item, depth + 1)
        return result
    raise ValueError("invalid_metadata")


def decode_content(message):
    try:
        data = json.loads(message.get("content") or "{}")
        return data if isinstance(data, dict) else {}
    except (ValueError, TypeError):
        return {}


def tool_reply(name, arguments, serial, content=None):
    return {"role": "assistant", "content": content, "tool_calls": [{
        "id": f"mobile-prd-{serial}", "type": "function",
        "function": {"name": name, "arguments": json.dumps(arguments)},
    }]}


def model_reply(messages, serial):
    user_index = next((i for i in range(len(messages) - 1, -1, -1)
                       if messages[i].get("role") == "user"), -1)
    turn = messages[user_index + 1:]
    if not any(message.get("tool_calls") for message in turn):
        supplied = decode_content(messages[user_index]) if user_index >= 0 else {}
        blocks = supplied.get("selected_blocks")
        source = blocks[0] if isinstance(blocks, list) and blocks else supplied.get("selected_block")
        citation = source.get("citation") if isinstance(source, dict) else None
        suffix = (" " + citation if isinstance(citation, str)
                  and re.fullmatch(r"\[block:[^:\]\s]{1,128}:[1-9]\d*-[1-9]\d*\]", citation) else "")
        diagnosis = ("The supplied failure reports missing configuration on the disposable dev-box "
                     "fixture (exit 2). The proposed command only creates that fixture configuration; "
                     "its outcome remains unknown until the native command result is observed." + suffix)
        return tool_reply("run_command", {
            "command": "trail-fixture repair",
            "reason": "Repair only the missing configuration on the disposable dev-box fixture.",
        }, serial, diagnosis)
    observations = [decode_content(message) for message in turn if message.get("role") == "tool"]
    latest = observations[-1] if observations else {}
    if latest.get("error") or latest.get("cancelled") or latest.get("confirmation_pending"):
        return {"role": "assistant", "content": "The original operation is not confirmed. Inspect its receipt; do not resend it."}
    context = latest.get("terminal_context", latest)
    block = context.get("last_command") or {} if isinstance(context, dict) else {}
    if (block.get("command", "").strip() == "trail-fixture repair"
            and block.get("exit_code") == 0 and block.get("id")
            and "TRAIL_FIXTURE_REPAIRED" in block.get("output", "")):
        citation = block.get("citation")
        suffix = " " + citation if isinstance(citation, str) and citation.startswith("[block:") else ""
        return {"role": "assistant", "content": "The native command result confirms the fixture configuration is repaired (exit 0)." + suffix}
    return tool_reply("read_screen", {"reason": "Observe the original operation without sending it again.", "wait_ms": 1000}, serial)


class DockerFixture:
    def __init__(self, context, run_id, output, docker="docker"):
        self.command = [docker, "--context", context]
        self.run_id = run_id
        self.output = output
        self.container = None
        self.port = None
        self.host_public_key = None
        self.image_id = None

    def call(self, *args, timeout=30, check=True):
        result = subprocess.run(self.command + list(args), capture_output=True, text=True, timeout=timeout)
        if check and result.returncode:
            raise RuntimeError("Disposable Docker fixture operation failed; no unrelated resources were changed.")
        return result

    def start(self, build_image=False):
        if build_image:
            with (self.output / "image-build.private.log").open("w") as log:
                result = subprocess.run(self.command + ["build", "--pull=false", "-t", IMAGE,
                                        str(Path(__file__).parent)], stdout=log, stderr=subprocess.STDOUT)
            if result.returncode:
                raise RuntimeError("Fixture image build failed; see image-build.private.log.")
        self.image_id = self.call("image", "inspect", "--format", "{{.Id}}", IMAGE).stdout.strip()
        name = "trail-mobile-prd-" + self.run_id.lower()
        result = self.call("run", "--detach", "--rm", "--name", name, "--hostname", "dev-box",
                           "--label", "trail.mobile-prd.run=" + self.run_id,
                           "--publish", "127.0.0.1::22", "--read-only",
                           "--tmpfs", "/run:rw,mode=0755", "--tmpfs", "/tmp:rw,mode=1777",
                           "--tmpfs", "/home/lab:rw,mode=0700,uid=1000,gid=1000", IMAGE)
        self.container = result.stdout.strip()
        if not re.fullmatch(r"[a-f0-9]{12,64}", self.container):
            raise RuntimeError("Docker returned an invalid fixture identity.")
        address = self.call("port", self.container, "22/tcp").stdout.strip()
        if not re.fullmatch(r"127\.0\.0\.1:\d+", address):
            raise RuntimeError("Fixture SSH must be published exclusively on loopback.")
        self.port = int(address.rsplit(":", 1)[1])
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            result = self.call("exec", self.container, "cat", "/run/mobile-prd/host_key.pub", check=False)
            if result.returncode == 0:
                pieces = result.stdout.split()
                if len(pieces) >= 2 and pieces[0] == "ssh-ed25519":
                    self.host_public_key = " ".join(pieces[:2])
                    try:
                        with socket.create_connection(("127.0.0.1", self.port), timeout=1):
                            return
                    except OSError:
                        pass
            time.sleep(0.2)
        raise RuntimeError("Disposable SSH fixture did not become ready.")

    def execution_count(self):
        # Read-only oracle. It never invokes trail-fixture or submits SSH input.
        result = self.call("exec", self.container, "sh", "-c",
                           "if [ -f /home/lab/.mobile-prd/repairs ]; then wc -c </home/lab/.mobile-prd/repairs; else printf 0; fi")
        return int(result.stdout.strip())

    def close(self):
        if self.container is None:
            return
        result = self.call("inspect", "--format", '{{index .Config.Labels "trail.mobile-prd.run"}}',
                           self.container, check=False)
        if result.returncode == 0 and result.stdout.strip() == self.run_id:
            self.call("rm", "--force", self.container, check=False)
        self.container = None


class FixtureState:
    def __init__(self, output, docker, simulator=None, xcrun="xcrun"):
        self.output = output
        self.docker = docker
        self.simulator = simulator
        self.xcrun = xcrun
        self.model_requests = 0
        self.sequence = 0
        self.lock = Lock()

    def event(self, event):
        safe = safe_metadata(event)
        with self.lock:
            self.sequence += 1
            record = {"recorded_at": now(), "sequence": self.sequence, **safe}
            with (self.output / "events.jsonl").open("a") as log:
                log.write(json.dumps(record, ensure_ascii=False) + "\n")

    def state(self):
        with self.lock:
            count = self.model_requests
        return {"model_requests": count, "execution_count": self.docker.execution_count()}

    def checkpoint(self, name, metadata):
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", name):
            raise ValueError("invalid_checkpoint_name")
        if self.simulator is None:
            raise ValueError("simulator_not_configured")
        metadata = safe_metadata(metadata)
        with self.lock:
            self.sequence += 1
            sequence = self.sequence
        directory = self.output / "checkpoints"
        directory.mkdir(exist_ok=True)
        screenshot = directory / f"{sequence:03d}-{name}.png"
        result = subprocess.run([self.xcrun, "simctl", "io", self.simulator, "screenshot", "--type=png", str(screenshot)],
                                capture_output=True, timeout=20)
        if result.returncode:
            raise RuntimeError("Simulator screenshot failed; no replacement image was generated.")
        data = screenshot.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
            raise RuntimeError("Simulator did not return a PNG screenshot.")
        width, height = struct.unpack(">II", data[16:24])
        record = {"name": name, "captured_at": now(), "method": "simctl_raw_png",
                  "physical": False, "file": str(screenshot.relative_to(self.output)),
                  "sha256": hashlib.sha256(data).hexdigest(), "width": width, "height": height,
                  "metadata": metadata}
        write_json(screenshot.with_suffix(".json"), record)
        self.event({"event": "checkpoint", "name": name, "file": record["file"]})
        return record


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, state):
        super().__init__(address, Handler)
        self.state = state


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self, status, value):
        raw = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        try:
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if self.path == "/health":
            return self.respond(200, {"fixture": True, "model": "deterministic_mock"})
        if self.path == "/v1/models":
            return self.respond(200, {"object": "list", "data": [{"id": "trail-mobile-prd", "object": "model"}]})
        if self.path == "/state":
            try:
                return self.respond(200, self.server.state.state())
            except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
                return self.respond(503, {"error": "execution_oracle_unavailable"})
        self.respond(404, {"error": "not_found"})

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_BODY:
                return self.respond(413, {"error": "body_limit"})
            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict):
                raise ValueError("invalid_object")
            if self.path == "/events":
                if not isinstance(payload.get("event"), str):
                    raise ValueError("missing_event")
                self.server.state.event(payload)
                return self.respond(200, {"recorded": True})
            if self.path == "/checkpoint":
                self.server.state.checkpoint(payload.get("name"), payload.get("metadata", {}))
                return self.respond(200, {"recorded": True})
            if self.path == "/v1/chat/completions":
                messages = payload.get("messages")
                if not isinstance(messages, list) or not messages or not all(isinstance(x, dict) for x in messages):
                    raise ValueError("invalid_messages")
                with self.server.state.lock:
                    self.server.state.model_requests += 1
                    serial = self.server.state.model_requests
                message = model_reply(messages, serial)
                self.server.state.event({"event": "model_request", "model_request": serial,
                                         "roles": [message.get("role") for message in messages],
                                         "reply_kind": "tool" if message.get("tool_calls") else "summary"})
                return self.respond(200, {"id": f"mobile-prd-{serial}", "object": "chat.completion",
                    "model": "trail-mobile-prd", "choices": [{"index": 0, "message": message,
                    "finish_reason": "tool_calls" if message.get("tool_calls") else "stop"}],
                    "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}})
            self.respond(404, {"error": "not_found"})
        except (ValueError, TypeError, KeyError):
            self.respond(400, {"error": "invalid_fixture_request"})
        except (OSError, RuntimeError, subprocess.TimeoutExpired):
            self.respond(503, {"error": "fixture_operation_failed"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--docker-context", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--simulator", help="Private simulator identifier for raw screenshots")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--build-image", action="store_true")
    parser.add_argument("--case", default="flow")
    args = parser.parse_args()
    os.umask(0o077)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    output = (args.output or ROOT / "build/mobile-prd-v1.1/runs" / run_id).resolve()
    output.mkdir(parents=True, exist_ok=False)
    docker = DockerFixture(args.docker_context, run_id, output)
    server = None
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    try:
        docker.start(build_image=args.build_image)
        state = FixtureState(output, docker, args.simulator)
        server = FixtureServer(("127.0.0.1", args.port), state)
        base = f"http://127.0.0.1:{server.server_port}"
        ssh = {"type": "ssh", "host": "127.0.0.1", "user": "lab", "port": docker.port,
               "auth": "password", "password": PUBLIC_PASSWORD, "privateKeys": [],
               "hostKeyPolicy": "strict", "connectTimeoutSeconds": 10, "keepaliveSeconds": 0,
               "keepaliveCountMax": 3, "proxyJumpProfiles": [], "portForwards": [],
               "agentForwarding": False, "x11Forwarding": False, "x11TargetPort": 0,
               "x11AuthProtocol": "MIT-MAGIC-COOKIE-1", "x11ScreenNumber": 0}
        fixture = {"runId": run_id, "ssh": ssh, "hostPublicKey": docker.host_public_key,
                   "modelBaseUrl": base + "/v1", "evidenceBaseUrl": base}
        write_json(output / "fixture-defines.json", {"TRAIL_MOBILE_PRD_FIXTURE": json.dumps(fixture),
                                                    "TRAIL_MOBILE_PRD_CASE": args.case})
        write_json(output / "runtime.private.json", {"simulator": args.simulator,
                   "container": docker.container, "docker_context": args.docker_context, "pid": os.getpid()})
        write_json(output / "environment.json", {"run_id": run_id, "started_at": now(),
                   "ssh_image_id": docker.image_id, "model": "deterministic_mock",
                   "listener": "loopback_only", "physical": False, "app_verified": False})
        print(json.dumps({"fixture_ready": True, "run_id": run_id,
                          "defines": str(output / "fixture-defines.json"), "evidence_url": base}), flush=True)
        server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Fixture setup failed.", file=sys.stderr)
        return 1
    finally:
        if server is not None:
            server.server_close()
        docker.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
