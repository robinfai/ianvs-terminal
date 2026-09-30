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
| macOS Update Checks | 12:29（相邻 PR） | PR 保留 Python、plist、脚本、真实 EdDSA/篡改检查；原来的 9:31 Debug 构建和 1:01 RunnerTests 默认复用 macOS 主任务，macOS 15 兼容抽查保留为手动全套 |
| macOS Release | 最近仅 18 秒便失败 | 发布不是每次提交的基础检查；改为显式启用，自动发布等待 Verify 成功且使用同一提交 |

保留 macOS 第二次 Release 构建：它验证增量 CodeAsset 打包后签名仍然完整，
不是无意义重复。保留 canonical / standalone 两个干净 Rust ABI 构建和包测试：
两者依赖边界不同，源镜像一致不能代替独立产物校验。两次干净 Rust 构建和原生契约
只在相关原生/包改动时运行；Flutter 包测试仍覆盖所有 Flutter 相关改动。
资源夜间 benchmark 原本默认不运行，继续保持手动开关；CI smoke benchmark 仍运行。

**覆盖频率变化**：旧 updater 原生测试在 macOS 15，Verify 原生测试在 macOS 26。
PR 现在自动检查 26；macOS 15 的完整 Debug/Sparkle/RunnerTests 改为手动运行
`macOS Update Checks`（`workflow_dispatch`），需在发布兼容验收时运行。
这保留了检查入口，但减少了每个相关 PR 的 OS 15 运行覆盖；不代表所有支持的 OS 均已验证。
此手动 job 不另存缓存，避免为偶发的兼容抽查占用日常检查的缓存容量。

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

首轮实测还发现旧 `setup-go` v5.0.2 的缓存恢复返回 400、保存失败，其内置缓存库
仍为 v3。升级到固定 SHA 的 [setup-go v7.0.0](https://github.com/actions/setup-go/releases/tag/v7.0.0)
以使用当前缓存服务和 Node 24；Go 编译器仍固定为原来的 1.23.x。
新加入的 `actions/cache` 同样固定为支持 Node 24 的 v6.1.0。

Flutter 的 Rust 依赖和 hook Cargo 输出在后续组件测试失败时也保存；首轮 3 个
组件用例失败曾导致已经完成的原生编译缓存全部丢失。缓存保存不会改变测试结果，
下轮仍执行 Cargo 输入检查和全部选中的测试。

首轮缓存达到 10.3 GB 时 Flutter job 尚未保存，接近默认容量上限。根据实际体积，
macOS 与 iOS 共用一份约 2.18 GB 的 SDK；取消约 1.69 GB 的 Linux SDK 缓存
（冷安装 57 秒），保留 pub 和更昂贵的原生编译缓存。不要靠增加付费容量掩盖重复缓存。
PR 缓存只对同一 PR 的后续运行可用；合并后的 main 首轮仍需建立主干缓存，之后其他
PR 可复用主干缓存。[GitHub 缓存范围和容量说明](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)

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

[PR 首轮全量验证](https://github.com/robinfai/ianvs-terminal/actions/runs/36732126772)
越过旧的视觉失败后，还暴露了 3 个示例测试失败（1906 通过）：

- **iOS 键盘工具栏**：侧栏布局的 builder 引入了新的 context，读到的是 Scaffold
  已清除的键盘 inset，导致真实键盘工具栏不显示。现在在 Scaffold 上层读取 inset，
  原有快捷键发送、键盘收起和会话导航测试继续验证实际行为。
- **签名测试夹具**：签名器增加了 Mach-O/dlopen 预检，但测试仍只建立空的 `.app`
  目录。夹具现在编译一个真实动态库，保留证书、签名、entitlement 的全部正反断言；
  这个用例需要 macOS 工具链。已有 4 项原生库验证器测试也接入 macOS job。
- **录制库重建测试**：真实文件和索引查询被固定 widget pump 次数截断，在 CI 上超时。
  现在在 `tester.runAsync` 中完成两次独立仓库的真实读取，再让 UI 消费结果，仍验证
  重建后的记录、搜索和复制；未延长生产超时或移除持久化断言。

## 验证记录

本地环境：macOS 27.0.1、Xcode 27.0、Flutter 3.44.8 / Dart 3.12.2。
已通过完整 Dart 静态分析、47 个仓库契约测试、9 个任务路径选择测试、14 个发布 helper
测试，以及完整 **45 个真实 macOS PTY 用例**（含下载确认、native-hint 和 masked-hint 唤醒）。
Xcode 已重新列出 iOS 模拟器目标。CI 固定 SDK 的视觉比较和完整平台构建需由 PR 运行确认；
这些本地结果不代表四个支持的 OS 大版本都已实测。

后续修复通过 21 项定向用例、4 项真实 Mach-O 校验器测试和再次静态分析。
206 个自包含示例测试文件中 1902 项直接通过；另 7 项直接加载原生库的用例在提供
当前工作树 `IANVS_CORE_LIB` 后全部通过（云端脚本原本先构建该库）。

优化后的冷/热缓存时长应与全绿运行分别比较：记录排队、SDK/cache restore、编译、测试和
cache save，避免把机器负载差异或提前失败算作加速。首次运行只是建立缓存，不能代表热缓存耗时。


## 功能分支上的 Linux CI

`codex/linux` 的 **Linux desktop** 尚未合入 main，本次修复不修改该分支。
[2026-09-30 成功运行](https://github.com/robinfai/ianvs-terminal/actions/runs/36680776134)
用时 37:49：环境依赖 0:42、分析 0:47、Rust 5:14、独立对端协议验收 0:07、
Dart/组件测试 16:08、真实 GTK/PTY/剪贴板/密钥库 7:49、发布打包 5:41。
原生 GTK 与安全存储、Linux 打包均应保留；合入时应接入本次路径选择和缓存，
共享静态检查，避免 PR 同时触发 branch push 与 pull_request 的重复整套运行。

## PR 实测

[PR #8 首轮 macOS Update Checks](https://github.com/robinfai/ianvs-terminal/actions/runs/36732126429)
已成功：job **29 秒**，原先同一检查 12:29；耗时下降约 **96%**，昂贵的构建与
RunnerTests 由 Verify/macOS job 继续执行。首轮 Flutter 最终出现上文 3 个后续失败，
所以首轮 **48:55** 不能作为完整成功的提速数据。

首轮 iOS job 已成功，用时 **29:16**，其中平台验证 25:11。运行环境为
macOS 26.6.2、Xcode 26.6、iPhone 17 Pro / iOS 26.2 模拟器；原生 RunnerTests、
沙箱集成用例、模拟器和设备 Release 的精确 ABI 检查均通过。设备 Release 为无签名
构建，不能据此声称在实体 iPhone 上完成了运行验证。

首轮 macOS job 已成功，用时 **37:58**，包含完整 45 个真实 PTY 用例、32 个原生
RunnerTests、Debug/Release 签名和两次 Release 打包。该冷缓存样本没有比历史 36:52
更快，因此不宣称它已有构建耗时收益；后续运行另行确认缓存效果。
