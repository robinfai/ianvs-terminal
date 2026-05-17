# Local Terminal Milestone Implementation Status

目的：跟踪 `LOCAL_TERMINAL_P0..P5_EXECUTION_PLAN_2026-05.md` 的实际推进状态，避免把“模型层完成”误判为“产品能力完成”。

## Status Legend

- `DONE`: 计划项已接入到可用产品路径并完成验证。
- `WIRED`: 已接入到产品 UI/runtime 路径，但尚未完成验证。
- `FOUNDATION/WIRED`: 部分核心路径已接入，仍有 foundation-only 或 advanced follow-up 范围。
- `FOUNDATION`: schema / model / repository / adapter 已建立，但尚未完整接入 UI/runtime。
- `TODO`: 尚未实现。

## P0 Documentation And Boundaries

| Area | Status | Evidence | Remaining |
| --- | --- | --- | --- |
| Local-first roadmap boundary | FOUNDATION | `LOCAL_TERMINAL_FEATURE_PLAN.md`, P0-P5 execution plans | 需要后续实现持续遵守非目标 |
| SSH/remote/SFTP/serial exclusion | FOUNDATION | P0-P5 plans and task Non-goals | 需要 runtime schema/UI 持续拒绝 remote-only fields |

## P1 Action And Config Foundation

| Area | Status | Evidence | Remaining |
| --- | --- | --- | --- |
| Action registry foundation | WIRED | `T-078`, `T-079`, `T-095`, `T-230` | 需要 analyze/tests/manual 验证所有 handlers/UI 路径 |
| Keybinding metadata | FOUNDATION/WIRED | `T-079`, `T-230` | shortcut production dispatch 已接入；用户配置覆盖和冲突诊断仍需验证 |
| Keybinding resolver | FOUNDATION/WIRED | `T-082`, `T-083`, `T-122`, `T-123`, `T-230` | 需要验证 shortcut bridge、焦点消费和配置冲突行为 |
| Local config schema | FOUNDATION | `T-080` | 需要接入 session bootstrap |
| Local config repository/migration | FOUNDATION | `T-081`, `T-102`, `T-124`, `T-125` | 需要接入 session bootstrap runtime |
| Action availability diagnostics | WIRED | `T-098`, `T-100`, `T-108`, `T-202`, `T-230` | 需要 widget/manual 验证 command menu diagnostics 和 disabled reasons |
| Unified action pipeline | WIRED | `T-114`, `T-115`, `T-116`, `T-117`, `T-118`, `T-119`, `T-136`, `T-137`, `T-138`, `T-230` | 需要 focused shell action tests 和 fallback-path 验证 |
| Command menu adapter/model | WIRED | `T-120`, `T-121`, `T-230` | 需要验证现有 command menu widget 的显示、执行和错误反馈 |

## P2 Local Workspace

| Area | Status | Evidence | Remaining |
| --- | --- | --- | --- |
| Workspace/tab/pane model | WIRED | `T-084`, `T-227`, `T-228`, `T-229`, `T-231` | 需要 multipane/manual 验证 |
| Split/focus/resize/swap/zoom model | WIRED | `T-086`, `T-227`, `T-228`, `T-229` | 需要 focus fallback、resize bounds、swap/zoom 行为验证 |
| Close/reopen pane/tab model | WIRED | `T-084`, `T-096`, `T-231` | 需要 close-last-pane/tab 和 reopen closed tab 验证 |
| Same-cwd intent | WIRED | `T-087`, `T-230` | 需要 shell integration cwd 可用/不可用路径验证 |
| Layout serialization/repository | FOUNDATION | `T-085`, `T-099`, `T-134` | 需要 restore trigger 和 schema version |
| Workspace action reducer | FOUNDATION/WIRED | `T-109`, `T-227`, `T-228`, `T-229`, `T-231` | core UI side effects 已接入；reducer-to-UI 一致性仍需验证 |

## P3 Shell Productivity

| Area | Status | Evidence | Remaining |
| --- | --- | --- | --- |
| Shell integration gates | FOUNDATION/WIRED | `T-088`, `T-098`, `T-208`, `T-217` | 需要真实 feature availability 和 disabled-state 验证 |
| Prompt navigation state | WIRED | `T-088`, `T-101`, `T-131`, `T-208` | 需要 viewport scroll/action handler 验证 |
| Command output range | WIRED | `T-088`, `T-101`, `T-131`, `T-216` | 需要 selection/copy runtime 范围验证 |
| Recent commands/directories | WIRED | `T-092`, `T-101`, `T-112`, `T-131`, `T-135`, `T-217` | 需要 picker/insert behavior 和 lifecycle 验证 |
| Search/block model | FOUNDATION/WIRED | `T-089`, `T-208` | normal search 已接入；block-scoped search/highlight 仍需验证/后续 UI |
| Read-only guard model | WIRED | `T-088`, `T-098`, `T-232` | 需要 terminal input/paste/mouse/focus-report 全路径验证 |
| Productivity action reducer | FOUNDATION/WIRED | `T-110`, `T-208`, `T-216`, `T-217`, `T-232`, `T-233`, `T-235`, `T-236`, `T-237` | core side effects 已接入；reducer-to-runtime 一致性仍需验证 |

## P4 Clipboard, Notifications, Hotkey Window

| Area | Status | Evidence | Remaining |
| --- | --- | --- | --- |
| Clipboard/paste policy | FOUNDATION/WIRED | `T-090`, `T-106`, `T-129`, `T-210`, `T-211`, `T-232` | paste/advanced paste/history/read-only core paths 已接入；confirmation UI 和 bypass 验证仍需完成 |
| Paste history policy | WIRED | `T-093`, `T-106`, `T-133`, `T-210` | 需要 repository/UI limit、disabled-state 和 confirmation path 验证 |
| Notification rules/dispatch | WIRED | `T-090`, `T-105`, `T-130`, `T-226`, `T-238` | 需要 system notification、focus policy、preference persistence 验证 |
| Hotkey window config/failure state | FOUNDATION/WIRED | `T-090`, `T-097`, `T-230` | action alias 已接入；`WindowBridge` failure mapping and visible UI 仍需验证/硬化 |
| Policy action reducer | FOUNDATION/WIRED | `T-111`, `T-226`, `T-238` | 部分真实 runtime 已接入；policy reducer 到 runtime 的完整一致性仍需验证 |

