import test from 'node:test'
import assert from 'node:assert/strict'
import { deviceIdentity } from '../src/state/deviceIdentity.ts'

test('browser installation identity survives logout and is shared by tabs', () => {
  const values = new Map<string, string>()
  Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  } })
  const first = deviceIdentity()
  assert.match(first, /^[a-f0-9-]{36}$/)
  values.set('ianvs.token', 'session-one')
  values.delete('ianvs.token')
  assert.equal(deviceIdentity(), first)
  values.clear()
  assert.notEqual(deviceIdentity(), first)
})
