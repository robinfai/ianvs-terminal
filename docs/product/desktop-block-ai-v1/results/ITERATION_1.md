# 第一轮实现与并行复评

2026-10-10，起点为 `79db5115`。本页保留工作树修复到 C1–C9 的历史过程；C3完整gate、C4生产修复、C5–C8测试／驱动修正与C8实际原生结果分开记账。上一正式归档C8完整gate verify-10已通过，C8组件复采48/48、63PNG和预览构建也通过，正式3passed／61not_run。以下记录不替代64个桌面、48个移动完整场景，也不构成发布结论。

| 问题 | 实际影响 | 本轮处理与证据 |
|---|---|---|
| API 重复操作 ID | 同一命令或按键操作可被模型再次返回并再次写入；参数变化和后续人工操作可能污染原回执 | 按 task 保留首次操作/参数/结果和精确 entry ID；重复只返回原回执，冲突拒绝。12 个专门回归；核心四文件共 75 通过，独立复评未见新增问题 |
| 未知提交时补充要求 | 用户新增约束可能未进入后续模型请求，来源也可能被新目标补全 | 保存为明确尚未发送的记录，冻结原来源；只检查回执不发送，明确继续才采用；预算超限保留原稿 |
| 编辑提案覆盖旧版本 | 原命令文本不能在任务记录中追溯 | 保留旧版本为已撤销，新版本使用独立 entry/revision；保存不执行 |
| 永久未知没有结束出口 | 用户只能反复检查，容易将重连/新任务误当重试 | 结束跟进只冻结旧任务，未知事实和原回执保留；新任务不复制待执行动作 |
| 桌面审阅层与收起语义 | 全局审阅阻挡邻 pane；关闭/Esc 与只读观察不一致 | 审阅局限于当前 pane；收起/Esc 进入观察；批准/继续用 pane epoch 复查 |
| 隐藏移动任务缺生命周期事件 | 主页或其他 tab 下保留的 controller 可能接受晚到模型/审核 | Shell owner 统一向所有保留 controller 分发；新建 controller 同步当前状态。21 项组合回归通过，属于 iOS widget/fake PTY |
| 延迟粘贴跨过 Block 生命周期 | 完成、挂起、失去输入或卸载后，先前 clipboard 回调仍可能发送 | 本地可撤销 sink 复查原输入代际；普通输出刷新保持有效输入。Block/焦点 16 项、Composer 12 项通过 |
| ready/运行输出抢焦点 | 晚到状态可能将焦点从 modal、其他 pane 或窗口移回终端 | 增加原 owner、route、window、generation 检查；正常快速完成仍可恢复原编辑器 |
| 搜索上限不严格且无提示 | 实际可显示 1,050 条，界面把部分结果写成全量匹配数 | 严格 1,000 总量、200 单块预算；显示上限/已显示数量，换查询清除旧提示 |
| 短窗摘要缺执行状态 | 默认 H/3 退化摘要不直接显示退出码 | 显示 Exit 0/255/? 或 Running；保留可访问详情入口。摘要/搜索/既有手机 Reader 共 44 项通过 |
| 构建阶段同步通知 | 关闭分屏/切旧来源时触发 setState during build | 权限撤销仍同步，只有构建期视图通知合并至帧结束；原 3 个 Shell 失败回归转绿，新增环境/销毁与既有焦点共 14 项通过 |
| 触摸板边界不能开启外层滚动 | 内层到底后新手势仍被内层 recognizer 截住；长手势跨 Block 时起点卸载会截断拖动 | 只在手势起点选择滚动归属；活动拖动保留起点，松手释放并继续原生惯性。先红后绿，新增 9 项与既有滚动/手机组合共 40 项通过，独立复评已收拢 |
| 缺桌面活动目标状态栏 | 原 PRD 的“保留状态栏”不能由当前源码证明 | 本轮补展示层，目标不匹配显示核对中；断连/未知可并存；4 项状态/缩放回归通过，7 文件静态分析无问题 |
| 证据 Reader 全局路由 | 阅读同一来源会占用整个窗口，缺显式宽窗检查器 | pane-local Reader 与 600+360 按需检查器已接入，复用原分页/查找/选择；TUI 不 resize、来源冻结和底栏联动回归已通过，焦点和过期回调独立复评已收拢 |
| 必要控件对比度不足 | 默认状态合格，但按钮 hover/focus/pressed、浅色滚动条、选中书签低于目标 | 最小语义 token 修正，四模式 242 个目标色对通过；新旧主题组合 25 项通过，见 [TOKEN_MAP](TOKEN_MAP.md) |
| Reader 行号被缩放裁切 | 2× UI 字号用终端单元宽度预算行号，第一位数字画到裁切区外 | 按实际行号字体和缩放测宽；新组件预览截图先发现，字形约束红测复现；同时去除宿主内重复的标题栏留白 |
| 手势期间 ScrollPosition 被替换 | 窗口 DPR 改变会丢失自定义拖动包装器，后续增量无效，委派外层可能保持拖动状态 | 按 Flutter absorb 生命周期迁移同一拖动对象；取消时查当前外层位置。两类 owner 的真实位置替换先红后绿，滚动文件 13 项通过 |
| 同一 session 的节点切换显示旧 ready | 新 SSH host/context 已出现在底栏，但旧 composer ready 尚未轮询更新 | 当前 mode 核对状态优先，只有新节点协商完成才恢复 ready；真实 ComposerPaneSession 回归先红后绿 |
| 整窗格 Reader 同帧旧 Run 漏口 | 只读层已打开，旧按钮回调仍可能在重建前取得旧 lease 并提交 | 同步撤权与同步保存不可见状态并撤销权限，只按当前 owner 恢复；实际提交计数先红后绿，相邻组合 34 项通过 |
| 完整应用检查暴露旧基线与旧操作路径 | 6 张 macOS 27 截图未含新增底栏，6 个手机测试仍将收起 AI 视为接管输入 | 逐张检查后只更新指定 6 张图片，两文件复验 6 项通过；手机用例先验证观察层零写入，再显式接管，完整文件 30 项通过 |
| Shell 入口超过文件预算 | 新增展示逻辑使入口 1,721 行超过 1,700 行约束 | 将控制器整体销毁归回既有会话展示管理文件，入口降至 1,690 行；清理顺序不变，未提高阈值，架构及观察层组合 28 项通过 |
| 打开 AI 同帧旧 Run 仍可提交 | 只撤销 Raw 输入代际，Composer 的旧回调在重建前仍持写权限 | macOS/iOS 真实 Shell 回归先红后绿；打开 AI 时同步撤销 Composer 权限，界面通知可延后但写权限不延后 |
| TUI 迟到回调接管新任务 | 旧 accepted 操作的 post-frame 回调只检查 mounted，可在切任务后接管新任务；原自动接管也与显式接管合同不符 | 按合同改为原 task/pane/owner 仍有效时的只读观察，人工写入须明确接管；补齐后台或 modal 内新到回执的反向时序红测，10 项 TUI 定向回归通过 |
| 人工未知提交被新节点核对状态遮蔽 | 新 SSH context 的 checking 会掩盖旧 Composer 未决回执 | 未知事实与新节点状态并列；真实提交→未知→节点切换→断连／其他 session 回归，底栏文件 6 项通过 |
| 待审关闭保护缺失 | 现有关闭链只处理来源占用、录制和传输，未说明未审任务丢失后果 | 已补实际 tab/pane 聚合确认、草稿复制与取消保留；录制保存后在 native close 前同步复查目标、提案、草稿、附件和未知操作身份。16 项新增及相关组合共 142 项通过 |
| 隐藏标签缺待审批标记 | 待审状态只显示在当前活动 Session 的 AI 入口，后台任务没有定位提示 | 已按原 session 聚合标记；顶部标签、溢出菜单、侧栏及折叠组汇总可定位原 pane，点击零提交，不被通知抢焦点 |
| 桌面顶栏仍为两行 | 44 高标题栏与 38 高 tab 栏叠加，不符合 D1-R01 单层合同 | 已合并同层，2× 字号按真实文本高度调整；实测布局白区传给原生拖动，缩放窗口先撤销旧区域；5 项 AppKit 原生回归通过 |
| 桌面截图 fixture 使用错误平台分支 | app-surfaces 只设置 ThemeData.platform，默认运行平台仍是 Android；截图中的双层栏和 Ctrl 快捷键不能证明 macOS 分支 | 显式指定 macOS 后重新采集；独立逐张审阅指定 6 组 master/test/diff，单层栏及 Cmd 差异符合预期；不复制到 macOS 26 |
| 侧栏遗漏待审入口 | 仅给顶部标签栏提供待审 scope，切换到侧栏或折叠分组后后台提案没有定位标记 | 两条真实 Shell 红测确认；共用原来源导航补齐侧栏行及汇总入口，回归确认定位原 split pane 且零 PTY 写入／零 Composer 提交 |
| 关闭完成抢走新弹窗焦点 | 录制保存期间用户切 tab 并打开新弹窗，完整或部分关闭完成的 post-frame 会强行聚焦终端 | 两条红测复现；恢复焦点前复查当前 pane、原 focus owner、窗口生命周期、modal 与 Reader；组合回归通过 |
| 确认后的新引用被旧关闭清掉 | 添加 AI 附件不改变 draftRevision，录制保存期间新增的来源可能继承旧关闭确认 | 全部保留任务的不可变附件身份加入关闭快照；确认后新增引用将拒绝旧关闭并继续录制，红测转绿 |