## P5 Visual And Advanced Local Features

| Area | Status | Evidence | Remaining |
| --- | --- | --- | --- |
| Theme preset/light-dark pair | FOUNDATION/WIRED | `T-091`, `T-103`, `T-132`, `T-223` | theme picker intent 已接入；import/export/runtime apply 仍需验证/后续 |
| Profile theme override | FOUNDATION | `T-094` | 需要 profile/config merge |
| Pane visual policy | FOUNDATION/WIRED | `T-091`, `T-227`, `T-229` | pane sizing/zoom 已接入；renderer/UI policy apply 仍需验证 |
| Layout templates | FOUNDATION/WIRED | `T-091`, `T-113`, `T-126`, `T-127`, `T-224` | two-pane apply 已接入；save/load/template picker 仍需后续 |
| Timestamps/command pane | FOUNDATION | `T-094` | 需要 shell integration/runtime UI |
| Scrollback export | WIRED | `T-094`, `T-104`, `T-128`, `T-233`, `T-237` | 需要 historical content、fallback、destination policy 和 failure messaging 验证 |
| Graphics/image storage policy | FOUNDATION | `T-094`, `T-107` | 需要 optional cache implementation and renderer decision alignment |
| Visual action reducer | FOUNDATION/WIRED | `T-115`, `T-223`, `T-224`, `T-233`, `T-235`, `T-236`, `T-237` | core side effects 已接入；advanced visual scope 和验证仍需完成 |

## Completion Audit

Current conclusion: **not complete**.

The milestone plans now have broad foundation coverage across schema, models,
repositories, reducers, policy decisions, diagnostics, UI adapters, dispatch
planning, side-effect executor protocols, and a unified action pipeline. The
core required local-terminal runtime/UI baseline is now broadly wired, and the
2026-05-16 automated loop has passing evidence for formatting, static analysis,
completion diagnostics, P1, cross-milestone wiring, P2, P3, P4, P5,
verification-evidence focused suites, broader project tests, and macOS
integration smoke/real-PTY acceptance. The objective “推进完成所有计划” still
cannot be marked complete until manual gates pass and the captured results are
converted into canonical verification evidence.

Historical task log below records when foundation slices were added. Some older
entries still describe their original foundation-stage remaining work; the
current status is the P0-P5 overview table above plus the T-230, T-239, T-240,
T-241, T-242, T-243, T-244, T-245, T-246, T-247, T-248, T-249, T-250, T-251,
T-252, T-253, T-254, T-255, T-256, T-257, T-258, T-259, T-260, T-261, T-262,
T-263, T-264, T-265, T-266, T-267, T-268, T-269, T-270, T-271, T-272, T-273, T-274, T-275, T-276, T-277, T-278, T-279, T-280, T-281, T-282, T-283, T-284, T-285, T-286, T-287, T-288, T-289, T-290, T-291, T-292, T-293, T-294, T-295, T-296, T-297, and T-323 through T-328 records.

- T-140 Shell command menu diagnostics: FOUNDATION. Added command menu availability and runtime-error diagnostics for UI consumption; production ShellScreen wiring and verification were pending at creation; superseded by final verified closure.

- Competitor coverage matrix: FOUNDATION. Added `docs/LOCAL_TERMINAL_COMPETITOR_COVERAGE_MATRIX_2026-05.md` to map competitor-derived local terminal capabilities to P0-P5, tasks, implementation artifacts, and remaining wiring/verification gaps.

- T-141 Shell action runtime production bindings: FOUNDATION. Added structured production binding context/result/failure codes and missing binding detection; real ShellScreen/SessionController registrations were pending at creation; superseded by ShellScreen production wiring evidence.

- T-142 Local terminal production wiring checklist: CREATED. Added `docs/LOCAL_TERMINAL_PRODUCTION_WIRING_CHECKLIST_2026-05.md` to track the remaining ShellScreen, SessionController, policy, visual, workspace, and verification gates.

- T-143 Shell action runtime binding audit: FOUNDATION. Added missing-required and unplanned-registered production binding audit support; the supported production action set still needs to be defined during ShellScreen wiring.

- T-144 Shell action production action set: FOUNDATION. Added default required/optional production action-set resolution plus binding-audit integration; unknown planned action names and missing required bindings still need to be reconciled during production wiring.

- T-145 Shell action production binding builder: FOUNDATION. Added action-name callback resolution into audited runtime bindings; real ShellScreen/SessionController callback registration remains pending.

- T-146 Shell action production binding diagnostics: FOUNDATION. Added blocking/advisory diagnostics for unknown action names, missing required bindings, and unplanned registered bindings; production UI/debug rendering remains pending.

- T-147 Shell action production callbacks: FOUNDATION. Added typed callback fields for production action handler registration; real ShellScreen/SessionController callback population remains pending.

- T-148 Shell action production wiring state: FOUNDATION. Added a single state object for typed callbacks, runtime bindings, audit results, and blocking diagnostics; real ShellScreen/SessionController instantiation remains pending.

- T-149 Shell action production executor: FOUNDATION. Added a readiness-gated production action executor with structured callback failure capture; ShellScreen/runtime dispatch integration remains pending.

- T-150 Shell action production runtime adapter: FOUNDATION. Added a runtime-facing adapter from typed production callbacks to `ShellActionBindingContext -> ShellActionBindingResult`; actual ShellScreen/runtime dispatch connection remains pending.

- T-151 Shell action production wiring report: FOUNDATION. Added JSON-compatible production wiring readiness and diagnostics reporting; real ShellScreen/runtime report exposure remains pending.

- T-152 Shell action production dispatch report: FOUNDATION. Added JSON-compatible single-action dispatch reporting with readiness, completion, failure code, and message; real runtime emission remains pending.

