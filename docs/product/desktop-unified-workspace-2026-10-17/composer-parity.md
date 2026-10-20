# 融合工作区：保留 Composer 编辑能力

桌面融合的首版把输入迁移到 AI 的普通文本框，遗漏了原 Composer 的 Tab 补全、历史候选及部分编辑快捷键。本次恢复这些能力，继续由融合工作区负责唯一的提交路径。

输入 `ls ./` 后按 Tab：使用当前会话、目录、Shell 上下文和有效 lease 查询候选。唯一结果可直接补入；多个结果显示原 Composer 候选列表和详情，↑／↓选择，Tab／Enter 采用。**采用只是编辑草稿；再次发送才执行命令。**

## 功能对照

| 原 Composer 能力 | 融合后的入口和行为 | 验证 |
| --- | --- | --- |
| Tab 补全、命令目录候选及详情 | 复用原候选查询、结果模型和候选面板；Tab 可触发本地文件查询，不改变自动建议偏好 | 三种桌面平台组件；macOS 真实 PTY 的目录候选 |
| 历史筛选 | Ctrl+R／编辑菜单／输入首行 ↑；Esc 恢复打开历史前的草稿；空输入也可采用历史 | 桌面与 iOS 组件 |
| 灰字建议 | 复用原历史／补全预测；→、Ctrl+F/E 采用，Ctrl+→分段采用；灰字不进入提交文本 | 三种桌面平台组件、原 Composer 回归 |
| 自动建议 | 编辑菜单开启／关闭；普通模式往返保留会话内的偏好 | 桌面与 iOS 菜单回归 |
| 撤销、重做 | Cmd/Ctrl+Z、加 Shift 重做，以及编辑菜单；普通模式往返保留编辑状态，新任务单独重置 | 三种桌面平台组件、原 Composer 回归 |
| 复制、清空、快捷键帮助 | 输入框右侧“…”编辑菜单；Ctrl+C 仅清空本地草稿，保留选区时使用系统复制 | 菜单与快捷键回归；复制复用系统 Clipboard |
| 多行编辑、展开编辑 | Shift/Ctrl/Option+Enter 换行；原展开编辑入口保持 | 融合输入／原 Composer 回归 |
| 命令块导航 | Cmd/Ctrl+↑/↓ 选择并聚焦命令块；返回输入框继续编辑 | 三种桌面平台组件 |
| 运行中输入 | 手动提交的当前命令块关联已接受的原生回执；Ctrl+C 和交互输入沿原终端输入链路；完成后返回同一编辑框 | 原生 Composer 验收；回执结束／上下文变化／观察模式／后台／新任务撤销回归 |
| 全屏及不支持内容 | 手动命令进入 TUI、嵌套 Shell 或无归属输出时恢复普通终端；AI 动作仍沿用只读观察和明确接管 | 原生验收及手机 TUI 组件回归 |
| 输入用途和执行回执 | 自动／命令／AI 沿用融合控制器；编辑模型没有 submit 回调，不能绕过回执／审批路径 | 融合工作区全套回归 |
| 只读、IME、任务隔离 | 候选采用前即时核对所有权；IME composing 期间 Tab/Enter 不遍历焦点或误发；新任务清除上一任务的撤销、历史筛选及候选状态 | 旧候选点击、迟到结果、任务切换及 IME 回归 |

补全浮层跟随输入区布局，不增加手机收起输入栏高度。iPad 分栏跨宽度重挂载保留同一浮层；手机命令操作菜单保留输入焦点，避免输入区收缩时菜单回调失效。

## CI 基线修正

上一提交的 macOS 26 CI 有两处失败：9 张视觉基线仍保留旧的设置说明／AI 字样，以及原生 Composer 验收仍寻找已被融合替换的旧输入框。本次保留原生验收全部功能场景，调整入口和回执等待；新增融合 AI 原生用例也纳入 CI。9 张截图来自同一 CI run `38933136958` 的 `visual-baseline-candidates-macos-26` 产物，逐项检查后更新，没有使用 macOS 27 生成结果替换 macOS 26 基线。本机 macOS 27 的同样 9 张基线独立采集并核对；两套基线均只变更融合入口图标与设置文案。

