#!/usr/bin/env python3
"""Disposable OpenSSH boundary experiments; Python standard library only."""
import argparse
import base64
import fcntl
import hashlib
import json
import os
import pty
import re
import select
import shlex
import signal
import struct
import subprocess
import tempfile
import termios
import time
from pathlib import Path

from prototype import ROOT, bash_bundle, bash_command, encode, repository_hook, streamed_install

PROMPT = b'LAB_PROMPT> '
FRAME = re.compile(rb'\x1bP(hook|lab);([0-9a-f]+)\x1b\\')


def run(argv, *, check=True, data=None, timeout=25):
    result = subprocess.run(argv, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(f'{argv[:4]} exited {result.returncode}: {result.stderr.decode(errors="replace")[-1000:]}')
    return result


def events(data):
    return [(kind.decode(), json.loads(bytes.fromhex(value.decode()))) for kind, value in FRAME.findall(data)]


def capabilities(data):
    result = set()
    for kind, event in events(data):
        if kind != 'hook':
            continue
        if event.get('shell'):
            result.add('shell_identity')
        if event.get('pwd') or event.get('cwd'):
            result.add('current_directory')
        if event.get('hook') == 'precmd':
            result.add('prompt_lifecycle')
        if event.get('hook') == 'preexec':
            result.add('command_start')
        if event.get('command'):
            result.add('command_text')
        if event.get('hook') == 'command_finished':
            result.add('command_finish')
            if isinstance(event.get('exit_code'), int):
                result.add('exit_code')
    return sorted(result)


class Terminal:
    def __init__(self, argv):
        master, slave = pty.openpty()
        self.fd = master
        def controlling_tty():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        self.process = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave,
                                        preexec_fn=controlling_tty, env={**os.environ, 'TERM': 'xterm-256color'})
        os.close(slave)
        self.data = b''
        self.closed = False

    def read_until(self, predicate, start=0, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate(self.data[start:]):
                # Let split DCS frames / prompt repaint finish before the next
                # command. A prompt substring alone is not an execution ack.
                while select.select([self.fd], [], [], .05)[0]:
                    try:
                        chunk = os.read(self.fd, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    self.data += chunk
                return self.data[start:]
            if select.select([self.fd], [], [], .1)[0]:
                try:
                    chunk = os.read(self.fd, 65536)
                except OSError:
                    chunk = b''
                if not chunk:
                    break
                self.data += chunk
        tail = FRAME.sub(b'<DCS>', self.data[start:])[-400:]
        raise AssertionError(f'PTY wait failed; process={self.process.poll()}, tail={tail!r}')

    def prompt(self, start=0):
        return self.read_until(lambda value: PROMPT in value, start)

    def send(self, command):
        start = len(self.data)
        os.write(self.fd, command.encode() + b'\r')
        return start

    def command(self, command):
        marker = f'{time.monotonic_ns():x}'
        command += "; printf '\\n__LAB_%s__\\n' " + marker
        start = self.send(command)
        return self.read_until(lambda data: ('__LAB_' + marker + '__').encode() in data, start)

    def exit7(self):
        start = self.send('/bin/sh -c "exit 7"')
        return self.read_until(lambda data: any(kind == 'hook' and item.get('hook') == 'command_finished' and item.get('exit_code') == 7 for kind, item in events(data)), start)

    def enter(self, host):
        start = self.send('ssh ' + host)
        return self.read_until(lambda data: any(kind == 'lab' and item.get('stage') == 'ready' for kind, item in events(data)), start)

    def leave(self):
        start = self.send('exit')
        return self.read_until(lambda data: any(kind == 'lab' and item.get('stage') == 'resume' for kind, item in events(data)), start)

    def close(self):
        if self.closed:
            return
        if self.process.poll() is None:
            try:
                os.write(self.fd, b'exit\r')
                deadline = time.monotonic() + 3
                while self.process.poll() is None and time.monotonic() < deadline:
                    if select.select([self.fd], [], [], .05)[0]:
                        chunk = os.read(self.fd, 65536)
                        if not chunk:
                            break
                        self.data += chunk
            except OSError:
                pass
        os.close(self.fd)
        self.closed = True
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=5)


class Sftp:
    """Minimal binary SFTP v3 client, exercising the bridge without a CLI parser."""
    def __init__(self, argv):
        self.stderr_file = tempfile.TemporaryFile()
        self.process = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.stderr_file)
        self.request_id = 0
        try:
            self.send(b'\x01' + struct.pack('>I', 3))
            reply = self.packet()
            assert reply[0] == 2, f'Expected SFTP VERSION, received {reply[:100]!r}'
            self.version = struct.unpack('>I', reply[1:5])[0]
            assert self.version == 3
        except Exception:
            self.close()
            raise

    def read(self, length):
        data = b''
        deadline = time.monotonic() + 8
        while len(data) < length:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.process.stdout], [], [], max(0, remaining))[0]:
                raise AssertionError('SFTP binary read timed out')
            chunk = os.read(self.process.stdout.fileno(), length - len(data))
            if not chunk:
                self.stderr_file.seek(0)
                raise AssertionError('SFTP stream closed: ' + self.stderr_file.read().decode(errors='replace')[-500:])
            data += chunk
        return data

    def packet(self):
        length = struct.unpack('>I', self.read(4))[0]
        assert 0 < length <= 1024 * 1024, f'Invalid SFTP packet length {length}; stdout contamination'
        return self.read(length)

    def send(self, packet):
        self.process.stdin.write(struct.pack('>I', len(packet)) + packet)
        self.process.stdin.flush()

    @staticmethod
    def string(value):
        if isinstance(value, str):
            value = value.encode()
        return struct.pack('>I', len(value)) + value

    def request(self, kind, data=b''):
        self.request_id += 1
        self.send(bytes([kind]) + struct.pack('>I', self.request_id) + data)
        response = self.packet()
        assert struct.unpack('>I', response[1:5])[0] == self.request_id
        return response[0], response[5:]

    def open(self, path, flags):
        kind, value = self.request(3, self.string(path) + struct.pack('>II', flags, 0))
        assert kind == 102, f'Expected HANDLE, received {kind}: {value[:100]!r}'
        length = struct.unpack('>I', value[:4])[0]
        return value[4:4 + length]

    def close_handle(self, handle):
        kind, value = self.request(4, self.string(handle))
        assert kind == 101 and value[:4] == b'\0\0\0\0'

    def put(self, path, value):
        handle = self.open(path, 2 | 8 | 16)
        for offset in range(0, len(value), 16384):
            kind, reply = self.request(6, self.string(handle) + struct.pack('>Q', offset) + self.string(value[offset:offset + 16384]))
            assert kind == 101 and reply[:4] == b'\0\0\0\0'
        self.close_handle(handle)

    def get(self, path):
        handle = self.open(path, 1)
        result = b''
        while True:
            kind, value = self.request(5, self.string(handle) + struct.pack('>QI', len(result), 16384))
            if kind == 101:
                assert value[:4] == struct.pack('>I', 1), f'Expected EOF: {value!r}'
                break
            assert kind == 103
            length = struct.unpack('>I', value[:4])[0]
            result += value[4:4 + length]
        self.close_handle(handle)
        return result

    def close(self):
        try:
            self.process.stdin.close()
        except BrokenPipeError:
            pass
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=3)
        self.process.stdout.close()
        self.stderr_file.close()