上述数量来自不同时间点和交叉集合，**不能相加为唯一测试数或 PRD 通过数**。最终以代码收拢后的统一完整检查为准。

## 当前日志与证据限制

本地工作日志位于 `build/desktop-prd-v1/iteration-1/`：`root-scope-status.log`（18 通过）、`status-priority.log`（4 通过）、`root-analyze.log`、`block-input-focus-after.log`、`composer-block-focus-after.log`、`block-summary-search-after.log`、`scroll-ownership-before.log`。API 核心日志为 `/private/tmp/ianvs-api-operation-core-tests.log`。这些是未冻结工作树的本地回归记录，不是已归档的候选 C 原生验收附件。

新增 Reader/底栏交互预览 3 组与底栏 5 项共 **8 项通过**，日志 `reader-status-final.log`。`previews/` 的 5 张图片使用仓库固定字体夹具，只证明组件布局；不替代真实 macOS 字形和原生操作。已视觉检查窄窗 2× 行号与浅色并排几何。单独红测日志为 `reader-gutter-before.log` 和 `status-node-before.log`。

文档合同 20 项通过；桌面证据 validator 单元测试 46 项通过，空 manifest 结构检查通过且明确提示 not_run 未验证。没有把校验器通过写成产品场景通过。

macOS 27.0.1 宿主和有线 iOS 27.0.1 iPhone 已识别。未发现可用实体 iPad 或外接显示器。设备可用性本身不支持 IME、触控、VoiceOver、后台存活、完整 API、性能或兼容性通过结论。

