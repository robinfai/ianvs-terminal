import { useEffect, useRef, useState } from 'react'
import { ApiError, DataApiClient } from '../api/client'
import { checkedAppleToken, loadAppleSDK, startAppleSignIn } from '../lib/appleSignIn'
import { useSession } from '../state/SessionContext'
import type { AppleWebConfig } from '../types'
import { Button, Notice, TextField } from './ui'

type Proof = { provider: 'apple' | 'google'; identity_token: string; nonce: string }
type GoogleSDK = { accounts: { id: {
  initialize(options: {client_id: string; nonce: string; auto_select: false; callback: (response: {credential: string}) => void}): void
  renderButton(element: HTMLElement, options: {type: 'standard'; theme: 'outline'; size: 'large'; text: 'signin_with'}): void
} } }
declare global { interface Window { google?: GoogleSDK } }
let googleLoading: Promise<void> | undefined
function loadGoogle() {
  if (window.google) return Promise.resolve()
  return googleLoading ??= new Promise<void>((resolve, reject) => {
    const script = document.createElement('script')
    const fail = () => { clearTimeout(timer); script.remove(); googleLoading = undefined; reject(new Error('Google 登录组件加载失败，请重试。')) }
    const timer = setTimeout(fail, 15000)
    script.src = 'https://accounts.google.com/gsi/client'; script.async = true
    script.onload = () => { clearTimeout(timer); if (window.google) resolve(); else fail() }; script.onerror = fail
    document.head.append(script)
  })
}

function IdentityButtons({apple, google, onProof, busy}: {apple?: AppleWebConfig | null; google?: string; onProof: (proof: Proof) => Promise<void>; busy: boolean}) {
  const session = useSession()
  const [nonce, setNonce] = useState('')
  const [error, setError] = useState('')
  const [generation, setGeneration] = useState(0)
  const googleHost = useRef<HTMLDivElement>(null)
  const receive = useRef(onProof); receive.current = onProof
  const locked = useRef(busy); locked.current = busy
  useEffect(() => {
    let live = true
    setNonce(''); setError('')
    void (async () => {
      try {
        const api = new DataApiClient({baseUrl: session.baseUrl})
        const challenge = await api.oauthChallenge()
        if (apple) await loadAppleSDK()
        if (google) await loadGoogle()
        if (!live) return
        setNonce(challenge.nonce)
        if (google && googleHost.current && window.google) {
          window.google.accounts.id.initialize({client_id: google, nonce: challenge.nonce, auto_select: false, callback: response => {
            if (live && !locked.current && response.credential) void receive.current({provider:'google',identity_token:response.credential,nonce:challenge.nonce})
          }})
          googleHost.current.replaceChildren()
          window.google.accounts.id.renderButton(googleHost.current,{type:'standard',theme:'outline',size:'large',text:'signin_with'})
        }
      } catch (e) { if (live) setError(e instanceof Error ? e.message : '登录组件加载失败。') }
    })()
    const timer = setTimeout(() => { if (live) setGeneration(v=>v+1) },240000)
    return () => {live=false;clearTimeout(timer)}
  },[session.baseUrl,apple?.client_id,google,generation])
  const appleSignIn = async () => {
    if (!apple || !nonce || busy) return
    try {
      const state = crypto.randomUUID()
      const response = await startAppleSignIn(apple,nonce,state)
      await onProof({provider:'apple',identity_token:checkedAppleToken(response,state),nonce})
    } catch { setError('Apple 登录未完成，请重试。') }
  }
  return <div className="stack">
    {apple && <Button className="apple-signin__button" disabled={busy || !nonce} onClick={()=>void appleSignIn()}>使用 Apple 登录</Button>}
    {google && <div ref={googleHost} hidden={busy} />}
    {error && <><Notice tone="error">{error}</Notice><Button variant="ghost" onClick={()=>setGeneration(v=>v+1)}>重试</Button></>}
  </div>
}

