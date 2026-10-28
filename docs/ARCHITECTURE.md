# ianvs terminal Architecture

这份文档只回答一个问题：当前仓库里，哪一层负责什么。

## 工作区分层

- `packages/ianvs_pty`
  - 负责 PTY 会话传输和 FFI 包装
  - 对上层公开 `PtySessionBackend`、`PtyEvent`、`PtyBindings`、`NativePtyBackend`
  - 封装当前 ABI 的会话、事件、帧与图形资产传输；运行能力由 Runtime Capabilities v1 和 ABI manifest 共同约束
- `packages/ianvs_terminal`
  - 依赖 `ianvs_pty`
  - 负责 `TerminalSessionConfig`、`TerminalLaunchConfig`、`TerminalDisplayConfig`
  - 负责 `TerminalRuntimeController`、`TerminalSessionEvent`
  - 负责 viewport、输入编码、选区、滚动和焦点相关适配
- `packages/ianvs_terminal_core`
  - 是面向第三方 Flutter 应用发布的 standalone package
  - terminal、PTY 和 native 实现由 canonical 源确定性生成，不维护第二套协议或 ABI
  - 手写范围只包含嵌入组件、公开 barrel、发布元数据和 build hook
- `example/`
  - 负责 tab/pane、窗口壳、菜单、Profile、SSH/SFTP、defaults、录制库与可选配置同步
  - 将产品 Profile 与凭据组装为 `TerminalSessionConfig`，不把产品元数据写入 native wire
  - 通过 `features/terminal/terminal.dart` 和 `features/pty/pty.dart` 消费 package
  - 平台桥接（例如系统剪贴板）留在 `example/lib/platform/`
  - 不再定义 PTY/terminal 共享能力
- `native/core`
  - 负责 Rust PTY、VT 解析、frame diff、事件输出
  - 当前仍保留原位置，不为目录整齐额外搬 Rust 源码
- `backend`
  - 使用 Go、GORM 和同一套资源模型提供本地/远程 REST API
  - 本地模式是一名保留用户 + SQLite；远程模式是登录后的多用户 + SQLite/MySQL
  - profile、session relaunch 和配置数据使用普通文本列保存 JSON，不依赖数据库 JSON 类型
  - 主密钥只保存在客户端；服务端不接收或验证密钥，只保存客户端生成的 AES-256-GCM 不透明信封
  - 显式 API export/merge 与客户端迁移器提供独立的数据迁移合同；应用始终本地优先，通过可选 API 做双向配置同步，冲突由用户选择
  - Terminal Layout、粘贴历史和录制留在本机，不进入应用的 API 同步集合

## 公开接口

### `ianvs_pty`

- `PtySessionBackend`
- `PtySessionConfigV1Backend`
- `PtyReplaySessionConfigV1Backend`
- `PtySessionRequestV1Backend`
- `PtySessionRequestV1`
- `PtySessionResponseV1`
- `PtyBindings`
- `PtyEvent`
- `NativePtyBackend`

这里不暴露 tab、profile、viewport 这些 app 词汇。

### `ianvs_terminal`

- `TerminalSessionConfig`
- `TerminalSessionConfigV1`
- `TerminalLaunchConfig`
- `TerminalDisplayConfig`
- `TerminalRuntimeController`
- `TerminalSessionEvent`
- `TerminalViewport`
- `TerminalViewportController`

这里不暴露 `Profile` 这个 app 词汇。session create 只接受有版本、带上限且字段和值
均严格校验的 SessionConfig v1；缺字段、未知字段、错误大小写和未来 schema 全部拒绝。
通用 session command 只发送有关联 identity 的 Session Request/Response v1，不回退到
旧 `{kind, ...payload}` JSON。operation-specific client 仍拥有各自 payload 和返回语义。
native-to-product 的 Host Request/Response v1 只承载确实需要关联响应的 child 请求；
当前首个 operation 是 OSC 52 `clipboard.read_text`。URL、attention、notification 和
asset transfer 继续保持单向事件或专用通道，不因名字里带 request 就自动归入双向合同。
Frame/Session 运行指标只使用 Runtime Envelope v1 的 Diagnostic Event 专用形态。
`terminal.export_diagnostics` 的隐私证据包是独立合同，
不因运行指标迁移而改变。高频 Frame 主路径优先使用带 session identity、sequence 和
timestamp 的 Protobuf Frame Packet v1；只有成功解码和接受的序号才会被确认，确认漂移由
native Snapshot 重同步。旧 Frame Protobuf/JSON 符号不属于当前 ABI。decoded RGBA 资产
传输只使用原子 Graphic Asset Packet v1；Dart 校验 session/asset/version、尺寸和
100 MiB 上限，不回退到旧 meta/copy symbols。

