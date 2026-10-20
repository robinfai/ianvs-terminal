"""Ephemeral UI SSH transport: forced task-container shell + local proxy tunnel.

No host shell, SFTP, agent forwarding or arbitrary TCP forwarding is exposed.
The active task is a host-side ready.json selected before a UI connection.
"""
import argparse
import getpass
import ipaddress
import json
import os
import re
import shlex
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / "tmp/terminal-bench/ui-2-1/ssh"


def enter_task():
    ready = json.loads((PRIVATE / "active-task.json").read_text())
    container = ready["container"]
    if not re.fullmatch(r"[a-f0-9]{64}", container):
        raise ValueError("Exact disposable container ID required")
    command = os.environ.get("SSH_ORIGINAL_COMMAND", "")
    # All strings after the container ID are interpreted only inside that
    # disposable container. SSH can never execute a command on the host.
    args = ["/opt/homebrew/bin/docker", "--context", "colima-trail-tbench", "exec", "-i"]
    if os.isatty(0):
        args.append("-t")
    # Match the explicit Bash shell selected in Normal-mode UI attachment.
    # Some official images set SHELL=/bin/sh, which cannot negotiate blocks.
    args += ["--env", "SHELL=/bin/bash", "--user", ready["user"],
             "--workdir", ready["cwd"], container]
    args += ["/bin/sh", "-c", command] if command else ["/bin/bash", "--noprofile", "--norc", "-i"]
    os.execv(args[0], args)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["init", "start", "enter"])
    parser.add_argument("--address")
    parser.add_argument("--port", type=int, default=22318)
    args = parser.parse_args()
    if args.action == "enter":
        enter_task()
        return
    os.umask(0o077)
    PRIVATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    if args.action == "init":
        address = ipaddress.ip_address(args.address or "127.0.0.1")
        if not address.is_private or address.is_unspecified:
            raise ValueError("Bind to an explicit private host address")
        for name in ("host", "client"):
            if not (PRIVATE / name).exists():
                subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(PRIVATE / name)], check=True)
        entry = PRIVATE / "force-entry"
        python = ROOT / "tmp/terminal-bench/venv/bin/python"
        entry.write_text("#!/bin/sh\nexec " + shlex.quote(str(python)) + " " + shlex.quote(str(Path(__file__).resolve())) + " enter\n")
        entry.chmod(0o700)
        config = f"""Port {args.port}
ListenAddress {address}
HostKey {PRIVATE}/host
PidFile {PRIVATE}/pid
AuthorizedKeysFile {PRIVATE}/client.pub
AllowUsers {getpass.getuser()}
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PermitUserEnvironment no
PermitUserRC no
AllowAgentForwarding no
X11Forwarding no
AllowTcpForwarding local
PermitOpen 127.0.0.1:8318
PermitListen none
GatewayPorts no
ForceCommand {entry}
LogLevel ERROR
"""
        (PRIVATE / "sshd_config").write_text(config)
        subprocess.run(["/usr/sbin/sshd", "-t", "-f", str(PRIVATE / "sshd_config")], check=True)
        (PRIVATE / "connection.json").write_text(json.dumps({
            "host": str(address), "port": args.port, "user": getpass.getuser(),
            "private_key_file": str(PRIVATE / "client"),
            "forward": "L 127.0.0.1:8318 127.0.0.1:8318",
        }, indent=2))
        print("Private SSH bridge configuration ready; no secrets printed.")
    else:
        os.execv("/usr/sbin/sshd", ["/usr/sbin/sshd", "-D", "-e", "-f", str(PRIVATE / "sshd_config")])


if __name__ == "__main__":
    main()
