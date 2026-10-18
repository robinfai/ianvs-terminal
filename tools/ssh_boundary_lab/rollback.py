#!/usr/bin/env python3
"""Real OpenSSH failure/rollback fixtures; never uses the user's SSH config/keys.

Build an image with tools/ssh_boundary_lab/rollback.Dockerfile, then run this
script. All containers, keys, and networks are temporary; evidence is retained.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=60, **kwargs).stdout.strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--context', default='colima')
    parser.add_argument('--image', default='ianvs-ssh-rollback:20261018')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/ssh-rollback')
    parser.add_argument('--flutter-ui', action='store_true', help='Run the native Block workspace failure scenario instead of the Rust protocol test')
    parser.add_argument('--flutter', default='flutter')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    docker = ['docker', '--context', args.context]
    prefix = f'iv-rollback-{os.getpid()}'
    containers = []
    with tempfile.TemporaryDirectory(prefix='iv-rollback-') as tmp:
        scratch = Path(tmp)
        key = scratch / 'client'
        run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)])
        run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(scratch / 'wrong')])
        try:
            run(docker + ['network', 'create', prefix])
            nodes = {}
            known = []
            for name in ['cloud', 'zsh', 'fish', 'target']:
                container = f'{prefix}-{name}'
                shell = name if name in ('zsh', 'fish') else 'bash'
                containers.append(container)
                run(docker + ['create', '--name', container, '--network', prefix,
                              '--network-alias', name, '-p', '127.0.0.1::22',
                              '-e', f'LAB_ROLE={name}',
                              '-e', f'LAB_SHELL={shell}', args.image])
                for filename in ['client', 'client.pub', 'wrong']:
                    run(docker + ['cp', str(scratch / filename), f'{container}:/fixture/{filename}'])
                run(docker + ['start', container])
                port = int(run(docker + ['port', container, '22/tcp']).split(':')[-1])
                for _ in range(100):
                    result = subprocess.run(docker + ['exec', container, 'cat', '/etc/ssh/ssh_host_ed25519_key.pub'], capture_output=True, text=True)
                    if result.returncode == 0 and result.stdout.startswith('ssh-ed25519 '):
                        break
                    time.sleep(.1)
                else:
                    raise RuntimeError(f'host key unavailable: {name}')
                public = ' '.join(result.stdout.split()[:2])
                known.append(f'{name},[127.0.0.1]:{port} {public}')
                nodes[name] = {'port': port, 'shell': shell}
            known_hosts = scratch / 'known_hosts'
            known_hosts.write_text('\n'.join(known) + '\n')
            for container in containers:
                run(docker + ['cp', str(known_hosts), f'{container}:/home/lab/.ssh/known_hosts'])
                run(docker + ['exec', container, 'bash', '-c', '''
config=/home/lab/.ssh/config
{ printf '%s\n' 'Host sg' '  HostName sg.invalid' 'Host refused' '  HostName 127.0.0.1' '  Port 9' 'Host denied' '  HostName target' '  User absent-user'; cat "$config"; } > "$config.new"
mv "$config.new" "$config"
chown -R lab:lab /home/lab/.ssh
'''])
            config = scratch / 'config'
            config.write_text('\n'.join(
                f'Host {name}\n  HostName 127.0.0.1\n  Port {node["port"]}'
                for name, node in nodes.items()) +
                f'\nHost *\n  User lab\n  IdentityFile {key}\n  IdentitiesOnly yes\n  BatchMode yes\n  StrictHostKeyChecking yes\n  UserKnownHostsFile {known_hosts}\n  ConnectTimeout 3\n')
            # Positive handshake check before product transport acceptance.
            assert run(['ssh', '-F', str(config), 'cloud', 'cat role.txt']) == 'cloud'
            fixture = scratch / 'fixture.json'
            fixture.write_text(json.dumps({'nodes': nodes, 'key': str(key),
                'known_hosts': str(known_hosts), 'local_config': str(config),
                'evidence': str(output / 'evidence.json')}))
            metadata = {'image': run(docker + ['image', 'inspect', '--format', '{{.Id}}', args.image]),
                        'host': run(['sw_vers']),
                        'server': run(docker + ['exec', containers[0], 'sh', '-c', 'ssh -V 2>&1']),
                        'shells': {name: run(docker + ['exec', containers[i], nodes[name]['shell'], '--version']).splitlines()[0]
                                   for i, name in enumerate(nodes)}}
            (output / 'environment.json').write_text(json.dumps(metadata, indent=2) + '\n')
            with (output / 'acceptance.log').open('w') as log:
                command = ([args.flutter, 'test', '--no-pub', 'integration_test/ssh_block_rollback_test.dart', '-d', 'macos',
                            f'--dart-define=SSH_ROLLBACK_FIXTURE={fixture}'] if args.flutter_ui else
                           ['cargo', 'test', '--manifest-path', str(ROOT / 'native/core/Cargo.toml'),
                            '--lib', 'product_ssh_failure_rollback', '--', '--ignored', '--nocapture', '--test-threads=1'])
                result = subprocess.run(command,
                    cwd=ROOT / 'example' if args.flutter_ui else ROOT,
                    env={**os.environ, 'IANVS_BOOTSTRAP_FIXTURE': str(fixture)}, stdout=log, stderr=subprocess.STDOUT,
                    timeout=600 if args.flutter_ui else 240)
            print((output / 'acceptance.log').read_text()[-10000:])
            if result.returncode:
                raise SystemExit(result.returncode)
        finally:
            for container in containers:
                subprocess.run(docker + ['rm', '-f', container], capture_output=True)
            subprocess.run(docker + ['network', 'rm', prefix], capture_output=True)


if __name__ == '__main__':
    main()
