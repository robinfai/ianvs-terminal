# Composer 全面设计优化

日期：2026-09-29。工作分支：`composer`。实现前基线：`5f164bea`。

## 用户目标与范围

启用 subagent，使用 imagegen 对 Composer 每个 UI 细节进行优化设计。图标可以重新设计；
每个功能的用途、状态表达和交互逻辑也需要梳理并落实优化。

本轮面向 Trail 桌面终端用户。保留 Warp Universal Input 式底部独立命令编辑体验，
让环境、输入归属、候选采用和命令执行更容易分辨。实现仍使用当前 Flutter 项目，
覆盖 canonical 与生成的 standalone 包；不把设计图作为运行时 UI 图片。

范围包括环境与目录、输入和灰字、工具栏、历史、补全与详情、自动候选、复制、撤销/
重做、终端输入切换、主操作、发送/运行/草稿/暂停/未知结果、恢复、加载/空/错误状态、
焦点与选区、快捷键、触摸板、窄窗、放大文字、深浅色、高对比和语义标签。

不新增未授权的 AI 模式或云历史。已有 shell 租约与提交边界、采用不执行、IME、
目录补全和触摸板滚动修复是必须保留的行为。

## 设计证据

- [交互审计](COMPOSER_REDESIGN_INTERACTIONS.md)：功能、状态、缺口和验收矩阵。
- [视觉系统审计](COMPOSER_REDESIGN_VISUAL_SYSTEM.md)：tokens、字体、图标、布局与状态。
- [设计前真实 Flutter 基线](redesign-evidence/before/README.md)：16 状态 × 3 配置，共 48 张。
- 可复用捕获入口：`example/test/design/composer_redesign_capture_test.dart`。

审计由三个 subagent 分别承担交互、视觉系统与基线捕获；主代理负责整合、imagegen、
后续实现分工及最终验证。实际基线使用 macOS 27.0；尚不代表其他支持 OS 的验证。

## Imagegen 视觉方向

使用内置 `image_gen`，没有使用 CLI 或 API key fallback。以下编号严格对应本轮聊天
中生成图像的显示顺序，每个方案为独立生成结果。源截图均为已经查看的本项目真实
Flutter 渲染；生成的文字与 glyph 只作为视觉参考，不直接进入产品。

| 显示顺序 | 设计图 | 完整生成 prompt | 输入参考 |
| --- | --- | --- | --- |
| 1 | [option-1.png](redesign-evidence/concepts/option-1.png) | [prompt](redesign-evidence/concepts/option-1-prompt.txt) | `example/test/design/goldens/macos-27/composer/light.png` |
| 2 | [option-2.png](redesign-evidence/concepts/option-2.png) | [prompt](redesign-evidence/concepts/option-2-prompt.txt) | `example/test/design/goldens/macos-27/composer/dark-history.png` |
| 3 | [option-3.png](redesign-evidence/concepts/option-3.png) | [prompt](redesign-evidence/concepts/option-3-prompt.txt) | `example/test/design/goldens/macos-27/composer/light.png` |

当前状态：**已向用户呈现三张方案并请求选择；尚未确定最终视觉目标，未开始产品实现。**
选定后记录方案及用户调整，按该结构完善所有状态，而非只实现单张静态截图。

生成图中示例 shell 输出、提交散列和分支名是 mock 内容，不是仓库状态证据。
方案 1 的模式下拉箭头不得照搬成无功能控件；当前只有命令模式。
方案 3 的历史弹层仍需在实现时跟随真实输入位置并约束可用空间。

## 实现与验收计划

- [x] 核对当前源码、分支与已有产品视觉参考。
- [x] 启用三个 subagent 分别审计交互、视觉系统和实际渲染。
- [x] 使用 imagegen 生成三个独立方向，保存图片与完整 prompts。
- [x] 捕获设计前浅/深/窄窗 2× 的完整状态基线。
- [ ] 用户选定视觉方向；完善所有状态的具体结构与文案。
- [ ] 建立统一主题 tokens 与语义图标映射，复用宿主的向量图标字体。
- [ ] 实现全部界面细节、响应式布局、明确的状态/主操作与完整辅助操作入口。
- [ ] 修复审计确认的状态生命周期问题，补充行为回归。
- [ ] 更新交互预览，并为同样场景生成 after 证据，与 before/视觉目标对照。
- [ ] 验证深浅色、窄窗/短窗、2× 字体、高对比、焦点、语义、IME、键盘和触摸板。
- [ ] 运行 canonical/standalone、真实 macOS 应用回归及静态分析，检查镜像一致性。
- [ ] 构建并校验本地 Release；提交 `composer`；逐项审查目标后再标记完成。

计划中的项目均不是已完成声明；最终以源码、渲染与行为测试的实际证据为准。
