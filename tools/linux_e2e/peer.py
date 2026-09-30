#!/usr/bin/env python3
"""Disposable independent SSH peer. Never use this fixture as a real server."""

import argparse
import asyncio
import contextlib
import errno
import fcntl
import logging
import os
from pathlib import Path
import pty
import signal
import struct
import termios

import asyncssh


async def ready(fd, *, write=False):
    loop = asyncio.get_running_loop()
    result = loop.create_future()
    add = loop.add_writer if write else loop.add_reader
    remove = loop.remove_writer if write else loop.remove_reader
    add(fd, lambda: None if result.done() else result.set_result(None))
    try:
        await result
    finally:
        remove(fd)


def resize(fd, size):
    width, height, pixwidth, pixheight = size
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, pixheight, pixwidth))


async def relay_input(process, master):
    while True:
        try:
            data = await process.stdin.read(65536)
        except asyncssh.TerminalSizeChanged as change:
            resize(master, change.term_size)
            continue
        if not data:
            return
        while data:
            try:
                count = os.write(master, data)
                data = data[count:]
            except BlockingIOError:
                await ready(master, write=True)


async def relay_output(process, master):
    while True:
        try:
            data = os.read(master, 65536)
        except BlockingIOError:
            await ready(master)
            continue
        except OSError as error:
            if error.errno == errno.EIO:  # Linux PTY reports EIO after its slave closes.
                return
            raise
        if not data:
            return
        process.stdout.write(data)
        await process.stdout.drain()


async def shell(process, root):
    if process.command is not None or not process.term_type:
        process.exit(1)
        return
    pid, master = pty.fork()
    if pid == 0:
        # No inherited user startup files, credentials, shell hooks, or agent socket.
        # Disable job control so test subprocesses stay in the cleanup process group.
        os.chdir(root / "home")
        os.execve("/bin/bash", ["bash", "--noprofile", "--norc", "-i", "+m"], {
            "HOME": str(root / "home"), "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8",
            "TERM": process.term_type, "PS1": "loopback$ ", "HISTFILE": "/dev/null",
        })
    tasks = []
    try:
        os.set_blocking(master, False)
        resize(master, process.term_size)
        input_task = asyncio.create_task(relay_input(process, master))
        output_task = asyncio.create_task(relay_output(process, master))
        closed_task = asyncio.create_task(process.wait_closed())
        tasks = [input_task, output_task, closed_task]
        done, _ = await asyncio.wait([output_task, closed_task], return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
        if output_task in done:
            _, status = await asyncio.to_thread(os.waitpid, pid, 0)
            pid = 0
            process.exit(os.waitstatus_to_exitcode(status))
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        os.close(master)
        if pid:
            # pty.fork creates a separate session/process group; clean up shell children too.
            with contextlib.suppress(ProcessLookupError):
                os.killpg(pid, signal.SIGKILL)
            with contextlib.suppress(ChildProcessError):
                await asyncio.to_thread(os.waitpid, pid, 0)


class Server(asyncssh.SSHServer):
    def __init__(self, username, key):
        self.username = username
        self.key = key

    def begin_auth(self, username):
        return True

    def public_key_auth_supported(self):
        return True

    def validate_public_key(self, username, key):
        return username == self.username and key == self.key


async def main(root, username):
    key = asyncssh.read_public_key(root / "client_key.pub")
    async with asyncssh.create_server(
        lambda: Server(username, key), "127.0.0.1", 0,
        server_host_keys=[root / "host_key"],
        process_factory=lambda process: shell(process, root),
        sftp_factory=lambda channel: asyncssh.SFTPServer(channel, chroot=root),
        encoding=None, line_editor=False, allow_scp=False,
        password_auth=False, kbdint_auth=False, agent_forwarding=False,
    ) as server:
        port = server.get_port()
        (root / "known_hosts").write_text(
            f"[127.0.0.1]:{port} " + (root / "host_key.pub").read_text()
        )
        # Publish only after the listener and strict host-key file are ready.
        (root / "port").write_text(str(port))
        print(f"AsyncSSH {asyncssh.__version__}: loopback port {port}", flush=True)
        stopped = asyncio.Event()
        loop = asyncio.get_running_loop()
        for signum in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(signum, stopped.set)
        await stopped.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("username")
    args = parser.parse_args()
    logging.basicConfig(level=logging.WARNING)
    asyncio.run(main(args.root.resolve(), args.username))
