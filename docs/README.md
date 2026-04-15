# flutterm Docs

这个目录是 `flutterm` 的工作文档区，目标是让 `oh my codex + gpt-5.3-codex-spark` 在持续迭代时尽量少走弯路。

## 使用顺序

如果要开始一个新迭代，推荐按这个顺序读：

1. [../README.md](/Users/robinfai/personal/flutterm/README.md)
2. [ROADMAP.md](/Users/robinfai/personal/flutterm/docs/ROADMAP.md)
3. 对应任务文档，或从 [tasks/TEMPLATE.md](/Users/robinfai/personal/flutterm/docs/tasks/TEMPLATE.md) 新建一个
4. [ACCEPTANCE.md](/Users/robinfai/personal/flutterm/docs/ACCEPTANCE.md)
5. [TESTING.md](/Users/robinfai/personal/flutterm/docs/TESTING.md)
6. [ARCHITECTURE.md](/Users/robinfai/personal/flutterm/docs/ARCHITECTURE.md)
7. [KNOWN_ISSUES.md](/Users/robinfai/personal/flutterm/docs/KNOWN_ISSUES.md)

## 文档职责

- `ARCHITECTURE.md`
  只写稳定设计、边界和长期约束。
- `ROADMAP.md`
  只写阶段目标、非目标、进入条件和完成条件。
- `ACCEPTANCE.md`
  只写全局完成定义、任务级验收规则和失败处理规则。
- `TESTING.md`
  只写标准验证命令和人工检查清单。
- `KNOWN_ISSUES.md`
  只写当前接受的限制、缺口和临时取舍。
- `tasks/`
  每个迭代任务一份文档，要求范围小、目标单一、验收明确。
- `DECISIONS/`
  只记录重要且需要长期追踪的架构决策。

## 维护规则

- 一个概念只保留一个权威文档，避免重复定义。
- 任务文档必须写 `Non-goals`，防止模型顺手扩 scope。
- 任务完成前必须执行对应验证命令，不能只凭“看起来没问题”。
- 如果某项验收暂时跳过，必须在任务文档或 `KNOWN_ISSUES.md` 里显式记录原因。
- 产品级说明放根目录和 `docs/`，不要继续把主文档散落到子项目 README。

## 推荐迭代方式

每次只让模型处理一个小任务，并在 prompt 里固定引用这几份文档：

- 当前任务文档
- `ACCEPTANCE.md`
- `TESTING.md`
- 必要时再加 `ARCHITECTURE.md`

推荐 prompt 结构：

```text
请按 docs/tasks/T-xxx.md 实施。
必须遵守 docs/ACCEPTANCE.md 和 docs/TESTING.md。
如果涉及稳定边界，遵守 docs/ARCHITECTURE.md。
不要扩展到 Non-goals。
完成前运行相关验证命令。
最终回复使用：变更 / 验证 / 剩余风险。
```