完整 gate 的第一轮在静态分析停止：临时主题导出探针被放在会参与分析的目录，以及预览存在未显式处理的 Future。探针已原样移到现有排除目录 `tmp/`，预览改用 `unawaited`；全局严格分析随后通过。第二轮完成 Rust、Go、Dart、终端包及文档等检查，在应用测试以 2,899 通过、1 跳过、13 失败结束。上表已记录这 13 项的原因及定向修复；第二轮没有执行后续 macOS 原生 gate，不能写作完整通过。

第三轮在 Flutter 启动器写 SDK 缓存时被 sandbox 拒绝，未继续到 Dart／应用／macOS 原生检查。后续使用所需权限已完成验收驱动的格式化和严格分析；原始日志 `verify-3.log` 保留，不将这次环境中止记作产品失败或通过。并行复评随后又发现上表的输入、关闭和顶栏缺口，因此待这些改动收拢后再冻结候选并运行完整 gate。

macOS 27 六张新基线的逐图检查、旧新哈希及复验日志在 `build/desktop-prd-v1/iteration-1/golden-review-2026-10-10/REVIEW.md`。其余 91 张基线没有变化。macOS 26 对应场景仍待真实宿主复采，不能将 macOS 27 图片复制过去宣称通过。

## 首个冻结候选的完整检查

实现已保存为 `1c3522c3863fdb34f6060a25cd9d05c58e28fab6`。提交前 1,015 个 Dart 文件格式检查、全局严格分析、生成镜像一致性通过；文档合同 20 项、证据校验器 46 项通过。顶栏拆分后的执行目标 manifest 源码锚点已同步，原禁止项检查保留。

第四轮 `make verify` 在该提交的干净工作树运行，首尾均干净，退出码 **2**。日志 `verify-4.log` 与 `verify-4-metadata.json` 记录了准确提交和时间。Rust／Go／Dart／PTY／两个终端包及文档等前置检查通过；应用测试为 **2,942 通过、1 跳过、4 失败**。失败均来自 `mobile_terminal_modes_test.dart`：macOS 完成 AI 后返回 Blocks 的编辑器未获焦点，以及手机 TUI 的 portrait／landscape／short-dark 三项在明确接管后未恢复 Esc 输入。它们是需要修复的交互回归，没有修改原断言规避；此轮尚未执行后续 macOS App 原生 gate。

已确认异步关闭焦点保护过严：明确接管会暂时清空焦点；菜单关闭后旧 FocusScope 已禁用，焦点会退回 Shell 自身作用域。修复只允许这两种合法过渡，继续保护新编辑框、modal、活动 pane、生命周期和 Reader。`mobile_terminal_modes_test`、`shell_close_protection_test`、`shell_screen_phase2b_test`、`composer_pane_focus_test` 共 **57 项通过**，包含原 4 个失败和 2 项关闭后不得抢走新弹窗焦点的回归；原测试断言未修改。日志为 `focus-regression-tests.log`，单文件格式与严格分析通过。修复将保存为下一候选并重跑完整检查；旧候选日志不改写为新候选证据。

## 第二候选的完整检查

焦点修复保存为 `87dbcefd455e5eebdbeb0d3f4cfccfcb5c5788e3`。第五轮 `make verify` 首尾工作树干净，运行 583 秒，退出码 **2**；准确时间和提交见 `verify-5-metadata.json`。全部前置检查通过，应用测试 **2,946 通过、1 跳过、0 失败**。macOS 原生冒烟 **4 通过**、真实 PTY **45 通过**，随后 Composer 原生用例在 `composer_acceptance_test.dart:266` 设置选区时失败：`TextSelection(baseOffset: 0, extentOffset: 12)` 超出当时文本范围。该轮没有删减功能断言，也没有登记为完整 gate 通过。Keychain、Debug／Release 重建签名和后续 Xcode 测试尚未执行。

原生诊断确认是产品焦点交接缺陷：提交进入 submitting 会先禁用编辑器，焦点退到页面 scope，既有 running 回调已无法识别原来源。修复后原测试继续通过补全、多条命令和滚动步骤，又在 Ctrl+C 后暴露第二边界：运行中的 Block 先卸载，ready 轮询随后才到。当前凭证记录实际持焦点节点、精确 scope 和可见性版本；仅当原节点被禁用或卸载才承认这种退焦，主动离焦、新输入 owner、pane、modal、生命周期及隐藏再显示均撤销旧凭证。未挂载终端不会排队 requestFocus，避免晚挂载抢走新焦点。

