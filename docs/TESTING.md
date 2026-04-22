# flutterm Testing

这份文档集中维护标准验证命令和人工 smoke 流程。任务文档里的 `Verification Commands` 应当优先引用这里，而不是每次重新发明。

## 默认命令

### Flutter

```bash
cd /Users/robinfai/personal/flutterm/app
flutter analyze
flutter test
flutter test integration_test/flutterm_smoke_test.dart
```

### Rust

```bash
cd /Users/robinfai/personal/flutterm/native/core
cargo fmt --check
cargo test
```

### 运行应用

```bash
cd /Users/robinfai/personal/flutterm/app
flutter run -d macos
```

### Flutter 侧 terminal 验证链

推荐入口：

```bash
cd /Users/robinfai/personal/flutterm
./tools/verify_flutter_terminal.sh
```

这个入口会先刷新 `native/core/target/debug/libflutterm_core.dylib`，再运行 Flutter 侧的 `analyze` / `flutter test` / `integration_test`，避免 FFI / PTY 测试加载到过期 dylib。

## 按改动类型选择命令

### 只改 Flutter UI 或状态层

至少执行：

- `flutter analyze`
- `flutter test`

如果本次改动涉及应用启动路径、tab 管理或可见主界面冒烟，追加：

- `flutter test integration_test/flutterm_smoke_test.dart`

### 改 Rust core 或 FFI

至少执行：

- `cargo fmt --check`
- `cargo test`
- 相关 Flutter 侧测试

如果本次改动会影响 Flutter 侧 FFI / PTY / integration 验证，额外执行：

- `cd /Users/robinfai/personal/flutterm`
- `./tools/verify_flutter_terminal.sh`

### 改 terminal emulation / VT220 host-feature gating

必须执行：

- `cargo fmt --check`
- `cargo test`
- `flutter analyze`
- `flutter test test/ffi/flutterm_core_test.dart`
- `flutter test test/terminal_input_controller_test.dart`

重点确认：

- VT220 profile 继续返回 VT220 DA
- VT220 profile 不暴露 `window_title`、`window_icon_name`、OSC 52 copy/paste 事件
- 默认 xterm profile 继续保留这些 host features
- VT220 keyboard / paste contract 不回归

### 改 terminal resize / cell metrics contract

必须执行：

- `flutter analyze`
- `flutter test test/sessions/session_controller_test.dart`
- `flutter test test/terminal/render_terminal_viewport_test.dart`
- `flutter test`
- `flutter test integration_test/flutterm_smoke_test.dart`

重点确认：

- `resizeActiveSession()` 优先使用 viewport 实测 cell size，而不是长期依赖 `9x18` 硬编码
- shell-originated resize event 的 window-size translation 也使用同一条 measured cell size 链，而不是旧的 `9x18` Y 轴换算
- viewport 首帧尚未产出测量值时，fallback 行为仍可工作
- 旧的 shell-driven Y 轴 `9x18` 漂移不再应被视为“已知未修复风险”；手工矩阵现在验证的是修复后是否仍有残余问题
- `app/test/sessions/session_controller_test.dart` 已有 measured-cell shell-resize regression guardrail
- identical resize request 继续被 dedupe
- scroll、selection、cursor blink、visible-content repaint 不回归

### 改 terminal 主链路、输入、滚动、viewport

必须执行：

- `cargo fmt --check`
- `cargo test`
- `flutter analyze`
- `flutter test`
- `flutter test integration_test/flutterm_smoke_test.dart`
- `flutter run -d macos`

### 改 shell top actions / launcher surface

必须执行：

- `flutter analyze`
- `flutter test test/shell/shell_screen_phase2a_test.dart`
- `flutter test test/widget_test.dart`
- `flutter test integration_test/flutterm_smoke_test.dart`
- `flutter run -d macos`

重点确认：

- launcher 入口在 active shell surface 上显式可见
- launcher 打开 / 关闭路径 deterministic
- launcher 打开时不会把按键或点击泄漏到 terminal input
- launcher 关闭后 active terminal viewport 恢复可交互状态

### 改 shell shortcut scope / action scoping（Phase 2B）

必须执行：

- `flutter analyze`
- `flutter test test/shell/shell_screen_phase2b_test.dart`
- `flutter test test/widget_test.dart`
- `flutter test integration_test/flutterm_smoke_test.dart`
- `flutter run -d macos`

重点确认：

- launcher 中 app actions / session actions 的 scope 显式可见
- app-scoped shortcut 只覆盖 launcher 入口与 top action access，不扩展成更广的 command palette
- shortcut 调用路径 deterministic，且不会把触发按键泄漏到 terminal input
- 关闭 launcher 或执行 app-scoped action 后，active terminal viewport 恢复可交互状态
- session-scoped copy / paste contract 与既有 terminal keyboard contract 不回归

