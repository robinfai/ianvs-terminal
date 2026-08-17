# Ianvs Data API

该目录是 Ianvs Terminal 的统一持久化服务。相同的 Go 二进制和 GORM 模型运行于两种模式：

- `local`：默认绑定 `127.0.0.1:47832`，保留一个本地用户，默认 SQLite。
- `remote`：Bearer 登录后的多用户服务，可使用 SQLite 或 MySQL。

业务 CRUD 和事务通过 GORM 完成；并发初始化锁、数据库时钟和 current schema 结构指纹使用少量受控的 SQLite/MySQL 方言 SQL。数据层不依赖数据库 JSON 类型、upsert 方言或数据库触发器；JSON 使用普通文本列，便于 SQLite/MySQL 共用 schema。项目尚未发布，服务只接受唯一的 current schema；遇到旧库或旧 JSON 时会拒绝启动，不在产品代码中迁移旧格式。

## 数据与安全边界

| 内容 | 存储方式 |
|---|---|
| 用户密码 | bcrypt 哈希 |
| 客户端主密钥 | 仅保存在客户端 Keychain；服务端不接收、不派生、不验证、不保存 |
| SSH 密码、私钥口令、X11 cookie、粘贴历史、最近路径、session relaunch 文档 | 客户端生成的 AES-256-GCM 信封；服务端按不透明 JSON 保存 |
| profile 名称、主机、主题、普通偏好和配置 | 明文 JSON 文本 |
| Bearer token | 客户端持有原值，数据库只保存 SHA-256 摘要 |

每个密文都绑定 `user + kind + resource id` 作为认证数据，不能被复制到其他用户或资源后继续解密。远程模式默认要求 TLS；如果 TLS 在反向代理终止，需在 JSON 配置中显式设置 `trust_proxy_headers: true`，并确保外部请求不能绕过代理直连服务。

主密钥没有服务端恢复通道：丢失密钥后既有敏感字段无法解密。Flutter 客户端把随机主密钥保存在同步 Apple Keychain 中；注册、登录和资源请求都不发送该密钥。错误密钥或损坏密文只会产生本地认证失败，HTTP 401 只表示账号或 Bearer token 认证失败。完整决策见 [ADR-0004](../docs/DECISIONS/ADR-0004-client-side-sensitive-encryption.md)。

## 本地运行

macOS 主应用无需手工运行本节命令：构建阶段会把 `ianvs-api` 放入应用包。在应用的 **Defaults & appearance → Data service** 选择本地服务后，主应用会在下次启动时以随机回环端口运行它。每次 sidecar 启动都会生成新的 32 字节随机 Bearer token，token 只存在于当前进程及启动期私有配置中，不写入 Keychain 或持久文件；后端报告 READY 后配置立即删除。独立的本地数据加密密钥继续保存在 macOS 登录 Keychain，以保证重启后仍能解密既有敏感资源。正常退出会主动关闭服务，主进程意外结束造成的 stdin 断开也会让服务自行退出。

下面的命令用于独立开发和调试：

```bash
cd backend
go mod download
make -C .. backend-generate-key
```

服务运行配置只从显式 JSON 文件读取，不读取父进程环境变量。`serve` 当前只支持具有 Unix 文件权限语义的平台；Windows 会 fail-closed。主应用会创建权限为 `0600` 的临时配置；独立调试可创建如下文件。示例 token 是 32 字节 ASCII 经无填充 base64url 编码后的合法非生产值，部署时必须替换为 CSPRNG 生成的 32 随机字节：

```json
{
  "schema_version": 1,
  "mode": "local",
  "address": "127.0.0.1:47832",
  "database_driver": "sqlite",
  "database_dsn": "/absolute/application-support/ianvs.db",
  "local_access_token": "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY",
  "exit_on_stdin_close": false,
  "auth_token_ttl_seconds": 86400,
  "allow_registration": false,
  "allow_insecure_sensitive_transport": false,
  "trust_proxy_headers": false
}
```

