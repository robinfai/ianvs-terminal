# 2026-10-11：流式输出、退出与紧凑输入

基线为 `composer@0abfaceee9e797d99750dc4ec1dd4418a6cfd198`，提交前再次查询远端仍一致。PR #10（`296728c3`）和 #11（`c2d88f7b`）已合入，沿用其阅读布局、任务条、菜单及回执机制。实现分支为 `codex/composer-stream-lifecycle-20261011`，面向 `composer` 开 Draft PR；没有合并或修改 `composer`，也没有操作 composer → main 的 PR #9。

## 实现

- 修复 native exit 已释放 viewport、UI effect 队列仍处理旧 shell hook 的竞态。过期观察被丢弃，exit 信号继续更新 pane、活动会话及连接状态；resize 和 Shell 读取 viewport 使用可空查询。
- 正常退出移除会话；SSH 255 保留历史和恢复入口，重连创建新 session。意外缺少 viewport 时提供可见状态、查看 AI 任务和关闭入口；已退出会话不能接收手动输入。
- 手机阅读态输入框垂直内边距由 4 调为 3，使 48px 控件加内边距和边框总高为 56 逻辑像素。沿用同一输入控制器、草稿、焦点及 composing 状态；编辑态仍可扩展。
- Chat Completions 使用 `stream: true`，按 SSE 事件逐片解码 UTF-8 文字并更新同一条回复。连接、等待首 Token、生成、审批、取消、完成、失败有对应状态；请求阶段有进度动画，其他状态短暂切换，减弱动态效果设置使用静态图标。
- 工具 name/id/arguments 仅在内部拼接，必须有合法结束原因和 `[DONE]`，再经原工具参数验证及审批流程。断流、截断、多工具、无效数据不会产生可审批动作；部分文字保留用于阅读，不写入完整模型历史。
- 每个增量绑定任务和取消令牌。暂停、任务切换、销毁后的增量和最终工具均不能写入新任务。未知提交继续使用已有原提交检查和回执机制，不增加重试。
- HTTP/SSE 有 1 MiB 上限和无数据超时；持续接收数据不受整段 45 秒时限影响。仍返回 JSON 的网关走原有完整响应路径，不伪造流式片段、不重新请求。ACP 后端保留既有路径。

## 实际测试结果

环境：Flutter 3.44.8、Dart 3.12.2、macOS 27.0.1（26A434）。CI 当前固定 Flutter 3.44.2，尚不能把本机结果替代 CI。测试在未提交工作树运行，下面的证据 JSON 保存对应源码哈希。

| 检查 | 结果 |
|---|---|
| `flutter analyze --no-pub --fatal-infos` | 通过，无问题 |
| 仓库完整 Dart 格式范围 | 1043 文件，0 修改 |
| 流式网络、迟到数据、紧凑手机输入、退出/缺失 viewport 定向测试 | 40 通过 |
| JSON 网关兼容、提交授权、关闭保护与流式网络回归 | 47 通过 |
| `flutter test --no-pub test/ai test/sessions test/shell --reporter expanded`（example） | 1445 通过、12 失败 |
| `integration_test/composer_acceptance_test.dart -d macos` | 1 通过，含真实 PTY `exit` 后无残留 pane |
| `integration_test/ai_streaming_acceptance_test.dart -d macos` | 1 通过，真实 HTTP/SSE 与生产 UI；终端为 fixture |
| `dart test test/docs_contract_test.dart test/runtime_documentation_contract_test.dart` | 21 通过、2 失败，详见下文 |
| `git diff --check`、macOS 检查脚本语法 | 通过 |

定向测试与扩大回归范围重叠，不能相加成独立用例总数。没有执行完整 `make verify`、发布签名安装或本轮手机实机验收。新增流式原生测试已加入 `tools/verify_macos_app.sh`。

### 基线问题的复核

在未修改的同一 `composer` 基线上单独运行以下三套测试，得到 51 通过、同样 12 失败：

- `terminal_ai_observer_test.dart`：4 个 iOS 用例仍找旧的关闭/观察按钮；#11 已将入口移入菜单。
- `mobile_terminal_modes_test.dart`：7 个用例在旧手机入口假设处失败，包括重连后的证据回填、SSH 断连保留、Reader、三种 TUI 布局和任务菜单。
- `shell_screen_architecture_test.dart`：1 个失败，既有 Shell 入口为 1714 行，超过 1700 门槛；本次未修改该入口文件。