### 改 profile/defaults persistence（Phase 3）

必须执行：

- `flutter analyze`
- `flutter test test/preferences/app_preferences_repository_test.dart`
- `flutter test test/sessions/session_controller_test.dart`
- `flutter test`
- `flutter test integration_test/flutterm_smoke_test.dart`

重点确认：

- preferences / legacy default / first-profile fallback precedence deterministic
- preferences 缺失时不会阻塞启动，也不会在无必要时提前写文件
- corrupt preferences 会被 quarantine，并 repair-write 回最小默认文档
- 删除 default profile 后 bootstrap 会落回首个可用 profile，而不是 fatal 或继续指向悬空 id
- terminal lifecycle、copy / paste、scroll、resize、exit baseline 不回归

### 改 defaults / appearance UI（Phase 3 remaining work）

必须执行：

- `flutter analyze`
- `flutter test test/shell/shell_screen_phase2a_test.dart`
- `flutter test test/shell/shell_screen_phase2b_test.dart`
- `flutter test test/shell/shell_screen_phase3_test.dart`
- `flutter test test/sessions/session_controller_phase3_test.dart`
- `flutter test test/preferences/app_preferences_repository_test.dart`
- `flutter test test/preferences/app_preferences_repository_phase3_test.dart`
- `flutter test test/app/app_theme_mode_test.dart`
- `flutter test integration_test/flutterm_smoke_test.dart`

重点确认：

- `Defaults & appearance` modal/sheet 是唯一 defaults/theme mutation surface
- sidebar 不再 inline `Set as default`
- configured default 与 effective fallback default 在 UI 上有明确区分
- repaired/missing defaults 不会被展示成 user-selected
- `MaterialApp` 真正消费 persisted `themeMode`
- 关闭 defaults surface 后 launcher / focus / terminal input 不回归

### 改 driver-only 验收入口 / Hyper-first MCP 验收状态面

必须执行：

- `flutter analyze`
- `flutter test test`
- `flutter test integration_test/flutterm_smoke_test.dart`

Live MCP 验收入口固定为：

- `root=/Users/robinfai/personal/flutterm/app`
- `target=lib/driver_main.dart`

Live 验收重点确认：

- `flutter_driver.get_health` 成功
- `flutter_driver.waitFor(ByValueKey: shell-chrome-menu)` 成功
- `flutter_driver.tap(shell-chrome-menu)` 若超时，必须立即同时检查：
  - screenshot 是否已显示 command menu
  - Dart MCP `get_widget_tree(summaryOnly=true)` 是否已出现 `_ShellCommandMenu`
  - driver `request_data(shell.acceptance)` 的状态快照是否变化
    - `visibleOverlay` 是否已变成目标值
    - `snapshotVersion` 是否递增

结果分类：

- `App pass`
  - tap 返回成功，且状态快照 / widget tree / screenshot 一致
- `Tool blocker`
  - tap 返回超时，但 screenshot 或 widget tree 已显示目标状态
  - 不再把这类结果归因为产品代码失败

## 自动化 Smoke

当前最小自动化 GUI 冒烟命令：

```bash
cd /Users/robinfai/personal/flutterm/app
flutter test integration_test/flutterm_smoke_test.dart
```

当前覆盖范围：

- 应用启动
- 主 terminal UI 渲染
- 新建 tab
- 关闭非激活 tab 焦点保持
- 关闭激活 tab 焦点迁移
- shell `exit` 后最后一个 tab 回到空状态
- 关闭最后一个 tab 后进入 empty-state
- shell `exit` 后最后一个 tab 回到 empty-state
- 从 empty-state 通过 `New Tab` 恢复
- shell `exit` 后回到 empty-state 再通过 `New Tab` 恢复
- 恢复后再次关闭并重新回到 empty-state
- active-state / empty-state 切换时 `TerminalViewport` 与 `Copy` / `Paste` 一起正确隐藏或恢复，同时保留 `New Tab` 恢复入口
- `Paste` 按钮写入 active session
- `Paste` 按钮空剪贴板 no-op
- `Paste` 按钮保留多行文本换行
- `Copy` 按钮写入系统剪贴板
- `Copy` 按钮空选区 no-op
- `Copy` 按钮保留多行选区换行
- `Copy` 按钮保留反向多行选区换行
- `Copy` 按钮对越界多行选区安全裁剪
- `Copy` 按钮保留非对称多行列范围
- 滚轮事件 -> core scroll 调用
- scroll 后 frame diff 驱动的可见内容 repaint
- 布局尺寸变化 -> core resize 调用
- resize 后 frame diff 驱动的可见内容 repaint
- Rust core 交互式 PTY 输入 -> 输出最小往返
- Flutter 侧 FFI -> PTY -> 输出最小往返
- Flutter 侧 FFI -> PTY 多命令往返
- Flutter 侧 FFI -> PTY 长输出后继续交互
- Flutter 侧 FFI -> PTY 在不同 prompt 配置下保持交互
- Flutter 侧真实 shell `exit` 事件传播
- shell `exit` 后活动 tab 焦点迁移
- 多行选区文本提取语义（换行、反向拖选、裁剪、非对称列范围、block 选择）
- shell workspace chrome / session tabs panel / richer empty-state shell surfaces
- top actions launcher surface open / close / new-tab path
- Phase 3 defaults / persistence bootstrap 不改变 shell startup / active-session 主链路
- Defaults & appearance surface open / close 不离开 shell 主链路

