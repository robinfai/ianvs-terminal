# Linux independent-peer SSH, SFTP, and ZMODEM smoke gate

Run `tools/linux_e2e/run.sh` on Linux with Rust, Python 3.10+, OpenSSH's
`ssh-keygen`, Bash, GNU coreutils (`timeout`), and GNU lrzsz (`rz` and `sz`).
Install the test-only AsyncSSH dependency in a virtual environment first:

```sh
python3 -m venv /tmp/ianvs-loopback-venv
/tmp/ianvs-loopback-venv/bin/python -m pip install -r tools/linux_e2e/requirements.txt
IANVS_LOOPBACK_PYTHON=/tmp/ianvs-loopback-venv/bin/python tools/linux_e2e/run.sh
```

The runner never installs dependencies or changes system configuration. No
Docker, root account, system SSH server, or external credentials are needed.
`IANVS_LOOPBACK_PYTHON`, `IANVS_LOOPBACK_RZ`, and `IANVS_LOOPBACK_SZ` can select
alternate absolute executable paths, including tools in an extracted sysroot.

The script starts an **independent AsyncSSH protocol peer**, bound only to a
kernel-assigned random loopback port. Host/client keys, a strict known-hosts
file, shell HOME, and all transferred files live under a fresh mode-0700
temporary directory. Only the generated public key and fixture username are
accepted; password, keyboard-interactive, agent, and network forwarding are
unavailable. The shell uses a real same-user Linux PTY, with byte-preserving
SSH-to-PTY relay and terminal resize handling. SFTP paths are rooted at the
fixture directory. The peer is a disposable test fixture, not a production
server or a security sandbox; its shell retains the invoking user's access.
It must not be exposed outside loopback or reused with real credentials.

The peer, its shell process groups, and fixture directory are removed on exit.
Setup and Cargo execution have time limits, and the Rust test bounds I/O waits.
Setup failures are errors. The test is ignored in ordinary Cargo runs so
missing peers never produce a false acceptance pass.

The native Rust client verifies:

- strict host-key and generated Ed25519 public-key authentication
- interactive shell input/output through a real Linux PTY
- SFTP directory creation/listing, binary upload/download, and deletion
- two-file batches in each ZMODEM direction through the native SSH PTY and GNU
  lrzsz, including every byte value, exact payloads, and modification timestamps
- return to usable shell output after each transfer

The runner accepts optional Cargo build arguments, for example:

```sh
IANVS_LOOPBACK_PYTHON=/tmp/ianvs-loopback-venv/bin/python \
  CARGO_TARGET_DIR=/path/to/existing/cargo-target \
  tools/linux_e2e/run.sh --release --target x86_64-unknown-linux-gnu
```

This smoke gate supplements the [OpenSSH Docker gate](../ssh_e2e/README.md) and
[pinned ZMODEM gate](../zmodem_e2e/README.md). A pass is **not an OpenSSH acceptance
pass** and does not establish password/PAM/OTP authentication, isolated two-hop
ProxyJump, port/agent/X11 forwarding, or compatibility with their pinned Ubuntu
and lrzsz peer versions. Keep and run those independent gates unchanged.