export function AppleSignIn({ config, googleClientId }: { config?: AppleWebConfig | null; googleClientId?: string }) {
  const session = useSession()
  const [proof,setProof] = useState<Proof | null>(null)
  const [link,setLink] = useState(false)
  const [passwordLink,setPasswordLink] = useState(false)
  const [username,setUsername] = useState('')
  const [password,setPassword] = useState('')
  const [busy,setBusy] = useState(false)
  const [error,setError] = useState('')
  const [capacity,setCapacity] = useState(false)
  const [replaceOldest,setReplaceOldest] = useState(false)
  const submit = async (identity: Proof, action = '', other?: Proof) => {
    if (busy) return
    setBusy(true);setError('')
    const api = new DataApiClient({baseUrl:session.baseUrl})
    let operation: string | undefined
    try {
      const prepared = await api.beginOAuth({...identity,action,replace_oldest:replaceOldest,...(other ? {link:other} : action === 'link' ? {username,password} : {})})
      operation=prepared.operation_id
      const result=await api.completeLogin(operation,`Web · ${identity.provider}`)
      await session.signIn(result.token,result.expires_at)
      setPassword('');setProof(null)
    } catch (e) {
      if (e instanceof ApiError && e.code==='oauth_account_choice_required') { setProof(identity);return }
      const code=e instanceof ApiError ? e.code : ''
      setCapacity(code==='auth_session_capacity')
      setError(({
        invalid_credentials:'账号或密码不正确。',
        apple_link_conflict:'该身份已关联其他账号，无法再次关联。',
        oauth_historical_account_missing:'该身份尚无历史账号，请选择其他方式或创建新账号。',
        apple_registration_disabled:'此服务未开放注册，请关联历史账号。',
        invalid_apple_identity:'验证已过期，请返回重新登录。',
        auth_session_capacity:'登录会话已满，可勾选下方选项后重试。',
      } as Record<string,string>)[code] ?? '登录未完成，请检查网络后重试。')
      if (operation) { try { await api.cancelOperation(operation) } catch { setError('登录清理未完成，请稍后重试。') } }
    } finally {setBusy(false)}
  }
  return <section className="stack" aria-label="账户登录">
    {!proof ? <IdentityButtons apple={config} google={googleClientId} busy={busy} onProof={p=>submit(p)} /> : <>
      <h2>{link ? '关联历史账号' : '首次登录'}</h2>
      {!link ? <><Button variant="primary" disabled={busy} onClick={()=>setLink(true)}>关联历史账号</Button><Button disabled={busy} onClick={()=>void submit(proof,'create')}>创建新账号</Button></> : <>
        {!passwordLink ? <><IdentityButtons apple={proof.provider==='google' ? config : null} google={proof.provider==='apple' ? googleClientId : undefined} busy={busy} onProof={other=>submit(proof,'link',other)} /><Button disabled={busy} onClick={()=>setPasswordLink(true)}>使用账号密码关联</Button></> : <>
          <TextField label="用户名" value={username} disabled={busy} onChange={e=>setUsername(e.target.value)} autoComplete="username" />
          <TextField label="密码" type="password" value={password} disabled={busy} onChange={e=>setPassword(e.target.value)} autoComplete="current-password" />
          <Button disabled={busy || !username || !password} onClick={()=>void submit(proof,'link')}>验证并关联</Button>
        </>}
      </>}
      <Button variant="ghost" disabled={busy} onClick={()=>{setProof(null);setLink(false);setPasswordLink(false);setPassword('');setError('')}}>返回</Button>
    </>}
    {capacity && <label className="row"><input type="checkbox" checked={replaceOldest} disabled={busy} onChange={e=>setReplaceOldest(e.target.checked)} />退出最早的一个会话后重试</label>}
    {error && <Notice tone="error" role="alert">{error}</Notice>}
  </section>
}


export function LinkedSignInMethods() {
  const session = useSession()
  const [providers,setProviders] = useState<string[] | null>(null)
  const [config,setConfig] = useState<AppleWebConfig | null>(null)
  const [google,setGoogle] = useState('')
  const [busy,setBusy] = useState(false)
  const [error,setError] = useState('')
  const load = async () => {
    if (!session.client) return
    setBusy(true);setError('')
    try {
      const [health,linked] = await Promise.all([session.client.health(),session.client.linkedOAuthProviders()])
      setConfig(health.apple_web ?? null);setGoogle(health.google_web_client_id ?? '');setProviders(linked.providers)
    } catch {setError('无法读取关联的登录方式，请重试。')} finally {setBusy(false)}
  }
  useEffect(()=>{void load()},[session.client])
  const link = async (proof: Proof) => {
    if (busy || !session.client) return
    setBusy(true);setError('')
    try {setProviders((await session.client.linkOAuthIdentity(proof)).providers)}
    catch(e) {setError(e instanceof ApiError && e.code==='apple_link_conflict' ? '该身份已关联其他账号，不能绑定到当前账号。' : '关联未完成，请重新验证后重试。')}
    finally {setBusy(false)}
  }
  return <section className="stack" aria-label="关联登录方式">
    {providers?.map(p=><p key={p}>{p==='apple'?'Apple':'Google'} · 已关联</p>)}
    {providers && <IdentityButtons apple={providers.includes('apple')?null:config} google={providers.includes('google')?undefined:google} busy={busy} onProof={link} />}
    {error && <><Notice tone="error">{error}</Notice><Button disabled={busy} onClick={()=>void load()}>重试</Button></>}
  </section>
}
