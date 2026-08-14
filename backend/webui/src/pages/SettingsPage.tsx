import { useState } from 'react'
import { useSession } from '../state/SessionContext'
import { Badge, Button, Card } from '../components/ui'
import { maskSecret } from '../lib/format'

export function SettingsPage() {
  const session = useSession()
  const [signingOut, setSigningOut] = useState(false)

  const signOut = async () => {
    setSigningOut(true)
    try {
      if (session.client && session.mode === 'remote') {
        try {
          await session.client.logout()
        } catch {
          // Ignore — local session is cleared regardless.
        }
      }
    } finally {
      session.signOut()
    }
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
            {session.user?.key_configured ? (
              <Badge tone="neutral">account key configured</Badge>
            ) : (
              <Badge tone="warning">account key not configured</Badge>
            )}
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
