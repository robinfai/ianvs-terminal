import { test, expect, type Page } from '@playwright/test'
import { mkdir } from 'node:fs/promises'
import path from 'node:path'

const captureDir = process.env.UI_CAPTURE_DIR
async function capture(page: Page, name: string) {
  if (captureDir) { await expect(page.locator('[aria-busy="true"]')).toHaveCount(0); await mkdir(captureDir, { recursive: true }); await page.screenshot({ path: path.join(captureDir, `${name}.png`), fullPage: true }) }
}
async function fixture(page: Page, options: { capacity?: boolean; failRevoke?: boolean; failSnapshot?: boolean; failLogin?: boolean } = {}) {
  const requests: { method: string; path: string; body: string | null }[] = []
  let sessions = [
    { id: 'current', device_name: '此浏览器', created_at: '2026-10-30T09:00:00Z', expires_at: '2026-11-02T09:00:00Z', current: true },
    { id: 'other', device_name: '测试工作电脑', created_at: '2026-10-29T09:00:00Z', expires_at: '2026-11-02T09:00:00Z', current: false },
    { id: 'third', device_name: '测试平板', created_at: '2026-10-28T09:00:00Z', expires_at: '2026-11-02T09:00:00Z', current: false },
  ]
  let resource: Record<string, unknown> | null = null
  await page.route('**/*', async route => {
    const request = route.request(), url = new URL(request.url()), p = url.pathname
    if (!p.startsWith('/v1/') && p !== '/healthz') return route.continue()
    requests.push({ method: request.method(), path: p, body: request.postData() })
    const reply = (data: unknown, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(data) })
    if (p === '/healthz') return reply({ status: 'ok', mode: 'remote', server_id: 'isolated-ui-fixture', time: '2026-10-31T09:00:00Z' })
    if (p === '/v1/me') return reply({ user: { id: 'fixture-user', username: 'demo' } })
    if (p.endsWith('/begin')) {
      const body = request.postDataJSON()
      if (options.failLogin) return reply({ error: { code: 'invalid_credentials', message: 'Invalid credentials' } }, 401)
      if (options.capacity && !body.replace_oldest) return reply({ error: { code: 'auth_session_capacity', message: 'Full' } }, 409)
      return reply({ operation_id: 'fixture-operation', kind: 'login', expires_at: '2026-11-02T09:00:00Z' })
    }
    if (p.endsWith('/complete')) return reply({ token: 'fixture-session-not-a-real-token', user: { id: 'fixture-user', username: 'demo' }, expires_at: '2026-11-02T09:00:00Z' })
    if (p === '/v1/auth/sessions') return reply({ sessions })
    if (p.startsWith('/v1/auth/sessions/')) {
      if (options.failRevoke && p.endsWith('/third')) return reply({ error: { code: 'unavailable', message: 'Fixture failure' } }, 503)
      sessions = sessions.filter(s => !p.endsWith('/' + s.id))
      return route.fulfill({ status: 204 })
    }
    if (p === '/v1/auth/logout' || p === '/v1/auth/cancel-operation') return route.fulfill({ status: 204 })
    if (p.startsWith('/v1/resources/')) {
      if (options.failSnapshot) return reply({ error: { code: 'unavailable', message: 'Fixture failure' } }, 503)
      if (request.method() === 'PUT') {
        const body = request.postDataJSON()
        resource = { ...body, id: 'default', kind: 'profile', revision: Number(resource?.revision ?? 0) + 1, has_sensitive: !!body.sensitive, updated_at: '2026-10-31T09:00:00Z' }
        return reply(resource)
      }
      if (resource && p === '/v1/resources/profile/default') {
        const result = { ...resource }
        if (url.searchParams.get('include_sensitive') !== 'true') delete result.sensitive
        return reply(result)
      }
      return reply({ error: { code: 'not_found', message: 'No document' } }, 404)
    }
    return reply({ error: { code: 'unexpected_test_request', message: p } }, 500)
  })
  return { requests }
}
async function login(page: Page) {
  await page.goto('/')
  await page.getByLabel('用户名').fill('demo')
  await page.getByLabel('密码').fill('fixture-password-only')
  await page.getByRole('button', { name: '登录账户', exact: true }).click()
  await expect(page.getByRole('heading', { name: '配置有序，连接安心' })).toBeVisible()
}

