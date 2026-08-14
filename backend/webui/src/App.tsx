import { useCallback, useEffect, useRef, useState } from 'react'
import { useSession } from './state/SessionContext'
import { Badge, Button, Spinner } from './components/ui'
import { ConnectPage } from './pages/ConnectPage'
import { ProfilesPage } from './pages/ProfilesPage'
import { SettingsPage } from './pages/SettingsPage'

type View = 'profiles' | 'settings'

const VIEWS: View[] = ['profiles', 'settings']

const NAV_ITEMS: { view: View; label: string; icon: string }[] = [
  { view: 'profiles', label: 'Profiles', icon: '▤' },
  { view: 'settings', label: 'Session', icon: '⚙' },
]

const VIEW_TITLES: Record<View, string> = {
  profiles: 'SSH Profiles',
  settings: 'Session security',
}

function readHash(): View {
  const hash = window.location.hash.replace(/^#\/?/, '')
  return (VIEWS as string[]).includes(hash) ? (hash as View) : 'profiles'
}

export function App() {
  const session = useSession()
  const [view, setView] = useState<View>(() => readHash())

  useEffect(() => {
    const onHashChange = () => setView(readHash())
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  }, [])

  // A fresh sign-in always lands on the Profiles home, regardless of which view
  // the previous session left in the URL hash.
  const wasSignedIn = useRef(Boolean(session.user))
  useEffect(() => {
    if (session.user && !wasSignedIn.current) {
      window.location.hash = '#/profiles'
      setView('profiles')
    }
    wasSignedIn.current = Boolean(session.user)
  }, [session.user])

  const handleSignOut = useCallback(async () => {
    const client = session.client
    if (client && session.mode === 'remote') {
      try {
        await client.logout()
      } catch {
        // Best effort — clearing the local session below is what matters.
      }
    }
    session.signOut()
  }, [session])

  if (session.restoring) {
    return (
      <div className="connect">
        <div className="row">
          <Spinner />
          <span className="secondary">Restoring session…</span>
        </div>
      </div>
    )
  }

  if (!session.client || !session.mode || !session.user) {
    return <ConnectPage />
  }

  const title = VIEW_TITLES[view]

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand__mark" aria-hidden="true">
            ▮
          </span>
          <span>
            <span className="brand__name">Ianvs SSH</span>
            <span className="brand__sub">Profile vault</span>
          </span>
        </div>
        <nav className="nav" aria-label="Main">
          {NAV_ITEMS.map((item) => (
            <a
              key={item.view}
              className="nav__link"
              href={`#/${item.view}`}
              aria-current={view === item.view ? 'page' : undefined}
            >
              <span className="nav__icon" aria-hidden="true">
                {item.icon}
              </span>
              {item.label}
            </a>
          ))}
        </nav>
        <div className="sidebar__footer">
          <span className="break-word">{session.baseUrl}</span>
          <span>
            Mode <Badge tone={session.mode === 'local' ? 'info' : 'success'}>{session.mode}</Badge>
          </span>
        </div>
      </aside>

      <div className="workspace">
        <header className="topbar">
          <span className="topbar__title" aria-hidden="true">
            {title}
          </span>
          <span className="topbar__spacer" />
          <div className="topbar__meta">
            <Badge tone={session.mode === 'local' ? 'info' : 'success'}>{session.mode}</Badge>
            <Badge tone="neutral">@{session.user.username}</Badge>
            <Badge tone={session.key ? 'success' : 'warning'}>
              {session.key ? 'Key ready' : 'Key on demand'}
            </Badge>
            <Button variant="ghost" onClick={handleSignOut}>
              Disconnect
            </Button>
          </div>
        </header>

        <main className="main" id="main-content" tabIndex={-1}>
          {view === 'profiles' ? <ProfilesPage /> : null}
          {view === 'settings' ? <SettingsPage /> : null}
        </main>
      </div>
    </div>
  )
}
