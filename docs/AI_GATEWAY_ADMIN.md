# AI 网关管理

网页登录后，部署配置指定的管理员可进入“AI 网关管理”。入口由 `/v1/me` 的
`is_admin` 控制；所有 `/v1/admin/ai/*` 接口仍独立校验登录、管理员身份与 HTTPS。
管理员身份由部署文件中的用户 UUID 指定，不能在浏览器自我授权。

## 能力

- Provider：添加、修改、启停、移除、更新密钥、检查已保存配置的 `/models` 连通性。
  支持 DeepSeek 和 OpenAI-compatible 协议；多个相同协议 provider 可使用不同端点和凭据。
  有模型引用的 provider 必须先移除引用；默认模型必须先切换才能移除。
- 模型：别名、上游 ID、provider 归属、输出 token 上限、启停、输入/缓存/输出价格及版本。
  页面价格单位为美元/百万 token；服务器使用整数 nano-USD/token。费率随请求固化，不回写历史成本。
- 全局默认：每日免费点数、每日请求上限及默认模型。
- 用户：分页搜索、查看免费和长期余额/预占/消费、覆盖每日额度和请求上限、限制模型、禁用 AI。
  留空覆盖值表示继承，零表示无免费额度/无请求名额。每日额度按 UTC 重置。
- 人工额度调整：整数点数差额，正数增加、负数扣减；记录原因、操作人及前后余额。
  不改写既有消费。操作 UUID 保证网络重试和并发重试不会重复到账；重复 UUID 内容不同返回 409。
  扣减不得挪用预占余额；调整并非 Apple 内购交易，也不会创建虚假的购买记录。
- 使用记录：全站/用户/模型/provider/状态/UTC 日期范围（最多 90 天）筛选；每页 50 条、游标翻页；
  汇总整个筛选范围的请求、token、扣点和待结算预占；保留费率快照；可导出当前已加载记录 CSV。
- 审计：配置、策略及余额调整独立持久记录；提供分页。无对话内容、SSH 资料、密码或 provider 密钥。

## 配置与持久化

在现有服务器私有配置中增加：

```json
{
  "ai_admin": {
    "user_ids": ["管理员的现有用户 UUID"],
    "encryption_key_file": "/run/ianvs-api/ai-admin.key"
  }
}
```

密钥是随机生成的 **32 字节二进制文件**，不是文本口令。权限仅服务用户可读（0400/0600）。
Docker 把宿主机 `/etc/ianvs-api/ai-admin.key` 只读挂载到 `/run/secrets/ianvs-ai-admin.key`；
entrypoint 将其复制到服务账号的 `/run/ianvs-api/ai-admin.key`。
此文件必须与数据库分别安全备份；丢失或替换密钥将无法解密已保存 provider 配置。

首次保存前以部署文件的 `ai_gateway` 为基线。管理配置保存到 `settings`，使用 AES-256-GCM
加密，认证附加数据绑定配置版本键。保存后数据库配置优先，直接修改部署文件中的 provider
不会覆盖已保存管理配置。Apple 内购配置仍由部署文件管理，不可通过管理页面读取或改写。
API 不回显密钥，空密钥保留旧值；改变端点或协议必须显式提供新密钥。

每个 AI 请求读取已提交的配置快照，不修改全局共享配置。运行中的流保持原费率，后续请求使用
新配置；多副本共享数据库可见同一版本。保存采用数据库写锁和 revision 校验，避免并发覆盖。
加密配置不可读时拒绝 AI 请求，不静默退回旧配置。

## 接口

| 方法与路径（前缀 `/v1/admin/ai`） | 用途 |
| --- | --- |
| `GET /gateway` | 脱敏配置与 revision |
| `PUT /gateway` | `{gateway, reason}`，携带当前 revision；不改用户策略 |
| `POST /providers/{id}/test` | 不发起生成，仅查询 provider 模型接口，返回状态与延迟 |
| `GET /users?q=&after=` | 搜索/分页用户 |
| `GET /users/{id}` | 当前策略、免费/长期额度、预占和今日请求 |
| `PUT /users/{id}/policy` | `{revision, policy, reason}` |
| `POST /users/{id}/credits` | `{operation_id, points, reason}`，差额调整 |
| `GET /requests?from=&to=&user_id=&model=&provider_id=&status=&before=` | 范围汇总和记录游标分页 |
| `GET /audit?before=` | 管理审计游标分页 |

普通用户继续通过 `/v1/ai/usage` 和 `/v1/ai/requests` 查询自己的信息，不能借助 user_id 参数越权。
请求状态 `pending` 表示上游用量或结算未确认，预占不会被管理页面擅自视为退款。

## 验证

- 后端契约覆盖非管理员和匿名拒绝、配置加密和密钥不回显、版本冲突、重启生效、
  并发调整幂等、禁止超额扣减、禁用策略即时生效、分页和汇总、密钥错误时拒绝请求。
- 隔离数据库中的浏览器流程验证 provider 保存、用户策略、长期额度调整、使用记录及审计。
- 生产部署保留原有每日额度、provider 凭据、购买余额及使用记录，不用生产余额做测试充值。