### `ianvs_terminal_core`

第三方应用只依赖可发布的 `ianvs_terminal_core`。它公开 current terminal runtime、
`TerminalSessionHandle.runtimeSignals`、viewport 和嵌入面板，并通过 CodeAsset hook 打包与
root manifest 完全一致的 `libianvs_core`。仓库内的同步门禁保证 standalone 镜像与
`ianvs_terminal`、`ianvs_pty`、`native/core` 的 canonical 源一致。

### `example/` 本地边界入口

- `example/lib/features/terminal/terminal.dart`
- `example/lib/features/pty/pty.dart`
- `example/lib/platform/clipboard_bridge.dart`

`example` 内部业务代码不再直接散落地 import `ianvs_terminal` / `ianvs_pty`；优先经过这些本地入口收口。这样 package 边界和 app 边界各自只有一个入口面。

## 数据流

创建会话：

1. `example/` 选择一个本地 shell 或 SSH Profile。
2. Profile 与平台凭据组装成 `TerminalSessionConfig`。
3. `TerminalRuntimeController` 把中性的 session config 转成当前 native wire。
4. `ianvs_pty` 通过 FFI 调 Rust。
5. `native/core` 启 PTY、解析输出并生成 frame diff / 事件。

输入与视口：

1. `example/` 把焦点、滚动、键盘、菜单动作交给 `ianvs_terminal`。
2. `ianvs_terminal` 把输入编码成字节或滚动请求。
3. `ianvs_pty` 下发给 Rust。
4. `TerminalRuntimeController` 消费 frame diff / event，驱动 `TerminalViewportController`。

## 搜索快照

原生搜索在 `TerminalSession.capture_search_snapshot()` 内持锁捕获拥有独立文本的
搜索行，同时保存软换行和折叠投影坐标；随后释放锁，再拼接逻辑行并执行匹配。
一次搜索不会混用捕获前后的主屏、alternate screen 或折叠状态，匹配阶段不阻塞
PTY 状态更新。相关回归在 `native/core/src/session/search_snapshot_tests.rs`。

这仍是同步搜索请求，捕获阶段仍需遍历保留历史；尚未引入分页、取消或写时复制。
返回坐标属于捕获时的状态，不能由此推定其在后续 resize、滚动淘汰后仍然有效。

## SSH 传输预算

`native/core/src/ssh/buffer.rs` 在异步 SSH 任务与同步 PTY reader 之间提供
4 MiB 输出队列，实际 `Read` 消费才释放额度；队列外最多保留一个 1 MiB
处理批次，结束诊断另有最多 4 KiB 的保留空间。剩余批次未交付时暂停接收下一条
channel message，消费后继续，本地取消仍独立处理。该预算不包含 russh 自身的
协议窗口和网络缓冲区；明确取消时不承诺排空尚未交付的数据。

普通输入按最多 64 KiB 分片，并共享 1 MiB 队列及在途额度，单条写入还计入
固定开销；大 `write_all` 等待消费推进而不是仅因超过预算被拒绝。
这是同步 Write 合同的背压，不意味着调用线程不会等待远端窗口。
关闭会唤醒等待额度的写入者。Shell bootstrap 回复使用独立预算，避免被等待
初始化完成的用户粘贴占满。异常超大输出批次有明确失败，不静默截断。

队列行为测试位于 `native/core/src/ssh/buffer.rs`；真实 OpenSSH 的慢消费者、
16 MiB 输出完整性及退出码验证由 `tools/ssh_e2e/run.sh` 执行。

## Trigger 输出事件

