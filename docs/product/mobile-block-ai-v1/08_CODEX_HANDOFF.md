# 08 · 交给 Codex 的执行任务

下面内容可直接作为 Codex 起始任务；本 PRD 包应置于 `docs/product/mobile-block-ai-v1/`。本次是基于现有实现的完善，禁止另起原型替换产品。

---

## 任务

在 `robinfai/ianvs-terminal` 的 `composer` 当前代码上，按本目录 S1–S4 PRD 完成移动端 Block + AI 交互与 UI 优化，并提交可由 GitHub 独立复核的源码、测试、真实截图和结果文档。

编写基线为 `763dc166bb1e56d6d50ed3379b57f366c9ca06b7`，但开始工作时先 fetch 并核对用户指定分支最新 HEAD。若 HEAD 已前进，记录变化；保留现有工作，不 reset/hard、强推或覆盖无关修改。不因 PRD 提及基线而回退分支。

## 必读

仓库 `AGENTS.md`、当前 execution target 和产品边界，以及本目录 00、01–04、05、06、07、10、11、12。遵守手机固定字号；保留 iPad/macOS 的适配；手机以模型 API 为基础，不实现未授权远程 ACP。不要把历史文档中的已修复缺口重新当需求重复开发。

## 执行顺序

先建立 `results/BASELINE.md`：最新 HEAD、当前功能矩阵、缺口、源码落点、基线截图、可用工具/设备/模型/SSH fixture。不要只读 PRD 就宣称当前代码有 bug。

S1 先补边界测试，再完成核心闭环和只读/接管分离。S2 收口输入与响应式。S3 统一 tokens、组件状态和视觉。S4 完成真实设备/原生/性能验证并修复问题。每阶段一组可独立审查的提交，不一边改底层协议一边大面积换皮。

如果支持并行任务，可以拆分测试/设计证据/独立 view 组件；runtime 所有权、同一控制器和同一生成镜像只能有明确负责人，防止互相覆盖。所有子任务最终经过同一真实 App 验证。

## 不可破坏

TerminalViewport 是真实输出；单一 PTY 写入所有权；租约与目标/提案版本检查；审批；未知回执不重发；草稿/阅读锚点隔离；IME 优先；TUI/特殊输出保守回退；原生 scrollback 与分页预算。

只读“查看终端”绝不发键盘、粘贴、鼠标报告。接管和暂停 AI 不发送 Ctrl+C；中断是单独显式动作。候选/历史采用与保存编辑不执行。

## 工程要求

复用当前 package/host 边界；只改 canonical 来源，再运行：

```sh
make terminal-core-sync
make terminal-core-check
make format-check
make analyze
make test-composer
make test-composer-ui
(cd example && flutter test test/ai)
make verify
```

上述目标在编写基线存在；开始时先读最新 Makefile 核对。需要设备的命令在合适 macOS 环境运行；不要在没有工具的环境伪造成功。新增 fixture、测试入口和采集脚本必须可重复、无生产数据依赖。

注意 `make install-iphone` 可能回退模拟器。需要实机证据时使用项目显式 physical 路径并核对设备类型；不能靠命令名称推断实机成功。安装前使用已授权的独立开发 bundle/目录，不覆盖用户生产版。

## 设计要求

05 和 design/ 是静态设计参考，不是验收截图，不是可以贴到产品里的背景图。使用真实 Flutter 控件、应用 ColorScheme/AppThemeTokens、原生 TerminalViewport。保留手机六行预览和全屏 Reader；手机主要按钮可点且有明确文字。每阶段按实例状态捕获实际 App，再对照例稿调整。

## 证据与结果

使用 `templates/STATUS.template.md`、`templates/STAGE_RESULT.template.md`、`templates/manifest.template.json` 建立真实结果。48 个用例初始 not_run，执行后填写；按 10 完成 110 个可见状态检查点，用 shot_ids 绑定原图。每个需求映射测试、源码 commit/path 和相应原图；results 文档必须嵌图，不能只给目录。

按 06 冻结实现 commit C，构建和采证，再提交 evidence-only E；记录源 hash 和二进制 hash。不得提交真实凭据/用户输出；不得把生成稿、旧图、桌面窄窗或 Widget 渲染标成手机实机截图。

运行本包文件/构建校验器及逐帧覆盖/嵌图校验器（见 06 和 10），然后人工打开每张关键原图检查是否错误窗口、黑屏、加载中、裁切或文字不可读。录屏检查中间过程，测试日志保留退出码与具体失败。

## 无法完成时

无 iPhone/iPad/某个 OS/真实模型时，继续完成能够验证的源码、fixtures 和测试，写 `implemented_unverified` / `blocked`，列出精确缺口与重跑步骤。不要换成伪数据后标通过，不要删用例，不要因为设备缺失而丢弃已完成工作。

## 完成回复格式

给出最终分支、实现 C、证据 E/PR、四阶段真实状态、测试命令与结果、原始图和录屏入口、未完成项、回滚路径。不用“全部完成”替代证据。没有新的用户授权，不发布 App Store、不覆盖生产安装、不改无关账户/服务。

---

## 最短的启动提示词

“请读取 `docs/product/mobile-block-ai-v1/08_CODEX_HANDOFF.md`，核对 composer 最新代码后按 S1–S4 执行。保留现有 runtime 安全边界；按 06/10 提交实际 App 截图、录屏和可追溯日志；无法验证的场景保持 blocked，不以设计稿或组件图冒充实机。完成后返回 GitHub 证据入口及实现/证据 commit。”