当前未覆盖：

- 自动化未直接证明、仍需人工验证的 terminal 矩阵：
  - VT220 `vttest` 基本矩阵
  - powerline / ANSI prompt fidelity
  - 真实 trackpad scrollback 交互
  - 不同字体度量 / DPI 下的 resize 与 window-size translation
  - 若后续扩展 block selection 的快捷键 / 空格 padding 语义，再补专项回归

## Terminal 手工矩阵

以下矩阵目前不应被自动化通过结果替代：

1. VT220 `vttest`
2. powerline / ANSI prompt fidelity
3. 真实 trackpad scrollback
4. 字体度量 / DPI resize

建议记录格式：

- `pass`
- `fail`
- `blocked`

推荐先运行：

```bash
cd /Users/robinfai/personal/flutterm
./tools/check_terminal_manual_matrix_prereqs.sh
```

本机 unblock 顺序：

1. 从已登录的 macOS 桌面会话里的 Terminal / iTerm 打开一个全新的 login shell，并串行运行诊断命令，不要并行启动多个 `flutter` 命令
2. 直接用显式环境变量清掉代理，不要假设 `flutterm_no_proxy` helper 一定存在
3. 执行 `command -v vttest`；如果已有路径，不要再把 `vttest` 当成当前 blocker
4. 运行显式 no-proxy 的 `./tools/check_terminal_manual_matrix_prereqs.sh`，先收集主机、桌面会话、proxy 状态、Flutter 工具链、设备可见性和 `flutter run` 证据
5. 再单独执行 `cd app && env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY no_proxy=127.0.0.1,localhost,::1 NO_PROXY=127.0.0.1,localhost,::1 flutter run -d macos --host-vmservice-port 49200`
6. 若 app 实际启动，先记录 frontmost app 与 `visible` 状态，再尝试点击 terminal viewport 并执行最小输入链：`y`、`Backspace`、`pwd`、`echo hello`、`ls`
7. 若固定端口重试下 app 仍不是 frontmost，或当前会话没有辅助访问 / 截图权限导致无法确认输入，会话应被记为 `unsuitable local host`
8. 若运行期间复现 `HardwareKeyboard` 重复 `KeyDownEvent`，记录为环境风险并按 `T-055` 现有分叉规则新开环境任务

脚本输出中的 `flutter run -d macos` 预检结果也必须固定使用 `pass` / `fail` / `blocked`。只要脚本本身无法证明 app 已进入真实可交互前置台，就默认按 `blocked` 处理，不要写成模糊状态。

脚本现在还会输出以下本机证据，便于 `T-054` 收口：

- host 与 macOS 版本
- 当前 shell 是否具备本地桌面会话证据
- 当前 shell 的 `http_proxy` / `https_proxy` / `all_proxy` / `no_proxy`
- `flutter --version`
- `flutter doctor -v`
- `flutter devices`
- `flutter run -d macos` 的 app bundle / 进程观测结果

当前机器 verdict 记录字段固定为：

- 绝对时间
- host / macOS
- branch 与 `HEAD`
- 固定端口 VM Service 是否出现
- frontmost app / `visible` 结果
- 输入链是否完整执行
- `y` / `Backspace` 是否触发异常
- `pwd` / `echo hello` / `ls` 是否真正进入 terminal
- 最终 verdict

如果诊断过程中出现 `Waiting for another flutter command to release the startup lock...`，先清掉残留 `flutter` 进程，再按上述顺序串行重跑，不要把并发锁竞争误记成 terminal 产品回归。

如果 `vttest` 未安装、`flutter run -d macos` 无法前置台，或环境缺少真实 trackpad / DPI 切换条件，应显式记为 `blocked`，不要省略。

