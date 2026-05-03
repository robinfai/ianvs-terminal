# Warp Alignment Snapshots

本目录只保存 Ianvs Terminal 自己的截图工件，不复制 Warp 图片。

Warp 参考基线：

- 语义：`Launch Configurations (Legacy)`  
  `https://docs.warp.dev/terminal/sessions/launch-configurations`
- 视觉：`Tab Configs`  
  `https://docs.warp.dev/terminal/windows/tab-configs/`
- 相关截图文件名：
  - `save-new-tab-config.png`
  - `saved-tab-config-menu.png`

Ianvs 截图工件：

- `launch_config_compose.png`
- `launch_config_success.png`

生成命令：

```bash
flutter test test/launch_config_golden_test.dart --update-goldens
```

对照结论：

- 当前 Ianvs 导出面板已经从 path-first 表单收口成 name-first 保存流，主标题、命名输入、路径预览、主 CTA 和 success state 都在同一个大 modal 里完成，层级接近 Warp 文档截图的保存节奏。
- `launch_config_compose.png` 对齐的是 Warp `Tab Configs` 截图的视觉重点：保存入口不再是单纯 JSON path，首屏先强调命名、主按钮和当前 snapshot 摘要；Ianvs 额外保留了 app-level window / tab / pane 统计与 startup command 编辑，这是为了匹配 Ianvs 的应用导出语义。
- `launch_config_success.png` 对齐的是 Warp `LaunchConfigSaveModal` 源码里的 `NotSaved -> Success` 流：保存后不直接消失，而是留在模态内显示文件结果，并提供继续验证的动作。Ianvs 这里用 `Apply saved app`、`Copy path`、`Done`，没有照搬 Warp 的 `Open file`。
- 以布局层级、主 CTA 优先级、信息密度和保存成功反馈来判断，这组 Ianvs 截图可以视为达到约 `80%` 的相似度。

仍然保留的差异：

- Ianvs 还没有 Warp `saved-tab-config-menu.png` 那种 `+` 菜单里的 saved config sidecar，也没有 `Make default` / `Remove` / `Edit config` 这类发现入口。
- Ianvs 保留了显式 `Advanced path`，因为当前产品仍需要可控地导出 app-level JSON 文件；Warp 文档截图更偏日常保存入口，而不是 Ianvs 当前这条导出任务的全部约束。
- Ianvs 不复制 Warp 品牌、图标、文案和菜单结构，只对齐交互层级与保存节奏。

![Launch Config Compose](./launch_config_compose.png)

![Launch Config Success](./launch_config_success.png)
