import { test, expect, type Page } from '@playwright/test'
import { requireEnv } from './env'

const LOCAL_URL = requireEnv('WEBUI_LOCAL_URL')
const TOKEN = requireEnv('WEBUI_LOCAL_TOKEN')
const KEY = '0123456789abcdef' // 16 bytes — the minimum valid data key.

async function connectLocal(page: Page): Promise<void> {
  await page.goto(LOCAL_URL)
  await expect(page.getByRole('heading', { name: 'Unlock SSH profiles' })).toBeVisible()
  await page.getByLabel('Local access token').fill(TOKEN)
  await expect(page.getByLabel('Encryption key')).toHaveCount(0)
  await page.getByRole('button', { name: 'Unlock profiles' }).click()
  await expect(page.getByRole('heading', { name: 'SSH Profiles' })).toBeVisible()
}

async function createProfile(
  page: Page,
  values: { name: string; host: string; user: string; password: string },
): Promise<void> {
  await page.getByRole('button', { name: 'New profile' }).click()
  const dialog = page.getByRole('dialog', { name: 'New SSH profile' })
  await expect(dialog).toBeVisible()
  await dialog.getByLabel('Name').fill(values.name)
  await dialog.getByLabel('Host').fill(values.host)
  await dialog.getByLabel('User').fill(values.user)
  await dialog.getByLabel('Password').fill(values.password)
  await dialog.getByRole('button', { name: 'Save' }).click()
  const prompt = page.getByRole('dialog', { name: 'Encryption key required' })
  await expect(prompt).toBeVisible()
  await prompt.getByRole('textbox', { name: 'Encryption key (required)' }).fill(KEY)
  await prompt.getByRole('button', { name: 'Unlock' }).click()
  await expect(dialog).toBeHidden()
}

test('local sidecar: connect, manage SSH profiles and secrets', async ({ page }) => {
  await connectLocal(page)

  // Login does not ask for a key; the first encrypted save initializes it.
  await createProfile(page, {
    name: 'Production',
    host: 'prod.example.com',
    user: 'root',
    password: 's3cret',
  })
  await expect(page.locator('tbody')).toContainText('Production')
  await expect(page.locator('tbody')).toContainText('root@prod.example.com:22')

  // View and decrypt the secrets (the key from the encrypted save is reused).
  await page.locator('tbody tr').first().getByRole('button', { name: 'View' }).click()
  const viewDialog = page.getByRole('dialog', { name: 'Production' })
  await expect(viewDialog).toBeVisible()
  await expect(viewDialog).toContainText('prod.example.com')
  await viewDialog.getByRole('button', { name: 'Decrypt secrets' }).click()
  await expect(viewDialog.getByText('s3cret')).toBeVisible()
  await viewDialog.getByRole('button', { name: 'Close', exact: true }).click()

  // Forget the key, then edit — the key is now demanded at save time.
  await page.getByRole('link', { name: 'Session' }).click()
  await page.getByRole('button', { name: 'Forget key' }).click()
  await page.getByRole('link', { name: 'Profiles' }).click()
  await page.locator('tbody tr').first().getByRole('button', { name: 'Edit' }).click()
  const editDialog = page.getByRole('dialog', { name: /Edit profile/ })
  await editDialog.getByLabel('Host').fill('prod2.example.com')
  await editDialog.getByRole('button', { name: 'Save' }).click()

  const prompt = page.getByRole('dialog', { name: 'Encryption key required' })
  await expect(prompt).toBeVisible()
  await prompt.getByRole('textbox', { name: 'Encryption key (required)' }).fill(KEY)
  await prompt.getByRole('button', { name: 'Unlock' }).click()
  await expect(page.locator('tbody')).toContainText('prod2.example.com')

  // Delete the profile.
  await page.locator('tbody tr').first().getByRole('button', { name: 'Delete' }).click()
  await expect(page.getByRole('dialog', { name: 'Delete profile' })).toBeVisible()
  await page
    .getByRole('dialog', { name: 'Delete profile' })
    .getByRole('button', { name: 'Delete', exact: true })
    .click()
  await expect(page.getByRole('dialog', { name: 'Delete profile' })).toBeHidden()
  await expect(page.getByText('No SSH profiles')).toBeVisible()
})
