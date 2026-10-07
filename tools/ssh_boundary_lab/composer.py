#!/usr/bin/env python3
"""Validate Composer over real OpenSSH with disposable keys and homes.

Requires a host sshd and Bash 4+ for the Bash case. It never changes system SSH
configuration or uses personal credentials. Everything listens on loopback.
"""
import argparse
import getpass
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import tempfile
import time

from disconnect_relay import DisconnectRelay

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bash', type=Path, required=True)
    parser.add_argument('--zsh', type=Path, default=Path('/bin/zsh'))
    parser.add_argument('--sshd', type=Path, default=Path('/usr/sbin/sshd'))
    parser.add_argument('--output', type=Path, default=ROOT / 'build/composer-ssh')
    parser.add_argument('--ui', action='store_true', help='Also validate the macOS app on Bash/emacs')
    parser.add_argument('--disconnect-ui', action='store_true', help='Also drop the app SSH transport through a disposable loopback relay')
    parser.add_argument('--bash-preexec', type=Path, help='Source a local upstream bash-preexec fixture in each Bash login')
    parser.add_argument('--history-off', action='store_true', help='Disable in-memory shell history to verify literal submission titles independently')
    args = parser.parse_args()
    if args.disconnect_ui:
        args.ui = True
    for label, executable in [('Bash', args.bash), ('zsh', args.zsh), ('sshd', args.sshd)]:
        if not executable.is_file() or not os.access(executable, os.X_OK):
            parser.error(f'{label} executable is unavailable: {executable}')
    bash_version = subprocess.run([str(args.bash), '-c', 'printf "%s" "${BASH_VERSINFO[0]}"'],
                                  check=True, capture_output=True, text=True).stdout
    if not bash_version.isdigit() or int(bash_version) < 4:
        parser.error('Composer SSH acceptance requires Bash 4+ (bind -x Readline editing).')
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'results.json').write_text(json.dumps({'passed': False, 'status': 'not_completed'}) + '\n')
    with tempfile.TemporaryDirectory(prefix='ianvs-composer-ssh-', dir='/tmp') as directory:
        scratch = Path(directory)
        for name in ('host', 'client'):
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(scratch / name)], check=True)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        host_key = ' '.join((scratch / 'host.pub').read_text().split()[:2])
        (scratch / 'known_hosts').write_text(f'[127.0.0.1]:{port} {host_key}\n')
        home = scratch / 'home'
        (home / '.ssh').mkdir(parents=True)
        (home / 'block-fixture.txt').write_text('Command Block output fixture\n')
        # -F is explicit: OpenSSH resolves ~/.ssh using passwd, not HOME.
        ssh_config = f'''Host composer-hop
  HostName 127.0.0.1
  Port {port}
  User {getpass.getuser()}
  IdentityFile {scratch}/client
  UserKnownHostsFile {scratch}/known_hosts
  StrictHostKeyChecking yes
  IdentitiesOnly yes
  BatchMode yes
  LogLevel ERROR
'''
        (home / '.ssh/config').write_text(ssh_config)
        bin_dir = scratch / 'bin'
        bin_dir.mkdir()
        (bin_dir / 'ssh').write_text(f'#!/bin/sh\nexec /usr/bin/ssh -F {shlex.quote(str(home / ".ssh/config"))} "$@"\n')
        (bin_dir / 'ssh').chmod(0o700)
        forced = scratch / 'force-command'
        config = scratch / 'sshd_config'
        config.write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {scratch}/host
