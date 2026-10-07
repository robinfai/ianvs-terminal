# UI 回归核对：2026-10-03

首次全量测试产生 24 项失败。逐项核对源码、测试日志和截图后，仅修正测试
操作、语义预期和已确认的截图基线，未为通过测试改变生产行为。

## 交互测试：13 项

- Tab 语义已显式提供点击动作。旧 `matchesSemantics` 默认不接受此动作，
  更新为要求 `hasTapAction: true`，保留选中状态与按钮角色断言。
- 面板菜单增加模式切换等项目后，关闭项超出测试窗口可视区域。点击前
  使用 `ensureVisible` 滚动菜单，继续验证关闭原始目标、分屏及搜索状态。
- SSH 255 断连保留已退出页面与输出历史。原测试仍要求自动关闭；现验证
  原生会话尚未释放、页面处于退出状态、错误及语义提示可见，然后通过
  Tab 关闭按钮确认历史页面和原生会话被释放。

## 截图测试：11 项

逐张查看测试图，并核对基线和差异图。更新范围如下：

| 截图 | 确认的变化 |
|---|---|
| 深色、浅色常规设置，以及设置 Tab 常规页 | 增加优先终端模式选项，下方内容随滚动区域顺延 |
| 紧凑设置页 | 同一设置项及平台默认说明；底部操作区保持固定 |
| Profile 下拉菜单 | 新增设置卡片在底部滚动裁剪边界露出少量圆角 |
| 桌面终端、命令面板、Profiles 面板 | 新增 AI 入口，移除旧的底部 Composer 入口 |
| 深色、浅色四分屏及窄窗口 | 同上；释放原 Composer 底栏占据的终端高度 |

没有提高像素误差阈值或批量接受未经查看的差异。原始差异图留在本机
`tmp/acp-runtime/reviewed-ui-differences/`。

## 结果

- `flutter test --reporter expanded`：2412 通过、0 失败、2 跳过。
- `flutter analyze`：No issues found。
- 环境：macOS 27.0.1（26A434）。
- 本次为自动化 widget/golden 验证；没有把它声称为真实 UI 操作或 VoiceOver 验收。
- 最终日志：`tmp/acp-runtime/application-completion-tests.log` 与
  `tmp/acp-runtime/application-completion-analysis.log`。
