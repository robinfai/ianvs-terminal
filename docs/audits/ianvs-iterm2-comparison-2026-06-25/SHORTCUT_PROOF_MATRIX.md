# Ianvs Terminal Shortcut Proof Matrix

Date: 2026-06-25

Scope: automated macOS widget proof for the shortcut set called out by `T-UX-002`.

## Evidence Command

```sh
cd example && flutter test test/widget_test.dart --plain-name "shortcut proof matrix"
```

Latest result in this worktree: passed.

## Matrix

| Shortcut | Expected action | Automated proof |
| --- | --- | --- |
| `Cmd+T` | Open a new tab | `shortcut proof matrix covers planned mac shortcuts` asserts `shell-tab-2` exists and is selected. |
| `Cmd+D` | Split right | Same test asserts `shell-pane-3` exists after the shortcut. |
| `Cmd+Shift+D` | Split down | Same test asserts `shell-pane-4` exists after the shortcut. |
| `Cmd+F` | Open shell search | Same test asserts `terminal-search-bar` exists. |
| `Cmd+Shift+P` | Open command menu | Same test asserts `shell-command-menu-overlay` exists. |
| `Cmd+Shift+H` | Open paste history | Same test asserts `paste-history-sheet` exists and shows the seeded entry. |
| `Option+Cmd+B` | Open instant replay workspace | Same test asserts `instant-replay-workspace` exists. |
| `Option+Cmd+Space` | Toggle hotkey window | Same test mocks `app/window_bridge` and asserts `toggleHotkeyWindow` was called. |

Every shortcut step also asserts `FakePtyBackend.writes` remains empty, distinguishing handled app shortcuts from accidental terminal input.

## Remaining Manual Proof

This matrix proves Flutter-level dispatch and visible UI outcomes. It does not prove macOS global delivery outside the app process or native foreground behavior. Those remain part of `T-UX-001` foreground launch proof and hotkey-window native availability proof.
