# ADR-0002: 使用 vendored terminal core

## Context

Ianvs 依赖 terminal core 的 damage 跟踪、scroll 优化、调试统计和终端协议扩展。
这些是当前 frame/runtime 行为的组成部分，不能仅依据上游版本号替换依赖。

## Decision

[Cargo.toml](../../native/core/Cargo.toml) 使用本地
[`par-term-emu-core-rust`](../../native/vendor/par-term-emu-core-rust/) fork。
[session](../../native/core/src/session.rs) 和 [frame 管线](../../native/core/src/session/frame/)
使用 `ScrollRegionDamage`、`TerminalDamage`、`TerminalProcessDebugStats`、
`drain_active_screen_damage()` 与 `take_process_debug_stats()` 等接口。

## Consequences

依赖升级或回归上游必须检查当前接口、协议行为和性能合同，并运行 native、frame corpus、
viewport 及真实 PTY 验证。使用本地 fork 本身不代表稳定性或兼容性已经通过验证。
Standalone 发布包必须同步同一套原生源，避免 app 与嵌入包行为分叉。

## Alternatives Considered

直接改回未经适配的上游发布包会丢失当前扩展或导致接口失配。后续可以单独评估上游化、
fork 瘦身和依赖更新，但必须以 [TESTING](../TESTING.md) 中的当前门禁验证。
