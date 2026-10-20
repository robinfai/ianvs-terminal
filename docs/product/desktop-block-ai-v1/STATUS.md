# 桌面 Block × AI 实施状态

当前实现为 **C10 `2d18e608c2a1149a093451b5246cb370de0167c3`**。C9补齐草稿关闭保护、右键输入归属、DPR变化和旧菜单目标；其完整verify11发现两项鼠标／焦点协议回归，原失败保留。C10在实际pointer处理前激活目标，并仅为精确失焦系统报告保留独立权限；原103项界面测试、相关297项和canonical165项通过，集合有重叠不累加。独立复评未见阻断，完整 [verify12](evidence/shared/C10-gates/verify-12.log) 已 exit0（792秒、源码首尾clean；[metadata](evidence/shared/C10-gates/verify-12-metadata.json)），应用3090通过／1跳过，原生smoke4／真实PTY45／Composer1／Keychain1及Debug／Release／签名检查／Xcode通过，首次正常UI复验因AX陈旧和提前结束录屏仅留局部观察；第二次有界复验补做遮罩取消及idleAI取消／明确关闭，保留A，未复现AXTree错误，但首轮原因仍未定且没有新增正式场景通过。详见 [C9–C10本轮记录](results/C9_FOLLOWUP.md)。以下C8完整gate／3个正式场景保持历史身份，不直接改记为C10通过。

[C10原生局部复验摘要](evidence/shared/C10-native-partial/review-summary.json)记录A关闭确认仅列A、Cancel／Esc保留草稿及离散PID／TTY保留。10条AXTree错误后自动化不可可靠继续；312秒录像因SCStream -3822提前结束，后两张支撑图不在视频内。未完成最终关闭、AI／split／12tab／重排／物理快捷键完整步骤，不增加formal pass。

[第二次C10有界复验摘要](evidence/shared/C10-native-fixed-window/review-summary.json)另记录A遮罩取消、B未发送idleAI草稿的取消与明确关闭，只移除B并保留A。该次0条AXTree错误、1条窗口移动警告，首轮原因未定；7个截图点均非前台。256秒录像包含这些检查点但不覆盖全程，SCStream停止与Ctrl-C关系未记录。12tab／重排／split／运行中关闭／物理键等完整用例仍未完成。

核对日期：2026-10-10。整体状态：`implemented_unverified`。v1.1 交互修订见 [16_REVISION_1_1](16_REVISION_1_1.md)。本轮从 `79db5115d1e6c69ac62116f19fdfb2b102724df5` 开始迭代；上一正式归档候选 **C8 = `19001573d9974c510e1e4cbcfeb01c94368ea157`**。C4 的生产修复已保留；C5–C8 只修改 Rust 测试夹具／生成测试镜像和原生验收驱动，没有修改生产 owner、生命周期或终端返回码来获得绿色验收。

C8 的 `native-c8-workspace-1` 已实际完成：driver exit 0，源码首尾干净，功能和原框架收尾断言通过，原生录像／截图完整且严格时段门禁为 true。真实本地 Shell、Block 与回执、失败→诊断→修正→引用、Reader、只读观察和 vim 子集都有本次原生动作；模型是本地确定性 HTTP fixture，输入由 WidgetTester 驱动，不是物理输入或真实模型完整验收。支撑记录已归档至 `evidence/shared/C8-native-workspace-1/`。

另以正常产品 UI 完成 [D1-T01 双标签页检查](results/D1.md)：两页显式选择 Blocks，进入／返回 AI、切页和明确接管后，原命令草稿、AI 草稿及 Shell PID／PTY／marker 保留。14 张原图已独立审阅，App PID29146／window28828，归档 `evidence/shared/C8-native-tabs-1/`。未配置或调用模型；部分截图时窗口不在前台，进程树仅离散采样，辅助只读输入探测不作为门禁强证明。

**C8 完整 `make verify` 已通过。** `verify-10` 在 2026-10-10 07:23:24–07:38:10 UTC 运行 886 秒，exit 0、源码首尾干净；应用 3,065 通过／1 跳过，原生冒烟 4、真实 PTY 45、Composer 1、Keychain 1 通过，Debug／Release 构建、签名与 Xcode 测试通过。原日志／metadata 归档至 `evidence/shared/C8-gates/`。前次 `verify-9` 的 SDK cache 沙箱权限中止保留为 exit 2 历史；C8 组件复采也已完成：48/48 测试、63 PNG，macOS Debug 预览入口构建成功，两次首尾 clean／source unchanged、未启动预览App；独立复核4/63代表图无新增阻断。详见 `evidence/shared/C8-component-states/`，不挪用 C4 PNG。

