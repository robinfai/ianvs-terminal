# C9–C10 修复、原生复验与手机连接恢复

2026-10-10，当前实现 C10 为 `2d18e608c2a1149a093451b5246cb370de0167c3`，前次 C9 为 `a60bc9d78f5f51414c43590ee6f34ae3cce7e7b9`。本记录把 E1 原生故障发现、C9 自动回归和手机 C4 配置恢复分开；不将局部复验换算为完整 PRD 场景通过。正式主 manifest 仍描述 C8 的 3/64 passed、61/64 not_run 历史，当前整体仍为 `implemented_unverified`。

## 已确认的问题与 C9 行为

| 问题 | 发现依据 | C9 修复与回归 |
|---|---|---|
| 只有未发送草稿时关闭不确认 | E1 正常 App UI 分别关闭 idle AI 草稿和 ready Composer 草稿的标签，未出现保护且原会话被移除；截图、录屏与进程记录的证明范围另列 | 草稿本身触发保护，覆盖命令／AI、旧任务草稿及只有来源附件的情况；取消保留，确认只关闭目标，没有草稿或其他风险仍直接关闭。关闭文件22项通过 |
| 右键邻 pane 会切换输入目标并使 Composer 失焦 | E1 两 pane 正常 UI 前后截图和操作者动作记录；没有对应右键连续录像 | 右键不激活非活动 pane，桌面 secondary tapOutside 不移除原编辑焦点；左键／触控和真实菜单显式焦点行为保留 |
| 不切换目标后，非活动 TUI 仍收到鼠标字节 | 独立源码复评及实际字节红测：非活动 pane 收到 SGR press/release，切走后未重建的旧 sink 仍可写入 | 在写入边界实时核对当前活动 session，保留已活动 TUI 鼠标正例、现有 epoch／窗口／AI／Reader 门禁 |
| 逻辑尺寸相同而 DPR 改变时 native 指标不更新 | 永久回归先红，包含选区释放延迟和快速 DPR 往返 | 调度及延迟提交同步核对 Size + DPR；旧回调不能覆盖新指标。属于 widget/捕获 resize 参数，未完成实体跨显示器验收 |
| 打开的旧菜单会跟随新目标 | 红测覆盖原 pane 自然退出、移动到其他 tab、根 pane 拆出并复用 tab ID | 冻结原 pane 与成员身份；目标移动／拆出后旧菜单失效，不关或改新 pane；自然退出后明确关闭原 tab 的正例保留 |

上述修复经独立只读复评未见新增阻断。定向日志在提交前工作树执行，C9 包含经核对的同一源码；不伪称日志在 clean C9 运行。新增 pane/metrics 14项、相关10文件198项、手机与输入71项均通过，另关闭保护文件22项通过。集合有重叠，不相加为唯一测试总数。静态分析、格式、diff和架构预算通过。

原始故障材料见 [E1原生归档](../evidence/shared/E1-native-findings/archive-index.json)：6张原图与对应进程/窗口记录，以及129.438333秒草稿关闭录像。独立录像复核实际抽看131个约1秒采样和两次关闭过渡的全部88个源帧（去重215帧），不是3771帧全部逐帧审阅；两个关闭过渡未出现窗口内确认。右键只有原图与操作记录，没有对应连续录像。原图/sidecar含开发账号路径，不声称匿名。

C9定向支撑见[关闭保护回归](../evidence/shared/C9-close-regression/archive-index.json)与[pane/指标回归](../evidence/shared/C9-pane-regression/archive-index.json)。C10日志和8份源码对照见[输入回归归档](../evidence/shared/C10-input-regression/archive-index.json)，保留原两项红测及后续成功记录。

## 完整 gate 与原生复验

C9 完整 `make verify` 第11轮于09:03:59–09:12:38 UTC运行519秒，源码首尾clean，exit2。应用3,083通过／1跳过／2失败；失败是非活动TUI首个主键鼠标报告与切换pane的旧目标focus-out被新门禁挡住。后续macOS构建／原生gate未执行，不把前置通过称为完整通过。原日志和metadata保留至 `evidence/shared/C9-gates/`。C10已修复这两项并保留原测试断言，完整gate另记，不回写C9结果。