新增 **14 项**焦点回归，相关组合 **72/72 通过**；两文件格式、严格分析及独立复评通过。正式 `composer_acceptance_test.dart` 未修改断言，完整原生流程 **1/1 通过**，日志 `composer-c2-fixed-native-2.log`；最初失败及中间失败日志保留。上述结果来自下一候选的工作树，仍须冻结后重跑完整 gate。

本轮并行核对还发现旧手工验收入口 `tool/macos_acceptance.dart` 只隔离了仓库数据和 portable master key，默认 AI 存储及初始登录 Shell 环境仍沿用开发宿主。新增 opt-in 桌面 PRD 入口复用真实启动及运行图，以独立开发文件存储隔离 AI、主密钥、Profile、布局和本地 Shell HOME；不预置模型，不导入个人凭据，也没有任务注入或自动批准接口。复用 Development bundle，原生窗口位置／尺寸仍共用其 UserDefaults；显式配置 ACP 后仍使用既有登录加载器及宿主 HOME，数据隔离不构成系统 Shell 沙箱。现有三个原生 AI 驱动的内存设置和临时 HOME 边界已分别核对。截图辅助程序只识别指定构建路径的新进程；主窗口视频不替代独立 NSAlert、物理输入或真实 DPI 证明。

新入口的真实启动图测试拦住并修正了额外 ProviderScope 绕过 PTY 配置的问题；最终保持单一生产根 Scope，仅合入验收 AI 存储。启动／复用／拒绝无关目录／本地与 SSH 环境／Keychain 零访问及正常资源关闭组合 **5/5 通过**，日志 `manual-fixture-widget-tests-6.log`；Python 启动器合同 **5/5 通过**。中间失败和主动中止日志保留，测试环境与原生产品问题分别记录。

独立核对原生 AI 驱动发现“失败命令 → 修正命令”流程此前没有重新打开修正结果的引用。新增同一次修正的诊断草稿、审阅、真实结果与 Reader 截图节点，并核对 accepted receipt、原生 submissionId、分页来源、返回后的 task／draft／请求及 Block 计数；原失败保持不变。驱动尚待新候选实际运行，新增断言不预先登记为通过。

## 后续执行

滚动、Reader、关闭保护、单层顶栏和待审定位已完成本轮实现及独立复评。新增关闭用例及相关组合日志为 `close-protection-tests.log`（142 通过）；顶栏／侧栏组合为 `unified-chrome-regression-3.log`（65 通过）；原生窗口检查为 `unified-chrome-native.log`（5 通过）。逐图审阅范围见 `unified-chrome-visual-review.md`；这些数量仍有交叉，不能相加当作唯一覆盖数。

standalone 435 个生成文件已同步。原生 Composer 修复已进入 C3 并通过完整 gate；按 [桌面逐项表](DESKTOP_COMPARISON.md) 和 [移动逐项表](MOBILE_COMPARISON.md) 继续补原生／物理／真实模型证据。源码再次变化则重跑影响面，旧移动 C1/C3 证据身份保持不变。


## 第三候选的完整检查与支撑探针

C3 为 `7e9f0dd8e7bd825c655ceb80d817d5fe214337bd`。第六轮 `make verify` 在严格分析阶段停止，退出码 2：两个临时原生诊断 Dart 源码副本被留在会参与全局分析的 `build/` 目录，产生 50 条诊断。原副本移到现有排除目录 `tmp/desktop-prd-v1/iteration-1/diagnostic-sources/`，迁移路径与 SHA 记录在 `verify-6-probe-relocation.json`；没有修改候选源码。全局严格分析随后通过，历史日志保留。

第七轮在同一 C3 干净工作树运行，2026-10-10 05:00:53–05:13:10 UTC，737 秒，退出码 **0**，首尾工作树干净。Rust／Go／Dart 前置检查、PTY 39、canonical terminal 1,013（1 跳过）、standalone 1,057（1 跳过）、应用 2,965（1 跳过）通过；原生冒烟 4、真实 PTY 45、Composer 1、Keychain 1 通过；Debug／Release 构建、签名检查与 Xcode 测试通过。完整原始日志及元数据见 [C3 支撑证据](C3_GATE_EVIDENCE.md)。不同集合不能相加为产品场景数。

后续 C3 支撑检查均首尾源码干净：回环 OpenSSH 的 zsh／bash emacs、vi 及各自 local→SSH 六组全部通过，含原生 API 的受控多跳和父节点恢复；Bash 使用 5.3.20。真实 ACP 2.1.1 连接返回 OK，完成回执确认模型 `gpt-5.6-sol`；cancel 后 session/load 使用同一 session ID，记忆短语检查通过。SSH 未运行 GUI，ACP 是协议探针，不计完整产品场景通过。

历史C3独立Trail PRD Profile包`physical-profile.MIDSac`构建成功，签名／描述文件／device-only Keychain校验通过；该构建记录当时尚未安装。当时iPhone枚举tunnel unavailable并询问USB重连。后续C4安装与真实设置连接smoke另列，不能改写C3原记录。

