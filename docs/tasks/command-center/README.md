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

History/Search lane:

```text
T-305 -> T-306 -> T-307 -> T-308 -> T-309 -> T-310 -> T-311 -> T-312
```

Blocks lane:

```text
T-313 -> T-314 -> T-315 -> T-316 -> T-320 -> T-321
```

Command Bar lane:

```text
T-317 -> T-318 -> T-319
```

Verification lane:

```text
T-322
```

`T-322` 贯穿全程，但作为收口任务沉淀自动化、手工、性能和 stop condition 验证门。

## 任务索引

- [T-300 Command Center Track Intake](T-300-command-center-track-intake.md)
- [T-301 Command Center Feature Flags](T-301-command-center-feature-flags.md)
- [T-302 Command Invocation Lifecycle Model](T-302-command-invocation-lifecycle-model.md)
- [T-303 Shell Hook Lifecycle Adapter](T-303-shell-hook-lifecycle-adapter.md)
- [T-304 Command Lifecycle Degraded State](T-304-command-lifecycle-degraded-state.md)
- [T-305 Session Command History Buffer](T-305-session-command-history-buffer.md)
- [T-306 Global Command History Repository](T-306-global-command-history-repository.md)
- [T-307 Command History Privacy Filter](T-307-command-history-privacy-filter.md)
- [T-308 Command Search Query Parser](T-308-command-search-query-parser.md)
- [T-309 Command Search Index Ranking](T-309-command-search-index-ranking.md)
- [T-310 Command Search Overlay Controller](T-310-command-search-overlay-controller.md)
- [T-311 Command Search Overlay Widget](T-311-command-search-overlay-widget.md)
- [T-312 Command Search Insert Execute Safety](T-312-command-search-insert-execute-safety.md)
- [T-313 Command Block Range Model](T-313-command-block-range-model.md)
- [T-314 Command Block Navigation](T-314-command-block-navigation.md)
- [T-315 Command Block Actions Reducer](T-315-command-block-actions-reducer.md)
- [T-316 Command Block Action Wiring](T-316-command-block-action-wiring.md)
- [T-317 Command Bar Editor](T-317-command-bar-editor.md)
- [T-318 Command Center Context Chips](T-318-command-center-context-chips.md)
- [T-319 Command Center Mode Router](T-319-command-center-mode-router.md)
- [T-320 Sticky Command Header](T-320-sticky-command-header.md)
- [T-321 Command Review Entrypoints](T-321-command-review-entrypoints.md)
- [T-322 Command Center Verification Gates](T-322-command-center-verification-gates.md)