C10提交前的最终回归为：原widget_test.dart 103/103、相关15文件297/297、canonical键鼠/手势/焦点6文件165/165；新增验证仅精确ESC[O系统协议豁免非owner限制，sendText同字节不豁免，AI/Reader/旧epoch仍撤权。源码镜像、格式和静态分析通过；独立复评未见阻断。日志运行在提交前工作树，8份最终源码与C10逐字节核对。完整 [verify12](../evidence/shared/C10-gates/verify-12.log) 于2026-10-10 09:26:18–09:39:30 UTC在干净C10运行792秒，exit0；[原始metadata](../evidence/shared/C10-gates/verify-12-metadata.json) 记录源码首尾clean与原生集成开启。应用3090通过／1跳过；原生smoke4、真实PTY45、Composer1、Keychain1，以及Debug／Release构建、签名检查和Xcode测试均通过。这是冻结C10上的独立完整运行，不改写前述提交前定向日志身份。

四个macOS driver均记录 `Failed to foreground app; open returned 1`，其后实际driver断言通过；该自动gate不证明前台物理输入或普通窗口视觉交互。nightly resource benchmark因 `VERIFY_FLUTTER_TERMINAL_RUN_NIGHTLY_BENCH!=1` 未运行，不把应用报告的1项skip与该独立夜间步骤混同。签名检查由 `verify_macos_app.sh` 的 `set -e` 必经步骤成功退出支持，不推断公证或证书类别。原字节／哈希与完整边界见 [C10 gate归档索引](../evidence/shared/C10-gates/archive-index.json)。

### C10 正常窗口局部复验（未完成）

`native-c10-windows-1` 于2026-10-10 09:40:47–09:52:36 UTC运行隔离的正常App入口，源码首尾均为干净C10；App PID77686／window31265。操作者经普通菜单与CUA系统事件创建A、B、S三个本地tab，随后用Cmd+T另建Raw4。B仅保留未发送AI草稿，未配置或发送模型；这不构成AI关闭或真实模型场景验收。操作记录是根据CUA响应重建的操作者转录，不是原始AX导出或控制器trace，见 [C10原生局部复验摘要](../evidence/shared/C10-native-partial/review-summary.json)。

已完成的局部检查：S保持自己的未发送命令草稿时，右键非活动A的tab选择关闭，确认仅列A／Session1及其原命令草稿；点Cancel后原草稿保留，再次打开确认后Esc也取消。A与S原稿保留有离散原图支持；A=PID77921／ttys008、B=PID80398／ttys016、S=PID81098／ttys017在所记录进程树中保持一致，不推断两次采样之间没有瞬态进程。预置的草稿副作用文件在结束时不存在，只核对该特定未发送草稿，不是全部PTY写入／网络调用零次证明。

运行随后记录10条Flutter `Failed to update ui::AXTree` 错误；操作者看到AX内容陈旧，后来缩减为一个checkbox，因此停止进一步依赖AX的正常UI验收并以runner `q`退出，exit0。错误首因未确定；不能归因CUA、窗口移动或某一产品改动。Cmd+T原生菜单路径仍有响应，数字切tab／Cmd+W／Cmd+Z及Raw Cmd+I没有观察到预期效果；原生菜单与Flutter组合键路径不同，没有物理键或事件轨迹，相关键盘子项保持未验证，不能据此判定新的产品快捷键缺陷。最初typeText丢失特殊字符、后改用准确paste也是输入路径观察，不能当成根因结论。

录像只覆盖09:41:51.449–09:47:04.065 UTC，采集器记录时长312秒；`SCStreamErrorDomain -3822`使其提前停止并先于操作者Ctrl-C自行exit0，不覆盖整段App运行。A关闭确认09:44:03与取消后原稿09:44:33截图位于该时段；S保留图09:48:02、最终界面图（当时AX查询异常）09:52:01均在视频之外，且这两次截图时App不在前台。不能将独立截图补述为连续录像已覆盖。

第一轮未完成遮罩点击取消、最终确认关闭、AI关闭／旧任务与仅来源变体、分栏右键和首个鼠标／focus报告、12tab／overflow／重排／移动／运行中关闭／待审标记／菜单边界或物理快捷键完整步骤。D2-T11／T14和其他正式场景均不据这次局部观察改为passed；正式记录仍是历史C8的3 passed／61 not_run。

第一轮[独立图像／视频审阅](../evidence/shared/C10-native-partial/independent-review-summary.json)实际查看6张原图和157/8749个不同源帧（106概览＋66局部，重叠15），支持A目标显示、弹窗消失与原稿保留；没有全片逐帧／逐像素审阅，Esc动作仍归操作者记录。最终界面PNG本身不诊断AXTree错误，错误依据launch日志与查询观察。第一轮6张原图与sidecar按原字节保留，视频原件及派生contact sheet留本地。

### 第二次 C10 有界复验（局部补齐，首轮异常未定因）

`native-c10-ax-2` 使用相同干净C10，App PID3809／window31358；启动09:57:37、结束11:58:40 UTC，正常runner `q`退出0。普通UI复核非活动A的关闭确认仅列A；Cancel、Esc及点击遮罩后保留。B仅有未发送idleAI草稿，其关闭确认仅列Session2／task-1和该草稿，Cancel保留；再次明确Close后，离散进程树仅B PID17469消失，A PID3929／ttys008及原命令草稿保留。详见[第二次C10有界复验摘要](../evidence/shared/C10-native-fixed-window/review-summary.json)；操作过程是操作者重建记录，截图／进程树只支持各自采样时点。

第二轮[独立图像／视频审阅](../evidence/shared/C10-native-fixed-window/independent-review-summary.json)实际查看7张原图与53/7508个源帧，支持A草稿确认／取消保留、B idleAI确认／取消保留及明确关闭后A草稿／身份保留的局部结果。Esc与遮罩取消仍仅由操作者转录支持，未用采样视频独立证明。20份源文件哈希未变；7张原图和sidecar按原字节归档，原视频／派生审阅图及私有语义记录留本地。

此轮launch日志AXTree错误为0，但有1条Window move警告；操作者没有拖窗或缩放，7次窗口bounds相同。这只表明有界序列没有复现首轮错误，不能推出首因、修复或“所有测试绿色”。7个截图点的`active_pids`均为空，不主张前台物理输入验证。4次只读既有语义RPC成功属于当前Flutter树观测，不是平台AXTree或首轮失败更新；原dump与调试认证地址保持私有。

录像为11:53:44.035–11:58:00.234 UTC、采集器记录256秒，7个检查点时间都在该区间。文件finalize后1毫秒记录SCStream -3822；与操作者Ctrl-C的精确关系未记录，不能照搬第一轮“提前于请求自行停止”的结论。录像不覆盖09:57开始的整段App生命周期。12tab／overflow／重排／pane移动／待审矩阵、split首个鼠标与focus协议、运行中关闭、旧任务／仅来源变体和物理键仍未完成；不增加正式场景通过，也不把完整verify12或手机C4结果换算成这些步骤通过。

## 手机 cloud 恢复与清理边界

用户已明确授权将本地 cloud 配置和私钥导入独立 `work.ianvs.trail.mobileprd`。本次实际手机仍为 C4 `1c95adcaab32fac64fb08142da7a0eb3b8620b5a`，不是 C9 安装。经 USB 传入后通过正常 App 文件选择器导入并保存；手机配置保活设为30秒、重试3次，本机 cloud 的 interval=0，因此这是有意的手机配置调整。

第一次尝试先连接，随后使用设备工具清理导入目录返回 exit1/error7000；报错后重连并执行只读命令成功，再次重启时出现 onboarding 和空 SSH 列表，配置目录元数据表明文件重建，DeepSeek Keychain 配置仍保留。时序支持设备工具清理范围异常这一候选，不能证明具体删除范围、唯一原因或产品持久化缺陷；退出错误也不等于无副作用。本轮已告知用户并恢复 cloud。

第二次恢复后，先重启验收版确认保存的 cloud 可连接，再只用零字节文件覆盖精确指定的临时导入文件，未再使用目录删除选项。独立只读复核确认唯一同名源从2459变为0字节；`ianvs_profiles.json` 和 `data-api/configuration.json` 的全部已记录元数据前后相同。清理后再次重启，cloud 仍在并可使用保存的私钥连接。只读验证返回 `TRAIL_CLOUD_IMPORT_OK`、工作目录及 `Linux`，成功命令块后 Shell 就绪。

独立 reviewer 实际逐张查看3张原图并核对哈希、两个不同进程的启动回执。原图与设备 JSON 含账号／设备信息，保留私有；只归档[脱敏审阅摘要](../evidence/shared/C4-cloud-restoration/independent-review-summary.json)。单文件逻辑大小为0不代表闪存安全擦除或排除全部未知副本，截图也不证明精确网络／执行次数。未修改本机原私钥。

此前 interval=0 的连接两次出现无远端退出码的 `transport_eof`。30秒保活下的重启连接与只读命令已成功，但后续镜像显示 iPhone 被使用而结束，无法继续观察；镜像中断不能等同于 SSH 断连，也不能据此宣称长时间保活通过。真实模型的完整闭环、Smart三档、软键盘/IME、后台锁屏等仍需另验。实体iPad和外接显示器按用户确认继续记为未验收，不重复询问。

公开E1启动日志使用[明确脱敏派生物](../evidence/shared/E1-native-findings/launch.redacted.log)；[派生说明](../evidence/shared/E1-native-findings/launch-log-redaction.json)保留原件SHA，原始日志未改，未将过期loopback调试认证URI直接发布。
