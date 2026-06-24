# T-322 Command Center Verification Gates

## Goal

沉淀 Command Center 的自动化、手工、性能和 stop condition 验证门。

## Scope

- 汇总 Command Center 各 lane 的最小自动化命令。
- 定义输入、IME、paste、read-only、shortcut、scroll、renderer 和 review 隔离的人工 QA。
- 定义 search index 和 sticky header 的性能门。
- 记录 stop conditions，出现时必须停止并修复。

## Non-goals

- 不实现任何 Command Center 功能。
- 不替代各实现任务自己的测试。
- 不降低 `docs/TESTING.md` 的默认验证要求。
- 不把失败 gate 写成通过。
- 不跳过 GUI、terminal、输入法、滚动、复制粘贴等人工检查。

## Files In Scope

- `docs/tasks/command-center/T-322-command-center-verification-gates.md`
- 必要时更新 `docs/TESTING.md`
- 必要时更新 `docs/KNOWN_ISSUES.md`

## Functional Acceptance

- Foundation lane 有模型和 adapter 的最小测试命令。
- History/Search lane 有 parser、index、overlay 和 insert/execute safety 的最小测试命令。
- Blocks lane 有 range、navigation、actions、sticky header 和 review entrypoints 的最小测试命令。
- Command Bar lane 有 editor、context chips 和 mode router 的最小测试命令。
- Manual QA 覆盖 `Ctrl-R`、read-only、IME、paste、shortcut、scrollback、copy output、sticky header、Instant Replay review 和 alt-buffer / pager。
- Performance gates 覆盖 10k history search、长输出 block creation、sticky header 可见范围计算和 context chip update debounce。

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。本任务是验证文档任务，最小验证为：

```bash
rg -n "Ctrl-R|read-only|IME|paste|shortcut|stop condition|performance" docs/tasks/command-center/T-322-command-center-verification-gates.md
```

## Manual QA

文档任务，无需 UI QA。人工检查是否覆盖 Search、Blocks、Command Bar、Review、输入安全和性能门。

## Done When

- 后续实现任务能引用同一验证门，而不是各自发明验收方式。
- 每个高风险输入/渲染/复制/滚动场景都有自动化或人工验证入口。
- stop conditions 清楚列出，不能被实现任务忽略。

## Risks / Follow-ups

- 真正跑 gate 的证据由各实现任务记录。
- 如果后续新增 Agent mode、diff review 或 saved commands，需要扩展本验证门。
- 性能阈值需要根据真实机器基线更新。