历史`native-c3-workspace-1`已采部分完整窗口原图，但录屏辅助程序在AppKit初始化前调用图形接口而退出。修复后单独5秒录制诊断成功，不补作原流程录像。后来工具明确报告Mac锁屏，UI停在Reader，已仅终止本次自有App，exit79／capture false。后续还发现并修正了driver陈旧Reader定位路径，因此不能把Reader停住全部归因锁屏；该不完整运行不判产品通过，也不从现象独断产品根因。

实体iPad、外接显示器按用户指示保持未验收，不重复询问。Mac／iPhone连接条件后来已恢复，当前没有新必需产品范围决策；最新结果和剩余步骤见下文与[当前交付结论](FINAL_REVIEW.md)。

## 第四候选的组件与输入反馈收拢

C4 `1c95adcaab32fac64fb08142da7a0eb3b8620b5a` 补齐九类已确认缺口。下表定向日志多数来自冻结前工作树，最终C4冻结后组件册证据另列；测试集合存在交叉，不可相加作唯一测试数／完整场景数。

| # | 修复／补充及实际行为 | 主要源码／回归入口 | 已核对的局部证据与限制 |
|---|---|---|---|
| 1 | 高对比预览接线：Composer、Command Blocks 及对应捕获测试将真实 `highContrast` 传给 `buildIanvsTerminalTheme`，与 MediaQuery 一致；检查生产 outline、onSurfaceVariant、Composer 边框和 TerminalViewport 颜色，不只检查 flag。 | `example/lib/ui/previews/{composer_preview,command_blocks_preview}.dart`；`example/test/ui/terminal_preview_theme_test.dart`；`example/test/design/{composer_redesign_capture,command_blocks_capture}_test.dart` | `preview-theme-after.log`：3 文件组合 142 项通过；`preview-theme-analyze-2.log`：无问题。`preview-theme-before-2.log` 保留 4 通过／18 失败的原记录；不可将失败总数冒充纯 palette 缺陷数。没有改生产全局主题或 golden 容差。 |
| 2 | AI 预览收起合同：旧预览把 onClose 接到 takeOver，收起会撤销待审任务；现进入只读观察预览，返回使用同一个 task、提案和草稿，观察中的 Block 重录仅准备草稿。此修正属于预览接线，生产 Shell 的只读观察合同先前已修。 | `example/lib/ui/previews/{ai_observation_preview,terminal_ai_workspace_preview,mobile_prd_component_previews}.dart`；`example/test/ai/ai_workspace_preview_test.dart` | `preview-focus-collapse-tests-1.log`：收起 3 项与标签焦点 8 项合计 11 通过；检查 pending、transcript、draft、taskId 保留和 `takenOver=false`。内存 fixture，无真实模型／PTY。 |
| 3 | 预览 Block／Reader 字体来源：共享 `TerminalAiComponentFixture` 和只读观察预览将 Composer 的真实 resultStyle 字体及 fallback 传给 TerminalFontConfig，避免状态图中的终端文本沿用 Ahem 条块；捕获主题完整使用固定字体，关闭 debug banner。 | `example/lib/ui/previews/mobile_prd_component_previews.dart:344`、`ai_observation_preview.dart`；状态册捕获测试与 `visual_capture_fonts.dart` | C4 的 63 图 manifest 明确 `fonts=repository and pinned Flutter SDK assets`。这是组件捕获字体修正，**不是系统字体、Core Text 字形、真实 DPI 或原生 ANSI 对比验收**。 |
| 4 | 六类真实组件状态册：Block、来源 Chip、候选、主按钮、标签、分割条；事实菜单只更改 controller 数据，hover／pressed／focus 由真实 pointer／keyboard 操作产生；支持浅深／高对比、2×、窄 pane、减少动画及重置局部 fixture。 | 新 `example/lib/ui/previews/desktop_component_states_preview.dart`、`example/lib/features/shell/shell_screen_preview_adapter.dart`；`example/test/ui/desktop_component_states_preview_test.dart` | C4 冻结后 48 项通过、63 图；状态册入口原生构建成功。目录不实例化终端 runtime，无真实模型／PTY。官方 web Widget Previewer 因现有原生依赖图编译失败，改为明确的 macOS 原生预览入口，不宣称支持 web Preview。 |
| 5 | 分割条键盘与可访问动作：Tab 可到达；仅裸轴向方向键按 10px 调整，反轴／组合键不吞；VoiceOver increase／decrease 复用现有 ratio／cell 约束，公布当前和增减后一位小数百分比；边界／无空间有中英原因、动作失效；真实 2×2 外层 divider 可调且不改变内层／活动 pane／PTY 写入。焦点可见且减少动画响应 MediaQuery。 | `example/lib/features/shell/shell_screen_command_menu.dart`、`shell_screen_state_terminal_layout.dart`；`example/test/ui/pane_divider_keyboard_test.dart` | `pane-divider-keyboard-before.log`：2 通过／12 失败；`pane-divider-keyboard-final-2.log`：14 定向＋13 架构合计 27 通过；`pane-divider-analyze-final.log`：无问题。Semantics 动作不等于实际 VoiceOver/FKA 验收。 |
| 6 | 桌面标签悬停下焦点被遮：side 的 focused 优先于 hovered，焦点边框不被 hover 状态覆盖；选中／未选中均可辨，聚焦不激活，Enter 只激活一次。 | `example/lib/features/shell/shell_screen_chrome.dart`；`example/test/ui/tab_focus_indicator_test.dart` | `preview-focus-collapse-tests-1.log` 中标签 8 项（浅深×高对比×选中）全部通过；与收起 3 项共 11。没有新增窗口／tab 架构或跨窗口能力。 |
| 7 | Block 标题状态与 Enter 目标：opaque Container 遮住 ink，导致 hover／pressed／focus 不可见；近端透明 Material 加前景焦点边框修复。按下不提前选中，release 才选择；标题获得焦点时裸 Enter 先选择该 Block，防止重录旧 active Block；随后列表 Enter 保留既有重录合同。短摘要和完整标题共用。 | `packages/ianvs_terminal/lib/src/terminal/command_blocks_view.dart`；`example/test/ui/command_block_title_states_test.dart` | `block-title-states-before.log`：14 失败；`block-title-states-final-2.log`：16 通过，包含真实像素、≥3:1 焦点、hover／press 文字≥4.5:1、取消按压与 full／summary Enter。`block-title-analyze-final.log` 无问题。原 package 82 项通过的组合日志整体 exit 1，原因是另 4 项主按钮新测试等待持续 spinner 超时；不能把 `block-title-package-regression.log` 整份称为绿色。 |
| 8 | 主按钮禁用原因未进入语义节点：父 Dock Tooltip 会覆盖仅存在 Tooltip 的解释；将说明合并至 FilledButton 自身 child Semantics，Tooltip `excludeFromSemantics=true`，保持 enabled／action 状态和零操作合同。 | `packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart:1125`；`packages/ianvs_terminal/test/composer/composer_primary_semantics_test.dart` | `composer-primary-semantics-final.log` 及最终 `composer-primary-focus-semantics.log`：EN／ZH×macOS／iOS 4 项通过。测试从空稿／submitting 禁用原因到 ready 及语义单次点击；仅针对持续 spinner 使用有界 pump，没有放松零写入／一次提交断言。 |
| 9 | 主按钮 hover 后键盘焦点仍不可辨：Material side 在 ink 下且同主色，真实边缘对 fill 为 1:1。主按钮局部 backgroundBuilder 的前景双色内描边覆盖 ink：outer primary 2px、inner onPrimary 净 2／3px；保持原 clip、尺寸、focus node、禁用语义和提交权限。 | `packages/ianvs_terminal/lib/src/composer/terminal_composer_view.dart:1153`；`example/test/ui/composer_primary_focus_test.dart` | `composer-primary-focus-red.log`：四主题全部失败；`composer-primary-focus-final.log`：4 新像素＋12 既有 action contrast 合计 16 通过；最终语义 4 项另通过。真实 fractional top=316.5 下验证 hover→键盘聚焦→离焦、内边对 fill／外边对 Dock 均≥3:1、bounds 稳定和提交 0→1；未改采样点或降低阈值。 |


