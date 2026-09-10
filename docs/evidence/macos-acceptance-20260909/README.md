# macOS 主流程真实 GUI 验收证据

后续记录：[2026-09-10 辅助访问补充验收](../macos-accessibility-20260910/README.md)。
用户已退出本轮遗留的旧实例；后续测试实例也已清理。以下保留 2026-09-09 的原始结果。

日期：2026-09-09。目标是隔离的 production release target，入口为
`example/tool/macos_acceptance.dart`。验收使用独立的 `/tmp` 数据目录和独立的
macOS Keychain namespace；未使用共享开发数据。数据 API 保持未配置，结论只覆盖
本地模式。

源码基线：`5a9755964bf0a46305cc99dcce798061443398e9`，加上随本验收记录提交的修复。
所有窗口操作、输入和截图均通过 Computer Use 执行；CLI 只用于构建、测试、
测试容器管理和只读诊断。没有使用 mock PTY、mock SSH 或 provider 测试替身。

## 已验收路径

- 使用真实 native PTY、真实 loopback SSH 和录制文件完成本地 SSH 主流程。
- 连接 `127.0.0.1:32768` 上的 Colima OpenSSH fixture，用户为 `ianvs`，使用唯一测试 profile。
- 创建并保存 profile；输入错误密码后编辑为正确凭据；连接后确认远端为
  `uname=Linux`。
- 退出并重启 release app 后，profile 和凭据仍在，并可再次连接。
- 真实 SSH 会话开始录制，执行 `echo TRAILACCEPTANCE20260909`，停止并保存；
  重启后录制仍可发现。修复回放路径错误拦截 SSH profile 后，录制可成功播放。
- 回放搜索得到 4 个匹配；Copy Visible 复制后粘贴到原生 TextEdit，确认包含完整
  `Linux` 输出和 `TRAILACCEPTANCE20260909` marker。临时 TextEdit 文稿已关闭并点选不保存。
- 设置路径覆盖 800x600 浅色/深色菜单、642x500 紧凑布局、箭头键与 Return 选择、
  Escape 仅关闭 dropdown 并恢复 trigger 焦点、滚动与固定 footer，以及暗色偏好保存。
- 真实快捷键搜索框完成 Cmd+A 原生菜单修复后的 before → 全选 → after 精确替换验证。
- 最终 release 复验：回放终端初始焦点下直接按 Escape 可关闭播放器；Tab 可进入
  回放控制区。SSH fixture 停止后，旧录制仍可离线打开。
- fixture 重启后 Docker 动态端口从 32768 变为 32769；在同一个已保存 Profile
  中使用 Cmd+A 修改端口、保存到本机，再重连并执行 `uname` 得到 `Linux`。
  修改保存时旧连接错误仍保留，开始同 Profile 重试后错误消失；没有手动关闭横幅。

## 本轮发现并修复

| 问题 | 修复 | 验证 |
| --- | --- | --- |
| SSH 录制被 live SSH capability 检查拒绝 | 仅真实 `TerminalReplayBackend` 跳过 live SSH 能力要求，普通 backend 仍保留检查 | 正反 SDK 回归、原失败录制真实播放、SSH 离线打开 |
| macOS 文本框 Cmd+A 无效 | 原生 Edit → Select All 转发到当前路由的焦点 EditableText | Flutter 回归、真实搜索框替换、SSH 端口替换、原生 Swift 菜单回归 |
| 同主机重试后旧 SSH 错误残留 | 按 Profile ID 和原始错误文本匹配清理，不清除其他 Profile 或较新的错误 | controller 回归、真实离线失败后编辑并重连 |
| 只读回放终端吞掉 Escape/Tab | 将这两个键交还宿主快捷键和焦点遍历 | viewport 焦点 widget 回归、真实窗口初始 Escape 和 Tab |

## 自动化证据

最终完整 `make verify` 于 2026-09-09 通过，退出码为 0，macOS 集成未跳过。
关键输出保存在 [verification-summary.txt](verification-summary.txt)。

| 默认门禁 | 结果 |
| --- | --- |
| Rust、Go、生成合同、SDK 镜像一致性 | 通过 |
| Dart 格式及静态分析 | 通过，728 个文件无需格式修改 |
| PTY / terminal / terminal_core tests | 39 / 636 / 680 项通过；后两个套件各保留 1 项既有跳过 |
| 文档合同 / 根目录合同 | 14 / 26 项通过 |
| 应用 unit、widget 和 golden tests | 192 个文件、1,790 项通过 |
| macOS 启动 / 真实 PTY / Keychain 集成 | 4 / 45 / 1 项通过 |
| Debug、两次 Release 构建及签名、原生合同 | 通过 |
| macOS RunnerTests | 27 项通过 |

