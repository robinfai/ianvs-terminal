# macOS 回放辅助访问补充验收

日期：2026-09-10。延续 [上一轮真实 GUI 验收](../macos-acceptance-20260909/README.md)，
使用相同的独立数据目录、Keychain namespace 和已保存 SSH 录制。本轮未配置数据 API。

## 已确认并修复

回放的共用图标按钮在外层声明名称和按钮角色，内层 Material 3 `IconButton`
又建立自己的语义边界，导致有名称的节点没有点击动作。通过实际语义操作可重现：

```text
The given node does not support SemanticsAction.tap.
flags: [isButton, hasEnabledState, isEnabled], label: "Play replay"
```

为共用回放按钮使用 `MergeSemantics`，使名称、点击动作、焦点和禁用状态属于同一
节点；同时为录制库的关闭、刷新按钮补充名称并合并动作。没有改变按钮尺寸、样式、
鼠标点击或键盘焦点逻辑。速度和计时菜单的实际语义操作已经通过，因此没有修改它们。

新增回归在打开侧栏前启用语义树，覆盖 800×600 下侧栏进入回放、通过有名称的
语义节点播放/暂停、调整速度、打开计时菜单、激活搜索并输入文本、关闭回放、
重新打开录制库、刷新和关闭。该测试验证真实语义节点与操作，而非只检查 widget 属性。

## 验证结果

- 录制库组件测试：9 项通过。
- 完整应用测试：192 个文件、1,791 项通过。
- 相关 Dart 静态分析和格式检查通过。
- 隔离 Release 构建、ad-hoc hardened-runtime 签名及签名校验通过。
- Computer Use 在修复版真实窗口完成录制打开、播放、搜索 4 个匹配及 Escape 关闭。
- 独立代码复审未发现新增行为或焦点问题。

本轮变更局限于 Flutter 语义聚合及回归测试，没有再次运行 Rust、Go 或原生测试。
上一轮完整 `make verify` 的通过记录仍保留在其原始日期，不能把它当作本轮重新执行的结果。

## 原生辅助访问仍未通过

Computer Use 冷启动复验时，打开回放后曾只读到 `Trail` 容器；修复版也出现画面已更新，
AX 树仍停留在旧 Chrome 按钮的情况。1152×768 宽窗口重新打开侧栏也可复现，因此
当前证据不足以将其归因于紧凑布局的 `BlockSemantics`，本轮没有修改遮罩逻辑。

修复版搜索截图：[replay-search.jpg](replay-search.jpg)。同一画面的原生 AX 输出：
[native-ax-stale.txt](native-ax-stale.txt)。两者展示了画面与工具所读树不一致的情况。

系统设置中 VoiceOver 原为关闭；点击后曾显示开启，但后续复查已经回到关闭，未能
建立稳定的 VoiceOver 对照会话。本记录不宣称 VoiceOver 朗读、原生 AX 更新或完整
辅助访问验收通过。终端画布本身的文本朗读和回放拖动把手的键盘操作也未纳入本轮修复。

原生退出确认再次未被工具暴露，工具仍返回主窗。没有为了绕过这一现象改动原生退出
合同。通过活动监视器准确选择独立的 `Trail Acceptance Final` 和 `Trail Accessibility`
测试进程，在没有进行中的录制后结束它们；正式 `Trail` 进程保持运行。最终已确认两个
测试实例均不再运行，VoiceOver 为原来的关闭状态，系统设置窗口已关闭。

## 构建与日志

- 入口：`example/tool/macos_acceptance.dart`。
- 构建副本：`/tmp/trail-macos-acceptance-20260909/Trail Accessibility.app`。
- Bundle ID：`work.ianvs.trail.acceptance.20260910.accessibility`。
- 构建指纹：[build-info.json](build-info.json)。
- 组件测试日志：`/tmp/trail-replay-ax-library-tests.txt`。
- 应用全量日志：`/tmp/trail-accessibility-app-suite.txt`。
- 分析日志：`/tmp/trail-accessibility-analysis.txt`。
- 构建日志：`/tmp/trail-replay-ax-build.txt`。

数据和录制继续保留在上一轮独立目录。
