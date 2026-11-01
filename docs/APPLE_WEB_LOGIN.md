# 网页 Apple 登录

网页登录沿用原生 App 的 Apple 身份校验、一次性 nonce 和两阶段登录。
Apple JS 通过弹窗返回 identity token，后端从 Apple 公钥验证签名、issuer、audience、nonce 和有效期。
浏览器检查随机 state；不通过邮件合并账号，不在浏览器存储 Apple token。

## Apple Developer 配置

- Services ID：`work.ianvs.trail.web`（Trail Web Sign In）。
- Primary App ID 必须选 `work.ianvs.trail`，使原生 App 与网站共享 Apple 用户标识。
- 域名：`api.terminal.ianvs.work`。
- Return URL：`https://api.terminal.ianvs.work/`（包括末尾斜线）。
- 使用 Apple JS `usePopup`，不需要把内购密钥提供给网页登录，也不创建登录私钥。

cloud 的私有配置增加公开的登录标识：

```json
{
  "apple_client_ids": ["work.ianvs.trail", "work.ianvs.trail.web"],
  "apple_web": {
    "client_id": "work.ianvs.trail.web",
    "redirect_uri": "https://api.terminal.ianvs.work/"
  }
}
```

`apple_web` 缺省或 null 时不展示网页登录按钮。必须使用 remote 模式、HTTPS 回调和已允许的 audience。
`GET /healthz` 只返回这些公开信息。仅启用 Apple 网页登录的 UI 页面允许加载固定 Apple 官方 JS URL，API 与未启用站点保持原 CSP。

## 用户行为与验收

- 已用 Apple 登录 Trail 的用户直接登录同一账号。
- 旧用户名账号可勾选“关联已有用户名账号”，验证旧密码后关联；避免创建第二个账号。
- 未关联且允许注册时创建 Apple 账号；关闭注册时要求关联已有账号。
- 浏览器需允许登录弹窗；取消、网络失败、关联冲突与会话满均显示明确提示。
- nonce 在用户点击前准备，避免异步请求使浏览器拦截弹窗；超时后要求重新点击。
- 验收真实 Apple 授权、回到站点、账户与原生 App 一致、取消与重试。

官方参考：https://developer.apple.com/documentation/signinwithapple/configuring-your-webpage-for-sign-in-with-apple