| 阶段 | 状态 | 完整场景正式登记 | 当前工作 |
|---|---|---|---|
| D1 | in_progress | 1/16（D1-T01） | 输入权限、补充要求、编辑版本、未知出口、当前 pane 审阅和关闭保护已修复；C8原生主链通过，真实API／ACP及目标变化完整矩阵仍待 |
| D2 | in_progress | 0/16 | 焦点、滚动、Reader、待审导航、单层顶栏和分割条键盘路径已有回归；实际拖窗、多pane组合、真实IME／键鼠仍待 |
| D3 | in_progress | 1/16（D3-T05） | C8内容分层原生证据已归档；同候选六组件48项／63PNG与预览构建已完成，4张代表图独立复核；完整主题／状态／本地化／原生辅助技术矩阵未齐 |
| D4 | in_progress | 1/16（D4-T01） | C8真实App主链、完整录像与同候选完整gate通过并归档；真实模型、物理输入、性能和升级回滚仍需补齐 |

正式 manifest 登记 **3/64 `passed`（D1-T01／D3-T05／D4-T01）与61/64 `not_run`**。合并后 metadata 校验及文档合同测试 20/20 通过；[最终门禁](evidence/shared/C8-documentation-check/final-gate.log)实际 exit 1，仍有 65 项未满足（4 阶段、61 场景），四阶段继续 in_progress。阶段进度、构建或局部回归均不替代 manifest 结果。源包 PACK_QA、reader 和 qa 目录只说明交付包自身检查，不说明产品通过。

历史 C3 `7e9f0dd8e7bd825c655ceb80d817d5fe214337bd` 的 `verify-7` 完整通过：exit 0、源码首尾干净；应用 2,965 通过／1 跳过，macOS 原生冒烟 4、真实 PTY 45、Composer 1、Keychain 1，Debug／Release 构建、签名和 Xcode 测试通过。C3 的 SSH 六组 native API（含受控多跳和父节点恢复）、ACP 真实返回模型及 cancel/load 记忆恢复也通过，见 [C3 支撑证据](results/C3_GATE_EVIDENCE.md)。它们保留历史身份，不补作 C8 完整场景。

C3 workspace 曾有录屏初始化错误，后来明确锁屏并停在 Reader，exit79／采集不完整；后续还修正了驱动中陈旧的 Reader 定位，因此不能把停住全部归因于锁屏。C6 缺 D12 当时的前台／焦点记录，无法确定未回只读的原因；C7 功能链完成但最终语义句柄校验失败。C8 增加只读诊断和采集首尾握手、不在运行中触发 CUA AX，原断言通过；没有删去语义检查或改生产权限。原失败／中止记录保留，详见 [第一轮记录](results/ITERATION_1.md)。

手机当前实际结果仍属于 **C4**：独立 `work.ianvs.trail.mobileprd` 已完成用户授权的 cloud 配置与私钥导入，手机保活设为30秒／3次。第一次目录清理报错后出现配置重建，已如实告知并恢复；第二次仅覆盖指定临时单文件，独立核对2459→0字节、两份配置元数据未变，清理前后两次重启均可使用保存的cloud连接，后续只读命令成功。三张原图与设备日志保留私有，公开[脱敏审阅摘要](evidence/shared/C4-cloud-restoration/independent-review-summary.json)。镜像随后因iPhone被使用而结束，长时保活与完整真实模型／Smart／移动PRD仍未验；不把镜像结束当SSH断连。DeepSeek设置继续保留，原连接测试和Manual/Smart查看历史见原摘要。实体iPad、外接显示器按用户确认保持未验收。

- [当前交付结论与待验收边界](results/FINAL_REVIEW.md)
- [基线与证据身份](results/BASELINE.md)
- [跨端需求／实现／证据对照](results/CROSS_PLATFORM_REVIEW.md)
- [桌面 64 条逐项对照](results/DESKTOP_COMPARISON.md)
- [移动 49 条逐项对照](results/MOBILE_COMPARISON.md)
- [第一轮修复与验证](results/ITERATION_1.md)
- [平台与环境台账](results/PLATFORM_MATRIX.md)
- [主题映射与对比度](results/TOKEN_MAP.md)
- [本轮决策](results/DECISIONS.md)
- [验收清单](plan.json) 与 [证据 manifest](evidence/manifest.json)


macOS 是主交付平台；Linux／Windows 依既有宿主分别记录能力与缺口。本轮没有增加 Android、远程 ACP 或跨进程聊天恢复。已约定范围没有新的必需产品决策；待办是完整验收、实际环境与可审查证据收拢。