冻结C4的 `component-states-c4-1/capture-run.json`／`capture.log` 记录48项通过，`captures/capture-manifest.json`记录63PNG；`native-build-run.json`／`native-build.log`记录macOS预览入口构建通过，两次首尾同一干净C4。未launch、无真实PTY／模型。实际测试DPR1、PNG导出2×、字体为仓库和固定SDK资产；六组件×五环境默认图加部分交互状态，不是所有主题×状态的笛卡尔全矩阵。相关代表原图独立复评通过，但不替系统字体、IME、DPI或VoiceOver。镜像由生成器统一同步，未手改。

同一C4的完整`make verify`第八轮在2026-10-10 06:32:54–06:35:12 UTC运行138秒，首尾clean、exit2。新安装的Homebrew Bash5.3首次让测试进入系统Bash3.2此前跳过的Composer分支，`legacy-deferred-string`中调用本机不存在的`/bin/false`得到127而非预期1；`/bin/true`同样不存在。这是测试外部命令路径假设，不改生产返回码或削弱断言。日志与metadata保留至 `evidence/shared/C4-gates/`。

物理iPhone上的C4独立`work.ianvs.trail.mobileprd`随后安装并启动，使用用户授权端点完成DeepSeek真实连接smoke。首次请求与系统无线权限提示相遇，明确重试后UI显示成功；不把首次请求写成完成。保存的Manual配置保留，Smart／三档仅看设置草稿后取消，复开仍Manual，未测试Smart实际执行；配置标签`deepseek-flash`不代表已核对返回模型。该次观察SSH列表空、未执行、未读取／导入私钥。在这份历史摘要记录时，用户已授权导入本机cloud，USB已恢复但镜像尚待解锁，私钥未复制、SSH待测；后续恢复成功见文末与C9–C10跟进记录。截图仅在镜像会话中审阅，不是正式归档原图，`acceptance_passed=false`，详见 `evidence/shared/C4-gates/ui-followup-summary.json`。C3构建未安装的历史状态不覆盖。

## C5–C7 测试夹具与原生采集诊断

