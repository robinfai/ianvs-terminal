# Trail 顶栏与标签样式调整

实现用户确认的两种布局设计：Trail 在整窗顶栏居中，设置入口固定右上角；保留原有顶部 tabs / 侧栏切换矢量图标及目标布局提示。桌面两种导航共用中性灰选中态、8px 圆角和终端图标。目录强调色、未读标记、快捷键、拖动排序、溢出菜单及侧栏宽度调整保留。

终端内容区继续使用会话配置的配色，没有覆盖用户终端主题。顶部标签保留现有等宽、最大 240 逻辑像素的规则。macOS 设置按钮的原生拖动排除区域同步移到窗口右端。

## 实际 Flutter 渲染

- [暗色侧栏](sidebar-dark.png)
- [暗色顶部 tabs](top-tabs-dark.png)
- [亮色侧栏](sidebar-light.png)
- [亮色顶部 tabs](top-tabs-light.png)
- [240px 侧栏、1.5 倍文字](sidebar-dark-minimum-large-text.png)

截图使用测试终端数据，不包含原生红黄绿按钮。

## 验证

- 6 个测试文件共 41 项组件/主题测试：40 项首次通过；旧居中断言更新为整窗居中后，所属文件 4 项复测全部通过。
- 截图测试通过，检查亮暗主题、窄窗口、大字号，没有布局溢出。
- Flutter 静态分析通过。
- Xcode Debug 构建及 2 项窗口拖动/按钮排除区域测试通过。
- 实际原生测试系统：macOS 27.0（26A428）。其他受支持版本及完整真实 PTY 端到端旅程未验证。
- Flutter 报告项目既有 uses-material-design 配置提示，本次截图的图标正常渲染。

重新生成截图（在 example 目录运行）：

```sh
flutter test --no-pub --dart-define=TRAIL_CHROME_CAPTURE=true test/design/session_chrome_visual_capture_test.dart
```
