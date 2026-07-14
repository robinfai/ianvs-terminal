# Zsh History Proxy Path Repair Design

## Problem

Ianvs injects zsh shell integration by launching zsh with `ZDOTDIR` pointed at
a per-session proxy directory. On macOS, `/etc/zshrc` derives the default
history path while that proxy value is active:

```zsh
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
```

The proxy later restores the user's original `ZDOTDIR` while sourcing the
user's `.zshrc`, but it does not repair values already derived from the proxy.
As a result, `HISTFILE` remains inside the temporary proxy directory, so a new
Ianvs session does not load the user's normal zsh history.

## Goals

- Make an Ianvs zsh session load the same default history file that zsh would
  use without the Ianvs `ZDOTDIR` proxy.
- Preserve an explicitly customized `HISTFILE`.
- Preserve custom `ZDOTDIR` behavior.
- Keep shell integration hooks and the current startup-file ordering intact.

## Non-goals

- Do not hard-code `$HOME/.zsh_history` for every user.
- Do not import history with `fc -R` after startup.
- Do not redesign shell integration or replace the `ZDOTDIR` proxy.
- Do not modify user-owned shell configuration files.

## Selected approach

The generated zsh proxy will repair only the default history path derived from
the proxy directory.

Before sourcing the user's `.zshrc`, the proxy will:

1. Capture the active proxy directory.
2. Compute the proxy-derived default history path
   (`$proxy_zdotdir/.zsh_history`).
3. Compute the user's default history path from the original `ZDOTDIR`, falling
   back to `HOME` when the original value is absent or empty.
4. Change `HISTFILE` only when its current value exactly matches the
   proxy-derived default path.
5. Leave every other `HISTFILE` value unchanged.

The user's `.zshrc` is then sourced normally and remains free to override
`HISTFILE` again.

## Data flow

```text
Ianvs sets ZDOTDIR to proxy
  -> macOS /etc/zshrc derives proxy/.zsh_history
  -> proxy detects that exact derived value
  -> proxy restores original-zdotdir-or-home/.zsh_history
  -> proxy sources the user's .zshrc
  -> proxy installs Ianvs shell hooks
```

## Safety and compatibility

- Exact-path matching prevents Ianvs from overwriting unrelated custom history
  locations.
- The repair is limited to zsh; bash and fish startup behavior is unchanged.
- If no usable original dot directory or home directory is available, the
  proxy leaves `HISTFILE` unchanged rather than guessing.
- Paths containing spaces remain supported by using quoted zsh assignments and
  comparisons.

## Test strategy

Implementation will follow a red-green cycle.

1. Add a real-zsh integration test that creates a temporary user dot directory,
   seeds its `.zsh_history`, launches a shell-integrated Ianvs session, runs
   `history`, and verifies that the seeded entry is present. This test must fail
   before the production change because the session uses the proxy history.
2. Add coverage showing that a user-defined non-default `HISTFILE` remains in
   effect.
3. Run the existing zsh shell-integration lifecycle and original-`ZDOTDIR`
   tests to guard startup ordering and hook behavior.
4. Run the native core test suite and formatting checks after the focused tests
   pass.

## Acceptance criteria

- A new Ianvs zsh session reads existing history from the user's effective
  default history file.
- `history` no longer starts from an empty per-session proxy history when a
  user history file exists.
- Explicit custom history paths are unchanged.
- Existing zsh shell integration hooks continue to emit lifecycle events.
- No user configuration file is created or modified by the repair itself.
