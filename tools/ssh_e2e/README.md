# Rust SSH / OpenSSH Docker acceptance

This fixture is the executable acceptance gate for Ianvs' native Rust SSH
transport. It builds one pinned OpenSSH image and starts eight disposable
services:

| Service | Reachable from host | Authentication / purpose |
| --- | --- | --- |
| `password` | random loopback port | password only |
| `keyboard-interactive` | random loopback port | PAM keyboard-interactive only |
| `otp` | random loopback port | custom PAM module with two distinct password/OTP rounds |
| `publickey` | random loopback port | generated Ed25519 key only |
| `jump` | random loopback port | first hop; forwarding is restricted to `jump2:22` |
| `jump2` | no published port | second hop; forwarding is restricted to `target:22` |
| `forwarding` | random loopback port | public key plus L/R/D, agent, and X11 forwarding |
| `target` | no published port | generated Ed25519 key; reachable only through both jump hosts |

The client side calls `ianvs_core::ssh::spawn_ssh`, so authentication, SSH
handshakes, PTY allocation, shell traffic, two-round keyboard-interactive UI
broker, the native two-hop ProxyJump chain, local/remote/dynamic port
forwarding, SSH-agent channels, and X11 channels are all exercised through
`russh`. The system `ssh` client is not used. `ssh-keygen` is used only to
create fresh disposable client and wrong-host fixtures, and to encrypt a copy
of the authorized client key for the bad-passphrase test.

Run the complete gate from the repository root:

```bash
./tools/ssh_e2e/run.sh
```

The runner builds the image, generates the client keypair, allocates random
ports, waits for every daemon to become healthy, verifies that `target` has no
host port, executes the required ignored Rust acceptance tests, and removes all
containers, volumes, networks, and temporary keys. A failure prints service
state plus bounded logs from every service before cleanup.

The acceptance test proves:

- password authentication and password-backed PAM keyboard-interactive;
- two separate PAM prompts (`Fixture password` followed by `One-time password`)
  delivered and answered as independent client challenge rounds;
- generated Ed25519 public-key authentication;
- default strict host-key rejection, explicit accept-new persistence,
  same-key strict reconnect, and changed-key rejection without mutation;
- bounded failures for a wrong password, wrong OTP, cancelled challenge,
  wrong encrypted-key passphrase, and an unresponsive jump host;
- a destination reachable only through `jump -> jump2 -> target`;
- local (`L`), remote (`R`), and dynamic SOCKS5 (`D`) forwarding with real
  TCP payloads;
- agent forwarding to a temporary Unix-domain socket; and
- X11 forwarding to a temporary local TCP listener, including OpenSSH's
  server-side fake `xauth` cookie setup and byte-exact replacement with the
  real local cookie before relay.

The test is intentionally marked ignored so ordinary `cargo test` cannot
report a false pass when Docker is absent. The runner verifies every required
test is present before invoking the ignored test binary serially. CI runs the
same script on Linux.

The fixture uses Ubuntu snapshot `20260801T000000Z`, base image digest
`sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea`,
and `openssh-server` version `1:9.6p1-3ubuntu13.18`. Direct packages, including
the PAM build toolchain, `socat`, and `xauth`, are version-pinned. The password
and OTP are fixed fixture-only values inside disposable containers. Host keys
and the client key are generated for each run and are not stored in the
repository.
