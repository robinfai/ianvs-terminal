import { useEffect, useState, type FormEvent } from 'react'
import { ApiError, DataApiClient } from '../api/client'
import { useSession } from '../state/SessionContext'
import { Badge, Button, Notice, Spinner, TextField } from '../components/ui'
import type { Mode } from '../types'

type ConnectionState = Mode | 'detecting' | 'error'

export function ConnectPage() {
  const session = useSession()
  const [connectionState, setConnectionState] = useState<ConnectionState>('detecting')
  const [error, setError] = useState<string | null>(null)

  const detect = async () => {
    setConnectionState('detecting')
    setError(null)
    try {
      setConnectionState(await detectMode(session.baseUrl))
    } catch (err) {
      setConnectionState('error')
      setError(err instanceof Error ? err.message : String(err))
    }
  }

  useEffect(() => {
    void detect()
    // The embedded console is permanently bound to its own API origin.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session.baseUrl])

  return (
    <main className="connect" id="main-content">
      <section className="terminal-login" aria-labelledby="login-title">
        <header className="terminal-login__bar">
          <span className="terminal-login__lights" aria-hidden="true">
            <i />
            <i />
            <i />
          </span>
          <span>ianvs — secure profile access</span>
          <Badge tone={connectionState === 'remote' ? 'success' : 'info'}>
            {connectionState === 'detecting' ? 'probing' : connectionState}
          </Badge>
        </header>

        <div className="terminal-login__body">
          <div className="terminal-login__intro">
            <p className="terminal-line" aria-hidden="true">
              <span className="terminal-prompt">$</span> ianvs profiles login
            </p>
            <h1 id="login-title">Unlock SSH profiles</h1>
            <p>
              Authenticate to manage profiles. Your client-owned encryption key is requested only
              when you encrypt, decrypt or rewrite sensitive fields.
            </p>
          </div>

          {connectionState === 'detecting' ? (
            <div className="terminal-login__status" role="status">
              <Spinner label="Detecting service mode" />
              <span>Detecting service mode…</span>
            </div>
          ) : null}

          {connectionState === 'remote' ? <RemoteAccess baseUrl={session.baseUrl} /> : null}
          {connectionState === 'local' ? <LocalForm /> : null}
          {connectionState === 'error' ? (
            <div className="stack">
              <Notice tone="error" role="alert">
                {error ?? 'The profile service is unavailable.'}
              </Notice>
              <Button type="button" variant="primary" onClick={detect}>
                Retry connection
              </Button>
            </div>
          ) : null}

          <footer className="terminal-login__footer">
            <span className="terminal-prompt" aria-hidden="true">
              ›
            </span>
            <span className="break-word">{session.baseUrl}</span>
            <span>· credentials stay in this browser tab</span>
          </footer>
        </div>
      </section>
    </main>
  )
}

async function detectMode(baseUrl: string): Promise<Mode> {
  const client = new DataApiClient({ baseUrl })
  try {
    const health = await client.health()
    return health.mode
  } catch (err) {
    // Local mode protects even /healthz with its sidecar bearer token.
    if (err instanceof ApiError && (err.status === 401 || err.status === 403)) {
      return 'local'
    }
    throw err
  }
}

function LocalForm() {
  const session = useSession()
  const [token, setToken] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const connect = async (event: FormEvent) => {
    event.preventDefault()
    setError(null)
    setBusy(true)
    try {
      const accessToken = token.trim()
      await session.signIn(accessToken)
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <form className="terminal-form" onSubmit={connect}>
      <Notice tone="info">
        Local sidecar detected. Use its access token now; the encryption key is requested only for
        sensitive profile operations.
      </Notice>
      <TextField
        label="Local access token"
        type="password"
        value={token}
        onChange={(event) => setToken(event.target.value)}
        autoComplete="off"
        required
        hint="The 43-character bearer token issued by the local sidecar."
      />
      {error ? (
        <Notice tone="error" role="alert">
          {error}
        </Notice>
      ) : null}
      <Button type="submit" variant="primary" busy={busy}>
        Unlock profiles
      </Button>
    </form>
  )
}

function RemoteAccess({ baseUrl }: { baseUrl: string }) {
  const [tab, setTab] = useState<'login' | 'register'>('login')
  return (
    <div className="stack">
      <div className="segmented" role="tablist" aria-label="Account access">
        <button
          id="login-tab"
          type="button"
          role="tab"
          aria-selected={tab === 'login'}
          aria-controls="login-panel"
          onClick={() => setTab('login')}
        >
          Sign in
        </button>
        <button
          id="register-tab"
          type="button"
          role="tab"
          aria-selected={tab === 'register'}
          aria-controls="register-panel"
          onClick={() => setTab('register')}
        >
          Create account
        </button>
      </div>
      <div
        id={tab === 'login' ? 'login-panel' : 'register-panel'}
        role="tabpanel"
        aria-labelledby={tab === 'login' ? 'login-tab' : 'register-tab'}
      >
        {tab === 'login' ? <LoginForm baseUrl={baseUrl} /> : <RegisterForm baseUrl={baseUrl} />}
      </div>
    </div>
  )
}

function LoginForm({ baseUrl }: { baseUrl: string }) {
  const session = useSession()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    setError(null)
    setBusy(true)
    const anonymous = new DataApiClient({ baseUrl })
    let issuedToken: string | null = null
    try {
      const prepared = await anonymous.beginLogin(username.trim(), password)
      const sessionResult = await anonymous.completeLogin(prepared.operation_id)
      issuedToken = sessionResult.token
      await session.signIn(sessionResult.token)
    } catch (err) {
      if (issuedToken) {
        try {
          await new DataApiClient({ baseUrl, token: issuedToken }).logout()
        } catch {
          // Best-effort cleanup; the invalid token was never persisted locally.
        }
      }
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <form className="terminal-form" onSubmit={submit}>
      <TextField
        label="Username"
        type="text"
        value={username}
        onChange={(event) => setUsername(event.target.value)}
        autoComplete="username"
        required
      />
      <TextField
        label="Password"
        type="password"
        value={password}
        onChange={(event) => setPassword(event.target.value)}
        autoComplete="current-password"
        required
      />
      {error ? (
        <Notice tone="error" role="alert">
          {error}
        </Notice>
      ) : null}
      <Button type="submit" variant="primary" busy={busy}>
        Unlock profiles
      </Button>
    </form>
  )
}

function RegisterForm({ baseUrl }: { baseUrl: string }) {
  const session = useSession()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [key, setKey] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    setError(null)
    setBusy(true)
    try {
      const anonymous = new DataApiClient({ baseUrl })
      const prepared = await anonymous.beginRegister(username.trim(), password, key)
      const sessionResult = await anonymous.completeRegister(prepared.operation_id)
      await session.signIn(sessionResult.token)
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <form className="terminal-form" onSubmit={submit}>
      <Notice tone="warning">Account creation may be disabled by the server administrator.</Notice>
      <TextField
        label="Username"
        type="text"
        value={username}
        onChange={(event) => setUsername(event.target.value)}
        autoComplete="username"
        required
        hint="3–64 lowercase letters, numbers, dots, underscores or hyphens."
      />
      <TextField
        label="Password"
        type="password"
        value={password}
        onChange={(event) => setPassword(event.target.value)}
        autoComplete="new-password"
        required
        hint="At least 12 characters."
      />
      <TextField
        label="Encryption key"
        type="password"
        value={key}
        onChange={(event) => setKey(event.target.value)}
        autoComplete="off"
        required
        hint="Required once to configure the account verifier; later sign-ins do not request it."
      />
      {error ? (
        <Notice tone="error" role="alert">
          {error}
        </Notice>
      ) : null}
      <Button type="submit" variant="primary" busy={busy}>
        Create and unlock
      </Button>
    </form>
  )
}
