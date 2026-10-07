# D10 恢复布局与 D14 配置状态复核

2026-10-03，`composer` 工作区，macOS 27.0.1（26A434）。直接对照既有 imagegen [D10](screens/D10.png)、[D14](screens/D14.png) 和生产组件截图；图像生成模型不是自动验收器。本页覆盖恢复与配置，云端 SSH 另行记录，不代替 20 场景最终审计。

## D10：未知回执与人工检查

中英文各六组生产 workspace：浅／深色桌面、680px 桌面 2× 字号、320px 手机浅色、390px 手机深色、568×320 手机短横屏。手机全部使用固定字号。12 项用例分别捕获未知命令卡片和滚动到恢复入口后的界面，共 24 张截图。

未知卡片明确说明命令可能已经执行，保留完整命令与原目标，不提供再次批准按钮。恢复区提供“检查原提交”和“返回终端检查”；草稿保持原值，发送和继续执行禁用。点击检查后只查询原 `submissionId`，PTY 写入始终为原先一次，模型请求数不增加。新连接不会把旧未知提交改成失败或可重试。

已直接复核[桌面深色 2× 卡片](evidence/recovery-configuration/recovery-components/D10-unknown-card-en-desktop-2x.png)和[手机短横屏恢复区](evidence/recovery-configuration/recovery-components/D10-unknown-recovery-zh-phone-landscape.png)：长原因正常换行，短屏可滚动到检查入口，输入草稿仍可见，没有第二个批准入口。第一次横屏测试使用 `ensureVisible` 寻找尚未建立的懒加载项失败，后改为真实滚动定位，未放宽生产断言。原始失败与通过日志均保留。

实际远端执行后丢失回执、断线及重新连接的网络证据仍见 [D10_RECONNECT.md](D10_RECONNECT.md)。这里的 12 项是布局和交互覆盖，不把组件端口注入当作网络故障测试。

## D14：配置、编辑与连接分别表达

应用设置的 AI 入口新增四种实际存储状态：读取中、读取失败、尚未配置、配置已保存。“已保存”不表示已经验证连接；入口仍可打开现有 endpoint/model/key 表单。读取失败不会显示成缺少配置，终端功能可以独立使用。

视觉复核发现首次保存失败时原提示写着“原配置已保留”，但首次使用并没有旧配置。现在分别说明：

- 保存失败：“无法保存配置。编辑内容已保留，请重试。”
- 移除失败：“无法移除配置。已保存的配置未改变。”
- 读取失败继续表达无法读取已保存配置，不与保存／移除失败混用。

四组 workspace 覆盖桌面浅色、桌面深色 2×、320px 手机和手机短横屏。缺配置时发送打开配置表单，不启动模型；取消丢弃表单编辑但保留任务草稿与附件；重新打开、保存失败、重试成功均不发送任务。只有返回后显式发送才发起一次模型请求，PTY 写入为零。已复核[手机保存失败](evidence/recovery-configuration/configuration-components/D14-save-failed-phone-light.png)、[深色桌面保存失败](evidence/recovery-configuration/configuration-components/D14-save-failed-desktop-dark-2x.png)，错误说明与固定操作区可达，密钥保持遮蔽。

设置组件另验证慢读取、读取异常、取消编辑、移除失败及重试；真实 macOS 主流程通过设置入口移除并重新保存本机 fixture 配置，入口同步显示[尚未配置](evidence/recovery-configuration/native/D14-configuration-missing-status.png)和[配置已保存](evidence/recovery-configuration/native/D14-configuration-saved-status.png)。同一会话、原生输出块和模型请求数不变。既有 HTTP 401→测试连接失败→测试成功未保存→保存→手动继续也在本轮原生流程重新通过。

## 验证范围

- [898 项应用回归](evidence/recovery-configuration/recovery-configuration-regression.log)通过，包含 AI、Shell、会话、偏好与模式。上述 12＋4 项及 29 项设置组件测试是其中子集，不重复累计。
- [5 项 macOS 原生／手机组件流程](evidence/recovery-configuration/recovery-configuration-native.log)通过：真实本机 PTY 和确定性本机 HTTP，以及四组固定字号手机生产组件渲染。没有实体 iPhone 验收或外部模型质量测试。
- [静态分析](evidence/recovery-configuration/recovery-configuration-analyze.log)、发布镜像、diff 检查通过。53 项证据、14 个关键源码哈希见[清单](evidence/recovery-configuration/manifest.json)。该清单对应这轮配置改动，不覆盖随后云端测试发现的原生清屏问题。

复现命令：在 `example/` 运行 `flutter test --no-pub test/ai test/shell test/sessions test/preferences test/terminal_composer/terminal_mode_test.dart --reporter expanded`；原生流程运行 `flutter test --no-pub integration_test/terminal_ai_workspace_acceptance_test.dart -d macos --dart-define=TRAIL_FUSION_EVIDENCE=/absolute/evidence/path --reporter expanded`。
