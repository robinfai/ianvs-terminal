# GitHub CI：检查范围、耗时与维护

评估日期：2026-09-30。基于 main `886450ff` 的失败记录和最近一次全绿
main `ab587623`，不把提前失败的运行当作提速结果。

## 耗时证据

[全绿 Verify #36005712231](https://github.com/robinfai/ianvs-terminal/actions/runs/36005712231)
墙钟耗时 **97 分 24 秒**，约 **149 runner 分钟**。Flutter 任务排队约 37 分钟，
iOS 排队约 58 分钟。并行声明不能消除托管 macOS runner 的排队。

| 环节 | 全绿运行耗时（不含排队） | 必要性与处理 |
| --- | --- | --- |
| SSH OpenSSH 验收 | 3:12 | 保留：真实认证、主机密钥、跳板和转发不能被 mock 替代；仅原生/包/工具变更触发，缓存 Rust |
| ZMODEM amd64 / arm64 | 各 2:27 | 保留双架构真实传输；相同路径选择、分架构缓存 |
| Windows fail-closed | 3:50 | 保留：证明不支持的平台拒绝请求；仅相关改动运行，添加锁文件约束和缓存 |
| Go MySQL | 3:26 | 保留 MySQL 和原来在 macOS 跑的 SQLite 两套 race 检查；在同一 Linux job 复用编译缓存，包含 gofmt/vet |
| Flutter 整体 | 60:21 | 原本串行包办 Go、Rust、静态分析、包和示例测试；将独立检查移出，按原生改动选择 Rust 全套检查 |
| 其中首次视觉比较 | 8:48 | 大部分是原生 hook 冷编译；保留严格比较和失败图片，缓存 hook 的 Cargo 输出 |
| 其中仓库验证 | 48:37 | 保留 ABI、源镜像、包与组件测试；移出 Go/供应商/静态检查，不重复跑 design 目录 |
| 独立 pub 包 dry-run | 0:14 | 保留：发布归档内容、许可证、零警告与 workspace 内测试不是同一保证 |
| macOS 集成与打包 | 36:52 | 保留真实 PTY、Keychain、Debug/Release、通用架构、签名和原生 RunnerTests |
| iOS 模拟器与设备构建 | 36:28 | 保留模拟器原生/沙箱测试与设备 Release ABI 检查；它们覆盖不同链接路径 |
| macOS Update Checks | 12:29（相邻 PR） | 保留 Python、plist、脚本、真实 EdDSA/篡改检查；原来的 9:31 重复 Debug 构建和 1:01 RunnerTests 归入 macOS 主任务 |
| macOS Release | 最近仅 18 秒便失败 | 发布不是每次提交的基础检查；改为显式启用，自动发布等待 Verify 成功且使用同一提交 |

保留 macOS 第二次 Release 构建：它验证增量 CodeAsset 打包后签名仍然完整，
不是无意义重复。保留 canonical / standalone 两个干净 Rust ABI 构建和包测试：
两者依赖边界不同，源镜像一致不能代替独立产物校验。它们只在相关原生/包改动时运行。
资源夜间 benchmark 原本默认不运行，继续保持手动开关；CI smoke benchmark 仍运行。

## 任务选择与缓存

`tools/ci/changed_jobs.py` 使用完整 git diff，PR 相对 merge-base，push 相对 before。
禁用 rename 合并以同时检查旧路径和新路径。手动运行、基线不可用、工作流/工具或
未知顶层路径改动均运行全套。路径选择自身有行为测试。

| 改动 | 昂贵检查 |
| --- | --- |
| 文档、根目录契约测试 | 只运行始终启用的 Linux 格式、分析、协议语料和仓库契约检查 |
| backend | Go SQLite/MySQL + macOS（内嵌 Go 服务） |
| Flutter 共享代码、资源或 pub 锁文件 | Flutter + macOS + iOS |
| macOS / iOS 工程 | Flutter + 对应平台 |
| example/test | Flutter；共享 test/support 还触发两端集成 |
| native / packages | Flutter、全部 Rust/SSH/ZMODEM/Windows、macOS、iOS |
| tools / .github / 未知目录 | 全套 |

工作流始终启动，按 job 条件选择昂贵任务；`Verify required checks` 汇总失败和取消，
允许按路径跳过的任务。若配置必需状态检查，推荐使用这个固定名称，避免 workflow
级路径过滤产生长期 Pending。[GitHub 工作流语法](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)

Flutter 固定 3.44.2，SDK/pub 缓存通过固定 SHA 的 `actions/cache` 管理；不启用
flutter-action 内部引用可变 tag 的缓存。Rust 缓存按任务、OS、架构、工具链和锁文件
隔离；hook 只缓存 Cargo 输出，键还包含 Xcode 指纹与原生源文件。hooks 继续执行输入
检查和产物生成。不缓存签名凭据、keychain、Xcode DerivedData 或已签名发布包。

## 本次失败及修复

来源：[Verify #36696180110](https://github.com/robinfai/ianvs-terminal/actions/runs/36696180110)
和 [Release #36696180293](https://github.com/robinfai/ianvs-terminal/actions/runs/36696180293)。

- **视觉基线**：6 张 macOS 26 shell/layout 旧图未反映已合入的标题栏和标签改动，
  差异为 7.44%–10.25%。核对该提交 CI 的 master/test 图后采用对应平台候选；
  未调宽容差或删除测试，其他基线保留。macOS 27 基线未据 macOS 26 输出改写。
- **macOS 下载验收**：桌面通知已经改为通知卡片，旧测试仍等待 SnackBar 并假设新通知
  替换旧通知。改为验证本地化的已保存/禁止上传消息，同时保留路径、字节和显式 Save 断言。
- **macOS 后台唤醒**：`poll_tick_skipped` 可能覆盖最新的 `refresh_result`，使测试错过
  264ms 状态后永远等待。改为查询最新完成结果；仍验证结果新于历史、刷新类别、回退参数、
  实际 FIFO 唤醒和原有时间上限。
- **iOS**：Runner LaunchAction 使用 Release，而该配置只支持设备，导致 Xcode 无法选择
  generic iOS Simulator。恢复 Debug 启动配置；Archive 和显式 Release 构建保留。
- **发布**：8 项签名 secret/variable 均未配置。这无法用代码替代。自动发布现在需要
  `MACOS_RELEASE_ENABLED=true`；手动或已启用的发布仍严格检查凭据并失败关闭。
  配置方法见 [发布说明](release/MACOS_RELEASE.md)。

## 验证记录

本地环境：macOS 27.0.1、Xcode 27.0、Flutter 3.44.8 / Dart 3.12.2。
已通过完整 Dart 静态分析、47 个仓库契约测试、9 个任务路径选择测试、14 个发布 helper
测试，以及 4 个真实 macOS PTY 回归用例（下载确认和三种 masked-hint 唤醒状态）。
Xcode 已重新列出 iOS 模拟器目标。CI 固定 SDK 的视觉比较和完整平台构建需由 PR 运行确认；
这些本地结果不代表四个支持的 OS 大版本都已实测。

优化后的冷/热缓存时长应与全绿运行分别比较：记录排队、SDK/cache restore、编译、测试和
cache save，避免把机器负载差异或提前失败算作加速。首次运行只是建立缓存，不能代表热缓存耗时。