- T-153 Shell action production audit snapshot: FOUNDATION. Added timestamped JSON-compatible production wiring and dispatch audit snapshot; real ShellScreen/runtime exposure remains pending.

- T-154 Shell action production closure manifest: FOUNDATION. Added a closure manifest requiring ready wiring, passing tests, and passing static analysis before P1 action wiring can close; real verification evidence remains pending.

- T-155 Local workspace production callbacks: FOUNDATION. Added typed production callback/wiring contract for tab, pane, split, focus, resize, swap, zoom, and layout operations; real ShellScreen workspace callback population remains pending.

- T-156 Shell productivity production callbacks: FOUNDATION. Added typed production callback/wiring contract for prompt navigation, command output, recent directory, search, read-only, and scrollback operations; real ShellScreen/SessionController/search/scrollback callback population remains pending.

- T-157 Local terminal policy production callbacks: FOUNDATION. Added typed production callback/wiring contract for clipboard, paste, notification, and hotkey-window operations; real paste/clipboard/notification/WindowBridge callback population remains pending.

- T-158 Local terminal visual production callbacks: FOUNDATION. Added typed production callback/wiring contract for theme, layout template, export, pane visual policy, graphics storage, timestamps, command pane, and scrollback editor operations; real settings/UI/export/runtime callback population remains pending.

- T-159 Local terminal production wiring manifest: FOUNDATION. Added a cross-milestone closure manifest for P1-P5 wiring readiness, test status, static analysis status, and blockers; real verification evidence remains pending.

- T-160 Local terminal domain wiring summary: FOUNDATION. Added conversion from P2-P5 production callback wiring objects into cross-milestone manifest inputs with missing operations preserved as blockers; real callback population and verification were pending at creation; superseded by current verified backlog evidence.

- T-161 Local terminal production wiring manifest builder: FOUNDATION. Added a builder that combines the P1 closure manifest and P2-P5 domain wiring summaries into the cross-milestone manifest; real production summaries and verification evidence were pending at creation; superseded by current verified completion evidence.

- T-162 Local terminal P0 boundary closure manifest: FOUNDATION. Added P0 documentation/boundary closure state and connected it to the cross-milestone manifest builder; real documentation review and verification evidence were pending at creation; superseded by verified P0 boundary evidence.

- T-163 Local terminal completion audit checklist: CREATED. Added `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` to map the active objective to concrete evidence requirements and explicitly record remaining production wiring and verification blockers.

- T-164 through T-169 real wiring backlog: WIRED / UNVERIFIED. Added `docs/LOCAL_TERMINAL_REAL_WIRING_BACKLOG_2026-05.md` and six tasks for P1-P5 production wiring plus final verification/closure. T-164 through T-168 now have implemented-but-unverified evidence; T-169 verification remains pending.

- T-170 Local terminal action domain router: FOUNDATION. Added routing from workspace/productivity/policy/visual production wiring into shell action callbacks while preserving missing-operation blockers; real ShellScreen domain callback population remains pending.

- T-171 Local terminal production wiring bundle: FOUNDATION. Added a single assembly point for P0 boundary evidence, P2-P5 domain callbacks, P1 action routing, and the cross-milestone manifest; real ShellScreen/SessionController/settings/export/runtime callback population remains pending.

- T-172 Local terminal completion evidence report: FOUNDATION. Added a final evidence report that combines the production wiring bundle and real wiring backlog statuses; final backlog verification and command/manual evidence are recorded.

- T-173 Local terminal real wiring backlog evidence: FOUNDATION / WIRED. Added a builder that converts T-164 through T-169 evidence into completion backlog items. T-239 keeps the conservative pending path; `currentVerified` now records T-164 through T-169 as verified when latest passed verification evidence is supplied.

- T-174 Local terminal ShellScreen wiring spec: CREATED. Added `docs/LOCAL_TERMINAL_SHELLSCREEN_WIRING_SPEC_2026-05.md` as the concrete callback map for ShellScreen/SessionController/settings/export/runtime wiring; required baseline callback population is represented by the verified production wiring evidence.

- T-175 Local terminal verification evidence: FOUNDATION. Added a verification evidence model for tests, static analysis, formatting, and manual/integration gates; no verification commands have been run yet.

- T-176 Local terminal verification backlog bridge: FOUNDATION. Connected `LocalTerminalVerificationEvidence` to T-169 backlog evidence so required verification gates block final closure until explicitly passed.

- T-177 Local terminal default verification gates: FOUNDATION. Added the default pending required verification gate set and corrected missing-gate handling so omitted gates cannot pass closure accidentally.

- T-178 Local terminal current completion state: FOUNDATION / WIRED. Added a conservative current completion state builder. T-239 now feeds it current implemented-but-unverified backlog evidence plus pending verification gates.

- T-179 Local terminal completion summary: FOUNDATION. Added readable completion summary output for blocked milestones, blocked real-wiring backlog items, and blocked verification gates; real production wiring and verification were pending at creation; superseded by final current-state closure.

- T-180 Local terminal completion controller: FOUNDATION. Added a controller facade for current completion state, readable summary, JSON output, and `canCloseObjective`; real production wiring and verification were pending at creation; superseded by final current-state closure.

- T-181 Local terminal completion diagnostics view model: FOUNDATION. Added a UI-friendly diagnostics model for blocked completion state; real production wiring and verification were pending at creation; superseded by final current-state closure.

- T-182 Local terminal completion diagnostics actions: FOUNDATION. Added read-only diagnostic action items for blocked completion state; real production wiring and verification were pending at creation; superseded by final current-state closure.

- T-183 Local terminal completion menu model: FOUNDATION. Added a menu-friendly read-only model for blocked completion diagnostics; real production wiring and verification were pending at creation; superseded by final current-state closure.

- T-184 Local terminal completion command menu adapter: FOUNDATION. Added grouped read-only command-menu section data for blocked completion diagnostics; real production wiring and verification were pending at creation; superseded by final current-state closure.

