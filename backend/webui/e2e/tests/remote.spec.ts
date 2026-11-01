import { test, expect, type Page } from '@playwright/test'
import { requireEnv } from './env'

const REMOTE_URL = requireEnv('WEBUI_REMOTE_URL')
const USERNAME = 'alice'
const PASSWORD = 'supersecret-password'
const KEY = '0123456789abcdef'

async function openRemoteConnect(page: Page): Promise<void> {
  await page.goto(REMOTE_URL)
  await expect(page.getByRole('heading', { name: '登录 Ianvs' })).toBeVisible()
  await expect(page.getByRole('tab', { name: '登录' })).toBeVisible()
}

async function signIn(page: Page): Promise<void> {
  await openRemoteConnect(page)
  await page.getByRole('tab', { name: '登录' }).click()
  await page.getByLabel('用户名').fill(USERNAME)
  await page.getByLabel('密码').fill(PASSWORD)
  await expect(page.getByLabel('数据密钥')).toHaveCount(0)
  await page.getByRole('button', { name: '登录账户' }).click()
  await expect(page.getByRole('heading', { name: '配置有序，连接安心' })).toBeVisible()
  await page.getByRole('link', { name: 'SSH 配置', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'SSH 配置' })).toBeVisible()
}

test('remote: sign in without a key and request it only for sensitive operations', async ({ page }) => {
  await openRemoteConnect(page)

  // Registration authenticates the account only; it never asks for a data key.
  await page.getByRole('tab', { name: '注册账户' }).click()
  await page.getByLabel('用户名').fill(USERNAME)
  await page.getByLabel('密码').fill(PASSWORD)
  await expect(page.getByLabel('数据密钥')).toHaveCount(0)
  await page.getByRole('button', { name: '创建账户并登录' }).click()
  await expect(page.getByRole('heading', { name: '配置有序，连接安心' })).toBeVisible()
  await page.getByRole('link', { name: 'SSH 配置', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'SSH 配置' })).toBeVisible()

  // Create an SSH profile with an encrypted password.
  await page.getByRole('button', { name: '新建配置' }).click()
  const createDialog = page.getByRole('dialog', { name: '新建 SSH 配置' })
  await createDialog.getByLabel('名称').fill('Staging')
  await createDialog.getByLabel('主机地址').fill('staging.example.com')
  await createDialog.getByLabel('SSH 用户名').fill('deploy')
  await createDialog.getByLabel('端口').fill('2200')
  await createDialog.getByLabel('密码').fill('s3cret')
  await createDialog.getByRole('button', { name: '保存' }).click()
  const encryptPrompt = page.getByRole('dialog', { name: '提供数据密钥' })
  await expect(encryptPrompt).toBeVisible()
  await encryptPrompt.getByLabel(/^数据密钥/).fill(KEY)
  await encryptPrompt.getByRole('button', { name: '继续本地操作' }).click()
  await expect(createDialog).toBeHidden()
  await expect(page.locator('tbody')).toContainText('deploy@staging.example.com:2200')

  // Sign out, then prove authentication succeeds without an encryption key.
  await page.getByRole('link', { name: '安全与会话' }).click()
  await page.getByRole('button', { name: '退出当前账户', exact: true }).click()
  await page.getByRole('dialog', { name: '确认退出当前会话？' }).getByRole('button', { name: '确认退出', exact: true }).click()
  await signIn(page)

  // Decryption is the point where a key is requested and verified.
  await page.locator('tbody tr').first().getByRole('button', { name: '查看' }).click()
  const viewDialog = page.getByRole('dialog', { name: 'Staging' })
  await viewDialog.getByRole('button', { name: '解密敏感字段' }).click()
  const decryptPrompt = page.getByRole('dialog', { name: '提供数据密钥' })
  await decryptPrompt
    .getByLabel(/^数据密钥/)
    .fill('incorrect-encryption-key')
  await decryptPrompt.getByRole('button', { name: '继续本地操作' }).click()
  await expect(viewDialog.getByRole('alert')).toContainText('密钥')
  await viewDialog.getByRole('button', { name: '解密敏感字段' }).click()
  const retryPrompt = page.getByRole('dialog', { name: '提供数据密钥' })
  await retryPrompt.getByLabel(/^数据密钥/).fill(KEY)
  await retryPrompt.getByRole('button', { name: '继续本地操作' }).click()
  await expect(viewDialog.getByText('s3cret')).toBeVisible()
  await viewDialog.getByRole('button', { name: '关闭', exact: true }).click()

  // The stored key is reused; saving an edit does not prompt again.
  await page.locator('tbody tr').first().getByRole('button', { name: '编辑' }).click()
  const editDialog = page.getByRole('dialog', { name: /编辑配置/ })
  await editDialog.getByLabel('主机地址').fill('staging2.example.com')
  await editDialog.getByRole('button', { name: '保存' }).click()
  await expect(page.locator('tbody')).toContainText('deploy@staging2.example.com:2200')

  // Profiles persist across another keyless sign-in.
  await page.getByRole('link', { name: '安全与会话' }).click()
  await page.getByRole('button', { name: '退出当前账户', exact: true }).click()
  await page.getByRole('dialog', { name: '确认退出当前会话？' }).getByRole('button', { name: '确认退出', exact: true }).click()
  await signIn(page)
  await expect(page.locator('tbody')).toContainText('deploy@staging2.example.com:2200')
})
