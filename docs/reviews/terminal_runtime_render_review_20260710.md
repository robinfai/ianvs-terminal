# Ianvs Terminal 运行时与渲染最终评审

日期：2026-07-11（Asia/Shanghai）

基线：`4b19f04`

最终受评代码：`63b445e9b8d8277151bffeb4e5eab8d5806bb1de`

远端分支：`origin/codex/terminal-runtime-render-review-20260710`

## 结论

整体结论：**GO**。最终代码、自动化门禁、本地 Release 签名检查和真实 macOS 界面验收均通过，没有遗留的可复现功能、交互或视觉问题。

游标 overlay 子实验的结论仍是 **NO-GO**。它降低了局部 build/paint 指标，但两次冻结端到端评估的 total-span p95 ratio 分别为 `1.6786461` 和 `1.9833154`，均高于 `<= 1.05` 的启用上限。因此生产 overlay、`TerminalCursorExperimentScope` 和 `TerminalCursorExperimentMode` 已删除，最终版本继续使用 surface 游标路径。

本报告中的“通过”只覆盖本分支定义的本地 macOS、真实 PTY、Flutter/Dart/Rust 测试和兼容性范围，不代表 Developer ID 签名、公证、Intel Mac、所有输入法或所有外部终端程序已验证。

## 已确认结果

### 运行时刷新

- 空闲刷新支持可选 native hint，并保留不支持 hint 时的兼容轮询。
- active、background 和 maximum-backoff 路径均有明确 hard ceiling。
- 真实 PTY acceptance 覆盖 native-hint 与 masked-fallback；最终证据均在 hard ceiling 内。
- 输入、resize、session activation 和异步输出会重置相应 deadline/backoff 状态。

### 渲染与图形

- terminal row picture/layout 缓存继续由 frame dirty/shift 语义驱动。
- 图形缓存以 graphics revision 与 asset revision 驱动，避免每帧集合重建。
- 绘制热路径复用 `Paint`、scratch collection 和解析结果，减少临时对象分配。
- `TerminalFocusReporter` 与 `TerminalGraphicsSync` 隔离了协调状态，但没有增加 Widget 层级或扩大公共 API。
- cursor overlay 未达到端到端收益门槛，已完整回退；最终 surface 文件与 Phase 4 基线一致。

### 帧传输

- JSON/Protobuf 共享边界限制和规范化规则。
- `automatic` 只在 backend 明确支持 Protobuf capability 时选择 Protobuf。
- 强制 JSON 或不支持 Protobuf 时保留 JSON 兼容路径。
- 已选择 Protobuf 后，空 payload、读取错误或解码失败不会在同一次读取中再次消费 JSON。
- 公共 `TerminalFrameDiff.fromJson` / `fromProtobufBytes` seam 保留。

### macOS 与本地 Release

- hidden runner 只允许 `hidden -> inactive -> resumed` 的受控恢复；其他异常 lifecycle 状态仍失败。
- Xcode Release 保持 `ENABLE_HARDENED_RUNTIME = YES`。
- `LocalRelease.entitlements` 仅启用 `com.apple.security.cs.disable-library-validation=true`。
- 本次续作构建的 Release 为约 54.6 MB；主程序、Rust dylib、`App.framework`、`FlutterMacOS.framework` 和 `objective_c.framework` 均为 `adhoc,runtime`。
- `codesign --verify --deep --strict` 通过，Bundle ID 为 `dev.ianvs.terminal`。

## 自动化与 benchmark 证据

Handoff 记录在最终代码 SHA `63b445e` 上连续两次执行 `./tools/verify_flutter_terminal.sh`，两次之间无代码改动，结果一致：

| 门禁 | 结果 |
| --- | --- |
| Rust core unit | 56/56 |
| Rust session | 431/431 |
| vttest regression | 3/3 |
| PTY Dart | 21/21 |
| `ianvs_terminal` | 434 passed，1 expected skip |
| docs contract | 7/7 |
| example | 908/908 |
| macOS smoke | 4/4 |
| real PTY acceptance | 16/16 |
| 静态分析 | 全部通过 |

专项证据：

| 专项 | 结果 |
| --- | --- |
| JSON/Protobuf parity | 26/26 |
| 真实 transport profile | 3 workloads × 2 formats × 3 repeats = 18 runs |
| viewport hash parity | 9/9 Protobuf/JSON pairs matched |
| formal transport audit | `passed=true`, `run_count=18` |
| Release real PTY refresh gate | 3/3 |
| cursor surface 最终画像 | 24 blinks、24 render events、24 FrameTiming、0 missed vsync、无 overlay paint |

Cursor overlay 的局部 build/paint 改善属于 benchmark 观察，不足以推导产品收益；冻结 total-span 结果直接否决了启用方案。证据位于：

- `docs/evidence/2026-07-10-cursor-overlay/decision.md`
- `docs/evidence/2026-07-10-cursor-overlay/cursor_overlay_gate.json`

## 真实 macOS Computer 验收

验收对象为工作区构建产物：

`example/build/macos/Build/Products/Release/Ianvs Terminal.app`

