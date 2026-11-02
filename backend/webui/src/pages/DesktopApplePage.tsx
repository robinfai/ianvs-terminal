import { useEffect, useState } from 'react'
import { Button, Notice } from '../components/ui'
import { checkedAppleToken, loadAppleSDK, startAppleSignIn } from '../lib/appleSignIn'
import type { AppleWebConfig } from '../types'

// A dedicated page does not establish a web session or touch existing accounts.
export function DesktopApplePage() {
  const [id] = useState(() => new URLSearchParams(location.hash.slice(1)).get('flow') ?? '')
  const [config, setConfig] = useState<{ nonce: string; apple_web: AppleWebConfig } | null>(null)
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)
  const [error, setError] = useState('')
  async function request(action: string, body: object = {}) {
    const response = await fetch(`/v1/auth/apple/desktop/${action}`, {
      method: 'POST', credentials: 'omit', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, ...body }),
    })
    if (!response.ok) throw new Error('登录请求已失效或无法连接，请返回 Trail 重试。')
    return response.json()
  }
  useEffect(() => {
    let active = true
    void (async () => {
      try {
        if (!/^[A-Za-z0-9_-]{43}$/.test(id)) throw new Error('请从 Trail 发起登录。')
        const info = await request('info')
        await loadAppleSDK()
        if (active) setConfig(info)
      } catch (e) { if (active) setError((e as Error).message) }
    })()
    return () => { active = false }
  }, [id])
  async function signIn() {
    if (!config || busy) return
    const state = crypto.randomUUID()
    setBusy(true); setError('')
    try {
      const response = await startAppleSignIn(config.apple_web, config.nonce, state)
      await request('complete', { identity_token: checkedAppleToken(response, state) })
      setDone(true)
    } catch { setError('Apple 登录未完成，请重试；若 Trail 已取消登录，请重新发起。') }
    finally { setBusy(false) }
  }
  return <main className="connect"><section className="terminal-login">
    <div className="terminal-login__body stack">
      <h1>登录 Trail</h1>
      <p>{done ? '验证完成，请返回 Trail 继续。你可以关闭此页面。' : '继续你在这台 Mac 上发起的登录。'}</p>
      {error && <Notice tone="error" role="alert">{error}</Notice>}
      {!done && <Button className="apple-signin__button" disabled={!config || busy} onClick={() => void signIn()}>使用 Apple 登录</Button>}
    </div>
  </section></main>
}
