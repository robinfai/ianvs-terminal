"""Loopback-only fault injection for the disposable SSH acceptance server."""

import select
import socket
import threading


class DisconnectRelay:
    def __init__(self, server_port, marker):
        self.server_port = server_port
        self.marker = marker
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen()
        self.port = self.listener.getsockname()[1]
        self.stopping = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        peers = {}
        upstreams = set()
        output_paused = False

        def close_pair(sock):
            peer = peers.pop(sock, None)
            if peer is not None:
                peers.pop(peer, None)
            for item in (sock, peer):
                if item is not None:
                    upstreams.discard(item)
                    try:
                        item.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                    item.close()

        try:
            while not self.stopping.is_set():
                if self.marker.exists():
                    action = self.marker.read_text().strip()
                    if action == 'pause-output':
                        output_paused = True
                    elif action == 'resume-output':
                        output_paused = False
                    else:
                        output_paused = False
                        for sock in list(peers):
                            close_pair(sock)
                    self.marker.unlink()
                    done = self.marker.with_suffix('.done')
                    staged = done.with_suffix('.tmp')
                    staged.write_text(action + '\n')
                    staged.replace(done)
                # Stop reading upstream instead of buffering encrypted SSH
                # payloads. Client input still reaches the disposable server.
                readable = [sock for sock in peers
                            if not output_paused or sock not in upstreams]
                ready, _, _ = select.select([self.listener, *readable], [], [], .05)
                for sock in ready:
                    if sock is self.listener:
                        client, _ = self.listener.accept()
                        try:
                            upstream = socket.create_connection(
                                ('127.0.0.1', self.server_port), timeout=2)
                        except OSError:
                            client.close()
                            continue
                        client.settimeout(2)
                        peers[client] = upstream
                        peers[upstream] = client
                        upstreams.add(upstream)
                    elif sock in peers:
                        try:
                            data = sock.recv(65536)
                            if data:
                                peers[sock].sendall(data)
                            else:
                                close_pair(sock)
                        except OSError:
                            close_pair(sock)
        finally:
            for sock in list(peers):
                close_pair(sock)
            self.listener.close()

    def close(self):
        self.stopping.set()
        self.thread.join(timeout=5)
        if self.thread.is_alive():
            raise RuntimeError('Disposable SSH relay failed to stop')
