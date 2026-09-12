# 初始化阶段确认 Shell 能力

本地初始化、协议 SSH 和包装后的子 Shell 统一使用 Hook 注册检查。收到当前 context 的 bootstrap.ready 后，内置 7 项能力立即可用，无需先执行用户命令。界面和诊断数据区分 initializationChecked 与 observed，真实事件到达后升级依据，不生成命令记录或退出码。

- Bash：检查 DEBUG trap、PROMPT_COMMAND、命令和提示符函数、编码辅助函数及 od/tr。
- Zsh：检查 preexec/precmd 数组、相关函数及 od/tr；本地在首次 precmd 前检查，覆盖 .zlogin 的晚期修改。
- Fish：检查 fish_preexec/fish_postexec/fish_prompt 的事件注册和辅助函数。
- 保留当前 Shell 独立状态及父层恢复；基础策略关闭、仿真模式和会话结束仍覆盖有效状态。
- 提示符坐标、输出区域等扩展项不能由普通 Hook 注册推出，继续等各自数据。明确检查失败标为不可用，未知或超时仍待确认。

注册检查证明初始化就绪，不等于已经通过实际命令的完整运行验证。检查不会手动触发 preexec/postexec，不执行探测命令，不向交互输入中粘贴脚本。

## 验证

原生完整回归 390 项通过。新增真实本地 PTY 用例确认 Bash/Zsh 在未发送任何用户命令时即收到开始/结束/退出码的注册结果，且无 preexec 或 command_finished 事件；Zsh 的 .zlogin 移除执行 Hook 时明确报告失败。远端内存引导用例同样在第一条命令前断言检查结果，保留预装复用、冲突和历史验证。

另有本地和内存引导 Bash 冲突用例：提示符串联内置回调与额外命令时，初始化明确报告冲突，不递归重装，不把提示符内部命令输出为用户命令事件。

- 应用状态、能力界面、Shell 页面及文件操作 158 项通过：[日志](app-test.log)。
- 原生完整回归：[日志](native-test.log)。
- 真实 OpenSSH 产品验收通过，覆盖 Bash/Zsh/Fish、预装 Hook、冲突、无 SFTP、只读目录、历史、多层 ControlMaster/SFTP 和端点隔离：[结果](product/results.json)、[日志](product/product-test.log)。
- 静态分析无问题：[日志](analyze.log)。

测试在 macOS 宿主及隔离 Ubuntu SSH 夹具运行，未重启用户应用或已有会话。
