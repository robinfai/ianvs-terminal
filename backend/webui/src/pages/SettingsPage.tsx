import { useEffect, useState } from 'react'
import { useSession } from '../state/SessionContext'
import { Badge, Button, Card, Notice } from '../components/ui'
import { maskSecret } from '../lib/format'

export function SettingsPage() {
  const session = useSession()
  const [signingOut, setSigningOut] = useState(false)
  const [sessions, setSessions] = useState<{id: string; device_name: string; created_at: string; expires_at: string; current: boolean}[]>([])
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const refresh = async () => {
    if (!session.client || session.mode !== 'remote') return
    setError(null)
    try { setSessions((await session.client.listSessions()).sessions) }
    catch (err) { setError(err instanceof Error ? err.message : String(err)) }
  }
  useEffect(() => { void refresh() }, [session.client, session.mode])
  const revoke = async (ids: string[]) => {
    if (!session.client || busy || ids.length === 0) return
    if (!window.confirm(`Sign out ${ids.length} session(s)? Those clients will need to sign in again.`)) return
    setBusy(true)
    setError(null)
    try {
      for (const id of ids) await session.client.revokeSession(id)
    } catch (err) { setError(err instanceof Error ? err.message : String(err)); setBusy(false); return }
    await refresh()
    setBusy(false)
  }

  const signOut = async () => {
    setSigningOut(true)
    setError(null)
    try {
      if (session.client && session.mode === 'remote') await session.client.logout()
      session.signOut()
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally { setSigningOut(false) }
  }

  return (
    <div className="page">
      <header className="page__header">
        <div>
          <h1 className="page__title">Session security</h1>
          <p className="page__subtitle">Current identity, endpoint and client-owned encryption key.</p>
        </div>
      </header>

      <Card title="Session">
        <div className="card__body">
          <dl className="kv-list">
            <div className="kv">
              <dt>Endpoint</dt>
              <dd className="break-word">{session.baseUrl}</dd>
            </div>
            <div className="kv">
              <dt>Mode</dt>
              <dd>
                <Badge tone={session.mode === 'local' ? 'info' : 'success'}>{session.mode}</Badge>
              </dd>
            </div>
            <div className="kv">
              <dt>User</dt>
              <dd>@{session.user?.username}</dd>
            </div>
            <div className="kv">
              <dt>Bearer token</dt>
              <dd className="mono">{session.token ? maskSecret(session.token) : '—'}</dd>
            </div>
          </dl>
        </div>
      </Card>

      {error ? <Notice tone="error" role="alert">{error}</Notice> : null}
      {session.mode === 'remote' ? <Card title="Signed-in sessions">
        <div className="card__body stack">
          <p className="secondary">{sessions.length} of 8 sign-in slots used by active sessions.
            Pending sign-ins also reserve a slot for up to five minutes.
            Closing a browser tab does not sign out its server session.</p>
          <div className="row">
            <Button onClick={refresh} disabled={busy}>Refresh sessions</Button>
            <Button variant="danger" disabled={busy || !sessions.some(s => !s.current)}
              onClick={() => revoke(sessions.filter(s => !s.current).map(s => s.id))}>
              Sign out other sessions
            </Button>
          </div>
          {sessions.map(s => <div className="stack" key={s.id}>
            <strong className="break-word">{s.device_name || 'Older session · device unknown'}{s.current ? ' · This session' : ''}</strong>
            <span className="secondary">Session {s.id.slice(0, 8)}</span>
            <span>Created: {new Date(s.created_at).toLocaleString()}</span>
            <span>Expires: {new Date(s.expires_at).toLocaleString()}</span>
            {!s.current ? <div><Button variant="danger" disabled={busy}
              onClick={() => revoke([s.id])}>Sign out session</Button></div> : null}
          </div>)}
        </div>
      </Card> : null}

      <Card title="Encryption key on demand">
        <div className="card__body stack">
          <p className="secondary">
            Sign-in never requests or verifies the client-owned key. Sensitive profile operations
            ask for it when needed and keep it only in page memory until refresh, sign out or forget.
          </p>
          <div className="row">
            <Badge tone={session.key ? 'success' : 'warning'}>
              {session.key ? 'Key ready' : 'No key in this session'}
            </Badge>
            <Badge tone="neutral">never sent to the server</Badge>
          </div>
          {session.key ? (
            <div className="row">
              <Button type="button" variant="ghost" onClick={session.clearKey}>
                Forget key
              </Button>
            </div>
          ) : null}
        </div>
      </Card>

      <Card title="Account">
        <div className="card__body stack">
          <p className="secondary">
            Signing out revokes the remote session token (when applicable) and clears this console
            session.
          </p>
          <div className="row">
            <Button variant="danger" onClick={signOut} busy={signingOut}>
              Sign out
            </Button>
          </div>
        </div>
      </Card>
    </div>
  )
}