class Lab:
    def __init__(self, args):
        self.args = args
        self.prefix = f'ianvs-boundary-{os.getpid()}-{int(time.time())}'
        self.docker = ['docker', '--context', args.context]
        # OpenSSH appends a suffix to ControlPath; macOS has short socket limits.
        self.temp = tempfile.TemporaryDirectory(prefix='ianvs-bl-', dir='/tmp')
        self.scratch = Path(self.temp.name)
        self.nodes = {}
        self.terminals = []
        self.sftp_clients = []
        self.results = []
        self.network_created = False
        self.args.output.mkdir(parents=True, exist_ok=True)

    def docker_run(self, *args, **kwargs):
        return run(self.docker + list(args), **kwargs)

    def exec(self, node, command, *, user='lab', **kwargs):
        return self.docker_run('exec', '-u', user, self.nodes[node]['name'], '/bin/bash', '-c', command, **kwargs)

    def setup(self):
        for key in ['client', 'wrong']:
            run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(self.scratch / key)])
        (self.scratch / 'bash-hook').write_text('IANVS_SHELL_INTEGRATION=1\nIANVS_SKIP_ORIGINAL_BASHRC=1\n' + repository_hook('BASH_RCFILE'))
        self.docker_run('network', 'create', self.prefix)
        self.network_created = True
        variants = {
            'a': {'LAB_SFTP': 'no'},
            'b': {'LAB_SFTP': 'no'}, 'c': {},
            'zsh': {'LAB_SHELL': 'zsh', 'LAB_SFTP': 'no'},
            'fish': {'LAB_SHELL': 'fish', 'LAB_SFTP': 'no'},
            'preloaded': {'LAB_STARTUP': 'preloaded'},
            'stale': {'LAB_STARTUP': 'stale'},
            'debug': {'LAB_STARTUP': 'debug'},
            'switch': {'LAB_STARTUP': 'switch'},
            'force': {'LAB_FORCE': 'yes'},
            'notty': {'LAB_TTY': 'no'},
            'single': {'LAB_MAX_SESSIONS': '1'},
            'noforward': {'LAB_FORWARDING': 'no'},
            'noisy': {'LAB_STARTUP': 'noisy'},
            'tmux': {'LAB_STARTUP': 'tmux'},
            'history': {'LAB_STARTUP': 'history'},
            'readonly': {'LAB_READONLY': 'yes', 'LAB_SFTP': 'no'},
            'password': {'LAB_PASSWORD': 'yes', 'LAB_SFTP': 'no'},
            'sh': {'LAB_SHELL': 'dash', 'LAB_SFTP': 'no'},
            'nohelpers': {'LAB_STARTUP': 'nohelpers', 'LAB_SFTP': 'no'},
        }
        for role, env in variants.items():
            name = f'{self.prefix}-{role}'
            options = ['create', '--name', name, '--hostname', role, '--network', self.prefix,
                       '--network-alias', role, '--cap-add', 'SYS_PTRACE', '--label', f'ianvs.boundary-lab={self.prefix}']
            if role not in ['b', 'c']:
                options += ['-p', '127.0.0.1::22']
            for key, value in {'LAB_ROLE': role, **env}.items():
                options += ['-e', f'{key}={value}']
            options.append(self.args.image)
            self.docker_run(*options)
            self.nodes[role] = {'name': name, 'config': env}
            for filename in ['client', 'client.pub', 'wrong'] + (['bash-hook'] if role == 'preloaded' else []):
                self.docker_run('cp', str(self.scratch / filename), f'{name}:/fixture/{filename}')
            self.docker_run('start', name)
        known = []
        for role, node in self.nodes.items():
            deadline = time.monotonic() + 15
            while True:
                logs = self.docker_run('logs', node['name']).stderr
                if b'Server listening' in logs:
                    break
                if time.monotonic() >= deadline:
                    raise AssertionError(f'{role} did not start: {logs[-800:]!r}')
                time.sleep(.2)
            public = self.exec(role, 'cat /etc/ssh/ssh_host_ed25519_key.pub', user='root').stdout.decode().split()
            key = ' '.join(public[:2])
            known.append(f'{role} {key}')
            if role not in ['b', 'c']:
                port = int(self.docker_run('port', node['name'], '22/tcp').stdout.decode().strip().split(':')[-1])
                node['port'] = port
                known.append(f'[127.0.0.1]:{port} {key}')
        (self.scratch / 'known_hosts').write_text('\n'.join(known) + '\n')
        for role, node in self.nodes.items():
            self.docker_run('cp', str(self.scratch / 'known_hosts'), f'{node["name"]}:/home/lab/.ssh/known_hosts')
            self.exec(role, 'chown lab:lab /home/lab/.ssh/known_hosts', user='root')
        self.metadata = {
            'context': self.args.context,
            'image': json.loads(self.docker_run('image', 'inspect', self.args.image).stdout)[0]['Id'],
            'versions': self.exec('a', 'dpkg-query -W openssh-server openssh-client bash zsh fish tmux strace').stdout.decode(),
            'hook_source_sha256': hashlib.sha256((ROOT / 'native/core/src/pty.rs').read_bytes()).hexdigest(),
            'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'prototype_sha256': hashlib.sha256((Path(__file__).parent / 'prototype.py').read_bytes()).hexdigest(),
            'git_head': run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD']).stdout.decode().strip(),
            'nodes': {role: {'config': node['config'], 'published': 'port' in node} for role, node in self.nodes.items()},
            'scope': 'OpenSSH container experiments and prototype; not application end-to-end acceptance',
        }

    def ssh(self, role, command=None, *, tty=False, master=None, wrong=False):
        node = self.nodes[role]
        argv = ['ssh', '-F', '/dev/null', '-p', str(node['port']), '-i', str(self.scratch / ('wrong' if wrong else 'client')),
                '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                '-o', f'UserKnownHostsFile={self.scratch / "known_hosts"}', '-o', 'LogLevel=ERROR',
                '-o', 'ConnectTimeout=3', '-o', 'ConnectionAttempts=1']
        if master:
            argv += ['-o', 'ControlMaster=auto', '-o', 'ControlPersist=30', '-S', str(master)]
        else:
            argv += ['-o', 'ControlMaster=no', '-S', 'none']
        argv += ['-tt' if tty else '-T', 'lab@127.0.0.1']
        if command is not None:
            argv.append(command)
        return argv

    def terminal(self, role, command=None, **kwargs):
        terminal = Terminal(self.ssh(role, command, tty=True, **kwargs))
        self.terminals.append(terminal)
        return terminal

    def sftp(self, argv):
        client = Sftp(argv)
        self.sftp_clients.append(client)
        return client

    def case(self, name, expected, fn):
        start = time.monotonic()
        print(f'RUN {name}: {expected}', flush=True)
        try:
            evidence = fn() or {}
            result = {'id': name, 'passed': True, 'expected': expected, 'evidence': evidence}
        except Exception as error:
            result = {'id': name, 'passed': False, 'expected': expected, 'error': str(error)}
            if self.terminals:
                (self.args.output / f'failed-{name}.pty').write_bytes(self.terminals[-1].data)
        result['seconds'] = round(time.monotonic() - start, 3)
        self.results.append(result)
        print(('PASS ' if result['passed'] else 'FAIL ') + name + (': ' + result['error'] if not result['passed'] else ''), flush=True)
        self.write_results()

    def write_results(self):
        (self.args.output / 'results.json').write_text(json.dumps({'metadata': getattr(self, 'metadata', {}), 'cases': self.results}, indent=2, ensure_ascii=False) + '\n')

    def cleanup(self):
        for client in self.sftp_clients:
            if client.process.poll() is None:
                client.close()
        for terminal in self.terminals:
            terminal.close()
        for socket in self.scratch.glob('*master'):
            run(['ssh', '-F', '/dev/null', '-S', str(socket), '-O', 'exit', 'lab@127.0.0.1'], check=False)
        for role, node in self.nodes.items():
            log = self.docker_run('logs', node['name'], check=False)
            (self.args.output / f'sshd-{role}.log').write_bytes(log.stdout + log.stderr)
            self.docker_run('rm', '-f', node['name'], check=False)
        if self.network_created:
            self.docker_run('network', 'rm', self.prefix, check=False)
        self.temp.cleanup()


