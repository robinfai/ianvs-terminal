#!/usr/bin/env python3
"""Exercise product Rust transports against the disposable OpenSSH lab.
No prototype injection code runs in these tests. Keys, containers and network
are removed on exit; output contains test results and server logs only.
"""
import argparse
import json
import os
import subprocess
from pathlib import Path
from run import Lab, ROOT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--context', default='colima')
    parser.add_argument('--image', default='ianvs-ssh-boundary-lab:20260912')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/reviews/ssh-product-bootstrap-20260912')
    args = parser.parse_args()
    lab = Lab(args)
    try:
        print('Preparing disposable SSH product fixtures', flush=True)
        lab.setup()
        config = lab.scratch / 'config'
        config.write_text(f'''Host a
  HostName 127.0.0.1
  ControlPath {lab.scratch / 'borrowed-master'}
  Port {lab.nodes['a']['port']}
  User lab
  IdentityFile {lab.scratch / 'client'}
  UserKnownHostsFile {lab.scratch / 'known_hosts'}
  StrictHostKeyChecking yes
  IdentitiesOnly yes
  BatchMode yes
  LogLevel ERROR
''')
        subprocess.run(['ssh', '-F', str(config), '-MNf', '-o', 'ControlMaster=yes', 'a'], check=True, timeout=10)
        fixture = lab.scratch / 'product.json'
        fixture.write_text(json.dumps({'nodes': lab.nodes, 'key': str(lab.scratch / 'client'),
                                      'known_hosts': str(lab.scratch / 'known_hosts'), 'local_config': str(config),
                                      'capability_evidence': str((args.output / 'capability-evidence.json').resolve())}))
        print('Running product transport acceptance', flush=True)
        command = ['cargo', 'test', '--manifest-path', str(ROOT / 'native/core/Cargo.toml'), '--lib',
                   'product_ssh_bootstrap_acceptance', '--', '--ignored', '--nocapture', '--test-threads=1']
        process = subprocess.Popen(command, cwd=ROOT, env={**os.environ, 'IANVS_BOOTSTRAP_FIXTURE': str(fixture)},
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        with (args.output / 'product-test.log').open('w') as log:
            for line in process.stdout:
                print(line, end='', flush=True)
                log.write(line)
        status = process.wait()
        if status:
            raise RuntimeError(f'Product transport acceptance failed ({status})')
        subprocess.run(['ssh', '-F', str(config), '-O', 'check', 'a'], check=True, timeout=5)
        checks = {'borrowed_master_preserved': True}
        for node in ['a', 'b', 'c', 'zsh', 'fish', 'preloaded', 'debug', 'stale', 'history']:
            history = lab.exec(node, 'cat ~/.bash_history ~/.zsh_history ~/.local/share/fish/fish_history 2>/dev/null', check=False).stdout
            assert b'__ianvs' not in history and b'__iv_' not in history and b"eval " not in history, f'{node}: injected history persisted'
            checks[node] = {'history_has_no_injection': True}
            wrong = lab.exec(node, 'test -e /home/lab/WRONG_ENDPOINT', check=False)
            assert wrong.returncode == 1, f'{node}: stale request wrote to another endpoint'
        checks['history']['positive_control'] = b'false' in lab.exec('history', 'cat ~/.bash_history').stdout
        assert checks['history']['positive_control']
        assert lab.exec('c', 'cat /home/lab/product-write.txt').stdout == b'endpoint-c-overwrite'
        assert lab.exec('a', 'test -e /home/lab/product-write.txt', check=False).returncode == 1
        assert lab.exec('b', 'test -e /home/lab/product-write.txt', check=False).returncode == 1
        metadata = {**lab.metadata, 'scope': 'Product Rust SSH and local PTY transports, real shell injection and SFTP routing'}
        (args.output / 'results.json').write_text(json.dumps({'passed': True, 'metadata': metadata, 'checks': checks}, indent=2) + '\n')
        print('PASS product injection, nested ControlMaster/SFTP, endpoint isolation and history checks', flush=True)
    finally:
        lab.cleanup()


if __name__ == '__main__':
    main()
