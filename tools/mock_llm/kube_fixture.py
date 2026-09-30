#!/usr/bin/env python3
"""Isolated read-only Kubernetes fixture for testing the real k9s binary.

No proxying, real credentials or cluster changes. Only loopback is bound.
"""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

RESOURCES = [("pods", "Pod", True, ["po"]), ("namespaces", "Namespace", False, ["ns"]),
             ("nodes", "Node", False, ["no"]), ("events", "Event", True, ["ev"])]


def metadata(name, **extra):
    return {"name": name, "uid": f"fixture-{name}", "resourceVersion": "1", "creationTimestamp": "2025-01-01T00:00:00Z", **extra}


def items(resource):
    if resource == "namespaces":
        return [{"apiVersion": "v1", "kind": "Namespace", "metadata": metadata("default"), "status": {"phase": "Active"}}]
    if resource == "pods":
        return [{"apiVersion": "v1", "kind": "Pod", "metadata": metadata("trail-ai-pod", namespace="default"),
            "spec": {"nodeName": "fixture-node", "containers": [{"name": "app", "image": "fixture:local", "resources": {}}]},
            "status": {"phase": "Running", "podIP": "10.0.0.2", "qosClass": "BestEffort",
                "containerStatuses": [{"name": "app", "ready": True, "restartCount": 0,
                    "image": "fixture:local", "imageID": "fixture", "started": True, "state": {"running": {"startedAt": "2025-01-01T00:00:00Z"}}}]}}]
    if resource == "nodes":
        return [{"apiVersion": "v1", "kind": "Node", "metadata": metadata("fixture-node"), "spec": {},
            "status": {"capacity": {"cpu": "2", "memory": "2Gi", "pods": "10"}, "allocatable": {"cpu": "2", "memory": "2Gi", "pods": "10"},
                "conditions": [{"type": "Ready", "status": "True"}],
                "nodeInfo": {"kubeletVersion": "v1.31.0", "osImage": "Fixture", "architecture": "arm64", "operatingSystem": "linux", "containerRuntimeVersion": "fixture://1"}}}]
    return []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self, payload, code=200):
        raw = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        try:
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        if path == "/version":
            return self.respond({"major": "1", "minor": "31", "gitVersion": "v1.31.0", "platform": "linux/arm64"})
        if path == "/api":
            return self.respond({"kind": "APIVersions", "versions": ["v1"], "serverAddressByClientCIDRs": []})
        if path == "/apis":
            return self.respond({"kind": "APIGroupList", "apiVersion": "v1", "groups": []})
        if path == "/api/v1":
            return self.respond({"kind": "APIResourceList", "groupVersion": "v1", "resources": [
                {"name": name, "singularName": kind.lower(), "namespaced": namespaced, "kind": kind,
                 "verbs": ["get", "list", "watch"], "shortNames": short} for name, kind, namespaced, short in RESOURCES]})
        for name, kind, _, _ in RESOURCES:
            if path in [f"/api/v1/{name}", f"/api/v1/namespaces/default/{name}"]:
                if parse_qs(parsed.query).get("watch") == ["true"]:
                    # A finite watch is valid and k9s reconnects using resourceVersion.
                    events = b"".join((json.dumps({"type": "ADDED", "object": item}) + "\n").encode() for item in items(name))
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(events)))
                    self.end_headers()
                    self.wfile.write(events)
                    return
                return self.respond({"kind": kind + "List", "apiVersion": "v1", "metadata": {"resourceVersion": "1"}, "items": items(name)})
        if path == "/api/v1/namespaces/default":
            return self.respond(items("namespaces")[0])
        return self.respond({"kind": "Status", "apiVersion": "v1", "status": "Failure", "reason": "NotFound", "code": 404}, 404)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path.endswith("selfsubjectaccessreviews"):
            return self.respond({"apiVersion": "authorization.k8s.io/v1", "kind": "SelfSubjectAccessReview", "status": {"allowed": True}})
        return self.respond({"kind": "Status", "code": 403, "reason": "ReadOnlyFixture"}, 403)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18788)
    parser.add_argument("--kubeconfig", required=True)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    Path(args.kubeconfig).write_text(json.dumps({"apiVersion": "v1", "kind": "Config",
        "clusters": [{"name": "trail-fixture", "cluster": {"server": f"http://127.0.0.1:{server.server_port}"}}],
        "users": [{"name": "fixture", "user": {}}],
        "contexts": [{"name": "trail-fixture", "context": {"cluster": "trail-fixture", "user": "fixture", "namespace": "default"}}],
        "current-context": "trail-fixture"}))
    print(f"Read-only Kubernetes fixture ready on {server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
