# 可选 API 同步验收

日期：2026-09-10。范围是首次合并、双向修改、冲突、网络及登录失败、关闭同步后的本地可用性。

## 隔离环境与方法

- 生产入口 `example/tool/macos_acceptance.dart`、Release 构建、真实 macOS Keychain、原生 PTY 和 SSH；应用操作全部通过 Computer Use。
- 专用数据目录 `/tmp/trail-api-sync-20260910/data`，Keychain account `work.ianvs.trail.acceptance.sync.20260910`。
- 应用只连接 `http://127.0.0.1:56209/` 的 Go remote API，使用临时 SQLite。用户明确授权临时账号 `sync-acceptance` 登录并保存配置后继续验收。
- 第二个真实 API 实例监听 `127.0.0.1:58985`，访问同一测试 SQLite，便于应用端 API 停机时制造远端修改。peer 脚本通过 HTTP GET/PUT 和 revision CAS 修改 Profile，保留加密敏感字段。没有通过文件或脚本修改应用登录状态。
- 401 由服务端测试 SQLite 将该账号的应用令牌到期时间设为过去产生，保留 peer 会话；通过应用“重新连接 / 登录”恢复。
- SSH 使用专用容器 `trail-api-sync-ssh-20260910`，只映射 `127.0.0.1:32770`。未使用正式 Trail 数据、凭据、API 账号或远程 SSH 主机。
- 隔离版本逐个退出后才启动下一版本。指纹见 [build-info.json](build-info.json)、[fixed-build-info.json](fixed-build-info.json)、[final-build-info.json](final-build-info.json)。

## 真实窗口结果

| 场景 | 观察结果 | 证据 |
| --- | --- | --- |
| 无 API 创建、保存 SSH | 本地保存后连接成功 | [01](01-local-ssh-before-sync.png) |
| 首次同步 | 本地主机和远端种子配置均保留，共 4 个 Profile | [02](02-first-sync-ready.png)、[03](03-first-sync-profile-union.png) |
| 不同字段同时编辑 | 本机名称 Sync Local Renamed 与远端标签 remote-edit 在两端合并，revision 4 | [04](04-disjoint-merge-ready.png) |
| 同字段冲突 | 显示 name 冲突路径；选择前本机与 API 各保留自己的值，revision 5 不变 | [05](05-conflict-awaiting-choice.png) |
| 保留本机冲突值 | 两端名称 Sync Local Choice，revision 6 | API 与本地文件读回 |
| 采用 API 冲突值 | 第二轮两端名称 Sync Remote Winner，revision 7，就绪 | [06](06-use-api-conflict-resolved.png) |
| 真实 401 | 明确提示重新登录；仍可本地保存 Sync Pending Login | [07](07-authentication-required.png) |
| 重新登录 | 待同步名称上传至 revision 8；3 个检查点文件身份保持一致 | API 读回及检查点文件名比较 |
| API 离线重启 | 离线保存 Sync Offline Restart，退出后启动新构建；名称、标签及其他 Profile 保留 | [08](08-offline-restart-mode-status.png)、[09](09-offline-restart-profiles.png) |
| 服务恢复 | 不重新输入密码，自动同步至 revision 9 | UI“同步已就绪”与 API 读回 |
| 停机时关闭同步并重启 | 配置已保存为 disabled，SSH 数据保留；发现状态误报，见修复记录 | [10](10-disabled-restart-state-before-fix.png) |
| 关闭 API 后 SSH 重连 | 选择已保存主机，无需再输入密码，真实执行并返回 TRAILSYNCRECONNECTOK | [11](11-ssh-reconnected-api-disabled.png) |

只读检查确认 SSH 密码未以明文出现在本机 Profile JSON。没有把敏感字段存在当作凭据可用的证明，最终通过真实 SSH 重连验证了凭据解密与使用。

## 发现与修复

1. 登录失效与网络错误共用提示。现在用固定中英文文案区分需要登录和普通失败，指向现有重连操作，不展示原始异常；本地修改和基线保留。
2. HTTP 回归发现 validateSession() 复用 owner ID 缓存，令牌被撤销后仍错误返回成功。主动验证改为每次请求 /v1/me；加解密仍缓存 owner ID，但清除失败 future，允许瞬时失败后的重试。
3. 横幅将当前数据模式误写为“运行中”，并把回环 HTTP 描述为 HTTPS。改为仅描述当前模式和已配置 API，实际连通状态由同步面板呈现。
4. API 不可达时关闭同步，退出清理失败不应让下次启动误报同步失败。启动组合仅在 API 已启用时设置 unavailable；本地模式保持 disabled。清理机制继续工作，不阻止本地保存、启动或 SSH。

5. 清理失败的瞬时提示和启动横幅改用安全的中英文说明，不再渲染原始异常及内部实现细节；明确在下次启动时重试，保留内部诊断及既有清理机制。

最终窗口复验通过：[12](12-disabled-restart-state-fixed.png) 确认本地模式不再误报同步失败，且不显示无效的立即同步按钮；[13](13-mode-marker-fixed.png) 确认未保存选择时旧选项标为当前模式；[14](14-cleanup-message-final.png) 确认最终中文清理提示与准确重试时机。最终版本指纹见 [complete-build-info.json](complete-build-info.json)，状态修复版本见 [verified-build-info.json](verified-build-info.json)。

## 自动化回归

- `./tools/verify_local_first_sync_http.sh`：真实 Go 后端与两个 DataApiClient 完整场景通过，覆盖首次合并、不同字段、两种冲突选择、不可达端口、真实 401、同身份重连、关闭及重新启用。
- HTTP 回归检查响应中的敏感字段只有密文，客户端可解密；检查点加密落盘并可重建。此测试使用专用文件文档，不启动窗口或使用平台 Keychain，不等同于完整 Profile 表单验收。
- 最终源码全量回归：1,795 项通过，1 项既有外部 trace 基准跳过，2 张视觉基线出现预期文案差异。逐张审核后仅更新这两张基线；包含全部设置视觉回归、配置恢复、设置和生产启动的复测 56 项通过。最后仅修改清理重试时机文案，对应 6 项回归再次通过，无剩余测试失败；静态分析无问题。
- Release 构建、ad-hoc hardened-runtime 签名及 strict deep 校验通过。

日志索引见 [verification-summary.txt](verification-summary.txt)。

## 范围限制

本轮覆盖 macOS 主路径与受控单账号双端同步，没有宣称生产 HTTPS 部署、多账号权限、移动端或完整 VoiceOver 验收通过。Computer Use 对部分原生退出对话框仍有旧窗口句柄问题；确认数据已保存且没有录制后，通过活动监视器只结束精确匹配的隔离进程，再启动验收。

只读复审还发现较少见的启动依赖恢复场景：凭据存储暂不可读导致 transport 未创建时，“立即同步”不能自行重建它。这与普通 API 离线不同；后续应补充依赖恢复入口及专门回归，不能以本轮网络恢复通过代替该场景。

## 测试环境清理

隔离测试应用均已退出；两处临时 API 已停止；本轮 SSH 容器已删除。正式 Trail 未改动。测试数据、构建和日志保留在本轮 /tmp 目录便于复查；仓库证据不包含密码或访问令牌。
