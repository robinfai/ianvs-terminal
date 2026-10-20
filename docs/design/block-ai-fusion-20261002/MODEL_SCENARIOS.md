# D01–D03、D05–D06：真实模型与回复排版验收

2026-10-03，`composer` 工作区；实际原生环境为 macOS 27.0.1（26A434）。依据 [场景设计](DESIGN.md) 和既有 imagegen 设计图进行人工对照；以下图片均为应用或生产组件截图，不是重新生成的设计稿。手机仅按固定字号验收，没有进行 iPhone 真机测试。

## 发现与整改

真实模型接入揭示了固定 HTTP 回复无法暴露的问题：用户要求“提出命令，等待确认”时，模型可能只在正文中再次询问确认；命令结果解释没有来源标记；失败诊断只给工具提案，没有先解释错误。

`aiSystemPrompt` 和工具说明现在明确：`run_command` / `send_keys` 创建的是审阅卡片，应用只在用户批准后写入终端；尊重只分析约束；解释原输出时使用真实 block ID 与一基、包含末行的引用范围；失败诊断先说明已有证据及未知部分，提案的简短用途不能代替正文诊断。审批、revision、目标与单次提交的守卫没有放宽。

初期真实回复还直接显示 `**粗体**` 和反引号。现在助手正文使用 Markdown，标题、列表、强调和代码沿用主题，整条回复支持跨段落选中和复制。正文不增加纵向滚动层，长代码可横向阅读；图片只显示来源文本，链接由明确点击交给现有终端链接处理流程。用户原话和终端原始输出保持各自的渲染与来源语义。

最后的原生视觉对照发现，直接使用 `fontFamily: 'monospace'` 在本机回退为比例字体；加载字体的组件截图掩盖了这个问题。提案、编辑器、附件输出与 Markdown 代码现统一使用现有 `IanvsTypography.code` 的平台字体及回退配置。原生测试实际测量 `WWW` 与 `iii` 的宽度相等，避免只检查字体配置字符串。

