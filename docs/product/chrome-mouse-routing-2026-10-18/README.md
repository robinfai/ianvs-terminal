# macOS 顶部标签和 Block + AI 鼠标点击修复

在 macOS 27.0.1 (26A434) 的当前 Trail 中复现：顶部标签和 AI 按钮有 hover，真实左键没有切换；底部详情按钮、辅助功能激活与右键菜单正常。

临时诊断确认：800 × 600 逻辑像素窗口中，AI 按钮的原生点击点为 (739, 578)，对应顶部坐标 (739, 22)。Flutter 报告的拖动区域不包含此点，AppKit hitTest 命中 FlutterView，窗口收到 leftMouseDown 和 leftMouseUp，但 Flutter 顶部 Listener 未收到事件。临时诊断代码已移除。

## 修改

在 MainFlutterWindow 的事件分发中，对顶部非拖动区且命中内容视图的左键事件直接调用内容控制器。保持同一接收者直到鼠标抬起，包含拖出标题栏后的移动和释放。空白拖动区继续使用原生 performDrag；实际系统窗口按钮、正文和右键事件保持原分发路径。

## 验证

- macOS Debug 构建通过。
- 3 项原生 XCTest 通过：控件实际窗口事件序列（标签、AI、跨区域拖动/释放、系统按钮/正文/右键排除）、已测量拖动区、尺寸变化后撤销旧区域。
- 独立开发构建使用真实坐标鼠标点击：AI 工作区打开；新增第二个本地 zsh 标签；点击第一个标签恢复其 Block + AI 页，再点击第二个标签恢复普通终端；拖动第二个标签到第一个位置后，标签顺序与当前会话均正确。
- 先前定位阶段 desktop_unified_chrome_test.dart 6/6 通过，说明仅 Flutter tester 点击无法覆盖这次 AppKit 分发问题。
- git diff --check 通过。

实际运行系统为 macOS 27.0.1；没有新增其他 macOS 版本、手机或模拟器验收。原来的生产 Trail 及四个会话未重启、未覆盖安装，仍运行旧代码。PR 保持 Draft / OPEN，不合并。
