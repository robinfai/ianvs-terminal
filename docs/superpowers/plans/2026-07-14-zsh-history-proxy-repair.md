# Zsh History Proxy Path Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the Ianvs zsh integration proxy from redirecting the user's default `HISTFILE` into a per-session temporary directory while preserving explicit custom history paths.

**Architecture:** Keep the existing `ZDOTDIR` proxy and repair only the exact default history path derived from that proxy. The generated proxy `.zshrc` performs the repair before sourcing the user's `.zshrc`, allowing user configuration to override the result normally. Cross-platform proxy-script tests cover the matching rule, and a macOS-only real-session test covers the observed `history` behavior.

**Tech Stack:** Rust, zsh startup scripts embedded in Rust, `portable_pty`, Rust unit and integration tests.

---

## File structure

- Modify `native/core/src/pty.rs`: add focused zsh proxy tests, add the history-path repair helper, and invoke it before the user's `.zshrc`.
- Modify `native/core/tests/session_test.rs`: add a macOS real-zsh regression test that verifies persisted history is visible through `history`.

### Task 1: Add failing proxy and real-session regression coverage

**Files:**
- Modify: `native/core/src/pty.rs:817`
- Modify: `native/core/tests/session_test.rs:16320`

- [ ] **Step 1: Add a cross-platform proxy-path regression test**

Add this test inside `native/core/src/pty.rs`'s existing `tests` module, after `zsh_shell_hook_integration_eligible_profile_sets_zdotdir_proxy`:

```rust
#[test]
fn zsh_proxy_repairs_proxy_derived_histfile_before_user_zshrc() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    let proxy_base = tempdir().unwrap();
    let (_helper_dir, helper_path) = helper_path_env();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "print -r -- \"ianvs-histfile=${HISTFILE:-}\"\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert("PATH".to_string(), helper_path);
    let profile = profile(
        "/bin/zsh",
        vec![],
        env,
        TerminalEmulation::Xterm256,
        true,
    );
    let plan = build_command_plan_with_proxy_factory(&profile, |kind, _profile, _program| {
        create_shell_integration_proxy_in(kind, proxy_base.path())
    });
    let proxy_histfile = Path::new(&plan.env["ZDOTDIR"]).join(".zsh_history");

    let output = std::process::Command::new("/bin/zsh")
        .args(["-f", "-c", "source \"$ZDOTDIR/.zshrc\""])
        .envs(&plan.env)
        .env("HISTFILE", &proxy_histfile)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "zsh proxy probe failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let expected_histfile = original_zdotdir.path().join(".zsh_history");
    assert!(
        stdout.contains(expected_histfile.to_string_lossy().as_ref()),
        "proxy-derived HISTFILE should be repaired before user .zshrc: {stdout}"
    );
}
```

- [ ] **Step 2: Add custom-path preservation coverage**

Add this second test beside the first one:

```rust
#[test]
fn zsh_proxy_preserves_custom_histfile_before_user_zshrc() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    let proxy_base = tempdir().unwrap();
    let custom_history_dir = tempdir().unwrap();
    let custom_histfile = custom_history_dir.path().join("custom.zsh_history");
    let (_helper_dir, helper_path) = helper_path_env();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        "print -r -- \"ianvs-histfile=${HISTFILE:-}\"\n",
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert("PATH".to_string(), helper_path);
    let profile = profile(
        "/bin/zsh",
        vec![],
        env,
        TerminalEmulation::Xterm256,
        true,
    );
    let plan = build_command_plan_with_proxy_factory(&profile, |kind, _profile, _program| {
        create_shell_integration_proxy_in(kind, proxy_base.path())
    });

    let output = std::process::Command::new("/bin/zsh")
        .args(["-f", "-c", "source \"$ZDOTDIR/.zshrc\""])
        .envs(&plan.env)
        .env("HISTFILE", &custom_histfile)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "zsh proxy probe failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        stdout.contains(custom_histfile.to_string_lossy().as_ref()),
        "custom HISTFILE should remain unchanged: {stdout}"
    );
}
```

- [ ] **Step 3: Add the macOS real-session regression test**

Add this test in `native/core/tests/session_test.rs` beside the existing zsh shell-integration tests:

```rust
#[cfg(target_os = "macos")]
#[test]
fn zsh_shell_hook_integration_loads_history_from_original_zdotdir() {
    if !Path::new("/bin/zsh").exists() {
        return;
    }

    let original_zdotdir = tempdir().unwrap();
    fs::write(
        original_zdotdir.path().join(".zsh_history"),
        ": 1783987200:0;echo ianvs-persisted-history-sentinel\n",
    )
    .unwrap();
    fs::write(
        original_zdotdir.path().join(".zshrc"),
        r#"HISTSIZE=50000
SAVEHIST=50000
if [[ -z "${HISTFILE:-}" ]]; then
  HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
fi
setopt SHARE_HISTORY APPEND_HISTORY INC_APPEND_HISTORY EXTENDED_HISTORY
PROMPT='ianvs terminal-history% '
"#,
    )
    .unwrap();
    let mut env = BTreeMap::new();
    env.insert(
        "HOME".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    env.insert(
        "ZDOTDIR".to_string(),
        original_zdotdir.path().to_string_lossy().into_owned(),
    );
    let session_id = session::create_session(
        &serde_json::to_string(&local_profile(
            "zsh-shell-integration-history",
            "Zsh Shell Integration History",
            "/bin/zsh",
            vec![],
            env,
            TerminalEmulation::Xterm256,
        ))
        .unwrap(),
    )
    .unwrap();

    let _ = wait_for_frame_containing(session_id, "ianvs terminal-history");
    session::write_session(session_id, b"history 1\n").unwrap();
    let frame = wait_for_frame_containing(session_id, "ianvs-persisted-history-sentinel");
    assert!(
        frame.contains("echo ianvs-persisted-history-sentinel"),
        "history should include the entry from the original ZDOTDIR: {frame}"
    );

    session::close_session(session_id).unwrap();
}
```

