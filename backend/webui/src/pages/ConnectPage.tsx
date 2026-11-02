import { useEffect, useState, type FormEvent } from 'react'
import { ApiError, DataApiClient } from '../api/client'
import { useSession } from '../state/SessionContext'
import { Badge, Button, Dialog, Notice, Spinner, TextField } from '../components/ui'
import { AppleSignIn } from '../components/AppleSignIn'
import type { AppleWebConfig, Mode } from '../types'

function errorMessage(error: unknown): string {
  if (!(error instanceof ApiError)) return '无法确认请求结果，请检查连接后重试。'
  if (error.code === 'invalid_credentials') return '用户名或密码不正确。'
  if (error.code === 'secure_transport_required') return '此服务要求 HTTPS，请通过安全服务地址访问。'
  if (error.code === 'invalid_account') return '请检查用户名格式，以及密码的 UTF-8 字节长度。'
  if (error.code === 'username_taken') return '此用户名已被使用；如果刚才注册中断，请尝试登录。'
  if (error.code === 'auth_session_capacity') return '全部 8 个登录名额已占用。'
  if (error.status === 429) return '请求过于频繁或密码验证繁忙，请稍后重试。'
  if (error.status === 403) return '服务拒绝此操作，请联系部署者确认访问策略。'
  return `操作未完成（${error.code}），请检查输入后重试。`
}

