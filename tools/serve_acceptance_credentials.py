#!/usr/bin/env python3
"""Serve one private acceptance credential document on loopback."""

from __future__ import annotations

import http.server
import pathlib
import secrets
import sys


class _Handler(http.server.BaseHTTPRequestHandler):
    credential_path: str
    contents: bytes
    consumed_file: pathlib.Path | None = None

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path != self.credential_path:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(self.contents)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(self.contents)
        self.wfile.flush()
        if self.consumed_file is not None:
            self.consumed_file.write_text("consumed\n", encoding="utf-8")
            self.consumed_file.chmod(0o600)

    def log_message(self, _format: str, *args: object) -> None:
        del args


def main() -> int:
    if len(sys.argv) not in (3, 4):
        raise SystemExit(
            "usage: serve_acceptance_credentials.py JSON READY_FILE [CONSUMED_FILE]"
        )
    credentials = pathlib.Path(sys.argv[1]).read_bytes()
    if len(credentials) > 4096:
        raise SystemExit("credential document exceeds 4096 bytes")
    credential_path = f"/{secrets.token_urlsafe(32)}"
    _Handler.credential_path = credential_path
    _Handler.contents = credentials
    if len(sys.argv) == 4:
        _Handler.consumed_file = pathlib.Path(sys.argv[3])
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
    ready_file = pathlib.Path(sys.argv[2])
    ready_file.write_text(
        f"http://127.0.0.1:{server.server_port}{credential_path}",
        encoding="utf-8",
    )
    ready_file.chmod(0o600)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
