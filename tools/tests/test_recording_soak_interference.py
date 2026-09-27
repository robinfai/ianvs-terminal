#!/usr/bin/env python3
"""Verify the real shell behavior behind externally contaminated soak input."""
import os
from pathlib import Path
import pty
import select
import shlex
import signal
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(sys.platform == 'darwin' and Path('/bin/bash').exists(),
                     'requires the macOS system Bash used by recording acceptance')
class BashInputInterferenceTest(unittest.TestCase):
    def test_escape_prefix_consumes_command_without_a_terminal_or_recorder(self):
        with tempfile.TemporaryDirectory(prefix='ianvs-bash-escape-') as temporary:
            root = Path(temporary)
            for escape in (False, True):
                with self.subTest(escape=escape):
                    child, master = pty.fork()
                    if child == 0:
                        env = dict(os.environ)
                        env.update(PS1='DIAGNOSTIC> ', INPUTRC='/dev/null',
                                   HISTFILE=str(root / f'history-{escape}'),
                                   TERM='xterm-256color')
                        os.execve('/bin/bash', ['/bin/bash', '--noprofile', '--norc', '-i'], env)
                    try:
                        transcript = self.read_until(master, b'DIAGNOSTIC> ')
                        os.write(master, b'bind -q non-incremental-reverse-search-history\n')
                        binding = self.read_until(master, b'DIAGNOSTIC> ')
                        self.assertIn(b'\\ep', binding)
                        if escape:
                            os.write(master, b'\x1b')
                        marker = root / f'command-{escape}'
                        self.write_marker(master, marker)
                        # A failed history search rings the bell instead of
                        # emitting a fresh prompt; wait for that actual response.
                        transcript += self.read_until(master, b'\x07' if escape else b'DIAGNOSTIC> ')
                        if escape:
                            self.assertIn(b':rintf', transcript)
                        self.assertEqual(marker.exists(), not escape, repr(transcript))
                        # Cancel shell editing explicitly before proving it still
                        # executes fresh input. This is not a soak recovery policy.
                        os.write(master, b'\x03')
                        self.read_until(master, b'DIAGNOSTIC> ')
                        recovery = root / f'recovery-{escape}'
                        self.write_marker(master, recovery)
                        transcript += self.read_until(master, b'DIAGNOSTIC> ')
                        self.assertEqual(recovery.read_text(), 'executed', repr(transcript))
                        self.assertEqual(marker.exists(), not escape)
                    finally:
                        os.close(master)
                        deadline = time.monotonic() + 2
                        while os.waitpid(child, os.WNOHANG)[0] == 0:
                            if time.monotonic() >= deadline:
                                os.kill(child, signal.SIGKILL)
                                os.waitpid(child, 0)
                                break
                            time.sleep(.02)

    def write_marker(self, master, path):
        os.write(master, f"printf '%s' executed > {shlex.quote(str(path))}\n".encode())

    def read_until(self, master, marker):
        output = b''
        deadline = time.monotonic() + 5
        while marker not in output:
            remaining = deadline - time.monotonic()
            self.assertGreater(remaining, 0, repr(output))
            ready, _, _ = select.select([master], [], [], remaining)
            if ready:
                data = os.read(master, 65536)
                self.assertTrue(data, repr(output))
                output += data
        return output


if __name__ == '__main__':
    unittest.main()
