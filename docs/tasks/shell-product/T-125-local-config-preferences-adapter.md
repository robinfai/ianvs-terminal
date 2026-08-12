# T-125 Local Config Preferences Adapter

> Superseded historical task. The compatibility adapter and its production
> wiring were removed; runtime consumes current local config directly.

## Goal

记录曾计划的 compatibility adapter；该方案不属于 current product contract。

## Scope

- no production artifacts (removed)
- `docs/tasks/README.md`
- `docs/LOCAL_TERMINAL_P1_EXECUTION_PLAN_2026-05.md`

## Non-goals

- 不接入 `SessionController`
- 不写入旧 preferences 文件
- 不迁移 profiles list
- 不处理 keybindings/workspace/policy runtime
- 不新增 remote/SSH fields

## Current Progress

- adapter and tests were removed by the current-only architecture.

## Functional Acceptance

- current local config is consumed directly; no compatibility conversion.

## Verification Commands

参考 [../../TESTING.md](../../TESTING.md)。

`flutter analyze`

## Manual QA

本任务只新增 adapter，不接 runtime；无需人工 UI 验收。

## Done When

- no production references to the removed adapter.

## Risks / Follow-ups

- keybindings/layout/policy all use current local config.
