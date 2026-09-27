# Recording storage experiments

These are reusable measurement tools for the
[storage proposal](../../docs/recording/STORAGE_PROPOSAL.md), not production
readers/writers or correctness fixtures. The current product contract is
[sampled schema 2](../../docs/recording/FORMAT_CURRENT.md). Older Python experiments
use committed legacy fixtures only; they are not product import/migration paths.

Run from the repository root. Default outputs are under ignored
`build/recording_bench/`; `--output` selects another local destination. Repeated
runs replace results in the chosen destination. Do not commit raw captures,
generated descriptors, compressed samples, or result JSON.

| Script | Purpose | Default output |
| --- | --- | --- |
| `storage-compression-benchmark.py` | Synthetic logs/TUI/high-entropy and committed NDJSON fixtures; gzip/Zstd codec roundtrips and timings | `build/recording_bench/compression/results.json` |
| `scenario-storage-benchmark.py` | Nine synthetic workloads, native snapshots versus FrameDiff, event/visual storage roundtrips | `build/recording_bench/scenarios/` |
| `top-storage-benchmark.py` | Explicit macOS `top` PTY capture, then equivalent format comparison | `build/recording_bench/top/` |

All scripts require Python 3 and libzstd. Native comparisons additionally require
Python `protobuf`, `protoc`, and a current macOS release library at
`native/core/target/release/libianvs_core.dylib`. Build the canonical library
before interpreting results:

```bash
cargo build --release --manifest-path native/core/Cargo.toml
python3 tools/recording_bench/storage-compression-benchmark.py
python3 tools/recording_bench/scenario-storage-benchmark.py --only idle,typing
python3 tools/recording_bench/scenario-storage-benchmark.py
```

If the installed Command Line Tools SDK and Xcode linker disagree, select a
matching installed SDK explicitly with `SDKROOT`; do not bake a developer's
local SDK path into the scripts.

The top recorder starts and terminates only its own child. Its output contains
real local process statistics, so capture is a separate explicit command:

```bash
python3 tools/recording_bench/top-storage-benchmark.py record --seconds 60 --name default_1s
python3 tools/recording_bench/top-storage-benchmark.py record --seconds 60 --sort cpu --name cpu_1s
python3 tools/recording_bench/top-storage-benchmark.py analyze
```

Limitations:

- Codec timing excludes disk, parser, search, and UI. The compression-only probe
  cuts byte chunks without a production index; it is not a usable container.
- Native probes use fixed 120×40 text/ANSI workloads. They do not test resize,
  image assets, arbitrary damaged files, persistent seek, or cross-engine replay.
- Snapshot comparisons exclude row modification times and source-row bookkeeping;
  they compare terminal model state rather than GPU pixels.
- The synthetic matrix defaults to 40,000 scrollback lines to avoid eviction.
  Explicitly run `--only scroll_burst --scrollback 8000` for the unresolved
  eviction boundary described in the proposal. Do not treat the larger budget
  as proof that ordinary scrollback behavior is correct.
- Sampled FrameDiff can omit transient screens and logs; compare its size only
  with the stated reduced fidelity. The experimental compact codec is not a
  public storage format.

The scripts read committed contract fixtures but never replace or remove them.
Results include local environment/library metadata where relevant; comparisons
must use the same source stream, fidelity, and compression settings.

## Adaptive structured-screen prototype

The selected new recording direction has an independent native sampler and
side-effect-free keyframe/delta replay model. Run its real-VT comparison before
changing sampling or frame materialization:

```bash
cargo test --manifest-path native/core/Cargo.toml --test sampled_recording_test
cargo run --release --manifest-path native/core/Cargo.toml \
  --example sampled_recording_bench -- build/recording_bench/adaptive/results.json
```

The report compares seven deterministic workloads with independently forced
snapshots, including 8,000-line eviction, resize, TUI, metadata and idle. It
reports sampled frame payload bytes, equivalent sampled snapshot bytes, hook
fixture counts, sampler timings and retained-model encoded sizes. Encoded sizes
are not heap/RSS; payload bytes exclude the implemented container, indexes, compression
and image blobs. Semantic fixtures do not prove real hook delivery. This is
accelerated logical time and never substitutes for 24-hour wall-clock acceptance.


## Structured file open, seek and search

```bash
cargo build --release --manifest-path native/core/Cargo.toml --example sampled_recording_file_bench
native/core/target/release/examples/sampled_recording_file_bench build/recording_bench/adaptive/file-results.json
```

This writes real containers and incremental indexes for 10,000 and 100,000
structured samples, verifies 25 cached opens without index replacement and 100
random seeks, then forces a recovery scan. It reports primary/index byte sizes,
creation/finish times and open/seek percentiles. It also measures first text-index
construction, 25 dense cached search pages, and complete rare/no-match scans,
checking hit counts, forward cursors and cache reuse. Search index bytes and both
per-page and whole-query latency are reported. Filesystem caches are warm and
timestamps are accelerated logical time. It excludes Flutter cross-file queries,
live PTY, images, input latency and power loss, and never establishes >24-hour
endurance.


## Real filesystem failure acceptance

Unlike the earlier storage experiments, `filesystem-acceptance.py` exercises the
production native writer/reader with real APFS ENOSPC or disconnection. It requires
macOS, a built `sampled_recording_durability_probe` example and an explicit **new**
output directory; it never replaces an existing output directory. It does not
require libzstd or Python protobuf. See the [reproduction commands and evidence
limits](../../docs/recording/DURABILITY_ACCEPTANCE.md). Only the newly created
128 MiB test image is filled or disconnected; reports and recovered files remain.
