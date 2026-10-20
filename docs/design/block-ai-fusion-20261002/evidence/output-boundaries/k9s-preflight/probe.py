import fcntl
import http.server
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import termios
import threading
import time
from urllib.parse import urlparse, parse_qs

home = Path(tempfile.mkdtemp(prefix='trail-k9s-', dir='/private/tmp'))
requests = []
stop = threading.Event()
resources = {'pods': 'Pod', 'namespaces': 'Namespace', 'nodes': 'Node', 'events': 'Event'}
pod = {'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': 'trail-fixture-pod', 'namespace': 'default', 'uid': 'fixture-pod', 'resourceVersion': '1', 'creationTimestamp': '2026-10-01T00:00:00Z'}, 'spec': {'nodeName': 'fixture-node', 'containers': [{'name': 'fixture', 'image': 'fixture-only:1'}]}, 'status': {'phase': 'Running', 'podIP': '127.0.0.2', 'containerStatuses': [{'name': 'fixture', 'ready': True, 'restartCount': 0, 'image': 'fixture-only:1', 'imageID': 'fixture-only', 'state': {'running': {'startedAt': '2026-10-01T00:00:00Z'}}}]}}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        uri = urlparse(self.path)
        path = uri.path
        requests.append(['GET', self.path])
        if path == '/version':
            data = {'major': '1', 'minor': '32', 'gitVersion': 'v1.32.0', 'gitCommit': 'fixture', 'platform': 'darwin/arm64'}
        elif path == '/api': data = {'apiVersion': 'v1', 'kind': 'APIVersions', 'versions': ['v1']}
        elif path == '/apis': data = {'apiVersion': 'v1', 'kind': 'APIGroupList', 'groups': []}
        elif path == '/api/v1':
            data = {'apiVersion': 'v1', 'kind': 'APIResourceList', 'groupVersion': 'v1', 'resources': [{'name': name, 'singularName': kind.lower(), 'namespaced': name in ['pods', 'events'], 'kind': kind, 'verbs': ['get', 'list', 'watch'], 'shortNames': ['po'] if name == 'pods' else []} for name, kind in resources.items()]}
        elif path.rsplit('/', 1)[-1] in resources:
            name = path.rsplit('/', 1)[-1]
            items = [pod] if name == 'pods' else ([{'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': 'default', 'uid': 'fixture-namespace', 'resourceVersion': '1'}, 'status': {'phase': 'Active'}}] if name == 'namespaces' else [])
            if parse_qs(uri.query).get('watch') == ['true']:
                self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers()
                try:
                    for item in items: self.wfile.write((json.dumps({'type': 'ADDED', 'object': item}) + '\n').encode())
                    self.wfile.flush(); stop.wait(30)
                except (BrokenPipeError, ConnectionResetError): pass
                return
            data = {'apiVersion': 'v1', 'kind': resources[name] + 'List', 'metadata': {'resourceVersion': '1'}, 'items': items}
        else:
            self.send_response(404); self.end_headers(); return
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    def do_POST(self):
        requests.append(['POST', self.path])
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.send_response(201); self.send_header('Content-Type', 'application/json'); self.end_headers()
        self.wfile.write(json.dumps({'apiVersion': 'authorization.k8s.io/v1', 'kind': 'SelfSubjectAccessReview', 'status': {'allowed': True}}).encode())

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
config = {'apiVersion': 'v1', 'kind': 'Config', 'current-context': 'trail-fixture', 'clusters': [{'name': 'trail-fixture', 'cluster': {'server': f'http://127.0.0.1:{server.server_port}'}}], 'users': [{'name': 'fixture', 'user': {}}], 'contexts': [{'name': 'trail-fixture', 'context': {'cluster': 'trail-fixture', 'user': 'fixture', 'namespace': 'default'}}]}
(home/'kubeconfig.json').write_text(json.dumps(config))
(home/'k9s').mkdir()
(home/'k9s/config.yaml').write_text('k9s:\n  skipLatestRevCheck: true\n')
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 44, 160, 0, 0))
def control_terminal():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
child = subprocess.Popen(['/opt/homebrew/bin/k9s', '--kubeconfig', str(home/'kubeconfig.json'), '--readonly', '--splashless', '-c', 'pods', '--logFile', str(home/'k9s.log'), '--logLevel', 'debug', '--request-timeout', '3s'], stdin=slave, stdout=slave, stderr=slave, cwd=home, preexec_fn=control_terminal, env={'HOME': str(home), 'XDG_CONFIG_HOME': str(home), 'XDG_DATA_HOME': str(home), 'PATH': '/usr/bin:/bin', 'TERM': 'xterm-256color', 'LANG': 'en_US.UTF-8'})
os.close(slave)
output = bytearray()
deadline = time.monotonic() + 12
while time.monotonic() < deadline and child.poll() is None:
    if select.select([master], [], [], .2)[0]:
        try: output.extend(os.read(master, 65536))
        except OSError: break
if child.poll() is None:
    try: os.write(master, b':q\r')
    except OSError: pass
deadline = time.monotonic() + 5
while time.monotonic() < deadline and child.poll() is None:
    if select.select([master], [], [], .2)[0]:
        try: output.extend(os.read(master, 65536))
        except OSError: break
if child.poll() is None: child.kill(); child.wait(5)
stop.set(); server.shutdown(); server.server_close(); os.close(master)
(home/'raw-output.bin').write_bytes(output)
(home/'requests.json').write_text(json.dumps(requests, indent=2))
print(json.dumps({'home': str(home), 'exit': child.returncode, 'alternate_screen': b'\x1b[?1049h' in output, 'fixture_pod_visible': b'trail-fixture-pod' in output, 'requests': requests}))
