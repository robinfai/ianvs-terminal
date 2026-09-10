# 启动依赖恢复后的同步重试验收

日期：2026-09-10。基于已推送的 `526f7927`，补齐凭据存储暂不可读、启动未能创建同步连接的恢复路径。

## 最终行为

- API 已启用但启动连接不可用时，“立即同步”重新读取已保存配置和凭据并创建连接，无需重启应用。普通网络故障继续使用现有连接重试。
- 恢复请求由同步协调器统一管理。连续点击、关闭并重新打开设置共用一次请求，恢复期间按钮不可重复操作。
- 保留本地修改、登录配置、凭据和同身份的加密同步检查点。缺失或过期凭据提示重新登录；其他失败使用固定安全提示，允许再次重试。
- 恢复与保存配置按顺序执行，较早的凭据读取不能覆盖后来保存的关闭同步状态。
- 成功恢复连接后移除旧的通用启动失败横幅；待清理远端凭据的独立提示继续保留。
- 应用退出由同步协调器关闭当前连接，包括启动后才恢复的连接；等待在途恢复，关闭迟到连接，并将清理失败交给现有退出错误处理。界面回调不会泄漏恢复异常。

## 自动化证据

| 层次 | 场景及断言 |
| --- | --- |
| 设置组件 | 点击立即同步恢复、合并两端修改；重复请求和设置重开共享忙碌状态；失败后再次恢复；登录失效分类；界面销毁后清理迟到连接 |
| 生产启动组合 | 注入暂不可读的凭据存储，仍可保存本地 Profile；恢复后使用原凭据和检查点，配置与凭据写入次数均为零；缺失或过期会话分类正确 |
| 配置并发 | 阻塞旧凭据读取，随后保存关闭同步并请求应用配置；解除阻塞后最终保持 disabled，连接为空 |
| Shell 界面 | 恢复连接后通用启动警告消失，远端凭据待清理警告保留 |
| 退出生命周期 | 初始及恢复后连接仅关闭一次；退出等待在途恢复并清理迟到连接；关闭失败正确进入退出结果；界面销毁后的恢复失败安全完成 |
| 真实 HTTP | 独立 Go API、临时 SQLite 和两个客户端。无连接期间保存本地修改，另一客户端修改远端；首次恢复失败，第二次用原同步身份和加密检查点恢复；两端修改合并、敏感字段可解密。既有冲突、401、离线和重新启用场景一并执行 |

最终全量测试 1,812 项通过、1 项既有外部 trace 基准跳过；真实 HTTP 验收、静态分析和生产入口 macOS Release 构建均通过。本轮未更新视觉基线。执行结果和日志索引见 [verification-summary.txt](verification-summary.txt)，构建指纹见 [build-info.json](build-info.json)。

## 复现

在 `example` 目录运行：

```sh
flutter test --no-pub test/startup/app_startup_coordinator_test.dart test/startup/app_runtime_sync_shutdown_test.dart test/data/sync/api_sync_panel_test.dart test/data/configuration/data_api_recovery_ui_test.dart
flutter test --no-pub
flutter analyze --no-pub
flutter build macos --release --no-pub
```

在仓库根目录运行真实服务验收：

```sh
./tools/verify_local_first_sync_http.sh
```

## 验收边界

凭据暂不可读由生产启动依赖接口注入，不修改 macOS Keychain 权限。真实 HTTP 测试使用加密文件存储和真实后端，但不启动原生窗口。本轮没有新增 Computer Use、真实 Keychain 故障或 VoiceOver 验收；上一轮窗口与 SSH 验收见 [API 同步验收](../api-sync-acceptance-20260910/README.md)。

HTTP 脚本退出时停止临时服务并删除临时数据库和账号。未使用正式应用数据或远端账号。
