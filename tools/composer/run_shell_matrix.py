#!/usr/bin/env python3
"""Required local zsh/real PTY contract checks; never invokes user dotfiles."""
import argparse
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import socket
import sys
import shlex
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--required', action='store_true')
    parser.add_argument('--shell', choices=['zsh'], default='zsh')
    parser.parse_args()
    shell = shutil.which('zsh')
    if not shell:
        raise SystemExit('BLOCKED: zsh is required')
    source = Path(__file__).resolve().parents[2] / 'native/core/src/composer_bridge.zsh'
    with tempfile.TemporaryDirectory(prefix='ic-', dir='/tmp') as directory:
        path = Path(directory)
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(str(path / 's'))
        listener.listen(1)
        listener.settimeout(5)
        script = source.read_text().replace('@@SOCKET@@', str(path / 's')).replace('@@NONCE@@', 'fixture')
        (path / '.zshrc').write_text('PROMPT="test> "\nRPROMPT=""\n' + script)
        pid, fd = pty.fork()
        if pid == 0:
            os.environ.update(HOME=directory, ZDOTDIR=directory, TERM='xterm-256color')
            os.execv(shell, [shell, '-d', '-i'])
        conn = None
        buffer = b''
        output = bytearray()
        events = []
        def line(prefix, timeout=5, wake=True):
            nonlocal buffer
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                while b'\n' in buffer:
                    item, buffer = buffer.split(b'\n', 1)
                    events.append(item)
                    if wake and item.startswith(b'prepared\t'):
                        os.write(fd, b'\x00')
                    if item.startswith(prefix):
                        if prefix in (b'ready', b'continuation'):
                            expected = sum(e.startswith((b'ready\t', b'continuation')) for e in events)
                            while output.count(b'\x1b[?2004h') < expected and time.monotonic() < deadline:
                                if select.select([fd], [], [], .1)[0]:
                                    output.extend(os.read(fd, 65536))
                        return item.decode().split('\t')
                readable, _, _ = select.select([conn, fd], [], [], .1)
                if fd in readable:
                    try: output.extend(os.read(fd, 65536))
                    except OSError: pass
                if conn in readable:
                    data = conn.recv(32768)
                    if not data: raise AssertionError('bridge closed: ' + output.decode(errors='replace'))
                    buffer += data
            raise AssertionError('missing ' + repr(prefix) + ': ' + repr(events) + output.decode(errors='replace'))
        def submit(epoch, id, text):
            conn.sendall(('submit\t' + epoch + '\t' + id + '\t' + text.encode().hex() + '\n').encode())
        try:
            conn, _ = listener.accept()
            assert line(b'hello') == ['hello', 'fixture']
            ready = line(b'ready')
            epoch = ready[1]
            submit(epoch, '1', 'export COMPOSER_FIXTURE=works')
            assert line(b'accepted') == ['accepted', '1']
            ready = line(b'ready')
            assert ready[1] != epoch
            submit(epoch, 'stale', 'print SHOULD_NOT_EXECUTE')
            assert line(b'rejected') == ['rejected', 'stale']
            submit(ready[1], '2', 'print "RESULT:$COMPOSER_FIXTURE:你好😀"')
            line(b'accepted'); ready = line(b'ready')
            assert 'RESULT:works:你好😀' in output.decode(errors='replace')
            child = "import os,sys; fd=int(sys.argv[1]);\ntry: os.fstat(fd); print('FD_INHERITED')\nexcept OSError: print('FD_CLOSED')"
            submit(ready[1], 'fd', shlex.quote(sys.executable) + " -c " + shlex.quote(child) + ' "$__ic_fd"')
            line(b'accepted'); ready = line(b'ready')
            # Compare output lines, not the shell's echo of the fixture source.
            assert b'\r\nFD_CLOSED\r\n' in output, output.decode(errors='replace')
            submit(ready[1], '3', 'cd /tmp')
            line(b'accepted'); ready = line(b'ready')
            assert bytes.fromhex(ready[2]).decode() in ('/tmp', '/private/tmp')
            os.write(fd, b'echo raw')
            line(b'busy')
            submit(ready[1], 'nonempty', 'print SHOULD_NOT_EXECUTE')
            assert line(b'rejected') == ['rejected', 'nonempty']
            os.write(fd, b'\x03')
            ready = line(b'ready')
            submit(ready[1], '4', 'print "first\nsecond"')
            line(b'accepted'); ready = line(b'ready')
            assert b'first\r\nsecond' in output
            submit(ready[1], '5', "print 'unfinished")
            line(b'accepted'); line(b'continuation')
            os.write(fd, b'\x03')
            ready = line(b'ready')
            submit(ready[1], '6', 'read -s "secret?Password: "')
            line(b'accepted')
            conn.settimeout(.25)
            try:
                assert not conn.recv(4096).startswith(b'ready')
            except TimeoutError: pass
            os.write(fd, b'fixture-only\r')
            ready = line(b'ready')
            submit(ready[1], 'cancelled', 'print SHOULD_NOT_EXECUTE')
            line(b'prepared', wake=False)
            conn.close()
            conn = None
            # Allow the EOF handler to restore the keymap before raw input.
            time.sleep(.05)
            os.write(fd, b'\x00print RAW_AFTER_CLOSE\r')
            deadline = time.monotonic() + 3
            while b'\r\nRAW_AFTER_CLOSE\r\n' not in output and time.monotonic() < deadline:
                if select.select([fd], [], [], .1)[0]:
                    output.extend(os.read(fd, 65536))
            assert b'\r\nRAW_AFTER_CLOSE\r\n' in output, output.decode(errors='replace')
            assert b'SHOULD_NOT_EXECUTE' not in output
            print('PASS: local zsh real PTY; export, cwd, Unicode, multiline, stale lease, nonempty buffer, continuation, password/raw isolation, close-on-exec, disconnect recovery')
        finally:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            os.close(fd)
            if conn: conn.close()
            listener.close()

if __name__ == '__main__':
    main()
