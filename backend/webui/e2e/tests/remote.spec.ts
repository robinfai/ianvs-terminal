import { test, expect, type Page } from '@playwright/test'
import { requireEnv } from './env'

const REMOTE_URL = requireEnv('WEBUI_REMOTE_URL')
const USERNAME = 'alice'
const PASSWORD = 'supersecret-password'
const KEY = '0123456789abcdef'

async function openRemoteConnect(page: Page): Promise<void> {
  await page.goto(REMOTE_URL)
  await expect(page.getByRole('heading', { name: 'Unlock SSH profiles' })).toBeVisible()
  await expect(page.getByRole('tab', { name: 'Sign in' })).toBeVisible()
}

async function signIn(page: Page): Promise<void> {
  await openRemoteConnect(page)
  await page.getByRole('tab', { name: 'Sign in' }).click()
  await page.getByLabel('Username').fill(USERNAME)
  await page.getByLabel('Password').fill(PASSWORD)
  await expect(page.getByLabel('Encryption key')).toHaveCount(0)
  await page.getByRole('button', { name: 'Unlock profiles' }).click()
  await expect(page.getByRole('heading', { name: 'SSH Profiles' })).toBeVisible()
}

test('remote: sign in without a key and request it only for sensitive operations', async ({ page }) => {
  await openRemoteConnect(page)

  // Registration authenticates the account only; it never asks for a data key.
  await page.getByRole('tab', { name: 'Create account' }).click()
  await page.getByLabel('Username').fill(USERNAME)
  await page.getByLabel('Password').fill(PASSWORD)
  await expect(page.getByLabel('Encryption key')).toHaveCount(0)
  await page.getByRole('button', { name: 'Create and unlock' }).click()
  await expect(page.getByRole('heading', { name: 'SSH Profiles' })).toBeVisible()

  // Create an SSH profile with an encrypted password.
  await page.getByRole('button', { name: 'New profile' }).click()
  const createDialog = page.getByRole('dialog', { name: 'New SSH profile' })
  await createDialog.getByLabel('Name').fill('Staging')
  await createDialog.getByLabel('Host').fill('staging.example.com')
  await createDialog.getByLabel('User').fill('deploy')
  await createDialog.getByLabel('Port').fill('2200')
  await createDialog.getByLabel('Password').fill('s3cret')
  await createDialog.getByRole('button', { name: 'Save' }).click()
  const encryptPrompt = page.getByRole('dialog', { name: 'Encryption key required' })
  await expect(encryptPrompt).toBeVisible()
  await encryptPrompt.getByRole('textbox', { name: 'Encryption key (required)' }).fill(KEY)
  await encryptPrompt.getByRole('button', { name: 'Unlock' }).click()
  await expect(createDialog).toBeHidden()
  await expect(page.locator('tbody')).toContainText('deploy@staging.example.com:2200')

  // Sign out, then prove authentication succeeds without an encryption key.
  await page.getByRole('link', { name: 'Session' }).click()
  await page.getByRole('button', { name: 'Sign out' }).click()
  await signIn(page)

  // Decryption is the point where a key is requested and verified.
  await page.locator('tbody tr').first().getByRole('button', { name: 'View' }).click()
  const viewDialog = page.getByRole('dialog', { name: 'Staging' })
  await viewDialog.getByRole('button', { name: 'Decrypt secrets' }).click()
  const decryptPrompt = page.getByRole('dialog', { name: 'Encryption key required' })
  await decryptPrompt
    .getByRole('textbox', { name: 'Encryption key (required)' })
    .fill('incorrect-encryption-key')
  await decryptPrompt.getByRole('button', { name: 'Unlock' }).click()
  await expect(page.getByRole('alert')).toContainText('invalid')
  await viewDialog.getByRole('button', { name: 'Decrypt secrets' }).click()
  const retryPrompt = page.getByRole('dialog', { name: 'Encryption key required' })
  await retryPrompt.getByRole('textbox', { name: 'Encryption key (required)' }).fill(KEY)
  await retryPrompt.getByRole('button', { name: 'Unlock' }).click()
  await expect(viewDialog.getByText('s3cret')).toBeVisible()
  await viewDialog.getByRole('button', { name: 'Close', exact: true }).click()

  // The stored key is reused; saving an edit does not prompt again.
  await page.locator('tbody tr').first().getByRole('button', { name: 'Edit' }).click()
  const editDialog = page.getByRole('dialog', { name: /Edit profile/ })
  await editDialog.getByLabel('Host').fill('staging2.example.com')
  await editDialog.getByRole('button', { name: 'Save' }).click()
  await expect(page.locator('tbody')).toContainText('deploy@staging2.example.com:2200')

  // Profiles persist across another keyless sign-in.
  await page.getByRole('link', { name: 'Session' }).click()
  await page.getByRole('button', { name: 'Sign out' }).click()
  await signIn(page)
  await expect(page.locator('tbody')).toContainText('deploy@staging2.example.com:2200')
})
