# T-065 Phase 4 Windows and Linux Validation Gate

## Goal

把 `FT-012` 从“跨平台风险提醒”收口成可执行的验证门槛，在拿到证据前，
不把 Windows / Linux 写成已支持。

## Scope

- 定义 Windows 和 Linux 各自必须给出的 PTY / runtime / packaging 证据矩阵。
- 固定 `pass` / `fail` / `blocked` 的判定规则和分流规则。
- 把 Phase 4 文档改成“validation gate”口径，而不是平台支持承诺。
- 明确缺少 host、toolchain、Flutter target 或交互桌面时应如何记为 `blocked`。

## Non-goals

- 不在本任务里做 Linux / Windows 平台适配实现。
- 不承诺 UI parity、字体 fidelity、renderer 行为或 SSH 能力已跨平台对齐。
- 不把 host/tooling blocker 写成产品回归。
- 不在没有证据时把 `flutter build linux` / `flutter build windows` 成功想象成
  “平台已支持”。

## Files In Scope

- `docs/tasks/verification-gates/T-065-phase4-windows-linux-validation-gate.md`
- `docs/ROADMAP.md`
- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`

## Functional Acceptance

- Windows 和 Linux 都必须逐项记录以下结果，每项只允许 `pass`、`fail`、
  `blocked`：
  - native/core build
  - native/core artifact export proof
  - PTY spawn
  - resize
  - search
  - selection text
  - shell-hook event propagation
  - Flutter packaging / runnable app evidence
- Linux 的 artifact export proof 至少接受以下任一证据：
  - `nm -D native/core/target/debug/libianvs_core.so`
  - `llvm-nm --defined-only native/core/target/debug/libianvs_core.so`
- Windows 的 artifact export proof 至少接受以下任一证据：
  - `dumpbin /exports native/core/target/debug/ianvs_core.dll`
  - `llvm-nm --defined-only native/core/target/debug/ianvs_core.dll`
- `blocked` 固定只用于 host、toolchain、Flutter target、桌面交互权限或
  shell 前置条件未满足。
- `fail` 固定只用于证据已经跑起来，但 PTY / runtime / packaging 行为错误。
- 任何 `blocked` 或 `fail` 都不能被写成“已支持”；Phase 4 只能在对应平台
  关键子项全部拿到非 blocked 证据后才算进入实现或验收讨论。
- 文档口径必须明确：`T-065` 是 validation gate，不是 support checklist。

## Verification Commands

参考 [TESTING.md](../../TESTING.md)。这份任务的验证固定拆成 baseline 与
target-host 两层：

```bash
cd native/core
cargo test
```

```bash
cd packages/ianvs_pty
dart test
```

```bash
cd packages/ianvs_terminal
flutter test
```

Linux target-host evidence:

```bash
cd example
flutter build linux
flutter run -d linux
```

```bash
nm -D native/core/target/debug/libianvs_core.so | rg "ianvs_session_search_json|ianvs_session_selection_text"
```

Windows target-host evidence:

```bash
cd example
flutter build windows
flutter run -d windows
```

```bash
dumpbin /exports native/core/target/debug/ianvs_core.dll
```

## Manual QA

1. 在 Linux 和 Windows 的目标机上分别启动一个本地 shell session。
2. 运行 `echo ok`，确认 spawn、输出、search、selection text 都工作。
3. 做一次窗口 resize，确认 rows / cols 和 viewport 内容同步更新。
4. 触发一轮 shell hook，确认 event 能传到 consumer，而不是只在 native /
   FFI 层消失。
5. 记录 host、OS、toolchain、artifact 路径、Flutter target、结果和 blocker。
6. 如果当前平台缺 target、缺 GUI 会话、缺 shell 前置条件或根本跑不起 app，
   立刻记为 `blocked`，不要继续包装成“只差一点点”。

## Done When

- Windows 和 Linux 的矩阵项都有明确结果，或明确的 `blocked` 证据。
- `blocked` 与 `fail` 的分流规则已经写进文档。
- `docs/ROADMAP.md`、`docs/TESTING.md`、`docs/KNOWN_ISSUES.md` 的口径都不再
  把 Phase 4 写成默认已支持。
- 后续 Phase 4 工作在开始前，已经知道自己缺的是 host/tooling 证据还是
  真正的实现缺口。

## Risks / Follow-ups

- Windows shell integration 很可能需要 PowerShell / shell profile 的单独 follow-up，
  不能直接复用 macOS zsh 路径来假设已通。
- Linux / Windows 的字体、输入法、trackpad / wheel fidelity 不是这份 gate
  的完成条件；如果后续要追这些体验，需要拆独立任务。
