"""Record real macOS top in a PTY, then compare storage using the native core.

Capture needs permission to inspect processes on macOS. Raw process output stays
in the chosen local output directory. Analysis prints aggregate sizes only.
Default output: build/recording_bench/top/ (ignored local artifacts).
"""
import argparse
import base64
import fcntl
import hashlib
import importlib.util
import json
import os
import platform
import pty
import select
import struct
import subprocess
import termios
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def record_top(folder, seconds, interval, sort):
    folder.mkdir(parents=True, exist_ok=True)
    command = ["/usr/bin/top", "-s", str(interval), "-stats", "pid,cpu,mem,time,threads,state"]
    if sort != "default":
        command += ["-o", sort]
    # top needs a controlling terminal, not just tty-shaped file descriptors.
    # This recorder is single-threaded; child setup runs after setsid.
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 960, 800))
    env = dict(os.environ, TERM="xterm-256color", LANG="en_US.UTF-8", LC_ALL="en_US.UTF-8", COLUMNS="120", LINES="40")
    start = time.monotonic_ns()
    proc = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave,
                            env=env, start_new_session=True, close_fds=True,
                            preexec_fn=lambda: fcntl.ioctl(slave, termios.TIOCSCTTY, 0))
    os.close(slave)
    events = []
    deadline = start + round(seconds * 1e9)
    try:
        while time.monotonic_ns() < deadline:
            remaining = (deadline - time.monotonic_ns()) / 1e9
            readable, _, _ = select.select([master], [], [], max(0, min(.2, remaining)))
            if readable:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                t = (time.monotonic_ns() - start) // 1000
                if t <= seconds * 1e6:
                    events.append((t, data))
            if proc.poll() is not None:
                break
        if proc.poll() is None:
            try:
                os.write(master, b"q\n")
            except OSError:
                pass
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)
    raw = b"".join(value for _, value in events)
    capture = {"command": command, "duration_seconds": seconds, "viewport": [120, 40],
               "term": "xterm-256color", "locale": "en_US.UTF-8", "return_code": proc.returncode,
               "pty_reads": len(events), "pty_payload_bytes": len(raw),
               "sha256": hashlib.sha256(raw).hexdigest(),
               "last_output_seconds": events[-1][0] / 1e6 if events else 0,
               "events": [[t, base64.b64encode(data).decode()] for t, data in events]}
    (folder / "capture.json").write_text(json.dumps(capture, indent=2))
    (folder / "output.ansi").write_bytes(raw)
    info = {k: v for k, v in capture.items() if k != "events"}
    print(json.dumps(info), flush=True)
    return info


def analyze(folder):
    from google.protobuf import descriptor_pb2, descriptor_pool, message_factory
    spec = importlib.util.spec_from_file_location("scenario_bench", Path(__file__).with_name("scenario-storage-benchmark.py"))
    bench = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bench)
    desc = folder / "frame_diff.desc"
    subprocess.run(["protoc", "--proto_path=" + str(ROOT / "native/core/proto"),
                    "--descriptor_set_out=" + str(desc), str(ROOT / "native/core/proto/frame_diff.proto")], check=True)
    pool = descriptor_pool.DescriptorPool()
    for descriptor in descriptor_pb2.FileDescriptorSet.FromString(desc.read_bytes()).file:
        pool.Add(descriptor)
    packet_type = message_factory.GetMessageClass(pool.FindMessageTypeByName("frame_diff.TerminalFramePacketV1"))
    library = ROOT / "native/core/target/release/libianvs_core.dylib"
    engine, codec = bench.Engine(library, packet_type, 8000), bench.Zstd()
    report = {"platform": platform.platform(), "python": platform.python_version(), "zstd": codec.version,
              "native_library_sha256": hashlib.sha256(library.read_bytes()).hexdigest(),
              "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "scope": "real macOS interactive top PTY output; original output bytes preserved; refresh grouping uses 20 ms quiet gaps",
              "samples": []}
    for sample_dir in sorted(folder.iterdir()):
        source = sample_dir / "capture.json"
        if not source.is_file():
            continue
        captured = json.loads(source.read_text())
        events = [(t, base64.b64decode(raw)) for t, raw in captured["events"]]
        assert events and b"Processes:" in b"".join(raw for _, raw in events), "top did not emit a live process screen"
        assert captured['last_output_seconds'] > captured['duration_seconds'] * .8, "top stopped early"
        # Merge only adjacent reads separated by <=20 ms for complete curses
        # repaint bursts. Full source streams retain the original read events.
        bursts = []
        for t, data in events:
            if bursts and t - bursts[-1][0] <= 20_000:
                bursts[-1] = (t, bursts[-1][1] + data)
            else:
                bursts.append((t, data))
        bench.DURATION_US = round(captured['duration_seconds'] * 1e6)
        formats = bench.output_records(events)
        # Also measure equal-burst packaging of output; transport read
        # fragmentation should not be mistaken for FrameDiff compression.
        formats['asciicast_v3_bursts'] = bench.output_records(bursts)['asciicast_v3']
        checks = {}
        for hz, suffix in [(None, "every_refresh"), (10, "10hz")]:
            native, dedup, checks[suffix] = bench.capture(engine, bursts, hz)
            formats['framediff_native_' + suffix] = native
            formats['framediff_compact_' + suffix] = bench.compact_frames(dedup, packet_type)
        measured = {}
        for kind, records in formats.items():
            path = sample_dir / kind
            measured[kind] = bench.measure(records, codec, path)
            if kind.startswith('framediff_'):
                suffix = '10hz' if kind.endswith('10hz') else 'every_refresh'
                if kind.startswith('framediff_compact_'):
                    digest, count = bench.verify_compact_file(path, packet_type().frame.__class__)
                    assert count + 1 == len(records)
                else:
                    digest, count = bench.verify_saved_frames(path, packet_type)
                    assert count == len(records)
                assert digest == checks[suffix]['final_visible_sha256']
        # Byte/time roundtrips of recorded output in both event formats.
        t = 0
        restored = []
        for _, value in formats['asciicast_v3'][1:-1]:
            delta, code, data = json.loads(value)
            assert code == 'o'
            t += round(delta * 1e6)
            restored.append((t, data.encode()))
        assert restored == events
        ndjson_events = [json.loads(raw) for _, raw in formats['current_ndjson'][2:-1]]
        assert [(e['monotonic_offset_micros'], base64.b64decode(e['payload']['bytes_base64'])) for e in ndjson_events] == events
        summary = {k: v for k, v in captured.items() if k != 'events'}
        summary.update(name=sample_dir.name, refresh_bursts=len(bursts),
                       refresh_gap_ms=[round((bursts[i][0] - bursts[i-1][0]) / 1000, 3) for i in range(1, len(bursts))],
                       checks=checks, formats=measured)
        report['samples'].append(summary)
        print(sample_dir.name, {k: v['zstd3_256KiB_indexed_bytes'] for k, v in measured.items()}, flush=True)
    (folder / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['record', 'analyze'])
    parser.add_argument('--output', type=Path, default=ROOT / 'build/recording_bench/top')
    parser.add_argument('--seconds', type=float, default=60)
    parser.add_argument('--interval', default='1')
    parser.add_argument('--sort', choices=['default', 'cpu'], default='default')
    parser.add_argument('--name', default='default_1s')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.mode == 'record':
        record_top(args.output / args.name, args.seconds, args.interval, args.sort)
    else:
        analyze(args.output)


if __name__ == '__main__':
    main()
