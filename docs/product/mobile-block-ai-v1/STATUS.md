# 移动端 Block × AI 实施状态

PRD v1.1；核对日期 2026-10-08。实现已冻结为 C `fe1556fc99af6ecca45caf7780604c9f8e541bd9`。本轮发现的输入阻塞、剩余 split tab 关闭、窄窗口布局、只读观察焦点、ACP 环境边界和 macOS 增量打包签名问题已修复并通过回归。精确 clean C 的完整 `make verify` 已 exit 0；独立物理 profile App 构建及严格签名校验通过，尚未安装或启动。正式 After 的 42 个 widget 捕获与原生 App 烟测已通过，49 张原图和原始视频已按下述有限范围审阅；Before 101 份、After 103 份公开白名单文件已同 hash 归档。manifest 已通过结构／完整性校验，完整 PRD 验收尚未完成。

After 原图审阅新增 P3 文案问题 PRD-019：单来源英文显示 `1 sources`，12 张英文 AI widget 图均可见，尚未修复，core_flow=false。保留冻结 C 和原始截图，不宣称全部发现均已修复。

- 原始压缩包 SHA-256：`ba7912453c8a6d0de0fd30b8d4ca138204627e06d1e205a1b2b6e489d16d897e`
- PRD 编写基线：`763dc166bb1e56d6d50ed3379b57f366c9ca06b7`
- 保留此前修复的生产基线：`29134363aecc20713f9f53e1c9a6c395ebf9ef2e`
- 最终 implementation commit C：`fe1556fc99af6ecca45caf7780604c9f8e541bd9`
- 实现 C 包含生产代码、回归测试、工具和镜像；本次证据文档提交 E 仅含文档与证据，不修改产品或 harness。

| 阶段 | 状态 | 完整用例通过 | 仍需完成 |
|---|---|---|---|
| S1 | in_progress | 0/12 | 完整用例路径及对应行为／原图／连续证据；已有四项烟测子步骤 |
| S2 | in_progress | 0/12 | C 的键盘、Reader、横竖屏及 iPad/桌面证据 |
| S3 | in_progress | 0/10 | 完整状态矩阵与设计对照；已有 42 张 widget 图审阅 |
| S4 | in_progress | 0/14 | 真机、真实 API/IME、性能、兼容与公开构建证据 |

冻结前的诊断检查中，265 个 example 测试文件首轮为 2747 通过、1 跳过、20 失败。之后修复并复跑相关范围：Reader/手机布局/observer 64 项、split tab 关闭 2 项、ACP 边界与设置等 63 项、canonical Reader 63 项、Composer golden 复验 9 项均通过；ACP 冗余空值断言清理后再复核 22 项通过。这些范围有重叠，不累加成唯一用例数。

原生修复先复现不查询 Composer 时普通键盘输入停滞，再通过 zsh hooks 7 项、Composer integration 8 项、bridge 单测 5 项及 session 526 项。最终格式检查覆盖 984 个文件、零变化；整仓静态分析无问题，canonical/core 镜像检查通过。上述为诊断与修复回归。旧 C `649c7769` 的完整 verify 随后通过 Rust、Go、Flutter 各前置门槛，example 全量 2776 通过、1 跳过；整条命令仍以 exit 2 失败，因为 macOS smoke 的旧语义断言遗漏已有 hasTapAction。补齐该断言并保留原状态要求后，macOS smoke 4、真实 PTY 45、Composer 1、Keychain 1 项通过；该断言遗漏不计为新增产品缺陷。

随后真实 Debug 增量构建发现外层 App 签名仍封存旧 App.framework。现已在 Xcode project 中声明四个 framework 与 Data API 的真实输出，修复签名依赖，未手动补签或修改 SDK，永久 gate 已加入第二次 Debug 检查。新 C 的完整 verify 于 2026-10-08 15:00:37–15:13:48 UTC 执行完成，exit 0，开始与结束均为 clean C，macOS 未跳过；包括 smoke 4、真实 PTY 45、Composer 1、Keychain 1、两次 Debug／两次 Release 严格签名校验及最终原生 Xcode TEST SUCCEEDED。完整原始日志保留于私有诊断目录，SHA-256 为 `85a3a13c11c8e9a8f077255b2a19587d77606ac75b8579446ab852c11e6d4d2d`；本段是结果及范围记录，不是公开完整日志，也不能替代 manifest 的公开 repo_verify/build 证据。

