# T-063 Shell-Hook Typed Runtime Event and Multi-Shell Contract

## Goal

把现有 `native/core -> PtyEvent(kind: "shell_hook")` 基线收口成
`flutterm_terminal` 的 typed runtime event 和可复用的 multi-shell 契约，
让消费方不再依赖产品侧 raw adapter 才能消费 shell hook。

## Scope

- 在 `flutterm_terminal` runtime 层新增 typed shell-hook 事件。
- 固化 raw payload 保留规则，以及 `hook`、`command`、`cwd`、`shell`、
  `exitCode` 这些便捷字段的读取约定。
- 明确 zsh、bash、fish 的 shell integration 只需要对齐同一组 logical
  hook names，不把 shell 自己的函数名暴露成公共 API。
- 为事件顺序、兼容性和 unknown hook passthrough 补测试与文档。

## Non-goals

- 不重做 `native/core` 的 DCS `hook;<hex-json>` 协议。
- 不修改 `flutterm_pty` 的 `PtyEvent` wire shape，除非测试先证明当前
  payload 缺少这份任务明确依赖的字段。
- 不在这次任务里实现 Ianvs Terminal 的 block 模型、cwd-aware completion
  或输出范围推断。
- 不把 xterm facade 扩展成第二套 shell-hook API；这次只收口 runtime
  controller 的公共 surface。

## Files In Scope

- `packages/flutterm_terminal/lib/src/runtime/terminal_runtime_controller.dart`
- `packages/flutterm_terminal/test/terminal_runtime_controller_test.dart`
- `packages/flutterm_terminal/README.md`
- `docs/tasks/runtime-pty/T-063-shell-hook-typed-runtime-event-and-multi-shell-contract.md`

## Functional Acceptance

- `TerminalRuntimeController.events` 对每个
  `PtyEvent(kind: "shell_hook")` 都发出 `TerminalSessionShellHookEvent`。
- `TerminalSessionShellHookEvent` 固定包含：
  - `sessionId`
  - `rawPayload`
  - `hook`
  - `command`
  - `cwd`
  - `shell`
  - `exitCode`
- `rawPayload` 必须完整保留 backend 原始 map。便捷字段只做轻量解析；
  字段缺失时返回 `null`，不写空字符串，不伪造默认值。
- Unknown hook 名称必须原样透传。runtime 层不能因为只认识
  `preexec`、`command_finished`、`precmd`、`precmd.pwd` 就丢弃其他 hook。
- 同一 poll batch 里若先收到 `shell_hook` 再收到 `exit`，runtime 必须先发出
  `TerminalSessionShellHookEvent`，再发 `TerminalSessionExitEvent`。
- 现有 frame 拉取、scrollback refresh、clipboard 和 resize 行为不因
  shell-hook typed event 而改变。
- multi-shell 契约固定为 logical hook names：
  - zsh baseline：`preexec`、`command_finished`、`precmd`、`precmd.pwd`
  - bash / fish follow-up：也要映射到同一组 logical hook names
  - 某个 shell 给不出某个字段时可以省略，但不能发 shell 专属字段名来替代

## Verification Commands

参考 [TESTING.md](../../TESTING.md)，本任务属于 runtime / shell 边界改动，
验证按完整链路跑：

```bash
cd native/core
cargo test shell_hook
```

```bash
cd packages/flutterm_pty
dart test
```

```bash
cd packages/flutterm_terminal
flutter test test/terminal_runtime_controller_test.dart
flutter test
```

## Manual QA

1. 在真实 zsh shell 里执行 `echo ok`、`false`、长命令后 `Ctrl-C`，确认
   consumer 能收到 `preexec`、`command_finished`、`precmd`、
   `precmd.pwd` 的 typed runtime event。
2. 确认 `command_finished` 能读到 `exitCode`，`precmd.pwd` 能读到 `cwd`。
3. 构造一个 runtime 不认识的 hook 名称，确认 `rawPayload` 和 `hook`
   仍然原样透出。
4. 在 bash / fish integration 接入后，复跑同样场景，确认 logical hook
   names 不变，只允许字段缺失为 `null`。

## Done When

- `TerminalRuntimeController.events` 有稳定的
  `TerminalSessionShellHookEvent` surface。
- raw payload 保留规则、便捷字段读取规则和 multi-shell 契约都写入文档。
- 事件顺序和 unknown hook passthrough 有自动化测试覆盖。
- 实现不引入第二套 shell-hook facade，也不要求 Ianvs Terminal 继续保留
  产品侧 raw adapter 才能消费事件。

## Risks / Follow-ups

- 如果 bash / fish integration 需要新增 payload 字段，必须先证明现有
  payload 不够，再拆 focused change；不要先扩 wire shape。
- 输出归属、command output row range 和 block render-layer 仍是后续任务，
  不由本任务顺手承担。
