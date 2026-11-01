import { test, expect, type Page } from '@playwright/test'
import { requireEnv } from './env'

const LOCAL_URL = requireEnv('WEBUI_LOCAL_URL')
const TOKEN = requireEnv('WEBUI_LOCAL_TOKEN')
const KEY = '0123456789abcdef' // 16 bytes — the minimum valid data key.
const PRIVATE_KEY =
  '-----BEGIN OPENSSH PRIVATE KEY-----\n' +
  'b3BlbnNzaC1rZXktdjEAAAAA\n' +
  '-----END OPENSSH PRIVATE KEY-----'

async function connectLocal(page: Page): Promise<void> {
  await page.goto(LOCAL_URL)
  await expect(page.getByRole('heading', { name: '登录 Ianvs' })).toBeVisible()
  await page.getByLabel('本地访问令牌').fill(TOKEN)
  await expect(page.getByLabel('数据密钥')).toHaveCount(0)
  await page.getByRole('button', { name: '连接本地服务' }).click()
  await expect(page.getByRole('heading', { name: '配置有序，连接安心' })).toBeVisible()
  await page.getByRole('link', { name: 'SSH 配置', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'SSH 配置' })).toBeVisible()
}

async function createProfile(
  page: Page,
  values: { name: string; host: string; user: string; password: string },
): Promise<void> {
  await page.getByRole('button', { name: '新建配置' }).click()
  const dialog = page.getByRole('dialog', { name: '新建 SSH 配置' })
  await expect(dialog).toBeVisible()
  await dialog.getByLabel('名称').fill(values.name)
  await dialog.getByLabel('主机地址').fill(values.host)
  await dialog.getByLabel('SSH 用户名').fill(values.user)
  await dialog.getByLabel('私钥文件').setInputFiles({
    name: 'id_ed25519',
    mimeType: 'application/octet-stream',
    buffer: Buffer.from(PRIVATE_KEY),
  })
  await expect(dialog).toContainText('已选择：id_ed25519')
  await dialog.getByLabel('密码').fill(values.password)
  await dialog.getByRole('button', { name: '保存' }).click()
  const prompt = page.getByRole('dialog', { name: '提供数据密钥' })
  await expect(prompt).toBeVisible()
  await prompt.getByLabel(/^数据密钥/).fill(KEY)
  await prompt.getByRole('button', { name: '继续本地操作' }).click()
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
  await page.locator('tbody tr').first().getByRole('button', { name: '查看' }).click()
  const viewDialog = page.getByRole('dialog', { name: 'Production' })
  await expect(viewDialog).toBeVisible()
  await expect(viewDialog).toContainText('prod.example.com')
  await viewDialog.getByRole('button', { name: '解密敏感字段' }).click()
  await expect(viewDialog.getByText('s3cret')).toBeVisible()
  await expect(viewDialog.getByText('已保存 1 个私钥')).toBeVisible()
  await expect(viewDialog).not.toContainText('BEGIN OPENSSH PRIVATE KEY')
  await viewDialog.getByRole('button', { name: '关闭', exact: true }).click()

  // Forget the key, then edit — the key is now demanded at save time.
  await page.getByRole('link', { name: '安全与会话' }).click()
  await page.getByRole('button', { name: '忘记此页密钥' }).click()
  await page.getByRole('link', { name: 'SSH 配置' }).click()
  await page.locator('tbody tr').first().getByRole('button', { name: '编辑' }).click()
  const editDialog = page.getByRole('dialog', { name: /编辑配置/ })
  await editDialog.getByLabel('主机地址').fill('prod2.example.com')
  await editDialog.getByRole('button', { name: '保存' }).click()

  const prompt = page.getByRole('dialog', { name: '提供数据密钥' })
  await expect(prompt).toBeVisible()
  await prompt.getByLabel(/^数据密钥/).fill(KEY)
  await prompt.getByRole('button', { name: '继续本地操作' }).click()
  await expect(page.locator('tbody')).toContainText('prod2.example.com')

  // Editing public fields preserves the encrypted private-key contents.
  await page.locator('tbody tr').first().getByRole('button', { name: '查看' }).click()
  const updatedViewDialog = page.getByRole('dialog', { name: 'Production' })
  await updatedViewDialog.getByRole('button', { name: '解密敏感字段' }).click()
  await expect(updatedViewDialog.getByText('已保存 1 个私钥')).toBeVisible()
  await expect(updatedViewDialog).not.toContainText('BEGIN OPENSSH PRIVATE KEY')
  await updatedViewDialog.getByRole('button', { name: '关闭', exact: true }).click()

  // Delete the profile.
  await page.locator('tbody tr').first().getByRole('button', { name: '删除' }).click()
  await expect(page.getByRole('dialog', { name: '删除配置' })).toBeVisible()
  await page
    .getByRole('dialog', { name: '删除配置' })
    .getByRole('button', { name: '删除', exact: true })
    .click()
  await expect(page.getByRole('dialog', { name: '删除配置' })).toBeHidden()
  await expect(page.getByText('还没有 SSH 配置')).toBeVisible()
})
