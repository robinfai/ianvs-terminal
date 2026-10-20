# Composer 高度与执行状态验证

2026-09-29，macOS 27.0。

## 改动

- 占位文字、英文、中文和 emoji 使用相同的行高与基线。修复前实测：1x 下从 27px 缩到 25px，2x 下从 54px 缩到 50px；修复后切换单行内容时输入区与整个 Composer 的高度一致。
- 多行输入仍随内容扩展。发送中、运行中和终端输入状态保持提交前的 Composer 高度，输入、历史、自动建议、更多和执行操作禁用。
- 保留正常的终端键盘输入；Shell 就绪后恢复编辑焦点。窗口尺寸或文字缩放变化时重新排版。
- 禁用状态保持统一外框，不添加输入区内边框。

## 验证

- Composer 包测试：76 项通过。
- 真实字体布局与交互：13 项通过，其中新增 4 项验证 1x/2x 单行高度、发送/运行/终端输入状态、多行高度保留与恢复编辑。
- 浅色、深色、高对比度、窄窗和大文字渲染：129 项通过；PNG 与 capture-manifest.json 位于本目录。
- Composer/终端布局视觉基准：12 项更新后正常比较通过，只更新 macOS 27 基准。
- macOS 原生应用验收：通过。包含真实 zsh、多行命令运行、禁用操作、Ctrl+C 到达终端、恢复编辑焦点和占位文字/输入等高。
- Flutter 静态分析、Dart 格式校验、生成包同步与 git diff --check：通过。

完整原生回归曾有一次路径补全等待超时，增加诊断信息后复验通过。其他 macOS 版本及真实拼音输入法/VoiceOver 人工验收未在本轮运行。

## 渲染样例

- [空输入](reference-light-empty.png)
- [运行中](light-running.png)
- [终端接收输入](dark-suspended.png)
- [2x 窄窗发送中](narrow-2x-submitting.png)

这些图片使用真实 Flutter 组件与测试状态，原生 PTY 行为由 integration_test/composer_acceptance_test.dart 验证。
