import { useCallback, useEffect, useRef, useState } from 'react'
import { useSession } from './state/SessionContext'
import { ThemeSelect } from './state/ThemeContext'
import { Badge, Button, Dialog, Notice, Spinner } from './components/ui'
import { ConnectPage } from './pages/ConnectPage'
import { ProfilesPage } from './pages/ProfilesPage'
import { SettingsPage } from './pages/SettingsPage'
import { OverviewPage } from './pages/OverviewPage'
import { SyncPage } from './pages/SyncPage'
import { AdminPage } from './pages/AdminPage'

type View = 'overview' | 'profiles' | 'sync' | 'settings' | 'admin'
const NAV_ITEMS: { view: View; label: string }[] = [
  { view: 'overview', label: '总览' },
  { view: 'profiles', label: 'SSH 配置' },
  { view: 'sync', label: '同步与换机' },
  { view: 'settings', label: '安全与会话' },
  { view: 'admin', label: 'AI 网关管理' },
]
function readHash(locationHash = window.location.hash): View {
  const hash = locationHash.replace(/^#\/?/, '')
  return NAV_ITEMS.some((item) => item.view === hash) ? (hash as View) : 'overview'
}
export function App() {
  const session = useSession()
  const [view, setView] = useState<View>(() => readHash())
  const [signOutOpen, setSignOutOpen] = useState(false)
  const [signOutBusy, setSignOutBusy] = useState(false)
  const [signOutError, setSignOutError] = useState<string | null>(null)
  useEffect(() => {
    const onHashChange = (event: HashChangeEvent) => {
      const hash = new URL(event.newURL).hash
      if (hash !== '#main-content') setView(readHash(hash))
      requestAnimationFrame(() => {
        document.getElementById('main-content')?.focus({ preventScroll: true })
        window.scrollTo({ top: 0 })
      })
    }
    const skipLink = document.querySelector<HTMLAnchorElement>('a[href="#main-content"]')
    const skipToContent = (event: MouseEvent) => {
      event.preventDefault()
      document.getElementById('main-content')?.focus()
    }
    skipLink?.addEventListener('click', skipToContent)
    window.addEventListener('hashchange', onHashChange)
    return () => {
      window.removeEventListener('hashchange', onHashChange)
      skipLink?.removeEventListener('click', skipToContent)
    }
  }, [])
  const wasSignedIn = useRef(Boolean(session.user))
  const restoringInitialSession = useRef(session.restoring)
  useEffect(() => {
    // Keep deep links when restoring an existing tab session. A fresh login
    // still starts at the overview, including after failed restoration.
    if (session.user && !wasSignedIn.current && !restoringInitialSession.current) {
      window.location.hash = '#/overview'
      setView('overview')
    }
    wasSignedIn.current = Boolean(session.user)
    if (!session.restoring) restoringInitialSession.current = false
  }, [session.user, session.restoring])
  const closeSignOut = useCallback(() => {
    if (!signOutBusy) setSignOutOpen(false)
  }, [signOutBusy])
  const handleSignOut = useCallback(async () => {
    if (signOutBusy) return
    setSignOutBusy(true)
    setSignOutError(null)
    try {
      if (session.client && session.mode === 'remote') await session.client.logout()
      session.signOut()
      setSignOutOpen(false)
    } catch {
      setSignOutError('服务端退出未确认，当前会话已保留。请重试；本次不会仅清除浏览器凭证。')
    } finally {
      setSignOutBusy(false)
    }
  }, [session, signOutBusy])
  if (session.restoring || !session.client || !session.mode || !session.user) {
    return <>
      <header className="public-header">
        <span className="public-header__brand">Ianvs <span>用户控制台</span></span>
        <ThemeSelect />
      </header>
      {session.restoring ? <main className="connect" id="main-content" tabIndex={-1}>
        <div className="row"><Spinner label="正在恢复会话" /><span className="secondary">正在验证已保存的会话…</span></div>
      </main> : <ConnectPage />}
    </>
  }
  const title = NAV_ITEMS.find((item) => item.view === view)?.label
  return <div className="app-shell">
    <aside className="sidebar" aria-label="控制台导航">
      <a className="brand" href="#/overview" aria-label="Ianvs 用户控制台总览">
        <span><span className="brand__name">Ianvs</span><span className="brand__sub">用户控制台</span></span>
      </a>
      <nav className="nav" aria-label="主导航">
        {NAV_ITEMS.filter(item => item.view !== 'admin' || session.isAdmin).map((item) => <a key={item.view} className="nav__link" href={`#/${item.view}`} aria-current={view === item.view ? 'page' : undefined}>{item.label}</a>)}
      </nav>
      <div className="sidebar__footer">
        <span>当前服务</span><span className="break-word">{session.baseUrl}</span>
        <span><Badge tone={session.mode === 'local' ? 'info' : 'success'}>{session.mode === 'local' ? '本地服务' : '远程服务'}</Badge></span>
        <span>账号登录与数据密钥分别管理。</span>
      </div>
    </aside>
    <div className="workspace">
      <header className="topbar">
        <span className="topbar__title" aria-hidden="true">{title}</span>
        <div className="topbar__meta">
          <Badge tone="neutral">@{session.user.username}</Badge>
          <Badge tone={session.key ? 'info' : 'warning'}>{session.key ? '密钥已载入，使用时验证' : '敏感凭据按需解锁'}</Badge>
          <ThemeSelect />
          <Button variant="ghost" onClick={() => { setSignOutError(null); setSignOutOpen(true) }}>{session.mode === 'local' ? '断开连接' : '退出登录'}</Button>
        </div>
      </header>
      <main className="main" id="main-content" tabIndex={-1}>
        {view === 'overview' ? <OverviewPage /> : null}
        {view === 'profiles' ? <ProfilesPage /> : null}
        {view === 'sync' ? <SyncPage /> : null}
        {view === 'settings' ? <SettingsPage /> : null}
        {view === 'admin' ? <AdminPage /> : null}
      </main>
    </div>
    <Dialog open={signOutOpen} title={session.mode === 'local' ? '断开本地服务连接？' : '退出当前会话？'} onClose={closeSignOut}
      footer={<>
        <Button data-dialog-initial-focus onClick={closeSignOut} disabled={signOutBusy}>取消</Button>
        <Button variant="danger" onClick={handleSignOut} busy={signOutBusy}>{signOutError ? '重试退出' : session.mode === 'local' ? '确认断开连接' : '确认退出登录'}</Button>
      </>}>
      <p>{session.mode === 'local' ? '断开会清除此浏览器的连接凭证和内存密钥，不会关闭本地服务或撤销其访问令牌。' : '退出会在服务端撤销当前会话，并清除此浏览器的登录凭证与内存密钥。其他会话不受影响。'}</p>
      <p className="secondary">已保存的配置不会删除。再次使用时需要重新连接或登录。</p>
      {signOutError ? <Notice tone="error" role="alert">{signOutError}</Notice> : null}
    </Dialog>
  </div>
}