C5 `c34e3a46`只修Rust测试外部探针为`/bin/sh -c 'exit 1/0/7'`及生成测试镜像，保留所有prompt style、单次事件、submission／accepted／重新安装断言；并修原生Reader陈旧定位。定向红测、绿测和独立复评保留，`bash-preexec-fixture-result.json`记录core suite exit0、1,018通过／6忽略，日志为`bash-preexec-fixture-core-suite.log`。没有生产Rust变化，不把这一局部工作树suite称为C4完整gate绿。

C6 `11c6fd29`在D06五个静态点加入带PID的native截图握手与有界host捕获，不在silent／stream时间敏感检查点停留。`native-c6-workspace-1`于D12获批vim退出后仍未回只读；已记录sendKeys accepted、shell ready／alt false，但缺当时lifecycle／focus／route证据。launcher报foreground失败不足以证明当时不在前台，root运行中未主动调用CUA；不能据此断定后台或生产owner竞态，更未改生产门禁绕过。

C7 `7c16d5dff0c61842ac399baddf6380ea46bf22f8`只在driver增加D01实际前台握手和D12owner／lifecycle诊断。确切PID前台及D12 resumed／AI task focus／active／route／原target alt均成立，全部功能断言到result；但测试末原框架报`A SemanticsHandle was active`，整体失败，不登记通过。该次开头有CUA AX读取／raise；SDK的AX→platform semantics→额外句柄路径支持假设，但C7未记录语义起终状态，因此不能写成已实证CUA因果，也没有重设／关闭语义校验。

## 第八候选原生主链与待收拢 gate

C8 `19001573d9974c510e1e4cbcfeb01c94368ea157`只修改同一验收driver：D01在导出widgetPNG前完成native握手；新增只读semantics起终观测；result写出后保持App挂载，有界等待同PID／recorded／exit0的录像结束回执。host在result后继续真实录制约1.4秒再正常停止，原media_end严格区间门禁保留。C5–C8相对C4仅3个test文件变化（driver、canonical Rust测试与其镜像），不改生产owner／生命周期／semantics。

`native-c8-workspace-1`于2026-10-10 07:17:08–07:18:29 UTC运行80秒，driver exit0、首尾clean。`native-test.private.log`实际到`(tearDownAll)`与`All tests passed!`；53.658333秒H.264原生窗口录像，74周期原生图、6精确原生点和42widget支撑图分别记录，capture readable／complete／strict interval均true。133项artifact SHA独立复核全部一致；完整原图角色／视频由独立视觉记录核对，hash／解码不代替画面评审。

实际窗口PID91804／window28413，1728×1084 points、3456×2168 pixels。D01在recording_started且同PID active／frontmost后才放行；launcher仍有`open returned1`警告，不谎称启动器成功。D12前置resumed／AI task owner／route与原target alt全匹配，45×203 TUI网格保持，批准退出后只读、显式接管才输入、手动回Blocks均通过。语义观测platform disabled／handle1→1，此1是测试框架自有句柄，正常teardown后原检查通过；没有运行中CUA AX。

严格区间复核：recording_started `07:17:35.085Z` ≤ 首driverPNG `07:17:37.604965Z`；末必要事件result mtime `07:18:27.324355Z` ≤ 保守media_end `07:18:28.085Z`，stop `07:18:28.743270Z`、finished `07:18:28.762Z`和recorded ack随后到达。首周期原图早于录像仅属额外图，不声称所有74图都在视频内。`native_command_count=1`只计首次编辑命令的匹配Block，不是整段只有一条命令或一次write；stream保持语义锚点但前后scroll offset差2px，不宣称像素完全不变。

模型为确定性本地HTTP，PTY为真实本地Shell，输入为WidgetTester；vim由runtime API准备。失败→诊断→独立修正→引用保留原失败，Reader选择／过滤、慢命令暂停恢复、来源冻结／认证设置恢复是实际子集；不能推成物理IME／触摸板、真实API／ACP、多pane、密码或unknown故障矩阵已验。

第九轮make verify在07:21:14–07:22:26 UTC、72秒、首尾clean、exit2，原因是SDK cache沙箱写权限，保留为环境中止。第十轮使用所需权限，在同一C8干净源码上于2026-10-10 07:23:24–07:38:10 UTC完整执行886秒，**exit0、源码首尾clean**。应用3,065通过／1跳过；macOS原生smoke4、真实PTY45、Composer1、Keychain1通过；Debug／Release构建、签名与Xcode测试通过。原始日志与metadata归档至 `evidence/shared/C8-gates/`，这些是本次实际结果，未抄C3计数；不同集合不可相加为完整场景数。C8组件随后在同一干净候选重采，2026-10-10 07:39:24–07:39:41 UTC，48/48通过、63PNG；07:40:23–07:40:38 UTC的macOS Debug预览入口构建exit0。两次首尾clean／source unchanged、未launch／无物理设备验收。组件归档 `evidence/shared/C8-component-states/` 的71项列明文件hash独立复核一致；AI独立查看4/63代表原图无新增阻断，不声称全部63张人工逐图审阅。DPR1／PNG导出2×、固定字体与无PTY／模型边界保持，C4图保留历史身份。

