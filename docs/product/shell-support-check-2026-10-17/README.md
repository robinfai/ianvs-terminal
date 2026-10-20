# 后台标签 Shell 检测卡住修复

2026-10-17，PR #12，保持 Draft / OPEN，不合并。

## 问题与原因

在用户正在运行的 `/Applications/Trail.app` 中复现：右键未激活的第一个 Local Shell 标签，Block + AI 一直显示“正在检测 Shell 支持…”。点击“重新检查”后再次打开菜单，状态不变。左键激活该标签后，Shell 就绪，Block + AI 恢复可用。排查结束后已返回原先的第 7 个会话，没有发送命令。

后台／恢复的标签可能尚未挂载 ComposerPane，因此没有创建 ComposerPaneSession，也没有启动能力轮询。菜单显示默认的 checking；原重新检查函数遇到不存在的检测器直接返回。不是该本地 Shell 的握手失败。

## 修复

- 打开桌面标签／窗格菜单时，初始化并刷新对应会话的能力检测；新建的检测器以不可输入的后台状态轮询。
- 菜单保持打开时，延迟完成的握手也能更新可用性。
- 显式重新检查和命令面板入口共用同一检查路径，不再因检测器未初始化而静默返回。
- 保留退出／只读限制、真实能力校验、当前活动标签和既有草稿；不直接放行尚不支持的 Shell。
- 一并修正上一提交 CI 的 `directives_ordering`：终端包公共导出语句排序，不改变导出内容。

## 验证

- 新增两项后台标签组件测试在修复前失败：就绪 Shell 未启用、未就绪 Shell 永久 checking。修复后均通过；覆盖菜单打开期间恢复、显式重查、活动标签不变、无输入／新建／关闭副作用及随后进入 Block + AI。
- 相关模式、Composer、桌面融合入口、移动端限制和关闭保护回归 **153 / 153 通过**。
- macOS **27.0.1 (26A434)** 原生集成 **1 / 1 通过**：隔离的真实 zsh，两个连续新建标签中只有最后一个挂载；右键未挂载标签检测成功，重查保持前台标签不变，后台命令块为空。此前的统一输入、历史、草稿与本地 AI 响应验证继续通过。
- 应用及终端包静态分析通过；格式与 diff 检查通过。仓库根目录分析另发现 34 条来自两份已有、未纳入 Git 的 `build/` UI 评审临时脚本的提示，本次未改动这些产物；本次修改的源文件无诊断。
- 原生测试日志中的 `Failed to foreground app` 是测试应用无法抢占前台的提示，测试正常执行并通过。
- macOS 生产入口 Release 构建通过，产物为 `example/build/macos/Build/Products/Release/Trail.app`。
- 本轮未覆盖其他操作系统的原生运行，也未替换当前运行的 Trail。

日志见 [evidence](https://github.com/robinfai/ianvs-terminal/tree/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/shell-support-check-2026-10-17/evidence)。

历史验收原件保留在[固定提交目录](https://github.com/robinfai/ianvs-terminal/tree/cbebe0244b554f99084100e9bda465d8f87ac83f/docs/product/shell-support-check-2026-10-17)。运行日志和临时产物已按文档归档规则移出当前 `docs/`；此处结果仅对应文中记录的构建与环境。
