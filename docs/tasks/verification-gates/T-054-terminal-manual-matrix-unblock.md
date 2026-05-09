# T-054 Terminal Manual Matrix Unblock

## Goal

解除当前 terminal 手工矩阵的主要执行阻塞，并把当前机器明确收口为以下二选一状态之一：

- 可用于真实 GUI smoke
- 不适合作为 `T-055` 执行机

## Scope

- `docs/TESTING.md`
- `docs/KNOWN_ISSUES.md`
- `docs/tasks/verification-gates/T-054-terminal-manual-matrix-unblock.md`

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
cd <repo-root>
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  no_proxy=127.0.0.1,localhost,::1 NO_PROXY=127.0.0.1,localhost,::1 \
  ./tools/check_terminal_manual_matrix_prereqs.sh
command -v vttest || true

cd example
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  no_proxy=127.0.0.1,localhost,::1 NO_PROXY=127.0.0.1,localhost,::1 \
  flutter --version
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  no_proxy=127.0.0.1,localhost,::1 NO_PROXY=127.0.0.1,localhost,::1 \
  flutter doctor -v
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  no_proxy=127.0.0.1,localhost,::1 NO_PROXY=127.0.0.1,localhost,::1 \
  flutter devices
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  no_proxy=127.0.0.1,localhost,::1 NO_PROXY=127.0.0.1,localhost,::1 \
  flutter test integration_test/flutterm_smoke_test.dart
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  no_proxy=127.0.0.1,localhost,::1 NO_PROXY=127.0.0.1,localhost,::1 \
  flutter run -d macos
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  no_proxy=127.0.0.1,localhost,::1 NO_PROXY=127.0.0.1,localhost,::1 \
  flutter run -d macos --host-vmservice-port 49200
