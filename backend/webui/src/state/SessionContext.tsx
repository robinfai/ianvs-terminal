import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { DataApiClient } from '../api/client'
import { Button, Dialog, Notice, TextField } from '../components/ui'
import type { Mode, User } from '../types'

const TOKEN_KEY = 'ianvs.token'

const DEFAULT_BASE_URL = window.location.origin

interface KeyPromptState {
  reason: string
  resolve: (key: string | null) => void
}

interface SessionState {
  baseUrl: string
  token: string | null
  key: string | null
  mode: Mode | null
  user: User | null
  /** True while the initial restore probe is in flight. */
  restoring: boolean
}

interface SessionContextValue extends SessionState {
  client: DataApiClient | null
  signIn: (token: string) => Promise<User>
  clearKey: () => void
  refreshUser: () => Promise<void>
  signOut: () => void
  /**
   * Resolves with the in-memory encryption key when one is already set,
   * otherwise prompts the user and keeps it only in page memory.
   * Returns null when the user cancels. Authentication never requests a key.
   */
  requestKey: (reason: string) => Promise<string | null>
}

const SessionContext = createContext<SessionContextValue | null>(null)

function readStoredToken(): string | null {
  return sessionStorage.getItem(TOKEN_KEY)
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [baseUrl] = useState(DEFAULT_BASE_URL)
  const [token, setToken] = useState<string | null>(() => readStoredToken())
  const [key, setKeyState] = useState<string | null>(null)
  const [mode, setMode] = useState<Mode | null>(null)
  const [user, setUser] = useState<User | null>(null)
  const [restoring, setRestoring] = useState<boolean>(() => Boolean(readStoredToken()))
  const [keyPrompt, setKeyPrompt] = useState<KeyPromptState | null>(null)
  const [keyPromptError, setKeyPromptError] = useState<string | null>(null)
  const keyPromptBusy = false

  const clearKey = useCallback(() => {
    setKeyState(null)
  }, [])

  const clearToken = useCallback(() => {
    sessionStorage.removeItem(TOKEN_KEY)
    setToken(null)
  }, [])

  const signIn = useCallback(
    async (newToken: string): Promise<User> => {
      const client = new DataApiClient({ baseUrl, token: newToken })
      const [health, response] = await Promise.all([client.health(), client.me()])
      sessionStorage.setItem(TOKEN_KEY, newToken)
      setToken(newToken)
      clearKey()
      setMode(health.mode)
      setUser(response.user)
      return response.user
    },
    [baseUrl, clearKey],
  )

  const refreshUser = useCallback(async () => {
    if (!token) return
    const client = new DataApiClient({ baseUrl, token })
    const [health, response] = await Promise.all([client.health(), client.me()])
    setMode(health.mode)
    setUser(response.user)
  }, [baseUrl, token])

  const signOut = useCallback(() => {
    clearToken()
    clearKey()
    setUser(null)
    setMode(null)
  }, [clearKey, clearToken])

  const requestKey = useCallback(
    (reason: string): Promise<string | null> => {
      if (key) return Promise.resolve(key)
      return new Promise<string | null>((resolve) => {
        setKeyPromptError(null)
        setKeyPrompt({ reason, resolve })
      })
    },
    [key],
  )

  const submitKeyPrompt = useCallback(
    (value: string) => {
      const current = keyPrompt
      if (!current || !token) return
      setKeyPromptError(null)
      setKeyState(value)
      current.resolve(value)
      setKeyPrompt(null)
    },
    [keyPrompt, token],
  )

  const cancelKeyPrompt = useCallback(() => {
    keyPrompt?.resolve(null)
    setKeyPrompt(null)
    setKeyPromptError(null)
  }, [keyPrompt])

  // Restore an existing session by validating the stored token against /v1/me.
  useEffect(() => {
    const storedToken = readStoredToken()
    if (!storedToken) {
      clearToken()
      clearKey()
      setRestoring(false)
      return
    }
    let cancelled = false
    const client = new DataApiClient({
      baseUrl,
      token: storedToken,
    })
    Promise.all([client.health(), client.me()])
      .then(([health, response]) => {
        if (cancelled) return
        setMode(health.mode)
        setUser(response.user)
      })
      .catch(() => {
        if (cancelled) return
        clearToken()
        clearKey()
        setUser(null)
        setMode(null)
      })
      .finally(() => {
        if (!cancelled) setRestoring(false)
      })
    return () => {
      cancelled = true
    }
  }, [baseUrl, clearKey, clearToken])

  const client = useMemo(() => {
    if (!token) return null
    return new DataApiClient({ baseUrl, token })
  }, [baseUrl, token])

  const value: SessionContextValue = {
    baseUrl,
    token,
    key,
    mode,
    user,
    restoring,
    client,
    signIn,
    clearKey,
    refreshUser,
    signOut,
    requestKey,
  }

  return (
    <SessionContext.Provider value={value}>
      {children}
      {keyPrompt ? (
        <KeyPromptDialog
          reason={keyPrompt.reason}
          error={keyPromptError}
          busy={keyPromptBusy}
          onSubmit={submitKeyPrompt}
          onCancel={cancelKeyPrompt}
        />
      ) : null}
    </SessionContext.Provider>
  )
}

function KeyPromptDialog({
  reason,
  error,
  busy,
  onSubmit,
  onCancel,
}: {
  reason: string
  error: string | null
  busy: boolean
  onSubmit: (key: string) => void
  onCancel: () => void
}) {
  const [value, setValue] = useState('')
  return (
    <Dialog
      open
      title="Encryption key required"
      onClose={onCancel}
      footer={
        <>
          <Button type="submit" variant="primary" form="key-prompt-form" busy={busy}>
            Unlock
          </Button>
          <Button type="button" onClick={onCancel}>
            Cancel
          </Button>
        </>
      }
    >
      <form
        id="key-prompt-form"
        className="stack"
        onSubmit={(event) => {
          event.preventDefault()
          if (value.length > 0) onSubmit(value)
        }}
      >
        <p className="secondary">{reason}</p>
        <TextField
          label="Encryption key"
          type="password"
          value={value}
          onChange={(event) => setValue(event.target.value)}
          autoComplete="off"
          required
          hint="Your client-owned data key. It stays in memory until refresh, sign out or forget."
        />
        {error ? (
          <Notice tone="error" role="alert">
            {error}
          </Notice>
        ) : null}
      </form>
    </Dialog>
  )
}

export function useSession(): SessionContextValue {
  const context = useContext(SessionContext)
  if (!context) {
    throw new Error('useSession must be used within a SessionProvider')
  }
  return context
}