配置包含访问令牌或数据库凭据时必须为普通文件，最大 64 KiB；Unix 上权限必须精确为 `0600` 或只读的 `0400`。然后启动：

```bash
chmod 0600 /absolute/path/to/ianvs-api-config.json
go run ./cmd/ianvs-api serve --config /absolute/path/to/ianvs-api-config.json
```

本地 SQLite 路径由配置文件的 `database_dsn` 显式指定。主密钥由 Flutter
客户端生成并保存在 Keychain；服务端没有生成、初始化或验证密钥的接口。

## 远程运行

SQLite 适合单实例、小规模部署。远程配置示例：

```json
{
  "schema_version": 1,
  "mode": "remote",
  "address": "0.0.0.0:47832",
  "database_driver": "sqlite",
  "database_dsn": "/var/lib/ianvs/ianvs.db",
  "local_access_token": "",
  "exit_on_stdin_close": false,
  "auth_token_ttl_seconds": 86400,
  "allow_registration": false,
  "allow_insecure_sensitive_transport": false,
  "trust_proxy_headers": true
}
```

将配置保存为权限 `0600` 或 `0400` 的文件后运行 `./ianvs-api serve --config /absolute/path/to/ianvs-api-config.json`。

MySQL 只需在同一 JSON 中切换 driver 和 DSN，业务代码及 current schema 不变：

```json
{
  "schema_version": 1,
  "mode": "remote",
  "address": "0.0.0.0:47832",
  "database_driver": "mysql",
  "database_dsn": "ianvs:<password>@tcp(mysql.example:3306)/ianvs?charset=utf8mb4&parseTime=True&loc=UTC",
  "local_access_token": "",
  "exit_on_stdin_close": false,
  "auth_token_ttl_seconds": 86400,
  "allow_registration": false,
  "allow_insecure_sensitive_transport": false,
  "trust_proxy_headers": true
}
```

仓库也提供仅绑定本机回环地址的开发组合：

```bash
IANVS_API_CONFIG_FILE='/absolute/path/to/ianvs-api-config.json' \
IANVS_MYSQL_PASSWORD='<dev-password>' IANVS_MYSQL_ROOT_PASSWORD='<dev-root-password>' \
  docker compose -f compose.mysql.yaml up --build
```

这里的 API 配置文件需使用上面的 MySQL 形式，并把主机名设为 Compose 服务名 `mysql`。Compose 只把宿主 `0400`/`0600` 文件只读挂载到固定入口；容器的 root entrypoint 将其复制为 root 不可遍历写入、`ianvs` 可读的私有 `0400` 文件，然后通过 `su-exec` 降权运行 API。DSN、token 和运行选项不会进入 API 进程环境，argv 只包含容器私有配置路径。

该组合为了本机反向代理/测试显式允许 HTTP，不应直接作为公网部署配置。

远程注册默认关闭。管理员只应在受控注册窗口把配置文件中的
`allow_registration` 显式改为 `true`。注册只创建账号密码，不接收数据密钥：

```bash
curl -X POST https://api.example.com/v1/auth/register/begin \
  -H 'Content-Type: application/json' \
  --data '{"username":"alice","password":"<at-least-12-characters>"}'
```

begin 响应只创建账号与短期 `prepared` operation，不签发 token。客户端必须先把服务端返回的 `operation_id` 持久写入恢复 journal，再提交：

```text
POST /v1/auth/register/complete  {"operation_id":"<server-issued-capability>"}
POST /v1/auth/login/begin        {"username":"alice","password":"..."}
POST /v1/auth/login/complete     {"operation_id":"<server-issued-capability>"}
```