- T-185 Local terminal completion diagnostics bundle: FOUNDATION. Added a single read-only diagnostics entry point for completion summary, menu model, command-menu sections, and JSON output; real production wiring and verification were pending at creation; superseded by final current-state closure.

- T-186 Local terminal completion shell command menu diagnostics: FOUNDATION. Added an adapter from completion menu entries to shell command menu disabled-reason diagnostics without fabricating action ids; real production wiring and verification were pending at creation; superseded by final current-state closure.

- T-187 Local terminal verification command plan: CREATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_COMMAND_PLAN_2026-05.md` to map required verification gates to command/manual evidence; no verification has been run yet.

- T-188 Local terminal shell UI wiring facade: FOUNDATION. Added a read-only UI-facing facade for completion evidence, summary, diagnostics, action group, and menu state; real ShellScreen production wiring remains pending.

- T-189 Local terminal shell UI wiring snapshot: FOUNDATION. Added a timestamped read-only shell UI wiring snapshot with blocked counts, summary, and facade JSON; real ShellScreen production wiring remains pending.

- T-190 Local terminal Shell UI wiring handoff: CREATED. Added `docs/LOCAL_TERMINAL_SHELL_UI_WIRING_HANDOFF_2026-05.md` to guide future ShellScreen wiring toward bundle/facade/snapshot/diagnostics entry points; real production wiring remains pending.

- T-191 Local terminal Shell UI wiring exports: FOUNDATION. Added a high-level export surface for future ShellScreen wiring and diagnostics integration; real production wiring remains pending.

- T-192 Local terminal completion diagnostics panel: FOUNDATION. Added a reusable read-only Flutter panel for blocked completion diagnostics and exported it through the Shell UI wiring surface; real ShellScreen integration remains pending.

- T-193 Local terminal completion diagnostics presentation: FOUNDATION. Added a read-only presentation model for choosing how blocked completion diagnostics should display in future ShellScreen UI; real ShellScreen integration remains pending.

- T-194 Local terminal completion diagnostics presentation resolver: FOUNDATION. Added a read-only resolver for completion diagnostics display mode and exported it through the Shell UI wiring surface; real ShellScreen integration remains pending.

- T-195 Local terminal verification evidence recorder: FOUNDATION. Added an immutable recorder for verification command/manual outcomes and exported it through the Shell UI wiring surface; no verification has been run yet.

- T-196 Local terminal verification evidence batch recording: FOUNDATION. Added batch gate recording for T-169 verification evidence; no verification commands have been run yet.

- T-197 Local terminal verification plan records: FOUNDATION. Added default pending verification records for every required gate and exported them through the Shell UI wiring surface; no verification has been run yet.

- T-198 Local terminal pending completion snapshot factory: FOUNDATION. Added a default blocked snapshot factory that initializes verification evidence from command-plan records; real production wiring and verification were pending at creation; superseded by final current-state closure.

- T-199 Local terminal test targets: CREATED. Added `docs/LOCAL_TERMINAL_TEST_TARGETS_2026-05.md` to map P0-P5 artifacts to focused test groups and evidence-recording rules; no test command has been run yet.

- T-200 Local terminal manual verification template: CREATED. Added `docs/LOCAL_TERMINAL_MANUAL_VERIFICATION_TEMPLATE_2026-05.md` for T-169 manual/integration gate evidence; no manual gate has been run yet.

- T-201 Local terminal evidence recording runbook: CREATED. Added `docs/LOCAL_TERMINAL_EVIDENCE_RECORDING_RUNBOOK_2026-05.md` to define how real wiring, command output, and manual results become final completion evidence; no evidence has been recorded yet.

- T-202 ShellScreen completion diagnostics first patch: WIRED / UNVERIFIED. Added `docs/LOCAL_TERMINAL_SHELLSCREEN_PATCH_CHECKLIST_2026-05.md`; ShellScreen now exposes completion diagnostics, but verification remains pending.

- T-245 Current completion state wiring evidence regression: TEST ADDED / NOT RUN. Added focused coverage that keeps T-164 through T-168 implemented-but-unverified and T-169 blocked by verification.

- T-246 Real wiring backlog current evidence regression: TEST ADDED / NOT RUN. Added direct coverage for `LocalTerminalRealWiringBacklogEvidence.currentImplementedUnverified` so current wiring evidence cannot regress to pending placeholders.

- T-247 Pending completion snapshot current evidence regression: TEST ADDED / NOT RUN. Added snapshot-factory coverage so UI diagnostics surfaces expose current implemented-but-unverified evidence through the facade layer.

- T-248 Shell UI wiring facade current evidence regression: TEST ADDED / NOT RUN. Added facade-report coverage so the shell UI wiring facade preserves current implemented-but-unverified backlog evidence.

- T-249 Production action set baseline regression: TEST ADDED / NOT RUN. Added default action-set coverage for the current P1 production baseline and key alias mappings.

- T-250 Production callback baseline regression: TEST ADDED / NOT RUN. Added typed callback surface coverage showing the current default P1 action baseline can be satisfied without missing required bindings.

- T-251 Production wiring state baseline regression: TEST ADDED / NOT RUN. Added wiring-state readiness coverage for the current default P1 action baseline with matching typed callbacks.

- T-252 Production executor baseline regression: TEST ADDED / NOT RUN. Added executor-layer coverage for representative alias-backed P1 baseline actions when production wiring is ready.

- T-253 Production runtime adapter baseline regression: TEST ADDED / NOT RUN. Added runtime-adapter external-executor coverage for representative alias-backed P1 baseline actions when production wiring is ready.

- T-254 Production report snapshot baseline regression: TEST ADDED / NOT RUN. Added wiring-report and audit-snapshot coverage showing the current default P1 baseline serializes as ready and clean.

- T-255 Production closure manifest baseline regression: TEST ADDED / NOT RUN. Added closure-manifest coverage showing ready default P1 wiring still cannot close without tests and static analysis evidence.

- T-256 Workspace production callback baseline regression: TEST ADDED / NOT RUN. Added core P2 workspace callback baseline coverage while keeping advanced layout/workspace gaps visible.

- T-257 Productivity production callback baseline regression: TEST ADDED / NOT RUN. Added core P3 productivity callback baseline coverage while keeping advanced command-block/output-export gaps visible.

- T-258 Policy production callback baseline regression: TEST ADDED / NOT RUN. Added core P4 policy callback baseline coverage while keeping advanced notification/hotkey gaps visible.

- T-259 Visual production callback baseline regression: TEST ADDED / NOT RUN. Added core P5 visual callback baseline coverage while keeping advanced theme/layout/export/graphics/UI gaps visible.

- T-260 Domain wiring summary core baseline regression: TEST ADDED / NOT RUN. Added cross-domain summary coverage for P2-P5 core-ready baselines and advanced gap reporting.

- T-261 Production wiring bundle core baseline regression: TEST ADDED / NOT RUN. Added production wiring bundle coverage for P2-P5 core baseline assembly, routed action execution, and verification blockers.

- T-262 Production manifest builder core baseline regression: TEST ADDED / NOT RUN. Added production manifest builder coverage for P2-P5 core summaries and verification blockers.

- T-263 Completion evidence report required backlog gate: TEST ADDED / NOT RUN. Tightened final completion evidence so all T-164 through T-169 backlog task ids must be present and verified before objective closure.

- T-264 Missing required backlog diagnostics: TEST ADDED / NOT RUN. Added summary and diagnostics view model coverage so missing required backlog task ids are visible to UI and text diagnostics.

- T-265 Missing backlog command menu diagnostics: TEST ADDED / NOT RUN. Added downstream diagnostics coverage so missing required backlog task ids appear in action items, menu entries, and command-menu sections.

- T-266 Real wiring backlog required id regression: TEST ADDED / NOT RUN. Added coverage tying real-wiring backlog evidence builders to the final required T-164 through T-169 id set.

- T-267 Required backlog blocker count: TEST ADDED / NOT RUN. Added a final diagnostics count that includes both blocked backlog items and missing required backlog task ids.

- T-268 Snapshot required backlog blocker count regression: TEST ADDED / NOT RUN. Added shell UI snapshot coverage so backlog blocker counts mirror final completion evidence semantics.

- T-269 Facade required backlog blocker count: TEST ADDED / NOT RUN. Added a facade-level required backlog blocker count so UI callers do not reach into report internals.

- T-270 Milestone execution index: CREATED. Added `docs/LOCAL_TERMINAL_MILESTONE_EXECUTION_INDEX_2026-05.md` to answer whether each P0-P5 milestone has an execution plan and to map competitor-derived local-terminal capabilities to those plans without claiming verification closure.

- T-271 Missing backlog diagnostics surfaces: TEST ADDED / NOT RUN. Added regression coverage so missing required real-wiring backlog task ids remain visible through the diagnostics bundle, presentation model, and Flutter panel surfaces.

- T-272 Missing backlog shell command-menu diagnostics: TEST ADDED / NOT RUN. Added regression coverage so missing required real-wiring backlog task ids remain visible after completion menu entries are adapted into shell command-menu disabled reasons.

- T-273 Current completion audit snapshot: CREATED. Added `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_SNAPSHOT_2026-05-16.md` to map the active objective to current artifacts, identify non-closure evidence, and record the remaining verification blockers without claiming completion.

- T-274 Verification readiness checklist: CREATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_READINESS_CHECKLIST_2026-05.md` to distinguish runnable verification entry points from real passing evidence and to keep final closure blocked until evidence is recorded.

