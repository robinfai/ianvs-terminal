"""Compare output streams with real native FrameDiff, using synthetic workloads.

Requires python protobuf, protoc, libzstd, and a built native/core release library.
Run from repository root:
  python3 tools/recording_bench/scenario-storage-benchmark.py
Default output: build/recording_bench/scenarios/
No live shell is launched. Timelines run faster than real time in replay sessions.
Frame correctness is checked against a second native session's forced snapshots.
"""
import argparse
import base64
import ctypes as c
import ctypes.util
import hashlib
import json
import platform
import random
import re
import struct
import subprocess
import sys
from pathlib import Path

from google.protobuf import descriptor_pb2, descriptor_pool, message_factory

ROOT = Path(__file__).resolve().parents[2]
DURATION_US = 60_000_000
COLS, ROWS = 120, 40


def jbytes(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()


def clone(message):
    result = type(message)()
    result.CopyFrom(message)
    return result


def bind(lib, name, args, result):
    fn = getattr(lib, name)
    fn.argtypes, fn.restype = args, result
    return fn


class Zstd:
    def __init__(self):
        lib = c.CDLL(ctypes.util.find_library("zstd") or "/opt/homebrew/lib/libzstd.dylib")
        self.bound = bind(lib, "ZSTD_compressBound", [c.c_size_t], c.c_size_t)
        self.compress = bind(lib, "ZSTD_compress", [c.c_void_p, c.c_size_t, c.c_void_p, c.c_size_t, c.c_int], c.c_size_t)
        self.decompress = bind(lib, "ZSTD_decompress", [c.c_void_p, c.c_size_t, c.c_void_p, c.c_size_t], c.c_size_t)
        self.error = bind(lib, "ZSTD_isError", [c.c_size_t], c.c_uint)
        self.version = bind(lib, "ZSTD_versionString", [], c.c_char_p)().decode()

    def pack(self, raw):
        dst = c.create_string_buffer(self.bound(len(raw)))
        size = self.compress(dst, len(dst), raw, len(raw), 3)
        assert not self.error(size)
        encoded = dst.raw[:size]
        restored = c.create_string_buffer(len(raw))
        n = self.decompress(restored, len(raw), encoded, len(encoded))
        assert not self.error(n) and restored.raw[:n] == raw
        return encoded


class Engine:
    def __init__(self, path, packet_type, scrollback):
        lib = c.CDLL(str(path))
        self.packet_type = packet_type
        self.create = bind(lib, "ianvs_replay_session_create_v1", [c.c_char_p], c.c_uint64)
        self.feed = bind(lib, "ianvs_replay_session_output", [c.c_uint64, c.c_char_p, c.c_size_t], c.c_int)
        self.resize = bind(lib, "ianvs_session_resize_with_cell_size", [c.c_uint64] + [c.c_uint16] * 6, c.c_int)
        self.take = bind(lib, "ianvs_session_take_frame_packet_v1_protobuf", [c.c_uint64, c.c_uint64, c.c_uint8, c.POINTER(c.c_size_t)], c.c_void_p)
        self.free = bind(lib, "ianvs_bytes_free", [c.c_void_p, c.c_size_t], None)
        self.close = bind(lib, "ianvs_session_close", [c.c_uint64], c.c_int)
        self.config = json.loads((ROOT / "native/core/tests/fixtures/session_config/session_config_v1_shape_corpus.json").read_text())["valid_local"]
        self.config["config"]["terminal"]["scrollbackLines"] = scrollback

    def session(self):
        sid = self.create(jbytes(self.config))
        assert sid and self.resize(sid, COLS, ROWS, 960, 800, 8, 20) == 0
        return sid

    def read(self, sid, seq, force=False):
        n = c.c_size_t()
        ptr = self.take(sid, (2**64 - 1) if force else (seq or 0), int(force or seq is not None), c.byref(n))
        if not ptr:
            return None
        data = c.string_at(ptr, n.value)
        self.free(ptr, n.value)
        return self.packet_type.FromString(data)


class State:
    def __init__(self):
        self.rows, self.meta = {}, None

    def apply(self, frame):
        if frame.frame_kind == 1:
            self.rows = {}
        elif frame.viewport_row_shift:
            shifted = {}
            for i, row in self.rows.items():
                nxt = i + frame.viewport_row_shift
                if 0 <= nxt < frame.viewport_rows:
                    item = clone(row)
                    item.index = nxt
                    shifted[nxt] = item
            self.rows = shifted
        for row in frame.rows:
            self.rows[row.index] = clone(row)
        self.meta = clone(frame)
        for field in ("rows", "frame_kind", "dirty_ranges", "viewport_row_shift"):
            self.meta.ClearField(field)

    def snapshot(self):
        result = clone(self.meta)
        result.frame_kind = 1
        result.rows.extend(self.rows[i] for i in sorted(self.rows))
        return result

    def visible(self):
        # Compare text, wrap, style, cursor, terminal modes, palette etc.
        # Physical source-row and modification-time bookkeeping is not a pixel.
        result = self.snapshot()
        for row in result.rows:
            for field in ("modified_at_micros", "source_row", "source_end_row"):
                row.ClearField(field)
        return result.SerializeToString(deterministic=True)


def scenarios():
    rng = random.Random(20260916)
    def timeline(hz, fn):
        return [(round((i + 1) * 1_000_000 / hz), fn(i).encode()) for i in range(60 * hz)]
    yield "idle", "静止终端", [(0, b"$ ready\r\n")]
    typed = []
    for i in range(20):
        start = i * 3_000_000
        command = f"echo task-{i:02}"
        typed.append((start, b"$ "))
        for k, ch in enumerate(command):
            typed.append((start + (k + 1) * 80_000, ch.encode()))
        typed.append((start + 1_500_000, f"\r\ntask-{i:02}\r\n".encode()))
    yield "typing", "低频命令输入", typed
    def logline(i):
        return f"2026-09-16T10:{i // 60 % 60:02}:{i % 60:02} INFO id={rng.getrandbits(64):016x} route=/items/{i % 83} status=200 latency={i % 97}ms\r\n"
    yield "append_logs", "追加日志 20 行/秒", timeline(20, logline)
    setup = b"\x1b[?1049h\x1b[2J\x1b[?25l"
    yield "precise_updates", "精确局部刷新 60 次/秒", [(0, setup)] + timeline(60, lambda i: f"\x1b[5;65H{i % 10000:04}")
    stable_rows = [f"worker {r:02} " + "stable-value " * 6 for r in range(32)]
    def repaint(i, clear=False):
        rows = list(stable_rows)
        rows[4] = f"worker 04 progress {i % 10000:04} " + "stable-value " * 5
        return "\x1b[?2026h" + ("\x1b[2J" if clear else "") + "".join(
            f"\x1b[{r+1};1H\x1b[32m{value}\x1b[0m" for r, value in enumerate(rows)) + "\x1b[1;1H\x1b[?2026l"
    yield "redundant_redraw", "整屏重复重绘 30 次/秒", [(0, setup)] + timeline(30, repaint)
    yield "clear_redraw", "清屏后重复重绘 30 次/秒", [(0, setup)] + timeline(30, lambda i: repaint(i, True))
    alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    def random_screen(i):
        return "\x1b[?2026h" + "".join(f"\x1b[{r+1};1H" + "".join(rng.choices(alphabet, k=96)) for r in range(32)) + "\x1b[1;1H\x1b[?2026l"
    yield "novel_screen", "整屏新内容 10 次/秒", [(0, setup)] + timeline(10, random_screen)
    yield "spinner", "进度覆盖 200 次/秒", [(0, setup)] + timeline(200, lambda i: f"\x1b[5;1Hstep={i:05} {('|','/','-','\\')[i % 4]}")
    yield "scroll_burst", "滚动日志 500 行/秒", timeline(50, lambda i: "".join(logline(i * 10 + j) for j in range(10)))


def output_records(events):
    cast = [(0, jbytes({"version": 3, "term": {"cols": COLS, "rows": ROWS, "type": "xterm-256color"}, "timestamp": 1789516800}) + b"\n")]
    ndjson = [(0, jbytes({"record_type": "metadata", "schema_version": 1, "session_id": "1", "created_at_utc": "2026-09-16T00:00:00.000Z", "input_policy": "redact"}) + b"\n")]
    def event(seq, t, kind, payload):
        return jbytes({"record_type": "event", "schema_version": 1, "session_id": "1", "sequence": seq,
                       "monotonic_offset_micros": t, "event_kind": kind, "payload": payload}) + b"\n"
    ndjson.append((0, event(0, 0, "session_started", {"terminal_emulation": "xterm256", "cols": COLS, "rows": ROWS})))
    previous = 0
    for seq, (t, raw) in enumerate(events, 1):
        cast.append((t, jbytes([(t - previous) / 1e6, "o", raw.decode()]) + b"\n"))
        ndjson.append((t, event(seq, t, "pty_output", {"bytes_base64": base64.b64encode(raw).decode()})))
        previous = t
    cast.append((DURATION_US, jbytes([(DURATION_US - previous) / 1e6, "x", "0"]) + b"\n"))
    ndjson.append((DURATION_US, event(len(events) + 1, DURATION_US, "session_exited", {"exit_code": 0})))
    return {"asciicast_v3": cast, "current_ndjson": ndjson}


def row_key(row):
    result = clone(row)
    result.ClearField("modified_at_micros")
    return result.SerializeToString(deterministic=True)


def capture(engine, events, hz):
    sid, reference = engine.session(), engine.session()
    state, optimized_state = State(), State()
    native_records, optimized_records = [], []
    seq, key_at, checked = None, -5_000_000, 0
    source_counts = {"snapshots": 0, "deltas": 0, "rows": 0, "null_polls": 0}
    timeline = [(0, [])]
    if hz is None:
        timeline += [(t, [raw]) for t, raw in events]
    else:
        grouped = {}
        interval = 1_000_000 // hz
        for t, raw in events:
            tick = ((t + interval - 1) // interval) * interval
            grouped.setdefault(tick, []).append(raw)
        # Idle polling never forces periodic duplicate keyframes.
        timeline += sorted(grouped.items())
    def serialize(packet, t):
        raw = packet.SerializeToString(deterministic=True)
        return struct.pack("<QI", t, len(raw)) + raw
    try:
        for t, batch in timeline:
            for raw in batch:
                assert engine.feed(sid, raw, len(raw)) == 0
                assert engine.feed(reference, raw, len(raw)) == 0
            packet = engine.read(sid, seq)
            ref = engine.read(reference, None, force=True)
            assert ref is not None and ref.frame.frame_kind == 1
            expected = State()
            expected.apply(ref.frame)
            if packet is None:
                source_counts["null_polls"] += 1
                assert state.visible() == expected.visible(), (t, "missed native update")
                continue
            seq = packet.sequence
            source_counts["snapshots" if packet.frame.frame_kind == 1 else "deltas"] += 1
            source_counts["rows"] += len(packet.frame.rows)
            packet.session_id = "1"
            packet.timestamp_micros = t
            for row in packet.frame.rows:
                row.modified_at_micros = t
            state.apply(packet.frame)
            if state.visible() != expected.visible():
                from google.protobuf.json_format import MessageToDict
                actual_dict = MessageToDict(type(packet.frame).FromString(state.visible()))
                expected_dict = MessageToDict(type(packet.frame).FromString(expected.visible()))
                differing = [i for i, (a, b) in enumerate(zip(actual_dict['rows'], expected_dict['rows'])) if a != b]
                print("MISMATCH", json.dumps({"time_us": t, "frame_kind": packet.frame.frame_kind,
                      "shift": packet.frame.viewport_row_shift, "emitted_rows": [r.index for r in packet.frame.rows],
                      "differing_row_indices": differing,
                      "actual_first_row": actual_dict['rows'][0], "expected_first_row": expected_dict['rows'][0]}), file=sys.stderr)
                raise AssertionError((t, "native delta mismatch"))
            keyframe = t - key_at >= 5_000_000
            if keyframe:
                key_at = t
            saved = clone(packet)
            if keyframe:
                saved.frame.CopyFrom(state.snapshot())
            native_records.append((t, serialize(saved, t)))
            # Proposed storage-only row equality filter, on real engine state.
            optimized = clone(packet)
            if keyframe or optimized_state.meta is None:
                optimized.frame.CopyFrom(state.snapshot())
            else:
                optimized.frame.CopyFrom(state.meta)
                optimized.frame.frame_kind = 2
                shift = packet.frame.viewport_row_shift if packet.frame.frame_kind == 2 else 0
                optimized.frame.viewport_row_shift = shift
                prior = {}
                for i, row in optimized_state.rows.items():
                    nxt = i + shift
                    if 0 <= nxt < ROWS:
                        item = clone(row)
                        item.index = nxt
                        prior[nxt] = item
                for i, row in state.rows.items():
                    if i not in prior or row_key(row) != row_key(prior[i]):
                        optimized.frame.rows.add().CopyFrom(row)
                if not optimized.frame.rows and not shift and state.meta == optimized_state.meta:
                    checked += 1
                    continue
            for row in optimized.frame.rows:
                row.ClearField("modified_at_micros")
            optimized_state.apply(optimized.frame)
            assert optimized_state.visible() == expected.visible(), (t, "optimized delta mismatch")
            optimized_records.append((t, serialize(optimized, t)))
            checked += 1
        # Final sample must match too, including sampled modes.
        assert optimized_state.visible() == state.visible()
        final_hash = hashlib.sha256(state.visible()).hexdigest()
        return native_records, optimized_records, {**source_counts, "samples_checked": checked,
                "final_visible_sha256": final_hash, "native_records": len(native_records),
                "optimized_records": len(optimized_records), "visible_snapshots_match": True}
    finally:
        assert engine.close(sid) == 0
        assert engine.close(reference) == 0


def measure(records, codec, prefix):
    raw = b"".join(value for _, value in records)
    prefix.write_bytes(raw)
    whole = codec.pack(raw)
    Path(str(prefix) + ".zst").write_bytes(whole)
    chunks, current, size, first, last = [], [], 0, 0, 0
    for t, value in records:
        if current and size + len(value) > 256 * 1024:
            chunks.append((first, last, b"".join(current)))
            current, size = [], 0
        if not current:
            first = t
        current.append(value)
        size += len(value)
        last = t
    if current:
        chunks.append((first, last, b"".join(current)))
    # Experimental common compression envelope: 32-byte header + 40-byte
    # time/offset/length directory entry per chunk, identical for every format.
    body = bytearray(struct.pack("<8sQQQ", b"RSCBEN01", len(chunks), len(raw), DURATION_US))
    directory = bytearray()
    for first, last, data in chunks:
        packed = codec.pack(data)
        directory.extend(struct.pack("<QQQQQ", first, last, len(body), len(packed), len(data)))
        body.extend(packed)
    body.extend(directory)
    Path(str(prefix) + ".blocks").write_bytes(body)
    return {"raw_bytes": len(raw), "zstd3_whole_bytes": len(whole),
            "zstd3_256KiB_indexed_bytes": len(body), "chunks": len(chunks),
            "records": len(records), "sha256": hashlib.sha256(raw).hexdigest(),
            "compression_roundtrip_equal": True}


def verify_saved_frames(path, packet_type):
    data, offset, state, records = path.read_bytes(), 0, State(), 0
    while offset < len(data):
        t, size = struct.unpack_from("<QI", data, offset)
        offset += 12
        packet = packet_type.FromString(data[offset:offset + size])
        assert packet.timestamp_micros == t
        state.apply(packet.frame)
        offset += size
        records += 1
    assert offset == len(data)
    return hashlib.sha256(state.visible()).hexdigest(), records


def varint(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def read_varint(data, offset):
    result, shift = 0, 0
    while True:
        value = data[offset]
        offset += 1
        result |= (value & 127) << shift
        if value < 128:
            return result, offset
        shift += 7
        assert shift < 70


def verify_compact_file(path, frame_type):
    data = path.read_bytes()
    assert data[:4] == b"FDS1"
    header_size = struct.unpack_from("<I", data, 4)[0]
    json.loads(data[8:8 + header_size])
    offset, t, frame, state, count = 8 + header_size, 0, frame_type(), State(), 0
    while offset < len(data):
        dt, offset = read_varint(data, offset)
        mask, offset = read_varint(data, offset)
        size, offset = read_varint(data, offset)
        delta = frame_type.FromString(data[offset:offset + size])
        offset += size
        t += dt
        assert t <= DURATION_US
        for field in frame.DESCRIPTOR.fields:
            if mask & (1 << (field.number - 1)):
                copy_field(frame, delta, field)
        state.apply(frame)
        count += 1
    assert offset == len(data)
    return hashlib.sha256(state.visible()).hexdigest(), count


def copy_field(dst, src, field):
    name = field.name
    dst.ClearField(name)
    if field.is_repeated:
        getattr(dst, name).extend(getattr(src, name))
    elif field.has_presence and not src.HasField(name):
        return
    elif field.message_type:
        getattr(dst, name).CopyFrom(getattr(src, name))
    else:
        setattr(dst, name, getattr(src, name))


def field_key(src, field):
    value = getattr(src, field.name)
    if field.is_repeated:
        return tuple(v.SerializeToString(deterministic=True) if field.message_type else v for v in value)
    if field.has_presence and not src.HasField(field.name):
        return None
    return value.SerializeToString(deterministic=True) if field.message_type else value


def compact_frames(records, packet_type):
    """Experimental disk codec: protobuf field mask + relative time.

    Removes transport envelope/static repeats; reset masks preserve zero/absent
    fields. Each keyframe includes every field so it is an independent base.
    Verifies every decoded compact record against the original visual state.
    """
    header = jbytes({"codec": "experimental-frame-fieldmask-v1", "cols": COLS, "rows": ROWS,
                     "duration_us": DURATION_US, "frame_schema": "terminal-frame-diff-v1"})
    compact = [(0, b"FDS1" + struct.pack("<I", len(header)) + header)]
    previous, restored, expected, actual, previous_t = None, None, State(), State(), 0
    transient = {"frame_kind", "rows", "dirty_ranges", "viewport_row_shift"}
    for t, data in records:
        packet = packet_type.FromString(data[12:])
        frame = packet.frame
        delta = type(frame)()
        mask = 0
        for field in frame.DESCRIPTOR.fields:
            if previous is None or frame.frame_kind == 1 or field.name in transient or field_key(frame, field) != field_key(previous, field):
                mask |= 1 << (field.number - 1)
                copy_field(delta, frame, field)
        payload = delta.SerializeToString(deterministic=True)
        compact.append((t, varint(t - previous_t) + varint(mask) + varint(len(payload)) + payload))
        decoded = type(frame).FromString(payload)
        if restored is None:
            restored = type(frame)()
        for field in frame.DESCRIPTOR.fields:
            if mask & (1 << (field.number - 1)):
                copy_field(restored, decoded, field)
        expected.apply(frame)
        actual.apply(restored)
        assert expected.visible() == actual.visible()
        previous, previous_t = clone(frame), t
    return compact


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/recording_bench/scenarios")
    parser.add_argument("--only", default="")
    parser.add_argument("--scrollback", type=int, default=40000)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    desc = args.output / "frame_diff.desc"
    subprocess.run(["protoc", "--proto_path=" + str(ROOT / "native/core/proto"), "--descriptor_set_out=" + str(desc), str(ROOT / "native/core/proto/frame_diff.proto")], check=True)
    pool = descriptor_pool.DescriptorPool()
    for descriptor in descriptor_pb2.FileDescriptorSet.FromString(desc.read_bytes()).file:
        pool.Add(descriptor)
    packet_type = message_factory.GetMessageClass(pool.FindMessageTypeByName("frame_diff.TerminalFramePacketV1"))
    library = ROOT / "native/core/target/release/libianvs_core.dylib"
    engine, codec = Engine(library, packet_type, args.scrollback), Zstd()
    report = {"platform": platform.platform(), "python": platform.python_version(), "zstd": codec.version,
              "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "native_library_sha256": hashlib.sha256(library.read_bytes()).hexdigest(),
              "duration_seconds": 60, "viewport": [COLS, ROWS], "scrollback_lines": args.scrollback, "keyframe_interval_seconds": 5,
              "scope": "synthetic UTF-8 text/ANSI workloads through actual native core; fixed viewport; no image assets; visual state only for FrameDiff",
              "samples": []}
    for name, label, events in scenarios():
        if args.only and name not in args.only.split(","):
            continue
        folder = args.output / name
        folder.mkdir(exist_ok=True)
        formats = output_records(events)
        # Validate both output representations recover every source payload/time.
        cast_lines = [json.loads(v) for _, v in formats["asciicast_v3"]][1:-1]
        times, t = [], 0
        for entry in cast_lines:
            t += round(entry[0] * 1e6)
            times.append((t, entry[2].encode()))
        assert times == events
        nd_lines = [json.loads(v) for _, v in formats["current_ndjson"]][2:-1]
        assert [(x["monotonic_offset_micros"], base64.b64decode(x["payload"]["bytes_base64"])) for x in nd_lines] == events
        checks = {}
        for hz, suffix in [(None, "every_event"), (10, "10hz")]:
            native, optimized, checks[suffix] = capture(engine, events, hz)
            formats["framediff_native_" + suffix] = native
            formats["framediff_dedup_" + suffix] = optimized
            formats["framediff_compact_" + suffix] = compact_frames(optimized, packet_type)
            if name in ("append_logs", "scroll_burst"):
                source_ids = set(re.findall(rb"id=([0-9a-f]{16})", b"".join(raw for _, raw in events)))
                retained_ids = set()
                for _, raw in native:
                    frame = packet_type.FromString(raw[12:]).frame
                    for row in frame.rows:
                        retained_ids.update(re.findall(rb"id=([0-9a-f]{16})", row.text.encode()))
                checks[suffix]["source_log_line_ids"] = len(source_ids)
                checks[suffix]["retained_log_line_ids"] = len(source_ids & retained_ids)
        measured = {}
        for kind, records in formats.items():
            path = folder / kind
            measured[kind] = measure(records, codec, path)
            if kind.startswith("framediff_") and not kind.startswith("framediff_compact_"):
                suffix = "10hz" if kind.endswith("10hz") else "every_event"
                digest, count = verify_saved_frames(path, packet_type)
                assert digest == checks[suffix]["final_visible_sha256"] and count == len(records)
            elif kind.startswith("framediff_compact_"):
                suffix = "10hz" if kind.endswith("10hz") else "every_event"
                digest, count = verify_compact_file(path, packet_type().frame.__class__)
                assert digest == checks[suffix]["final_visible_sha256"] and count + 1 == len(records)
        report["samples"].append({"name": name, "label": label, "output_events": len(events),
                                  "pty_payload_bytes": sum(len(raw) for _, raw in events),
                                  "checks": checks, "formats": measured})
        (args.output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print(name, {k: v["zstd3_256KiB_indexed_bytes"] for k, v in measured.items()}, flush=True)
    print("Verified all codec roundtrips, output event roundtrips and frame reconstructions.")


if __name__ == "__main__":
    main()