Profile 触发器消费原生 `output_text` 事件，不再扫描 Frame 的可见行。
会话只有在配置了 Trigger 后才通过当前 Session Request 开启输出观察；后台
窗格也遵循同一规则。每条事件携带独立文本、订阅标识和逻辑行身份，runtime
校验当前订阅与会话 epoch，app 对同一行的同一规则只执行一次。
帧重建、滚动、resize 和回放都不会单独执行通知或发送输入。

观察器保守处理控制序列：光标编辑、图形和超长行不会跨片段拼接成匹配；
事件溢出有诊断，不能把有界观察声明为无损命令审计。启用前的启动输出不追溯，
中途订阅从下一安全行开始；已经执行的 partial 匹配不能被未来输出撤销。
精确字段、限制和测试入口见
[输出观察合同](protocols/SESSION_REQUEST_RESPONSE_V1.md#live-output-observation)。

## 命令发生记录与文件上下文

`CommandOccurrence` 是现有原生命令 Block 的元数据投影，以 runtime 的 session
epoch 和 block ID 标识一次执行，保留 context/submission 关联、执行时目录、
开始结束时间和可空退出码。真实启动传输由 runtime 捕获，shell 声明的主机和
用户名另存为证据；后续 `cd`、Profile 修改或嵌套 shell 不改写旧记录。
Block controller 有界保留元数据，Composer 从同一来源投影当前上下文的历史。
记录仍在不代表原始输出仍在；输出部分淘汰、不可用和未确定分别表示，未知
退出码也不视为成功。该记录不新增持久历史库或 Layout 字段。

终端目标解析优先显式 OSC 8 链接，再识别连续软换行中的 URL；文件候选只在
有明确来源上下文时启用，支持路径和 `:line:column`，以及引号包裹的含空格路径。
相对路径使用输出所属命令捕获的目录，不使用点击时的当前目录。文件操作接在
Block 内联输出、紧凑视图和阅读器，直接使用同一个 Block 快照。普通终端 Frame
携带同锁捕获的 `semantic_snapshot_token`、去重 Block 来源信息和完整视口行归属；
三者在每帧（包括 delta）整体替换，不从异步 Block 列表或预览文本推定文件上下文。
终端写入与 dirty/cache 发布共享状态锁边界，抽帧不能看见新内容配旧 dirty 范围。
点击、右键菜单和异步确认绑定显示帧修订与会话代际；显示帧更新后旧目标失效。
只有整行具有唯一输出归属时才授权文件操作，折叠摘要、填充行、混合归属、
alternate screen、replay 或超出元数据预算均不猜测路径。无上下文的 `file://`
同样不能打开文件。协议边界见 [Frame Packet](protocols/TERMINAL_FRAME_PACKET_V1.md)。
后续光标写入或结构性编辑覆盖旧输出时，其文件来源授权失效；失效状态随快照
保留。软换行中的文件 URI 与普通路径使用相同的跨片段归属检查。
记录查询与输出页面缓存也绑定 session epoch；同名 Block 不能继承旧会话的页面、
选择或阅读状态。包含 `..` 的路径暂不用于语义文件操作，避免词法折叠跨越符号
链接时定位到另一个文件；需要真实文件系统规范化后才能安全支持该情况。

宿主在用户点击时核对会话与传输。远端路径复用 SFTP 面板及已有下载／编辑
能力，不交给本地文件打开器；本地路径继续使用现有确认与系统打开流程。
SFTP 菜单与确认绑定面板位置修订，目录或连接变化后旧授权失效；异步任务轮询和
取消绑定会话代际，不能把旧任务编号用于复用同一 ID 的新会话。
嵌套 SSH 的文件路由还绑定实例凭据，该凭据随命令来源冻结；context ID 再次
使用不会让历史点击或编辑器回传取得新连接的文件权限。
嵌套 host route 缺失时不回退外层 SSH；shell 声明的主机名与 SFTP 端点不一致
且没有别名对应证据时拒绝定位。该保守限制包括部分 IP／DNS／短主机名组合。
解析到行列不等于系统默认应用支持跳转行列，也不代表引入编辑器或工程管理器。

## App 侧终端状态

当前产品状态边界由 [TERMINAL_PRODUCT_SCOPE.md](TERMINAL_PRODUCT_SCOPE.md)
定义：

- `Profile` 提供可复用启动默认值；
- `Session` 拥有 live PTY 和运行态；
- `Terminal Layout` 只保存 tab/pane topology、焦点和最小 Relaunch Spec；
- `Relaunch Spec` 只保存 `profileId` 和可选 `cwd`；启动命令与参数来自当前 Profile；
- `Recording Library` 独立保存录制，不把 recording path 写回重启意图。

`Open Terminal at Folder` 只以所选目录作为新 Session 的初始 `cwd`。它不创建
Project Workspace identity，不切换现有 tab/PTY，也不维护 Recent Workspace。
旧 Workspace v1-v3、project index 和 `workspace` config 不属于当前合同；运行时不发现、迁移、删除或重新创建这些数据。

## 不属于 package 的内容

以下能力明确留在 `example/`：

- tab 生命周期和排序
- 窗口标题与窗口壳
- launcher / command menu
- 系统剪贴板桥接
- defaults / appearance UI
- profile 编辑器
- `reference_demo.dart` 和其他 demo fixture

## 当前约束

- `native/core` 只接受 current SessionConfig v1、Session Request/Response v1、Runtime
  Envelope v1、Frame Packet v1 和 Graphic Asset Packet v1；不存在 predecessor 降级链。
- Host Request/Response v1 承载需要关联响应的 child 请求；事件和命令不通过旧 JSON
  facade 旁路。
- 实际构建的动态库导出必须与 `ianvs_core_abi_v1.json` 中的 `ianvs_*` 函数精确一致；
  workspace native 与 standalone package native 都执行同一门禁。
- `example/` 目录里的 Flutter package 现阶段仍保留 `name: app`，这是为了稳定既有 `package:app/...` import 面；macOS bundle identity 由 Runner project 单独维护。
- `ianvs_terminal_core` 是 pub.dev 发布入口；workspace packages 仍是 canonical 开发源。
- SSH 已作为 Profile/Session 扩展实现，SFTP 复用 SSH 连接配置；它们不恢复 Project Workspace。
- Toolbelt 和旧 completion/wiring 产品面板已退役；历史验证模型仅用于工程回归，用户诊断导出保持独立。
- 新的可选 [Composer](composer/README.md) 是 Session 内的独立草稿组件；纯 Rust matcher、受限本地 provider 与私有 ZLE 通道分层，通过当前 Session Request v1 接入，不恢复旧面板或 ABI。

## 模块代码与文档入口

| 模块 | 当前实现入口 | 权威文档 |
| --- | --- | --- |
| PTY / native wire | `packages/ianvs_pty/lib`、`native/core/src` | [PTY README](../packages/ianvs_pty/README.md)、[wire 清单](protocols/RUNTIME_WIRE_INVENTORY.md) |
| runtime / viewport / recording codec | `packages/ianvs_terminal/lib` | [Terminal README](../packages/ianvs_terminal/README.md)、[录制格式](recording/FORMAT_CURRENT.md) |
| standalone 发布包 | `packages/ianvs_terminal_core`、`tools/sync_terminal_core.dart` | [Core README](../packages/ianvs_terminal_core/README.md) |
| Shell / Session / Profile / Layout / SSH / SFTP | `example/lib/features` | [产品范围](TERMINAL_PRODUCT_SCOPE.md)、[App README](../example/README.md) |
| 本地存储 / 可选同步 / 凭据 | `example/lib/persistence_repository_composition.dart`、`example/lib/data` | [持久化合同](DATA_API_PERSISTENCE.md) |
| 数据 API / Web 管理端 | `backend/internal`、`backend/webui` | [Backend README](../backend/README.md)、[OpenAPI](../backend/openapi.yaml) |
| 构建 / 验证 | `Makefile`、`tools`、`test` | [测试入口](TESTING.md) |

版本依据是工作区当前源代码、ABI/schema 与对应测试。过期任务与验收产物不保存在 docs；当前运行结果写入 build，不能凭历史结果宣称当前 checkout 已通过验证。
有效的终端标准兼容、密钥迁移和显式 API 迁移路径各有实际消费者，不能因包含
legacy/compatibility 字样就删除；废弃产品模型和旧 native ABI 不因此恢复。
