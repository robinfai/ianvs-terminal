import type { AppleWebConfig } from '../types'

export interface AppleResponse {
  authorization: { id_token: string; state: string }
}
interface AppleSDK {
  auth: {
    init(options: { clientId: string; redirectURI: string; state: string; nonce: string; usePopup: true }): void
    signIn(): Promise<AppleResponse>
  }
}
declare global { interface Window { AppleID?: AppleSDK } }
let loading: Promise<void> | undefined

export function loadAppleSDK(): Promise<void> {
  if (window.AppleID) return Promise.resolve()
  if (loading) return loading
  loading = new Promise<void>((resolve, reject) => {
    const script = document.createElement('script')
    script.src = 'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js'
    script.async = true
    const timer = window.setTimeout(() => fail(), 15000)
    const fail = () => {
      window.clearTimeout(timer); script.remove(); loading = undefined
      reject(new Error('Apple 登录组件加载失败，请检查网络后重试。'))
    }
    script.onerror = fail
    script.onload = () => {
      window.clearTimeout(timer)
      if (window.AppleID) resolve()
      else fail()
    }
    document.head.append(script)
  })
  return loading
}

export function startAppleSignIn(config: AppleWebConfig, nonce: string, state: string): Promise<AppleResponse> {
  if (!window.AppleID || new URL(config.redirect_uri).origin !== window.location.origin) {
    throw new Error('Apple 登录配置与当前站点不一致，请联系管理员。')
  }
  window.AppleID.auth.init({ clientId: config.client_id, redirectURI: config.redirect_uri, nonce, state, usePopup: true })
  // Must execute synchronously from the click, before any network await.
  return window.AppleID.auth.signIn()
}

export function checkedAppleToken(response: AppleResponse, expectedState: string): string {
  if (!expectedState || response?.authorization?.state !== expectedState || !response.authorization.id_token) {
    throw new Error('Apple 登录响应校验失败，请重新登录。')
  }
  return response.authorization.id_token
}