## 验证

- 融合工作区相关回归：**878 / 878 通过**，包括手机 56 逻辑像素、深浅色／横竖屏组件、预览、审批、回执、关闭草稿保护和会话生命周期。
- 全部设计回归：**839 通过，1 项原有跳过**；macOS 26／27 的基线分别维护。
- 原 Composer 控制器及组件回归：**189 / 189 通过**。
- 功能与视觉定向复验：**14 / 14 通过**，含 macOS/Windows/Linux 键盘、桌面与 iOS 编辑菜单，以及深浅色、640 × 400／2 倍文字比例、手机 TUI 草稿和只读输入。
- macOS **27.0.1 (26A434)** 原生集成：真实 Native PTY、隔离 zsh 和临时 alpha/beta 目录，`ls ./` Tab 列出路径，Enter 采用但不执行，随后同一输入框完成命令和回环 HTTP AI 回复。
- 原 Composer 全场景 macOS 原生验收 **1 / 1 通过**：保留路径／历史补全、目录与变量、长输出滚动、多行运行高度、Ctrl+C、`read` 交互、普通模式往返、嵌套 Bash、真实 `top`／`vim`、后台无归属输出回退和退出场景。
- 运行中输入边界额外复验 **1 / 1 通过**，含切换 AI 后可继续编辑提问，且旧命令输入回调失效。
- 应用及 Composer 静态分析、格式、diff、core 镜像检查通过；生产入口 macOS Release 构建通过。

Windows/Linux 和手机本轮为组件平台变体，不是实机验收；没有新增手机安装。原生 AI 响应来自本地确定性 HTTP 服务，未调用外部模型或真实 SSH。候选能力沿用项目现有补全提供器，不声称兼容所有第三方 zsh 插件。

[原生路径候选截图](screenshots/native-path-completions.png) · [手机历史截图](screenshots/composer-history-iOS.png) · [相关回归](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/desktop-unified-workspace-2026-10-17/composer-parity-evidence/regressions.log) · [原 Composer 回归](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/desktop-unified-workspace-2026-10-17/composer-parity-evidence/original-composer.log) · [定向与视觉](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/desktop-unified-workspace-2026-10-17/composer-parity-evidence/visual.log) · [融合原生集成](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/desktop-unified-workspace-2026-10-17/composer-parity-evidence/native.log) · [原 Composer 原生验收](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/desktop-unified-workspace-2026-10-17/composer-parity-evidence/original-native.log) · [运行中输入边界](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/desktop-unified-workspace-2026-10-17/composer-parity-evidence/running-boundary.log) · [设计回归](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/desktop-unified-workspace-2026-10-17/composer-parity-evidence/design.log) · [生产构建](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/desktop-unified-workspace-2026-10-17/composer-parity-evidence/production-build.log) · [应用分析](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/desktop-unified-workspace-2026-10-17/composer-parity-evidence/analyze.log) · [组件分析](https://github.com/robinfai/ianvs-terminal/blob/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/desktop-unified-workspace-2026-10-17/composer-parity-evidence/package-analyze.log)

```sh
# example/
flutter test --no-pub test/ai test/terminal_composer test/shell/terminal_modes_test.dart test/shell/desktop_unified_chrome_test.dart test/shell/mobile_terminal_modes_test.dart test/shell/shell_close_protection_test.dart test/shell/desktop_session_status_test.dart test/shell/mobile_sessions_lifecycle_test.dart test/startup/app_startup_host_test.dart test/ui/phone_text_scale_policy_test.dart
flutter test --no-pub test/shell/mobile_terminal_modes_test.dart --name 'unified Composer|desktop unified keyboard and layout'
flutter test --no-pub integration_test/composer_acceptance_test.dart -d macos
flutter test --no-pub integration_test/desktop_unified_workspace_test.dart -d macos
# packages/ianvs_terminal/
flutter test --no-pub test/composer
```
