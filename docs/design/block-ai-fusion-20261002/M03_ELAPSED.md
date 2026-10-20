# M03 耗时保留与 D13 导航补验

2026-10-03，当前 `composer` 工作区。手机遵从固定字号规则，以 iOS 主题生产组件验收，不进行 iPhone 真机测试。原生流程实际运行于 macOS 27.0.1（26A434）。

## 耗时展示

此前手机预览和阅读页没有命令耗时，桌面只显示已完成命令的耗时。AI 暂停后的观察状态不能代替命令本身的运行时间。

现在三处共同使用原生块的 `startedAt` / `finishedAt`。这些时间戳由客户端处理 shell 标记时记录，不依赖 SSH 节点的时区。运行时每秒仅更新耗时标签，完成后固定为原生时间差；没有时间戳时不编造耗时。后台和被覆盖的页面停止刷新标签，恢复后按原始开始时间重新计算，不从零计时。

- 手机列表：耗时位于现有标题行，与运行／完成图标并列，没有新增预览高度；仍只显示末尾六行。
- 手机阅读页：在现有标题区域补充耗时，保持单一输出滚动容器。
- 桌面：沿用块底部状态行，整块仍受视口三分之一高度约束。
- 耗时不是 live region，不会每秒覆盖 AI 阶段变化的语义播报；不读取额外终端数据、不发送输入、不重建输出帧。

六项组件回归覆盖中英文、桌面和 320px 手机、阅读页往返、运行刷新与完成冻结、毫秒／秒／分钟、缺失时间戳、时钟提前、后台恢复、输出帧与几何位置不变及语义隔离。它们包含在最终共享终端的 70 项测试中。

浅深色 workspace 组合测试保留 60→120→180 行输出、六行预览、历史锚点和草稿。深色用显式“暂停 AI”，浅色由进入后台触发暂停；回前台不请求模型或发送终端输入。完成后均保留 `1m 32s`。

| 状态 | 最终源码截图 |
| --- | --- |
| 手机运行与六行预览 | [深色](evidence/elapsed-navigation/M03-live-six-rows-dark.png)、[浅色](evidence/elapsed-navigation/M03-live-six-rows-light.png) |
| 暂停后仍保留运行耗时 | [深色](evidence/elapsed-navigation/M03-live-paused-after-background-dark.png)、[浅色](evidence/elapsed-navigation/M03-live-paused-after-background-light.png) |
| 完成后保留耗时 | [深色](evidence/elapsed-navigation/M03-completed-elapsed-dark.png)、[浅色](evidence/elapsed-navigation/M03-completed-elapsed-light.png) |

实际 PTY 执行 `sleep 12; printf 'SILENT_DONE\n'`，暂停 AI、继续观察和补充要求均没有中断或重发命令。同一个块的开始时间保持不变，原生结束时间差 **12,023ms**，完成显示 **12.0s**。见 [暂停截图](evidence/elapsed-navigation/D04-silent-command-ai-paused-elapsed.png)、[完成截图](evidence/elapsed-navigation/D04-silent-command-completed-elapsed.png) 和 [原始结果](evidence/elapsed-navigation/result.json)。

## 快速导航覆盖

原生回归曾在第二次定位提案后找不到拒绝按钮，记录于 [中间失败日志](evidence/elapsed-navigation/elapsed-native-verified.log)。进一步构造组件复现：点击“返回阅读位置”后，在恢复完成前再次点击“查看最新”，旧异步恢复仍把视口拉回历史，距底部 2,202px。见 [修复前](evidence/elapsed-navigation/navigation-cancel-before.log)。

现在“查看最新”同时撤销工作区和共享时间线尚未完成的恢复。新增测试在恢复开始前、第一帧和第二帧重复触发新定位，最终保持最新位置，不产生模型请求或终端输入。见 [修复后](evidence/elapsed-navigation/navigation-cancel-verified.log)。

最终原生流程再次通过持续输出、回看、定位、返回、第二次定位与拒绝提案。三批输出为 81→161→241 行；整块 257.4px，后续 255px，视口 800px；原执行证明文件只有一个 `x`，新提案未执行。[第二次定位截图](evidence/elapsed-navigation/D13-stream-second-explicit-proposal-location.png)保留完整提案和审批入口。

## 最终检查与边界

- [应用回归](evidence/elapsed-navigation/elapsed-navigation-app.log)：728 项 AI、Shell 与会话测试通过。
- [共享终端回归](evidence/elapsed-navigation/elapsed-navigation-terminal.log)：70 项通过，含耗时、阅读、锚点、复制和触控。
- [原生／组件验收](evidence/elapsed-navigation/elapsed-navigation-final.log)：1 项完整 macOS HTTP→PTY 流程与 4 项手机生产组件预览，共 5 项通过。
- [最终手机截图](evidence/elapsed-navigation/elapsed-mobile-final.log)：浅深色两个组合场景通过；属于应用回归中的用例，不另加计数。
- [静态分析](evidence/elapsed-navigation/elapsed-navigation-analyze.log)无问题；[发布镜像](evidence/elapsed-navigation/elapsed-navigation-mirror.log)无漂移；`git diff --check` 通过。

原生模型响应为确定性本地 HTTP fixture，仅证明交互、执行及恢复链路，不证明真实模型质量。手机截图来自固定字号生产组件，不是系统键盘或真机证据。以上补齐 M03 的耗时缺口和 D13 的快速导航问题，完整 20 场景的其余待验项继续保留在 [实现矩阵](IMPLEMENTATION.md)。没有提交或推送。
