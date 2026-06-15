# T-300 Command Center Track Intake

## Goal

冻结 Command Center 作为并行产品线进入仓库路线图和任务体系。

## Scope

- 在 `docs/ROADMAP.md` 中记录 Command Center 与现有 `M1-M5` 的并行关系。
- 建立 `docs/tasks/command-center/README.md` 作为任务目录入口。
- 建立 `T-300` 到 `T-322` 的完整任务包。

## Non-goals

- 不实现 Command Center UI 或 runtime 能力。
- 不修改 `packages/ianvs_terminal` 或 `packages/ianvs_pty` API。
- 不复制 zip 里的 `COMMAND_CENTER_*.md` 文档。
- 不做 Agent v1、AI command generation、remote / SSH / SFTP / serial、cloud sync、协作或插件生态。
- 不重写 terminal renderer，不改变普通输入默认发给 shell 的行为。

## Files In Scope

- `docs/ROADMAP.md`
- `docs/tasks/command-center/README.md`
- `docs/tasks/command-center/T-300-command-center-track-intake.md`
- `docs/tasks/command-center/T-301-command-center-feature-flags.md`
- `docs/tasks/command-center/T-302-command-invocation-lifecycle-model.md`
- `docs/tasks/command-center/T-303-shell-hook-lifecycle-adapter.md`
- `docs/tasks/command-center/T-304-command-lifecycle-degraded-state.md`
- `docs/tasks/command-center/T-305-session-command-history-buffer.md`
- `docs/tasks/command-center/T-306-global-command-history-repository.md`
- `docs/tasks/command-center/T-307-command-history-privacy-filter.md`
- `docs/tasks/command-center/T-308-command-search-query-parser.md`
- `docs/tasks/command-center/T-309-command-search-index-ranking.md`
- `docs/tasks/command-center/T-310-command-search-overlay-controller.md`
- `docs/tasks/command-center/T-311-command-search-overlay-widget.md`
- `docs/tasks/command-center/T-312-command-search-insert-execute-safety.md`
- `docs/tasks/command-center/T-313-command-block-range-model.md`
- `docs/tasks/command-center/T-314-command-block-navigation.md`
- `docs/tasks/command-center/T-315-command-block-actions-reducer.md`
- `docs/tasks/command-center/T-316-command-block-action-wiring.md`
- `docs/tasks/command-center/T-317-command-bar-editor.md`
- `docs/tasks/command-center/T-318-command-center-context-chips.md`
- `docs/tasks/command-center/T-319-command-center-mode-router.md`
- `docs/tasks/command-center/T-320-sticky-command-header.md`
- `docs/tasks/command-center/T-321-command-review-entrypoints.md`
- `docs/tasks/command-center/T-322-command-center-verification-gates.md`

## Functional Acceptance

- `docs/ROADMAP.md` 说明 Command Center 不替换 `M1-M5`，可以作为独立产品线并行推进。
- `docs/tasks/command-center/README.md` 指向 `T-300` 到 `T-322`，并说明全局护栏和任务依赖。
- 每个 Command Center 任务都包含 `Goal`、`Scope`、`Non-goals`、`Files In Scope`、`Functional Acceptance`、`Verification Commands`、`Manual QA`、`Done When` 和 `Risks / Follow-ups`。
- 任务包明确防止把产品 UI 下沉到 package、绕过 terminal safety 或重写 renderer。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。本任务是文档入库任务，最小验证为：

```bash
rg -n "Command Center 并行产品线|T-300-command-center-track-intake|T-322-command-center-verification-gates" docs/ROADMAP.md docs/tasks/command-center
```

```bash
find docs/tasks/command-center -maxdepth 1 -type f -name 'T-3*.md' | sort | wc -l
```

期望任务文件数量为 `23`。

## Manual QA

文档任务，无需 UI QA。人工检查路线图关系、任务入口和全局护栏是否能让后续执行者不误解范围。

## Done When

- Command Center 并行产品线入口存在。
- `docs/tasks/command-center/` 可以作为后续实施入口。
- 完整任务包已写入并通过结构检查。

## Risks / Follow-ups

- 后续执行任务时必须继续保持细粒度，不把多个功能合进一个任务。
- 如果某个实现任务发现范围过大，应拆出新的 `T-3xx` 后续任务，不在原任务里扩张。
