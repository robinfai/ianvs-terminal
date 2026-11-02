import type { Price } from './types'
// Official pricing verified 2026-11-02; quota presets, not account availability.
export const modelPresets = [
  { provider: 'deepseek', id: 'deepseek-flash', input: 0.30, cached: 0.006, output: 1.20 },
  { provider: 'deepseek', id: 'deepseek-v4-pro', input: 1.32, cached: 0.044, output: 3.96 },
  { provider: 'openai', id: 'gpt-6.1-sol', input: 2, cached: 0.10, output: 10 },
  { provider: 'openai', id: 'gpt-6.1-terra', input: 1, cached: 0.05, output: 5 },
  { provider: 'openai', id: 'gpt-6-luna', input: 0.10, cached: 0.01, output: 0.50 },
  { provider: 'openai', id: 'gpt-6-astra', input: 10, cached: 1, output: 50 },
] as const
export function presetPrice(provider: string, id: string): Price | undefined {
  const p = modelPresets.find(p => p.provider === provider && p.id === id)
  if (!p) return undefined
  return { version: `${provider}-2026-11-02-${provider === 'deepseek' ? 'peak' : 'standard-short'}`, input_nano_usd_per_token: Math.round(p.input * 1000), cached_input_nano_usd_per_token: Math.round(p.cached * 1000), output_nano_usd_per_token: Math.round(p.output * 1000) }
}
export function priceMultipliers(p: Price) {
  const input = p.input_nano_usd_per_token
  return { model: input / 2000, output: input > 0 ? p.output_nano_usd_per_token / input : null, cached: input > 0 ? p.cached_input_nano_usd_per_token / input : null }
}
