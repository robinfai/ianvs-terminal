# Ianvs Terminal product site

Ianvs Terminal 的静态产品官网，发布于 `gh-pages` 分支。暖白与墨绿两套主题覆盖全部六个页面，默认跟随系统，并记住用户的选择。

## 本地预览

在本分支根目录运行：

```bash
python3 -m http.server 4312 --bind 127.0.0.1
```

打开 http://127.0.0.1:4312/ 。无需 npm、外部 CDN 或线上构建步骤。

## 页面与交互

- `/`：产品概览，本地 / SSH / 回看工作流演示。
- `/features/`：会话布局、回看与录制、本地存储、可选配置同步。
- `/technology/`：架构与 Flutter 嵌入入口。
- `/osc/`：协议搜索、分类筛选、空状态与可恢复查询链接。
- `/roadmap/`：产品进展与平台支持状态。
- `/open-source/`：源码运行步骤、命令复制与常见问题。

原有页面路径、功能及技术锚点和图像资源保留。终端演示仅展示工作流，不执行命令或建立连接。使用相对资源路径，可直接托管于 GitHub Pages 项目子路径。

## 编辑

- `tools/build_site.py`：页面内容与公共 HTML。
- `assets/styles.css`：主题变量与响应式布局。
- `assets/theme.js`：首屏主题与持久化。
- `assets/app.js`：导航、演示、复制和协议筛选。

更新内容后重新生成 HTML：

```bash
python3 tools/build_site.py
```

生成后的 HTML 与源文件一起提交。

## 验证

```bash
python3 tools/validate_site.py
node --check assets/theme.js
node --check assets/app.js
node tools/test_interactions.cjs
python3 tools/check_contrast.py
```

校验覆盖页面结构、本地资源与锚点、主题及交互事件、协议筛选和文字颜色对比度。另需在浏览器检查桌面与窄屏布局、明暗主题、键盘操作和控制台错误。

## 产品内容依据

功能介绍依据主分支 `README.md`、`docs/TERMINAL_PRODUCT_SCOPE.md`、`docs/CURRENT_EXECUTION_TARGET.md`、`packages/ianvs_terminal_core/README.md`、协议矩阵和 Shell 集成文档维护。

macOS 为主交付平台；iOS 与其他平台按实际支持状态描述。API 仅提供可选配置同步，终端布局和录制保留在本机。产品能力变化时，应同时更新官网文案与对应文档链接。