- [ ] **Step 4: Run the proxy test and verify the expected red state**

Run from `native/core`:

```bash
cargo test --lib pty::tests::zsh_proxy_repairs_proxy_derived_histfile_before_user_zshrc -- --exact --nocapture
```

Expected: FAIL because the printed `HISTFILE` still points at the generated proxy directory.

- [ ] **Step 5: Run the preservation test**

Run from `native/core`:

```bash
cargo test --lib pty::tests::zsh_proxy_preserves_custom_histfile_before_user_zshrc -- --exact --nocapture
```

Expected: PASS, establishing the existing custom-path behavior that the repair must preserve.

- [ ] **Step 6: Run the macOS regression test and verify the expected red state**

Run from `native/core`:

```bash
cargo test --test session_test zsh_shell_hook_integration_loads_history_from_original_zdotdir -- --exact --nocapture
```

Expected on macOS: FAIL by timing out while waiting for `ianvs-persisted-history-sentinel`, because zsh is reading the proxy history file. On non-macOS platforms the test is not compiled.

### Task 2: Repair only the proxy-derived default history path

**Files:**
- Modify: `native/core/src/pty.rs:474-542`

- [ ] **Step 1: Add the focused zsh repair helper**

Add this function to `ZSH_PROXY_COMMON`, after `__ianvs_original_zdotdir` and before `__ianvs_source_original_zdotfile`:

```zsh
__ianvs_restore_proxy_derived_histfile() {
  emulate -L zsh
  local __ianvs_proxy_zdotdir="${ZDOTDIR:-}"
  [[ -n "$__ianvs_proxy_zdotdir" ]] || return 0
  [[ "${HISTFILE:-}" == "$__ianvs_proxy_zdotdir/.zsh_history" ]] || return 0
  local __ianvs_user_zdotdir="$(__ianvs_original_zdotdir)"
  [[ -n "$__ianvs_user_zdotdir" ]] || __ianvs_user_zdotdir="${HOME:-}"
  [[ -n "$__ianvs_user_zdotdir" ]] || return 0
  HISTFILE="$__ianvs_user_zdotdir/.zsh_history"
}
```

- [ ] **Step 2: Invoke the repair before loading the user's `.zshrc`**

Change the generated proxy `.zshrc` body in `write_zsh_proxy_files` to:

```rust
format!(
    "{}\n{}\n__ianvs_restore_proxy_derived_histfile >/dev/null 2>&1 || true\n__ianvs_source_original_zdotfile \".zshrc\"\n__ianvs_install_shell_hooks >/dev/null 2>&1 || true\n__ianvs_suspend_startup_prompt_sp >/dev/null 2>&1 || true\n__ianvs_restore_zdotdir >/dev/null 2>&1 || true\n",
    ZSH_PROXY_COMMON, ZSH_HOOK_INSTALLER
),
```

- [ ] **Step 3: Run both proxy tests**

Run from `native/core`:

```bash
cargo test --lib pty::tests::zsh_proxy_ -- --nocapture
```

Expected: both proxy history tests PASS.

- [ ] **Step 4: Run the macOS real-session regression test**

Run from `native/core`:

```bash
cargo test --test session_test zsh_shell_hook_integration_loads_history_from_original_zdotdir -- --exact --nocapture
```

Expected on macOS: PASS and the terminal frame contains `echo ianvs-persisted-history-sentinel`.

- [ ] **Step 5: Run existing zsh integration regression coverage**

Run from `native/core`:

```bash
cargo test --test session_test zsh_shell_hook_integration -- --nocapture
cargo test --lib pty::tests::zsh_shell_hook_integration -- --nocapture
```

Expected: all matching tests PASS, including lifecycle hooks, prompt substitution, original `ZDOTDIR`, and login-shell eligibility.

- [ ] **Step 6: Commit the tested repair**

```bash
git add native/core/src/pty.rs native/core/tests/session_test.rs
git commit -m "fix(pty): restore zsh history path after proxy startup"
```

### Task 3: Run full native-core verification

**Files:**
- Verify: `native/core/src/pty.rs`
- Verify: `native/core/tests/session_test.rs`

- [ ] **Step 1: Check Rust formatting**

Run from `native/core`:

```bash
cargo fmt --check
```

Expected: exit code 0 with no formatting diff.

- [ ] **Step 2: Run Clippy with warnings denied**

Run from `native/core`:

```bash
cargo clippy --all-targets -- -D warnings
```

Expected: exit code 0 with no warnings.

- [ ] **Step 3: Run the complete native-core test suite serially**

Run from `native/core`:

```bash
cargo test -- --test-threads=1
```

Expected: all unit and integration tests PASS with zero failures.

- [ ] **Step 4: Confirm the final patch scope**

Run from the repository root:

```bash
git status --short
git diff --check HEAD~1..HEAD
git diff --stat HEAD~1..HEAD
```

Expected: only `native/core/src/pty.rs` and `native/core/tests/session_test.rs` are changed by the implementation commits, with no whitespace errors.