Before 已有 B4 的 42 对可读字体 Widget 原图/sidecar，以及 B6 的 7 对完整 App 模拟器原图/sidecar 与未改动原始视频。B4 的 42 份 sidecar 未记录 captured_at，原字节保留、不补造时间，只作辅助比较，不进入 C 的主 manifest。B6 视频容器标称 95.461667 秒，解码 393 帧，业务 checkpoint 的原始 PTS 为 19.302–29.967 秒；尾部时间表稀疏且不一致，不能把容器时长当作已核验的连续业务时长。已通过全帧缩略图和 9 个放大关键帧审阅，未在播放器连续播放或逐帧放大全部画面。B6 使用真实 native SSH 与 deterministic model，不能算真实 API、IME 或真机验证。

同 C 的正式 After runner 于 2026-10-08 15:17:25–15:19:04 UTC 完成，combined receipt 为 passed、source_tree_clean=true，含 42 个 widget 与 7 个原生 App 检查点；原生失败 exit 2、明确审批后修复 exit 0，独立计数为模型请求 2 次、修复执行 1 次。receipt SHA-256 为 `ee5c76b07ecb4beabf6b0ee88e90b9f1a413f69d9cd9630ef2033030d5cede86`，原始清单 SHA-256 为 `6b3f75cb47f13146500c1084f394a2044b209fb8c9291b53242b0e6c8815759c`。这是模拟器 native SSH 与 deterministic model 烟测；不能换算为完整 PRD 用例通过。诊断目录中其他名为 after 的组件图不自动成为该 C 的正式 After。

已人工查看全部 7 张原生 After PNG，检查点内容和流程动作可读，审阅范围内未发现真实凭据或系统通知；长终端输出仍受水平视口截断，单张截图不能证明全部输出可读。After 的 12 张中英文 widget 图中，草稿 `🧭` 均显示缺字框，已交叉确认；这是测试字体／特殊字符证据缺口，保留原图和 C，不据此宣称真实 App emoji 已验证。视频及其他矩阵的审阅范围另记，不能用这 7 张图替代。

全部 42 张 After widget 原图已由独立 reviewer 逐张查看，未发现需要改变冻结 C 的核心布局阻断；PRD-019 与 emoji 字体限制仍保留。该观察只覆盖这次 fixture 的原图，不代表完整 App、键盘或设备矩阵已通过。

After 原视频为 15.053333 秒、393 帧，原始 PTS 0–15.04 秒无倒退，七个 checkpoint 逐一对应，未重现 Before 的尾部时间表异常。审阅方法仍是全部帧缩略图与 9 个放大关键帧，不是播放器连续观看或全部画面逐帧放大；原视频 SHA-256 为 `a8d28e0c0127ecb3a4aa60f390e8a1d11a39fdb2aea12a9c23b7ac0a1f9ff8d9`，字节未改。4.218–4.842 秒的 SSH 启动画面出现 `dquote cmdsubst>`，Before 也有；原因未定，不把录屏描述为启动无杂讯或认定为新回归。

此前已连接 iPhone 17 / iOS 27.0.1，最新精确目标设备未唯一可用，等待 USB 连接恢复，无需调整 Wi-Fi。该 C 的 `Trail PRD` 独立 Bundle/Keychain 正常 App 已完成物理 profile 构建和严格签名／隔离校验，App bundle SHA-256 为 `fa86448ba6f7f7bf3b9bee5d4a8da208524dac1034cf025a44c0ad699b8aad99`。校验 receipt 为 validated=true、installed=false、launched=false；不能称已安装或已通过设备验收。安装、启动和用户填写专用真实 API 仍 pending。真实 iPad及 iOS 17 运行环境尚未取得；真实系统 IME、旋转与触控、VoiceOver、断网/锁屏/后台恢复、TUI/密码接管、长输出与错误注入、实机 profile 性能及升级回滚证据仍缺。

主 manifest 的 51 份 shared artifacts 含 49 张 After 截图、原视频与 fixture 日志，108 项 source_hashes 绑定 C，正式 structure/integrity validator 已通过。S1-T01/02/03/05 仅记录实际烟测子步骤 partial，其余不虚写运行记录；48 项用例全部仍为 not_run，不填 shot_ids。文中 partial 仅表示部分步骤或证据，manifest 不新增 partial 枚举，不把组件测试或 smoke passed 换算为 PRD passed，也未宣称 S4 evidence gate 已通过。

[基线与冲突](results/BASELINE.md) · [问题登记](results/issues.md) · [用例清单](evidence/manifest.json) · [最终复核](results/FINAL_REVIEW.md)
