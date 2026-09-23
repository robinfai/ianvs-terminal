"""Reproducible codec-only probe; synthetic data, not a product benchmark.

Run: python3 tools/recording_bench/storage-compression-benchmark.py
Default output: build/recording_bench/compression/results.json
Requires libzstd (system library); no recording files or user data are read
except the three committed contract fixtures. Timings exclude disk and parser.
"""
import argparse
import base64
import ctypes as c
import ctypes.util
import gzip
import json
import platform
import random
import statistics
import time
from pathlib import Path

lib = c.CDLL(ctypes.util.find_library("zstd") or "/opt/homebrew/lib/libzstd.dylib")
lib.ZSTD_compressBound.argtypes = [c.c_size_t]
lib.ZSTD_compressBound.restype = c.c_size_t
lib.ZSTD_compress.argtypes = [c.c_void_p, c.c_size_t, c.c_void_p, c.c_size_t, c.c_int]
lib.ZSTD_compress.restype = c.c_size_t
lib.ZSTD_decompress.argtypes = [c.c_void_p, c.c_size_t, c.c_void_p, c.c_size_t]
lib.ZSTD_decompress.restype = c.c_size_t
lib.ZSTD_isError.argtypes = [c.c_size_t]
lib.ZSTD_isError.restype = c.c_uint
lib.ZSTD_versionString.restype = c.c_char_p


def zcompress(data):
    capacity = lib.ZSTD_compressBound(len(data))
    output = c.create_string_buffer(capacity)
    size = lib.ZSTD_compress(output, capacity, data, len(data), 3)
    assert not lib.ZSTD_isError(size)
    return output.raw[:size]


def zdecompress(data, capacity):
    output = c.create_string_buffer(capacity)
    size = lib.ZSTD_decompress(output, capacity, data, len(data))
    assert not lib.ZSTD_isError(size)
    return output.raw[:size]


def timed(fn):
    fn()  # warmup
    values = []
    for _ in range(7):
        start = time.perf_counter_ns()
        result = fn()
        values.append((time.perf_counter_ns() - start) / 1e6)
    return result, round(statistics.median(values), 3)


def ndjson(payloads):
    records = [{"record_type": "metadata", "schema_version": 1,
                "session_id": "synthetic", "created_at_utc": "2026-09-16T00:00:00.000Z",
                "input_policy": "redact"}]
    for sequence, payload in enumerate([None] + payloads):
        records.append({"record_type": "event", "schema_version": 1,
                        "session_id": "synthetic", "sequence": sequence,
                        "monotonic_offset_micros": sequence * 20000,
                        "event_kind": "session_started" if payload is None else "pty_output",
                        "payload": {"terminal_emulation": "xterm256", "cols": 120, "rows": 40}
                        if payload is None else {"bytes_base64": base64.b64encode(payload).decode()}})
    return ("\n".join(json.dumps(r, separators=(",", ":")) for r in records) + "\n").encode()


def run(name, data, raw_bytes=None):
    # Byte chunks test compression tradeoffs only. Production chunks must
    # preserve event framing and include a time/offset index.
    chunks = [data[i:i + 256 * 1024] for i in range(0, len(data), 256 * 1024)]
    methods = [
        ("gzip-6-whole", lambda: [gzip.compress(data, compresslevel=6, mtime=0)],
         lambda parts: gzip.decompress(parts[0])),
        ("zstd-3-whole", lambda: [zcompress(data)],
         lambda parts: zdecompress(parts[0], len(data))),
        ("zstd-3-256KiB", lambda: [zcompress(part) for part in chunks],
         lambda parts: b"".join(zdecompress(part, len(src)) for part, src in zip(parts, chunks))),
    ]
    rows = []
    for codec, encode, decode in methods:
        encoded, compress_ms = timed(encode)
        restored, decompress_ms = timed(lambda: decode(encoded))
        assert restored == data, (name, codec)
        size = sum(map(len, encoded))
        rows.append({"codec": codec, "bytes": size,
                     "percent_of_ndjson": round(size * 100 / len(data), 2),
                     "compress_ms": compress_ms, "decompress_ms": decompress_ms,
                     "roundtrip_equal": True})
    return {"sample": name, "ndjson_bytes": len(data), "raw_payload_bytes": raw_bytes,
            "results": rows}


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path,
        default=root / "build/recording_bench/compression/results.json",
        help="Result JSON path (defaults to ignored build/recording_bench).",
    )
    args = parser.parse_args()
    rng = random.Random(20260916)
    logs = [(f"2026-09-16T10:{i // 60 % 60:02}:{i % 60:02} INFO request={i:08x} "
             f"route=/api/items/{i % 113} status=200 elapsed={i % 97}ms "
             "查询成功 " + "item=terminal-recording " * 20 + "\r\n").encode()
            for i in range(3000)]
    tui = [("\x1b[H\x1b[32m" + "\r\n".join(
        f"task {j:02} progress={(i + j) % 101:3}% cpu={(i * j) % 100:2}% " + "." * 24
        for j in range(24)) + "\x1b[0m").encode() for i in range(3000)]
    noise = [rng.randbytes(1024) for _ in range(3000)]
    samples = [run("synthetic-" + name, ndjson(payloads), sum(map(len, payloads)))
               for name, payloads in [("logs", logs), ("tui", tui), ("high-entropy", noise)]]
    for path in sorted((root / "packages/ianvs_terminal/test/fixtures/recording").glob("*.ndjson")):
        samples.append(run("fixture-" + path.name, path.read_bytes()))
    report = {"platform": platform.platform(), "python": platform.python_version(),
                      "zstd": lib.ZSTD_versionString().decode(),
                      "timing": "median of 7 warm runs; codec + Python buffers only; no IO/parser/UI",
                      "chunk_index_bytes_included": False, "samples": samples}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Verified {len(samples)} samples; wrote {args.output}")


if __name__ == "__main__":
    main()
