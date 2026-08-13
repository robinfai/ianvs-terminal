import { defineConfig } from '@playwright/test'

// The servers are started by tools/verify_data_api_webui.sh, which exports the
// per-mode base URLs and the local access token into the environment. Using the
// system Google Chrome avoids a large browser download on developer machines.
export default defineConfig({
  testDir: './tests',
  timeout: 120_000,
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [['list']],
  outputDir: './test-results',
  use: {
    channel: 'chrome',
    headless: true,
    locale: 'en-US',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
})