- T-275 Verification evidence ledger: CREATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_EVIDENCE_LEDGER_2026-05.md` as the fill-in ledger for future command/manual outputs; all required gates now have real evidence recorded.

- T-276 Verification record examples: CREATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_RECORD_EXAMPLES_2026-05.md` to show how filled ledger rows convert into `LocalTerminalVerificationGateRecord` values without treating examples as passing evidence.

- T-277 Verification command batches: CREATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_COMMAND_BATCHES_2026-05.md` with copy-ready verification batches mapped to required gates; no batch has been executed or recorded as passing.

- T-278 Final verification handoff: CREATED. Added `docs/LOCAL_TERMINAL_FINAL_VERIFICATION_HANDOFF_2026-05.md` as the single operator entry point for final verification execution; it records no passing evidence and does not close T-169.

Note: T-279 through T-297 preserve their original creation-time status text.
They are superseded by T-298 onward for the current verification execution
state.

- T-279 Verification batch runner script: CREATED / NOT RUN. Added `tools/local_terminal_verification_batches.sh` to list, print, or explicitly run verification batches; the script has not been executed and records no evidence by itself.

- T-280 Verification batch runner print all: CREATED / NOT RUN. Updated `tools/local_terminal_verification_batches.sh` so `print all-automated` can display the full automated verification sequence without executing it; the script still has not been run and records no evidence.

- T-281 Verification failure triage log: CREATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_FAILURE_TRIAGE_LOG_2026-05.md` for future failed batch triage; no verification batch has run, so the log contains no real failure evidence.

- T-282 Testing known-issues verification links: CREATED. Linked the local-terminal final verification workflow from global testing docs and recorded the P0-P5 wired-but-unverified closure risk in known issues; no validation was run.

- T-283 Verification capture wrapper: CREATED / NOT RUN. Added `tools/local_terminal_verification_capture.sh` to explicitly run future verification batches with captured logs under `build/local-terminal-verification/`; it has not been executed and records no ledger evidence automatically.

- T-284 Verification capture ledger entry template: CREATED / NOT RUN. Updated `tools/local_terminal_verification_capture.sh` so future captured runs also generate `ledger-entry.md`; the wrapper has not been executed and no canonical ledger evidence was recorded.

- T-285 Verification status helper: CREATED / NOT RUN. Added `tools/local_terminal_verification_status.sh` to print the final verification handoff and evidence entry points without running verification; the helper has not been executed and records no evidence.

