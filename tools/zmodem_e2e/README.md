# ZMODEM OpenSSH end-to-end fixture

This fixture runs from macOS (Colima) or Linux (Docker Engine) and validates
both native ZMODEM directions through a real SSH PTY
against the `lrzsz` implementation. It is deliberately an ignored Rust test:
ordinary `cargo test` reports it as `ignored`, never as a false pass. Run it
explicitly with `--ignored --exact`; a missing or partial environment fails.
The `zmodem-openssh` GitHub Actions job performs that explicit run against
Docker Engine on every repository verification workflow.
The SSH profile uses `-e none` so OpenSSH's local escape character cannot
consume a binary byte sequence.
The Dockerfile pins the multi-platform Ubuntu 24.04 image digest, the immutable
Ubuntu `20260801T000000Z` package snapshot, and exact `lrzsz` and
`openssh-server` package versions. SSH host keys are generated when each
disposable container starts, so random keys do not make the image layer vary.
Files created by package maintainer scripts are normalized to the same fixed
`SOURCE_DATE_EPOCH` to reduce irrelevant image churn. The fixture does not
claim bit-for-bit reproducible image IDs: BuildKit and package maintainer
behavior remain outside that contract. The pinned snapshot is fetched over
an HTTP bootstrap URI that `snapshot.ubuntu.com` redirects to HTTPS. The pinned
base image has no CA bundle, so TLS peer verification is disabled only for the
`apt-get update` and install transaction that installs the pinned
`ca-certificates` package. During that bootstrap, APT authenticates content
using Ubuntu's pinned archive keyring, signed repository metadata, and package
hashes; the option is not relied on after the image layer is built.
Before running either transfer, the ignored test verifies the fixture marker,
both Debian package versions, and the GNU `rz`/`sz` `0.12.21rc` version strings;
a silently changed peer is rejected.

Do not point this test at a general-purpose SSH host. Both remote commands
require the marker installed by this purpose-built image, allocate their own
`mktemp` directory, install failure/signal cleanup traps, and remove that
directory before printing the success marker. Concurrent test runs therefore
do not share a remote path or leave transferred files behind.

```bash
# macOS only; on Linux start Docker Engine by the host's normal mechanism.
colima start
docker build --provenance=false \
  --build-arg SOURCE_DATE_EPOCH=1785542400 \
  -t ianvs-zmodem-e2e tools/zmodem_e2e
fixture_dir=$(mktemp -d /tmp/ianvs-zmodem-e2e.XXXXXX)
fixture_name=ianvs-zmodem-e2e-$(basename "$fixture_dir")
ssh-keygen -q -t ed25519 -N '' -f "$fixture_dir/id_ed25519"
docker run --rm -d --name "$fixture_name" \
  -p 127.0.0.1::22 \
  ianvs-zmodem-e2e
docker cp "$fixture_dir/id_ed25519.pub" \
  "$fixture_name:/root/.ssh/authorized_keys"
docker exec "$fixture_name" \
  sh -c 'chown root:root /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys'
fixture_port=$(docker port "$fixture_name" 22/tcp | sed 's/.*://')
```

Run the exact ignored test using the allocated host port and an absolute path
to a representative regular-file fixture:

```bash
IANVS_ZMODEM_SSH_TARGET=root@127.0.0.1 \
IANVS_ZMODEM_SSH_PORT="$fixture_port" \
IANVS_ZMODEM_SSH_IDENTITY="$fixture_dir/id_ed25519" \
IANVS_ZMODEM_SSH_SEND_FILE=/absolute/path/to/zmodem-send-fixture.bin \
cargo test --manifest-path native/core/Cargo.toml \
  --test zmodem_ssh_test -- \
  --ignored --exact zmodem_round_trips_files_over_real_openssh_pty --nocapture
```

`IANVS_ZMODEM_SSH_SEND_FILE` is required and must be an absolute regular-file
path. Its basename must differ from `ianvs-zmodem-batch-companion.bin` and may
contain only ASCII letters, digits, `.`, `_`, and `-`; these constraints keep
the purpose-built remote shell command unambiguous. The test verifies two
distinct files in a remote `sz -e` receive batch
and two distinct files in a remote `rz -bye` send batch. It compares MD5
values and byte sizes computed independently at both ends and requires source
and destination modification times to match to the second for all four files.
A checked macOS/Colima run with the 108,277,050-byte installer fixture is recorded in
[`docs/evidence/ZMODEM_COLIMA_OPENSSH_2026-08-07.md`](../../docs/evidence/ZMODEM_COLIMA_OPENSSH_2026-08-07.md).
Clean up the one run's container and key directory when finished:

```bash
docker stop "$fixture_name"
rm -rf "$fixture_dir"
colima stop
```
