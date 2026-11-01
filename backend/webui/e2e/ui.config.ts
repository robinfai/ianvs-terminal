import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './ui',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [['list']],
  outputDir: './ui-results',
  use: {
    baseURL: 'http://127.0.0.1:4174',
    headless: true,
    locale: 'zh-CN',
    launchOptions: process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {},
    screenshot: 'only-on-failure',
  },
  webServer: { command: 'pnpm dev --host 127.0.0.1 --port 4174 --strictPort', url: 'http://127.0.0.1:4174', reuseExistingServer: !process.env.CI },
})
