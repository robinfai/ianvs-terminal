#!/usr/bin/env python3
"""Run real macOS Release recording acceptance with an owned SSH fixture.

The default is 25 actual hours. --probe is explicitly non-qualifying evidence.
The built app is copied before launch so later builds cannot replace its code.
"""
import argparse
import hashlib
import json
import os
import platform
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from run import Lab, ROOT


def utc():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--context', default='colima-ianvs-recording-acceptance')
    parser.add_argument('--image', default='ianvs-ssh-boundary-lab:20260912')
    parser.add_argument('--output', required=True, type=Path,
                        help='New, task-owned artifact directory (must not exist)')
    parser.add_argument('--seconds', type=int, default=90000)
    parser.add_argument('--probe', action='store_true')
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        parser.error('requires macOS')
    if args.seconds < 60 or (not args.probe and args.seconds <= 86400):
        parser.error('acceptance requires >86400 seconds; --probe permits >=60')
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    if shutil.disk_usage(args.output).free < 5 * 1024 ** 3:
        parser.error('at least 5 GiB of free disk required before building')
    env = dict(os.environ)
    env.pop('IANVS_CORE_LIB', None)  # Exercise the frozen embedded Release core.
    lab = Lab(args)
    child = None
    report = {'passed': False, 'probe': args.probe, 'requested_seconds': args.seconds,
              'started_utc': utc(), 'runner_pid': os.getpid(), 'output': str(args.output)}
    started = time.monotonic()

    def stop_child():
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=20)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=5)

    def interrupt(signum, _frame):
        stop_child()
        raise SystemExit(128 + signum)

    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, interrupt)

    def execute(command, log, timeout, cwd=ROOT):
        nonlocal child
        print(f'RUN {command[0]} -> {log}', flush=True)
        with (args.output / log).open('w') as stream:
            child = subprocess.Popen(command, cwd=cwd, env=env,
                                     stdout=stream, stderr=subprocess.STDOUT)
            try:
                status = child.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                stop_child()
                raise RuntimeError(f'{log} timed out after {timeout} seconds')
            if status:
                raise RuntimeError(f'{log} failed ({status}); inspect retained log')

    def checkpoint():
        (args.output / 'runner.json').write_text(json.dumps(report, indent=2) + '\n')

    try:
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        sources = ['example/integration_test/sampled_recording_soak_test.dart',
                   'tools/ssh_boundary_lab/recording_soak.py', 'tools/ssh_boundary_lab/run.py']
        report.update({'revision': revision, 'macos': platform.mac_ver()[0],
                       'architecture': platform.machine(),
                       'hardware': subprocess.check_output(
                           ['/usr/sbin/sysctl', '-n', 'hw.model', 'hw.ncpu', 'hw.memsize'], text=True).splitlines(),
                       'source_sha256': {name: digest(ROOT / name) for name in sources},
                       'tracked_diff': subprocess.check_output(['git', 'diff', 'HEAD', '--stat'], cwd=ROOT, text=True),
                       'phase': 'fixture'})
        checkpoint()
        print('Preparing isolated SSH fixture', flush=True)
        lab.setup(roles=['a', 'b', 'c'])
        report['fixture'] = {**lab.metadata, 'scope': 'Full Flutter application with product SSH transport; no prototype injection'}
        fixture = lab.scratch / 'recording.json'
        fixture.write_text(json.dumps({'nodes': lab.nodes, 'key': str(lab.scratch / 'client'),
                                       'known_hosts': str(lab.scratch / 'known_hosts')}))
        report['phase'] = 'build'
        checkpoint()
        command = ['flutter', 'build', 'macos', '--release',
                   '--target=integration_test/sampled_recording_soak_test.dart',
                   '--dart-define=IANVS_RECORDING_STANDALONE=true',
                   f'--dart-define=IANVS_RECORDING_SOAK_SECONDS={args.seconds}',
                   f'--dart-define=IANVS_RECORDING_SOAK_OUTPUT={args.output}',
                   f'--dart-define=IANVS_RECORDING_SSH_FIXTURE={fixture}',
                   f'--dart-define=IANVS_RECORDING_SOAK_REVISION={revision}']
        report['build_command'] = command
        execute(command, 'build.log', 2400, cwd=ROOT / 'example')
        source_app = ROOT / 'example/build/macos/Build/Products/Release/Trail.app'
        execute([str(ROOT / 'tools/sign_local_macos_release.sh'), str(source_app)], 'sign.log', 120)
        app = args.output / 'Trail.app'
        execute(['/usr/bin/ditto', str(source_app), str(app)], 'copy.log', 120)
        execute(['/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)], 'codesign.log', 60)
        report['binary_sha256'] = {str(path.relative_to(app)): digest(path) for path in app.rglob('*')
                                  if path.is_file() and (path.suffix == '.dylib' or path.name in ('Trail', 'App', 'ianvs_core'))}
        report['phase'] = 'running'
        report['app_started_utc'] = utc()
        checkpoint()
        timeout = args.seconds + 900
        launch = [sys.executable, str(ROOT / 'tools/run_process_group_with_timeout.py'), str(timeout),
                  str(args.output / 'stdout.log'), str(args.output / 'stderr.log'),
                  '/usr/bin/caffeinate', '-i', str(app / 'Contents/MacOS/Trail')]
        report['run_command'] = launch
        checkpoint()
        execute(launch, 'process-runner.log', timeout + 60)
        result = json.loads((args.output / 'result.json').read_text())
        if not result.get('passed') or not result.get('safe_to_terminate'):
            raise RuntimeError('application acceptance or shutdown did not pass')
        if 'IANVS_RECORDING_SOAK_RESULT=passed' not in (args.output / 'stdout.log').read_text():
            raise RuntimeError('standalone test completion marker absent')
        if not args.probe and not result.get('qualifies_long_duration'):
            raise RuntimeError('run did not qualify as >24-hour Release acceptance')
        report['passed'] = True
        report['qualifies_long_duration'] = not args.probe and result.get('qualifies_long_duration', False)
        print('PASS ' + ('short probe (not long-duration acceptance)' if args.probe else '>24-hour acceptance'), flush=True)
    except BaseException as error:
        report['error'] = f'{type(error).__name__}: {error}'
        raise
    finally:
        stop_child()
        report['phase'] = 'finished'
        report['finished_utc'] = utc()
        report['runner_elapsed_seconds'] = time.monotonic() - started
        try:
            lab.cleanup()
            report['fixture_cleanup_complete'] = True
        except Exception as error:
            report['passed'] = False
            report['fixture_cleanup_error'] = str(error)
            raise
        finally:
            checkpoint()


if __name__ == '__main__':
    main()
