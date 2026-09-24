# 桌面通知与操作反馈

## 两条展示链路

| 类型 | 入口 | 展示位置与生命周期 |
| --- | --- | --- |
| 复制选区、路径等 | `ClipboardBridge.copyWithFeedback` | 剪贴板写入完成后显示成功或失败，2 秒 |
| Shell、配置、SFTP、SSH 操作结果 | `AppNotifications.show`、`_showShellSnackBar` | 桌面右上角；普通 Shell/SFTP 提示 3 秒，其余沿用调用方时长 |
| 导出路径、录制已保存、收到文件 | `AppNotifications.show` | 同一区域，保留 Reveal/Replay/Save 操作与关闭回调；分别为 4/6/30 秒 |
| 后台会话活动、终端 OSC 通知、Profile trigger | `_sendShellNotification` → `_dispatchShellNotification` → `WindowBridge.showNotification` | macOS `UNUserNotificationCenter`；系统决定屏幕横幅的位置，按原有策略、限流与权限处理 |

复制反馈原先直接调用底部 `ScaffoldMessenger.showSnackBar`，会覆盖终端底部
readline 输入区域。它不是 macOS 通知中心横幅，不应通过调整系统通知权限解决。
`LocalTerminalNotificationDispatcher` 是独立策略模型；应用内操作提示不经过它。

## 桌面呈现规则

- `MaterialApp.builder` 安装 `AppNotificationHost`，覆盖主界面和应用内对话框。
- 位于窗口右上角、标题栏和标签栏下方；最大宽度 360，随窗口缩小。列表限制在
  窗口上半部，长文本和大字号可滚动，不改变终端布局，也不占用底部输入区域。
- 最新通知在最上方，同时显示至多 3 条。超出的旧普通提示直接退场；带操作的
  通知保留在队列中，重新可见时开始计时，不因连续复制而丢弃待保存文件。
- 相同的纯文本状态提示合并为最新一条并重新计时；含操作按钮的通知不合并。
- 每条单独计时。鼠标悬停或键盘焦点进入通知时暂停，离开后重新计时。
  屏幕阅读器的 accessible navigation 模式下等待用户关闭。
- 出现时不主动请求焦点，不拦截通知区域外的点击或键盘输入。关闭按钮使用
  Material 本地化标签，消息通过语义 live region 宣告，减少动画设置禁用淡入。
- 卡片复用 `AppPanel` 与主题的颜色、字体、间距、圆角、阴影，支持浅色和深色。
- Android/iOS 保留 `SnackBar`；桌面宿主缺失时也回退至 `ScaffoldMessenger`，
  便于嵌入与已有组件测试。

## 生命周期约定

`AppNotificationController.closed` 保留 `SnackBarClosedReason`，收到文件的
提示可据此区分 Save、超时、手动关闭、移除和宿主卸载，执行原有资源清理。
`controller.close()` 关闭对应通知，避免录制回放操作误关后来出现的复制提示。
含自定义按钮的 content 应传 `hasActions: true`，避免被按普通状态提示去重或淘汰。

Widget previews 位于 `example/lib/ui/previews/app_notifications_preview.dart`。
回归覆盖排序、去重、独立超时、操作队列、焦点、指针、屏幕阅读器、窄窗大字和
移动端回退；复制测试覆盖异步成功与平台写入失败。
