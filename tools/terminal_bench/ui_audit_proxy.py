"""Local audit relay to the existing OAuth proxy. Never logs secrets or prompts.

Only model identity, token accounting, timing and request hashes are retained.
UI actions, task solving and approvals remain entirely in the Trail app.
"""
import argparse
import hashlib
import hmac
import json
import os
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8318)
    args = parser.parse_args()
    os.umask(0o077)
    args.log.parent.mkdir(parents=True, exist_ok=True)
    key = (Path(__file__).resolve().parents[2] / "tmp/terminal-bench/proxy/client-key").read_text().strip()
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            if self.path != "/v1/chat/completions":
                self.send_error(404)
                return
            if not hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + key):
                self.send_error(401)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 1024 * 1024:
                    self.send_error(413)
                    return
                body = self.rfile.read(length)
                request = json.loads(body)
                model = request.get("model")
                if model not in {"gpt-6-luna", "gpt-6-sol", "gpt-6-astra"} or request.get("stream"):
                    self.send_error(400)
                    return
            except (ValueError, OSError):
                self.send_error(400)
                return
            started = time.monotonic()
            record = {"started_at": datetime.now(timezone.utc).isoformat(),
                      "requested_model": model, "request_sha256": hashlib.sha256(body).hexdigest()}
            users = [m for m in request.get("messages", []) if m.get("role") == "user"]
            if users:
                try:
                    prompt = json.loads(users[-1]["content"])["request"]
                    record["instruction_sha256"] = hashlib.sha256(prompt.encode()).hexdigest()
                except (ValueError, KeyError, TypeError):
                    pass
            try:
                upstream = urllib.request.Request(
                    "http://127.0.0.1:8317/v1/chat/completions", data=body,
                    headers={"Content-Type": "application/json", "Authorization": "Bearer " + key},
                )
                with urllib.request.urlopen(upstream, timeout=600) as response:
                    result = response.read(1024 * 1024 + 1)
                    status = response.status
                parsed = json.loads(result)
                record.update(response_model=parsed.get("model"), request_id=parsed.get("id"), usage=parsed.get("usage"))
            except urllib.error.HTTPError as error:
                status = error.code
                result = b'{"error":{"message":"Upstream HTTP failure"}}'
            except (OSError, ValueError):
                status = 502
                result = b'{"error":{"message":"Upstream unavailable"}}'
            record.update(http_status=status, elapsed_sec=round(time.monotonic() - started, 3),
                          finished_at=datetime.now(timezone.utc).isoformat())
            with lock, args.log.open("a") as log:
                log.write(json.dumps(record) + "\n")
            try:
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(result)))
                self.end_headers()
                self.wfile.write(result)
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"UI audit relay listening on 127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
