# Shell Hook Evidence

Date: 2026-05-29
Machine: Mac16,11
Scope: native real pty shell-hook tests plus shell-hook launch-plan/degrade tests

## Commands

```bash
cargo test shell_hook_integration --manifest-path native/core/Cargo.toml --test session_test -- --nocapture
cargo test shell_hook_integration --manifest-path native/core/Cargo.toml -- --nocapture
```

## Result

- Native real pty shell-hook session tests: pass, 9 passed, 0 failed.
- Shell-hook launch-plan and degrade tests: pass, 8 unit tests passed plus session shell-hook tests passed.
- Fish real pty shell-hook session tests after installing fish: pass, 2 passed, 0 failed.

## Real pty coverage on this machine

- zsh: covered with real pty. The test starts `/bin/zsh`, validates `precmd.pwd`, validates `echo ok` command lifecycle, and validates `false` exit code 1.
- bash: covered with real pty. The test starts `/bin/bash`, validates `precmd.pwd`, validates `echo ok` command lifecycle, and validates `false` exit code 1.
- fish: covered with real pty after installing fish 4.7.1 via Homebrew. The test starts `/opt/homebrew/bin/fish`, validates `precmd.pwd`, validates `echo ok` command lifecycle, and validates `false` exit code 1.

## Evidence files

- `shell-availability.txt`
- `shell-availability-after-fish-install.txt`
- `native-real-pty-shell-hook-session-test.log`
- `native-real-pty-fish-shell-hook-session-test.log`
- `native-shell-hook-plan-and-degrade-test.log`

## Notes

This evidence replaces manual App shell-hook checks for zsh, bash, and fish on this host.
