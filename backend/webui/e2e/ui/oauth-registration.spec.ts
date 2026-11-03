import { test, expect } from '@playwright/test'

for (const allowed of [true, false]) {
  test(`OAuth registration capability ${allowed}`, async ({page}) => {
    const actions: string[] = []
    await page.addInitScript(() => {
      let state = ''
      window.AppleID = { auth: {
        init(options) { state = options.state },
        async signIn() { return {authorization: {id_token:'fixture-identity', state}} },
      } }
    })
    await page.route('**/healthz', route => route.fulfill({json: {
      status:'ok',mode:'remote',server_id:'fixture',time:new Date().toISOString(),
      allow_registration:allowed,password_auth_enabled:false,
      apple_web:{client_id:'fixture.apple',redirect_uri:'http://127.0.0.1:4174/'},
    }}))
    await page.route('**/v1/**', async route => {
      const p = new URL(route.request().url()).pathname
      if (p === '/v1/auth/oauth/challenge') return route.fulfill({json:{nonce:'a'.repeat(43)}})
      if (p === '/v1/auth/oauth/begin') {
        const action = route.request().postDataJSON().action
        actions.push(action)
        return route.fulfill({status:409,json:{error:{code: action ? 'apple_registration_disabled' : 'oauth_account_choice_required',message:'fixture'}}})
      }
      return route.fulfill({status:401,json:{error:{code:'unauthorized',message:'fixture'}}})
    })
    await page.goto('/')
    await page.getByRole('button',{name:'使用 Apple 登录',exact:true}).click()
    await expect(page.getByRole('heading',{name:'首次登录'})).toBeVisible()
    await expect(page.getByRole('button',{name:'关联已有账号',exact:true})).toBeVisible()
    await page.screenshot({path:test.info().outputPath('first-sign-in.png'),fullPage:true})
    const create = page.getByRole('button',{name:'创建新账号',exact:true})
    if (allowed) {
      await expect(create).toHaveClass(/primary/)
      await create.click()
      await expect(create).toHaveCount(0)
      expect(actions).toEqual(['','create'])
    } else {
      await expect(create).toHaveCount(0)
      expect(actions).toEqual([''])
    }
    await expect(page.getByText('此服务暂不开放新账号注册，请关联已有账号。')).toBeVisible()
    await page.getByRole('button',{name:'关联已有账号',exact:true}).click()
    await expect(page.getByRole('button',{name:'使用账号密码关联',exact:true})).toBeVisible()
  })
}