- T-286 Verification helper index: CREATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_HELPER_INDEX_2026-05.md` to document helper script side effects and distinguish read-only inspection from verification execution; helper scripts have not been run.

- T-287 Verification machine-readable manifest: CREATED / NOT VALIDATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json` to map gates, batches, helper scripts, and closure rules for future tooling; it has not been parsed or used as verification evidence.

- T-288 Verification manifest maintenance: CREATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_MANIFEST_MAINTENANCE_2026-05.md` to document source-of-truth ordering and update rules for the machine-readable manifest; no JSON parsing or verification was run.

- T-289 Verification helper execution warning: CREATED / NOT RUN. Updated verification batch and capture helpers to print that ledger updates remain manual and script output alone is not closure evidence; helper scripts have not been executed.

- T-290 Verification capture gate hints: CREATED / NOT RUN. Updated `tools/local_terminal_verification_capture.sh` to include advisory gate hints in future `summary.txt` and `ledger-entry.md` files; the wrapper has not been executed and no ledger evidence was recorded.

- T-291 Verification helper safety comments: CREATED / NOT RUN. Added shellcheck hints and explicit read-only/execution/ledger warnings to local-terminal verification helper scripts; helpers have not been executed and no verification evidence was recorded.

- T-292 Verification helper README: CREATED. Added `tools/LOCAL_TERMINAL_VERIFICATION_HELPERS.md` to document helper purpose, `bash tools/...` invocation, and evidence boundaries; helper scripts have not been run.

- T-293 Root README verification link: CREATED. Linked the local-terminal final verification handoff and helper index from the repository root README; no helper or verification command was run.

- T-294 Verification authorization gate: CREATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_AUTHORIZATION_GATE_2026-05.md` to define what counts as explicit authorization to run final verification; no authorization has been given and no verification was run.

- T-295 Verification manifest authorization state: CREATED / NOT VALIDATED. Updated `docs/LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json` with the authorization gate path and current `not_authorized` state; the JSON was not parsed and no verification was run.

- T-296 Verification status authorization state: CREATED / NOT RUN. Updated `tools/local_terminal_verification_status.sh` to print the current `not authorized` verification state and authorization gate path; the helper has not been executed and no verification was run.

- T-297 Verification blocked-state handoff: CREATED. Added `docs/LOCAL_TERMINAL_VERIFICATION_BLOCKED_STATE_2026-05.md` to record that the remaining blocker is verification authorization and real evidence, not additional preparation artifacts; no verification was run.

- T-298 Verification execution state refresh: PARTIAL / BLOCKED. Verification
  was authorized and executed through
  `bash tools/local_terminal_verification_capture.sh run all-automated`;
  formatting, static analysis, completion, P1, cross-milestone, P2, P3, P4, P5,
  and verification-evidence batches passed. The broader suite failed one
  visibility-path widget test before the latest fix could be rerun.

- T-299 Verification status surface refresh: UPDATED / CHECKED. Updated
  `docs/LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json` and
  `tools/local_terminal_verification_status.sh` to reflect the authorized,
  then-current partially verified, execution-blocked state. Parsed the JSON with
  `python3 -m json.tool` and ran the status helper successfully.

- T-300 Broader rerun blocker record: BLOCKED. Updated verification handoff,
  blocked-state, helper index, authorization gate, known issues, command batch
  docs, test-target docs, manifest, ledger, and triage log so the next concrete
  step is unambiguous:
  `bash tools/local_terminal_verification_capture.sh run broader`. This command
  had not yet been rerun after the latest fix because escalated execution was
  temporarily unavailable. This historical blocker was later resolved by
  `20260516T154351Z-broader`.

- T-301 Integration batch concretization: READY / NOT RUN. Updated the
  integration verification batch from an unspecified placeholder to the default
  smoke command
  `bash tools/local_terminal_verification_capture.sh run integration`.
  The explicit macOS runner avoids unrelated Android device-discovery hangs.
  `vttest_gui_test.dart` remains an optional external-binary supplement and is
  not part of the default closure gate.

- T-302 Capture summary final status: UPDATED / NOT RUN. Updated
  `tools/local_terminal_verification_capture.sh` so future captured summaries
  write `started_status: running` at creation and append final
  `status: passed` or `status: failed` after the batch exits. No new
  verification command was run for this helper change.

- T-303 Verification helper syntax check: CHECKED. Parsed
  `docs/LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json` with
  `python3 -m json.tool` and checked
  `tools/local_terminal_verification_batches.sh` plus
  `tools/local_terminal_verification_capture.sh` with `bash -n`. No Flutter
  verification or broader rerun was executed.

- T-304 macOS integration runner hardening: UPDATED / NOT RUN. Changed the
  default integration batch to use `flutter test -d macos ...` so the future
  integration smoke avoids unrelated Android device-discovery hangs documented
  in `docs/KNOWN_ISSUES.md`. Updated the status helper to list
  `bash tools/local_terminal_verification_capture.sh run integration`.

- T-305 Verification plan record command alignment: UPDATED / NOT RUN. Updated
  `LocalTerminalVerificationPlanRecords.defaultPending()` so default pending
  evidence records expose the current closure commands:
  `bash tools/local_terminal_verification_capture.sh run all-automated`,
  `bash tools/local_terminal_verification_capture.sh run broader`, and the
  macOS-targeted integration command. Added test assertions for these command
  strings. Ran `dart format` on the two touched Dart files; no Flutter
  verification was run.

- T-306 Verification evidence command example alignment: UPDATED / NOT RUN.
  Updated verification evidence recorder/model tests so example command strings
  use the current capture helper commands instead of stale bare
  `flutter test` / `flutter test test/widget_test.dart` examples. Ran
  `dart format` on the touched test files and confirmed no stale verification
  command examples remain in the local-terminal verification evidence code/test
  slice. No Flutter verification was run.

- T-307 Completion audit evidence-state alignment: UPDATED. Updated
  `docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` so the top-level
  audit rows reflect current evidence: formatting and static analysis have
  passing captured evidence, focused automated suites passed, and broader,
  integration, and manual/integration-backed gates are now superseded by later
  passing evidence records.

