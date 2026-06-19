# Command Center Warp Post-Universal-Input Spec

Date: 2026-06-19

This track supersedes the earlier terminal-only Command Center v1 scope. The
product direction is now a clean terminal session plus a dedicated Agent
conversation surface, connected by explicit input ownership and command proposal
safety gates.

## Product Model

Command Center remains terminal-first by default:

- ordinary terminal input continues to write to the shell;
- command search, action search, saved commands, and command bar remain explicit
  enhanced surfaces;
- Agent conversation is a separate surface, not a hidden owner of terminal text;
- natural-language routing is visible and configurable, never silent.

Agent Center is now in scope for this implementation track:

- Agent conversation modes;
- natural-language intent routing;
- terminal/session/context attachments;
- mock Agent runtime adapters;
- command proposal and review UI;
- explicit insert/execute bridge from Agent proposals back to the terminal.

## Preserved Safety Constraints

The scope reset does not relax input or execution safety:

- AI-generated commands must not silently write to the PTY.
- Read-only mode blocks terminal execution.
- Paste confirmation, shortcut isolation, and terminal input policy remain
  authoritative.
- Risky or destructive commands require visible review and explicit user
  confirmation.
- Agent context must be redacted and size-limited before it can leave the
  process.
- Tests must use mock Agent adapters and must not require provider credentials.

## Input Ownership

Only one surface owns text input at a time:

```text
terminal                    -> terminal PTY
terminalCommandBar           -> command editor
commandSearch                -> command search overlay
actionSearch                 -> action search overlay
savedCommandSearch           -> saved command overlay
agentConversation            -> Agent composer
agentInlineAsk               -> Agent composer with attached context
agentCommandReview           -> proposal review/editor
```

Terminal focus may remain visually present while another surface is active, but
hidden terminal focus does not have text insertion rights.

## Task Lane

The Agent Center task lane starts at `T-500` and continues through `T-524`:

```text
T-500 scope reset and docs rewrite
T-501 mode taxonomy and state model
T-502 input ownership router
T-503 Agent conversation domain models
T-504 mockable Agent runtime adapter
T-505 Agent context snapshot builder
T-506 context attachments and chips
T-507 natural-language intent router
T-508 auto-detection policy and visible route UI
T-509 Agent conversation pane
T-510 Agent message composer
T-511 streaming response renderer and cancellation
T-512 command proposal model
T-513 command proposal review UI
T-514 execution safety pipeline
T-515 Agent-to-terminal execution bridge
T-516 terminal blocks vs Agent conversation blocks
T-517 explain selected block
T-518 debug last failed command
T-519 command search Agent actions
T-520 session summary and memory bridge
T-521 provider configuration and secret boundaries
T-522 context privacy and budget filtering
T-523 test gates and regression suite
T-524 feature flags and staged rollout
```

The minimum useful vertical slice is:

```text
Open Agent -> ask question -> attach context -> mock stream response
  -> show command proposal -> insert into command bar
```

Execution remains a later gated slice and must pass the safety pipeline before
any proposal can run in the terminal.
