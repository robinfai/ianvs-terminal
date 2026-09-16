# Alt/Option 单击移动终端光标：实现与验收

基于工作树基线 `469c1ff8`。未修改原有 iOS 工程改动及其他用户文件。

## 实现

- Alt/Option + 鼠标左键短点击（< 500ms），在抬起时定位。使用当时最新帧的光标。
- 超过拖动阈值后永久取消本次定位，保留矩形选择，包括空白区拖动和拖回起点。
- 普通缓冲区只发送左右键，跨行按源行与终端列展开；备用缓冲区支持上下左右，并按本项目“前一行 wrapped”语义处理软换行。
- 使用 `TerminalTextCells` 修正中文、宽字符续格计数，续格点击吸附到字符起点。复杂 Unicode 的编辑单位仍可能与前台应用不同。
- 根据 `applicationCursor` 编码 CSI/SS3，无物理 Alt 修饰，一次发送。终端输出决定实际光标，不直接修改渲染坐标。
- 鼠标报告模式交给应用；本地点击不会产生孤立的应用鼠标释放事件。
- 使用当前底部视口的源行范围判定活动屏幕，不把累计历史计数 `globalBottomRow` 与保留缓冲区源行混用；已覆盖历史裁剪后与备用屏幕的计数差异。
- 回看历史、折叠占位行、屏幕外坐标不定位；投影后的可见行转换为源行；即时回放显式关闭功能。
- 成功识别定位手势后清除临时选择，并跳过自动复制、链接打开。
- 配置 `interaction.altClickMovesCursor` 默认 true，支持 JSON/copyWith；应用“配置编辑器 → 按键”中提供中英文开关，保存与分区重置均接入。
- 应用包装视图与独立发布包嵌入视图传递配置。发布包通过 `tools/sync_terminal_core.dart` 同步。
- 该选项只控制客户端，不写入严格的原生 SessionConfig v1 协议。旧配置仍默认开启。

算法参考：[xterm.js MoveToCell](https://github.com/xtermjs/xterm.js/blob/master/src/browser/input/MoveToCell.ts)、[SelectionService](https://github.com/xtermjs/xterm.js/blob/master/src/browser/services/SelectionService.ts)。不依赖 shell integration；不承诺识别提示符或输入末尾。前台应用不支持对应方向键时，仍有兼容性限制。

## 自动化验收结果

| 范围 | 结果 | 证据 |
| --- | --- | --- |
| 主包算法/手势/输入/移动端/键盘/配置 + 发布包算法/手势/原生配置/嵌入 + 真实 PTY | 185 passed | `acceptance.log` |
| 配置编辑器全部测试，包含关闭新开关并保存 | 22 passed | `profile-editor.log` |
| 真实 zsh 与 bash：ASCII 左/右、中文左/右、跨软换行左移，发送后插入 X 并执行命令核对结果 | 10/10 场景通过 | `real-pty.log` |
| 两个包与应用相关文件静态分析 | No issues found | `analyze.log`、`profile-analyze.log` |
| 发布包同步 | current | `sync.log` |
| 扩展到应用全部终端渲染/选择测试（坐标边界补测前） | 282 passed，4 个既有触控板失败 | `expanded-regression.log` |

扩大回归中以下失败已用修改前的主包 TerminalViewport 与应用包装视图复测，四项同样失败，确认不是本次引入。对比后已恢复当前实现：

1. alternate trackpad pan：期望 OA，实际 OB。
2. positive scrollback deltas：期望正数，实际负数。
3. continues trackpad momentum：方向断言失败。
4. momentum can carry scrollback back to bottom：回底断言失败。

证据见 `baseline-trackpad.log`。没有改写这些用例以隐藏失败。

包含 `shell_screen_instant_replay.dart` 的扩大静态检查还报告一个既有 `prefer_initializing_formals` 提示（第 8 行）；这段构造代码未被本次修改。新增代码没有分析错误或警告。

## 复现

仓库根目录：

```sh
flutter test --no-pub \
  packages/ianvs_terminal/test/terminal_cursor_move_test.dart \
  packages/ianvs_terminal/test/terminal_viewport_alt_click_test.dart \
  packages/ianvs_terminal/test/terminal_input_controller_test.dart \
  packages/ianvs_terminal/test/terminal_viewport_keyboard_test.dart \
  packages/ianvs_terminal/test/terminal_viewport_mobile_gesture_test.dart \
  packages/ianvs_terminal/test/terminal_config_test.dart \
  packages/ianvs_terminal/test/terminal_session_config_v1_test.dart \
  packages/ianvs_terminal_core/test/terminal_cursor_move_test.dart \
  packages/ianvs_terminal_core/test/terminal_viewport_alt_click_test.dart \
  packages/ianvs_terminal_core/test/terminal_session_config_v1_test.dart \
  packages/ianvs_terminal_core/test/embed/terminal_embed_current_test.dart \
  example/test/terminal/terminal_alt_click_pty_test.dart
dart run tools/sync_terminal_core.dart --check
```

应用目录 `example`：

```sh
flutter test --no-pub test/profiles/profile_editor_test.dart
```

真实 PTY 验收需要 Unix、Python 3，以及 `/bin/zsh` 或 `/bin/bash`，禁用 shell 用户启动脚本。当前机器两个 shell 均已验收。Windows 跳过此 PTY 用例，其余算法和 Flutter 交互测试不依赖真实 shell。
