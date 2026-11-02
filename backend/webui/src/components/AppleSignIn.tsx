import { useEffect, useRef, useState } from 'react'
import { ApiError, DataApiClient } from '../api/client'
import { checkedAppleToken, loadAppleSDK, startAppleSignIn } from '../lib/appleSignIn'
import { useSession } from '../state/SessionContext'
import type { AppleWebConfig } from '../types'
import { Button, Notice, TextField } from './ui'

export function AppleSignIn({ config }: { config: AppleWebConfig }) {
  const session = useSession()
  const [nonce, setNonce] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [link, setLink] = useState(false)
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const generation = useRef(0)
  const expiresAt = useRef(0)
  const api = () => new DataApiClient({ baseUrl: session.baseUrl })
  const prepare = async () => {
    const current = ++generation.current
    setNonce(null)
    try {
      const [, challenge] = await Promise.all([loadAppleSDK(), api().appleChallenge()])
      if (current !== generation.current) return
      expiresAt.current = Date.now() + 240000
      setNonce(challenge.nonce)
    } catch {
      if (current === generation.current) setError('Apple 登录暂时无法准备，请检查网络后重试。')
    }
  }
  useEffect(() => { void prepare(); return () => { ++generation.current } }, [session.baseUrl, config.client_id])

  const [atCapacity, setAtCapacity] = useState(false)
  const [replaceOldest, setReplaceOldest] = useState(false)
  const signIn = async () => {
    if (busy || !nonce) return
    setError(null)
    if (link && (!username.trim() || !password)) { setError('请填写要关联的现有账号及密码。'); return }
    if (Date.now() >= expiresAt.current) { await prepare(); setError('登录验证已刷新，请再次点击使用 Apple 登录。'); return }
    setBusy(true)
    let operation: string | undefined
    let signedIn = false
    try {
      const state = crypto.randomUUID()
      const result = await startAppleSignIn(config, nonce, state)
      const token = checkedAppleToken(result, state)
      const prepared = await api().beginApple(token, nonce, link ? username.trim() : '', link ? password : '', replaceOldest)
      operation = prepared.operation_id
      const resultSession = await api().completeLogin(operation, 'Web · Apple')
      await session.signIn(resultSession.token, resultSession.expires_at)
      signedIn = true
      setPassword('')
    } catch (err) {
      let message = 'Apple 登录未完成，请重试。'
      if (err instanceof ApiError) {
        setAtCapacity(err.code === 'auth_session_capacity')
        const messages: Record<string, string> = {
          invalid_credentials: '现有账号或密码不正确。',
          apple_link_conflict: '此 Apple 账号或现有账号已关联其他账号，无法再次关联。',
          apple_registration_disabled: '此服务未开放新账号注册，请关联已有账号登录。',
          invalid_apple_identity: 'Apple 身份验证失败，请重试。',
          auth_session_capacity: '登录会话已满。可退出其他设备，或勾选下方选项后重新验证 Apple 身份登录。',
        }
        message = messages[err.code] ?? message
      } else if (err && typeof err === 'object' && 'error' in err) {
        const code = String(err.error)
        message = code === 'popup_closed_by_user' || code === 'user_cancelled_authorize'
          ? '已取消 Apple 登录。'
          : code === 'popup_blocked_by_browser' ? '浏览器阻止了登录窗口，请允许本站弹出窗口后重试。' : message
      } else if (err instanceof Error) message = err.message
      if (operation) {
        try { await api().cancelOperation(operation) }
        catch { message += ' 本次登录清理未确认，请稍后检查账户会话。' }
      }
      setError(message)
    } finally {
      setBusy(false)
      if (!signedIn) void prepare()
    }
  }
  return <section className="stack apple-signin" aria-label="Apple 登录">
    <Button className="apple-signin__button" disabled={!nonce || busy} busy={busy} onClick={() => void signIn()}>使用 Apple 登录</Button>
    <p className="secondary">使用与 Trail App 相同的 Apple 账号，可访问同一账户。首次使用且未关联旧账号时，将创建新账户。</p>
    <label className="row"><input type="checkbox" checked={link} disabled={busy} onChange={e => { setLink(e.target.checked); setPassword('') }} />关联已有用户名账号</label>
    {link && <div className="stack"><TextField label="已有用户名" value={username} disabled={busy} onChange={e => setUsername(e.target.value)} autoComplete="username" /><TextField label="已有账号密码" type="password" value={password} disabled={busy} onChange={e => setPassword(e.target.value)} autoComplete="current-password" hint="验证账号归属后关联，保留已有配置、额度与使用记录。" /></div>}
    {atCapacity && <label className="row"><input type="checkbox" checked={replaceOldest} disabled={busy} onChange={e => setReplaceOldest(e.target.checked)} />退出最早的一个会话并重新登录（该设备需要重新登录）</label>}
    {error && <Notice tone="error" role="alert">{error}</Notice>}
    {!nonce && !busy && <Button variant="ghost" onClick={() => { setError(null); void prepare() }}>重新准备 Apple 登录</Button>}
  </section>
}
