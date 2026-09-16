#!/usr/bin/env python3
"""Verify generated Alt-click sequences against real shell line editing.

Receives JSON cases as argv[1], each containing command, sequence, and expected.
Only uses an isolated interactive shell with startup files disabled.
"""
import fcntl
import json
import os
import pty
import select
import signal
import struct
import sys
import termios
import time


def read_until(fd, marker):
    output = b""
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 0.1)[0]:
            output += os.read(fd, 65536)
            if marker in output:
                return output
    raise AssertionError(f"Missing {marker!r}; got {output!r}")


def verify(case, shell):
    pid, fd = pty.fork()
    if pid == 0:
        env = dict(os.environ, TERM="xterm-256color", LANG="en_US.UTF-8", LC_ALL="en_US.UTF-8")
        args = [shell, "-f", "-i"] if shell.endswith("zsh") else [shell, "--noprofile", "--norc", "-i"]
        os.execve(shell, args, env)
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, case["cols"], 0, 0))
        if shell.endswith("zsh"):
            setup = "unsetopt PROMPT_SP; PROMPT='> '; RPROMPT=''; bindkey -e; "
        else:
            setup = "PS1='> '; PS2=''; set -o emacs; "
        os.write(fd, (setup + "printf '\\n__READY__\\n'\r").encode())
        read_until(fd, b"\r\n__READY__\r\n")
        os.write(fd, case["command"].encode())
        # FIFO ordering ensures the editor receives text before navigation.
        os.write(fd, case["beforeSequence"].encode() + case["sequence"].encode() + b"X\r")
        read_until(fd, ("\r\nACCEPT:" + case["expected"] + ":END\r\n").encode())
    finally:
        os.close(fd)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)


if __name__ == "__main__":
    cases = json.loads(sys.argv[1])
    shells = [shell for shell in ("/bin/zsh", "/bin/bash") if os.path.isfile(shell)]
    if not shells:
        raise RuntimeError("No supported shell found")
    for shell in shells:
        for case in cases:
            verify(case, shell)
            print(f"PASS {shell}: {case['name']}")