for (const theme of ['light', 'dark']) {
  test(`${theme}: real browser navigation, guide, demo boundary and responsive capture (mock API)`, async ({ page }) => {
    const { requests } = await fixture(page)
    const errors: string[] = []
    page.on('pageerror', e => errors.push(e.message))
    await page.setViewportSize({ width: 1440, height: 1024 })
    await page.goto('/')
    await page.getByLabel('选择外观主题').selectOption(theme)
    await expect(page.locator('html')).toHaveAttribute('data-theme', theme)
    await capture(page, `${theme}-login-desktop`)
    await page.reload()
    await expect(page.getByLabel('选择外观主题')).toHaveValue(theme)
    await login(page)
    await expect(page.getByText('尚无文档', { exact: true })).toHaveCount(3)
    await capture(page, `${theme}-overview-desktop`)
    await page.getByRole('link', { name: '同步与换机', exact: true }).click()
    await capture(page, `${theme}-sync-panel-desktop`)
    await page.getByRole('button', { name: '打开换机与恢复指引' }).click()
    await page.getByRole('button', { name: '账户正确，继续' }).click()
    await page.getByRole('button', { name: '没有旧设备或备份' }).click()
    await expect(page.getByText(/无法恢复原主密钥时/)).toBeVisible()
    await capture(page, `${theme}-guide-desktop`)
    await page.getByRole('link', { name: '管理预览（未接入）' }).click()
    await expect(page.getByText(/此页面不授予管理员权限/)).toBeVisible()
    await page.getByRole('button', { name: '载入独立演示数据' }).click()
    await page.getByRole('button', { name: '用户', exact: true }).click()
    await page.getByLabel('筛选示例用户名').fill('lin')
    await page.getByRole('button', { name: '查看示例用户 lin' }).click()
    await capture(page, `${theme}-admin-desktop`)
    await page.getByRole('button', { name: '查看禁用确认示例' }).click()
    await expect(page.getByRole('button', { name: '未接入管理服务，无法禁用' })).toBeDisabled()
    await capture(page, `${theme}-admin-confirm-desktop`)
    await page.keyboard.press('Escape')
    await page.getByRole('link', { name: '安全与会话', exact: true }).click()
    await page.getByRole('button', { name: '撤销此会话' }).first().click()
    await capture(page, `${theme}-revoke-confirm-desktop`)
    await page.setViewportSize({ width: 390, height: 844 })
    await capture(page, `${theme}-revoke-confirm-mobile`)
    await page.getByRole('button', { name: '取消', exact: true }).click()
    await capture(page, `${theme}-sessions-mobile`)
    await page.getByRole('link', { name: '同步与换机', exact: true }).click()
    await capture(page, `${theme}-sync-mobile`)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBeTruthy()
    await page.getByRole('link', { name: '管理预览（未接入）' }).click()
    await capture(page, `${theme}-admin-mobile`)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBeTruthy()
    expect(requests.some(r => r.path.includes('/admin') || r.path.includes('/users'))).toBeFalsy()
    expect(errors).toEqual([])
  })
}

test('capacity replacement requires explicit confirmation and a new authenticated begin', async ({ page }) => {
  const { requests } = await fixture(page, { capacity: true })
  await page.goto('/')
  await page.getByLabel('用户名').fill('demo')
  await page.getByLabel('密码').fill('fixture-password-only')
  await page.getByRole('button', { name: '登录账户', exact: true }).click()
  await page.getByRole('button', { name: '处理已满的登录名额' }).click()
  await page.getByRole('button', { name: '取消', exact: true }).click()
  expect(requests.filter(r => r.body?.includes('"replace_oldest":true'))).toHaveLength(0)
  await page.getByRole('button', { name: '处理已满的登录名额' }).click()
  await page.getByRole('button', { name: '退出最早会话并登录', exact: true }).click()
  await expect(page.getByRole('heading', { name: '配置有序，连接安心' })).toBeVisible()
  expect(requests.filter(r => r.body?.includes('"replace_oldest":true'))).toHaveLength(1)
})

test('failed sign-in stays signed out, recovery has no fake submission', async ({ page }) => {
  const { requests } = await fixture(page, { failLogin: true })
  await page.goto('/')
  await page.getByLabel('用户名').fill('demo')
  await page.getByLabel('密码').fill('wrong-password')
  await page.getByRole('button', { name: '登录账户', exact: true }).click()
  await expect(page.getByRole('alert')).toContainText('用户名或密码不正确')
  await page.getByRole('button', { name: '忘记密码或无法登录？' }).click()
  await expect(page.getByRole('dialog')).toContainText('尚未接入')
  expect(requests.some(r => /reset|recover/.test(r.path))).toBeFalsy()
  await page.setViewportSize({ width: 390, height: 844 })
  await capture(page, 'recovery-mobile')
})

