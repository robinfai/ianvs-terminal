# OpenSSH hook and multi-hop file-channel boundary lab

This lab provides disposable OpenSSH servers for two separate runners:

- `run.py` validates the architecture prototype and boundary conditions.
- `product.py` exercises the production Rust SSH/PTY transports, bootstrap and
  SFTP routing. See the [product acceptance report](../../docs/reviews/ssh-product-bootstrap-20260912/README.md).

Neither runner drives the complete Flutter GUI; application state and widget
behavior are tested separately.

The runner extracts the real bash/zsh/fish/sh integration strings from
`native/core/src/pty.rs`. `prototype.py` adds an experimental DCS handshake,
context IDs and a deliberately limited `ssh host` wrapper. It does not replace
the existing application transport. Arbitrary SSH options, shell replacement,
prompt detection and third-party integration compatibility are not solved by
this prototype.

## Run

Requirements: Docker/Colima, Python 3.10+, and host OpenSSH. Python dependencies
are standard-library only. The lab explicitly selects a Docker context and
does not change the user's default context or stop unrelated containers.

```sh
# Only needed if the repository's pinned base fixture is not cached:
docker --context colima build -t ianvs-ssh-e2e:20260808 tools/ssh_e2e

docker --context colima build -t ianvs-ssh-boundary-lab:20260912 tools/ssh_boundary_lab
python3 tools/ssh_boundary_lab/run.py --context colima \
  --output /tmp/ianvs-ssh-boundary-results

# Production implementation; no prototype injection is executed:
python3 tools/ssh_boundary_lab/product.py --context colima \
  --output /tmp/ianvs-ssh-product-results
```

The base fixture pins Ubuntu and OpenSSH. Additional tools come from the same
immutable Ubuntu package snapshot. Every report records the actual image ID,
package versions, Git revision and hash of the hook source. Keys are generated
per run, only fixture host keys enter the temporary known-hosts file, and host
key verification stays enabled. Host ports bind only to loopback; B and C have
no published ports. The test user has no access to personal SSH credentials.

Containers and networks have a unique `ianvs.boundary-lab` label. Normal exit
and assertion failures collect sshd logs and remove those resources and the
temporary keys. The reusable image remains cached. If the runner is forcibly
killed, inspect `docker --context colima ps -a --filter label=ianvs.boundary-lab`
and remove only the resources bearing that interrupted run's label.

## Evidence and interpretation

- `results.json` records each assertion and evidence. A passing **negative**
  case means a limitation was reproduced, not that the feature works there.
- `sshd-*.log` supplies server-side connection/session evidence. These logs
  contain only disposable fixture identities, addresses and public fingerprints.
- A failed PTY case produces `failed-*.pty` for diagnosis. These can contain
  the experimental bootstrap; do not interpret them as production log hygiene.
- SFTP is exercised by an actual binary v3 client (INIT, OPEN, WRITE, READ,
  CLOSE), with all byte values and a SHA-256 checked round trip. It does not
  scrape `ls` output or parse an interactive `sftp` prompt.
- Remote master passengers deliberately have only an unauthorized key and
  `BatchMode=yes`; direct authentication must fail while reuse succeeds.
  This is a test oracle, not the proposed production reconnection policy.
- `strace` records file operations in the sshd process tree. Read-only home
  and `/tmp`, on-disk payload scans and creation-path checks cover script-file
  persistence. They do not promise absence of shell caches, sshd audit logs,
  process command lines, swap or administrator-controlled session recording.
  The `created_paths` field lists `O_CREAT` attempts, including failed opens.

The bash pipe bootstrap emits ready before its first prompt, but intentionally
uses an interactive rc-file launch rather than promising full login-shell
startup equivalence. zsh/fish stream tests wait for a known **fixture** prompt
inside the final shell and buffer it before considering the shell ready. This
proves in-memory installation in that process, not arbitrary host prompt
detection or the application's future UI gate. Completion generation is
disabled in the zsh fixture to avoid unrelated compinit costs under strace.

The preceding prototype observations describe `run.py` only. The production
implementation has its own authenticated control protocol and context-aware
capability and SFTP state. `product.py` checks those native transport paths,
while Flutter regression tests check the corresponding state and panel wiring.