文档检查中，`docs/design/mobile-ai-reading-v2` 不在归档白名单的失败在原始 checkout 也存在（22 通过、1 失败）。隔离 checkout 另有 `TOKEN_MAP.md` 指向旧 `tmp/`、`build/` 产物的失效链接；原始 checkout 有这些本地生成文件，因此该项在那里通过。没有复制私有旧产物或放宽门槛来制造通过。

## 截图证据

[本轮来源、尺寸和 SHA-256 清单](../evidence/shared/20261011-stream-lifecycle/result.json)记录 8 张原始测试输出 PNG。7 张 AI 状态图为 macOS 原生 runner 中的 iOS 主题组件，画布 3456×2168；exit 图为完整 App 和真实 PTY。它们由 `RenderRepaintBoundary.toImage(pixelRatio: 2)` 生成，未裁切、缩放或改写原文件，已逐张查看。它们不是手机原生截图，也不证明系统中文 IME、真实模型服务或整条执行链恰好执行一次。

| 检查点 | 原图 |
|---|---|
| 空输入、56px 断言 | [01](../evidence/shared/20261011-stream-lifecycle/01-compact.png) |
| 等待首 Token | [02](../evidence/shared/20261011-stream-lifecycle/02-first-token.png) |
| 已收到增量，响应尚未结束 | [03](../evidence/shared/20261011-stream-lifecycle/03-generating.png) |
| 完整工具后才可审批 | [04](../evidence/shared/20261011-stream-lifecycle/04-approval.png) |
| 取消保留部分文字 | [05](../evidence/shared/20261011-stream-lifecycle/05-cancelled.png) |
| 新任务完整回复 | [06](../evidence/shared/20261011-stream-lifecycle/06-completed.png) |
| 断流失败保留文字 | [07](../evidence/shared/20261011-stream-lifecycle/07-failed.png) |
| exit 后切回仍可用会话 | [exit](../evidence/shared/20261011-stream-lifecycle/normal-exit-no-stale-pane.png) |

旧 `20261011T022419Z-c2d88f7b` 的七张镜像图经解码确认为 JPEG、768×1694，修正了 JSON 元数据。原字节和 SHA-256 均未改变，仍不计为手机原图；旧失败记录保留。

## 手机原图与连续证据要求

继续遵循 [截图清单](../10_SCREENSHOT_SHOTLIST.md)及[证据合同](../06_EVIDENCE_CONTRACT.md)。本轮至少补齐：

1. 从本 PR 精确提交构建并记录安装身份；记录设备型号、OS、方向、逻辑尺寸、DPR、固定字号、深浅色、软键盘状态，以及脱敏的模型/端点类型。
2. 直接导出手机系统截图原件。保留原格式、完整画布、原字节与 SHA-256，尺寸和 MIME 按解码结果填写；镜像窗口图单列。需遮盖隐私时另建副本，原件保持私有且不替换来源记录。
3. 阅读态空输入及有草稿时分别截图；用布局检查或同构建日志证明输入高度 ≤56 逻辑像素。软键盘和中文拼音 composing 期间操作，确认不误发、换行/选区/草稿保留；补横竖屏及深色。
4. 真实支持 SSE 的模型请求：连接、等待首 Token、至少两帧增量、完成；保留连续原录屏和脱敏到达时间，证明首片先于结束、动画正确停止。JSON 回退不能算流式通过。
5. 工具参数未收齐、已收齐但流未结束、正式审批三个节点。配合请求与提交计数证明前两节点不可执行，明确审批后最多一次提交。
6. 生成中取消后立即新建任务，继续观察旧请求的迟到数据；记录旧/新任务 ID，证明新任务不混入旧文本或提案。补断流、超时、错误后的可读状态。
7. 手动 Composer 提交正常 `exit`：退出前后、连接列表、重新进入三个节点，证明没有持续空白或错误的“运行中”。SSH 异常断连保留历史和 AI 草稿，重连为新 session，草稿不自动发送。
8. 注入未知提交回执：检查原提交、取消/恢复、切任务及重连；记录 operation/submission ID 与实际终端写入次数，证明没有自动重试。单张截图不能独立证明无重复写入。

本轮未将正式 48 项 PRD 场景升级为 passed，手机、iPad、真实系统输入、真实模型服务与完整发布验收仍需补证据。
