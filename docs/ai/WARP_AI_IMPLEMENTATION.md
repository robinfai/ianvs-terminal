# Terminal AI

Goal: consult Warp's documentation, provide a mock LLM API, configure the client's
API key and endpoint, and implement natural-language input, command correction,
and AI interaction with vi/vim/k9s and other terminal applications.

## Reference decisions

Reviewed 2026-10-01:

| Official reference | Relevant behavior | Trail implementation |
| --- | --- | --- |
| [Terminal and Agent modes](https://docs.warp.dev/agents/local-agents/interacting-with-agents/terminal-and-agent-modes/) | Separate direct terminal input from a conversation; explicit switching and contextual entry points. | Composer and AI input share local rules, session evidence and an original bilingual classifier, with visible destinations and per-draft manual overrides; see [input intent](INPUT_INTENT.md). The terminal's AI button and Cmd+I (Ctrl+I elsewhere) also work in Normal/TUI mode. |
| [Blocks as Context](https://docs.warp.dev/agents/local-agents/agent-context/blocks-as-context/) | A block can supply the command and output for an error-related prompt. | Block menu “Correct with AI” / “Ask AI about this block”; the panel can correct the most recent failed command. Context includes the native exit code, cwd and unfiltered output tail. |
| [Command Corrections](https://docs.warp.dev/terminal/entry/command-corrections/) | Warp's separate correction feature uses thefuck rules to suggest changes after errors. | Trail uses the configured LLM for correction. The deterministic mock has a few explicit fixture rules; these are not represented as a general LLM or a port of thefuck. |
| [Full Terminal Use](https://docs.warp.dev/agents/capabilities/full-terminal-use/) | The agent sees the live buffer and interacts with the same PTY, including editors and REPLs. Users approve proposals and can take over. | `read_screen`, `run_command`, `send_keys` tools. Each writing action is previewed and approved under the selected manual/smart policy; interactive keys still need manual confirmation. The panel overlays the existing TUI; it does not replace it with a command block or launch another shell. |
| [Custom inference endpoint](https://docs.warp.dev/agents/inference/custom-inference-endpoint/) | OpenAI Chat Completions compatibility; configurable model, endpoint and credential stored on the device. Warp routes requests through its backend. | Trail's harness runs in the client and connects directly to the selected endpoint, so loopback and LAN endpoints work. Configuration stays outside profile/data synchronization. Production uses Keychain/secure storage; the isolated macOS development client uses a private local file to avoid Keychain prompts. |

## How to use

1. Start the development mock from the repository root:

   ```sh
   python3 tools/mock_llm/server.py
   ```

2. In Trail, open **Settings → General → AI** or **AI → settings**. Choose
   **Local mock**, **Test connection**, then **Save**.

   - Endpoint: `http://127.0.0.1:8787/v1`
   - API Key: `trail-local-mock` (a public fixture value, not a real credential)
   - Model: `trail-mock`

3. In Command Blocks mode, enter “请列出当前目录文件” or “show me all files”.
   Composer indicates **Ask AI**. Enter opens the conversation; the prose is
   not submitted as a shell command. Ambiguous wording can be sent explicitly
   through the Composer menu or the AI panel.
4. After `ls --not-a-real-option`, open the failed block's menu and select
   **Correct with AI**. Review the proposal before running it.
5. Start `vi file.txt` / `vim file.txt`, open AI, and ask
   `在 vim 第一行插入 "Hello Trail" 并保存`. The mock first proposes editor
   keystrokes and then, after observing the result, proposes saving the file.
6. In an existing k9s session, ask `在 k9s 中查看 pods`. The mock navigates the
   real TUI using keys, then reports the returned screen.
7. **Take over**, close the panel, or type directly into the terminal to revoke
   pending work. In-flight network requests are closed and no further keys are
   sent. Already submitted input cannot be undone by cancellation.
8. **Continue task** resumes a paused or recoverable failed turn with fresh
   terminal context and the original task constraints. It does not itself
   resubmit a command. Any new writing proposal still requires approval.
   The fixed status area distinguishes thinking, waiting, approval and pause;
   its arrow locates the latest proposal or reply while preserving your reading
   position until you choose to jump. Short panels put status in the header.

For iPhone, run the mock with `--host 0.0.0.0` on the Mac and enter the Mac's LAN
address in the endpoint field. `127.0.0.1` on the phone refers to the phone.
Real providers use the same configuration screen and tool protocol; model
quality and support for function calls belong to the chosen provider.

## Implementation boundaries

- `example/lib/features/ai/ai_api_client.dart`: actual HTTP client; bounded
  response and timeout; cancels the socket; never forwards credentials through
  redirects or includes provider error bodies in the UI.
- `ai_settings.dart`: one atomic stored value for endpoint/key/model, using the
  environment's production secure store or isolated development file store.
  Conversation drafts, terminal context and proposals stay session-local in memory.
- `terminal_ai_controller.dart`: conversation/tool-result loop and approval
  state. Read-only screen observations may continue automatically; every agent
  write waits for the user's approval. Explicit human commands in the AI input
  use the same guarded PTY directly, without inference. See [input intent](INPUT_INTENT.md).
  A turn is limited to 24 inference steps.
- `read_screen` accepts optional `wait_ms` (integer, 0–30,000). It waits for a
  command/shell/context transition and returns early for a ready shell or an
  alternate-screen application. Its observation receipt separates wait expiry
  from command failure. Cancellation ends the wait without sending input.
  Duplicate unchanged observations are compacted as complete call/result pairs;
  distinct output is retained until the general history size bound is reached.
  Compaction preserves human requests and explicitly selected block context.
- `terminal_ai_runtime.dart`: uses the existing runtime and native composer
  lease. It does not retry an uncertain command submission. The approval guard
  contains the session, SSH context, cwd, shell state/lease, running command,
  native block identity and manual-input generation.
- `terminal.live_screen`: reads the active native grid, cursor and dimensions
  without altering scroll position, folded blocks or frame-damage delivery.
  Alternate-screen applications expose their actual active screen.
- `send_keys` represents control keys explicitly and respects the terminal's
  application-cursor mode. Tool proposals cannot encode hidden ESC bytes inside
  an ostensibly plain-text insertion. A named Esc is sent separately with a
  120 ms pause before the next key, so TUI decoders can distinguish it from an
  Alt-modified character; cancellation and session guards are checked between
  writes. This accounts for the escape-expiry behavior in
  [tcell's input loop](https://github.com/gdamore/tcell/blob/v2.8.1/tscreen.go#L1734-L1787).
- Terminal content is treated as untrusted data in the system instructions;
  proposed writes are visible and require approval. Requests include a bounded
  current-screen snapshot plus the selected/latest command's output tail, not
  an entire unbounded scrollback or a recursive project upload.
- Block context includes native identity, running state, exit status, total
  line count, zero-based output range (exclusive end), eviction and truncation.
  The tail remains bounded to 160 lines/16,000 characters. Truncation is exposed
  to the model; this is not a full-history or paged block retrieval tool.

## Verification entry points

```sh
flutter test --no-pub test/ai                       # from example/
cargo test --locked --manifest-path native/core/Cargo.toml --lib live_screen_tests
PROFILE=debug tools/build_core.sh
python3 tools/mock_llm/kube_fixture.py \
  --kubeconfig /private/tmp/trail-ai-acceptance/kubeconfig.json
# Keep both mock servers running, then from example/:
flutter test --no-pub -d macos integration_test/terminal_ai_acceptance_test.dart \
  --dart-define=AI_EVIDENCE_DIR=/private/tmp/trail-ai-acceptance/screenshots
```

The k9s fixture is a loopback-only Kubernetes API with read-only Pod/Namespace
data; the test launches the installed k9s executable with `--readonly` and an
explicit fixture kubeconfig. It does not contact an existing cluster. The LLM
mock's optional `--audit` log records request counts, model and message roles;
it does not persist prompts, terminal contents or API keys.

Completion requires the native integration flow to prove real shell output,
a failing command's correction, file contents saved by **both vi and vim**,
and a Pod visible in **real k9s** after the approved key sequence. Widget/unit
tests alone do not prove those outcomes. See the acceptance record for actual
test results and platform coverage in [ACCEPTANCE.md](ACCEPTANCE.md).

For the waiting/recovery/history flow fixture, start
`python3 tools/mock_llm/block_flow_fixture.py --audit /tmp/trail-block-flow.jsonl`
instead of `server.py`. Use the same Local mock settings. Start a new conversation
for each scenario: `流程验收` proposes a 12-second command; `流程验收：暂停恢复`
proposes a 30-second command. `历史阅读验收` returns 80 lines, after which
`流程验收：验证审批定位` proposes a command below the history. Review, then reject
that proposal to verify that locating approval does not execute it. This fixture
never runs terminal commands itself and is not an inference-quality benchmark.

Smart review is an independent Trail policy extension, not a claim of Warp
implementation parity. See [SMART_APPROVAL.md](SMART_APPROVAL.md) for its
authorization scope, stale-decision protection and actual validation.
