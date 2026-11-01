import { test } from 'node:test'
import assert from 'node:assert/strict'
import { checkedAppleToken } from '../src/lib/appleSignIn.ts'

test('Apple response must match this browser login attempt before sending its token', () => {
 assert.equal(checkedAppleToken({ authorization: { state: 'expected', id_token: 'signed-by-apple' } }, 'expected'), 'signed-by-apple')
 assert.throws(() => checkedAppleToken({ authorization: { state: 'other', id_token: 'token' } }, 'expected'))
 assert.throws(() => checkedAppleToken({ authorization: { state: '', id_token: 'token' } }, ''))
 assert.throws(() => checkedAppleToken({ authorization: { state: 'expected', id_token: '' } }, 'expected'))
})
