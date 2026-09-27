#!/usr/bin/env python3
"""Run isolated real-filesystem recording acceptance; preserve all evidence."""
import argparse
import datetime
import errno
import hashlib
import json
import os
from pathlib import Path
import plistlib
import select
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]

parser = argparse.ArgumentParser(description='Verify actual ENOSPC or disconnect using a new, bounded, task-owned APFS image.')
parser.add_argument('--case', choices=['full', 'disconnect'], required=True)
parser.add_argument('--output', type=Path, required=True, help='New evidence directory; must not exist')
parser.add_argument('--probe', type=Path, default=ROOT / 'native/core/target/debug/examples/sampled_recording_durability_probe')
args = parser.parse_args()
if sys.platform != 'darwin':
    parser.error('requires macOS and hdiutil')
probe = args.probe.resolve()
if not probe.is_file():
    parser.error('build the sampled_recording_durability_probe Cargo example first')
root = args.output.resolve()
root.mkdir(parents=True, exist_ok=False)
mount = root / 'mount'
mount.mkdir()
image = root / 'fixture.dmg'
report = {'case': args.case, 'output': str(root), 'passed': False,
          'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'scope': '128 MiB task-owned APFS image; production native BackgroundWriter and ContainerReader',
          'not_established': 'System or hardware power-loss durability', 'commands': []}
device = None
child = None

def save():
    (root / 'result.json').write_text(json.dumps(report, indent=2) + '\n')

def run(argv, key, timeout=60):
    report['commands'].append(argv)
    value = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    (root / (key + '.stdout')).write_bytes(value.stdout)
    (root / (key + '.stderr')).write_bytes(value.stderr)
    if value.returncode:
        raise RuntimeError(f'{key} failed {value.returncode}: {value.stderr.decode(errors="replace")}')
    return value.stdout

def attach(key):
    global device
    parsed = plistlib.loads(run(['hdiutil', 'attach', '-nobrowse', '-mountpoint', str(mount), '-plist', str(image)], key))
    mounted = [entry for entry in parsed['system-entities'] if entry.get('mount-point') == str(mount)]
    assert len(mounted) == 1, parsed
    disks = [entry['dev-entry'] for entry in parsed['system-entities']
             if entry.get('content-hint') == 'GUID_partition_scheme']
    assert len(disks) == 1, parsed
    device = disks[0]
    assert device.startswith('/dev/disk')
    report[key] = parsed

def detach(key, force=False):
    global device
    assert device and str(image).startswith(str(root) + '/')
    # The device identity originates only from attaching this unique image.
    command = ['hdiutil', 'detach', device] + (['-force'] if force else [])
    run(command, key)
    device = None

def hashes(bundle):
    return {str(p.relative_to(bundle)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in bundle.rglob('*') if p.is_file() and (p.name == 'records.bin' or 'assets' in p.parts)}

try:
    assert shutil.disk_usage(root).free >= 2 * 1024**3
    report['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    report['macos'] = subprocess.check_output(['sw_vers', '-productVersion'], text=True).strip()
    report['probe_source_sha256'] = hashlib.sha256((ROOT / 'native/core/examples/sampled_recording_durability_probe.rs').read_bytes()).hexdigest()
    report['probe_sha256'] = hashlib.sha256(probe.read_bytes()).hexdigest()
    report['core_sha256'] = hashlib.sha256((ROOT / 'native/core/target/debug/deps/libianvs_core.rlib').read_bytes()).hexdigest()
    run(['hdiutil', 'create', '-size', '128m', '-fs', 'APFS', '-volname', 'IANVS-Recording-FS-Probe', '-type', 'UDIF', '-nospotlight', str(image)], 'create')
    attach('initial_attach')
    bundle = mount / 'failure.trailrec'
    child = subprocess.Popen([str(probe), 'write', str(bundle)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if not select.select([child.stdout], [], [], 15)[0]:
        raise RuntimeError('probe did not acknowledge initial durable prefix')
    ready = child.stdout.readline()
    assert ready.startswith('READY committed_records=2'), ready
    report['ready'] = ready.strip()
    report['initial_primary_hashes'] = hashes(bundle)
    report['disk_before'] = shutil.disk_usage(mount)._asdict()
    if args.case == 'full':
        written = 0
        block = os.urandom(1024 * 1024)
        with (mount / 'owned-filler.bin').open('wb', buffering=0) as filler:
            for size in (1024 * 1024, 4096):
                while written < 128 * 1024 * 1024:
                    try:
                        written += filler.write(block[:size])
                    except OSError as exc:
                        if exc.errno != errno.ENOSPC:
                            raise
                        report['filler_errno'] = exc.errno
                        break
            try:
                os.fsync(filler.fileno())
            except OSError as exc:
                if exc.errno != errno.ENOSPC:
                    raise
        assert report.get('filler_errno') == errno.ENOSPC
        report['filler_bytes'] = written
        report['disk_full'] = shutil.disk_usage(mount)._asdict()
    else:
        detach('forced_disconnect', force=True)
    before = time.monotonic()
    stdout, stderr = child.communicate('stress\n', timeout=30)
    (root / 'writer.stdout').write_text(ready + stdout)
    (root / 'writer.stderr').write_text(stderr)
    report['writer_exit_code'] = child.returncode
    report['failure_wall_seconds'] = time.monotonic() - before
    assert child.returncode == 0, stderr
    assert 'writer_phase=Failed' in stdout and 'settled=true' in stdout and 'finish_rejected=true' in stdout
    if args.case == 'full':
        assert 'os error 28' in stdout, stdout
        before_hash = hashes(bundle)
        report['full_volume_scan'] = run([str(probe), 'scan', str(bundle)], 'full_volume_scan').decode()
        assert hashes(bundle) == before_hash
        (mount / 'owned-filler.bin').unlink()
        detach('clean_detach')
    attach('recovery_attach')
    before_hash = hashes(bundle)
    report['reopened_scan'] = run([str(probe), 'scan', str(bundle)], 'reopened_scan').decode()
    assert hashes(bundle) == before_hash
    report['final_primary_hashes'] = before_hash
    shutil.copytree(bundle, root / 'recovered.trailrec')
    report['passed'] = True
except BaseException as exc:
    report['error'] = repr(exc)
    raise
finally:
    if child and child.poll() is None:
        child.kill()
        child.communicate(timeout=5)
    if device:
        try:
            detach('cleanup_detach', force=True)
        except BaseException as exc:
            report['cleanup_error'] = repr(exc)
            report['passed'] = False
    save()
    print(json.dumps({'output': str(root), 'passed': report['passed'], 'error': report.get('error')}), flush=True)

if not report["passed"]:
    raise SystemExit(1)
