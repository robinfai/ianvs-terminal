"""Verify transport fault timing without depending on SSH or Flutter."""

from pathlib import Path
import socket
import tempfile
import time
import unittest

from disconnect_relay import DisconnectRelay


class DisconnectRelayTest(unittest.TestCase):
    def test_paused_output_keeps_input_and_disconnect_discards_pending_output(self):
        with tempfile.TemporaryDirectory() as directory, socket.socket() as server:
            server.bind(('127.0.0.1', 0))
            server.listen()
            server.settimeout(2)
            marker = Path(directory) / 'disconnect.request'
            relay = DisconnectRelay(server.getsockname()[1], marker)

            def fault(action):
                done = marker.with_suffix('.done')
                done.unlink(missing_ok=True)
                staged = marker.with_suffix('.staged')
                staged.write_text(action)
                staged.replace(marker)
                deadline = time.monotonic() + 3
                while not done.exists():
                    if time.monotonic() > deadline:
                        self.fail(f'Relay did not acknowledge {action}')
                    time.sleep(.01)
                self.assertEqual(done.read_text().strip(), action)

            try:
                with socket.create_connection(('127.0.0.1', relay.port)) as client:
                    upstream, _ = server.accept()
                    with upstream:
                        upstream.settimeout(2)
                        client.settimeout(.15)
                        fault('pause-output')
                        client.sendall(b'command')
                        self.assertEqual(upstream.recv(100), b'command')
                        upstream.sendall(b'receipt')
                        with self.assertRaises(socket.timeout):
                            client.recv(100)
                        fault('resume-output')
                        client.settimeout(2)
                        self.assertEqual(client.recv(100), b'receipt')
                        fault('pause-output')
                        upstream.sendall(b'must remain unobserved')
                        fault('disconnect')
                        self.assertEqual(client.recv(100), b'')
                # A fresh connection must not inherit the output pause.
                with socket.create_connection(('127.0.0.1', relay.port)) as client:
                    upstream, _ = server.accept()
                    with upstream:
                        client.settimeout(2)
                        upstream.sendall(b'new connection')
                        self.assertEqual(client.recv(100), b'new connection')
            finally:
                relay.close()


if __name__ == '__main__':
    unittest.main()
