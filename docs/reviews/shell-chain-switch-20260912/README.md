# 链路设计与 Shell 切换跟踪修复

本次按用户选择使用纵向轨道布局，并将数据库形状图标改为 Material 终端 / 双层服务器图标。当前行高亮、端口弱化、跳数摘要与紧凑说明均已接入实际 Flutter 界面，保留实时状态更新和窄屏换行。

- [选定设计及图标修订](design-target.png)
- [Flutter 实际渲染](selected-design.png)
- [暗色窄屏、2 倍文字](compact-dark.png)
- [并排核对页](comparison.html)
- [视觉核对记录](design-qa.md)

设计修订使用内置 ImageGen，参考所选纵向图与第一张图的服务器图标；最终提示要求保留纵向布局和所有数据，仅替换数据库图标为双层矩形服务器图标，并统一轨道对齐。生成图作为设计参考保存在本目录，产品 UI 使用原生 Flutter 组件和现有图标库。

## 问题与修复

原有实现只包装 SSH，新启动的交互 Shell 没有获得初始化流程。新增的真实本地 PTY 用例在修改前进入 Bash 后等待 Hook 超时，修复后 `zsh → bash → zsh → 返回` 通过，且关闭本地 SSH 包装仍能工作。

交互式子 Shell 使用单独 context 检查和加载 Hook，同时复用所属主机 context。子 Shell 的能力重新观察，返回时恢复父层；SSH 链路不多出节点，SFTP 面板与文件请求保持主机目标。脚本和 `-c` 仍直接执行；具体支持边界见 [协议说明](../../protocols/ssh_shell_bootstrap.md)。

## 验证

- Rust 全量库回归 386 项通过，1 项外部夹具验收默认忽略并单独运行通过。
- 真实 OpenSSH 验收：远端 Bash/Zsh/Fish 根 Shell 继续切换 Bash → Zsh → Fish，再 SSH 到下一主机；跨 Shell 恢复命令状态；同主机换 Shell 后原 SFTP context 仍下载到正确主机；已有 master 保留，退出后的历史文件无注入正文。
- 产品验收通过记录：[results.json](product/results.json)、[测试日志](product/product-test.log)。
- Flutter state/controller/dialog/screen/SFTP 相关 138 项通过；最终端口视觉调整后 8 项能力对话框用例再次通过。
- 变更范围静态分析无问题。明暗、390 px 窄屏、2 倍字体、实时返回更新和 Escape 关闭均已验证。

测试在 macOS 宿主和隔离 Ubuntu OpenSSH 夹具运行。Flutter 截图来自真实 widget 渲染；本次未重启用户正在使用的应用或 SSH 会话。
