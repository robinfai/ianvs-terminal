# D09 目标变更与恢复：实现复核

2026-10-03，`composer` 工作区。依据 DESIGN.md 的 D09 和 `screens/D09-v2.png`。本记录覆盖目标选择流程，不代表全部 20 场景完成。

## 发现与整改

实际截图中，原目标的标题为空时显示成 `Original: / root / /tmp`；会话、上下文和目录拼成一行；选择入口只有底部恢复图标。时间线同时显示目标变化和泛化错误，重复解释同一状态。

修复后原目标／当前目标使用同一组件，名称、目录、终端上下文分别展示。名称为空则使用真实 session ID，不推测远端主机名。浅灰／深色中性表面与现有主题一致，两个动作直接放在目标提示旁。普通错误只有在未被目标提示解释，或另有终端／未知提交故障时才显示。

「返回终端检查原目标」关闭任务视图，由用户切回原终端上下文；不会暗中输入 `exit` 或 SSH 命令，也不会假装已经返回原节点。「在当前目标继续」确认用户看到的目标，重新读取终端；若目标已改变，则保持暂停并展示新目标。旧提案保留为已撤销，新提案仍需单独确认。

底部恢复入口保留弹窗。短屏中两个操作放在同一行，内容可以滚动；手机固定字号、至少 44px 操作高度。桌面继续覆盖 2 倍字号。

## 四步审计

| 步骤 | 复核结果 | 实际组件截图 |
| --- | --- | --- |
| 1. 原提案后发生目标变化 | 原提案不可批准；原目标／当前目标有独立标签；提供返回与继续入口 | [变化提示](evidence/target-after/01-target-change.png)、[中文长路径](evidence/target-after/desktop-zh-light-notice.png) |
| 2. 打开恢复选择 | 名称空值已回退；路径与上下文分行；提示新命令仍需批准。返回不请求模型、不写终端 | [选择弹窗](evidence/target-after/02-target-choice.png) |
| 3. 确认期间再次跳转 | 旧选择被拒绝；请求数和终端写入数不增加；提示更新到第二目标 | [过期选择](evidence/target-after/03-stale-choice.png) |
| 4. 对新目标显式继续 | 读取新目标后产生独立提案；原撤销记录仍在；执行数仍为零，等待新批准 | [重新提案](evidence/target-after/04-fresh-proposal.png) |

四步在此测试范围内通过。另有回归核验：同一帧重复点击恢复只开一个弹窗；重复点击行内继续只请求一轮；弹窗打开后切换任务不能把旧选择应用到新任务；草稿与尚未发送的附件保留。

## 自适应与主题

12 组长名称／路径变体：桌面英文、桌面中文、桌面 2 倍字号、390×620 手机、320×260 短屏、844×300 横屏，各含浅色与深色。目标提示与时间线共享滚动；弹窗内容超长时可以滚动，操作区保持可达。

- [手机深色弹窗](evidence/target-after/phone-dark-dialog.png)
- [短屏初始](evidence/target-after/phone-short-light-dialog.png)及[滚动后](evidence/target-after/phone-short-light-dialog-scrolled.png)
- [横屏深色滚动后](evidence/target-after/phone-landscape-dark-dialog-scrolled.png)
- [桌面 2 倍字号](evidence/target-after/desktop-large-dark-dialog.png)

测试主题原先只把 macOS 主题的 platform 字段改成 iOS，没有使用生产触控尺寸。改用实际 iOS 主题后，既有测试发现极短屏输入区域为 76px（既有要求至少 80px），长附件的范围文字越过 320px 屏幕右边界。已调整单行输入区横向留白，并以 Composer 的可用宽度约束整颗附件。没有缩小触控按钮或隐藏行号范围。

[失败日志](evidence/target-app-before.log)、[长附件修复](evidence/target-after/D07-phone-touch-range.png)、[极短屏输入修复](evidence/target-after/M06-short-touch-theme.png)。短屏图的下半部分是键盘 inset 占位，不是系统键盘截图。

## 验证与边界

- 完整 AI、Shell、终端模式回归：613 项通过，[日志](evidence/target-app-tests.log)。本轮增加 15 项：3 项交互守卫及 12 组目标布局。
- 实际字体截图运行：工作区全部 45 项通过，[日志](evidence/target-captures.log)。不是只用默认测试字体做布局判断。
- AI 生产代码及工作区测试静态分析：[无问题](evidence/target-analyze.log)。
- 发布包生成源码：[没有漂移](evidence/target-mirror.log)。本轮没有修改核心包。

目标选择使用生产 Flutter 组件、内存终端端口与固定模型回复；不是实际 SSH 跳转证据。手机遵从用户要求，仅使用固定字号和 iOS 平台组件在 macOS 渲染，未做 iPhone 真机或系统键盘测试。设计图只用于对照，不作为应用截图。真实 `ssh cloud`、其他场景最终视觉复核和模型质量评估仍见 IMPLEMENTATION.md。
