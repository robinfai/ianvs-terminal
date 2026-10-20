# 11 · 桌面交互、焦点与执行安全合同

> 2026-10-10 修订：与本文有关的敏感性、补充要求、收起/Esc、人工编辑保存和未知结果出口，统一以 [v1.1 交互修订](16_REVISION_1_1.md) 为准。原有 64 项需求及全部原生验收门槛保留。


## 1. 四维状态和身份

|维度|可能状态|决定者|
|---|---|---|
|显示|Blocks、task、Raw observer、Raw input、Reader、Review|当前pane视图|
|输入意图|auto + resolved(command/AI/unknown)、explicit command/AI|当前草稿与已存在的意图机制|
|任务|idle/thinking/reviewing/awaitingApproval/executing/paused/failed|既有任务controller|
|写授权|none、人手有效owner、单次获批Agent operation|既有native/runtime guard，不是UI bool|

提交身份至少关联window/pane所属Session、SSH node/context、task/turn generation、editor revision、proposal revision、operation/submission id和manual input generation。字段名是分析模型，Codex映射现有类型，不重写公共协议。

## 2. 动作的副作用矩阵

|动作|草稿/显示|模型|有效终端提交/输入|
|---|---|---|---|
|选块/文本/hover/右键|只改选择与情境菜单|无|无|
|AI诊断|附来源，空稿填问题，有稿不覆盖|无起始请求|无|
|采用补全/历史、保存展开编辑|改当前草稿revision|无|无|
|切Auto/Command/AI|显示最终去向|本地分类沿用既有机制|无|
|发送AI/补充要求|冻结本轮稿/来源|一次用户起始事件，正常多轮循环可继续|不自动批准|
|手工执行|校验可见意图/lease|零推理|同operation最多一次有效提交|
|打开审阅/证据|仅阅读|无新增请求|无|
|编辑提案保存|新revision、旧审批失效|Smart可能重新独立审阅|无|
|批准一次|有效revision+target校验|后续循环按原机制|仅该operation授权|
|只读查看|换显示，保留任务|原任务可继续|observer UI写入为0|
|暂停AI|撤销后续操作，保留已运行命令|取消相关请求|不发Ctrl+C|
|接管输入|先撤销Agent后续写，后交human owner|取消相关请求|接管本身不提交草稿|
|中断命令|明确目标，观察实际结果|不创建新推理|已有owner通道显式中断|
|切tab/pane/window|变活动视图，不重定向任务|原任务按既有策略|无隐式转授权|
|继续任务|重读原receipt与目标后规划|可能继续|不重放已发送输入|

## 3. 为什么只读不能仅设置TextField.readOnly

必须审查所有写入来源：raw keyboard、shortcut bridge、粘贴/拖放、mouse reporting、focus reporting、IME提交、延迟回调、窗口激活和自动focus恢复。observer仅持读/选区能力；同一个可写FocusNode不能同时交observer与live viewport。

进入observer不提交未完成composition，不清本地草稿；人工要输入先显式接管。核心原有终端查询应答仍允许；使用来源可追溯的observer_input_write_count判断，不能破坏VT协议来取得“0字节”。

## 4. 窗口与pane切换

key window内的活动pane才可接收人工输入。AI通知、输出、shell ready、补全返回都不能激活另一个pane或窗口。保存阅读锚点按sourceSession/block/原始行或item内偏移，不仅裸scrollOffset。

在A打开审批后切B：审批仍属A，批准禁用并可定位A；不能让窗口状态栏变B后拿B当前lease批准A命令。再次回A须重新核对revision/target。已完成操作的合法cwd通知例外沿用现有严格关联，不扩大到一般OSC事件。

## 5. Enter/Esc与焦点恢复

IME具有最高优先；modal/menu优先于pane动作；候选采用优先于草稿执行。Enter一次只做一种行为；批准只能由明确焦点的有效按钮激活，不能全球监听Enter。Esc从最内层弹层/候选/历史逐级退出，不直接暂停整个任务，更不能误发TUI Esc。

关闭Reader回打开前的阅读锚点；明确“放入编辑”才转到对应Composer。关闭审批回触发点/任务状态，不落到已销毁按钮或自动触发主操作。ready恢复编辑焦点前检查key window、active pane、当前focus owner与generation；用户已转到别处则不恢复。

## 6. 不确定结果与幂等

同operation重复查询返回原结果；参数不一致拒绝。已提交但确认未到是unknown，不是未执行。恢复/重连/切后端/新布局不允许自动新建id重跑。连接死亡后无法证实就保持未知，并说明可采取的检查路径。

一条命令可能产生多个native write/协议帧；有效提交和副作用≤1才是产品保证。partial send_keys显式显示已发送步骤及下一步未知，不自动重放余下步骤；继续任务是重新观察规划。

## 7. 回调验证表

|事件|必须核验|失效处理|
|---|---|---|
|补全/历史返回|Session/context/editor revision/query id|丢弃旧结果，不覆盖新稿|
|AI回复|task、配置连接identity、turn generation|不注入新任务/新pane|
|批准回调|原target、operation、proposal revision、owner generation|拒绝并重新审阅|
|真正提交前|lease/readiness/current node/manual input generation|fail closed|
|accepted receipt|原submission与原editor revision|只清原稿，保留新稿|
|目标/cwd事件|可信已接受Block、同session/node|否则要求明确目标变化处理|
|Reader分页|来源、保留范围、宽度/分页版本|不混页，显式重读|
|布局后restore|当前view/focus generation、稳定锚点|不抢焦点；淘汰时说明降级|
|关闭/接管|controller存活、queued write generation|撤销所有后续未授权回调|

## 8. 模型API / ACP的一致与不同

一致：任务绑定、宿主审批、终端读写、operation receipts、证据来源。不同：API的网络循环与ACP本地适配器进程/session/load生命周期分别验证，不用其中一种通过代替另一种。ACP permission event不是终端写许可；不启用当前受限profile外的native shell/files/browser等工具。

本包不提供“整个任务永久允许”。Smart只是当前操作的独立审阅策略；审阅失败保守处理。后台任务能合法继续，不代表任何UI窗口随时可改其目标。

## 9. 冲突与跨端

D包不能全局覆盖移动S包的Return、字号、六行预览。可共享controller主操作决策、state/receipt模型、tokens角色；平台输入差异以adapter和tests表达。分支合流先对相同canonical文件做集成，再统一生成standalone，不能分别手改两个镜像。