PidFile {scratch}/pid
AuthorizedKeysFile {scratch}/client.pub
StrictModes no
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PermitUserEnvironment no
AllowUsers {getpass.getuser()}
ForceCommand {forced}
LogLevel ERROR
''')
        for shell, executable in [('zsh', args.zsh), ('bash', args.bash)]:
            for keymap, local in [('emacs',False), ('vi',False), ('emacs',True)]:
                name = f'{shell}-{keymap}' + ('-local-ssh' if local else '')
                print(f'OpenSSH Composer: {name}', flush=True)
                fixture_path = f'export PATH={shlex.quote(str(bin_dir))}:"$PATH"\n'
                (home / '.zshrc').write_text(fixture_path + "PROMPT='fixture> '\nRPROMPT=''\nHISTFILE=''\n" + ('bindkey -v\n' if keymap == 'vi' else 'bindkey -e\n') + ('HISTSIZE=0\nSAVEHIST=0\n' if args.history_off else ''))
                bash_preexec = '' if args.bash_preexec is None else f'source {shlex.quote(str(args.bash_preexec.resolve(strict=True)))}\n'
                (home / '.bash_profile').write_text(fixture_path + "PS1='fixture> '\nHISTFILE=''\n" + f'set -o {keymap}\n' + bash_preexec + ('set +o history\n' if args.history_off else ''))
                forced.write_text('#!/bin/sh\n' + '\n'.join(f'export {key}={shlex.quote(str(value))}' for key, value in {
                    'HOME': home, 'ZDOTDIR': home, 'SHELL': executable,
                    'PATH': f'{bin_dir}:/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL':'en_US.UTF-8',
                }.items()) + f'\ncd {shlex.quote(str(home))} || exit 1\n' + 'exec /bin/sh -c "$SSH_ORIGINAL_COMMAND"\n')
                forced.chmod(0o700)
                fixture = scratch / 'fixture.json'
                fixture.write_text(json.dumps({'shell': shell, 'home':str(home), 'local':local, 'connection': {
                    'type':'ssh', 'host':'127.0.0.1', 'port':port, 'user':getpass.getuser(),
                    'auth':'public_key', 'privateKeys':[str(scratch / 'client')],
                    'hostKeyPolicy':'strict', 'knownHostsFile':str(scratch / 'known_hosts'),
                }}))
                with (args.output / f'{name}.sshd.log').open('w') as server_log:
                    server = subprocess.Popen([str(args.sshd), '-D', '-e', '-f', str(config)], stdout=server_log, stderr=server_log)
                    try:
                        time.sleep(.15)
                        with (args.output / f'{name}.test.log').open('w') as log:
                            result = subprocess.run(['cargo', 'test', '--offline', '--manifest-path', str(ROOT / 'native/core/Cargo.toml'), '--test', 'remote_composer_ssh_test', '--', '--ignored', '--nocapture'],
                                cwd=ROOT, env={**os.environ, 'IANVS_COMPOSER_SSH_FIXTURE':str(fixture)}, stdout=log, stderr=subprocess.STDOUT, timeout=120)
                        if result.returncode:
                            print((args.output / f'{name}.test.log').read_text()[-7000:])
                            raise RuntimeError(f'{name} failed')
                        assert not (home / 'WRONG_ENDPOINT').exists()
                        if args.ui and name == 'bash-emacs':
                            relay = None
                            try:
                                if args.disconnect_ui:
                                    marker = scratch / 'disconnect.request'
                                    relay = DisconnectRelay(port, marker)
                                    with (scratch / 'known_hosts').open('a') as known:
                                        known.write(f'[127.0.0.1]:{relay.port} {host_key}\n')
                                    app_fixture = json.loads(fixture.read_text())
                                    app_fixture['connection']['port'] = relay.port
                                    app_fixture['disconnectPath'] = str(marker)
                                    fixture.write_text(json.dumps(app_fixture))
                                with (args.output / 'app.test.log').open('w') as log:
                                    result = subprocess.run(['flutter', 'test', '--no-pub', '-d', 'macos',
                                        f'--dart-define=COMPOSER_SSH_FIXTURE={fixture}',
                                        f'--dart-define=BLOCKS_NATIVE_EVIDENCE_DIR={args.output.resolve()}',
                                        'integration_test/ssh_composer_acceptance_test.dart'], cwd=ROOT / 'example',
                                        stdout=log, stderr=subprocess.STDOUT, timeout=360)
                            finally:
                                if relay is not None:
                                    relay.close()
                            if result.returncode:
                                print((args.output / 'app.test.log').read_text()[-10000:])
                                raise RuntimeError('macOS SSH Composer acceptance failed')
                        print(f'PASS {name}', flush=True)
                    finally:
                        server.terminate()
                        server.wait(timeout=10)
        (args.output / 'results.json').write_text(json.dumps({'passed':True,'appPassed':args.ui,'disconnectPassed':args.disconnect_ui,'bashPreexec':args.bash_preexec is not None,'historyOff':args.history_off,'shells':['zsh','bash'],'keymaps':['emacs','vi'],'scope':'real loopback SSH, native session API, exact compound and long command titles, cancellation provenance, consecutive command blocks, multi-hop and parent restoration; optional real transport loss retains AI task and native history'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
