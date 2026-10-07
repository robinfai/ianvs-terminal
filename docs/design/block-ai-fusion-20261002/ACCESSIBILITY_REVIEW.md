# 高对比与减少动态效果复核

2026-10-03。继续执行 DESIGN.md 的公共行为合同。本轮完成应用高对比主题接入和 AI 工作区的动态效果整改；不将这些检查标为整套无障碍验收完成。手机保持固定字号，未使用 iPhone 真机。

后续已补齐 Block、内部阅读路由及 Shell 菜单的动态效果，并通过 1,025 项应用、74 项共享终端和 1 项独立原生窗口检查，见 [MOTION_REVIEW.md](MOTION_REVIEW.md)。当前二十场景状态见 [CURRENT_ACCEPTANCE.md](CURRENT_ACCEPTANCE.md)。2026-10-03 用户明确要求跳过 VoiceOver，实际朗读记为未验收；下文保留本轮历史边界，不再作为当前阻塞项。

## 改动与原因

终端 Composer 已读取高对比偏好，但 MaterialApp 原先没有高对比主题。AI 卡片、附件和配置表单因此仍使用普通主题的弱边界。现在浅色、深色分别提供高对比主题，在现有设计系统 token 上增强次级文字、分隔线、输入框、菜单、对话框与滚动条；保持字体、控件尺寸和页面布局。描边按钮的键盘焦点继续使用独立的 2px 焦点边界，避免被普通高对比边框覆盖。

AI 审阅页和输出阅读页使用应用的 Material 页面转场。减少动态效果开启时直接显示页面内容；关闭时保留平台原有转场。AI 工作区的附件、提案编辑、目标选择、待附加上下文、配置、歧义证据弹窗及任务菜单显式关闭入场动画。输出观察、超时和终端处理没有被当作装饰动画停用。

## 本轮证据

| 检查 | 结果及证据范围 |
| --- | --- |
| 主题颜色 | 浅深色 × macOS/iOS：在 canvas、chrome、panel、raised 上，主要/次级文字对比度至少 4.5，边框和输入焦点至少 3；普通主题保持原设计，固定字号和控件尺寸不变 |
| 系统开关 | 真实 IanvsTerminalApp 在浅深色下切换系统高对比开关，再关闭，主题随之更新而会话对象不变 |
| 减少动态效果 | macOS/iOS/Android 的 MaterialPageRoute 检查首帧和下一帧的完整位置；禁用时不产生 Slide/Fade 转场，弹窗入场已完成；启用动画时仍有过渡 |
| AI 生产组件 | 六组：桌面 1100×800、桌面 2× 字号 1100×900、手机固定字号 390×700，各含浅深色。打开附件快照、编辑/完整审阅、配置后返回，草稿与附件保留，未执行命令，未多发模型请求 |
| 状态语义回归 | 原有桌面/手机 live region 用例随全套重跑：时间和输出更新不改变朗读节点及标签；暂停、断线、目标变化才改变阶段说明。这仍只是 Flutter 语义树证据 |
| 应用回归 | [972 项通过](evidence/accessibility/a11y-regression.log)，包含本轮新增用例、UI、应用主题、AI、Shell、会话、偏好和模式检查；计数不与专项重复相加 |
| 本机原生 | [5 项通过](evidence/accessibility/a11y-native.log)：隔离 HTTP→真实 PTY 工作流及四个固定字号手机组件。结果保留命令单次提交、历史阅读位置、配置恢复、44×203 Vim 网格与手动恢复，见 [result.json](evidence/accessibility/native-result.json)。该流程为普通系统显示设置下的回归，不冒充 OS 高对比开关实机验证 |
| 代码质量 | [静态分析通过](evidence/accessibility/a11y-analyze.log)，改动文件格式通过，git diff --check 通过 |

24 张生产组件截图和源码哈希保存在[清单](evidence/accessibility/manifest.json)。直接对照 D03、M02、D14 设计稿复核了普通桌面提案、深色附件快照、手机深色完整审阅、手机浅色配置及桌面 2× 配置。设计稿用于核对结构与操作层级，不作为对比度或实际朗读的证据。

代表图：

- [桌面高对比提案](evidence/accessibility/workspace/a11y-desktop-light-proposal.png)
- [深色附件来源、范围、退出码](evidence/accessibility/workspace/a11y-desktop-dark-snapshot.png)
- [手机固定字号完整审阅](evidence/accessibility/workspace/a11y-phone-fixed-dark-review.png)
- [桌面 2× 配置](evidence/accessibility/workspace/a11y-desktop-2x-light-settings.png)

## 未完成的边界

本轮没有取得 VoiceOver 的真实朗读记录。原生控制工具选择 VoiceOver 时超时；随后全局读取最后朗读短语/光标文本被自动审批拒绝，因为没有限定到 Trail，可能包含其他应用内容。读取未执行。关闭 VoiceOver 最初也因无法确认进程归属而被拒绝；用户明确同意关闭后，退出命令成功，进程检查确认不再运行。没有改变 VoiceOver 的脚本控制权限。

后续实际朗读应先建立可唯一识别的隔离 Trail 窗口，再验证系统朗读输出的归属，不能读取全局未知短语作为捷径。公共合同中的实际朗读、全套场景最终逐项审计，以及 AI 工作区以外装饰动画的覆盖仍待完成；此次 972 项和图片不能证明这些项目。整体目标保持进行中，没有提交或推送。

## 复现

在 `example/` 运行：

```sh
flutter test --no-pub test/ai test/shell test/sessions test/preferences test/terminal_composer/terminal_mode_test.dart test/ui test/app --reporter expanded
flutter test --no-pub test/ai/terminal_ai_workspace_test.dart --plain-name 'high contrast and reduced motion' --dart-define=AI_WORKSPACE_EVIDENCE_DIR=/absolute/evidence/path --reporter expanded
flutter test --no-pub integration_test/terminal_ai_workspace_acceptance_test.dart -d macos --dart-define=TRAIL_FUSION_EVIDENCE=/absolute/native/evidence/path --reporter expanded
flutter analyze --no-pub
```

原生环境为 macOS 27.0.1（26A434）。组件测试替换系统特征输入，不证明其他支持 OS 的实机表现。
