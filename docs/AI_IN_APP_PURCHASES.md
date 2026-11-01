# AI 额度内购

iOS 通过 StoreKit 2 购买消耗型额度包，购买余额绑定当前登录的 Trail 后端账号，
在所有 SSH Profile 间共享。每日免费额度优先消耗；购买额度不随每日重置过期。
购买余额不解除管理员配置的每日请求次数限制或禁用策略。

## 2 倍成本定价

继续使用现有成本单位：1 点 = 2,000 nano-USD，500,000 点 = 1 美元模型成本。
额度出售价格按成本的 **2 倍**，即每 1 美元售价提供 250,000 点。
AI 请求仍按后端配置的模型原始 token 费率扣点，不在扣点时再乘一次 2。

已在 App Store Connect 创建以下 **Consumable（消耗型）** 商品草稿，基准地区为美国：

| 商品 ID | 美国基准售价 | 到账点数 | 对应模型成本 |
| --- | ---: | ---: | ---: |
| `work.ianvs.trail.ai.credits.small` | US$1.99 | 497,500 | US$0.995 |

其他地区采用 App Store 的本地币种价格，税费、汇率、商店价格档位和 Apple 佣金
不计入上面的基础成本倍率。客户端始终展示 StoreKit 返回的 `displayPrice`，不硬编码人民币售价。
商品 Apple ID：`6829471536`，已配置中英文文案及初始价格；尚未提交审核或验证真实交易。
中国大陆当前商店换算价为 ¥15.00，以实际 StoreKit 显示为准。
已销售商品的 ID 与点数映射应保持不变；调整套餐使用新的商品 ID。

## 开通配置

1. 在 App Store Connect 选中 bundle ID `work.ianvs.trail` 对应应用，检查上表的
   消耗型商品草稿，补齐审核截屏及应用审核资料。
2. 在 App Store Connect 的用户和访问权限中生成 **In-App Purchase API Key**，
   记录 Issuer ID、Key ID，将下载的 `.p8` 存放在服务器私有配置目录，权限 `0600`。
   私钥只放后端，不提交 Git，不进入客户端。开发签名证书不能代替这个 API Key。
3. 在现有 `ai_gateway` 中添加 `apple_purchases`。示例见
   [ai-purchases.example.json](../backend/ai-purchases.example.json)。保留现有 DeepSeek
   模型与用户额度配置，仅添加这个对象。
4. 如后端使用 Docker，把服务器私钥只读挂载到 `/run/secrets/ianvs-apple-iap.p8`，
   entrypoint 会以服务账号权限复制到 `/run/ianvs-api/apple-iap.p8`，
   `private_key_file` 填后者。
   重启后端。未配置 `apple_purchases` 时，商品 API 返回 `enabled: false`，不接受充值。
5. App Store Server Notifications V2 的生产 URL 设置为
   `https://api.terminal.ianvs.work/v1/ai/purchases/apple/notifications`。
   通知只触发已知交易的 Apple 服务端查询，通知本身不会直接授予或撤销额度。
6. 确认付费协议、税务和收款信息在 App Store Connect 已完成，并将内购随应用提交审核。
   这些账户与协议操作需要账号持有者在 Apple 网站完成。

## 测试与环境隔离

- Sandbox / TestFlight 使用独立后端与数据库，将 `environment` 设置为 `Sandbox`；
  生产后端只配置 `Production`。生产环境拒绝 Sandbox 交易，不把测试购买兑换成真实可消耗余额。
- Xcode StoreKit 本地测试可以验证付款 UI 与中断状态，但交易不在 Apple Server API 中，
  不能据此证明真实后端到账。代码里没有绕过验单的生产开关。
- 真实验收需要 Apple 已可查询的商品、内购 API Key、Sandbox 测试账号及隔离后端。
- 验收顺序：购买成功 → 后端验单到账 → 重复回调不重复充值 → 付款后断网/重启补单 →
  切换 Trail 账号不会领取另一账号的交易 → 退款通知撤回额度 → 每日重置保留购买余额。
- 后端全量 Go 测试覆盖原子到账、重复/并发回调、账号/环境/商品验证、免费额度优先、
  并发预占、退款去重、伪造通知不影响余额、Apple 固定 HTTPS 查询与服务端 JWT。
  Dart 测试覆盖取消、待批准、补单、账号切换、重复更新和浅/深色购买页。
- 支持的系统下限保持 iOS 17；构建通过不等于所有支持版本都已真机验证。

## 交易与计费约定

- `GET /v1/ai/purchases/products`：服务端商品点数映射及账号绑定 UUID；价格来自 StoreKit。
- `POST /v1/ai/purchases/verify`：仅接受 `transaction_id`，使用服务端密钥请求 Apple
  `Get Transaction Info`。不接受客户端传来的金额、点数、账号 ID 或自称已签名的凭证作为充值依据。
  Apple 返回的交易必须匹配 bundle、environment、consumable 类型、quantity、商品与 appAccountToken。
- Apple 交易响应只从固定的 HTTPS 主机获取，拒绝重定向；该受信任响应的 JWS 载荷在此路径解析。
  不把相同解码器用于信任客户端 JWS。通知载荷是未受信任的查询提示，必须重新查询 Apple。
- 交易唯一键、账号余额和用户购买索引在同一个数据库事务内提交。
  StoreKit `finish()` 只发生在服务端确认持久到账或已撤销之后；失败保留 unfinished 交易。
- 应用启动、返回前台和 StoreKit 更新时自动尝试补单，也提供“检查未到账购买”。
- 退款按原充值金额一次性撤回；余额不足时记账为负，不抹去已经发生的使用成本。
  后续充值先抵消欠额，可用余额显示不低于零。历史购买保留原始充值金额。
- 生产运维应监控通知 429/503 与 Apple 的通知重试，并使用 Apple 通知历史核对遗漏退款。

官方参考：[StoreKit Transaction](https://developer.apple.com/documentation/storekit/transaction)、
[App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)、
[App account token](https://developer.apple.com/documentation/appstoreserverapi/appaccounttoken)。
