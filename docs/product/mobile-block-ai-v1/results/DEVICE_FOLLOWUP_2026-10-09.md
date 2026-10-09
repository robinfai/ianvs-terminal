# 2026-10-09 真机与真实 API 复验

本轮已将保存的 `cloud` SSH 配置用于独立 Trail PRD，完成真机连接、重启后重连以及真实模型的只读诊断流程。最终手机实现为 C3 `1a678e38f0b9b5765f468d339d564faa16a03f25`。这些是范围明确的实际运行观察，完整 PRD 验收仍未完成，48 项用例不升级为 passed。

## 版本与成品身份

| 标识 | 来源与用途 |
|---|---|
| C1 `fe1556fc99af6ecca45caf7780604c9f8e541bd9` | 2026-10-08 正式 After 与主 manifest 的历史实现；原始图片、视频、sidecar 和 source hashes 不改写 |
| C2 `eb1fe32f36edfffcd87d55f33bdc4c1ca816de4a` | SSH 人工交互超时、受限终止原因及独立 PRD 凭据持久化修复 |
| C3 `1a678e38f0b9b5765f468d339d564faa16a03f25` | 旧 bash-preexec 退出码修复；本轮最终安装并复验的实现 |
| 设备 | iPhone 17，iOS 27.0.1；没有由此推定其他支持版本已实测 |
| App | `work.ianvs.trail.mobileprd`，0.1.0+1，profile AOT，正常 `example/lib/main.dart` 入口，无 fixture/test driver |
| C3 App bundle SHA-256 | `baa7bc0b3030cea96007bd9b1d226e24b0d4605d5ee5791b4160bb50f49b227f` |

C3 成品于 2026-10-09 03:13:59 UTC 完成安装和启动。严格预检确认签名、目标设备、独立 Bundle/Keychain、实际 device-only master key 标记、AOT 入口及成品完整性；receipt 为 validated=true、installed=true、launched=true。本轮后续 E 只更新文档，不修改这份已测实现或重新加工原始证据。

## 已确认的修复与边界

- SSH 连接的网络超时不再消耗等待用户处理主机指纹等交互的时间，覆盖直接连接及 ProxyCommand/ProxyJump 传输；交互仍受自身上限和取消控制。45 项 SSH 定向回归包含真实握手路径。用户已手动信任本次主机；C3 没有重新测试未知指纹下长时间等待的真机路径。
- 独立 PRD 只有在实际 Bundle ID 与严格布尔构建标记同时匹配时，才使用独立、不同步、仅本设备解锁时可用的 Keychain master key。既有生产 iOS 的同步密钥只读策略保持原要求；本次不验证生产 iCloud 同步。原有密钥读取/损坏/空值错误不会静默新建覆盖。
- 旧 bash-preexec 的首条 `declare -F` 判断会把上一条命令的 `$?` 改为 0，导致真实失败命令被记录为成功。C3 仅替换精确匹配的旧分发前缀，先捕获并恢复退出码，再调用原分发器；保留用户 prompt 尾部、数组稀疏索引、history、DEBUG trap 和回调顺序，不改写未知或现代前缀，也不额外提交命令。

## 设备观察

1. 经用户授权导入并保存 `cloud` 私钥后，临时手机明文文件已覆盖清空，并核对长度为 0；Mac 原私钥未修改。主机策略保留“询问信任”，未复制本机跳过验证的设置。C2 冷重启与 C3 更新后，均可使用已保存配置重连。
2. keepalive=0 时曾观察到 `transport_eof`，没有远端退出码。改用 15 秒 keepalive 后，C2 在约 11 分钟没有业务命令的间隔后仍能成功执行新的只读命令。期间有保活包；这不是连续网络取证，未将原因归咎于服务端、VPN 或路由器。
3. C3 上执行独立 `/bin/false`，失败图标及直接“AI 诊断”入口可见，Reader 明确显示退出码 1。进入诊断后形成草稿，随后由操作者明确发送。
4. 使用用户在 App 内配置并授权的 DeepSeek 端点，取得真实命令提案。先打开全文审阅，再明确点击一次“执行一次”。命令只运行 `/bin/true`、`/bin/false` 并打印状态，不更改远端文件或服务。
5. 回复完成后点击“证据 · 1–2 行”，进入对应 Reader，实际输出为 `true -> 0` 与 `false -> 1`；整条验证命令最后的 echo 成功，所以该组合命令退出码 0 正确。返回终端后有两个已结束命令块，Shell 就绪。

