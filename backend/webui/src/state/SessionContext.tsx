import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { ApiError, DataApiClient } from '../api/client'
import { Button, Dialog, Notice, TextField } from '../components/ui'
import type { Mode, User } from '../types'

const TOKEN_KEY = 'ianvs.token'
const EXPIRY_KEY = 'ianvs.session-expiry'

const DEFAULT_BASE_URL = window.location.origin

interface KeyPromptState {
  reason: string
  resolve: (key: string | null) => void
}

interface SessionState {
  isAdmin: boolean
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
  signIn: (token: string, expiresAt?: string) => Promise<User>
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
  const token = localStorage.getItem(TOKEN_KEY) ?? sessionStorage.getItem(TOKEN_KEY)
  const expiry = localStorage.getItem(EXPIRY_KEY)
  if (expiry && Date.parse(expiry) <= Date.now()) return null
  if (token) localStorage.setItem(TOKEN_KEY, token)
  sessionStorage.removeItem(TOKEN_KEY)
  return token
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [baseUrl] = useState(DEFAULT_BASE_URL)
  const [token, setToken] = useState<string | null>(() => readStoredToken())
  const [key, setKeyState] = useState<string | null>(null)
  const [mode, setMode] = useState<Mode | null>(null)
  const [isAdmin, setIsAdmin] = useState(false)
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
    localStorage.removeItem(TOKEN_KEY)
    localStorage.removeItem(EXPIRY_KEY)
    setToken(null)
  }, [])

  const signIn = useCallback(
    async (newToken: string, expiresAt?: string): Promise<User> => {
      const client = new DataApiClient({ baseUrl, token: newToken })
      const [health, response] = await Promise.all([client.health(), client.me()])
      localStorage.setItem(TOKEN_KEY, newToken)
      if (expiresAt) localStorage.setItem(EXPIRY_KEY, expiresAt)
      else localStorage.removeItem(EXPIRY_KEY)
      setToken(newToken)
      clearKey()
      setMode(health.mode)
      setUser(response.user); setIsAdmin(response.is_admin === true)
      return response.user
    },
    [baseUrl, clearKey],
  )

  const refreshUser = useCallback(async () => {
    if (!token) return
    const client = new DataApiClient({ baseUrl, token })
    const [health, response] = await Promise.all([client.health(), client.me()])
    setMode(health.mode)
    setUser(response.user); setIsAdmin(response.is_admin === true)
  }, [baseUrl, token])

  const signOut = useCallback(() => {
    clearToken()
    clearKey()
    setUser(null); setIsAdmin(false)
    setMode(null)
  }, [clearKey, clearToken])

  useEffect(() => {
    const expire = (event: Event) => {
      if ((event as CustomEvent<string>).detail === token && localStorage.getItem(TOKEN_KEY) === token) signOut()
    }
    const check = () => {
      if (!token || document.visibilityState !== 'visible') return
      const expiry = localStorage.getItem(EXPIRY_KEY)
      if (expiry && Date.parse(expiry) <= Date.now()) { signOut(); return }
      void refreshUser().catch(() => {}) // 401 is handled by the client event.
    }
    const changed = (event: StorageEvent) => {
      if (event.key === TOKEN_KEY) {
        setToken(readStoredToken()); clearKey(); setUser(null); setIsAdmin(false)
      }
    }
    window.addEventListener('ianvs-session-expired', expire)
    window.addEventListener('storage', changed)
    window.addEventListener('focus', check)
    document.addEventListener('visibilitychange', check)
    const timer = window.setInterval(check, 30000)
    const expiry = Date.parse(localStorage.getItem(EXPIRY_KEY) ?? '')
    const expiryTimer = Number.isFinite(expiry)
      ? window.setTimeout(check, Math.min(2147483647, Math.max(0, expiry - Date.now())))
      : undefined
    return () => {
      window.removeEventListener('ianvs-session-expired', expire)
      window.removeEventListener('storage', changed)
      window.removeEventListener('focus', check)
      document.removeEventListener('visibilitychange', check)
      window.clearInterval(timer)
      window.clearTimeout(expiryTimer)
    }
  }, [token, signOut, refreshUser, clearKey])

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
        setUser(response.user); setIsAdmin(response.is_admin === true)
      })
      .catch((error) => {
        if (cancelled) return
        if (!(error instanceof ApiError) || (error.status !== 401 && error.status !== 403)) return
        clearToken()
        clearKey()
        setUser(null); setIsAdmin(false)
        setMode(null)
      })
      .finally(() => {
        if (!cancelled) setRestoring(false)
      })
    return () => {
      cancelled = true
    }
  }, [baseUrl, token, clearKey, clearToken])

  const client = useMemo(() => {
    if (!token) return null
    return new DataApiClient({ baseUrl, token })
  }, [baseUrl, token])

  const value: SessionContextValue = {
    isAdmin,
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
      title="提供数据密钥"
      onClose={onCancel}
      footer={
        <>
          <Button type="submit" variant="primary" form="key-prompt-form" busy={busy}>
            继续本地操作
          </Button>
          <Button type="button" onClick={onCancel}>
            取消
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
        <p className="secondary">{reason.includes("Modifying") ? "改写现有敏感配置前，需要在本地解密并重新加密。" : reason.includes("Saving") ? "保存敏感配置前，需要使用数据密钥在本地加密。" : "此操作需要数据密钥。解密是否成功将在实际操作时校验；密钥不会上传服务器。"}</p>
        <TextField
          label="数据密钥"
          type="password"
          value={value}
          onChange={(event) => setValue(event.target.value)}
          autoComplete="off"
          required
          hint="仅保存在本页内存，刷新、退出或忘记后清除。输入密钥不代表已经校验成功。"
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
