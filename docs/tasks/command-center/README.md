# Command Center Tasks

Command Center 是并行产品线，不替换 `docs/ROADMAP.md` 里的 `M1-M5`。本目录是
Command Center 的任务执行入口。

## 全局护栏

- 普通输入默认发给 shell。
- 不做自然语言自动识别。
- 不重写 terminal renderer。
- 不把产品 UI 下沉到 `packages/ianvs_terminal`。
- 不绕过 read-only、paste confirmation、shortcut isolation 或 terminal input policy。
- v1 不做 Agent / AI、remote / SSH、cloud sync、协作或插件生态。

## 执行阶段

- `CC0`：规划和任务包入库。
- `CC1`：command lifecycle 数据基座。
- `CC2`：history repository 和 search index。
- `CC3`：`Ctrl-R` command search overlay。
- `CC4`：command blocks range 和 actions MVP。
- `CC5`：command bar、context chips、mode router。
- `CC6`：sticky header、review 接入、验证收口。

## 任务依赖

Foundation lane:

```text
T-300 -> T-301 -> T-302 -> T-303 -> T-304
```

Runtime wiring lane:

```text
T-303 -> T-323 -> T-324
```

History/Search lane:

```text
T-305 -> T-306 -> T-307 -> T-308 -> T-309 -> T-310 -> T-311 -> T-312 -> T-325 -> T-327
```

Blocks lane:

```text
T-313 -> T-314 -> T-315 -> T-316 -> T-320 -> T-321
```

Command Bar lane:

```text
T-317 -> T-318 -> T-326 -> T-319 -> T-328 -> T-329 -> T-330 -> T-331 -> T-332
```

Verification lane:

```text
T-322
```

`T-322` 贯穿全程，但作为收口任务沉淀自动化、手工、性能和 stop condition 验证门。

## 任务索引

- [Command Center Track Intake](T-300-command-center-track-intake.md)
- [Command Center Feature Flags](T-301-command-center-feature-flags.md)
- [Command Invocation Lifecycle Model](T-302-command-invocation-lifecycle-model.md)
- [Shell Hook Lifecycle Adapter](T-303-shell-hook-lifecycle-adapter.md)
- [Command Lifecycle Degraded State](T-304-command-lifecycle-degraded-state.md)
- [Session Command History Buffer](T-305-session-command-history-buffer.md)
- [Global Command History Repository](T-306-global-command-history-repository.md)
- [Command History Privacy Filter](T-307-command-history-privacy-filter.md)
- [Command Search Query Parser](T-308-command-search-query-parser.md)
- [Command Search Index Ranking](T-309-command-search-index-ranking.md)
- [Command Search Overlay Controller](T-310-command-search-overlay-controller.md)
- [Command Search Overlay Widget](T-311-command-search-overlay-widget.md)
- [Command Search Insert Execute Safety](T-312-command-search-insert-execute-safety.md)
- [Command Block Range Model](T-313-command-block-range-model.md)
- [Command Block Navigation](T-314-command-block-navigation.md)
- [Command Block Actions Reducer](T-315-command-block-actions-reducer.md)
- [Command Block Action Wiring](T-316-command-block-action-wiring.md)
- [Command Bar Editor](T-317-command-bar-editor.md)
- [Command Center Context Chips](T-318-command-center-context-chips.md)
- [Command Center Mode Router](T-319-command-center-mode-router.md)
- [Sticky Command Header](T-320-sticky-command-header.md)
- [Command Review Entrypoints](T-321-command-review-entrypoints.md)
- [Command Center Verification Gates](T-322-command-center-verification-gates.md)
- [Command Center Runtime State](T-323-command-center-runtime-state.md)
- [Command Center Shell Event Wiring](T-324-command-center-shell-event-wiring.md)
- [Command Search Shell Wiring](T-325-command-search-shell-wiring.md)
- [Command Center Context Chip Wiring](T-326-command-center-context-chip-wiring.md)
- [Command History Persistence Wiring](T-327-command-history-persistence-wiring.md)
- [Saved Command Repository](T-328-saved-command-repository.md)
- [Command Action Search Index](T-329-command-action-search-index.md)
- [Command Action Search Controller](T-330-command-action-search-controller.md)
- [Command Action Search Shell Wiring](T-331-command-action-search-shell-wiring.md)
- [Command Action Search Overlay Widget](T-332-command-action-search-overlay-widget.md)
