# Trail Known Issues

这份文档只记录当前已接受的限制、缺口和临时取舍。

## 当前已知边界

- macOS 是当前主交付平台；iOS 已实现 SSH 配置、保存和会话流程，但尚未完成实体设备上的完整产品验收
- 当前支持 local shell 与基于 Rust 的 SSH session；两者共用现有 tab、pane 与 layout 模型
- scrollback 搜索目前只支持本地纯文本搜索
- 已支持 xterm synchronized output mode；剩余风险主要是性能回归自动化和更宽宿主环境验证
- 还没有插件系统
- 当前没有 native renderer
- 当前没有 `wgpu` renderer

## 当前技术取舍

- terminal viewport 先使用 Flutter Canvas，而不是 native renderer
- Flutter 与 Rust 的帧及图形传输使用 Protobuf Terminal Frame Packet v1 与 Graphic Asset Packet v1；配置、请求及事件使用各自当前版本化合同，旧 JSON frame diff 不再是当前帧传输边界
- macOS 运行依赖把 Rust 动态库打进 app bundle
- 为了让本地 shell MVP 可运行，当前没有启用 app sandbox

## 当前缺少的非功能性保障

- 已有首批本地性能基线 evidence（`docs/evidence/2026-05-29-benchmark/` 与 `TERMINAL_XTERM_RECENT_FIX_AUDIT.md` 里的 release snapshots），并且 `tools/bench/configs/bench_ci_smoke.yaml` 已覆盖轻量 p95 frame-build / JSON decode / apply 回归 gate，也会采集 `os_resource.ndjson` 的 CPU/RSS 样本。`tools/bench/configs/bench_nightly_resource.yaml` 可通过 `VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH=1` 接入 verify 脚本，在 quiet-host/nightly lane 对 `max_p95_process_cpu_percent` 与 `max_peak_process_rss_bytes` 做资源阈值门禁；但还没有 cross-machine 对比基线
- 还没有跨平台验证
- SSH 自动化目前覆盖 OpenSSH 的密码、keyboard-interactive/OTP、公私钥、两跳 ProxyJump、host-key 策略、L/R/D/agent forwarding 与安全 X11 转发；更宽的服务器版本、发行版和真实网络环境矩阵尚未验证
- local-only terminal 手工矩阵已于 `2026-05-06` 在 `T-059` 实际执行；当时发现的真实失败项已拆到 `T-066`、`T-067`、`T-068` 并完成，`T-059` 仍作为历史矩阵入口保留
- local-terminal P0-P5 required closure baseline 已由 canonical verification records 标记为 verified；对应入口见 `docs/LOCAL_TERMINAL_VERIFICATION_MANIFEST_2026-05.json`、`docs/LOCAL_TERMINAL_COMPLETION_AUDIT_CHECKLIST_2026-05.md` 和 `tools/local_terminal_verification_status.sh`。剩余风险主要是 advanced visual/productivity/policy follow-up、跨平台验证、性能回归自动化和更宽的宿主环境矩阵，不应再把 required closure baseline 记录为缺 evidence。
- macOS 本地 SSH 重启重连、录制回看和配置表单已完成隔离 release 的真实 GUI 验收，见 [2026-09-09 验收证据](evidence/macos-acceptance-20260909/README.md)。这不覆盖 API 同步联机、iOS 实体设备、安装发布或完整辅助访问验收。

## 当前环境相关风险

- `flutter test -d macos integration_test/ianvs_terminal_smoke_test.dart` 的历史运行可能打印 `Failed to foreground app; open returned 1`；本轮隔离 production release GUI 验收已完成启动、重启、SSH 重连和录制发现，但该 smoke 输出仍可作为环境噪声单独跟踪。
- 默认 verification helper 现在用 `flutter test -d macos ...` 运行 integration smoke，避免当前 host 卡在 Flutter device discovery 的 Android `adb devices` 路径；手工 ad-hoc 跑 integration smoke 时仍不要省略 `-d macos`。这属于本机验证环境风险，不是 terminal 产品回归。
- Computer Use 可操作大部分 macOS UI，但回放及录制库的原生 AX 树仍可能停留在旧内容。2026-09-10 已修复回放图标按钮名称与点击动作分离、录制库关闭/刷新按钮缺少名称的问题，并通过真实语义节点操作回归；这不等于原生 AX 或 VoiceOver 已通过。详见 [辅助访问补充验收](evidence/macos-accessibility-20260910/README.md)。

## 当前已接受的延期风险

- Unicode 真实终端列宽已不再按 rune 计列：Rust parser 和 Flutter `TerminalTextCells` 已覆盖 CJK、combining marks、emoji presentation/ZWJ/tag/keycap/flag cluster、Powerline 与 Nerd Font private-use glyph 的列宽和 continuation cell。剩余风险主要是宿主机器缺少对应字体时的视觉 fallback box，需要在字体/profile 变更时做视觉 smoke。
- `2026-04-23` 决定先不把 `ps1 diag export` 接到真实 live shell prompt。当前导出链默认仍基于 repo 内固定 fixture，所以 `ps1-current.png`、`shell-surface-current.png` 适合做稳定回归和几何排查，不等于真实用户会话截图。拿它和 Kaku 对比时，要把这个限制算进结论里。

## 使用建议

- 如果一次改动碰到主链路，请默认做完整 smoke 流程
- 如果某个限制不再成立，应同步更新这里以及 `README.md`
