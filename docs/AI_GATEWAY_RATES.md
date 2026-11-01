# AI 网关费率与用户配额

核对日期：2026-11-01。AIGW 没有统一的配额标准；此项目采用
[New API 的换算约定](https://doc.newapi.pro/guide/console/settings/rate-settings/)：
1 USD = 500,000 配额点。分组倍率暂为 1。

价格 P 的单位为 USD / 百万 token：

`扣点 = (未缓存输入 × P输入 + 缓存输入 × P缓存 + 输出 × P输出) / 2`

对应 New API：模型倍率 = P输入 / 2；输出倍率 = P输出 / P输入；
缓存倍率 = P缓存 / P输入。缓存 token 是输入的一部分，不能重复加算。

| 模型/时段 | 输入价格 | 缓存价格 | 输出价格 | 模型倍率 | 输出倍率 | 缓存倍率 |
|---|---:|---:|---:|---:|---:|---:|
| DeepSeek Flash 谷时 | 0.15 | 0.003 | 0.60 | 0.075 | 4 | 0.02 |
| DeepSeek Flash 峰时 | 0.30 | 0.006 | 1.20 | 0.15 | 4 | 0.02 |
| DeepSeek V4 Pro 谷时 | 0.66 | 0.022 | 1.98 | 0.33 | 3 | 0.033333… |
| DeepSeek V4 Pro 峰时 | 1.32 | 0.044 | 3.96 | 0.66 | 3 | 0.033333… |
| GPT-6.1 Sol | 2.00 | 0.10 | 10.00 | 1 | 5 | 0.05 |
| GPT-6.1 Terra | 1.00 | 0.05 | 5.00 | 0.5 | 5 | 0.05 |
| GPT-6 Luna | 0.10 | 0.01 | 0.50 | 0.05 | 5 | 0.10 |
| GPT-6 Astra | 10.00 | 1.00 | 50.00 | 5 | 5 | 0.10 |

[DeepSeek 官方定价](https://api-docs.deepseek.com/quick_start/pricing/)：峰时为
周一至周五 UTC 01–04、06–10（北京时间 09–12、14–18），中国法定假日除外。
其余时段为谷时。实际可用模型已通过本地密钥查询，返回 deepseek-flash 与 deepseek-v4-pro。

[OpenAI 官方定价](https://developers.openai.com/api/docs/pricing)：上表为 Standard、
Short context、普通全球 endpoint。Fast/Ultrafast、长上下文、区域 endpoint 等需另行计算。
GPT-6 系列还有缓存写入费：30 分钟/12 小时写入价格分别为输入价的 1.25/2.5 倍；
上表的缓存列仅指读取。当前网关不支持缓存写入计价，因此没有启用这些 OpenAI 模型。
OpenAI provider 协议适配已实现，接入具体模型须补齐对应 usage 分类和凭据。

例：10,000 未缓存输入 + 2,000 输出，无缓存写入或其他收费：

| 模型 | USD 成本 | 配额点 |
|---|---:|---:|
| Flash 谷时 | 0.0027 | 1,350 |
| Flash 峰时 | 0.0054 | 2,700 |
| V4 Pro 谷时 | 0.01056 | 5,280 |
| V4 Pro 峰时 | 0.02112 | 10,560 |
| GPT-6.1 Sol | 0.04 | 20,000 |
| GPT-6.1 Terra | 0.02 | 10,000 |
| GPT-6 Luna | 0.002 | 1,000 |
| GPT-6 Astra | 0.20 | 100,000 |

当前部署策略：默认 Flash，每用户每日 500,000 点和 100 次请求，均可按用户 ID 覆盖。
为保持用户额度稳定，用户扣点使用固定峰时费率；这是配额政策，**不等于谷时供应商实际账单**。
数据库用整数 nano-USD 保存（每点 2,000 nano-USD），不使用浮点倍率扣款。
调用前预占、成功后按 usage 结算；未知 usage 保留 pending，不伪装成实际消费。

## 部署与验证

2026-11-01 已通过 `ssh cloud` 部署 `ianvs-api:aigw-20261101`。
- 全量 `go test ./...` 与 AI 网关 `go test -race` 通过。
- 云端独立数据库的真实 DeepSeek 普通/流式调用各一次，合计 18 输入、2 输出 token，
  扣 3.9 点，余额 499,996.1 点，预占清零。
- 生产 HTTPS `/healthz` 正常，未登录 `/v1/ai/models` 返回 401。
- 保留旧容器 `ianvs-api-pre-aigw-20261101`。
- 配置备份 `/etc/ianvs-api/configuration.pre-aigw-20261101.json`；
  数据库一致性快照 `/var/lib/ianvs-api/ianvs.pre-aigw-20261101.db`，完整性检查通过。
- DeepSeek 密钥来自本地环境，经 SSH 标准输入写入云端权限受限配置；未写入源码。


## Bifrost 为核心参考的调整

后端治理结构改为“认证用户策略 → 模型别名访问范围 → 用户费率覆盖 → 模型费率目录”。
以 nano-USD 金额作为预算配置和账本单位，旧配额点字段保留兼容，显示换算不变。
费率仍为上一节核对的价格，不因采用 Bifrost 结构而变更。

参考 [Bifrost Custom Pricing](https://docs.getbifrost.ai/providers/custom-pricing)
的作用域覆盖与价格目录，采用明确版本、固定快照，不自动同步未审核的远程价格。
参考 [Bifrost Budgets](https://docs.getbifrost.ai/features/governance/budget-and-limits)
的策略所有者和访问限制；我们继续保留请求前预占，未复制其超额后拦截下一次请求的行为。

已实现独立请求账本、原子预占/结算、幂等结算、用户限定的分页查询，
保留旧日预算桶及其消费。用户覆盖价格属于扣点费率，不应当作供应商真实账单。
本次没有安装 Bifrost 运行时，也没有宣称支持其全部能力。
详细配置与继承规则见 [backend README](../backend/README.md#bifrost-inspired-governance-2026-11-01)。

本轮部署：2026-11-01，镜像 `ianvs-api:bifrost-reference-20261101`。
`go test ./...` 及 httpapi/config 的 race 测试通过。云端隔离验证普通/流式
DeepSeek 请求各一次，2 条账本均 settled，费率版本
`deepseek-2026-11-01-peak`，扣款合计 3.9 点、预占清零。
生产健康检查通过，旧容器 `ianvs-api-pre-bifrost-20261101` 保留。
配置备份为 `/etc/ianvs-api/configuration.pre-bifrost-20261101.json`，
数据库快照为 `/var/lib/ianvs-api/ianvs.pre-bifrost-20261101.db`。

## 客户端额度展示

AI 服务设置内展示当前账号的每日额度、剩余额度、已用与预占额度，以及本地时区的
下次重置时间。桌面工具栏及移动端更多操作均提供“AI 额度与用量”独立页面入口。
明细按卡片展示 provider、model、时间、扣点、输入/缓存/输出 token、结算状态、
请求编号和费率版本，支持分页与刷新。预占不作为确认消费展示。

接口使用当前后端登录凭据，不持久化用量数据，不跟随 SSH Profile 拆分账号余额；
自定义模型连接不展示后端账户额度。额度不足错误与 provider 限流分别处理，
会话错误区提供明确提示与查看入口；不在客户端依据旧余额自动重试或拦截请求。
刷新失败保留旧数据并标明，首次加载失败不伪装成零余额。登录失效会清除已缓存的额度。

客户端验证：AI 全量 762 项通过，新增 HTTP 鉴权/重定向、精确换算、分页、明暗主题
390px 页面及额度不足提示验证通过；Dart 静态分析无问题。尚未安装到真机验收。
