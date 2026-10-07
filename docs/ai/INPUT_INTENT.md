# Local command / AI intent

Reviewed and implemented on 2026-10-03. Automatic routing is available in the
Command Block composer and the AI workspace. It never inspects raw keystrokes
sent to a Normal terminal or a full-screen application.

## What Warp actually does

The [official interaction documentation](https://docs.warp.dev/agents/local-agents/interacting-with-agents/terminal-and-agent-modes/#understanding-auto-detection)
describes detection before submission, a visible destination, detection in both
input surfaces, separate settings, and explicit overrides.

Source reviewed at commit `6398d1e96d56e6e81c561cc3ebfc612c783f7dae`:

- [Input state and policy](https://github.com/warpdotdev/warp/blob/6398d1e96d56e6e81c561cc3ebfc612c783f7dae/app/src/ai/blocklist/input_model.rs):
  manual locks, agent ownership and attachments gate detection; recent history
  and follow-up words precede classification; aliases come from the completion
  context. Explicit operations temporarily suppress detection for 250 ms.
  History matching uses a 0.9 similarity cutoff and excludes command-not-found.
- [Local model pipeline](https://github.com/warpdotdev/warp/blob/6398d1e96d56e6e81c561cc3ebfc612c783f7dae/crates/input_classifier/src/onnx/mod.rs):
  shell and language heuristics precede a bundled BERT-tiny ONNX classifier.
  Inference failure retains the current input type; panic falls back to a
  heuristic. It does not request a remote LLM classification.
- [Model construction](https://github.com/warpdotdev/warp/blob/6398d1e96d56e6e81c561cc3ebfc612c783f7dae/app/src/input_classifier.rs):
  build features select model versions; model-load failure uses a heuristic.
  The repository alone does not establish which version every shipped GUI uses.

The product intent is to reduce mode switching while keeping the next Enter
predictable. Automatic detection changes the destination, never submits input
by itself and never grants approval to an agent's proposed command.

## Trail implementation

`packages/ianvs_terminal/lib/input_intent.dart` is a pure Dart entry point.
Automatic routing requires positive shell evidence. An unknown name goes to the
configured AI backend (LLM or ACP), even if it has flags or looks like a CLI.
No separate remote classification request is made while typing. Enter sends one
normal agent prompt; any proposed terminal write retains the existing approval.

The decision order is:

1. Preserve the current decision during IME composition. Active agent turns,
   pending proposals and attached context retain AI ownership.
2. Honor a manual Command / AI selection for this draft. Clearing/submitting
   resets Auto. A real session/node change resets it; initial or temporarily
   unavailable metadata does not erase the user's selection.
3. Preserve explicit executable paths and shell assignments, and interpret short
   replies in the active agent conversation. Otherwise resolve the first name
   against the **current shell's** PATH executables, builtins, reserved words,
   functions and aliases. Without a match, route to AI.
4. For matched names, distinguish literal shell arguments from a question about
   the command (for example `git status 是什么意思`). The original small local
   language model can identify ambiguous prose, but a low AI score can no longer
   create command evidence. Bare matched names remain commands.
5. Inputs over 8,192 characters go to AI in Auto; manual Command remains available.

The previous implementation let a 334-fixture character/word n-gram model decide
unknown input. Unseen phrases could have no matching features and fall through
to the command-biased intercept. This affected both everyday Chinese and English,
not just the reported phrase. The correction changes that decision boundary;
it does not add the reported phrase to training. Raw command history is now used
only for navigation. A failed attempt cannot make a later draft a command.

Both inputs show Command or AI before Enter; desktop also labels Auto. The menu
offers Auto, Command and AI. Cmd+I / Ctrl+I overrides intent while the input has
focus. Existing terminal-level shortcuts still open/close the AI workspace.
History/completion acceptance remains a draft edit and cannot execute a command.

A Command entered in the AI workspace is an explicit human execution request:
it uses the existing PTY, target guard, shell lease, unique submission and native
receipt. It requires no configured model and makes no inference call. Unknown
receipts block retries; rejected submissions retain the draft. AI-proposed
writes still require their existing separate approval. Manual commands become
context for later questions without inventing assistant tool calls.

Shell-name metadata is excluded from model context. Local zsh and negotiated
SSH Bash/zsh publish name-only snapshots on each prompt. PATH reads and shell
introspection never invoke candidate commands or read function bodies. New names
are committed atomically with the owning prompt epoch; remote frames require
the adapter secret and active node. Returning to another node cannot import the
previous node's names. Removed aliases/functions and newly installed/deleted
PATH executables are refreshed on the next prompt.

Snapshots are bounded to 4,096 names / 64 KiB, transported in chunks of at most
4 KiB. Missing, incomplete or invalid snapshots clear name evidence. Names
outside those bounds, missing metadata on old peers, unusual quoting, or
ambiguous language can still require the visible manual Command override.
This is not a claim of perfect semantic classification or model parity with
Warp. Persistent auto-detection settings and Warp's BERT model are not reproduced.

## Automated acceptance

Permanent checks:

- `packages/ianvs_terminal/test/composer/input_intent_test.dart`: shell-evidence and unknown-input
  cases across everyday conversation, writing and multiple languages, quoting, follow-ups, large input, IME,
  manual overrides, initial metadata and SSH context isolation.
- `example/test/ai/input_intent_routing_test.dart`: no-model execution, stale
  targets, unknown receipts, duplicate Enter, task switching and local metadata.
- AI workspace/composer widget tests: both destinations, manual overrides,
  IME commit without a polling delay, light/dark, desktop and fixed-font phone.
- `example/integration_test/input_intent_acceptance_test.dart`: actual macOS
  app and PTY, isolated HOME, loopback model fixture. Natural language produces
  one proposal and no shell input; a command entered in AI executes once in the
  same terminal with an accepted receipt and no extra model call.
- Native remote-composer tests and `tools/ssh_boundary_lab/composer.py`:
  authenticated/bounded command-name snapshots and six real loopback SSH configurations
  spanning Bash, zsh, emacs/vi keymaps and local-to-SSH multi-hop restoration.

Run shared tests and the AI suite with Flutter. Run the native UI check with
`flutter test --no-pub -d macos integration_test/input_intent_acceptance_test.dart`
from `example`. `TRAIL_INTENT_EVIDENCE` records screenshots and a JSON receipt.
`AI_WORKSPACE_EVIDENCE_DIR` records widget screenshots when running the workspace
tests. `dart run tools/input_intent/benchmark.dart` is the standalone Dart smoke
and inference benchmark; `python3 tools/input_intent/train.py` regenerates weights.

After shared changes run `dart run tools/sync_terminal_core.dart` and its
`--check` mode. Phone evidence is widget-based; no physical iPhone was used for
this change. OS compatibility beyond the recorded macOS host is not implied.

Earlier run (before the evidence-first correction): macOS 27.0.1; 254 AI tests, 138 Composer tests, 4 native remote
unit tests, six SSH configurations and the native GUI scenario passed. Static
analysis, standalone Dart loading, reproducible weights and the core-package
sync check passed. On this host, 1,000 warmed inference samples measured
P50 30 µs / P95 604 µs / P99 694 µs; this is not a phone performance claim.
The regression corpus includes common commands represented in training and is
not a blind model accuracy benchmark. See the
[recorded manifest](evidence/input-intent-20261003/manifest.json), logs and
screenshots in that directory for the exact scope and source hashes.

Evidence-first correction, same host: 168 Composer tests, 254 AI tests, one
inventory unit test, five remote-composer unit tests, five local Composer
integration tests, six SSH configurations and the native GUI scenario passed.
The GUI entered `讲个故事` into the Composer, observed one agent request with no
shell block, then executed a known command exactly once in the original PTY.
Static analysis (including infos), mirror sync and whitespace checks passed.
The updated mixed benchmark measured P50 9 µs / P95 87 µs / P99 189 µs.
See the [correction manifest](evidence/input-intent-20261003/evidence-first/manifest.json)
and [actual Composer screenshot](evidence/input-intent-20261003/evidence-first/composer-story-to-ai.png).
The Development app was built for isolated acceptance; the installed daily app
was not replaced. No Terminal-Bench rerun or physical iPhone claim is made here.