- T-308 Evidence recording runbook state alignment: UPDATED. Updated
  `docs/LOCAL_TERMINAL_EVIDENCE_RECORDING_RUNBOOK_2026-05.md` so its recording
  sequence and gate mapping use the current helper commands:
  rerun `broader`, carry forward or rerun `all-automated`, run the macOS
  `integration` batch, then record manual gates and convert ledger rows into
  `LocalTerminalVerificationGateRecord` values. The runbook now reflects the
  partial captured evidence and then-current execution blocker. This state was
  later superseded by the successful broader and integration reruns.

- T-309 Verification evidence closure guard hardening: UPDATED / NOT RUN.
  Tightened `LocalTerminalVerificationEvidence.canClose` so manually
  constructed evidence cannot close unless every default required verification
  gate is present and passed. Updated regression coverage to assert partial
  required evidence remains non-closeable and full default-gate coverage can
  close. Ran `dart format` on the touched files; no Flutter test was run.

- T-310 Production wiring manifest closure guard hardening: UPDATED / NOT RUN.
  Tightened `LocalTerminalProductionWiringManifest.canCloseAll` so a manifest
  cannot close unless every required P0-P5 milestone is present and closeable.
  Added `missingRequiredMilestones` JSON output and regression coverage for
  missing required milestone blockers. Ran `dart format` on the touched files;
  no Flutter test was run.

- T-311 P1 dispatch failure closure guard: UPDATED / NOT RUN. Tightened
  `ShellActionProductionAuditSnapshot.canCloseP1ActionWiring` and
  `ShellActionProductionClosureManifest.blockers` so recent production action
  dispatch failures block P1 closure with an explicit blocker. Added regression
  coverage for failed dispatch reports and ran `dart format` on the touched
  files; no Flutter test was run.

- T-312 Missing production milestone diagnostics: UPDATED / NOT RUN. Exposed
  `missingRequiredProductionMilestones` and `productionMilestoneBlockerCount`
  through `LocalTerminalCompletionEvidenceReport`, then surfaced missing
  production milestones in completion summary and diagnostics view model output.
  This keeps hand-constructed or corrupted manifests from producing a blocked
  report with no readable milestone blocker. Ran `dart format` on the touched
  files; no Flutter test was run.

- T-313 Shell UI milestone blocker count alignment: UPDATED / NOT RUN. Updated
  `LocalTerminalShellUiWiringSnapshot.blockedMilestoneCount` to use
  `LocalTerminalCompletionEvidenceReport.productionMilestoneBlockerCount`, so
  completion panels and presentation totals include missing required production
  milestones as well as blocked present milestones. Ran `dart format` on the
  touched file; no Flutter test was run.

- T-314 Missing verification gate diagnostics: UPDATED / NOT RUN. Added
  `missingRequiredGates` and `verificationGateBlockerCount` to
  `LocalTerminalVerificationEvidence`, surfaced missing verification gates in
  completion summary, diagnostics view model, shell UI blocker counts, and T-169
  backlog blockers. Added regression expectations for missing gate blockers and
  ran `dart format` on the touched files; no Flutter test was run.

- T-315 Summary/view-model verification consistency guard: UPDATED / NOT RUN.
  Updated `LocalTerminalCompletionSummary.fromEvidence` and
  `LocalTerminalCompletionDiagnosticsViewModel.fromEvidence` so the user-facing
  closeable state requires both `LocalTerminalCompletionEvidenceReport` and
  `LocalTerminalVerificationEvidence` to be closeable. This prevents a stale or
  inconsistent report from showing completion while verification evidence still
  has blocked or missing required gates. Ran `dart format` on the touched files;
  no Flutter test was run.

- T-316 Current state/facade verification consistency guard: UPDATED / NOT RUN.
  Updated `LocalTerminalCurrentCompletionState.canCloseObjective` and
  `LocalTerminalShellUiWiringFacade.canCloseObjective` to require both the
  completion report and verification evidence to be closeable, matching the
  summary and diagnostics view-model guard. Ran `dart format` on the touched
  files; no Flutter test was run.

- T-317 Closeable proxy consistency check: CHECKED. Searched shell feature code
  for direct `report.canCloseObjective` proxy usage and confirmed the remaining
  user-facing closeability surfaces combine report closure with verification
  evidence closure. No Flutter test was run.

- T-318 Missing verification gate UI propagation coverage: UPDATED / NOT RUN.
  Extended completion diagnostics action, menu model, and command-menu adapter
  regression expectations so missing required verification gates propagate from
  the view model into secondary UI surfaces. Ran `dart format` on the touched
  test files; no Flutter test was run.

- T-319 Facade closeability expectation alignment: UPDATED / NOT RUN. Updated
  `local_terminal_shell_ui_wiring_facade_test.dart` so facade closeability is
  asserted as the conjunction of completion report closure and verification
  evidence closure, then confirmed no stale report-only facade closeability
  assertions remain. Ran `dart format` on the touched test file; no Flutter test
  was run.

- T-320 Missing verification gate presentation/panel coverage: UPDATED / NOT
  RUN. Extended completion diagnostics presentation and panel regression
  expectations so missing required verification gates contribute to presentation
  blocker totals and render visibly in the diagnostics panel. Ran `dart format`
  on the touched test files; no Flutter test was run.

- T-321 Missing verification gate diagnostics bundle coverage: UPDATED / NOT
  RUN. Extended completion diagnostics bundle regression expectations so missing
  required verification gates appear in bundled plain-text output and command
  menu sections. Ran `dart format` on the touched test file; no Flutter test was
  run.

- T-322 Missing verification gate UI coverage check: CHECKED. Searched the
  local-terminal completion diagnostics tests and confirmed missing verification
  gate coverage now reaches presentation, panel, diagnostics actions, menu
  model, command-menu adapter, bundle, evidence, and T-169 backlog paths. No
  Flutter test was run.