只有 complete 才在同一数据库事务中把 operation 从 `prepared` 改为 `issued` 并创建 token。complete 响应丢失时，客户端用 journal 中同一 capability 调用 `POST /v1/auth/cancel-operation`；它会取消已有 operation 并撤销关联 token。未知或重复 cancel 返回 204 且绝不创建数据库 tombstone。服务端签发的 `operation_id` 是 32 字节随机、无填充 base64url 的撤销能力，不得作为请求关联 ID、URL 参数或日志字段。注册 begin 响应丢失可能留下无 token 账号，用户可用相同凭据经 login 流程恢复。

登录和 Bearer 会话只负责身份认证。敏感 JSON 由客户端在上传前使用本地主密钥
进行 AEAD 加密，服务端只保存不透明 envelope；下载后的解密与 MAC 校验也只在
客户端执行。密钥不会出现在 HTTP header、body、用户表或服务端日志中。因此
401 只表示账号或 token 认证失败，错误密钥表现为客户端本地认证失败。

## Web 控制台

`ianvs-api` 二进制内嵌了一个 React 构建的 SSH Profile 管理站点（源码在 `backend/webui/src`，构建产物提交到 `backend/webui/dist` 并通过 Go `embed` 提供）。服务启动后直接用浏览器打开服务地址即可使用：

- 根路径 `/` 返回单页应用，未知非 API 路径回退到 `index.html`，支持前端导航与深链接；
- `/healthz` 与 `/v1/*` 仍是纯 JSON API，不会被静态资源处理器遮蔽；
- 内容哈希资源（`/assets/*`）永久缓存，`index.html` 不缓存；
- 登录页的静态资源无需认证即可加载，但所有数据端点仍受本地访问令牌或 Bearer 会话令牌保护。

站点首屏是终端风格的认证表单。远程登录与注册只要求用户名和密码，本地 sidecar 登录只要求本地访问令牌；登录和会话恢复都不会请求、校验或发送加密 key。只有用户保存敏感字段、重写已有密文或主动解密时才弹出 key 输入框，key 仅保留在当前页面内存中。登录后只展示 SSH profile 与会话安全页，可浏览、创建、编辑、删除 SSH profile，并按需查看敏感字段。Web 与 Flutter 客户端共享 `profile/default` canonical 文档合同；非 SSH profile 会被原样保留。SSH 私钥通过文件选择读取，浏览器界面只记录所选文件名，持久化时保存私钥内容；私钥内容、密码、私钥口令、X11 cookie 与 ProxyJump 密码始终留在客户端生成的 AES-GCM `sensitive` envelope 中。

```bash
cd backend/webui
pnpm install --frozen-lockfile
pnpm build        # 产出 dist/，go build 会将其嵌入二进制

make webui-e2e    # 构建前后端并跑 Playwright 端到端验收
```

端到端验收脚本 `tools/verify_data_api_webui.sh` 会构建前端与 `ianvs-api`，分别启动 local 与 remote（开发 HTTP）两个临时 SQLite 实例，再用真实 Chrome 验证无 key 登录、敏感操作按需请求 key、错误 key 拒绝、SSH profile 创建/查看/解密/编辑/删除、退出与重新登录等流程；用例位于 `backend/webui/e2e/tests`。`pnpm test:unit` 与 Flutter 的 Web UI profile 合同测试共同验证 canonical 文档及递归敏感字段分离。

## 资源 API

所有持久化对象使用稳定的 `kind/id`。两者都是 canonical lowercase 标识符，必须匹配 `[a-z0-9][a-z0-9._:-]*`；该合同保证 SQLite 与 MySQL 在唯一性、查找和游标排序上的语义一致：

```text
GET    /v1/resources?kind=profile&limit=100&cursor=<opaque>
GET    /v1/resources/{kind}/{id}
PUT    /v1/resources/{kind}/{id}
DELETE /v1/resources/{kind}/{id}
```

写入示例：

```json
{
  "data": {
    "name": "Production",
    "connection": {"type": "ssh", "host": "prod.example.com"}
  },
  "sensitive": {
    "connection": {"password": "secret"}
  },
  "expected_revision": 3
}
```

