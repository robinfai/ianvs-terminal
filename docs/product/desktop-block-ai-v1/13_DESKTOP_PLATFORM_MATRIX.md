# 13 · 桌面平台、Shell、后端与发布声明

## 1. 本轮范围

仓库编写基线明确macOS为主交付端，Linux/Windows产品声明依赖实际桌面host证据。[执行目标](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/CURRENT_EXECUTION_TARGET.md) [产品范围](https://github.com/robinfai/ianvs-terminal/blob/763dc166bb1e56d6d50ed3379b57f366c9ca06b7/docs/TERMINAL_PRODUCT_SCOPE.md)。因此本包64个主case以macOS实际原生App为基准；D4-T15要求核对和提交其他桌面就绪矩阵，不等于强制从零移植。

允许最终写“macOS桌面版D1–D4通过，Linux/Windows未验证/未实现”；不允许写“桌面全平台通过”而只提供Mac截图。

## 2. 平台台账（实施时填写，不能预填通过）

|平台|host/构建入口|native PTY/SSH|真实App启动|IME/键鼠/DPI|API/ACP|实际测试环境|结论|
|---|---|---|---|---|---|---|---|
|macOS|核对最新入口|必须真实验证|必须|必须|API和ACP分别|填OS/架构/屏幕/构建|not_run|
|Linux|检查最新分支是否实现|有host才逐项验证|无图不宣称|X11/Wayland实际环境分列|ACP检测≠执行通过|实际发行版/显示协议|unassessed|
|Windows|检查最新分支是否实现|依实际后端/ConPTY实现核对|无图不宣称|系统缩放/快捷键/IME单列|不由Mac推断|实际系统/架构|unassessed|

状态取值：`not_supported`（明确当前无能力）、`implemented_unverified`（有实现缺证据）、`verified`（该平台全部所声明路径有证据）、`blocked`（环境/依赖不可用）、`failed`。目录存在不等于implemented全部能力；Windows字段提到ConPTY是应核查对象，不是本轮已核实实现。

## 3. 已承诺平台的独立扩展矩阵

最新分支若已具备/承诺Linux或Windows原生产品，不能因本包Mac主线而忽略退化。按每平台建立独立 `results/platform-<name>.md` 及证据，不复用Mac检查点ID覆盖它。

|扩展ID|最低内容|最低证据|
|---|---|---|
|<platform>-X01|干净源码构建、包安装/启动、native库加载|真实OS/VM原生App完整图+日志|
|X02|本地Shell有效提交、Block真实输出、未知/拒绝边界|连续视频+operation与fixture结果|
|X03|SSH支持范围、租约、回退、重连|真实SSH+原生App|
|X04|输入法、复制/粘贴、Ctrl/Cmd作用域、鼠标/滚轮|实际系统操作|
|X05|分屏、窗口resize、字体、DPI/系统缩放、深浅色|真实UI+环境元数据|
|X06|API完整链路；ACP有支持声明则另跑真实适配器|实际后端+审批/结果|
|X07|打包/升级/回滚、配置/录制保留|隔离环境结果|
|X08|与Mac共享canonical的回归及完整平台gate|测试日志+源码hash|

这些是平台扩展case，不包含在64主case/159主截图检查点计数中，也不由本包主validator自动认证。D4-T15通过只表示平台台账诚实完整；未跑X矩阵的平台仍不可标原生verified。

## 4. Shell / AI 范围

本地zsh与已协商远端Bash4+/Zsh是本轮首先核查的已有路径；Bash/fish/特殊Shell本地提交、远端文件补全/历史不可凭一般终端支持推断。无可信bridge可编辑/复制或Raw回退，不盲打清行/Enter。

API与本地ACP的配置、真实连接、任务与审阅分别记录。ACP进程在桌面本地，即使终端是SSH；没有远程ACP网关支持声明。历史文档中的adapter/model版本只作为历史基线，实施使用当前明确可用版本并记录实际返回信息。

## 5. macOS版本与架构

按最新 `docs/APPLE_PLATFORM_COMPATIBILITY.md` 和实际Xcode部署目标核对支持窗口。本包不另造OS清单，不把最高版本测试代表所有支持版本。记录不同OS/arm64/x64的实际测试与缺口；无法取得旧系统就标未验证，不跨OS复制golden。

真实物理键盘/触摸板、多显示器与性能项目需相应实际设备；VM可以补验证原生host/功能，但不证明物理设备体验。显示器最高规格也不等于测量时实际刷新率。