def assert_all_hooks(data):
    active = capabilities(data)
    assert len(active) == 7, active
    done = [event for kind, event in events(data) if kind == 'hook' and event.get('hook') == 'command_finished']
    assert any(event.get('exit_code') == 7 for event in done), done[-3:]
    return {'capabilities': active, 'exit_code_7_observed': True}


def remote_ssh(host, socket, *, command=None, subsystem=False, master=False):
    argv = ['ssh', '-F', '/dev/null', '-T', '-S', socket,
            '-i', '/home/lab/.ssh/id_ed25519' if master else '/home/lab/.ssh/wrong',
            '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
            '-o', 'UserKnownHostsFile=/home/lab/.ssh/known_hosts', '-o', 'LogLevel=ERROR',
            '-o', 'ConnectTimeout=3', '-o', 'ConnectionAttempts=1']
    if master:
        argv += ['-M', '-N', '-f', '-o', 'ControlPersist=60']
    else:
        argv += ['-o', 'ControlMaster=no']
    if subsystem:
        argv.append('-s')
    argv.append('lab@' + host)
    if command is not None:
        argv.append(command)
    return shlex.join(argv)


def subsystem_argv(lab, host, **kwargs):
    argv = lab.ssh(host, **kwargs)
    argv.insert(len(argv) - 1, '-s')
    return argv + ['sftp']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--context', default='colima')
    parser.add_argument('--image', default='ianvs-ssh-boundary-lab:20260912')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/reviews/ssh-boundary-lab-20260912')
    args = parser.parse_args()
    lab = Lab(args)
    try:
        lab.setup()
        run_cases(lab)
    finally:
        lab.cleanup()
        lab.write_results()
    failed = [case['id'] for case in lab.results if not case['passed']]
    print(f'{len(lab.results) - len(failed)}/{len(lab.results)} expectations satisfied; failed={failed}', flush=True)
    return 1 if failed else 0