默认门禁的 nightly resource benchmark 与需要专用环境的既有跳过项仍按原脚本
处理，不把它们计入本轮覆盖。

本轮记录的 focused checks 包括：

- recording library 与 session controller focused tests：107 项通过；
- replay SDK tests：27 项通过；
- phase 4 tests：92 项通过；
- 录制生命周期 tests：33 项通过；
- 3 个 app-surface golden 在更新后通过。

门禁还暴露并修复了三处测试维护问题：原生 RunnerTests 的 Swift 模块导入对齐
品牌更名后的 `Trail_Development`；resolved-analyzer 架构扫描在独立复跑中也超过
默认 30 秒，为该文件设置 2 分钟上限，保留全部架构断言；两个录制测试改为等待
shutdown coordinator 安全完成后再释放容器、删除目录，避免异步写盘与清理竞态。
未吞掉文件系统异常或跳过录制断言。修复后应用全量测试连续两次通过，其中一次
属于最终完整 `make verify`。

## 截图索引

`01-ssh-connected-stale-error.png` 和 `06-ssh-replay-error.png` 保留为修复前失败证据。

- `02-ssh-connected.png`：正确凭据连接后的 SSH 主流程
- `03-recording-saved.png`：录制停止保存
- `04-ssh-reconnected-after-restart.png`：重启后 SSH 重连
- `05-recording-found-after-restart.png`：重启后发现录制
- `07-dropdown-light.png`、`08-local-only-mode.png`、`09-dropdown-dark.png`、
  `10-dropdown-compact.png`：设置布局和本地模式
- `11-ssh-replay-playing.png`：SSH 录制成功播放
- `12-replay-search.png`：回放搜索结果
- `13-native-select-all.png`：原生 Cmd+A 搜索框行为
- `14-replay-copy-to-textedit.png`：复制可见内容并在 TextEdit 验证
- `15-replay-tab-focus.png`：Tab 焦点进入回放时间轴
- `16-ssh-offline-error.png`：测试 SSH 服务离线后的真实错误
- `17-replay-escape-from-viewport.png`：从回放初始终端焦点按 Escape 后回到主界面
- `18-ssh-edit-port.png`：本地 SSH 表单端口编辑
- `19-ssh-retry-clears-error.png`：同 Profile 重试成功，旧错误横幅消失

## 隔离构建与环境

从 `example` 目录构建：

```sh
flutter build macos --release --target tool/macos_acceptance.dart \
  --dart-define=TRAIL_ACCEPTANCE_DATA_DIRECTORY=/tmp/trail-macos-acceptance-20260909/data \
  --dart-define=TRAIL_ACCEPTANCE_KEYCHAIN_ACCOUNT=work.ianvs.trail.acceptance.20260909
```

构建产物复制到 `/tmp/trail-macos-acceptance-20260909/`，修改副本的 bundle ID、
显示名称并使用 `macos/Runner/LocalRelease.entitlements` 做 ad-hoc hardened-runtime
签名。本次分别使用 `Trail Acceptance.app` 与 `Trail Acceptance Final.app`；后者
只用于绕开电脑工具缓存的旧模态窗口句柄，读取相同的验收数据。

专用 `trail-ui-acceptance-20260909` 容器已删除，Docker context 已恢复 `default`。
Colima 中另有运行中的容器，因此保留虚拟机运行。验收数据和录制保留在上述 `/tmp`
目录，方便复查；没有修改正式 Trail 的 Profile、凭据或外观设置。

## 未覆盖或待确认

回放面板在工具 AX 树中曾出现塌缩，当前仍可通过 1px 拖拽操作；尚未确认这是产品
布局问题还是 Computer Use bridge 的 AX 表示问题。因此本记录不声称 VoiceOver 或
完整辅助访问验收通过。

工具切换部分原生应用曾耗时数分钟；一次退出确认进入 `NSAlert.runModal`，工具
仍返回旧主窗，后续输入因此无效。最终复验改用新的独立 bundle ID 后完成。原旧
验收实例的模态窗口未能通过工具定位关闭，最终验收实例已正常退出。初次启动时
过早打开的设置会显示尚未加载的 Profile 列表；不能把该中间画面认作数据丢失。

本记录不覆盖 API 同步联机、iOS 实体设备、安装/发布流程、真实外网 SSH 矩阵，或
Linux/Windows 目标机验收。
