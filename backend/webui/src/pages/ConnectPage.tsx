import { useEffect, useState, type FormEvent } from 'react'
import { ApiError, DataApiClient } from '../api/client'
import { useSession } from '../state/SessionContext'
import { Badge, Button, Notice, Spinner, TextField } from '../components/ui'
import { AppleSignIn } from '../components/AppleSignIn'
import type { AppleWebConfig, Mode } from '../types'

export function ConnectPage() {
  const session = useSession()
  const [mode, setMode] = useState<Mode | 'detecting' | 'error'>('detecting')
  const [error, setError] = useState<string | null>(null)
  const [appleWeb, setAppleWeb] = useState<AppleWebConfig | null>(null)
  const [googleClientId, setGoogleClientId] = useState('')
  const detect = async () => {
    setMode('detecting'); setError(null)
    try { const health = await new DataApiClient({ baseUrl: session.baseUrl }).health(); setMode(health.mode); setAppleWeb(health.apple_web ?? null); setGoogleClientId(health.google_web_client_id ?? '') }
    catch (err) {
      // The existing local service protects health with its sidecar token.
      if (err instanceof ApiError && (err.status === 401 || err.status === 403)) setMode('local')
      else { setMode('error'); setError('暂时无法连接此服务。请确认服务已启动，然后重试。') }
    }
  }
  useEffect(() => { void detect() }, [session.baseUrl])
  return <main className="connect" id="main-content">
    <section className="terminal-login" aria-labelledby="login-title">
      <header className="terminal-login__bar"><strong>IANVS / 账户与同步</strong><Badge>{mode === 'remote' ? '远程服务' : mode === 'local' ? '本地服务' : '连接检查'}</Badge></header>
      <div className="terminal-login__body">
        <div className="terminal-login__intro"><p className="terminal-line">连接你的工作空间</p><h1 id="login-title">登录 Ianvs</h1><p>管理 SSH 配置与账户会话。登录无需数据密钥，敏感内容在需要时于本地解锁。</p></div>
        {mode === 'detecting' && <div className="row"><Spinner label="正在连接服务" /><span>正在检查服务…</span></div>}
        {mode === 'remote' && (appleWeb || googleClientId) && <AppleSignIn config={appleWeb} googleClientId={googleClientId} />}
        {mode === 'remote' && !appleWeb && !googleClientId && <Notice tone="error">此服务尚未配置 Apple 或 Google 登录。</Notice>}
        {mode === 'local' && <LocalForm />}
        {mode === 'error' && <div className="stack"><Notice tone="error" role="alert">{error}</Notice><Button onClick={detect}>重新连接</Button></div>}
        <footer className="terminal-login__footer"><span className="break-word">{new URL(session.baseUrl).hostname === 'api.terminal.ianvs.work' ? 'Trail 同步服务' : `当前服务：${session.baseUrl}`}</span></footer>
      </div>
    </section>
  </main>
}

function LocalForm() {
  const session = useSession()
  const [token, setToken] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const submit = async (event: FormEvent) => {
    event.preventDefault(); if (busy) return
    setBusy(true); setError(null)
    try { await session.signIn(token.trim()) } catch { setError('无法验证本地访问令牌，请确认令牌属于当前正在运行的本地服务。') } finally { setBusy(false) }
  }
  return <form className="terminal-form" onSubmit={submit}><Notice>当前为本地 sidecar。使用本地访问令牌连接，不需要远程账号密码。</Notice><TextField label="本地访问令牌" type="password" value={token} onChange={e => setToken(e.target.value)} required autoComplete="off" hint="由本地服务签发的 43 字符令牌；这不是数据加密密钥。" />{error && <Notice tone="error" role="alert">{error}</Notice>}<Button type="submit" variant="primary" busy={busy}>连接本地服务</Button></form>
}