```

## Manual QA

1. 从已登录的 macOS 桌面会话里的 Terminal / iTerm 打开一个全新的 login shell，不要并行启动多个 `flutter` 命令
2. 用显式环境变量清掉代理后再运行命令，不要依赖不存在的 `flutterm_no_proxy` helper
3. 若 `command -v vttest` 为空，再处理 Homebrew / PATH；若已有路径则不要再把 `vttest` 当成 blocker
4. 运行显式 no-proxy 的 `./tools/check_terminal_manual_matrix_prereqs.sh`，记录主机、桌面会话、proxy 环境、Flutter 工具链、设备、integration smoke 和 `flutter run` 证据
5. 单独运行显式 no-proxy 的 `flutter run -d macos --host-vmservice-port 49200`
6. 若 app 实际启动，先确认 frontmost app 与 `visible` 状态，再尝试点击 terminal viewport 并执行最小输入链：`y`、`Backspace`、`pwd`、`echo hello`、`ls`
7. 若运行期间复现 `HardwareKeyboard` 重复 `KeyDownEvent`，记录最小复现并拆出新任务
8. 若 app 不能进入已确认的前台交互，或当前会话缺少辅助访问 / 截图权限导致无法确认输入，停止继续在本机深挖，并把当前机器标记为 `unsuitable local host`

记录字段固定为：

- 绝对时间
- host / macOS
- branch 与 `HEAD`
- 固定端口 VM Service 是否出现
- frontmost app / `visible` 结果
- 输入链是否完整执行
- `y` / `Backspace` 是否触发异常
- `pwd` / `echo hello` / `ls` 是否真正进入 terminal
- 最终 verdict

## Current Status

`2026-04-22` 本机最新复跑结果：

- `shell no_proxy helper`: `fail`
  - `zsh -lic 'type flutterm_no_proxy'` 返回 `flutterm_no_proxy not found`
  - `~/.zshrc` 当前没有定义该 helper，因此本轮改用显式 no-proxy 环境变量取证
- `command -v vttest`: `pass`
  - 当前机器可直接解析到 `/opt/homebrew/bin/vttest`
  - `vttest` 已重新就位，不再是当前 host 的 blocker
- 显式 no-proxy preflight：`blocked`
  - 时间：`2026-04-22 11:11 CST`
  - host: `BINGHUILUO-MC6`
  - macOS: `26.3.1 (25D771280a)`
  - branch: `codex/hyper-first-shell`
  - `HEAD`: `758b5c4e57555a7176fe66cbdc7d818cda3ab901`
  - 本地桌面会话证据仍存在：
    - `launchctl gui/501` 可见
    - AppleScript 可查询当前 frontmost app
    - frontmost app 当时为 `Codex`
  - 同一轮 preflight 中代理已被显式清空：
    - `http_proxy`: `unset`
    - `https_proxy`: `unset`
    - `all_proxy`: `unset`
    - `no_proxy`: `127.0.0.1,localhost,::1`
  - Flutter 侧结果：
    - `flutter --version`: `pass`
    - `flutter doctor -v`: `pass`
    - `flutter devices`: `pass`
    - `flutter test integration_test/flutterm_smoke_test.dart`: `pass`
    - `flutter run -d macos`: `blocked`
      - `exit code: 124`
      - `Dart VM Service observed: yes`
      - `app bundle observed: yes`
      - `app process likely observed: yes`
      - 仍打印 `Failed to foreground app; open returned 1`
- 当前会话辅助访问状态：`blocked`
  - `osascript -e 'tell application "System Events" to get UI elements enabled'` 返回 `false`
  - 当前会话仍不具备已确认的 viewport 点击与键盘输入条件
- 固定端口 `flutter run -d macos --host-vmservice-port 49200`: `blocked`
  - 时间：`2026-04-22 10:11 CST`
  - 已稳定构建 `build/macos/Build/Products/Debug/app.app`
  - `A Dart VM Service on macOS is available at: http://127.0.0.1:49200/...`
  - app 进程 PID：`57519`
  - `visible`: `true`
  - 但 frontmost app 仍不是 `app`
  - `tell application "app" to activate` 没能把 app 切到前台
  - `System Events` 辅助访问被拒绝：`osascript` 不允许辅助访问
  - `screencapture -x` 失败：`could not create image from display`
  - 因此当前会话无法点击 viewport，也无法完成已确认的键盘输入链
- 最小输入链记录：
  - `y` / `Backspace`: 未执行；原因是没有已确认的前台输入路径
  - `pwd` / `echo hello` / `ls`: 未执行；原因相同
  - `HardwareKeyboard` 重复 `KeyDownEvent`: 本轮未复现，但由于根本没有完成输入链，不能把该风险视为已收敛
- 最终 verdict：`unsuitable local host`
  - 不是 terminal 产品逻辑失败
  - 而是当前 host 仍然无法把 app 带入已确认的前台交互状态，并且辅助访问 / 截图权限不足，无法完成决定性的键盘交互确认

基于这轮结果，`T-054` 应收口为“当前机器不适合作为 `T-055` 执行机”。后续若要继续本地主机排障，应聚焦环境权限和 host 准备；`T-055` 主线仍应迁移到满足前置条件的标准交互式 macOS 开发机完成。

## Done When

- 当前机器已被明确归类为 `usable for real GUI smoke` 或 `unsuitable local host`
- 手工矩阵的主要执行阻塞有明确状态，不再停留在口头结论
- `docs/TESTING.md` / `docs/KNOWN_ISSUES.md` 与最新环境证据一致
- VT220 手工矩阵已经具备可准备、可执行的前置说明

## Risks / Follow-ups

- 某些阻塞可能属于当前运行环境，而不是仓库本身；如果确认如此，文档必须明确标注环境范围
- 残留的 `flutter` startup lock / 并发诊断命令会污染本机证据；复跑时必须串行执行 Flutter 命令
- 本任务完成后，完整兼容性矩阵仍留给 `T-055`
