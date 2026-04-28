# ADR-0002: Keep terminal core on the vendored `par-term-emu-core-rust` fork

## Context

当前 terminal core 这轮工作，不只是把 Rust 端抽帧改成 delta，而是把 frame 提取、滚屏处理和调试统计一起往 damage 驱动方向推进。

`2026-04-27` 早期，`native/core/Cargo.toml` 还直接依赖 crates.io 的 `par-term-emu-core-rust 0.41.1`。同一轮后续工作里，terminal core 改成了本地 path 依赖，并开始在 vendored crate 内直接补 damage 跟踪、scroll 行为优化和调试统计。

到 `2026-04-28`，本地代码和会话复盘已经确认：公开 `0.41.1` 不提供当前 `native/core` 已经在使用的 damage/debug API，不能通过“直接切回 crates.io”恢复到公开依赖。

当前仓库里，这个判断已经能从代码直接看出来：

- `native/core/Cargo.toml` 依赖的是 `../vendor/par-term-emu-core-rust`
- `native/core/src/session.rs` 直接 import 了 `ScrollRegionDamage`、`TerminalDamage`、`TerminalProcessDebugStats`
- vendored crate 公开了 `drain_active_screen_damage()` 和 `take_process_debug_stats()`

这份文档记录的是“为什么 fork 发生，以及为什么它现在仍然必要”。它不是这轮 terminal 变更的稳定性结论，也不代表当前分支已经可以忽略仍在进行中的 review finding。

## Decision

当前项目继续把 `native/vendor/par-term-emu-core-rust` 作为 `native/core` 的权威依赖实现。

这样做的直接原因是：`native/core/src/session.rs` 已经依赖 vendored fork 才有的接口和导出，而这些接口不在 crates.io `0.41.1` 中：

- `ScrollRegionDamage`
- `TerminalDamage`
- `TerminalProcessDebugStats`
- `drain_active_screen_damage()`
- `take_process_debug_stats()`

这份 ADR 只记录一个当前决策：

- fork 目前必要

这份 ADR 不附带以下判断：

- 当前 terminal delta 改动已经稳定可合入
- 当前整仓 vendoring 已经是长期最优形态
- 后续一定不会做上游化、瘦身或依赖回收

## Consequences

- 现在不能把 `native/core` 的依赖直接改回 crates.io `par-term-emu-core-rust 0.41.1`。那样不仅会失去当前的 damage/debug 能力，`native/core` 还会先在编译层面失配。
- 这个 fork 承担的不只是“接口补洞”。按照当前代码和本地会话记录，它还承载了 damage 跟踪、调试统计、ASCII fast path、row-ring scroll 等 terminal 性能改造。
- 后续如果要讨论“是否继续整仓 vendor”“是否收敛到更小的 fork”“是否把部分改动回推上游”，应该作为新的决策单独评估，不在这份 ADR 里预先拍板。
- terminal 功能是否稳定、是否满足合入条件，仍然要由对应测试、benchmark 和 code review 单独判断，不能借这份 ADR 直接推导。

## Alternatives Considered

### 1. 直接切回 crates.io `par-term-emu-core-rust 0.41.1`

Rejected，因为当前 `native/core` 已经依赖 `0.41.1` 不提供的 damage/debug API，直接切回去既不满足能力要求，也不能无痛编译通过。

### 2. 只把结论写进任务文档

Rejected，因为这不是一次性实现细节，而是会持续影响 terminal core、依赖边界和后续性能工作的长期决策。

### 3. 只记在 `.omx/notepad.md` 或会话记录里

Rejected，因为这类记录不够稳定，也不够容易被后续工程改动直接反查到。

## Evidence Checked

仓库内证据：

- `native/core/Cargo.toml`
- `native/core/src/session.rs`
- `native/vendor/par-term-emu-core-rust/src/terminal/mod.rs`
- `native/vendor/par-term-emu-core-rust/src/grid/mod.rs`

本地会话反查入口：

- `~/.codex/sessions/2026/04/27/rollout-2026-04-27T11-41-56-019dcd07-87c6-7572-8cf7-3f116ec59f36.jsonl`
- `~/.codex/sessions/2026/04/27/rollout-2026-04-27T19-15-24-019dcea6-b137-7743-b35e-b1440968e4ba.jsonl`
- `~/.codex/sessions/2026/04/28/rollout-2026-04-28T10-29-36-019dd1eb-ad65-7481-ad83-f84baeb6b579.jsonl`

这些会话路径只是为了方便后续本地反查决策来源，不属于构建输入，也不替代代码本身。