test('partial revocation reports confirmed successes and does not claim all sessions revoked', async ({ page }) => {
  await fixture(page, { failRevoke: true })
  await login(page)
  await page.getByRole('link', { name: '安全与会话', exact: true }).click()
  await page.getByRole('button', { name: '退出其他会话' }).click()
  await page.getByRole('button', { name: '确认撤销', exact: true }).click()
  await expect(page.getByText(/已确认撤销 1 \/ 2 个会话/)).toBeVisible()
  await expect(page.getByText('测试平板', { exact: true })).toBeVisible()
  await expect(page.getByText('测试工作电脑', { exact: true })).toHaveCount(0)
})

test('server failures are errors, not empty or synced success', async ({ page }) => {
  await fixture(page, { failSnapshot: true })
  await login(page)
  await expect(page.getByText('无法获取服务器状态，请重试。', { exact: true })).toHaveCount(3)
  await expect(page.getByText('尚无文档', { exact: true })).toHaveCount(0)
  await expect(page.getByText('服务器已保存', { exact: true })).toHaveCount(0)
})

test('SSH secret is encrypted before PUT; key is not sent or persisted', async ({ page }) => {
  const { requests } = await fixture(page)
  await login(page)
  await page.getByRole('link', { name: 'SSH 配置', exact: true }).click()
  await page.getByRole('button', { name: '新建配置', exact: true }).click()
  await page.getByLabel('名称').fill('Fixture SSH')
  await page.getByLabel('主机地址').fill('ssh.example.test')
  await page.getByLabel('SSH 用户名').fill('fixture')
  await page.getByLabel('认证方式').selectOption('password')
  await page.getByLabel('密码').fill('fixture-ssh-secret')
  await page.getByRole('button', { name: '保存', exact: true }).click()
  await page.getByRole('textbox', { name: /^数据密钥/ }).fill('fixture-master-key')
  await page.getByRole('button', { name: '继续本地操作', exact: true }).click()
  await expect(page.getByText('Fixture SSH', { exact: true })).toBeVisible()
  const writes = requests.filter(r => r.method === 'PUT')
  expect(writes).toHaveLength(1)
  expect(writes[0].body).toContain('aes-256-gcm')
  expect(JSON.stringify(requests)).not.toContain('fixture-master-key')
  expect(writes[0].body).not.toContain('fixture-ssh-secret')
  expect(await page.evaluate(() => JSON.stringify({ ...localStorage, ...sessionStorage }))).not.toContain('fixture-master-key')
})

test('system theme follows OS changes until explicitly overridden', async ({ page }) => {
  await fixture(page)
  await page.emulateMedia({ colorScheme: 'light' }); await page.goto('/')
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light')
  await page.emulateMedia({ colorScheme: 'dark' })
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
  await page.getByLabel('选择外观主题').selectOption('light')
  await page.emulateMedia({ colorScheme: 'dark' })
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light')
  await page.setViewportSize({ width: 390, height: 844 })
  await capture(page, 'light-login-mobile')
  await page.getByLabel('选择外观主题').selectOption('dark')
  await capture(page, 'dark-login-mobile')
})


test('keyboard account tabs and skip link preserve the active page', async ({ page }) => {
  await fixture(page)
  await page.goto('/')
  await page.getByRole('tab', { name: '登录', exact: true }).focus()
  await page.keyboard.press('ArrowRight')
  await expect(page.getByRole('tab', { name: '注册账户', exact: true })).toBeFocused()
  await expect(page.getByRole('tabpanel', { name: '注册账户' })).toBeVisible()
  await page.keyboard.press('Home')
  await expect(page.getByRole('tab', { name: '登录', exact: true })).toBeFocused()
  await login(page)
  await page.getByRole('link', { name: '同步与换机', exact: true }).click()
  await expect(page.getByRole('heading', { name: '掌握你的同步状态' })).toBeVisible()
  await page.getByRole('link', { name: '跳转到主内容' }).focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('heading', { name: '掌握你的同步状态' })).toBeVisible()
  await expect(page.locator('#main-content')).toBeFocused()
  await expect(page).toHaveURL(/#\/sync$/)
  await page.reload()
  await expect(page.getByRole('heading', { name: '掌握你的同步状态' })).toBeVisible()
})