引入 `flutter_markdown_plus 1.0.12` 与其 `markdown 7.3.1` 依赖，锁文件没有变更其他依赖版本。组件选择依据见包的 [MarkdownBody API](https://pub.dev/documentation/flutter_markdown_plus/latest/flutter_markdown_plus/MarkdownBody-class.html)。

## 真实模型流程

新入口为 `example/integration_test/terminal_ai_model_scenarios_test.dart`，通过生产 `AiApiClient`、本机记录转发器和已有 OAuth 代理访问模型。转发器不修改模型回复，仅记录本次合成场景的 JSON 请求／响应，不记录鉴权头。旧的 `terminal_ai_proxy_acceptance_test.dart` 仍使用旧面板入口，本轮没有把它算作通过的验收。

最终源码运行：**1 个完整流程通过、5 次模型请求、返回模型均为 `gpt-6-luna`、2 条实际 PTY 命令**。原始证据为 [结果](evidence/model-scenes/real/result.json)、[请求与回复](evidence/model-scenes/real/model-traffic.json)和[日志](evidence/model-scenes/model-font-real.log)。

1. 两个服务目标存在歧义，要求等待用户选择。模型保留等待状态，没有提案或 PTY 命令。
2. 用户选择 beta，继续只分析、不提出命令。模型给出尚未执行的计划，原任务 ID 与约束保留，没有把步骤标成已完成。
3. 用户单独授权提出 `cat beta/status.txt`。真实审阅卡片出现，批准前无执行；批准后只产生一个真实块，退出码 0。
4. 文件包含 `enabled=false`、`health=not_checked`。模型明确“读取成功不能证明服务恢复”，引用原块第 1–3 行。
5. 验收程序通过原生 composer 单独执行合成检查脚本，产生两行连接拒绝输出和退出码 7。块菜单仅附加上下文，不发送模型请求；用户随后要求诊断，模型解释该次连接拒绝以及无法确定的原因，并引用原块第 1–2 行。它另外提出只读 `grep` 检查脚本的卡片；测试拒绝该卡片，没有重试原命令或新增执行。

两个服务目录与脚本均为隔离的测试数据；脚本打印合成失败并退出，没有连接真实数据库。最终所有测试文件保持原内容。自动断言覆盖任务身份、输入次数、审批前后块数量、真实退出码、来源标记、附件副作用、文件内容和模型 ID；“证据充分程度、是否过度推断”等语义结论另由人工阅读实际回复确认。单个有界场景通过不等于所有模型、任意错误或多次随机运行均可靠。

## 逐场景对照

| 场景 | 最终截图与检查 | 本轮结论 |
| --- | --- | --- |
| D01 | [失败块待附加](evidence/model-scenes/real/D01-real-model-pending-context.png)：来源、行号范围、删除附件、AI 意图和发送动作清楚可见；原失败块保留；菜单完全关闭后截图 | 本轮桌面主流程视觉对照通过。原生流程另断言往返 AI 保留命令草稿及选区；无配置、IME 等交互继续由现有组件测试覆盖 |
| D02 | [澄清](evidence/model-scenes/real/D02-real-model-clarification.png)、[计划](evidence/model-scenes/real/D02-real-model-plan.png)：单列时间线、正文列表，没有未经验证的完成标记或第二个聊天栏 | 同一任务中的真实澄清与只分析计划通过；使用自然语言补答，不把设计稿中的示例选项当作固定模型协议 |
| D03 | [真实模型提案](evidence/model-scenes/real/D03-real-model-read-only-proposal.png)、[原生编辑审批](evidence/model-scenes/native/D03-command-review.png)：用途、目标、目录、完整等宽命令、编辑／拒绝／执行一次均在审阅区域 | 桌面主流程视觉对照通过，原生测宽确认等宽字体；键盘审批、双击、revision 和连续三条提案的守卫由应用回归覆盖 |
| D05 | [退出 0 的有限结论](evidence/model-scenes/real/D05-real-model-zero-exit-incomplete-health.png)：原块、状态与引用链接分明，没有把文件读取成功写成服务恢复 | 本场景真实模型表述通过；本轮当时尚缺焦点证据，后续已由 [D05 焦点验收](D05_FOCUS.md) 补齐；本表仍不代替完整合同审计 |
| D06 | [原失败与新提案](evidence/model-scenes/real/D06-real-model-failure-evidence.png)：原始退出 7、诊断正文、证据范围、新审阅卡片分别保留 | 本例说明已有证据和未知原因，无盲目重试。另一个确定性原生流程验证批准修正后产生独立块且原失败块不变 |
| M01 / M02 | [固定字号输入](evidence/model-scenes/native/M01-fixed-text.png)、[键盘空间](evidence/model-scenes/native/M01-keyboard-space.png)、[竖屏审阅](evidence/model-scenes/native/M02-full-review.png)、[横屏审阅](evidence/model-scenes/native/M02-landscape-review.png) | 手机仍使用独立审阅页与固定底部操作。新字体没有遮挡入口；60 行长命令滑动到底、返回不执行的组件回归通过 |

对照保留 DESIGN.md 的单列结构、细边界、单一蓝色主操作及真实终端输出。生成稿中的示例文字、图标细节和渐变不作为替代实际主题的要求。没有以图像生成结果代替产品运行证据，也没有声称 imagegen 自动判定“没有问题”。

回复排版另有四组截图：[手机浅色](evidence/model-scenes/markdown/phone-light.png)、[手机深色](evidence/model-scenes/markdown/phone-dark.png)、[桌面浅色](evidence/model-scenes/markdown/desktop-light.png)、[桌面深色](evidence/model-scenes/markdown/desktop-dark.png)。手机尺寸为 320×568、固定字号；这些组件截图使用仓库测试字体，颜色、字号、间距与生产主题保持一致。原生字体正确性以实际 macOS 测宽与原生截图为准。

## 最终验证

- [818 项应用回归](evidence/model-scenes/model-font-app.log)：AI、Shell、全部 session 测试与 terminal mode。比此前 728 项范围扩大，不能把数量差全部当作新增用例；本轮新增正文测试为 4 项，覆盖跨段落复制、代码完整性、链接点击、图片不加载和单一纵向滚动。
- [5 项原生／手机组件流程](evidence/model-scenes/model-font-native.log)：1 项生产 HTTP→真实 PTY 流程与 4 项固定字号手机组件预览。静默命令 12,024ms；持续输出 81→161→241 行、整块 257.4→255px、视口 800px；阅读锚点往返、401 恢复和 vim 44×203 网格保持。详见 [原生结果](evidence/model-scenes/native/result.json)。其中 `native_command_count` 是首次编辑命令阶段的计数，不能解释为整份原生脚本只执行一条命令。
- [1 项真实模型原生流程](evidence/model-scenes/model-font-real.log)：上述 5 次请求和 2 条命令，不与确定性流程混为模型质量证据。
- [相关静态分析](evidence/model-scenes/model-font-analyze.log)无问题；[发布镜像](evidence/model-scenes/model-final-mirror.log)无漂移；工作区 `git diff --check` 通过。主 Shell 文件 1698 行，未放宽架构门槛。
- [清单与源码哈希](evidence/model-scenes/manifest.json)记录本轮证据及关键源码。归档前检查内容未含本机代理密钥；本轮自行启动的代理已退出，没有复制 OAuth 凭据。

中间失败日志保留以说明修复缘由：[正文确认但无提案](evidence/model-scenes/model-scenes-requested.log)、[结果无引用标记](evidence/model-scenes/model-scenes-proposal.log)、[失败时缺少诊断正文](evidence/model-scenes/model-scenes-rendered.log)。早期仅发出第一次请求还包含测试未聚焦输入框的问题，已通过显式聚焦、草稿断言及新请求计数等待修正，不能将该次失败归因于模型。

复现时从 `example/` 运行：

```sh
flutter test --no-pub test/ai test/shell test/sessions test/terminal_composer/terminal_mode_test.dart --reporter expanded
flutter test --no-pub integration_test/terminal_ai_workspace_acceptance_test.dart -d macos --reporter expanded
flutter test --no-pub integration_test/terminal_ai_model_scenarios_test.dart -d macos --dart-define=TRAIL_PROXY_KEY_FILE=/absolute/private/client-key --dart-define=TRAIL_MODEL_SCENE_EVIDENCE=/absolute/evidence/path --reporter expanded
```

最后一项需要已有本机代理监听 `127.0.0.1:8317`；密钥只从本机私有文件读取。截图可用 `TRAIL_FUSION_EVIDENCE` 和 `AI_MESSAGE_EVIDENCE_DIR` 指定绝对目录。

整体目标继续进行。D05 焦点后续已补验，见 [D05_FOCUS.md](D05_FOCUS.md)。其余场景最终设计对照、真实 cloud、k9s 和完整 20 场景完成审计仍保留在 [实现矩阵](IMPLEMENTATION.md)。本轮没有提交或推送。