export function ConnectPage() {
  const session = useSession()
  const [mode, setMode] = useState<Mode | 'detecting' | 'error'>('detecting')
  const [error, setError] = useState<string | null>(null)
  const [appleWeb, setAppleWeb] = useState<AppleWebConfig | null>(null)
  const [recovery, setRecovery] = useState(false)
  const detect = async () => {
    setMode('detecting'); setError(null)
    try { const health = await new DataApiClient({ baseUrl: session.baseUrl }).health(); setMode(health.mode); setAppleWeb(health.apple_web ?? null) }
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
        {mode === 'remote' && appleWeb && <AppleSignIn config={appleWeb} />}
        {mode === 'remote' && <RemoteAccess baseUrl={session.baseUrl} />}
        {mode === 'local' && <LocalForm />}
        {mode === 'error' && <div className="stack"><Notice tone="error" role="alert">{error}</Notice><Button onClick={detect}>重新连接</Button></div>}
        {mode === 'remote' && <Button variant="ghost" onClick={() => setRecovery(true)}>忘记密码或无法登录？</Button>}
        <footer className="terminal-login__footer"><span className="break-word">当前服务：{session.baseUrl}</span></footer>
      </div>
    </section>
    {recovery && <Dialog open title="恢复账户访问" onClose={() => setRecovery(false)} footer={<Button onClick={() => setRecovery(false)}>返回登录</Button>}><div className="stack"><Notice tone="warning">当前服务尚未接入密码找回或重置接口。</Notice><p>请通过你已有的可信渠道联系此服务的部署者，确认账户处理方式。此页面不会收集恢复凭证或发送找回邮件。</p><p className="secondary">账户密码与数据密钥相互独立。恢复登录不会恢复已遗失的加密密钥；旧设备或你保存的密钥备份仍可能需要保留。</p></div></Dialog>}
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

function RemoteAccess({ baseUrl }: { baseUrl: string }) {
  const [tab, setTab] = useState<'login' | 'register'>('login')
  return <div className="stack"><div className="segmented" role="tablist" aria-label="账户访问">{(['login', 'register'] as const).map(value => <button key={value} id={`${value}-tab`} type="button" role="tab" aria-selected={tab === value} tabIndex={tab === value ? 0 : -1} onKeyDown={event => {
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return
      event.preventDefault()
      const next = event.key === 'Home' ? 'login' : event.key === 'End' ? 'register' : tab === 'login' ? 'register' : 'login'
      setTab(next)
      document.getElementById(`${next}-tab`)?.focus()
    }} aria-controls={`${value}-panel`} onClick={() => setTab(value)}>{value === 'login' ? '登录' : '注册账户'}</button>)}</div><div id={`${tab}-panel`} role="tabpanel" aria-labelledby={`${tab}-tab`}><AccountForm key={tab} baseUrl={baseUrl} register={tab === 'register'} /></div></div>
}

function AccountForm({ baseUrl, register }: { baseUrl: string; register: boolean }) {
  const session = useSession()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [deviceName, setDeviceName] = useState(defaultDeviceName)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [atCapacity, setAtCapacity] = useState(false)
  const [confirmReplace, setConfirmReplace] = useState(false)
  const submit = async (replaceOldest = false) => {
    if (busy) return
    if (register) {
      const length = new TextEncoder().encode(password).length
      if (length < 12 || length > 72) { setError('密码需为 12–72 个 UTF-8 字节；中文等字符会占用多个字节。'); return }
      if (!/^[a-z0-9][a-z0-9._-]{2,63}$/.test(username.trim())) { setError('用户名需为 3–64 个小写字母、数字、点、下划线或短横线，并以字母或数字开头。'); return }
    }
    setBusy(true); setError(null); setConfirmReplace(false)
    const anonymous = new DataApiClient({ baseUrl })
    let operationId: string | null = null
    try {
      const prepared = register ? await anonymous.beginRegister(username.trim(), password) : await anonymous.beginLogin(username.trim(), password, replaceOldest)
      operationId = prepared.operation_id
      const result = register ? await anonymous.completeRegister(operationId, deviceName) : await anonymous.completeLogin(operationId, deviceName)
      await session.signIn(result.token, result.expires_at)
    } catch (err) {
      let cleanupFailed = false
      if (operationId) {
        try { await anonymous.cancelOperation(operationId) } catch { cleanupFailed = true }
      }
      setAtCapacity(err instanceof ApiError && err.code === 'auth_session_capacity')
      const message = register && !operationId && err instanceof ApiError && err.code === 'not_found' ? '此服务未开放注册，请联系部署者。' : errorMessage(err)
      setError(message + (cleanupFailed ? ' 本次登录清理结果未确认，可能暂时占用名额；请稍后检查会话。' : ''))
    } finally { setBusy(false) }
  }
  return <><form className="terminal-form" onSubmit={event => { event.preventDefault(); void submit() }}>
    {register && <Notice tone="warning">注册是否开放由部署者决定，当前接口不提供策略预查询。提交后以服务端结果为准。</Notice>}
    <TextField label="用户名" value={username} onChange={e => setUsername(e.target.value)} autoComplete="username" required disabled={busy} hint={register ? '3–64 个小写字母、数字、点、下划线或短横线。' : undefined} />
    <TextField label="密码" type="password" value={password} onChange={e => setPassword(e.target.value)} autoComplete={register ? 'new-password' : 'current-password'} required disabled={busy} hint={register ? '12–72 个 UTF-8 字节，不是数据密钥。' : undefined} />
    <TextField label="此会话的设备备注" value={deviceName} onChange={e => setDeviceName(e.target.value)} maxLength={128} disabled={busy} hint="例如：工作 Mac · Chrome。备注用于辨认登录，不表示设备在线。" />
    {error && <Notice tone="error" role="alert">{error}</Notice>}
    {atCapacity && !register && <Notice tone="warning">待完成登录也会占用名额，最多五分钟。你可以选择退出最早会话后继续。<Button type="button" variant="danger" disabled={busy} onClick={() => setConfirmReplace(true)}>处理已满的登录名额</Button></Notice>}
    <Button type="submit" variant="primary" busy={busy}>{register ? '创建账户并登录' : '登录账户'}</Button>
  </form>{confirmReplace && <Dialog open title="退出最早会话并登录？" onClose={() => setConfirmReplace(false)} footer={<><Button data-dialog-initial-focus onClick={() => setConfirmReplace(false)}>取消</Button><Button variant="danger" onClick={() => void submit(true)}>退出最早会话并登录</Button></>}><p>服务将重新验证你的密码，并在名额仍满时撤销最早会话，或取消最早待完成登录。被退出的客户端需要重新登录，本地数据不会被删除。</p></Dialog>}</>
}

function defaultDeviceName(): string {
  const ua = navigator.userAgent
  const os = /Android/.test(ua) ? 'Android' : /iPhone/.test(ua) ? 'iPhone' : /iPad/.test(ua) ? 'iPad' : /Macintosh/.test(ua) ? 'Mac' : /Windows/.test(ua) ? 'Windows' : /Linux/.test(ua) ? 'Linux' : '浏览器'
  const browser = /Edg\//.test(ua) ? 'Edge' : /Firefox\/|FxiOS\//.test(ua) ? 'Firefox' : /Chrome\/|CriOS\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : 'Web'
  return `${os} · ${browser}`
}
