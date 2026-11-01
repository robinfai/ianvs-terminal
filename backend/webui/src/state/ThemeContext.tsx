import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'

export type ThemePreference = 'system' | 'light' | 'dark'
const THEME_KEY = 'ianvs.theme'
const ThemeContext = createContext<{
  theme: ThemePreference
  setTheme: (theme: ThemePreference) => void
} | null>(null)

function parseTheme(value: string | null): ThemePreference {
  return value === 'light' || value === 'dark' ? value : 'system'
}

function readTheme(): ThemePreference {
  try {
    return parseTheme(localStorage.getItem(THEME_KEY))
  } catch {
    return 'system'
  }
}

function applyTheme(theme: ThemePreference) {
  const resolved = theme === 'system'
    ? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
    : theme
  document.documentElement.dataset.theme = resolved
  const background = getComputedStyle(document.documentElement).getPropertyValue('--color-bg').trim()
  if (background) document.querySelector('meta[name="theme-color"]')?.setAttribute('content', background)
}

/** Apply the saved preference before React paints the first screen. */
export function initializeTheme() {
  applyTheme(readTheme())
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setPreference] = useState<ThemePreference>(readTheme)

  useEffect(() => {
    applyTheme(theme)
    const media = window.matchMedia('(prefers-color-scheme: dark)')
    const onChange = () => {
      if (theme === 'system') applyTheme('system')
    }
    media.addEventListener('change', onChange)
    return () => media.removeEventListener('change', onChange)
  }, [theme])

  useEffect(() => {
    const onStorage = (event: StorageEvent) => {
      if (event.storageArea === localStorage && (event.key === THEME_KEY || event.key === null)) {
        const next = parseTheme(event.newValue)
        setPreference(next)
        applyTheme(next)
      }
    }
    window.addEventListener('storage', onStorage)
    return () => window.removeEventListener('storage', onStorage)
  }, [])

  const setTheme = (next: ThemePreference) => {
    setPreference(next)
    applyTheme(next)
    try {
      localStorage.setItem(THEME_KEY, next)
    } catch {
      // Restricted storage still permits switching for this page lifetime.
    }
  }

  return <ThemeContext.Provider value={{ theme, setTheme }}>{children}</ThemeContext.Provider>
}

export function ThemeSelect() {
  const context = useContext(ThemeContext)
  if (!context) throw new Error('ThemeSelect requires ThemeProvider')
  return (
    <label className="theme-select">
      <span>外观</span>
      <select
        aria-label="选择外观主题"
        value={context.theme}
        onChange={(event) => context.setTheme(parseTheme(event.target.value))}
      >
        <option value="system">跟随系统</option>
        <option value="light">浅色</option>
        <option value="dark">深色</option>
      </select>
    </label>
  )
}
