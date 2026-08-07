# ZMODEM Colima/OpenSSH evidence — 2026-08-07

This record captures the manual macOS/Colima evidence for the RZ/SZ change.
The automated amd64 and arm64 Docker runs remain in `.github/workflows/verify.yml`.
The values below are from the final frozen-source rerun on 2026-08-07 after
publication, batch, mtime, close-race, full-duplex ordering, and protocol-reply
hardening.

## Environment

- Branch: `codex/rzsz-zmodem`
- Base commit: `954a7b431f11501e4bb160f42e8b00d7cbfa49d4`
- Changed-source manifest: 86 modified/untracked paths, excluding this evidence
  file; SHA-256
  `fcc77d2007f938bb3d92299f1b94feae754a20070fef6aa3054b320818c8f3c4`
- Host: `Darwin 25.5.0 arm64`
- Container: Linux arm64, image
  `sha256:6198aa4b44f9d7073570098d3a28493e09bac8dfae63feeb8ce1365a9f0eb85b`
- Ubuntu snapshot: `20260801T000000Z`
- `lrzsz`: `0.12.21-11build1` (`rz`/`sz` report `0.12.21rc`)
- `openssh-server`: `1:9.6p1-3ubuntu13.18`

## Command

The disposable container used a dynamically allocated localhost SSH port and
an ephemeral Ed25519 key. The executed test command was:

```bash
IANVS_ZMODEM_SSH_TARGET=root@127.0.0.1 \
IANVS_ZMODEM_SSH_PORT=32773 \
IANVS_ZMODEM_SSH_IDENTITY=/private/tmp/ianvs-zmodem-final23.LAB321/id_ed25519 \
IANVS_ZMODEM_SSH_SEND_FILE=/Users/robinfai/Downloads/tabby-1.0.181-macos-arm64.pkg \
cargo test --manifest-path native/core/Cargo.toml \
  --test zmodem_ssh_test -- \
  --ignored --exact zmodem_round_trips_files_over_real_openssh_pty --nocapture
```

The source-manifest digest above binds this uncommitted evidence run to the
exact working-tree contents without recursively hashing this evidence file:

```bash
git ls-files -m -o --exclude-standard \
  | grep -v '^docs/evidence/ZMODEM_COLIMA_OPENSSH_2026-08-07.md$' \
  | LC_ALL=C sort \
  | xargs shasum -a 256 \
  | shasum -a 256
```

The test first probes the fixture marker and exact package/version strings. In
each direction the sender computes MD5, byte size, and whole-second mtime; the
receiver computes them independently and the test requires equality before it
can pass.

## Results

| Direction | Remote command | File | MD5 | Bytes | mtime (Unix seconds) |
| --- | --- | --- | --- | ---: | ---: |
| Container → host | `sz -e` | `ianvs-zmodem-receive-a.bin` | `fecd741df848500b821b184df03d32bb` | 4,194,304 | 1,700,000,123 |
| Container → host | `sz -e` | `ianvs-zmodem-receive-b.bin` | `99c9b2f1132c463497ed3b2c4e18e677` | 786,432 | 1,700,000,789 |
| Host → container | `rz -bye` | `tabby-1.0.181-macos-arm64.pkg` | `992a420ef968cf669c67dbca266d7818` | 108,277,050 | 1,786,005,644 |
| Host → container | `rz -bye` | `ianvs-zmodem-batch-companion.bin` | `31c03c0ef6a863d3bbc90ae5b4d8aeaf` | 29 | 1,700,000,789 |

Result: `1 passed; 0 failed`, completed in `57.45s`. Both remote temporary
directories were removed by the fixture before their success markers were
accepted. The non-zero mtime checks also prove that a successful round trip
does not project the file timestamp as 1970.
