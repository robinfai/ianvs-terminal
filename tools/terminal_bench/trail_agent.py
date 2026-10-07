"""Harbor adapter for Trail's actual Flutter AI controller and native PTY.

Only instruction.md and the task container reach the solving agent. Harbor owns
environment creation, deadlines, verifier isolation and scoring.
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import shutil
import signal
from pathlib import Path

from harbor.agents.base import BaseAgent
from harbor.agents.options import AgentOptions
from harbor.environments.base import BaseEnvironment
from harbor.environments.docker.docker import DockerEnvironment
from harbor.models.agent.context import AgentContext


ROOT = Path(__file__).resolve().parents[2]
CONTEXT = "colima-trail-tbench"
MODELS = {"gpt-6-luna", "gpt-6-sol", "gpt-6-astra"}


class TrailOptions(AgentOptions):
    reasoning_effort: str = "high"


class TrailAgent(BaseAgent):
    options_model = TrailOptions

    @staticmethod
    def name() -> str:
        return "trail-terminal"

    def version(self) -> str:
        return "0.2.0"

    async def setup(self, environment: BaseEnvironment) -> None:
        if not isinstance(environment, DockerEnvironment):
            raise ValueError("This adapter currently supports local Docker trials only")
        if os.environ.get("DOCKER_CONTEXT") != CONTEXT:
            raise ValueError("Use the dedicated colima-trail-tbench Docker context")
        if self.model_name not in MODELS:
            raise ValueError("An exact requested GPT-6 model ID is required")
        result = await environment._run_docker_compose_command(["ps", "-q", "main"])
        short_id = result.stdout.strip()
        proc = await asyncio.create_subprocess_exec(
            "docker", "--context", CONTEXT, "inspect", "--format", "{{.Id}}", short_id,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate()
        self.container_id = stdout.decode().strip()
        if proc.returncode or not re.fullmatch(r"[a-f0-9]{64}", self.container_id):
            raise RuntimeError("Cannot pin the Harbor task container: " + stderr.decode())
        shell = await environment.exec("command -v bash && pwd", timeout_sec=15)
        if shell.return_code != 0:
            raise RuntimeError("This adapter requires bash in the task image")
        self.cwd = shell.stdout.strip().splitlines()[-1]

    async def run(self, instruction: str, environment: BaseEnvironment, context: AgentContext) -> None:
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        instruction_file = self.logs_dir / "trail-instruction.txt"
        instruction_file.write_text(instruction)
        job_file = self.logs_dir / "trail-job.json"
        key_file = ROOT / "tmp/terminal-bench/proxy/client-key"
        flutter = os.environ.get("TRAIL_FLUTTER") or shutil.which("flutter")
        if not flutter or not key_file.is_file():
            raise RuntimeError("Set TRAIL_FLUTTER and complete the local OAuth proxy setup")
        job_file.write_text(json.dumps({
            "container": self.container_id, "docker_context": CONTEXT,
            "docker_executable": shutil.which("docker"), "cwd": self.cwd,
            "user": environment.default_user, "model": self.model_name,
            "reasoning_effort": self.options.reasoning_effort,
            "instruction_file": str(instruction_file.resolve()),
            "key_file": str(key_file), "output": str(self.logs_dir.resolve()),
        }, indent=2))
        env = {**os.environ, "TRAIL_BENCH_JOB": str(job_file.resolve()),
               "IANVS_CORE_LIB": str(ROOT / "native/core/target/debug/libianvs_core.dylib")}
        # No credentials or host workspace mounts are passed to the container.
        with (self.logs_dir / "trail-flutter.log").open("w") as log:
            proc = await asyncio.create_subprocess_exec(
                flutter, "test", "tool/terminal_bench_test.dart", "--no-pub",
                "--concurrency=1", "--reporter=expanded",
                cwd=ROOT / "example", env=env, stdout=log, stderr=log,
                start_new_session=True,
            )
            try:
                await proc.wait()
            finally:
                if proc.returncode is None:
                    os.killpg(proc.pid, signal.SIGTERM)
                    try:
                        await asyncio.wait_for(proc.wait(), 10)
                    except TimeoutError:
                        os.killpg(proc.pid, signal.SIGKILL)
                        await proc.wait()
                result_file = self.logs_dir / "trail-result.json"
                if result_file.exists():
                    result = json.loads(result_file.read_text())
                    context.n_input_tokens = result["n_input_tokens"]
                    context.n_output_tokens = result["n_output_tokens"]
                    context.n_cache_tokens = result["n_cache_tokens"]
                    context.metadata = {"trail": result, "adapter_version": self.version()}
        if proc.returncode:
            raise RuntimeError(f"Trail harness exited {proc.returncode}; see trail-flutter.log")
