# T-054 Terminal Manual Matrix Unblock

## Goal

解除当前 terminal 手工矩阵的主要执行阻塞，并把当前机器明确收口为以下二选一状态之一：

- 可用于真实 GUI smoke
- 不适合作为 `T-055` 执行机

## Scope

- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`
- `docs/tasks/T-054-terminal-manual-matrix-unblock.md`

## Non-goals

- 不修改 terminal 产品逻辑
- 不修改 Rust core / FFI / frame schema
- 不在本任务里执行完整 VT220 / prompt / trackpad / DPI 矩阵
- 不把 `HardwareKeyboard` 问题顺手混进 terminal 功能任务

## Functional Acceptance

- 当前机器对 `flutter run -d macos` 的前置台 / 可交互路径有明确结论：
  - 要么可用于真实 GUI smoke
  - 要么被明确记录为 `unsuitable local host`，并附复现步骤与具体错误文本
- `vttest` 的前置条件被明确写出，并在当前机器上验证是否可用
- 若再次出现 `HardwareKeyboard` 重复 `KeyDownEvent` 断言，必须单开独立排障任务
- 诊断证据必须包含主机、桌面会话、Flutter 工具链、设备可见性和 app bundle / 进程观测结果，而不是只记一句 blocker 结论

## Verification Commands

```bash
cd /Users/robinfai/personal/flutterm
zsh -lic 'type flutterm_no_proxy'
zsh -lic 'flutterm_no_proxy ./tools/check_terminal_manual_matrix_prereqs.sh'
command -v vttest || true

cd /Users/robinfai/personal/flutterm/app
zsh -lic 'flutterm_no_proxy flutter --version'
zsh -lic 'flutterm_no_proxy flutter doctor -v'
zsh -lic 'flutterm_no_proxy flutter devices'
zsh -lic 'flutterm_no_proxy flutter test integration_test/flutterm_smoke_test.dart'
zsh -lic 'flutterm_no_proxy flutter run -d macos'
zsh -lic 'flutterm_no_proxy flutter run -d macos --host-vmservice-port 49200'
```

## Manual QA

1. 从已登录的 macOS 桌面会话里的 Terminal / iTerm 打开一个全新的 login shell，不要并行启动多个 `flutter` 命令
2. 先执行 `type flutterm_no_proxy`，确认 `~/.zshrc` 已加载 no-proxy helper
3. 若 `command -v vttest` 为空，再处理 Homebrew / PATH；若已有路径则不要再把 `vttest` 当成 blocker
4. 运行 `flutterm_no_proxy ./tools/check_terminal_manual_matrix_prereqs.sh`，记录主机、桌面会话、proxy 环境、Flutter 工具链、设备、integration smoke 和 `flutter run` 证据
5. 单独运行 `flutterm_no_proxy flutter run -d macos`，人工确认 app 是否真正前置到真实可交互桌面
6. 若仍提示 foreground failure，再运行 `flutterm_no_proxy flutter run -d macos --host-vmservice-port 49200`，检查 VM Service 是否稳定、app 是否实际已在前台
7. 若运行期间复现 `HardwareKeyboard` 重复 `KeyDownEvent`，记录最小复现并拆出新任务
8. 若 helper/no-proxy 会话下仍不能完成前台交互确认，停止继续在本机深挖，并把当前机器标记为 `unsuitable local host`

## Current Status

`2026-04-22` 本机复跑结果：

- `zsh` login shell no-proxy helper: `pass`
  - `~/.zshrc` 现已导出 `no_proxy=127.0.0.1,localhost,::1`
  - `NO_PROXY` 同步为相同值
  - `flutterm_no_proxy` helper 已可在新 login shell 中直接调用
- `command -v vttest`: `pass`
  - 当前机器可直接解析到 `/opt/homebrew/bin/vttest`
  - 旧的 “`vttest` 未安装 / Homebrew Formula API 超时” 结论已不再是当前 blocker
- `flutterm_no_proxy ./tools/check_terminal_manual_matrix_prereqs.sh`: `blocked`
  - `2026-04-22 00:28 CST` 的 no-proxy preflight 证明当前机器处于本地 GUI 桌面会话：
    - host: `BINGHUILUO-MB3`
    - macOS: `15.7.3 (24G419)`
    - `launchctl gui/501` 可见，AppleScript 可查询 frontmost app
  - 同一轮 preflight 里，proxy 环境已按预期被 helper 清空：
    - `http_proxy`: `unset`
    - `https_proxy`: `unset`
    - `all_proxy`: `unset`
    - `no_proxy`: `127.0.0.1,localhost,::1`
  - 但 Flutter 侧运行链仍不稳定：
    - `flutter doctor -v`: `blocked`，20 秒超时；已确认 Flutter 本体正常，但 Android toolchain / Xcode 仍有环境警告
    - `flutter devices`: `blocked`，20 秒超时且无输出
    - `flutter test integration_test/flutterm_smoke_test.dart`: `blocked`，60 秒超时且无输出
    - `flutter run -d macos`: `blocked`，虽已观测到 Dart VM Service / app process / app bundle，但 Flutter tool 仍打印 `Failed to foreground app; open returned 1`
- 单独 `flutter run -d macos`: `blocked`
  - 在 no-proxy 会话下，preflight 内的 `flutter run -d macos` 已能看到：
    - `Dart VM Service observed: yes`
    - `app process likely observed: yes`
    - `app bundle observed: yes`
  - 这说明 shell 层代理已不再阻断本地 VM Service 路径
- 固定端口 `flutter run -d macos --host-vmservice-port 49200`: `partial pass`
  - `2026-04-22 00:31 CST` 的直接重跑可稳定构建 `build/macos/Build/Products/Debug/app.app`
  - Flutter tool 仍打印 `Failed to foreground app; open returned 1`
  - 但同一轮运行已成功暴露固定 VM Service：
    - `http://127.0.0.1:49200/...`
  - 运行中查询系统状态时：
    - frontmost app 查询返回 `app`
    - frontmost unix pid 返回 `64518`
    - `visible` 为 `true`
  - 这证明当前更像是 Flutter tool 的前置台判定异常或竞态，而不是 app 实际没有进入前台
- `HardwareKeyboard` 重复 `KeyDownEvent`: `blocked`
  - 这轮复跑未再次触发
  - 由于仍未完成一次已确认键盘输入的前台 terminal 会话，暂时不能视为风险收敛

基于这轮结果，`T-054` 已从“代理/`vttest`/GUI 会话都不确定”推进到“shell no-proxy 已生效、`vttest` 已可用、Flutter 能建立本地 VM Service，剩余 blocker 集中在 Flutter tool 的 foreground 判定和人工键盘交互确认”。当前机器比之前更接近 `usable for real GUI smoke`，但在完成键盘交互确认前仍不能当作 `T-055` 完成机。

## Done When

- 当前机器已被明确归类为 `usable for real GUI smoke` 或 `unsuitable local host`
- 手工矩阵的主要执行阻塞有明确状态，不再停留在口头结论
- `docs/TESTING.md` / `docs/KNOWN_ISSUES.md` 与最新环境证据一致
- VT220 手工矩阵已经具备可准备、可执行的前置说明

## Risks / Follow-ups

- 某些阻塞可能属于当前运行环境，而不是仓库本身；如果确认如此，文档必须明确标注环境范围
- 残留的 `flutter` startup lock / 并发诊断命令会污染本机证据；复跑时必须串行执行 Flutter 命令
- 本任务完成后，完整兼容性矩阵仍留给 `T-055`
