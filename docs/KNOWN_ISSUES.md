# Trail Known Issues

只记录当前限制与未关闭问题；不保存历史运行结论或验收产物。

## 产品与平台

- macOS 是当前主交付平台；iOS 已实现 SSH 配置、保存和会话流程，但尚未完成实体设备上的完整产品验收。
- 当前支持 local shell 与基于 Rust 的 SSH session；两者共用 tab、pane 与 layout 模型。
- scrollback 搜索支持子串/正则与大小写选项，范围是当前会话已接收的输出。
- 还没有跨平台验证；Linux / Windows 仍需真实目标机桌面证据。
- 还没有插件系统；当前没有 native renderer，也没有 `wgpu` renderer。
- API 跨设备同步、安装发布、完整 VoiceOver 和原生 AX 行为需要独立验收，单元或语义树测试不能替代。

## 技术与性能

- viewport 使用 Flutter Canvas；帧和图形传输使用当前 Protobuf Packet，旧 JSON frame diff 不属于 ABI。
- macOS 依赖随应用打包的 Rust 动态库；本地 shell 当前没有启用 app sandbox。
- benchmark smoke 覆盖正确性和轻量时延门槛；CPU/RSS 阈值需要安静宿主运行，尚无跨机器长期对比基线。
- SSH 自动化覆盖认证、ProxyJump、host-key 与转发；更宽的服务器版本、发行版和真实网络环境仍需验证。
- 字体/DPI、Unicode cluster、Powerline / Nerd Font 的实际观感，以及 trackpad 和宿主快捷键，需要[人工检查](compatibility/MANUAL_VERIFICATION.md)。
- 长录制的容量、内存与快照恢复改进见[录制存储提案](recording/STORAGE_PROPOSAL.md)，尚未实施。

## 当前门禁阻塞

- 本机 CLT 27 SDK 与链接器不匹配。命令级指定 Xcode 26.2 的 `SDKROOT` 可避开该链接错误，不需改项目配置。
- Dart 严格分析仍有既有 info 级 lint；Data 范围主要为 `prefer_initializing_formals`。
- 工作区 iOS Bundle ID / signing 设置与 Apple identity 合同不一致；Runner simulator destination 匹配失败使本地优先启动 gate 尚未运行到断言。
- 视觉 golden 已归入 `example/test/design/goldens/`。迁移保持原图，但当前 UI 的 39 项视觉回归出现像素差异；基线须经设计确认后更新，不能把文件迁移当作通过。

运行方法见 [TESTING.md](TESTING.md)。修复问题时同步本页；新日志、截图与失败对比统一写入 `build/` 或测试工具的临时失败目录。
