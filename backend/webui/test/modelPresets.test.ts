import test from 'node:test'
import assert from 'node:assert/strict'
import { modelPresets, presetPrice, priceMultipliers } from '../src/features/admin/modelPresets.ts'

test('every selectable model has a positive price and correct quota conversion', () => {
  for (const p of modelPresets) {
    const price = presetPrice(p.provider, p.id)!
    assert.ok(price.input_nano_usd_per_token > 0)
    assert.equal(price.output_nano_usd_per_token, Math.round(p.output * 1000))
    assert.equal(priceMultipliers(price).model, p.input / 2)
  }
  assert.deepEqual(priceMultipliers(presetPrice('deepseek', 'deepseek-flash')!), { model: 0.15, output: 4, cached: 0.02 })
  assert.deepEqual(priceMultipliers(presetPrice('openai', 'gpt-6.1-sol')!), { model: 1, output: 5, cached: 0.05 })
})
test('provider mismatch or unknown model never inherits a different model price', () => {
  assert.equal(presetPrice('openai', 'deepseek-flash'), undefined)
  assert.equal(presetPrice('deepseek', 'unknown'), undefined)
})
