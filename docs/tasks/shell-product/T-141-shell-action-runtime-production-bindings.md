# T-141 Shell action runtime production bindings

## Milestone

P1 - Local terminal action foundation

## Intent

Define the stable seam between the shell action runtime and production
`ShellScreen` / `SessionController` callbacks before wiring UI actions into real
terminal behavior.

## Scope

- Add a binding context that carries action id, tab id, pane id, cwd, and an
  optional payload.
- Add a binding result with explicit completion state and failure code.
- Add a runtime binding registry that can run a production callback by
  `TerminalActionId`.
- Add missing-action detection so production wiring can report incomplete action
  coverage.

## Deliverables

- `example/lib/features/shell/shell_action_runtime_bindings.dart`
- `example/test/shell/shell_action_runtime_bindings_test.dart`

## Acceptance criteria

- Registered bindings receive action context and return structured results.
- Unsupported actions return a failed result instead of throwing.
- Missing production bindings can be listed from a target action set.
- No production UI/runtime behavior changes until the bindings are connected.

## Status

Foundation implemented. Not verified in this session.
