# Decisions

这个目录用来放需要长期追踪的架构决策文档。

适合写成决策文档的情况：

- 影响多个阶段的技术选型
- 会改变后续任务边界
- 未来很可能需要回看“为什么当时这么选”

建议命名格式：

- `ADR-0001-flutter-canvas-first.md`
- `ADR-0002-json-ffi-first.md`

每份决策文档至少包含：

- `Context`
- `Decision`
- `Consequences`
- `Alternatives Considered`

如果只是一次性实现细节，不要放到这里，直接写在任务文档里。
