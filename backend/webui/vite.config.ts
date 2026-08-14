import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The built assets are embedded into the Go binary and served from the root
// path, so every asset reference must be absolute.
export default defineConfig({
  plugins: [react()],
  base: '/',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    target: 'es2020',
    sourcemap: false,
  },
})
