"""Harbor -> Trail controller -> ACP -> MCP -> native SSH; not a UI score."""
from __future__ import annotations
import asyncio
import getpass
import json
import os
import shutil
import signal
import socket
import tempfile
from pathlib import Path
from .ui_agent import TrailUiAgent

ROOT = Path(__file__).resolve().parents[2]


class TrailAcpAgent(TrailUiAgent):
    @staticmethod
    def name() -> str:
        return "trail-acp"

    def version(self) -> str:
        return "1.0.0"

    async def run(self, instruction, environment, context) -> None:
        if self.model_name != "gpt-5.6-sol":
            raise ValueError("This frozen evaluation requires gpt-5.6-sol")
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        instruction_file = self.logs_dir / "instruction.txt"
        instruction_file.write_text(instruction)
        private = Path(tempfile.mkdtemp(prefix="trail-acp-bench-"))
        processes = []
        try:
            for key in ("host", "client"):
                process = await asyncio.create_subprocess_exec(
                    "ssh-keygen", "-q", "-t", "ed25519", "-N", "",
                    "-f", str(private / key),
                )
                if await process.wait():
                    raise RuntimeError("Cannot create ephemeral transport keys")
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = sock.getsockname()[1]
            entry = private / "enter.py"
            docker_args = [
                shutil.which("docker"), "--context", "colima-trail-tbench",
                "exec", "-i", "-t", "--env", "SHELL=/bin/bash",
                "--user", self.user, "--workdir", self.cwd, self.container,
            ]
            # All shell text runs inside this exact disposable container.
            entry.write_text(
                "#!" + str(Path(os.sys.executable).resolve()) + "\n"
                "import os\n"
                "args = " + repr(docker_args) + "\n"
                "command = os.environ.get('SSH_ORIGINAL_COMMAND', '')\n"
                "args += ['/bin/sh', '-c', command] if command else "
                "['/bin/bash', '--noprofile', '--norc', '-i']\n"
                "os.execv(args[0], args)\n"
            )
            entry.chmod(0o700)
            config = private / "sshd_config"
            config.write_text(f"""Port {port}
ListenAddress 127.0.0.1
HostKey {private}/host
PidFile {private}/pid
AuthorizedKeysFile {private}/client.pub
AllowUsers {getpass.getuser()}
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PermitUserEnvironment no
PermitUserRC no
AllowAgentForwarding no
X11Forwarding no
AllowTcpForwarding no
PermitTunnel no
ForceCommand {entry}
LogLevel ERROR
""")
            host_public = (private / "host.pub").read_text().split()
            known_hosts = private / "known_hosts"
            known_hosts.write_text(f"[127.0.0.1]:{port} {host_public[0]} {host_public[1]}\n")
            with (self.logs_dir / "transport.log").open("w") as transport_log:
                sshd = await asyncio.create_subprocess_exec(
                    "/usr/sbin/sshd", "-D", "-e", "-f", str(config),
                    stdout=transport_log, stderr=transport_log, start_new_session=True,
                )
                processes.append(sshd)
                await asyncio.sleep(0.3)
                if sshd.returncode is not None:
                    raise RuntimeError("Disposable SSH transport failed to start")
                job = {
                    "model": self.model_name, "container": self.container,
                    "image_id": self.image, "provenance": self.provenance,
                    "agent_command": str(Path(shutil.which("node")).resolve()),
                    "agent_arguments": [str(ROOT / "tmp/acp-runtime/node_modules/@agentclientprotocol/codex-acp/dist/index.js")],
                    "instruction_file": str(instruction_file.resolve()),
                    "output": str(self.logs_dir.resolve()),
                    "connection": {
                        "type": "ssh", "host": "127.0.0.1", "port": port,
                        "user": getpass.getuser(), "auth": "publicKey",
                        "privateKeys": [str(private / "client")],
                        "hostKeyPolicy": "strict", "knownHostsFile": str(known_hosts),
                    },
                }
                job_path = private / "job.json"
                job_path.write_text(json.dumps(job))
                job_path.chmod(0o600)
                env = {
                    **os.environ, "TRAIL_ACP_BENCH_JOB": str(job_path),
                    "IANVS_CORE_LIB": str(ROOT / "native/core/target/debug/libianvs_core.dylib"),
                }
                with (self.logs_dir / "flutter.log").open("w") as log:
                    flutter = os.environ.get("TRAIL_FLUTTER") or shutil.which("flutter")
                    if not flutter:
                        raise RuntimeError("Set TRAIL_FLUTTER")
                    process = await asyncio.create_subprocess_exec(
                        flutter, "test", "tool/acp_terminal_bench_test.dart",
                        "--no-pub", "--concurrency=1", "--reporter=expanded",
                        cwd=ROOT / "example", env=env, stdout=log, stderr=log,
                        start_new_session=True,
                    )
                    processes.append(process)
                    code = await process.wait()
                result_path = self.logs_dir / "acp-result.json"
                if result_path.exists():
                    result = json.loads(result_path.read_text())
                    # ACP 2.1.1 reports only the last inference here, not total
                    # task consumption. Do not publish it as an aggregate.
                    context.metadata = {"trail_acp": result, "provenance": self.provenance}
                if code:
                    raise RuntimeError("Trail ACP runner failed; inspect retained flutter.log")
        finally:
            for process in reversed(processes):
                if process.returncode is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        await asyncio.wait_for(process.wait(), 5)
                    except TimeoutError:
                        os.killpg(process.pid, signal.SIGKILL)
                        await process.wait()
            shutil.rmtree(private)
