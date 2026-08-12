# Ianvs Data API

该目录是 Ianvs Terminal 的统一持久化服务。相同的 Go 二进制和 GORM 模型运行于两种模式：

- `local`：默认绑定 `127.0.0.1:47832`，保留一个本地用户，默认 SQLite。
- `remote`：Bearer 登录后的多用户服务，可使用 SQLite 或 MySQL。

业务 CRUD 和事务通过 GORM 完成；并发初始化锁、数据库时钟和 current schema 结构指纹使用少量受控的 SQLite/MySQL 方言 SQL。数据层不依赖数据库 JSON 类型、upsert 方言或数据库触发器；JSON 使用普通文本列，便于 SQLite/MySQL 共用 schema。项目尚未发布，服务只接受唯一的 current schema；遇到旧库或旧 JSON 时会拒绝启动，不在产品代码中迁移旧格式。

## 数据与安全边界

| 内容 | 存储方式 |
|---|---|
| 用户密码 | bcrypt 哈希 |
| 用户创建的数据密钥 | 不保存；只保存 Argon2id 盐与校验值 |
| SSH 密码、私钥口令、X11 cookie、粘贴历史、最近路径、session relaunch 文档 | AES-256-GCM 密文 |
| profile 名称、主机、主题、普通偏好和配置 | 明文 JSON 文本 |
| Bearer token | 客户端持有原值，数据库只保存 SHA-256 摘要 |

每个密文都绑定 `user + kind + resource id` 作为认证数据，不能被复制到其他用户或资源后继续解密。远程模式默认要求 TLS；如果 TLS 在反向代理终止，需在 JSON 配置中显式设置 `trust_proxy_headers: true`，并确保外部请求不能绕过代理直连服务。

数据密钥没有服务端恢复通道：丢失密钥后既有敏感字段无法解密。客户端应把 16–1024 字节的随机密钥备份到受保护的凭据存储。密钥合同 v1 只允许首次创建和同密钥验证；重复 setup/register 不能更换密钥，服务也不提供恢复或在线轮换。完整决策与未来 old+new key 全量重加密要求见 [ADR-0004](../docs/DECISIONS/ADR-0004-data-api-key-lifecycle-v1.md)。

## 本地运行

macOS 主应用无需手工运行本节命令：构建阶段会把 `ianvs-api` 放入应用包。在应用的 **Defaults & appearance → Data service** 选择本地服务后，主应用会在下次启动时以随机回环端口运行它。每次 sidecar 启动都会生成新的 32 字节随机 Bearer token，token 只存在于当前进程及启动期私有配置中，不写入 Keychain 或持久文件；后端报告 READY 后配置立即删除。独立的本地数据加密密钥继续保存在 macOS 登录 Keychain，以保证重启后仍能解密既有敏感资源。正常退出会主动关闭服务，主进程意外结束造成的 stdin 断开也会让服务自行退出。

下面的命令用于独立开发和调试：

```bash
cd backend
go mod download
go run ./cmd/ianvs-api generate-key
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

将 `generate-key` 生成的数据密钥保存在客户端安全存储中，然后只需初始化一次本地用户：

```bash
curl -X POST http://127.0.0.1:47832/v1/auth/setup \
  -H 'Authorization: Bearer <local-access-token>' \
  -H 'Content-Type: application/json' \
  --data '{"encryption_key":"<client-owned-key>"}'
```

本地 SQLite 路径由配置文件的 `database_dsn` 显式指定。

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
`allow_registration` 显式改为 `true`，首次用户注册时同时创建登录密码和独立数据密钥：

```bash
curl -X POST https://api.example.com/v1/auth/register/begin \
  -H 'Content-Type: application/json' \
  --data '{"username":"alice","password":"<at-least-12-characters>","encryption_key":"<client-owned-key>"}'
```

begin 响应只创建账号与短期 `prepared` operation，不签发 token。客户端必须先把服务端返回的 `operation_id` 持久写入恢复 journal，再提交：

```text
POST /v1/auth/register/complete  {"operation_id":"<server-issued-capability>"}
POST /v1/auth/login/begin        {"username":"alice","password":"..."}
POST /v1/auth/login/complete     {"operation_id":"<server-issued-capability>"}
```

只有 complete 才在同一数据库事务中把 operation 从 `prepared` 改为 `issued` 并创建 token。complete 响应丢失时，客户端用 journal 中同一 capability 调用 `POST /v1/auth/cancel-operation`；它会取消已有 operation 并撤销关联 token。未知或重复 cancel 返回 204 且绝不创建数据库 tombstone。服务端签发的 `operation_id` 是 32 字节随机、无填充 base64url 的撤销能力，不得作为请求关联 ID、URL 参数或日志字段。注册 begin 响应丢失可能留下无 token 账号，用户可用相同凭据经 login 流程恢复。

访问敏感数据时，客户端还必须通过 `X-Ianvs-Encryption-Key` 提供自己的数据密钥；登录密码不能替代数据密钥。

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

`data` 明文保存；`sensitive` 整体加密。省略 `sensitive` 会保留原密文，`clear_sensitive: true` 才会清除它。`expected_revision` 可选，用于阻止并发覆盖。读取默认只返回 `has_sensitive`；显式添加 `?include_sensitive=true` 并提供数据密钥才会解密返回。

列表使用按 `kind / resource id / internal id` 排序的 keyset 分页。`limit` 默认为 100，范围 1–100；响应中的 `next_cursor` 存在时必须继续请求下一页。服务端签名的游标会绑定数据库时钟产生的首屏 UTC 创建时间 cutoff、`kind` 与 `include_deleted`，不能篡改或在翻页中切换这些过滤条件；共享数据库的多个 API 实例即使主机时钟偏斜，也不会把首屏请求后新建的资源纳入该次遍历。单页和单资源 JSON 响应上限为 12 MiB；为了保持该上限，实际条数可能少于 `limit`。

建议的 kind：`profile`、`session`、`config`、`theme`、`layout_template`、`recent_items`、`paste_history`。API 允许增加其他 kind，无需改表。

## 本地到远程单向合并

本地和远程暴露相同的 migration contract：

```text
GET  /v1/migrations/export?include_sensitive=true&limit=100&cursor=<opaque>
POST /v1/migrations/merge
```

每个导出页都可直接提交给 merge，避免在磁盘留下含解密敏感字段的临时 bundle。下面的管道只适用于没有 `next_cursor` 的单页；多页迁移必须逐页读取 cursor，并按页提交：

```bash
curl -sS 'http://127.0.0.1:47832/v1/migrations/export?include_sensitive=true' \
  -H 'X-Ianvs-Encryption-Key: <local-key>' | \
curl -sS -X POST 'https://api.example.com/v1/migrations/merge' \
  -H 'Authorization: Bearer <remote-token>' \
  -H 'X-Ianvs-Encryption-Key: <remote-key>' \
  -H 'Content-Type: application/json' \
  --data-binary @-
```

本地与远程数据密钥可以不同：bundle 在 TLS 通道内传递解密后的敏感 JSON，远程收到后使用目标用户的密钥重新加密。导出与 merge 共用每批最多 100 个资源、编码 JSON 最多 12 MiB 的合同，因此合法导出页不会超过导入上限；每个资源携带 source revision，按页重试仍保持幂等。

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