没有使用 `/Applications` 中的其他版本。最终界面流程结果：

| 场景 | 结果 |
| --- | --- |
| 启动与新 shell | Release 直接启动，shell prompt 与 shell-integration 状态正常 |
| ASCII/CJK | `ASCII_OK` 与 `中文输出_OK` 输入、回显和输出正确 |
| idle marker | 后台延迟 marker 在空闲提示符后自动出现，未需额外输入唤醒 |
| resize | `93×21`、约 `75×15` 往返，维度更新、重排和稳定帧正常，无溢出或冻结 |
| tabs | 创建第二标签、在两个标签间切换，内容和 active 状态保持正确 |
| split/focus | 创建右侧分屏，左右 pane 切换 active/inactive，分别输入并观察输出 |
| cursor/focus | 定时帧观察到 blink 状态变化；pane 焦点丢失/恢复与 active 标记一致 |
| scrollback | 生成 80 行输出，真实向上滚轮从底部 `62–80` 到历史 `7–27`，向下滚轮返回 `62–80` 与 prompt |
| close/empty state | 关闭 3 个测试 shell 后显示 `Shell workspace is idle` 和 `The last session has closed` |
| recovery | 点击空状态 `New Tab`，重新创建 `Local Shell`，显示 `Back in shell` |

Computer Use 的直接键盘注入会丢弃部分标点和 Unicode，因此 CJK 命令通过 TextEdit 可访问文本框写入、复制并在 terminal UI 中粘贴；应用实际收到的完整命令与输出均可见。该限制属于验收工具，不是产品输入缺陷。

验收过程中曾出现 resize 后“重复 marker”的截图候选。后续检查表明：

- native snapshot 中 marker 数量正确；
- SIGWINCH redraw delta 的 dirty row 与内容自洽；
- 导出 scrollback 中 marker 只有一条；
- 第三次真实 resize 复现从 0.5 秒起保持单条；
- 只有 Computer Use 增量截图曾保留旧 dirty region，完整稳定帧没有复制。

因此该候选被分类为 Computer Use 截图合成伪影，没有修改生产代码，也没有把它记录为已确认产品问题。

最终流程未观察到崩溃、卡住、产品侧重复输入、丢帧、焦点错误、游标异常或布局问题。

## 本次续作实际执行的命令

由于 `pub.dev` 在本机不可达，而 `https://pub.flutter-io.cn` 可达，本次只从镜像取得锁文件指定的 `protobuf 6.0.0`，再放入 `pub.dev` 本地 cache；随后恢复原锁文件并离线解析。最终工作树没有依赖文件改动。

```bash
dart pub --directory . get --example --offline
cd example
flutter build macos --release --no-pub
cd ..
./tools/sign_local_macos_release.sh \
  "example/build/macos/Build/Products/Release/Ianvs Terminal.app"
codesign --verify --deep --strict --verbose=2 \
  "example/build/macos/Build/Products/Release/Ianvs Terminal.app"
```

环境：Flutter 3.44.2、Dart 3.12.2、macOS arm64。

本次续作没有再次运行两轮完整 `verify_flutter_terminal.sh`、18-run transport profile 或 3-run Release refresh gate。原因是 handoff 已记录这些命令在相同最终代码 SHA `63b445e` 上连续通过，续作未修改代码；续作只补齐缺失的 Computer gate、重新构建/签名 Release 和最终报告。若报告编写或后续提交引入代码改动，该豁免立即失效。

## 兼容性、风险与后续

### 已确认兼容性

- JSON wire path 保留。
- Protobuf 只在 capability 支持时自动启用。
- JSON/Protobuf 边界、规范化和 final viewport hash 一致。
- 公共 frame factory seam 未删除。
- cursor overlay 没有留下公共 barrel、listener、cache、Expando 或 mode API。

### 未验证假设

- Developer ID 签名、公证和分发环境未验证；本报告只验证本地临时签名。
- Intel Mac、外接显示器 DPI 切换、所有 IME 和所有第三方 shell prompt 未穷举。
- benchmark 结果只支持当前 workload/host，不应外推为所有终端负载的普遍性能结论。

### 后续建议

- 在稳定 Release 主机继续保留 transport/profile 和 refresh gate 的周期性运行。
- 若未来重新尝试 cursor overlay，必须沿用冻结 total-span gate，不得只凭局部 paint 指标启用。
- `TerminalViewport` 仍拥有 key、selection、caret geometry 和 `TextInputConnection` 生命周期；本轮有意不做大协调器重构。

## 最终接受条件审计

- [x] 自动化总门禁在最终代码上连续通过两次。
- [x] JSON/Protobuf correctness 与 viewport hash parity 无回归。
- [x] 真实 PTY idle wake、active/background/max-backoff 有定量门禁。
- [x] cursor 实验有明确 NO-GO 结论且生产代码已回退。
- [x] 本地 Release hardened runtime 与嵌套签名通过。
- [x] Computer 界面验收完成，没有可复现产品问题。
- [x] 已生成 review 与 changes 两份最终文档。
