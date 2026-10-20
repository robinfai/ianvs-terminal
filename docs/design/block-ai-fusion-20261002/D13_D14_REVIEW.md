# D13 导航与 D14 平台偏好整改

2026-10-03，`composer` 工作区，macOS 27.0.1（26A434）。对照 [D13](screens/D13-v2.png)、[D14](screens/D14.png) 与当前生产截图。使用既有 imagegen 图作为设计参照；没有将图像模型当作自动验收器。

## 发现与修复

**D13：宽桌面的导航含义不清楚。** 原生截图只有向下、返回图标，虽然有 tooltip，但没有设计稿中直接可见的文字。现在按真实字体测量、字号与可用宽度显示“定位待确认提案”“返回阅读位置”；空间不足时保留带说明的图标，手机短屏继续使用现有任务菜单。状态、暂停、执行和定位仍是独立操作，导航不会审批命令。

五组生产组件覆盖中英文宽屏、深色、960px／600px 桌面 2× 字号与 320px 手机固定字号。新提案到来保持原项及项内偏移；点击定位能看到待审阅命令，返回后恢复同一锚点；四次模型请求后不再请求，PTY 写入始终为零。字体截图通过后，默认测试字体的完整回归另发现窄桌面“补充要求”按钮溢出 74px。已让按钮受剩余宽度约束并允许文本自然换行，没有缩放整页或删掉完整标签。

**D14：无法恢复平台默认。** 原底层使用空覆盖值表示平台默认，但设置页只有 Normal／Blocks，用户一旦明确选择就无法恢复默认。现在增加第三项“跟随平台默认”，显示与保存均区分空覆盖和明确选择。清除覆盖后，手机新会话默认 Blocks、桌面新会话默认 Normal；仍以当前节点协商结果决定 Blocks 是否可用。既有会话的模式和手动选择保持不变。

设置帮助同时说明“仅用于新会话”和“能力恢复后手动切回”。保留现有设置导航与原 AI 配置表单，不增加后台代理或自动执行。原生测试通过设置入口选择默认、检查未保存状态、保存，再核对同一会话、原始块快照和模型请求计数都不变。模型／设置／Shell 回归还覆盖跨平台解析、保存与取消，以及恢复默认之后新旧会话采用各自正确模式。

## 证据

- [桌面新提案到来后仍在阅读历史](evidence/navigation-preferences/native/D13-stream-completed-proposal-keeps-history.png)、[明确定位后返回入口](evidence/navigation-preferences/native/D13-stream-second-explicit-proposal-location.png)。原生输出分三批 81→161→241 行，命令只执行一次；具体锚点与偏移见 [result.json](evidence/navigation-preferences/native/result.json)。
- [英文文字入口](evidence/navigation-preferences/components/D13-wide-en-located.png)、[深色历史状态](evidence/navigation-preferences/components/D13-wide-zh-dark-reading.png)、[窄桌面 2× 字号](evidence/navigation-preferences/components/D13-narrow-desktop-2x-located.png)、[手机固定字号](evidence/navigation-preferences/components/D13-phone-fixed-located.png)。这些是生产组件渲染，不能外推为实体手机系统键盘验收。
- [三种模式偏好](evidence/navigation-preferences/native/D14-platform-preference-options.png)、[平台默认尚未保存](evidence/navigation-preferences/native/D14-platform-preference-staged.png)。与既有 [AI 连接测试成功但未保存](evidence/navigation-preferences/native/D14-connection-tested-not-saved.png)、[保存后任务保留](evidence/navigation-preferences/native/D14-saved-task-retained.png) 分开表达。

测试夹具的两项问题也保留记录：时间线控制器需要使用其公开具体类型读取锚点；手机只允许 SSH，且协商必须返回 `shell` transport。最初沿用本地端口造成手机不建连／正常降级，已修正夹具，没有放宽生产能力判断。

最终 885 项应用回归、5 项真实 macOS／手机组件流程通过，另以实际字体重跑 5 项导航截图用例。44 项偏好专项属于应用回归子集，不重复累计。静态检查无问题，发布镜像和 diff 检查通过；33 项证据、16 个当前源码哈希见 [归档清单](evidence/navigation-preferences/manifest.json)。最终原生图确认两个导航文字入口可见，平台默认帮助完整换行、保存区可达，原提案仍需独立执行。

本轮未测试真实 cloud 节点，没有连接外部模型或进行实体手机测试。D10 未知回执的深色／放大字号视觉复核、D14 其余配置状态与完整 20 场景最终审计仍待继续；本页不宣称整体目标完成。
