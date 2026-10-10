# 08 · Codex 桌面端实施交接

## 任务

在 `robinfai/ianvs-terminal` 的用户指定最新 `composer` 分支上，按本包 D1–D4 完成桌面 Block × AI 的交互、UI、键鼠、多窗格与原生验收完善。交付生产代码、测试、实际截图/录屏、证据清单和可由GitHub独立复核的结果。

本包应放 `docs/product/desktop-block-ai-v1/`，不替代 `mobile-block-ai-v1/`。编写基线为 `763dc166bb1e56d6d50ed3379b57f366c9ca06b7`；开始时fetch并记录最新HEAD，保留未提交工作，不reset/hard、强推或覆盖无关修改。最新代码已满足需求时保留并补回归，不因旧PRD重复开发。

## 必读与基线

阅读仓库AGENTS、CURRENT_EXECUTION_TARGET、TERMINAL_PRODUCT_SCOPE、现有Composer重设计/Blocks/API/ACP文档，以及本目录00、01–04、05、06、10、11、13、14。先创建 `results/BASELINE.md`，列实际HEAD、已实现/缺口/待确认、生产代码入口、现有快捷键、平台host、可用模型/设备、真实before图。

## 桌面特定要求

保留单层窗口栏、Terminal tabs、底部状态栏、三层Composer Dock；默认不增加永久侧栏或项目容器。桌面Block默认按所在pane终端内容H/3限制，内部滚动/手动展开保留，不能套手机六行预览。桌面缩放1/1.5/2与真实DPI验证保留；不得沿用手机固定字号clamp。

同一pane一个可写主入口，可复用不同controller+adapter；多pane分别有独立草稿/任务/模式。API与本地ACP分别验收，ACP不固定过时模型名、不扩大工具权限。macOS是主门槛；Linux/Windows依13独立记录，不用编译或Flutter跨平台能力代替原生证据。

## 不可破坏的执行边界

真实TerminalViewport、当前PTY/协议、lease/target/revision检查、单次operation、未知回执不重发、IME优先、完成块/observer只读、TUI回退、来源/草稿/阅读锚点隔离全部保留。

查看终端不等于接管；暂停AI不等于Ctrl+C；接管先撤销后续Agent写，再交人工owner。observer来源写入须为0，但不禁止正常核心协议应答；有效operation最多一次，不按write系统调用次数判断。活动pane改变不重定向旧任务/审批。后台回复和shell ready不能抢其他pane/window的焦点。

## 实施顺序

按12中的16个工作包推进：先补边界测试与D1工作流，再D2键鼠/布局，D3tokens/状态，D4真实原生/物理设备验证。可并行独立view、tests、证据模板；同controller/nativeguard/生成镜像必须明确负责人。

共享canonical更改与移动包合流时记录冲突和回归。不要分别手改standalone，先检查最新Makefile后使用现有入口：

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

有影响时运行native/core、真实SSH、AI App集成与现有goldens；不存在的命令先建立真实入口并记录，不写虚构成功日志。不要默认执行make install去覆盖用户/Applications生产版；使用已授权的隔离开发bundle、HOME/数据目录与fixture。

## 设计与截图

`design/`是静态文档样稿，不能贴成运行时背景，不是App证据。用Flutter控件、宿主tokens、原生终端输出实现。按05的布局/状态说明对照，功能和安全合同高于例图像素。

按10逐图清单采159个可见检查点；可兼容复用但要理由。结果文档逐case嵌入实际原图，不能只给目录。动态用例交连续录屏和日志；行为安全须生产通路+边界断言+受控副作用验证。原图不得用生成图/Widget/文档渲染替代。

## 可追溯交付

填写模板生成STATUS、results/D1…D4、PLATFORM_MATRIX、PERFORMANCE、FINAL_REVIEW与evidence/manifest.json。全部64case初始not_run。每阶段冻结实现C→构建采证→证据E；最终代码变化重跑影响面，最终自动gate严格匹配最终实现commit。保留C/E的diff和二进制/源码hash。

```sh
python3 docs/product/desktop-block-ai-v1/scripts/validate_evidence.py \
  docs/product/desktop-block-ai-v1/evidence/manifest.json --gate final
```

运行后必须人工查看关键原图和连续视频，排除错窗口、空白、加载中、缺动作、错误目标或裁剪。校验器通过不等于产品通过。

## 缺环境时

无macOS、物理键盘/触摸板、外接屏、真实API或ACP时，继续可完成的代码、fixtures和测试，把对应项标implemented_unverified/blocked并附可运行重测步骤。不把mock转成“真实模型通过”，不把VM/Widget模拟改成物理测试，不删除case。Linux/Windowshost未实现则如实记录not_supported，不展开未授权移植。

## 最终回复

返回分支/PR、实现commit C、证据commit E、四阶段状态、实际OS/设备/后端、完整gate、原图/录屏、未完成与回滚路径。未得到额外授权，不发应用商店、不改账号/生产服务、不覆盖生产安装。

## 可直接使用的启动提示词

请读取 `docs/product/desktop-block-ai-v1/08_CODEX_HANDOFF.md`，核对composer最新代码后按D1–D4实施桌面Block×AI交互优化。保留现有单层窗口栏、三层Dock、底部状态栏和PTY安全边界；按06和10提交实际桌面App截图、录屏、日志与GitHub结果文档。已实现项补证据，不重复重构；缺原生/设备/模型的项目保持未验证。完成返回实现/证据commit与FINAL_REVIEW入口。
