# SSH 注入产品实现验收

日期：2026-09-12。结论：生产 Rust SSH、PTY 传输验收通过；Flutter 状态与界面回归通过。实现说明见 [SSH Shell 内存引导](../../protocols/ssh_shell_bootstrap.md)，设计参考见 [Warp 调研](../warp-shell-bootstrap-20260912.md)。

## 实现入口

- 设置 → 常规：本地 SSH 命令包装、SSH 协议连接自动注入，两个独立开关，默认开启。
- SSH 配置 → 高级选项：自动注入继承全局 / 开启 / 关闭，修改只影响新会话。
- 会话能力界面：分别显示检查结果和实际观察到的激活状态；进入和退出 SSH 子层时切换对应能力与文件面板。

## 产品传输验收

运行 `python3 tools/ssh_boundary_lab/product.py --context colima`，直接调用生产 `spawn_terminal_transport` 和 SFTP API。测试宿主为 macOS，远端为固定镜像中的 Ubuntu OpenSSH 9.6，Bash 5.2、Zsh 5.9、Fish 3.7。镜像摘要、包版本及源码摘要记录在 [results.json](results.json)，断言执行记录见 [product-test.log](product-test.log)。

| 场景 | 验证结果 |
| --- | --- |
| Bash / Zsh / Fish，服务端关闭 SFTP | Hook 安装成功，用户命令 `false` 上报退出码 1 |
| 已加载兼容 Hook、残留标记、第三方 DEBUG trap | 分别复用、修复、保留原 trap 并报告冲突 |
| 只读远端、未知 shell、关闭注入 | 只读环境成功；未知 shell 降级；关闭时不启动引导 |
| 提前输入命令 | 等待检查完成后执行，输入不进入引导正文 |
| Connected 时序 | 能力检查消息先于 Connected 文本 |
| Zsh / Fish 继续 SSH 跳转 | 子层完成注入，SFTP 下载确认来自目标主机 |
| 协议 SSH A → B → C、本地 Bash → A → B → C | 各层能力登记和返回恢复；A、B 无 SFTP 时，C 文件通道仍可工作 |
| 文件操作隔离 | 下载、上传及原子替换均命中 C；退出 C 后新请求使用旧 context 会失败，其他主机无误写 |
| 已有 ControlMaster | 复用指定 master；终端关闭后 master 仍通过 `ssh -O check` |
| 历史文件 | 退出后检查 9 个节点，无注入正文；history 节点保存了普通 `false` 命令作为正向对照 |

此 runner 复用边界实验的 20 个节点配置，但只将上表列出的场景作为产品验收。其他节点存在或有 sshd 日志，不代表其边界已经通过产品实现验证。临时密钥、容器和网络已由 runner 清理，镜像保留缓存。

## 自动化回归

- Rust 全量库测试：384 通过，1 项外部夹具测试默认忽略；上述产品验收单独运行该测试并通过。
- Flutter 应用相关回归：224 通过；文件面板检查阶段隐藏调整后，另复跑屏幕与文件面板相关 19 项通过。
- 终端包配置、协议请求和运行时回归：271 通过。
- 变更范围静态分析无新增问题；应用保留 3 项既有 `prefer_initializing_formals` 提示，终端包无问题。Rust 格式检查和 `git diff --check` 通过。
- 新增的本机 PTY 用例验证 Bash/Zsh 的真实历史保存、预加载复用、标记修复、DEBUG trap 冲突；控制协议用例覆盖分片、重复、过期和跨层消息。

Rust 全量使用 `--test-threads=1`：并行执行曾遇到现有进程测试的 PID 文件创建与读取竞争，串行全量通过。验收覆盖实际生产传输和 Flutter widget/state 测试，未将两者合并成连接真实服务器的完整 GUI 自动化，也不代表已经运行所有目标平台。