本次原生材料归档目录为 `evidence/shared/C8-native-workspace-1/`。该次workspace运行凭真实原生步骤、原图／录像、回执／来源和独立视觉审阅支持D3-T05／D4-T01两项；随后D1-T01补验通过，当前合计3/64 passed、61项not_run；归档metadata／文件合同校验PASS，未宣称完整阶段gate通过。整体继续`implemented_unverified`；iPad／外接屏暂无设备明确未验收，其余可执行工作继续，不把环境缺口写成范围删除或通过。

## C8 正常 UI 双标签页补验

同一C8另经 `tools/desktop_prd/run_manual.py` 从隔离配置启动正常产品入口，不使用测试控制器注入任务、配置或批准。两页通过正常菜单显式改为 Blocks。进入／收起AI、切页及明确接管后，命令草稿与各页AI草稿均恢复；A=PID29364／ttys014、B=PID32038／ttys016，BEFORE／AFTER的marker、PID、PPID及PTY均一致；数字Session1／2由实际底栏AX响应事后逐字转录，未把⌘快捷键当Session ID。14张原图及五个二进制哈希经独立复核，启动和结束时源码均为干净C8，正常q退出0。见[D1-T01结果](D1.md)和`evidence/shared/C8-native-tabs-1/`。

D1-T01按记录的显式Blocks前提登记通过；不宣称新安装默认Blocks。部分截图时App不在前台；readonly探测只记录无可见echo，不作为输入门禁强证明；进程树是离散采样，不证明采样之间绝无瞬态进程。未配置／发送模型，CUA原生事件不等于物理输入。当前正式计数3passed／61not_run，整体仍implemented_unverified。


## C9 原生发现后的修复与手机恢复

当前实现为 **C10 `2d18e608c2a1149a093451b5246cb370de0167c3`**。C9补齐草稿关闭保护、右键输入归属、DPR变化和旧菜单目标；其完整verify11发现两项鼠标／焦点协议回归，原失败保留。C10在实际pointer处理前激活目标，并仅为精确失焦系统报告保留独立权限；原103项界面测试、相关297项和canonical165项通过，集合有重叠不累加。独立复评未见阻断，完整 [verify12](../evidence/shared/C10-gates/verify-12.log) 已 exit0（792秒、源码首尾clean；[metadata](../evidence/shared/C10-gates/verify-12-metadata.json)），应用3090通过／1跳过，原生smoke4／真实PTY45／Composer1／Keychain1及Debug／Release／签名检查／Xcode通过，首次正常UI复验因AX陈旧和提前结束录屏仅留局部观察；第二次有界复验补做遮罩取消及idleAI取消／明确关闭，保留A，未复现AXTree错误，但首轮原因仍未定且没有新增正式场景通过。详见 [C9–C10本轮记录](C9_FOLLOWUP.md)。以下C8完整gate／3个正式场景保持历史身份，不直接改记为C10通过。

本轮另运行 `native-c10-windows-1`，源码首尾clean、runner正常q退出0；仅完成非活动A关闭确认仅列A，以及Cancel／Esc保留命令草稿、A／S与三个Shell PID／TTY离散保留的局部核对。10条AXTree错误后内容陈旧，首因未确定，不归因CUA或窗口移动。Cmd+T有响应但Flutter组合键未确认；312秒录像在09:47:04因SCStream -3822提前结束，晚于此时的S保留和最终界面图不能当作录像内证据。最终关闭、AI／分栏／12tab／重排／物理键完整流程未做，本轮没有新增formal pass。原记录边界见[C10原生局部复验摘要](../evidence/shared/C10-native-partial/review-summary.json)及[C9–C10本轮记录](C9_FOLLOWUP.md)。

第二次 `native-c10-ax-2` 在同一干净C10、固定窗口有界重做A关闭Cancel／Esc／遮罩取消，并补B未发送idleAI草稿的取消／明确关闭：B PID17469移除，A PID3929／ttys008／原命令草稿保留。0条AXTree错误仅是本次序列结果，1条Window move警告仍存在；不能抹除首轮失败或归因移动。7个截图点均非前台；录像11:53:44–11:58:00约256秒包含各检查点但非整段App运行，finalize与SCStream停止／Ctrl-C因果未定。4次只读当前语义RPC不等于平台AXTree失败复现。完整12tab／split／物理键等仍未验，详见[第二次C10有界复验摘要](../evidence/shared/C10-native-fixed-window/review-summary.json)。

手机后续恢复结果仍属于 **C4**：独立 `work.ianvs.trail.mobileprd` 已完成用户授权的 cloud 配置与私钥导入，手机保活设为30秒／3次。第一次目录清理报错后出现配置重建，已如实告知并恢复；第二次仅覆盖指定临时单文件，独立核对2459→0字节、两份配置元数据未变，清理前后两次重启均可使用保存的cloud连接，后续只读命令成功。三张原图与设备日志保留私有，公开[脱敏审阅摘要](../evidence/shared/C4-cloud-restoration/independent-review-summary.json)。镜像随后因iPhone被使用而结束，长时保活与完整真实模型／Smart／移动PRD仍未验；不把镜像结束当SSH断连。DeepSeek设置继续保留，原连接测试和Manual/Smart查看历史见原摘要。实体iPad、外接显示器按用户确认保持未验收。
