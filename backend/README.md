# Ianvs Data API

该目录是 Ianvs Terminal 的统一持久化服务。相同的 Go 二进制和 GORM 模型运行于两种模式：

- `local`：默认绑定 `127.0.0.1:47832`，保留一个本地用户，默认 SQLite。
- `remote`：Bearer 登录后的多用户服务，可使用 SQLite 或 MySQL。

数据层没有原生 SQL、数据库 JSON 类型、upsert 方言或数据库触发器。所有读写、事务、迁移和条件查询都通过 GORM 完成；JSON 使用普通文本列，便于 SQLite/MySQL 共用 schema。

## 数据与安全边界

| 内容 | 存储方式 |
|---|---|
| 用户密码 | bcrypt 哈希 |
| 用户创建的数据密钥 | 不保存；只保存 Argon2id 盐与校验值 |
| SSH 密码、私钥口令、X11 cookie、粘贴历史、最近路径、session relaunch 文档 | AES-256-GCM 密文 |
| profile 名称、主机、主题、普通偏好和配置 | 明文 JSON 文本 |
| Bearer token | 客户端持有原值，数据库只保存 SHA-256 摘要 |

每个密文都绑定 `user + kind + resource id` 作为认证数据，不能被复制到其他用户或资源后继续解密。远程模式默认要求 TLS；如果 TLS 在反向代理终止，需显式设置 `IANVS_TRUST_PROXY_HEADERS=true`，并确保外部请求不能绕过代理直连服务。

数据密钥没有服务端恢复通道：丢失密钥后既有敏感字段无法解密。客户端应把 16–1024 字节的随机密钥备份到受保护的凭据存储。密钥合同 v1 只允许首次创建和同密钥验证；重复 setup/register 不能更换密钥，服务也不提供恢复或在线轮换。完整决策与未来 old+new key 全量重加密要求见 [ADR-0004](../docs/DECISIONS/ADR-0004-data-api-key-lifecycle-v1.md)。

## 本地运行

macOS 主应用无需手工运行本节命令：构建阶段会把 `ianvs-api` 放入应用包。在应用的 **Defaults & appearance → Data service** 选择本地服务后，主应用会在下次启动时以随机回环端口运行它。访问令牌和数据密钥保存在系统安全存储中，SQLite 位于应用支持目录。正常退出会主动关闭服务，主进程意外结束造成的 stdin 断开也会让服务自行退出。

下面的命令用于独立开发和调试：

```bash
cd backend
go mod download
go run ./cmd/ianvs-api generate-key
go run ./cmd/ianvs-api serve
```

将第一条命令生成的随机值保存在客户端安全存储中，然后只需初始化一次本地用户：

```bash
curl -X POST http://127.0.0.1:47832/v1/auth/setup \
  -H 'Content-Type: application/json' \
  --data '{"encryption_key":"<client-owned-key>"}'
```

本地 SQLite 默认是 `backend/ianvs.db`。建议显式放到应用支持目录：

```bash
IANVS_DB_DSN=/absolute/application-support/ianvs.db \
  go run ./cmd/ianvs-api serve
```

## 远程运行

SQLite 适合单实例、小规模部署：

```bash
IANVS_API_MODE=remote \
IANVS_API_ADDR=0.0.0.0:47832 \
IANVS_DB_DRIVER=sqlite \
IANVS_DB_DSN=/var/lib/ianvs/ianvs.db \
  ./ianvs-api serve
```

MySQL 只需切换 driver 和 DSN，业务代码及迁移不变：

```bash
IANVS_API_MODE=remote \
IANVS_DB_DRIVER=mysql \
IANVS_DB_DSN='ianvs:<password>@tcp(mysql.example:3306)/ianvs?charset=utf8mb4&parseTime=True&loc=UTC' \
  ./ianvs-api serve
```

仓库也提供仅绑定本机回环地址的开发组合：

```bash
IANVS_MYSQL_PASSWORD='<dev-password>' \
IANVS_MYSQL_ROOT_PASSWORD='<dev-root-password>' \
  docker compose -f compose.mysql.yaml up --build
```

该组合为了本机反向代理/测试显式允许 HTTP，不应直接作为公网部署配置。

远程注册默认关闭。管理员只应在受控注册窗口显式设置
`IANVS_ALLOW_REGISTRATION=true`，首次用户注册时同时创建登录密码和独立数据密钥：

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

所有持久化对象使用稳定的 `kind/id`：

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

## 旧 JSON 导入本地 ORM

导入命令识别当前应用的八个文件：profiles、preferences、config、terminal layout、themes、layout templates、recent items 和 paste history。

```bash
cd backend
IANVS_ENCRYPTION_KEY='<client-owned-key>' \
IANVS_LEGACY_PROFILE_KEY='<base64-key-from-client-secure-storage>' \
  go run ./cmd/ianvs-api import-legacy \
  --dir '/absolute/path/to/application-support'
```

profiles 会拆成独立资源；已是明文的 `password`、`privateKeyPassphrase`、`x11AuthCookie` 和 proxy jump 密钥会从普通 JSON 中移出并重新加密。如果客户端显式提供 `IANVS_LEGACY_PROFILE_KEY`，导入器还能验证并解密现有 `ianvs-profile-secrets-v1` envelope，再使用新用户数据密钥重新加密。未提供旧 key 时，envelope 会作为敏感数据原样保护，不会猜测或丢字段。

其余分类：

- preferences/config、theme、layout template：普通 JSON。
- terminal layout/session relaunch、recent items、paste history：整份加密。

导入使用稳定 ID，重复执行是幂等的；文件发生变化后再次执行会更新对应本地 ORM 资源。命令不会删除或改写旧 JSON，便于回滚验证。

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

## 配置

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `IANVS_API_MODE` | `local` | `local` 或 `remote` |
| `IANVS_API_ADDR` | 本地 `127.0.0.1:47832`；远程 `0.0.0.0:47832` | 监听地址 |
| `IANVS_DB_DRIVER` | `sqlite` | `sqlite` 或 `mysql` |
| `IANVS_DB_DSN` | `ianvs.db` | SQLite 文件或 MySQL DSN |
| `IANVS_LOCAL_ACCESS_TOKEN` | 空 | 可选；本地模式所有请求需要的 Bearer token，主应用启动 sidecar 时自动设置 |
| `IANVS_EXIT_ON_STDIN_CLOSE` | `false` | stdin 关闭时优雅停止服务，供主应用管理 sidecar 生命周期 |
| `IANVS_AUTH_TOKEN_TTL` | `24h` | 登录 token 有效期 |
| `IANVS_ALLOW_REGISTRATION` | `false` | 是否开放远程注册；仅在受控注册窗口显式启用 |
| `IANVS_TRUST_PROXY_HEADERS` | `false` | 是否接受代理提供的 HTTPS 标记 |
| `IANVS_ALLOW_INSECURE_SENSITIVE_TRANSPORT` | `false` | 仅限受控开发环境 |
| `IANVS_LEGACY_DATA_DIR` | 空 | legacy import 默认目录 |
| `IANVS_LEGACY_PROFILE_KEY` | 空 | 可选；旧 profile Keychain 密钥（base64 32 字节） |
| `IANVS_ENCRYPTION_KEY` | 空 | 仅供一次性 CLI import；服务进程不需要 |

完整 HTTP contract 见 [openapi.yaml](openapi.yaml)。

## 验证

```bash
go test ./...
go vet ./...
```
