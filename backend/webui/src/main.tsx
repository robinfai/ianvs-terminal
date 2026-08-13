import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { SessionProvider } from './state/SessionContext'
import { App } from './App'
import './styles.css'

const container = document.getElementById('root')
if (!container) {
  throw new Error('Root element #root was not found.')
}

createRoot(container).render(
  <StrictMode>
    <SessionProvider>
      <App />
    </SessionProvider>
  </StrictMode>,
)