当前环境记录（2026-04-22）：

- `shell no_proxy helper`: `fail`
  - `zsh -lic 'type flutterm_no_proxy'` 返回 `flutterm_no_proxy not found`
  - 当前会话改用显式 no-proxy 环境变量，不再依赖 helper
- `VT220 vttest`: `pass`
  - `command -v vttest` 当前返回 `/opt/homebrew/bin/vttest`
- `desktop GUI session`: `pass`
  - `2026-04-22 11:11 CST` 的显式 no-proxy preflight 证明当前机器存在本地 GUI 桌面会话
  - host: `BINGHUILUO-MC6`
  - macOS: `26.3.1 (25D771280a)`
  - branch: `codex/hyper-first-shell`
  - `HEAD`: `758b5c4e57555a7176fe66cbdc7d818cda3ab901`
  - `launchctl gui/501` 可见，AppleScript 可查询 frontmost app
  - frontmost app 查询结果为 `Codex`
  - 同一轮脚本中 `http_proxy` / `https_proxy` / `all_proxy` 已全部显示为 `unset`
- `flutter doctor -v`: `pass`
  - Flutter 本体正常，但 Android toolchain / Xcode 仍有环境警告
- `flutter devices`: `pass`
- `integration_test/flutterm_smoke_test.dart`: `pass`
- `flutter run -d macos`: `blocked`
  - 显式 no-proxy preflight 下仍打印 `Failed to foreground app; open returned 1`
  - 但同一轮脚本已观测到 `Dart VM Service observed: yes`、`app process likely observed: yes`、`app bundle observed: yes`
- `UI elements enabled`: `blocked`
  - `osascript -e 'tell application "System Events" to get UI elements enabled'` 返回 `false`
  - 当前会话仍无辅助访问权限，不能完成已确认的点击和键盘输入
- `fixed-port flutter run`: `blocked`
  - `2026-04-22 10:11 CST` 的固定端口重跑可稳定暴露本地 VM Service：`http://127.0.0.1:49200/...`
  - 运行中的 app 进程 PID 为 `57519`
  - `visible: true`
  - 但 frontmost app 仍不是 `app`
  - `tell application "app" to activate` 没能把 app 带到前台
  - `System Events` 辅助访问被拒绝，`screencapture -x` 也失败，因此这轮无法完成点击 viewport 与键盘输入确认
- `HardwareKeyboard` 重复 `KeyDownEvent` 断言: `blocked`
  - 这轮没有复现
  - 但 `y` / `Backspace` 根本没有进入已确认前台 terminal，会话风险不能视为已收敛
- `foreground keyboard confirmation`: `blocked`
  - 输入链执行状态：未完成
  - `y` / `Backspace`: 未执行
  - `pwd` / `echo hello` / `ls`: 未执行
  - 最终 verdict：`unsuitable local host`
- `T-055` 本机执行状态: `blocked`
  - `vttest` 已到位，不再是当前 blocker
  - 当前 remaining blocker 集中在 foreground failure、辅助访问权限未开、无法完成已确认键盘输入，以及真实 trackpad 与字体度量 / DPI 条件缺失
  - 当前更合理的下一步是把 `T-054` 收口为 `unsuitable local host`，并把 `T-055` 继续放到标准交互式 macOS 开发机完成

若任一 terminal 手工矩阵子项结果为 `fail`，必须立即拆成 focused task，并包含最小复现、影响范围，以及最小验证命令或明确的手工验收线。若结果是 `blocked` 且原因属于 host/tooling，则继续走 `T-054` 这类环境排障路径，不要把它误记成 terminal 产品回归。

## 手工 Smoke Checklist

只要改动影响 terminal 主链路，就至少做一轮手工检查：

1. 启动应用
2. 打开一个本地 shell tab
3. 输入 `pwd`
4. 输入 `echo hello`
5. 输入 `ls`
6. 复制一段文本并粘贴回 terminal
7. 向上滚动查看 scrollback
8. 拖动鼠标进行线性选择
9. 调整窗口大小，确认内容和光标不乱
10. 打开多个 tab 并切换

## 高风险改动附加检查

以下改动应追加更细的人工验证：

- 输入事件映射
- selection / clipboard
- resize
- frame diff 结构
- PTY 生命周期
- profile 持久化

建议额外检查：

- 快速切换 tab
- 连续输入多行命令
- 高输出命令后 GUI 是否仍可交互
- shell 退出后的状态是否正确更新

## 结果记录要求

最终汇报里至少要说明：

- 运行了哪些命令
- 是否做了手工 smoke
- 有哪些未覆盖或未验证的风险