- T-323 Broader verification rerun: VERIFIED. Ran
  `bash tools/local_terminal_verification_capture.sh run broader` after the
  profile visibility fix. Captured evidence in
  `build/local-terminal-verification/20260516T154351Z-broader`; exit status was
  `0` and the log ended with `All tests passed!`.

- T-324 Integration batch environment hardening: UPDATED / VERIFIED. Updated
  `tools/local_terminal_verification_batches.sh` so the integration batch builds
  the debug native core, runs from the `example` package to use desktop plugin
  registration, sets `FLUTTERM_CORE_LIB`, and executes the smoke and real-PTY
  integration files sequentially.

- T-325 Integration smoke visibility fix: UPDATED / VERIFIED. Updated
  `example/integration_test/flutterm_smoke_test.dart` to make the `Profiles…`
  menu item visible before tapping it in the 800x600 macOS test window. Ran
  `dart format example/integration_test/flutterm_smoke_test.dart` and
  `bash -n tools/local_terminal_verification_batches.sh`.

- T-326 Integration verification rerun: VERIFIED. Ran
  `bash tools/local_terminal_verification_capture.sh run integration` after the
  helper and smoke-test fixes. Captured evidence in
  `build/local-terminal-verification/20260516T155028Z-integration`; exit status
  was `0`, `flutterm_smoke_test.dart` passed 4/4, and
  `real_pty_acceptance_test.dart` passed 7/7. Manual gates and
  completion evidence records are now closed.

- T-327 Verification plan command alignment rerun: VERIFIED. Updated
  `LocalTerminalVerificationPlanRecords.defaultPending()` and its regression
  test so the integration gate points at
  `bash tools/local_terminal_verification_capture.sh run integration`. Ran
  `dart format` on the touched Dart files and reran
  `bash tools/local_terminal_verification_capture.sh run verification-evidence`;
  captured evidence in
  `build/local-terminal-verification/20260516T171327Z-verification-evidence`
  with exit status `0` and 13/13 passing tests.

- T-328 Latest static analysis rerun: VERIFIED. Ran
  `bash tools/local_terminal_verification_capture.sh run static-analysis` after
  the command-alignment Dart changes. This earlier run was later superseded by
  `build/local-terminal-verification/20260516T171224Z-static-analysis`; exit
  status was `0` and `flutter analyze` reported `No issues found!`.

- T-329 Product paste policy closure: UPDATED / VERIFIED. Manual product-app
  verification exposed that multiline paste reached the shell without a visible
  confirmation dialog. Routed `ShellScreen` paste through
  `LocalTerminalPasteDecisionResolver`, added a `Confirm paste` dialog for
  multiline/large paste decisions, and preserved read-only paste blocking. Ran
  `dart format`, focused `flutter test example/test/shell/shell_screen_phase4_test.dart`
  with 9/9 passing tests, latest static analysis in
  `build/local-terminal-verification/20260516T171224Z-static-analysis`, latest
  broader in `build/local-terminal-verification/20260516T171406Z-broader`, and
  latest integration in `build/local-terminal-verification/20260516T171644Z-integration`.

- T-330 Product multipane zoom closure: UPDATED / VERIFIED. Manual product-app
  verification exposed that `Zoom active pane` did not change the visible pane
  layout because `_buildTerminalWorkspace` still rendered every effective pane.
  Updated `ShellScreen` to render only the zoomed pane when
  `_zoomedPaneSessionId` resolves inside the active tab, and added focused
  zoom/unzoom widget coverage. Verified by focused phase4 9/9 and latest
  broader/static/integration captures.

- T-331 Hotkey-window visible failure closure: UPDATED / VERIFIED. Added
  `ShellScreen` hotkey-window status checking and visible SnackBar feedback for
  unregistered platform status or platform errors instead of allowing a silent
  no-op. Added focused widget coverage that simulates unregistered hotkey
  status and verifies `Hotkey window unavailable` feedback. Verified by focused
  phase4 9/9 and latest broader/static/integration captures.

- T-332 Final verification capture rerun: VERIFIED. After the paste, zoom, and
  hotkey-window fixes, reran `bash tools/local_terminal_verification_capture.sh
  run static-analysis`, `broader`, and `integration`. Latest evidence:
  `20260516T171224Z-static-analysis` exited 0 with `No issues found!`,
  `20260516T171406Z-broader` exited 0 with 601 passing tests plus 1 skipped
  test, and `20260516T171644Z-integration` exited 0 with smoke 4/4 and real PTY
  7/7 passing.

- T-333 Verification ledger status refresh: UPDATED. Updated the evidence
  ledger, manifest, final handoff, audit checklist, failure triage log, and
  status helper so all required automated, integration, and manual/integration-
  backed gates point at the latest passing evidence. Remaining closure work is
  ledger-to-`LocalTerminalVerificationGateRecord` conversion and completion-
  evidence rebuild, not more verification execution.

### T-334 - Persist final passed verification records
- Status: completed
- Evidence: `LocalTerminalVerificationPlanRecords.latestPassed()` now records every required gate as passed using the final verified capture directories.
- Verification: `flutter test example/test/shell/local_terminal_verification_plan_records_test.dart` covered completion evidence closure and backlog verified status.

### T-335 - Final verification capture refresh after record conversion
- Status: completed
- Evidence: final capture directories are `20260516T171224Z-static-analysis`, `20260516T171327Z-verification-evidence`, `20260516T171406Z-broader`, and `20260516T171644Z-integration`.
- Verification: static analysis reported no issues; verification evidence passed 13/13; broader suite passed 601 with 1 skipped; integration smoke passed 4/4 and real PTY passed 7/7.

### T-336 - Verified current completion-state closure
- Status: completed
- Evidence: `LocalTerminalRealWiringBacklogEvidence.currentVerified`, `LocalTerminalCurrentCompletionState.verified`, and `LocalTerminalCompletionController.verified` now convert the final passed gate evidence into a closeable `LocalTerminalCompletionEvidenceReport`.
- Verification: focused completion-state/facade/controller/verification-plan tests passed 15/15; final `flutter analyze` reported no issues.
