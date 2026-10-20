"""Harbor lifecycle only. A human/UI driver operates an already running Trail.

This agent never calls a model, terminal controller, shell solver or approval.
It exposes the disposable transport, waits for UI completion, then lets Harbor
run the unmodified official verifier.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import os
import re
from datetime import datetime, timezone

from harbor.agents.base import BaseAgent
from harbor.environments.docker.docker import DockerEnvironment
from harbor.models.agent.context import AgentContext


class TrailUiAgent(BaseAgent):
    @staticmethod
    def name() -> str:
        return "trail-ui"

    def version(self) -> str:
        return "0.1.0"

    async def setup(self, environment) -> None:
        if not isinstance(environment, DockerEnvironment):
            raise ValueError("UI acceptance currently requires the isolated Docker environment")
        if os.environ.get("DOCKER_CONTEXT") != "colima-trail-tbench":
            raise ValueError("Use the dedicated benchmark Docker context")
        result = await environment._run_docker_compose_command(["ps", "-q", "main"])
        process = await asyncio.create_subprocess_exec(
            "docker", "--context", "colima-trail-tbench", "inspect", result.stdout.strip(),
            stdout=asyncio.subprocess.PIPE,
        )
        output, _ = await process.communicate()
        if process.returncode:
            raise RuntimeError("Cannot identify the isolated task container")
        record = json.loads(output)[0]
        self.container = record["Id"]
        if not re.fullmatch(r"[a-f0-9]{64}", self.container):
            raise ValueError("Expected exact container identity")
        self.image = record["Image"]
        self.cwd = record["Config"].get("WorkingDir") or "/"
        self.user = record["Config"].get("User") or "root"
        image_process = await asyncio.create_subprocess_exec(
            "docker", "--context", "colima-trail-tbench", "image", "inspect", self.image,
            stdout=asyncio.subprocess.PIPE,
        )
        image_output, _ = await image_process.communicate()
        if image_process.returncode:
            raise RuntimeError("Cannot record task image provenance")
        image = json.loads(image_output)[0]
        self.provenance = {
            "image_architecture": image.get("Architecture"),
            "image_os": image.get("Os"),
            "image_repo_digests": image.get("RepoDigests", []),
            "docker_context": "colima-trail-tbench",
            "memory_bytes": record["HostConfig"].get("Memory"),
            "nano_cpus": record["HostConfig"].get("NanoCpus"),
        }

    async def run(self, instruction: str, environment, context: AgentContext) -> None:
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        (self.logs_dir / "ui-instruction.txt").write_text(instruction)
        ready = {
            "container": self.container, "image_id": self.image,
            "cwd": self.cwd, "user": self.user, "requested_model": self.model_name,
            "instruction_sha256": hashlib.sha256(instruction.encode()).hexdigest(),
            "ready_at": datetime.now(timezone.utc).isoformat(),
            "provenance": self.provenance,
            "scope": "UI only; no solver/controller/approval calls in this adapter",
        }
        (self.logs_dir / "ui-ready.json").write_text(json.dumps(ready, indent=2))
        finished = self.logs_dir / "ui-complete.json"
        while not finished.exists():
            await asyncio.sleep(1)
        record = json.loads(finished.read_text())
        if record.get("source") != "trail-real-ui" or not record.get("evidence"):
            raise ValueError("Completion requires a real UI evidence record")
        context.n_input_tokens = record.get("input_tokens")
        context.n_output_tokens = record.get("output_tokens")
        context.n_cache_tokens = record.get("cached_tokens")
        context.metadata = {"ui": record, "environment": ready}