```sh
/bin/true; echo "true -> $?"; /bin/false; echo "false -> $?"
```

该真实模型路径是只读诊断烟测，没有修复一个实际失败的项目，因此不能等同于 S4-T01 的全部场景。操作者观察到一次审批点击；未采集独立设备模型请求/PTY 提交计数日志，不能仅凭截图证明恰好执行一次。

## 实际验证

- C3 修复先在真实 PTY 复现错误，再通过永久回归：新增 2 项参数化入口测试；相关 shell_bootstrap 为 19 passed / 1 外部环境 fixture ignored，pty 为 15 passed。计数范围重叠，不相加作为独立用例总数。
- 宿主 Bash 3.2 通过 4 组 scalar 真实 PTY 路径及独立结构回归；离线 Bash 5.2 通过 8 组旧/现代、延迟/已安装、scalar/sparse-array 组合，并覆盖 raw 与 Composer 提交。实际 cloud Bash 4.4 经 Composer 提交普通命令名和绝对路径命令，取得两轮 1→0→7；C3 真机随后核对失败退出码。
- C3 clippy、格式与 canonical/core 镜像检查通过；独立 reviewer 未发现本次精确前缀修复的阻断问题。
- C2 精确 clean 实现的完整 `make verify` 已于 02:42:11–02:56:33 UTC exit 0，macOS 未跳过，原日志 SHA-256：`691c576dad7393d8fdb42a0bd127f6b714bc7273562b60c6a6b2f3afc7eb5893`。
- 精确 clean C3 的完整 `make verify` 于 2026-10-09 03:14:37–03:28:31 UTC 通过（exit 0），开始/结束源码一致且干净，macOS integration 未跳过，覆盖重复 Debug/Release 严格签名和最终原生 Xcode tests；原始完整日志 SHA-256：`b95470c11556159f6bbedac10e9e085017b931aab706576584443ee52288de1b`。日志保留私有。

完整 gate 日志和签名安装原收据保留私有。上述结果/hash 摘要不能替代 S4 要求的公开完整 repo_verify/build 原始证据。

## 证据与剩余范围

C2 的 7 张原图与 C3 的 7 张原图、来源 sidecar、安装/检查 receipt 分别绑定各自源码和 App hash，保留在本地忽略目录 `build/mobile-prd-v1.1/physical-api/cloud-20261009/` 及 `physical-preflight/`、`audit/`。C3 原图采集于 03:15:22–03:22:43 UTC，原始画布为 3840×2880，设备视口为 402×874 points / DPR 3；未裁切或重新标记旧图。

输入来自 iPhone 镜像中的 Mac 键盘和鼠标，截图来自设备无线显示。独立 reviewer 已逐张查看全部 7 张 C3 原图，hash、来源与安装回执相符，未发现本轮范围内新的可见缺陷；可见结果包括完整提案、实际两行输出、独立失败退出码 1 和结束时 Shell 就绪。 原图含真实 SSH 用户、主机或目录信息，继续私有保存。截图不能独立证明请求的端点来源、动作完整时序、恰好执行一次或持续连接时间。没有取得本轮原始连续设备录像，也没有验证手机软键盘、中文 IME 或直接触控。

主 manifest 与 2026-10-08 公开 After 仍只描述 C1，不冒充 C3 证据；本轮记录不改变其中 48 个 not_run。真实 API/SSH 前提已经满足，但连续视频/断言日志、完整修复场景、IME/旋转/VoiceOver、断网锁屏后台、TUI/密码、长输出、iPad/其他支持系统、性能及升级回滚等证据仍缺。旧 C1 的无末尾换行输出被下次 prompt 覆盖观察在 C3 尚未复验；英文单来源 `1 sources` 的 PRD-019 也仍 open。

本次整理时，manifest 的 structure/integrity 与 shot coverage/embedding 检查通过；另逐一核对 C1 Git 对象中的 108 项 source hashes，均一致。带 `--repo-root .` 的当前源码一致性检查明确拒绝 3 处差异：`example/lib/main.dart`、`tools/mobile_prd/build_ios_fixture.sh`、`tools/mobile_prd/test_build_ios_fixture.py`。这些文件已随 C2 更新，因此 C1 manifest 不能通过 C3 的当前源码 gate；未修改 validator、旧 hash 或原件来消除此差异。文档合同检查 23 项通过。

参见[状态](../STATUS.md)、[问题登记](issues.md)与[S4 场景](S4.md)。