`data` 明文保存；`sensitive` 整体加密。省略 `sensitive` 会保留原密文，`clear_sensitive: true` 才会清除它。`expected_revision` 可选，用于阻止并发覆盖；值为 `0` 时只在逻辑资源不存在时创建，已删除的 tombstone 可由一个并发创建者安全重建。读取默认只返回 `has_sensitive`；显式添加 `?include_sensitive=true` 并提供数据密钥才会解密返回。

列表使用按 `kind / resource id / internal id` 排序的 keyset 分页。`limit` 默认为 100，范围 1–100；响应中的 `next_cursor` 存在时必须继续请求下一页。服务端签名的游标会绑定数据库时钟产生的首屏 UTC 创建时间 cutoff、`kind` 与 `include_deleted`，不能篡改或在翻页中切换这些过滤条件；共享数据库的多个 API 实例即使主机时钟偏斜，也不会把首屏请求后新建的资源纳入该次遍历。单页和单资源 JSON 响应上限为 12 MiB；为了保持该上限，实际条数可能少于 `limit`。

建议的 kind：`profile`、`session`、`config`、`theme`、`layout_template`、`recent_items`、`paste_history`。API 允许增加其他 kind，无需改表。

## 本地到远程单向合并

本地和远程暴露相同的 migration contract：

```text
GET  /v1/migrations/export?include_sensitive=true&limit=100&cursor=<opaque>
POST /v1/migrations/merge
```

服务端导出和 merge 只传递不透明客户端密文。客户端迁移器会在内存中用源账号
上下文解密，再按目标账号上下文重新加密；不能再用 curl 管道完成需要敏感字段
的跨账号迁移。无敏感字段的 bundle 仍可直接提交。多页迁移必须逐页读取
cursor，并按页提交。

导出与 merge 共用每批最多 100 个资源、编码 JSON 最多 12 MiB 的合同，因此合法导出页不会超过导入上限；每个资源携带 source revision，按页重试仍保持幂等。

默认冲突策略为 `preserve_destination`：新资源创建；已有资源仅在 `source_id` 与当前来源一致且 `source_revision` 严格递增时原子更新；更低的同源 revision 与内容完全一致的同 revision 重放会跳过，同 revision 但普通或敏感内容不同则报告 `conflict`；其他来源对同一资源的内容变更同样保留目标端并报告 `conflict`。同源高 revision 会一起更新普通字段和显式提供的敏感字段，省略敏感字段仍保留现有密文。显式迁移工具也可提交 `source_wins` 或 `newer_wins`。删除默认不传播，只有 `propagate_deletes: true` 才应用 tombstone。

## 配置合同

`serve` 必须且只能通过 `--config <path>` 接收一个 current JSON 配置。所有字段必填，未知字段、重复字段、尾随 JSON、非 current `schema_version`、超限值和不安全的文件权限都会被拒绝；没有环境变量或旧格式回退。

| JSON 字段 | 合同 |
|---|---|
| `schema_version` | 必须为 `1` |
| `mode` | `local` 或 `remote` |
| `address` | 1–255 字节的 `host:port`；local 必须是数值 loopback |
| `database_driver` | `sqlite` 或 `mysql` |
| `database_dsn` | 1–8192 字节；可含凭据，因此不得放在 argv |
| `local_access_token` | local 必须是 32 随机字节的 canonical 无填充 base64url（精确 43 字符）；remote 必须为空 |
| `exit_on_stdin_close` | 是否在父进程 stdin 关闭时优雅停止 |
| `auth_token_ttl_seconds` | `1..2592000` |
| `allow_registration` | local 必须为 `false` |
| `allow_insecure_sensitive_transport` | local 必须为 `false`；remote 只限受控开发环境 |
| `trust_proxy_headers` | local 必须为 `false`；remote 仅在可信反向代理隔离直连时启用 |

完整 HTTP contract 见 [openapi.yaml](openapi.yaml)。

## 验证

```bash
go test ./...
go vet ./...
```
