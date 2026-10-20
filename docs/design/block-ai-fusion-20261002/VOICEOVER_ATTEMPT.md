# 已授权的 VoiceOver 验收尝试

2026-10-03，macOS 27.0.1（26A434）。用户明确授权临时开启 VoiceOver、只检查独立 Trail 测试窗口并在结束后关闭，随后要求继续测试。该授权已执行，不再等待原来的限定窗口授权。

最终范围：用户随后明确要求“VoiceOver 跳过”。实际朗读记为未验收，本次不再继续或等待全局字幕读取授权。以下保留此前实际尝试与限制。

## 实际结果

- 原生窗口、PID、唯一标题和前台状态再次核对通过，见[控制接口预检记录](evidence/voiceover-attempt/control-preflight.json)。首次启动出现 VoiceOver 欢迎窗口；使用其“使用旁白”入口后确认 VoiceOver 进程运行。
- VoiceOver 光标边界查询超时。检查 VoiceOver 自身设置确认：“允许使用 AppleScript 来控制旁白”未勾选，“显示字幕面板”已勾选。没有开启脚本控制权限，也没有修改字幕设置。
- 尝试调查可能阻塞控制的系统通知窗口时，自动审批拒绝读取 UserNotificationCenter：它可能包含无关私人通知。没有执行该读取，也没有通过其他方式读取它。
- 改用现有字幕面板仍被自动审批拒绝：虽然读取前确认了独立测试窗口在前台，按 VoiceOver 应用绑定的字幕仍是全局内容，不能证明只来自该窗口。没有执行字幕或当前朗读文本读取。
- 三次均为同一原生用例的运行，不累计为三个不同用例。最终[原生日志](evidence/voiceover-attempt/captions-native.log)通过；六阶段的终端写入为 0，见[原生结果](evidence/voiceover-attempt/native-result.json)。这证明生产组件在此次运行中的行为与语义断言，不证明实际朗读内容。
- 按授权关闭 VoiceOver，退出命令返回 0；同时关闭本次打开的 VoiceOver 实用工具。最后进程检查确认二者及原生测试进程均已退出。

## 最终范围调整

实际 VoiceOver 朗读未验证，不能用 Flutter 语义树、原生用例通过或截图替代。此前发出的全局字幕读取授权请求已因用户明确跳过而不再需要处理。跳过仅调整此次实际 VoiceOver 验收范围；已有状态语义、键盘操作、高对比与减少动态效果实现及测试保留。

本轮未改产品代码，未提交或推送。六个证据文件与两个源码哈希见[清单](evidence/voiceover-attempt/manifest.json)，[尝试摘要](evidence/voiceover-attempt/attempt-summary.json)明确区分工具观察、审批拒绝与未取得的朗读证据。
