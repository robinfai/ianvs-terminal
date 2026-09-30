# Terminal AI acceptance — 2026-10-01

The native macOS integration test passed with the actual Trail development app,
the Rust PTY backend, a real local HTTP mock, and the installed vi/vim/k9s
executables. The model is deterministic; terminal execution and screen/file
observations are real.

## Environment and configuration

- macOS 27.0.1 (26A434), Apple Silicon. This records one tested OS, not the
  entire supported Apple release window.
- `/bin/zsh`, `/usr/bin/vi`, `/usr/bin/vim`; k9s 0.50.16, commit
  `3c37ca2197ca48591566d1f599b7b3a50d54a408`.
- Endpoint `http://127.0.0.1:8787/v1`, model `trail-mock`, public fixture API key
  `trail-local-mock`. Configured through the actual settings UI, checked with a
  real HTTP request, and read back from secure storage. The final run used
  `AI_PERSIST_CONFIGURATION=true` to retain this configuration for the tested
  development client. No credential is synchronized with terminal profiles.
- Shell HOME, files, preferences and kubeconfig were isolated. Real k9s used a
  read-only loopback Kubernetes fixture; it did not connect to a user cluster.
- Light appearance for settings/shell/editor cases; dark appearance for k9s,
  whose default skin assumes a dark terminal background.

## Observed outcomes

| Flow | Assertion / observed result |
| --- | --- |
| Natural-language Composer input | “请列出当前目录文件” opened an AI proposal. No shell block existed before approval. Approval executed `ls -la`, showing the real `ai-visible-file.txt`. |
| Failed-command correction | Real `ls --not-a-real-option` produced a nonzero exit status. AI received command/output/cwd/status, proposed `ls`, and the approved correction exited with status 0. |
| vi | The actual file remained `original\n` before approval. Approved insertion and save produced `Trail vi verified\noriginal\n`; a subsequent approved `:wq` returned to the shell. |
| vim | The same flow produced `Trail vim verified\noriginal\n` in the actual file, then returned to a ready shell. Opening AI preserved the full terminal viewport size in both editors. |
| k9s | After the actual namespace view loaded, approved Esc / `:pods` / Enter opened the real Pod view containing `trail-ai-pod`. |
| Takeover | A subsequent namespace proposal was revoked by Take over. No namespace navigation was sent and the Pod screen remained visible. |

The test explicitly waits for the k9s alternate screen and resource heading;
matching a word in the echoed launch command is not a readiness signal. Native
text-input focus is settled before follow-up conversation entry.

## Checks

- AI protocol/controller tests: 16 passed. Includes real HTTP authorization and
  UTF-8 request length, redirect rejection, cancellation, stale SSH context,
  takeover during execution, secure-store errors, and explicit key validation.
- AI widget tests: 7 passed. Includes natural-language routing, command override,
  macOS/iOS light/dark at 320 × 260 with 2× text scaling, settings, and reopening
  a conversation at the latest message without pulling subsequent reading back.
- Shared Composer, blocks, JSON client and runtime regression tests: 345 passed.
- Native active-screen tests: 2 passed; active alternate buffer, cursor/mode,
  primary-buffer preservation, scrollback exclusion and carriage-return output.
- Actual macOS integration: 1 passed; final run completed in 16 seconds after
  the build. [Native test log](evidence/native-acceptance.txt).
- Targeted Flutter static analysis: no issues. `git diff --check` passed.
- `dart run tools/sync_terminal_core.dart --check`: generated sources current.

The existing runner emitted a Material icon configuration warning and could
not foreground the test app through `open`. The integration binding still
rendered frames, captured screenshots and completed every assertion.

## Evidence

- [Configured connection](evidence/01-configured-connection.png)
- [Natural-language approval](evidence/02-natural-language-approval.png)
- [Error correction](evidence/04-error-correction.png)
- [Saved vi file](evidence/05-vi-saved.png)
- [Saved vim file](evidence/05-vim-saved.png)
- [Real k9s Pod view](evidence/07-k9s-pods.png)

## Coverage limits

This AI change was not installed on an iPhone or over the user's existing local
Trail installation during this acceptance. iOS coverage here is widget-level;
real-device networking, keyboard behavior and secure storage need a device run.
No external paid model was tested. The OpenAI-compatible protocol is exercised
over real HTTP; inference quality and provider-specific tool support remain
dependent on the configured model.