def run_cases(lab):
    # Added below: each expected limitation is an assertion, not a skipped test.
    def bash_memory():
        term = lab.terminal('a', bash_command(False))
        initial = term.prompt()
        first_prompt = initial.index(PROMPT)
        ready = next(match for match in FRAME.finditer(initial) if match[1] == b'lab')
        assert ready.start() < first_prompt
        term.command('cd ~/work')
        term.exit7()
        proof = assert_all_hooks(term.data)
        term.close()
        return {**proof, 'ready_before_first_prompt': True, 'sftp_configured': False, 'controlmaster': False}
    lab.case('bash-memory-nosftp-nomaster', 'Seven hook capabilities with no SFTP and no ControlMaster', bash_memory)

    for shell in ['zsh', 'fish']:
        def install(shell=shell):
            term = lab.terminal(shell)
            internal = term.prompt()
            assert not capabilities(internal)
            begin = term.send(streamed_install(shell))
            installed = term.read_until(lambda data: any(kind == 'lab' for kind, _ in events(data)) and PROMPT in data, begin)
            term.command('cd ~/work')
            term.exit7()
            proof = assert_all_hooks(term.data)
            term.close()
            return {**proof, 'initial_prompt_buffered': True, 'ready_received': any(kind == 'lab' for kind, _ in events(installed)), 'fixture_prompt_detection_only': True}
        lab.case(f'{shell}-memory-nosftp', 'Install repository hook into final interactive shell without SFTP', install)

    for role, expected in [('preloaded', True), ('stale', False)]:
        def check(role=role, expected=expected):
            term = lab.terminal(role, bash_command(False))
            initial = term.prompt()
            ready = next(event for kind, event in events(initial) if kind == 'lab' and event.get('stage') == 'ready')
            assert ready['registered'] is expected, ready
            if expected:
                term.exit7()
                assert ready['source'] == 'reused'
                proof = assert_all_hooks(term.data)
                completions = [event for kind, event in events(term.data) if kind == 'hook' and event.get('exit_code') == 7 and event.get('hook') == 'command_finished']
                assert len(completions) == 1, completions
            else:
                proof = {'capabilities': capabilities(term.data)}
                assert not proof['capabilities']
            term.close()
            return {**proof, 'registration': ready}
        lab.case(f'bootstrap-{role}', 'Reuse real hooks; stale sentinel / existing DEBUG trap must not report activation', check)

    def nested():
        term = lab.terminal('a', bash_command(True))
        term.prompt()
        term.exit7()
        term.enter('b')
        term.exit7()
        term.enter('c')
        term.command('cd ~/work')
        term.exit7()
        term.leave()
        term.leave()
        controls = [event for kind, event in events(term.data) if kind == 'lab']
        ready = [event for event in controls if event.get('stage') == 'ready']
        assert [item['context_id'].split(':')[0] for item in ready] == ['a', 'b', 'c'], ready
        assert ready[1]['parent'] == ready[0]['context_id'] and ready[2]['parent'] == ready[1]['context_id']
        resume = [item['context_id'].split(':')[0] for item in controls if item.get('stage') == 'resume']
        assert resume == ['b', 'a'], resume
        states = {}
        for item in ready:
            # Decode attribution rather than relying on terminal session ID.
            selected = b''.join(match[0] for match in FRAME.finditer(term.data) if json.loads(bytes.fromhex(match[2].decode())).get('context_id') == item['context_id'])
            states[item['context_id']] = capabilities(selected)
            assert len(states[item['context_id']]) == 7, states
        term.close()
        return {'ready_contexts': ready, 'resumed_hosts': resume, 'independent_capabilities': states, 'bundle_bytes': len(bash_bundle(True))}
    lab.case('nested-a-b-c-return', 'Three real interactive shells and correct parent restoration', nested)

    def isolation():
        term = lab.terminal('a', bash_command(True))
        term.prompt()
        term.exit7()
        parent_events = term.data
        child = term.enter('stale')
        ready = next(item for kind, item in events(child) if kind == 'lab' and item.get('stage') == 'ready')
        assert ready['registered'] is False
        term.command('true')
        child_events = [(kind, item) for kind, item in events(term.data[len(parent_events):]) if item.get('context_id') == ready['context_id']]
        assert not any(kind == 'hook' for kind, item in child_events)
        term.leave()
        term.exit7()
        term.close()
        return {'parent_capabilities': capabilities(parent_events), 'child_capabilities': [], 'parent_restored': True,
                'current_app_flat_state_would_retain_parent': True}
    lab.case('nested-unhooked-child-isolation', 'Child failure must not inherit parent activation', isolation)

    def debug_conflict():
        term = lab.terminal('debug', bash_command(False))
        initial = term.prompt()
        ready = next(item for kind, item in events(initial) if kind == 'lab' and item.get('stage') == 'ready')
        observed = term.command("trap -p DEBUG")
        assert b'__ianvs_preexec' in observed, observed[-500:]
        assert ready['registered'] is True
        term.exit7()
        term.close()
        return {'existing_debug_trap': "trap ':' DEBUG", 'after': "trap '__ianvs_preexec' DEBUG", 'limitation': 'Repository installer overwrites an existing DEBUG trap in this scenario'}
    lab.case('existing-debug-trap-conflict', 'Expose DEBUG trap coexistence limitation in repository installer', debug_conflict)

    def bypass():
        term = lab.terminal('a', bash_command(False))
        term.prompt()
        data = term.command("command ssh c 'cat /home/lab/role.txt'")
        assert b'c\r\n' in data
        assert not any(kind == 'lab' and item.get('stage') in ['enter', 'ready'] for kind, item in events(data))
        explicit = term.command("ssh c 'printf \"%s\\n\" \"argument with spaces\"'")
        assert b'argument with spaces\r\n' in explicit
        assert not any(kind == 'lab' for kind, item in events(explicit))
        term.close()
        return {'command_ssh_bypasses_wrapper': True, 'explicit_remote_command_preserved': True, 'automatic_child_detection': False}
    lab.case('wrapper-bypass-and-argv', 'Bypass is observable limitation; noninteractive argv stays unchanged', bypass)

    def failed_hop():
        term = lab.terminal('a', bash_command(False))
        term.prompt()
        start = term.send('ssh nonexistent-boundary-host')
        data = term.read_until(lambda value: any(kind == 'lab' and item.get('stage') == 'resume' for kind, item in events(value)), start)
        resume = next(item for kind, item in events(data) if kind == 'lab' and item.get('stage') == 'resume')
        assert resume['exit_code'] == 255
        assert not any(kind == 'lab' and item.get('stage') == 'ready' for kind, item in events(data))
        term.close()
        return {'parent_restored': True, 'ssh_exit_code': 255, 'child_ready': False}
    lab.case('failed-hop-restores-parent', 'Failed connection cannot create an active child', failed_hop)

    def no_sftp():
        try:
            lab.sftp(subsystem_argv(lab, 'a'))
        except AssertionError as error:
            assert 'closed' in str(error)
            result = run(lab.ssh('a', "printf 'SHELL_STILL_WORKS'"))
            assert result.stdout == b'SHELL_STILL_WORKS'
            return {'sftp_rejected': True, 'shell_still_works': True}
        raise AssertionError('SFTP unexpectedly available on no-SFTP host')
    lab.case('sftp-disabled-independent', 'Missing SFTP does not disable shell access', no_sftp)

    # The two masters reside on different machines. Every passenger below has
    # ONLY a deliberately unauthorized identity; success proves actual reuse.
    lab.exec('a', remote_ssh('b', '/home/lab/.ssh/to-b', master=True))
    lab.exec('b', remote_ssh('c', '/home/lab/.ssh/to-c', master=True))

    def bridge_command():
        return remote_ssh('b', '/home/lab/.ssh/to-b', command=remote_ssh('c', '/home/lab/.ssh/to-c', command='sftp', subsystem=True))

    def binary_bridge():
        direct = lab.exec('b', remote_ssh('c', '/home/lab/.ssh/absent', command='true'), check=False)
        assert direct.returncode == 255 and b'Permission denied' in direct.stderr
        client = lab.sftp(lab.ssh('a', bridge_command()))
        assert client.get('/home/lab/role.txt') == b'c\n'
        payload = bytes(range(256)) * 513 + b'\x00\x1bPhook;not-an-event\x1b\\\xffEND'
        client.put('/home/lab/work/roundtrip.bin', payload)
        downloaded = client.get('/home/lab/work/roundtrip.bin')
        assert downloaded == payload
        assert lab.exec('b', 'test ! -e /home/lab/work/roundtrip.bin', check=False).returncode == 0
        client.close()
        return {'target': 'c', 'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest(),
                'wrong_key_without_master_exit': direct.returncode, 'wrong_key_with_master_succeeded': True,
                'intermediate_a_sftp': False, 'b_and_c_have_no_host_ports': True, 'pty_in_file_path': False}
    lab.case('multi-hop-sftp-binary-reuse', 'Binary SFTP round trip through A/B, reusing both remote masters', binary_bridge)

    def file_channel_tracks_live_terminal():
        root_socket = lab.scratch / 'root-master'
        term = lab.terminal('a', bash_command(True), master=root_socket)
        term.prompt()
        term.enter('b')
        term.enter('c')
        term.exit7()
        sockets = {}
        for origin, destination in [('a', 'b'), ('b', 'c')]:
            config = lab.exec(origin, 'ssh -G -o ControlPath=/home/lab/.ssh/cm-%C ' + destination).stdout.decode()
            sockets[origin] = next(line.split(' ', 1)[1] for line in config.splitlines() if line.startswith('controlpath '))
        def auth_counts():
            return {role: lab.docker_run('logs', lab.nodes[role]['name']).stderr.count(b'Accepted publickey for') for role in ['a', 'b', 'c']}
        before = auth_counts()
        route = remote_ssh('b', sockets['a'], command=remote_ssh('c', sockets['b'], command='sftp', subsystem=True))
        client = lab.sftp(lab.ssh('a', route, master=root_socket, wrong=True))
        assert client.get('/home/lab/role.txt') == b'c\n'
        after = auth_counts()
        assert after == before, (before, after)
        path = '/home/lab/work/pinned-transfer.bin'
        handle = client.open(path, 2 | 8 | 16)
        first, second = bytes(range(256)) * 128, b'AFTER_RETURN_TO_B\x00\xff' * 1024
        kind, reply = client.request(6, client.string(handle) + struct.pack('>Q', 0) + client.string(first))
        assert kind == 101 and reply[:4] == b'\0\0\0\0'
        resumed = term.leave()
        assert any(kind == 'lab' and item.get('stage') == 'resume' and item['context_id'].startswith('b:') for kind, item in events(resumed))
        kind, reply = client.request(6, client.string(handle) + struct.pack('>Q', len(first)) + client.string(second))
        assert kind == 101 and reply[:4] == b'\0\0\0\0'
        client.close_handle(handle)
        assert client.get(path) == first + second
        assert client.get('/home/lab/role.txt') == b'c\n'
        assert lab.exec('b', 'test ! -e ' + path, check=False).returncode == 0
        client.close()
        term.leave()
        term.close()
        return {'all_three_original_connections_reused': True, 'authentication_counts_before': before,
                'authentication_counts_after': after, 'active_terminal_after_exit': 'b', 'ongoing_transfer_target': 'c',
                'bytes': len(first + second), 'sha256': hashlib.sha256(first + second).hexdigest(),
                'existing_app_panel_not_involved': True}
    lab.case('live-terminal-sftp-reuse-and-pinning', 'Reuse the actual three terminal connections and keep a transfer on C after return to B', file_channel_tracks_live_terminal)

    def no_intermediate_sftp():
        rejected = False
        try:
            lab.sftp(lab.ssh('a', remote_ssh('b', '/home/lab/.ssh/to-b', command='sftp', subsystem=True)))
        except AssertionError:
            rejected = True
        assert rejected, 'B must reject its own SFTP subsystem'
        client = lab.sftp(lab.ssh('a', bridge_command()))
        assert client.get('/home/lab/role.txt') == b'c\n'
        client.close()
        return {'a_sftp': False, 'b_sftp': False, 'b_subsystem_rejected': True, 'c_sftp': True, 'bridge_still_works': True}
    lab.case('both-intermediates-without-sftp', 'Only the final target needs SFTP', no_intermediate_sftp)

    def no_forwarding_needed():
        lab.exec('noforward', remote_ssh('c', '/home/lab/.ssh/to-c', master=True))
        command = remote_ssh('c', '/home/lab/.ssh/to-c', command='sftp', subsystem=True)
        client = lab.sftp(lab.ssh('noforward', command))
        assert client.get('/home/lab/role.txt') == b'c\n'
        client.close()
        return {'AllowTcpForwarding': 'no', 'exec_relay_works': True}
    lab.case('exec-relay-with-forwarding-disabled', 'Exec-based SFTP bridge does not require TCP forwarding permission', no_forwarding_needed)

    def no_tty():
        result = run(lab.ssh('notty', 'true', tty=True), check=False)
        assert result.returncode != 0 and b'PTY allocation request failed' in result.stderr
        client = lab.sftp(subsystem_argv(lab, 'notty'))
        assert client.get('/home/lab/role.txt') == b'notty\n'
        client.close()
        return {'pty_rejected': True, 'sftp_available': True}
    lab.case('no-pty-sftp-available', 'PTY permission and SFTP support are independent', no_tty)

    def single_channel():
        socket = lab.scratch / 'single-master'
        term = lab.terminal('single', bash_command(False), master=socket)
        term.prompt()
        try:
            lab.sftp(subsystem_argv(lab, 'single', master=socket, wrong=True))
        except AssertionError as error:
            message = str(error)
            assert 'closed' in message
            term.exit7()
            term.close()
            return {'MaxSessions': 1, 'extra_sftp_channel_rejected': True, 'existing_shell_alive': True, 'error': message}
        raise AssertionError('MaxSessions=1 unexpectedly allowed another channel')
    lab.case('maxsessions-one', 'Live terminal may exhaust all channels allowed on its connection', single_channel)

    def force_command():
        result = run(lab.ssh('force', bash_command(False)), check=False)
        assert result.stdout == b'FORCE_COMMAND_ONLY\n'
        assert not events(result.stdout)
        try:
            lab.sftp(subsystem_argv(lab, 'force'))
        except AssertionError as error:
            return {'bootstrap_ignored': True, 'ready_received': False, 'sftp_error': str(error)}
        raise AssertionError('ForceCommand unexpectedly allowed SFTP')
    lab.case('forcecommand-blocks-bootstrap-and-sftp', 'Server-forced command overrides client requests', force_command)

    def noisy_relay():
        lab.exec('noisy', remote_ssh('c', '/home/lab/.ssh/to-c', master=True))
        command = remote_ssh('c', '/home/lab/.ssh/to-c', command='sftp', subsystem=True)
        try:
            lab.sftp(lab.ssh('noisy', command))
        except AssertionError as error:
            assert 'packet length' in str(error)
            return {'noninteractive_startup_stdout_corrupts_sftp': True, 'error': str(error)}
        raise AssertionError('Noisy startup unexpectedly produced a clean SFTP stream')
    lab.case('noisy-startup-corrupts-relay', 'Noninteractive shell stdout can corrupt raw SFTP framing', noisy_relay)

    def stopped_master():
        lab.exec('b', "ssh -S /home/lab/.ssh/to-c -O exit lab@c")
        try:
            lab.sftp(lab.ssh('a', bridge_command()))
        except AssertionError as error:
            assert 'Permission denied' in str(error), str(error)
            return {'bridge_unavailable': True, 'fresh_auth_not_silently_satisfied': True, 'error': str(error)}
        raise AssertionError('Bridge succeeded after its master exited despite unauthorized key')
    lab.case('master-exit-no-silent-reconnect', 'Expired master breaks reuse and cannot masquerade as a healthy file channel', stopped_master)

    def readonly_bootstrap():
        assert lab.exec('readonly', 'touch /tmp/forbidden', check=False).returncode != 0
        assert lab.exec('readonly', 'touch ~/forbidden', check=False).returncode != 0
        term = lab.terminal('readonly', bash_command(False))
        term.prompt()
        term.exit7()
        proof = assert_all_hooks(term.data)
        term.close()
        return {**proof, 'home_and_tmp_writable': False, 'bootstrap_transport': 'pipe and /dev/fd', 'sftp': False}
    lab.case('readonly-home-tmp-bootstrap', 'Memory bootstrap succeeds when home and /tmp cannot accept files', readonly_bootstrap)

    def history_leak():
        term = lab.terminal('history')
        term.prompt()
        begin = term.send(streamed_install('bash'))
        term.read_until(lambda data: any(kind == 'lab' for kind, item in events(data)), begin)
        term.exit7()
        term.close()
        history = lab.exec('history', 'cat ~/.bash_history').stdout
        assert b'eval' in history and b'base64 -d' in history
        return {'leading_space_protects_without_ignorespace': False, 'injection_saved_in_history': True,
                'limitation': 'Blind PTY eval is not a general no-persistence solution'}
    lab.case('stdin-injection-history-leak', 'A leading space alone does not guarantee no script persistence', history_leak)

    def shell_switch():
        term = lab.terminal('switch', bash_command(False))
        before = term.prompt()
        assert not any(kind == 'lab' for kind, item in events(before))
        proof = term.command('printf "FISH_VERSION=%s\\n" $version')
        assert re.search(rb'FISH_VERSION=\d', proof)
        start = term.send(streamed_install('fish'))
        term.read_until(lambda data: any(kind == 'lab' for kind, item in events(data)), start)
        term.exit7()
        activated = assert_all_hooks(term.data)
        term.close()
        return {**activated, 'login_shell': 'bash', 'final_shell': 'fish', 'original_bash_bootstrap_ready': False,
                'recovered_using_final_shell_adapter': True}
    lab.case('startup-exec-changes-final-shell', 'Configured login shell is not reliable final-shell identification', shell_switch)

    def password_gate():
        argv = lab.ssh('password', bash_command(False), tty=True, wrong=True)
        argv[argv.index('BatchMode=yes')] = 'BatchMode=no'
        term = Terminal(argv)
        lab.terminals.append(term)
        auth = term.read_until(lambda data: b'password:' in data)
        assert not events(auth)
        begin = term.send('fixture-boundary-password')
        ready = term.read_until(lambda data: any(kind == 'lab' and item.get('stage') == 'ready' for kind, item in events(data)), begin)
        assert PROMPT in ready
        term.exit7()
        term.close()
        return {'password_prompt_before_hook_check': True, 'hook_ready_after_auth': True, 'auth_ui_must_remain_visible': True}
    lab.case('password-before-readiness', 'Authentication must be interactive before hook ready gating', password_gate)

    def long_socket():
        argv = lab.ssh('a', 'true', master=lab.scratch / ('m' * 120))
        failed = run(argv, check=False)
        assert failed.returncode != 0 and b'too long' in failed.stderr, (failed.returncode, failed.stderr)
        return {'overlong_ControlPath_rejected': True, 'error': failed.stderr.decode().strip()}
    lab.case('controlpath-length-limit', 'ControlPath must leave room for the OpenSSH temporary suffix', long_socket)

    def exec_bypass():
        term = lab.terminal('a', bash_command(False))
        term.prompt()
        begin = term.send('exec /usr/bin/ssh -tt c')
        child = term.prompt(begin)
        assert not any(kind == 'lab' for kind, item in events(child))
        assert not any(kind == 'hook' and item.get('shell') == 'bash' and item.get('hook') == 'precmd' for kind, item in events(child))
        term.close()
        return {'child_interactive': True, 'child_handshake': False, 'parent_wrapper_resume': False}
    lab.case('exec-ssh-bypasses-context-tracking', 'Process replacement bypasses wrapper and has no parent return event', exec_bypass)

    def tmux_passthrough():
        term = lab.terminal('tmux')
        term.prompt()
        marker = '{"stage":"tmux-probe"}'.encode().hex()
        plain = term.command("printf '\\033Plab;" + marker + "\\033\\\\'")
        assert not any(kind == 'lab' for kind, item in events(plain))
        term.command('tmux set-option -g allow-passthrough on')
        wrapped = term.command("printf '\\033Ptmux;\\033\\033Plab;" + marker + "\\033\\033\\\\\\033\\\\'")
        assert any(kind == 'lab' and item.get('stage') == 'tmux-probe' for kind, item in events(wrapped)), wrapped[-500:]
        term.close()
        return {'bare_dcs_received': False, 'tmux_wrapped_dcs_received': True, 'explicit_passthrough_needed': True}
    lab.case('tmux-dcs-filtering', 'Plain hook DCS needs explicit tmux passthrough handling', tmux_passthrough)

    def no_script_files():
        proof = {}
        scan = r'''
import json, pathlib, re
home=pathlib.Path('/home/lab')
payload=[]
for base in [home, pathlib.Path('/tmp')]:
    for path in base.rglob('*'):
        if path.is_file() and not path.is_symlink() and '.ssh' not in path.parts:
            try:
                value=path.read_bytes()
            except OSError:
                continue
            if b'__ianvs_install_shell_hooks' in value or b'base64 -d' in value:
                payload.append(str(path))
creates=set()
for path in pathlib.Path('/run').glob('sshd.trace.*'):
    for line in path.read_text(errors='replace').splitlines():
        if 'O_CREAT' in line:
            match=re.search(r'"(/[^"\\]+)"',line)
            if match and (match[1].startswith('/tmp/') or match[1].startswith('/home/lab/')):
                creates.add(match[1])
print(json.dumps({'payload_files':payload,'created_paths':sorted(creates)}))
'''
        for role in ['a', 'zsh', 'fish', 'readonly']:
            data = json.loads(lab.exec(role, 'python3 -c ' + shlex.quote(scan), user='root').stdout)
            assert not data['payload_files'], (role, data)
            assert not any(path.startswith('/tmp/') for path in data['created_paths']), (role, data)
            proof[role] = data
        return {'scan': proof, 'scope': 'Injector script persistence; shell history/cache and sshd audit writes are separate'}
    lab.case('script-persistence-and-file-syscalls', 'Check on-disk payload content and transient /tmp creation via strace', no_script_files)

    def sh_fallback():
        term = lab.terminal('sh', "export PS1='LAB_PROMPT> '; exec /bin/sh -i")
        term.prompt()
        source = encode(repository_hook('SH_INIT'))
        term.command(' IANVS_SHELL_INTEGRATION=1; eval "$(printf %s ' + source + ' | base64 -d)"')
        data = term.command('cd /home/lab/work')
        assert b'\x1b]7;file://' in data and b'/home/lab/work\x1b\\' in data
        assert not capabilities(term.data)
        term.close()
        return {'OSC7_cwd': True, 'DCS_command_lifecycle': False, 'full_bash_zsh_fish_capabilities': False}
    lab.case('posix-sh-directory-only', 'POSIX sh fallback reports directory but not full lifecycle capabilities', sh_fallback)

    def helpers_missing():
        term = lab.terminal('nohelpers')
        term.prompt()
        source = encode(repository_hook('BASH_RCFILE'))
        term.command(' IANVS_SHELL_INTEGRATION=1; IANVS_SKIP_ORIGINAL_BASHRC=1; eval "$(printf %s ' + source + ' | /usr/bin/base64 -d)"')
        term.command('/bin/true')
        assert not capabilities(term.data)
        status = term.command('printf "REGISTERED=%s\\n" "${__IANVS_SHELL_INTEGRATION_LOADED:-no}"')
        assert b'REGISTERED=no\r\n' in status
        term.close()
        return {'od_and_tr_available': False, 'hook_registered': False, 'shell_commands_work': True}
    lab.case('missing-hook-helpers', 'Unavailable od/tr must not be reported as active shell integration', helpers_missing)


if __name__ == '__main__':
    raise SystemExit(main())
