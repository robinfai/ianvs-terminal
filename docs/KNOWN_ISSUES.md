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
- 录制四批次已按用户修订的约两小时范围完成验收：连续录制 1 小时 54 分 43 秒，独立回放、搜索、定位、文件校验及资源审查通过。末尾超时已复现为测试工具发送的 Escape 进入 Bash，与下一条命令首字母 p 触发历史搜索；改用菜单 Cancel 后，短对照的录制、正常保存与新进程重开全部通过。原始失败报告保留，不宣称 24 小时稳定性。首次搜索准备约需 9–12 秒；详见[验收结果及限制](recording/ACCEPTANCE_RESULT.md)。

- Bash 的 DEBUG hook 可能只报告复合输入行的首个简单命令；录制不会从按键或画面补造其余命令。内置 Bash/Zsh/Fish hook 已补充安装时获取的主机名；未提供主机元数据的其他 hook 仍无法按主机筛选，完整应用短测已覆盖实际嵌套 SSH 主机切换及跨录制主机筛选；实际约两小时录制与独立重开已结束，尾部超时已复现并归因为外部测试按键干扰。

## 环境与其他平台限制

- 本机 CLT 27 SDK 与链接器不匹配。命令级指定 Xcode 26.2 的 `SDKROOT` 可避开该链接错误，不需改项目配置。 当前录制实现的完整 macOS 门禁已通过，见录制验收结果。
- 工作区 iOS Bundle ID / signing 设置与 Apple identity 合同不一致；Runner simulator destination 匹配失败使本地优先启动 gate 尚未运行到断言。
- macOS 视觉 golden 位于 `example/test/design/goldens/`，使用共享字体配置与精确像素比较；运行环境的 Flutter 和系统字体版本差异仍可能影响结果。

运行方法见 [TESTING.md](TESTING.md)。修复问题时同步本页；新日志、截图与失败对比统一写入 `build/` 或测试工具的临时失败目录。
